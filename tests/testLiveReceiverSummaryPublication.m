function ok=testLiveReceiverSummaryPublication(sourceFolder,outputFolder)
% Declared reducer fixtures, optionally followed by original receiver replay.
% No waveform, channel, RF or scenario execution occurs in this test.
if nargin<1, sourceFolder=""; end
if nargin<2, outputFolder=""; end
root=tempname; mkdir(root);
cleanup=onCleanup(@()rmdir(root,'s')); %#ok<NASGU>
cfg=sixgr.config.defaultConfig(); cfg.run.totalSlots=4;
cfg.channel.model="AWGN"; cfg.channel.awgnOnly=true;
empty=sixgr.truth.exportLLSLiveDerivedTables(cfg,root,struct(),struct(),struct(),struct(),"receiver_observations");
assert(empty.SchedulerReconciliation.DL_GrantCount==0 && isempty(empty.LinkAdaptationInput));
dl=localTrial("DL",[1;2],[1;0]); ul=localTrial("UL",3,NaN);
ul.PostEqSINR_dB(:)=NaN; % No measured quality from which CQI can be derived.
raw=struct('DL',dl,'UL',ul);
before=raw;
a=sixgr.truth.exportLLSLiveDerivedTables(cfg,root,raw,struct(),struct(),struct(),"receiver_observations");
assert(isequaln(before,raw),'Publication must not mutate its source rows.');
assert(a.DLReceiverRows==2 && a.ULReceiverRows==1 && height(a.LinkAdaptationInput)==3);
assert(a.SchedulerReconciliation.DL_GrantCount==2 && a.SchedulerReconciliation.UL_GrantCount==1);
assert(a.SchedulerReconciliation.DL_BLER==.5 && isnan(a.SchedulerReconciliation.UL_BLER));
assert(a.SchedulerReconciliation.UL_CRCUnknownTrials==1 && ~a.SchedulerReconciliation.SchedulerKpiReconciliationOk);
assert(~isempty(a.RankEstimationStats) && ~isempty(a.ChannelEstimationStats));
assert(all(isnan(a.LinkAdaptationInput.WidebandCQI(a.LinkAdaptationInput.Direction=="UL"))), ...
    'Missing CQI without measured quality must remain missing.');
assert(all(a.LinkAdaptationInput.CQIValueStatus(a.LinkAdaptationInput.Direction=="DL")== ...
    "legacy_row_backfill_from_measured_receiver_evidence"), ...
    'Any diagnostic CQI derivation must retain its measured-evidence label.');
expectedCQI=sixgr.link.resolveWidebandCQI(struct('WidebandSINR_dB',10, ...
    'SINRSource','PostEqSINR_dB','SINRValueRole','measured_post_equalization_scheduling_input', ...
    'SINRValueStatus','OK'),cfg,"DL");
isDL=a.LinkAdaptationInput.Direction=="DL";
assert(all(a.LinkAdaptationInput.WidebandCQI(isDL)==expectedCQI.WidebandCQI) && ...
    all(a.LinkAdaptationInput.CQIValueSource(isDL)=="derived_from_PostEqSINR_dB") && ...
    all(a.LinkAdaptationInput.SchedulerConsumptionStatus=="not_recorded_by_trial"), ...
    'Diagnostic CQI mapping must not imply received feedback or scheduler consumption.');
assert(~isfile(fullfile(root,'reports','csv','channel_impulse_response.csv')) && ...
    ~isfile(fullfile(root,'reports','csv','antenna_config_resolved.csv')) && ...
    ~isfile(fullfile(root,'reports','csv','live_user_performance_snapshot.csv')) && ...
    ~isfile(fullfile(root,'harq','csv','live_harq_observation_timeline.csv')), ...
    'Receiver refresh must not run heavy/static work or duplicate runtime-owned publication.');
full=sixgr.truth.exportLLSLiveDerivedTables(cfg,root,raw,struct(),struct(),struct());
for name=["ChannelEstimationStats","ChannelNMSEPopulationSummary","ChannelNMSESourceAudit", ...
        "RankEstimationStats","CSIFeedbackStats","CSISelectionObservations","CSIRSStats", ...
        "LinkAdaptationInput","SymbolThroughput","ErrorRateSummary","AntennaRuntimeEvidence"]
    assert(isequaln(a.(name),full.(name)), 'Compact/full receiver projections differ: %s',name);
end
assert(isequaln(a.SchedulerReconciliation,full.RFInterferenceReconciliation.Tables.Scheduler));
if strlength(string(sourceFolder))>0
    localRetained(sourceFolder,outputFolder);
end
ok=true; disp('LIVE_RECEIVER_SUMMARY_PUBLICATION_PASS RF_executions=0');
end

function T=localTrial(direction,slots,crc)
n=numel(slots);
T=table(repmat(direction,n,1),slots(:),ones(n,1),ones(n,1),crc(:), ...
    repmat(608,n,1),repmat(.5,n,1),repmat(20,n,1),repmat(10,n,1), ...
    ones(n,1),ones(n,1),zeros(n,1),zeros(n,1),repmat(2,n,1),repmat(12,n,1), ...
    'VariableNames',{'Direction','Slot','Frame','UEIndex','CRCPass','TBSize_bits', ...
    'AirInterfaceTTI_ms','SNR_dB','PostEqSINR_dB','Layers','FinalizedFlag', ...
    'FallbackFlag','IsWarmupFrame','SymbolStart','NumSymbols'});
T.LogicalTBID=direction+"_declared_TB_"+string(slots(:));
T.GoodBits=608*crc(:); T.WidebandCQI=nan(n,1); T.MCSIndex=ones(n,1);
end

function localRetained(sourceFolder,outputFolder)
assert(strlength(string(outputFolder))>0 && ~isfolder(outputFolder) && ~isfile(outputFolder), ...
    'Retained replay requires a new separate output directory.');
layout=sixgr.report.resultLayout(sourceFolder);
paths=string(fullfile(layout.AirInterfaceCSVDir, ...
    {'dl_pdsch_trials.csv','ul_pusch_trials.csv','srs_trials.csv','trs_trials.csv','csi_rs_trials.csv'}));
paths=paths(isfile(paths)); hashes=strings(size(paths));
for k=1:numel(paths), hashes(k)=sixgr.util.sha256File(paths(k)); end
data=sixgr.analytics.loadAllTrialData(sourceFolder);
raw=struct('DL',data.dl,'UL',data.ul,'SRS',data.srs,'TRS',data.trs);
csiPath=fullfile(layout.AirInterfaceCSVDir,'csi_rs_trials.csv');
if isfile(csiPath), raw.CSIRS=sixgr.util.csvReadTable(csiPath); end
scfg=sixgr.lls6g.config.loadScenarioConfig(fullfile(sourceFolder,'meta','scenario_config_resolved.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(scfg,outputFolder);
% Preserve existing row identities; no new execution UUID is installed.
original=raw;
a=sixgr.truth.exportLLSLiveDerivedTables(cfg,outputFolder,raw,struct(),struct(),struct(),"receiver_observations");
assert(isequaln(raw,original) && a.DLReceiverRows==height(data.dl) && a.ULReceiverRows==height(data.ul));
assert(height(a.LinkAdaptationInput)==height(data.dl)+height(data.ul));
expected=sixgr.analytics.buildSchedulerKPIReconciliation(data.dl,data.ul,cfg);
assert(isequaln(a.SchedulerReconciliation,expected));
for k=1:numel(paths), assert(string(sixgr.util.sha256File(paths(k)))==hashes(k)); end
sixgr.util.jsonWrite(fullfile(outputFolder,'receiver_summary_replay.json'), ...
    struct('SourceFolder',string(sourceFolder),'OriginalPaths',paths,'OriginalSHA256',hashes, ...
    'DLRows',height(data.dl),'ULRows',height(data.ul),'RFExecutions',0,'FullRunQualified',false));
end
