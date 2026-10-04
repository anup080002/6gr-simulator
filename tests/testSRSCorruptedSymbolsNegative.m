function ok = testSRSCorruptedSymbolsNegative()
setup6GRSimToolkit("Verbose", false);
localAssertSRSNegative("corrupted_srs_symbols", "srs_channel_estimate_unavailable");
% Reproduce the sparse wide-carrier configuration that the retained
% richness diagnostic unexpectedly accepted. Keep its receiver thresholds.
scenario=sixgr.lls6g.config.loadScenarioConfig(fullfile(pwd,'simulator', ...
    'configs','fixtures','lls_result_richness.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(scenario,tempname);
srsCfg=sixgr.phy.srs.buildSRSConfigFromScenario(cfg);
tx=sixgr.phy.srs.generateSRSWaveform(srsCfg);
rx=sixgr.phy.srs.applySRSChannel(tx,srsCfg,'FaultMode','corrupted_symbols', ...
    'SNRdB',max(35,srsCfg.HighSNRdB),'Seed',26007);
det=sixgr.phy.srs.detectSRSFromULGrid(rx,srsCfg);
ch=sixgr.phy.srs.estimateULChannelFromSRS(det,srsCfg);
timing=sixgr.phy.srs.estimateSRSDelayTiming(rx,tx,srsCfg);
score=sixgr.phy.srs.scoreSRSDetection(srsCfg,rx,det,ch,timing, ...
    'TrialType','corrupted_srs_symbols','NegativeExpected',true);
assert(~score.StrictOk && score.TrialRow.NegativeExpectedOk && ...
    contains(score.TrialRow.FailureReason,'srs_channel_estimate_unavailable'), ...
    'Sparse wide-carrier SRS symbol corruption must remain a rejected physical observation.');
fprintf('SRS_WIDE_CORRUPTION metric=%.9g threshold=%.9g model=%s rejected=%d\n', ...
    det.DetectionMetric,srsCfg.DetectionThreshold,rx.FaultModel,~score.StrictOk);
ok = true;
end
