function diagnoseSharedPRACHReceiveGuard()
% Actual PRACH code/modulation/detection with explicit analytic delays.
% Receiver-origin diagnostic only: no channel or main-run qualification.
s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios', ...
    'lls_causal_access_to_data_wiring_tdd.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
ra=sixgr.mac.ra.RAConfig(cfg,'RuntimeSlot',15);
[tx,occasion]=sixgr.phy.ra.generateMsg1PRACHWaveform(cfg,ra);
fprintf('PRACH_RX_ORIGIN_DIAGNOSTIC fs=%g preamble=%g format=%s samples=%g\n', ...
    tx.SampleRate_Hz,ra.PreambleIndex,string(tx.Format),size(tx.Waveform,1));
pc=sixgr.phy.ra.buildPRACHConfigFromRACHCommon(cfg,ra);
for delay=[0 7 77 84 85 100]
    x=[zeros(delay,size(tx.Waveform,2),'like',tx.Waveform);tx.Waveform];
    det=sixgr.rach.PRACHDetector(x,pc,'Occasion',occasion,'CandidatePreambles',0:63, ...
        'DetectorBackend','toolbox_peak','DetectionThresholdMode','fixed','DetectionThreshold',.02);
    fprintf('explicit_delay=%g detected=%d decoded_preamble=%g raw_offset=%g\n', ...
        delay,det.Detected,det.DetectedPreambleIndex,det.TimingOffsetSamples);
end
end
