function receipt=runHARQCalibrationCampaign(studyPath,outputRoot,runTag)
%RUNHARQCALIBRATIONCAMPAIGN Resumable physical HARQ population collection.
% Records conditional attempts only (stop on success), never extrapolates
% an unexecuted retransmission. Not a fitted/qualified SLS calibration MAT.
arguments
    studyPath (1,1) string
    outputRoot (1,1) string
    runTag (1,1) string
end
assert(~isempty(regexp(char(runTag),'^[A-Za-z0-9_-]+$','once')), ...
    'sixgr:ran1ai1032:HARQRunTag','Use a single safe run-tag directory.');
[study,provenance]=sixgr.studies.ran1ai1032.loadStudyConfig(studyPath);
p=study.harq.calibration; e=study.lls.execution;
for f=["fit_episodes_per_history","validation_episodes_per_history","episodes_per_invocation","seed_base"]
    validateattributes(p.(f),{'numeric'},{'scalar','integer','positive','finite'});
end
histories=p.snr_histories_db;
if iscell(histories), histories=vertcat(histories{:}); end
histories=double(histories); rv=double(study.harq.rv_sequence);
if isvector(histories), histories=reshape(histories,1,[]); end
assert(ismatrix(histories) && ~isempty(histories) && size(histories,2)==numel(rv) && ...
    all(isfinite(histories),'all') && size(unique(histories,'rows'),1)==size(histories,1), ...
    'sixgr:ran1ai1032:HARQCalibrationHistory','Require unique finite SNR-history rows with one column per RV.');
plan=sixgr.studies.ran1ai1032.buildLLSCasePlan(study); C=plan.CasePlan;
selected=C.ExperimentID=="F1" & ismember(C.EntryID,string(e.entry_ids)) & ...
    ismember(C.ChannelProfile,string(e.channel_profiles)) & ismember(C.Rank,double(e.ranks));
if isfield(e,'antenna_case_ids') && ~isempty(e.antenna_case_ids)
    selected=selected & ismember(C.AntennaCaseID,string(e.antenna_case_ids));
end
C=C(selected,:); assert(~isempty(C),'sixgr:ran1ai1032:HARQSelection','No physical cases selected.');
counts=[double(p.fit_episodes_per_history),double(p.validation_episodes_per_history)];
perCase=size(histories,1)*sum(counts);
totalEpisodes=height(C)*perCase;
pairKeys=unique(string(C.ComparisonPairKey),'stable');
[~,pairIndex]=ismember(string(C.ComparisonPairKey),pairKeys);
assert(double(p.seed_base)+numel(pairKeys)*perCase*numel(rv)<2^32, ...
    'sixgr:ran1ai1032:HARQSeeds','Selected population exceeds the unique uint32 seed space.');
% Budget changes may resume; scientific or implementation changes may not.
science=study; science.harq.calibration=rmfield(science.harq.calibration,'episodes_per_invocation');
sources=["+sixgr/+studies/+ran1ai1032/runHARQCalibrationCampaign.m", ...
    "+sixgr/+studies/+ran1ai1032/executeF1HARQSequence.m", ...
    "+sixgr/+studies/+ran1ai1032/executeF1PUSCHTrial.m", ...
    "+sixgr/+studies/+ran1ai1032/buildF1RuntimeConfig.m", ...
    "+sixgr/+studies/+ran1ai1032/applyF1TransmitRF.m", ...
    "+sixgr/+studies/+ran1ai1032/applyRFStudyBranch.m", ...
    "+sixgr/+studies/+ran1ai1032/resolveF1RFBranch.m", ...
    "+sixgr/+rf/+runtime/RFImpairmentStream.m", ...
    "+sixgr/+rf/+runtime/PhaseNoiseProcess.m", ...
    "+sixgr/+rf/+runtime/SpectralPhaseNoiseFilter.m", ...
    "+sixgr/+rf/+runtime/resolveMultipolePhaseNoiseProfile.m", ...
    "+sixgr/+phy/+ul/PUSCH_Tx.m","+sixgr/+phy/+ul/PUSCH_Rx.m", ...
    "+sixgr/+phy/+harq/combineSoftLLR.m","+sixgr/+channel/ChannelFactory.m", ...
    "+sixgr/+truth/SharedWaveformPhysicalRuntime.m",string(e.research_transport_policy_path)];
branch=sixgr.studies.ran1ai1032.resolveF1RFBranch(study,string(2^C.Qm(1))+"QAM");
if isfield(branch,'phase_noise_profile_path')
    sources(end+1)=string(branch.phase_noise_profile_path);
end
hashes=strings(size(sources));
sourceText=cell(size(sources));
for k=1:numel(sources)
    hashes(k)=sixgr.csi.studyFileSHA256(sources(k));
    sourceText{k}=fileread(sources(k));
end
identity=string(sixgr.util.sha256Hex(uint8(unicode2native(jsonencode(science)+join(hashes,''),'UTF-8'))));
folder=fullfile(outputRoot,runTag,'harq'); if ~isfolder(folder), mkdir(folder); end
identityFile=fullfile(folder,'identity.mat');
if isfile(identityFile)
    old=load(identityFile,'identity');
    assert(old.identity==identity,'sixgr:ran1ai1032:HARQResumeIdentity','Scientific/source identity changed; use a new run tag.');
else
    environment=struct('MATLABVersion',version,'Toolboxes',ver);
    save(identityFile,'identity','study','provenance','sources','hashes','sourceText','environment');
    writetable(C,fullfile(folder,'selected_cases.csv'));
    copyfile(studyPath,fullfile(folder,'input_study.yaml'));
end
executed=0; completed=0; attemptCount=0; allComplete=true;
for ci=1:height(C)
    for hi=1:size(histories,1)
        cf=fullfile(folder,C.OutputGroupID(ci),"history_"+hi);
        if ~isfolder(cf), mkdir(cf); end
        file=fullfile(cf,'checkpoint.mat');
        if isfile(file)
            saved=load(file,'state'); state=saved.state;
            assert(state.Identity==identity,'sixgr:ran1ai1032:HARQResumeIdentity','Checkpoint identity differs.');
        else
            state=struct('Identity',identity,'EpisodeCount',[0 0],'Trials',table());
        end
        roles=["fit","validation"];
        for role=1:2
            while state.EpisodeCount(role)<counts(role) && executed<p.episodes_per_invocation
                episode=state.EpisodeCount(role)+1;
                ordinal=(ci-1)*perCase+(hi-1)*sum(counts)+sum(counts(1:role-1))+episode;
                % Common random channel seeds across modulation comparators;
                % fit/validation and independent episodes remain disjoint.
                seedOrdinal=(pairIndex(ci)-1)*perCase+(hi-1)*sum(counts)+sum(counts(1:role-1))+episode;
                seeds=double(p.seed_base)+(seedOrdinal-1)*numel(rv)+(1:numel(rv));
                result=sixgr.studies.ran1ai1032.executeF1HARQSequence(study,C(ci,:),histories(hi,:),seeds);
                T=result.TrialTable; n=height(T);
                T.CaseID=repmat(C.CaseID(ci),n,1); T.Role=repmat(roles(role),n,1);
                T.HistoryIndex=repmat(hi,n,1); T.EpisodeIndex=repmat(episode,n,1);
                T.TrialID=identity+"_episode_"+ordinal+"_attempt_"+T.Attempt;
                T.SourceClassification=repmat(result.SourceClassification,n,1);
                % Commit exact executed configurations before committing
                % their trial rows. MAT retains complex arrays losslessly.
                resolvedConfigurations=result.ResolvedConfigurations;
                configFile=fullfile(cf,roles(role)+"_episode_"+episode+"_resolved.mat");
                partial=configFile+".partial.mat";
                save(partial,'resolvedConfigurations','identity');
                [ok,msg]=movefile(partial,configFile,'f'); assert(ok,'%s',msg);
                state.Trials=[state.Trials;T]; %#ok<AGROW>
                state.EpisodeCount(role)=episode;
                temporary=file+".partial.mat"; save(temporary,'state','-v7.3');
                [ok,msg]=movefile(temporary,file,'f'); assert(ok,'%s',msg);
                executed=executed+1; attemptCount=attemptCount+n;
                fprintf('HARQ_CALIBRATION_PROGRESS case=%s history=%d role=%s episode=%d attempts=%d delivered=%d\n', ...
                    C.CaseID(ci),hi,roles(role),episode,n,result.Delivered);
            end
        end
        if ~isempty(state.Trials)
            % Rebuild from the committed checkpoint, so a interrupted CSV
            % materialization cannot duplicate or omit physical attempts.
            for role=1:2
                T=state.Trials(state.Trials.Role==roles(role),:);
                if isempty(T), continue; end
                target=fullfile(cf,roles(role)+"_attempts.csv"); tmp=target+".partial.csv";
                writetable(T,tmp); [ok,msg]=movefile(tmp,target,'f'); assert(ok,'%s',msg);
            end
        end
        completed=completed+sum(state.EpisodeCount);
        allComplete=allComplete && all(state.EpisodeCount==counts);
    end
end
receipt=struct('RunFolder',folder,'CampaignIdentity',identity, ...
    'EpisodesThisInvocation',executed,'AttemptsThisInvocation',attemptCount, ...
    'EpisodesCompleted',completed,'EpisodesPlanned',totalEpisodes, ...
    'AllEpisodesComplete',allComplete,'PrimaryStudyAccepted',false, ...
    'Status',"raw_waveform_collection_not_fitted_SLS_calibration");
save(fullfile(folder,'receipt.mat'),'receipt');
end
