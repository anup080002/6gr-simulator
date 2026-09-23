function ok=test5MHzOutagePublication()
% Negative-acquisition runtime regression, not successful-link acceptance.
setup6GRSimToolkit('Verbose',false);
scfg=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_5mhz_outage_publication_fixture.yaml');
parent=fullfile(pwd,'results','lls','outage_publication_component');
sixgr.util.ensureFolder(parent);
root=tempname(parent);
cfg=sixgr.lls6g.buildInternalConfig(scfg,root);
opt=struct('LinkSNR_dB',cfg.channel.snr_dB,'LinkSNRGrid_dB',cfg.channel.snr_dB, ...
    'LinkMaxSimFrames',scfg.get('run_control.total_slots'), ...
    'LinkDuration_s',scfg.get('simulation.min_duration_s'),'SaveFigures',false);
out=sixgr.truth.runWaveformLinkBundle(cfg,fullfile(root,'air_interface'),opt);
raw=out.RawTrials;
assert(isempty(raw.DL) && isempty(raw.UL),'No data trial may be invented during acquisition outage.');
B=raw.PBCH;
assert(~isempty(B) && all(~B.CRCPass) && all(~B.SSBIdentityVerified) && ...
    all(~B.SelectedBeamFlag) && all(isnan(B.SSBIndex)));
assert(all(isfinite(B.ObservationStartSample)) && ...
    all(B.ObservationEndSampleExclusive>B.ObservationStartSample) && ...
    all(B.ObservationCompletionTime_s==B.ObservationEndSampleExclusive./B.ObservationSampleRateHz));
assert(~any(B.Crash),'Acquisition outage is not a row-conversion exception.');
T=readtable(fullfile(root,'reports','csv','live_waveform_preview.csv'),'TextType','string');
assert(~isempty(T) && all(T.ObservationKind=="broadcast_window") && ...
    all(T.Source=="completed_shared_waveform_observation_buffers"));
assert(any(T.TxMagnitude>0) && any(T.RxMagnitude>0));
assert(isempty(raw.CoupledRuntime.SharedWaveformStream.DataTransmissions));
outage=sixgr.link.classifyCompletedAcquisitionOutage(raw,scfg.get('run_control.total_slots'));
assert(outage.Recognized && ~outage.ScenarioPass && ~outage.DataBLERAvailable && ...
    ~outage.DataConstellationAvailable && outage.PBCHAttempts==height(B));
bad=raw; bad.PBCH.CRCPass=double(bad.PBCH.CRCPass); bad.PBCH.CRCPass(1)=NaN;
assert(~sixgr.link.classifyCompletedAcquisitionOutage(bad,8).Recognized);
bad=raw; bad.PBCH.CRCPass(1)=1;
assert(~sixgr.link.classifyCompletedAcquisitionOutage(bad,8).Recognized);
bad=raw; bad.PBCH.ObservationStartSample(1)=NaN;
assert(~sixgr.link.classifyCompletedAcquisitionOutage(bad,8).Recognized);
bad=raw; bad.PBCH=table();
assert(~sixgr.link.classifyCompletedAcquisitionOutage(bad,8).Recognized);
bad=raw; bad.DL=table(NaN,'VariableNames',{'CRCPass'});
assert(~sixgr.link.classifyCompletedAcquisitionOutage(bad,8).Recognized);
bad=raw; bad.CoupledRuntime.SlotTraceTable(end,:)=[];
assert(~sixgr.link.classifyCompletedAcquisitionOutage(bad,8).Recognized);
bad=raw; bad.CoupledRuntime.SlotTraceTable.ULGrantCount(1)=1;
assert(~sixgr.link.classifyCompletedAcquisitionOutage(bad,8).Recognized);
assert(~sixgr.link.classifyCompletedAcquisitionOutage(raw,9).Recognized);
fprintf('FIVE_MHZ_OUTAGE_PUBLICATION_PASS pbch_rows=%d waveform_rows=%d data_trials=0 folder=%s\n', ...
    height(B),height(T),root);
ok=true;
end
