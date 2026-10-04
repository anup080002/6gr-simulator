function receipt=run_grant_calibration(configPath,outputRoot,runTag)
%RUN_GRANT_CALIBRATION Resume YAML-driven, exact-grant waveform collection.
% Raw waveform collection is not statistical qualification or installation.
arguments
    configPath (1,1) string
    outputRoot (1,1) string="results/calibration"
    runTag (1,1) string=string(datetime('now','Format','yyyyMMdd_HHmmss'))
end
invocationClock=tic;
assert(~isempty(regexp(char(runTag),'^[A-Za-z0-9][A-Za-z0-9_-]*$','once')), ...
    'sixgr:calibration:RunTag','Use a single safe run-tag directory.');
[p,collections,scienceIdentity]=sixgr.calibration.loadGrantCampaign(configPath);
folder=fullfile(outputRoot,runTag);
if ~isfolder(folder), mkdir(folder); end
lockPath=fullfile(folder,'.grant_campaign_lock'); lock=java.io.File(char(lockPath));
assert(lock.mkdir(),'sixgr:calibration:GrantCollectionBusy','This campaign already has an owner.');
unlock=onCleanup(@()rmdir(lockPath)); %#ok<NASGU>
sources=sixgr.calibration.grantSourceIdentity();
manifest=fullfile(folder,'grant_campaign.mat');
if isfile(manifest)
    sixgr.calibration.verifyEpisodeFile(manifest);
    prior=load(manifest,'scienceIdentity','sources');
    assert(prior.scienceIdentity==scienceIdentity && isequaln(prior.sources,sources), ...
        'sixgr:calibration:GrantCampaignIdentity','Scientific inputs or source changed; use a new run tag.');
else
    assert(~isfile(manifest+".sha256.json"),'sixgr:calibration:EpisodeCommit','Orphaned campaign checksum.');
    entries=string({dir(folder).name});
    assert(all(ismember(entries,[".","..",".grant_campaign_lock"])), ...
        'sixgr:calibration:GrantCampaignIdentity', ...
        'Output folder contains unowned files without its sealed campaign manifest; use a new run tag.');
    sourceText=fileread(configPath); %#ok<NASGU>
    createdUTC=char(datetime('now','TimeZone','UTC','Format',"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'")); %#ok<NASGU>
    [gitStatus,revision]=system('git rev-parse HEAD'); %#ok<ASGLU>
    staging=string(tempname(folder))+".mat";
    save(staging,'p','scienceIdentity','sources','sourceText','revision','collections','createdUTC','-v7.3');
    sixgr.calibration.commitFile(staging,manifest);
    sixgr.util.jsonWrite(manifest+".sha256.json",struct('SHA256',sixgr.csi.studyFileSHA256(manifest)));
    sixgr.util.jsonWrite(fullfile(folder,'resolved_campaign.json'),sixgr.util.jsonSafeValue(p));
end
receipt=struct('CampaignID',string(p.campaign_id),'Folder',folder, ...
    'EvidenceStorage',string(p.evidence_storage), ...
    'InvocationEpisodeLimit',double(p.episodes_per_invocation), ...
    'PlannedEpisodes',sum(arrayfun(@(c)numel(c.Plan),collections)), ...
    'CompletedEpisodes',0,'NewEpisodes',0,'PhysicalAttempts',0, ...
    'InvocationElapsedSeconds',0,'NewEpisodeExecutionSeconds',0, ...
    'TimingCoveredEpisodes',0,'RecordedEpisodeExecutionSeconds',0,'StoredEpisodeBytes',0, ...
    'AllPlannedEpisodesPresent',false,'CalibrationQualified',false,'PrimaryStudyAccepted',false, ...
    'Status',"running_raw_waveform_collection");
receipt=localReceipt(folder,receipt,invocationClock);
try
    remaining=double(p.episodes_per_invocation);
    joint=table(); performance=table();
    for k=1:numel(collections)
        c=collections(k); child=fullfile(folder,c.ID);
        % MaximumNewEpisodes=0 performs verified inventory only, enabling
        % one campaign-wide budget while keeping every joint CSV complete.
        r=sixgr.system.waveform.collectGrantCalibrationEpisodes(c.Config,c.Plan,child, ...
            'MaximumNewEpisodes',remaining,'EvidenceStorage',string(p.evidence_storage));
        remaining=remaining-r.NewEpisodes;
        receipt.CompletedEpisodes=receipt.CompletedEpisodes+r.CompletedEpisodes;
        receipt.NewEpisodes=receipt.NewEpisodes+r.NewEpisodes;
        receipt.PhysicalAttempts=receipt.PhysicalAttempts+r.PhysicalAttempts;
        receipt.NewEpisodeExecutionSeconds=receipt.NewEpisodeExecutionSeconds+r.NewEpisodeExecutionSeconds;
        receipt.TimingCoveredEpisodes=receipt.TimingCoveredEpisodes+r.TimingCoveredEpisodes;
        receipt.RecordedEpisodeExecutionSeconds=receipt.RecordedEpisodeExecutionSeconds+r.RecordedEpisodeExecutionSeconds;
        receipt.StoredEpisodeBytes=receipt.StoredEpisodeBytes+r.StoredEpisodeBytes;
        if r.PhysicalAttempts>0
            rows=readtable(fullfile(child,'waveform_trials.csv'),'TextType','string');
            rows.CollectionID=repmat(c.ID,height(rows),1);
            rows.EpisodeRelativePath=c.ID+"/"+rows.EpisodeRelativePath;
            joint=[joint;rows]; %#ok<AGROW>
            metricsPath=fullfile(child,'episode_execution_metrics.csv');
            metricOptions=detectImportOptions(metricsPath,'TextType','string');
            metricOptions=setvartype(metricOptions, ...
                {'EpisodeID','Role','ExecutionStartedUTC','TimingScope','EvidenceStorage','EpisodeRelativePath'},'string');
            metricOptions=setvartype(metricOptions, ...
                {'PhysicalAttempts','ExecutionElapsed_s','TimingAvailable','StoredEpisodeBytes', ...
                'CalibrationQualified','PrimaryStudyAccepted'},'double');
            metrics=readtable(metricsPath,metricOptions);
            metrics.CollectionID=repmat(c.ID,height(metrics),1);
            metrics.EpisodeRelativePath=c.ID+"/"+metrics.EpisodeRelativePath;
            performance=[performance;metrics]; %#ok<AGROW>
        end
        receipt=localReceipt(folder,receipt,invocationClock);
    end
    sixgr.calibration.assertGrantSourceIdentity(sources);
    staging=string(tempname(folder))+".csv"; writetable(joint,staging);
    sixgr.calibration.commitFile(staging,fullfile(folder,'waveform_trials.csv'));
    if ~isempty(performance)
        staging=string(tempname(folder))+".csv"; writetable(performance,staging);
        sixgr.calibration.commitFile(staging,fullfile(folder,'episode_execution_metrics.csv'));
    end
    receipt.AllPlannedEpisodesPresent=receipt.CompletedEpisodes==receipt.PlannedEpisodes;
    receipt.Status="paused_at_invocation_budget";
    if receipt.AllPlannedEpisodesPresent, receipt.Status="collection_complete_not_qualified"; end
    receipt=localReceipt(folder,receipt,invocationClock);
catch err
    receipt.Status="failed"; receipt.ErrorIdentifier=string(err.identifier); receipt.ErrorMessage=string(err.message);
    localReceipt(folder,receipt,invocationClock); rethrow(err)
end
end

function receipt=localReceipt(folder,receipt,invocationClock)
receipt.InvocationElapsedSeconds=toc(invocationClock);
staging=string(tempname(folder))+".json";
sixgr.util.jsonWrite(staging,receipt);
sixgr.calibration.commitFile(staging,fullfile(folder,'receipt.json'));
end
