function receipt=collectGrantCalibrationEpisodes(cfg,plan,folder,options)
%COLLECTGRANTCALIBRATIONEPISODES Resumable, sealed frozen-grant raw collection.
% No curve, effective-SINR fit or qualification is manufactured here. Plan
% entries contain EpisodeID, Role (fit/validation), Grants, SNRdB and Seeds.
arguments
    cfg (1,1) struct
    plan (1,:) struct
    folder (1,1) string
    options.MaximumNewEpisodes (1,1) double {mustBeInteger,mustBeNonnegative}=1
    options.EvidenceStorage (1,1) string {mustBeMember(options.EvidenceStorage, ...
        ["raw","lossless_path_gains_xor_v1","lossless_path_gains_xor_dedup_v1"])}="raw"
end
invocationClock=tic;
assert(~isempty(plan) && all(isfield(plan,{'EpisodeID','Role','Grants','SNRdB','Seeds'})), ...
    'sixgr:calibration:GrantCollectionPlan','Require identifiable fit/validation episode plans.');
ids=string({plan.EpisodeID}); roles=string({plan.Role});
assert(all(strlength(strtrim(ids))>0) && numel(unique(ids))==numel(ids) && ...
    all(ismember(roles,["fit","validation"])) && all(ismember(["fit","validation"],roles)), ...
    'sixgr:calibration:GrantCollectionPlan','Plan distinct episodes in both fit and held-out roles.');
allSeeds=[]; evolutions=strings(numel(plan),1);
for k=1:numel(plan)
    s=plan(k).Seeds;
    assert(all(isfield(s,{'Bits','Noise','Channel','ControlNoise','RF'})), ...
        'sixgr:calibration:GrantCollectionSeeds','Missing independent seed components.');
    [streams,evolutions(k)]=sixgr.system.waveform.validateGrantCalibrationSeeds(s,numel(plan(k).Grants));
    allSeeds=[allSeeds;streams]; %#ok<AGROW>
end
assert(numel(unique(evolutions))==1,'sixgr:calibration:GrantCollectionEvolution', ...
    'Do not pool independent-attempt and persistent-link HARQ populations.');
assert(all(isfinite(allSeeds)) && all(allSeeds==fix(allSeeds)) && ...
    all(allSeeds>=0 & allSeeds<=2^32-1) && numel(unique(allSeeds))==numel(allSeeds), ...
    'sixgr:calibration:GrantCollectionSeeds', ...
    'Fit and validation episodes must not reuse component seed realizations.');
if ~isfolder(folder), mkdir(folder); end
assert(~isfile(fullfile(folder,'source_change_failure.json')), ...
    'sixgr:calibration:GrantSourceChanged', ...
    'This collection observed a source change during execution; retain it for diagnosis and use a new folder.');
lockPath=fullfile(folder,'.grant_collection_lock');
lock=java.io.File(char(lockPath));
assert(lock.mkdir(),'sixgr:calibration:GrantCollectionBusy', ...
    'Collection is already owned or has an unreleased lock: %s',lockPath);
unlock=onCleanup(@()rmdir(lockPath)); %#ok<NASGU> % This invocation's empty lock only.
sources=sixgr.calibration.grantSourceIdentity();
storageMode=options.EvidenceStorage;
identityValue=struct('Schema',"sixgr.grant_collection/v1", ...
    'Config',cfg,'Plan',plan,'Sources',sources);
if storageMode~="raw", identityValue.EvidenceStorage=storageMode; end
identity=localHash(identityValue);
manifestPath=fullfile(folder,'campaign.mat');
if isfile(manifestPath)
    localVerify(manifestPath);
    prior=load(manifestPath,'identity');
    assert(isfield(prior,'identity') && string(prior.identity)==identity, ...
        'sixgr:calibration:GrantCollectionIdentity', ...
        'Configuration, grant plan, seeds, software or source changed; use a new collection folder.');
else
    assert(~isfile(string(manifestPath)+".sha256.json") && ...
        ~isfolder(fullfile(folder,'episodes')), ...
        'sixgr:calibration:GrantCollectionCommit','Cannot adopt orphaned episodes or a partial manifest.');
    staging=string(tempname(folder))+".mat";
    save(staging,'cfg','plan','sources','identity','storageMode','-v7.3');
    localCommit(staging,manifestPath);
end
episodeFolder=fullfile(folder,'episodes');
if ~isfolder(episodeFolder), mkdir(episodeFolder); end
rows=struct([]); newCount=0; performance=table(); newExecutionSeconds=0;
for k=1:numel(plan)
    executionMetrics=struct();
    episodePath=fullfile(episodeFolder,localHash(ids(k))+".mat");
    if isfile(episodePath)
        localVerify(episodePath);
        retained=load(episodePath,'episodeID','role','collectionIdentity','episode');
        assert(string(retained.episodeID)==ids(k) && string(retained.role)==roles(k) && ...
            string(retained.collectionIdentity)==identity, ...
            'sixgr:calibration:GrantCollectionIdentity','Retained episode does not belong to this plan.');
        episode=sixgr.calibration.decodeGrantEpisodeStorage(retained.episode,storageMode);
        variables=whos('-file',episodePath);
        if any(strcmp({variables.name},'executionMetrics'))
            metadata=load(episodePath,'executionMetrics');
            executionMetrics=metadata.executionMetrics;
        end
    elseif newCount<options.MaximumNewEpisodes
        assert(~isfile(string(episodePath)+".sha256.json"), ...
            'sixgr:calibration:GrantCollectionCommit','Episode sidecar exists without its raw evidence.');
        startedUTC=string(datetime('now','TimeZone','UTC','Format',"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"));
        episodeClock=tic;
        episode=sixgr.system.waveform.executeGrantCalibrationEpisode( ...
            cfg,plan(k).Grants,plan(k).SNRdB,plan(k).Seeds);
        executionMetrics=struct('Schema',"sixgr.grant_episode_execution_metrics/v1", ...
            'StartedUTC',startedUTC,'ElapsedSeconds',toc(episodeClock), ...
            'Scope',"episode_executor_including_setup_and_evidence_excluding_persistence");
        newExecutionSeconds=newExecutionSeconds+executionMetrics.ElapsedSeconds;
        assert(localHash(sixgr.calibration.grantSourceIdentity())==localHash(sources), ...
            'sixgr:calibration:GrantCollectionSourceChanged', ...
            'Executable source changed during waveform collection; this attempt cannot be committed.');
        episodeID=ids(k); role=roles(k); collectionIdentity=identity; %#ok<NASGU>
        staging=string(tempname(episodeFolder))+".mat";
        episode=sixgr.calibration.encodeGrantEpisodeStorage(episode,storageMode);
        save(staging,'episode','episodeID','role','collectionIdentity','executionMetrics','-v7.3');
        % Verify restoration before committing an immutable scientific episode.
        episode=sixgr.calibration.decodeGrantEpisodeStorage(episode,storageMode);
        localCommit(staging,episodePath);
        newCount=newCount+1;
    else
        continue;
    end
    elapsed=NaN; startedUTC=""; scope="unavailable_not_retained";
    timingAvailable=~isempty(fieldnames(executionMetrics));
    if timingAvailable
        assert(all(isfield(executionMetrics,{'Schema','StartedUTC','ElapsedSeconds','Scope'})) && ...
            executionMetrics.Schema=="sixgr.grant_episode_execution_metrics/v1" && ...
            isscalar(executionMetrics.ElapsedSeconds) && isfinite(executionMetrics.ElapsedSeconds) && ...
            executionMetrics.ElapsedSeconds>=0, ...
            'sixgr:calibration:GrantExecutionMetrics','Invalid retained episode timing metadata.');
        elapsed=executionMetrics.ElapsedSeconds; startedUTC=executionMetrics.StartedUTC; scope=executionMetrics.Scope;
    end
    fileInfo=dir(episodePath);
    metric=table(ids(k),roles(k),numel(episode.Attempts),startedUTC,elapsed,timingAvailable,scope, ...
        double(fileInfo.bytes),storageMode,"episodes/"+localHash(ids(k))+".mat",false,false, ...
        'VariableNames',{'EpisodeID','Role','PhysicalAttempts','ExecutionStartedUTC','ExecutionElapsed_s', ...
        'TimingAvailable','TimingScope','StoredEpisodeBytes','EvidenceStorage','EpisodeRelativePath', ...
        'CalibrationQualified','PrimaryStudyAccepted'});
    performance=[performance;metric]; %#ok<AGROW>
    for j=1:numel(episode.Attempts)
        a=episode.Attempts(j);
        row=struct('EpisodeID',ids(k),'Role',roles(k),'Attempt',a.Attempt, ...
            'ScheduledAbsoluteSlot0',a.ScheduledAbsoluteSlot0,'RV',a.RV, ...
            'ChannelEvolution',episode.ChannelEvolution, ...
            'ChannelInitialTime_s',sixgr.util.structGet(a,'ChannelInitialTime_s',NaN), ...
            'ConfiguredSNRdB',a.ConfiguredSNRdB,'CRCError',a.CRCError, ...
            'PriorAttemptsFailed',a.PriorAttemptsFailed,'TBSBits',a.TBSBits, ...
            'TransportBlockSHA256',a.TransportBlockSHA256, ...
            'DataREAllocationSHA256',a.DataREAllocationSHA256, ...
            'CalibrationKeySHA256',a.CalibrationKeySHA256, ...
            'CalibrationBindingAvailable',a.CalibrationBindingAvailable, ...
            'EpisodeRelativePath',"episodes/"+localHash(ids(k))+".mat", ...
            'EpisodeSHA256',sixgr.csi.studyFileSHA256(episodePath), ...
            'SourceClassification',"executed_frozen_grant_waveform_episode", ...
            'WaveformExecuted',true,'CalibrationQualified',false,'PrimaryStudyAccepted',false);
        if isempty(rows), rows=row; else, rows(end+1)=row; end %#ok<AGROW>
    end
end
% Retain raw sealed episodes on a source-change failure, but do not publish
% a collection-complete receipt for potentially mixed-revision execution.
try
    sixgr.calibration.assertGrantSourceIdentity(sources);
catch sourceError
    if strcmp(sourceError.identifier,'sixgr:calibration:GrantSourceChanged')
        sixgr.util.jsonWrite(fullfile(folder,'source_change_failure.json'), ...
            struct('CollectionIdentity',identity,'SourceChangedDuringExecution',true, ...
            'CalibrationQualified',false,'PrimaryStudyAccepted',false));
    end
    rethrow(sourceError)
end
% Keep one primary raw-trial CSV for every SNR and both populations. Derive
% it from sealed episodes on every resume, never from an unverified journal.
trials=struct2table(rows);
if ~isempty(rows)
    csvStaging=string(tempname(folder))+".csv";
    writetable(trials,csvStaging);
    sixgr.calibration.commitFile(csvStaging,fullfile(folder,'waveform_trials.csv'));
    metricStaging=string(tempname(folder))+".csv";
    writetable(performance,metricStaging);
    sixgr.calibration.commitFile(metricStaging,fullfile(folder,'episode_execution_metrics.csv'));
end
done=0;
if ~isempty(rows), done=numel(unique(string(trials.EpisodeID))); end
receipt=struct('CollectionIdentity',identity,'Folder',folder, ...
    'EvidenceStorage',storageMode, ...
    'PlannedEpisodes',numel(plan),'CompletedEpisodes',done,'NewEpisodes',newCount, ...
    'PhysicalAttempts',height(trials),'AllPlannedEpisodesPresent',done==numel(plan), ...
    'CalibrationQualified',false,'PrimaryStudyAccepted',false, ...
    'Status',"raw_collection_only_fit_and_independent_validation_still_required");
receipt.InvocationElapsedSeconds=toc(invocationClock);
receipt.NewEpisodeExecutionSeconds=newExecutionSeconds;
receipt.TimingCoveredEpisodes=0; receipt.RecordedEpisodeExecutionSeconds=0; receipt.StoredEpisodeBytes=0;
if ~isempty(performance)
    receipt.TimingCoveredEpisodes=nnz(performance.TimingAvailable);
    receipt.RecordedEpisodeExecutionSeconds=sum(performance.ExecutionElapsed_s(performance.TimingAvailable));
    receipt.StoredEpisodeBytes=sum(performance.StoredEpisodeBytes);
end
end

function digest=localHash(value)
digest=string(sixgr.util.sha256Hex(uint8(unicode2native( ...
    jsonencode(sixgr.util.jsonSafeValue(value)),'UTF-8'))));
end

function localCommit(staging,target)
assert(~isfile(target),'sixgr:calibration:GrantCollectionCommit', ...
    'Never overwrite a committed waveform episode or its manifest.');
sixgr.calibration.commitFile(staging,target);
seal=struct('SHA256',sixgr.csi.studyFileSHA256(target));
staging=string(tempname(fileparts(target)))+".json";
sixgr.util.jsonWrite(staging,seal);
sixgr.calibration.commitFile(staging,string(target)+".sha256.json");
end

function localVerify(path)
sixgr.calibration.verifyEpisodeFile(path);
end
