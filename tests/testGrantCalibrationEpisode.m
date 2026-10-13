function ok=testGrantCalibrationEpisode()
% Real failed attempts, retained TB/soft buffer, stop on actual CRC success.
cfg=localConfig();
seeds=struct('Bits',5101,'Noise',[5102 5103 5104], ...
    'Channel',[5105 5106 5107],'ControlNoise',[5108 5109 5110],'RF',[5111 5112 5113]);
for direction=["DL","UL"]
    for rankValue=[1 2]
        [variant,grants]=localPlan(cfg,direction,rankValue);
        inputGrants=grants;
        originalRNG=rng;
        e=sixgr.system.waveform.executeGrantCalibrationEpisode(variant,grants,[-40 40 40],seeds);
        assert(isequal(originalRNG,rng),'Episode execution changed the caller random stream.');
        assert(numel(e.Attempts)==2 && e.Attempts(1).CRCError && ...
            ~e.Attempts(2).CRCError && e.Attempts(2).HARQSoftCombiningApplied && ...
            e.Delivered && e.StopReason=="crc_success", ...
            'Actual low-SNR failure must retry with soft combining and stop at success.');
        assert(isequaln(grants,inputGrants) && ~e.CalibrationQualified && ~e.PrimaryStudyAccepted);
        stream=RandStream('mt19937ar','Seed',seeds.Bits);
        expected=int8(randi(stream,[0 1],grants{1}.TBSBits,1));
        assert(isequal(expected,e.OriginalTransportBlock));
        assert(isequal(e.Captures{1}.Transmitter.TransportBlock,e.Captures{2}.Transmitter.TransportBlock));
        assert(e.Captures{2}.Transmitter.Carrier.NFrame==1 && ...
            e.Captures{2}.Transmitter.Carrier.NSlot==3);
        % Independent channel seeds must not reset a scheduled attempt to
        % time zero. These 30-kHz grants straddle the radio-frame boundary.
        expectedTimes=[19 23]*0.0005;
        assert(e.ChannelEvolution=="independent_attempt_realizations" && ...
            isequal([e.Attempts.ChannelSeed],seeds.Channel(1:2)) && ...
            max(abs([e.Attempts.ChannelInitialTime_s]-expectedTimes))<1e-14);
        for attempt=1:2
            assert(abs(e.Replays{attempt}.ReplayChannelInitialTime_s-expectedTimes(attempt))<1e-14 && ...
                abs(e.Captures{attempt}.Propagation.ChannelInitialTime_s-expectedTimes(attempt))<1e-14, ...
                'Independent realizations must execute on the frozen grant clock.');
        end
        assert(~sixgr.system.waveform.harqSoftBufferCache('get',e.Replays{1}.HARQSoftBufferKey));
        firstSuccess=sixgr.system.waveform.executeGrantCalibrationEpisode(variant,grants,[40 -40 -40],seeds);
        assert(numel(firstSuccess.Attempts)==1 && firstSuccess.Delivered && ...
            ~firstSuccess.Attempts(1).HARQSoftCombiningApplied, ...
            'No artificial retries after CRC success and no leaked soft buffer between episodes.');
        exhausted=sixgr.system.waveform.executeGrantCalibrationEpisode(variant,grants(1),-40, ...
            struct('Bits',seeds.Bits,'Noise',seeds.Noise(1), ...
            'Channel',seeds.Channel(1),'ControlNoise',seeds.ControlNoise(1),'RF',seeds.RF(1)));
        assert(~exhausted.Delivered && exhausted.StopReason=="attempt_budget_exhausted");
        assert(~sixgr.system.waveform.harqSoftBufferCache('get',exhausted.Replays{1}.HARQSoftBufferKey), ...
            'Exhausted TB buffers must be released without clearing another runtime TB.');
        fprintf('GRANT_CALIBRATION_EPISODE_CASE direction=%s rank=%d real_retry=1 stop_on_crc=1\n',direction,rankValue);
    end
end
bad=seeds; bad.Noise(2)=bad.Noise(1);
localExpect(@()sixgr.system.waveform.executeGrantCalibrationEpisode(variant,grants,[0 0 0],bad), ...
    'sixgr:calibration:GrantEpisodeSeeds');
badGrants=grants; badGrants{2}.TransportBlockIdentity="other_tb";
localExpect(@()sixgr.system.waveform.executeGrantCalibrationEpisode(variant,badGrants,[0 0 0],seeds), ...
    'sixgr:calibration:GrantEpisodeIdentity');
badGrants=grants; badGrants{2}.TBSBits=grants{2}.TBSBits+8;
localExpect(@()sixgr.system.waveform.executeGrantCalibrationEpisode(variant,badGrants,[0 0 0],seeds), ...
    'sixgr:calibration:GrantEpisodeIdentity');
key=char(string(grants{1}.Direction)+"|tb="+string(grants{1}.TransportBlockIdentity)+ ...
    "|tbs="+string(grants{1}.TBSBits));
sixgr.system.waveform.harqSoftBufferCache('set',key,17);
cleanup=onCleanup(@()sixgr.system.waveform.harqSoftBufferCache('clear',key)); %#ok<NASGU>
localExpect(@()sixgr.system.waveform.executeGrantCalibrationEpisode(variant,grants,[0 0 0],seeds), ...
    'sixgr:calibration:GrantEpisodeCacheOwnership');
[hit,value]=sixgr.system.waveform.harqSoftBufferCache('get',key);
assert(hit && value==17,'Collector must not destroy another live TB buffer.');
clear cleanup;
localCollection(variant,grants,seeds);
ok=true;
fprintf('GRANT_CALIBRATION_EPISODE_PASS qualification=0 synthetic_retries=0\n');
end

function localCollection(cfg,grants,seeds)
folder=tempname(fullfile(pwd,'logs'));
plan=struct('EpisodeID','fit_1','Role','fit','Grants',{grants}, ...
    'SNRdB',[40 40 40],'Seeds',seeds);
plan(2)=plan(1); plan(2).EpisodeID='held_out_1'; plan(2).Role='validation';
for name=string(fieldnames(seeds)).'
    plan(2).Seeds.(name)=seeds.(name)+100;
end
quarantined=tempname(fullfile(pwd,'logs')); mkdir(quarantined);
sixgr.util.jsonWrite(fullfile(quarantined,'source_change_failure.json'), ...
    struct('SourceChangedDuringExecution',true,'CalibrationQualified',false));
localExpect(@()sixgr.system.waveform.collectGrantCalibrationEpisodes(cfg,plan,quarantined), ...
    'sixgr:calibration:GrantSourceChanged');
first=sixgr.system.waveform.collectGrantCalibrationEpisodes(cfg,plan,folder);
assert(first.NewEpisodes==1 && first.CompletedEpisodes==1 && ~first.AllPlannedEpisodesPresent);
csv=fullfile(folder,'waveform_trials.csv');
one=readtable(csv,'TextType','string');
assert(height(one)==1 && one.Role=="fit" && one.Attempt==1 && ~one.CRCError);
episodeFile=fullfile(folder,char(one.EpisodeRelativePath(1)));
originalHash=sixgr.csi.studyFileSHA256(episodeFile);
timingPath=fullfile(folder,'episode_execution_metrics.csv');
timed=readtable(timingPath,'TextType','string');
disk=dir(episodeFile);
assert(height(timed)==1 && timed.TimingAvailable && timed.ExecutionElapsed_s>0 && ...
    timed.StoredEpisodeBytes==disk.bytes && timed.PhysicalAttempts==1 && ...
    first.TimingCoveredEpisodes==1 && ...
    abs(first.NewEpisodeExecutionSeconds-timed.ExecutionElapsed_s)<=1e-12*max(1,timed.ExecutionElapsed_s) && ...
    first.InvocationElapsedSeconds>=first.NewEpisodeExecutionSeconds && ...
    ~timed.CalibrationQualified && ~timed.PrimaryStudyAccepted);
second=sixgr.system.waveform.collectGrantCalibrationEpisodes(cfg,plan,folder);
assert(second.NewEpisodes==1 && second.CompletedEpisodes==2 && second.AllPlannedEpisodesPresent && ...
    ~second.CalibrationQualified && ~second.PrimaryStudyAccepted);
joint=readtable(csv,'TextType','string');
assert(height(joint)==2 && all(ismember(["fit","validation"],joint.Role)) && ...
    ~any(joint.PrimaryStudyAccepted) && sixgr.csi.studyFileSHA256(episodeFile)==originalHash, ...
    'Resume must keep the original decoded episode and aggregate both populations into one CSV.');
third=sixgr.system.waveform.collectGrantCalibrationEpisodes(cfg,plan,folder);
timedAgain=readtable(timingPath,'TextType','string');
assert(third.NewEpisodes==0 && third.PhysicalAttempts==2 && third.NewEpisodeExecutionSeconds==0 && ...
    third.TimingCoveredEpisodes==2 && ...
    timedAgain.ExecutionElapsed_s(1)==timed.ExecutionElapsed_s && ...
    third.StoredEpisodeBytes==sum(timedAgain.StoredEpisodeBytes), ...
    'Resume must retain original execution timings and count each episode file only once.');
localCampaign(folder);
badPlan=plan; badPlan(2).Seeds=plan(1).Seeds;
localExpect(@()sixgr.system.waveform.collectGrantCalibrationEpisodes(cfg,badPlan,folder), ...
    'sixgr:calibration:GrantCollectionSeeds');
badPlan=plan; badPlan(2).SNRdB=[39 40 40];
localExpect(@()sixgr.system.waveform.collectGrantCalibrationEpisodes(cfg,badPlan,folder), ...
    'sixgr:calibration:GrantCollectionIdentity');
% Simulate an older sealed episode lacking optional performance metadata.
% Only this test-created file is rewritten; its PHY outcomes stay identical.
legacy=load(episodeFile); legacy=rmfield(legacy,'executionMetrics');
save(episodeFile,'-struct','legacy','-v7.3');
sixgr.util.jsonWrite(string(episodeFile)+".sha256.json", ...
    struct('SHA256',sixgr.csi.studyFileSHA256(episodeFile)));
legacyReceipt=sixgr.system.waveform.collectGrantCalibrationEpisodes(cfg,plan,folder,'MaximumNewEpisodes',0);
legacyMetrics=readtable(timingPath,'TextType','string');
assert(~legacyMetrics.TimingAvailable(1) && isnan(legacyMetrics.ExecutionElapsed_s(1)) && ...
    legacyMetrics.TimingScope(1)=="unavailable_not_retained" && ...
    legacyReceipt.TimingCoveredEpisodes==1 && legacyReceipt.NewEpisodeExecutionSeconds==0, ...
    'Inventory-read time must never replace missing original execution time.');
% Corrupt only this test-created retained MAT, without resealing it.
tamper=1; save(episodeFile,'tamper','-append');
localExpect(@()sixgr.system.waveform.collectGrantCalibrationEpisodes(cfg,plan,folder), ...
    'sixgr:calibration:EpisodeDigest');
assert(~isfolder(fullfile(folder,'.grant_collection_lock')),'Error cleanup left the collection locked.');
fprintf('GRANT_COLLECTION_RESUME_PASS joint_csv=1 held_out_seed_guard=1 tamper_rejected=1 folder=%s\n',folder);
end

function localCampaign(templateFolder)
% Exercise the public YAML entry point with real fresh waveform episodes.
% The retained manifest supplies allocations only, never its earlier CRCs.
root=tempname(fullfile(pwd,'logs')); mkdir(root);
template=fullfile(templateFolder,'campaign.mat');
c=struct('id',"ul_awgn_a",'template_manifest',string(template), ...
    'template_manifest_sha256',sixgr.csi.studyFileSHA256(template), ...
    'template_episode_id',"fit_1",'snr_histories_db',[40 40 40], ...
    'fit_starts_per_history',1,'validation_starts_per_history',1);
c(2)=c(1); c(2).id="ul_awgn_b";
p=struct('schema',"sixgr.grant_calibration_campaign/v1", ...
    'campaign_id',"public_grant_entry_regression",'research_class',"baseline_benchmark", ...
    'seed_base',71000,'channel_evolution',"persistent_link_absolute_slot", ...
    'episodes_per_invocation',1,'collections',c);
file=fullfile(root,'campaign.yaml'); sixgr.util.jsonWrite(file,p);
[~,expanded,identity]=sixgr.calibration.loadGrantCampaign(file);
streams=[];
for k=1:numel(expanded)
    for j=1:numel(expanded(k).Plan)
        episode=expanded(k).Plan(j);
        streams=[streams;sixgr.system.waveform.validateGrantCalibrationSeeds(episode.Seeds,3)]; %#ok<AGROW>
        assert(all(episode.Seeds.Channel==episode.Seeds.Channel(1)));
        assert(episode.Grants{1}.TransportBlockIdentity==string(episode.EpisodeID));
    end
end
assert(numel(unique(streams))==numel(streams),'All collections and roles need independent streams.');
first=run_grant_calibration(file,root,'physical');
assert(first.NewEpisodes==1 && first.CompletedEpisodes==1 && first.PlannedEpisodes==4 && ...
    ~first.AllPlannedEpisodesPresent && ~first.CalibrationQualified && ~first.PrimaryStudyAccepted);
jointPath=fullfile(first.Folder,'waveform_trials.csv');
one=readtable(jointPath,'TextType','string');
assert(height(one)==1 && one.CollectionID=="ul_awgn_a" && one.Attempt==1 && ~one.CRCError);
original=fullfile(first.Folder,one.EpisodeRelativePath(1)); originalHash=sixgr.csi.studyFileSHA256(original);
% Budget changes are scheduling controls, not a change in the population.
p.episodes_per_invocation=3; sixgr.util.jsonWrite(file,p);
[~,next,nextIdentity]=sixgr.calibration.loadGrantCampaign(file);
assert(identity==nextIdentity && isequaln(expanded,next));
second=run_grant_calibration(file,root,'physical');
assert(second.NewEpisodes==3 && second.CompletedEpisodes==4 && second.AllPlannedEpisodesPresent);
rows=readtable(jointPath,'TextType','string');
assert(height(rows)==4 && numel(unique(rows.CollectionID))==2 && ...
    all(ismember(["fit","validation"],rows.Role)) && ...
    all(rows.Attempt==1) && ~any(rows.CRCError) && ~any(rows.CalibrationQualified) && ...
    sixgr.csi.studyFileSHA256(original)==originalHash);
third=run_grant_calibration(file,root,'physical');
metrics=readtable(fullfile(third.Folder,'episode_execution_metrics.csv'),'TextType','string');
assert(third.NewEpisodes==0 && third.PhysicalAttempts==4 && ...
    third.NewEpisodeExecutionSeconds==0 && third.TimingCoveredEpisodes==4 && ...
    height(metrics)==4 && numel(unique(metrics.EpisodeID))==4 && ...
    all(metrics.TimingAvailable) && third.StoredEpisodeBytes==sum(metrics.StoredEpisodeBytes) && ...
    abs(third.RecordedEpisodeExecutionSeconds-sum(metrics.ExecutionElapsed_s))<= ...
    1e-12*max(1,third.RecordedEpisodeExecutionSeconds), ...
    'Joint timing/storage accounting must cover all collections and roles without duplicating retry files.');
bad=p; bad.unknown_policy=true; sixgr.util.jsonWrite(file,bad);
localExpect(@()sixgr.calibration.loadGrantCampaign(file),'sixgr:calibration:GrantCampaignFields');
bad=p; bad.collections(1).template_manifest_sha256=repmat('0',1,64); sixgr.util.jsonWrite(file,bad);
localExpect(@()sixgr.calibration.loadGrantCampaign(file),'sixgr:calibration:GrantCampaignTemplateDigest');
bad=p; bad.collections(1).snr_histories_db=[40 40]; sixgr.util.jsonWrite(file,bad);
localExpect(@()sixgr.calibration.loadGrantCampaign(file),'sixgr:calibration:GrantCampaignHistory');
bad=p; bad.seed_base=2^32-1; sixgr.util.jsonWrite(file,bad);
localExpect(@()sixgr.calibration.loadGrantCampaign(file),'sixgr:calibration:GrantCampaignSeeds');
bad=p; bad.seed_base=p.seed_base+1; sixgr.util.jsonWrite(file,bad);
localExpect(@()run_grant_calibration(file,root,'physical'),'sixgr:calibration:GrantCampaignIdentity');
sixgr.util.jsonWrite(file,p);
assert(~isfolder(fullfile(first.Folder,'.grant_campaign_lock')));
fprintf('GRANT_YAML_CAMPAIGN_PASS new_physical_episodes=4 shared_csv=1 independent_roles=1 qualified=0 folder=%s\n',first.Folder);
end

function cfg=localConfig()
cfg=sixgr.config.defaultConfig();
cfg.run.strictMode=true; cfg.run.useMex=false;
cfg.run.pdschExecutionProfile='phy_calibration'; cfg.run.puschExecutionProfile='phy_calibration';
cfg.phy.carrier.NSizeGrid=24; cfg.phy.carrier.NStartGrid=0; cfg.phy.carrier.SubcarrierSpacing=30;
cfg.phy.fc_Hz=4e9; cfg.phy.nTxAnt=2; cfg.phy.nRxAnt=2;
cfg.scenario.bs.nTxAnt=2; cfg.scenario.bs.nRxAnt=2;
cfg.scenario.ue.nTxAnt=2; cfg.scenario.ue.nRxAnt=2;
cfg.antenna.bs.numElements=2; cfg.antenna.bs.numRFChains=2;
cfg.antenna.ue.numElements=2; cfg.antenna.ue.numRFChains=2;
cfg.rf=struct(); cfg.phy.impairments=struct();
cfg.phy.beamManagement.hybridBeamformingEnabled=false;
cfg.phy.ssb.enable=false; cfg.phy.csirs.enable=false; cfg.phy.trs.enable=false;
cfg.phy.csiim.enable=false; cfg.phy.ptrs.enable=false;
cfg.channel=struct('model','AWGN','awgnOnly',true,'nTxAnt',2,'nRxAnt',2);
mcs=sixgr.link.resolveMCSProfile('qam64_table1',1);
for name=["pdsch","pusch"]
    cfg.phy.(name).modulation='QPSK'; cfg.phy.(name).codeRate=mcs.TargetCodeRate;
    cfg.phy.(name).mcsTable='qam64_table1'; cfg.phy.(name).mcsIndex=1;
    cfg.phy.(name).numPorts=2; cfg.phy.(name).nPorts=2;
    cfg.phy.(name).enablePTRS=false; cfg.phy.(name).xOverhead=0;
    cfg.phy.(name).prbSet=0:5; cfg.phy.(name).symbolAllocation=[2 10];
end
cfg.phy.pusch.transformPrecoding=false;
end

function [cfg,grants]=localPlan(cfg,direction,layers)
for name=["pdsch","pusch"]
    cfg.phy.(name).numLayers=layers; cfg.phy.(name).nLayers=layers;
    cfg.phy.(name).dmrs.portSet=0:layers-1;
end
carrier=sixgr.phy.grid.makeCarrier(cfg);
if direction=="DL"
    [~,info,channel]=sixgr.phy.grid.allocREsPDSCH(carrier,cfg,'RNTI',73);
else
    [~,info,channel]=sixgr.phy.grid.allocPUSCHTransport(carrier,cfg,'RNTI',73);
end
if isfield(info,'IndicesInfo'), info=info.IndicesInfo; end
tbs=double(nrTBS('QPSK',layers,numel(channel.PRBSet),info.NREPerPRB,cfg.phy.pdsch.codeRate,0));
W=eye(2,layers)/sqrt(layers); rv=[0 2 3]; slots=[19 23 27]; grants=cell(1,3);
for k=1:3
    g=struct('Direction',char(direction),'Frame',floor(slots(k)/20),'Slot',mod(slots(k),20), ...
        'ScheduledAbsoluteSlot',slots(k),'RNTI',73,'UEIndex',1,'ServingCell',1, ...
        'PRBSet',0:5,'SymbolAllocation',[2 10],'Modulation','QPSK', ...
        'NumLayers',layers,'Layers',layers,'NumLogicalPorts',2,'NumRFChains',2, ...
        'TargetCodeRate',cfg.phy.pdsch.codeRate,'MCSIndex',1,'MCSTable','qam64_table1', ...
        'TBSBits',tbs,'RV',rv(k),'IsRetransmission',k>1, ...
        'TransportBlockIdentity',"grant_episode_regression_"+direction+"_r"+string(layers), ...
        'HARQTBContext',struct('OriginalNumLayers',layers), ...
        'PrecodingMatrixLogicalPorts',W,'PrecodingMatrix',W, ...
        'PrecoderNormalizationConvention','unit_frobenius','PrecoderSource','episode_regression');
    g.PHYGrant=sixgr.phy.grant.freezePHYGrant(cfg,direction,g,'Frame',g.Frame,'Slot',g.Slot);
    grants{k}=g;
end
end

function localExpect(callback,id)
caught=false;
try, callback(); catch err, caught=strcmp(err.identifier,id); if ~caught, rethrow(err); end; end
assert(caught,'Expected explicit rejection: %s',id);
end
