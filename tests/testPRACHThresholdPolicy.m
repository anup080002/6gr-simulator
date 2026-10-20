function ok=testPRACHThresholdPolicy()
% Actual generated preamble, explicit receiver-array shape fixtures. This
% tests threshold/metadata authority, not main channel or PFA conformance.
profiles=["lls_causal_access_to_data_wiring_tdd.yaml","lls_causal_access_to_data_wiring.yaml"];
for profile=profiles
    s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios',profile));
    cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
    assert(string(cfg.random_access.detection_threshold_mode)=="auto");
    pc=sixgr.rach.PRACHConfig(cfg);
    occ=sixgr.rach.mapPRACHToOccasion(pc,'OccasionIndex',1);
    tx=sixgr.rach.generatePRACHWaveform(pc,'Occasion',occ,'PreambleIndex',0);
    for nRx=[1 2 4]
        w=repmat(tx.Waveform(:,1),1,nRx)/sqrt(nRx);
        [idx,~,referenceInfo]=nrPRACHDetect(tx.Carrier,tx.PRACH,w,'PreambleIndex',0:63);
        d=sixgr.rach.PRACHDetector(w,pc,'Occasion',occ,'CandidatePreambles',0:63, ...
            'DetectorBackend','toolbox_peak','DetectionThresholdMode','auto');
        assert(~isempty(idx) && d.Detected && d.DetectedPreambleIndex==0);
        assert(d.Threshold==referenceInfo.DetectionThreshold && d.RxAntennaCount==nRx && ...
            d.ThresholdSource=="nrPRACHDetect_default_format_LRA_repetitions_rx_antennas");
        assert(isnan(d.ThresholdBackgroundComponent) && isnan(d.ThresholdGlobalPeakComponent) && ...
            isnan(d.PeakGuardFactor) && isnan(d.TargetFalseAlarmProbability), ...
            'Unused CFAR/background/target values must not be presented as decision inputs.');
        assert(d.ThresholdCalibrationStatus=="single_detection_not_statistical_qualification");
        fixed=sixgr.rach.PRACHDetector(w,pc,'Occasion',occ,'CandidatePreambles',0:63, ...
            'DetectorBackend','toolbox_peak','DetectionThresholdMode','fixed', ...
            'DetectionThreshold',cfg.random_access.detection_threshold);
        assert(fixed.Threshold==cfg.random_access.detection_threshold && ...
            fixed.ThresholdSource=="configured_fixed_nrPRACHDetect");
    end
end
% Exact H4 receiver shape and short-preamble duration. This is a
% deterministic native-threshold check, not a 64-branch fading/PFA campaign.
h4=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios', ...
    'h4_100_cdlc100_connected_impaired_40db_adaptation.yaml'));
h4cfg=sixgr.lls6g.buildInternalConfig(h4,tempname);
pc=sixgr.rach.PRACHConfig(h4cfg,'NumPRACHOccasions',1,'NumTrials',1);
occ=sixgr.rach.mapPRACHToOccasion(pc,'OccasionIndex',1);
tx=sixgr.rach.generatePRACHWaveform(pc,'Occasion',occ,'PreambleIndex',0);
assert(string(tx.PRACH.Format)=="B4" && tx.PRACH.LRA==139 && ...
    tx.PRACH.PRACHDuration==12 && pc.NumRxAntennas==64);
w=repmat(tx.Waveform(:,1),1,pc.NumRxAntennas)/sqrt(pc.NumRxAntennas);
d=sixgr.rach.PRACHDetector(w,pc,'Occasion',occ,'CandidatePreambles',0:63, ...
    'DetectorBackend','toolbox_peak','DetectionThresholdMode','auto');
documented=0.1/sqrt(size(w,2)*double(tx.PRACH.PRACHDuration));
assert(d.Detected && d.DetectedPreambleIndex==0 && ...
    abs(d.Threshold-documented)<1e-15 && ...
    d.RxAntennaCount==64 && d.ThresholdCalibrationStatus=="single_detection_not_statistical_qualification");
fprintf('H4_PRACH_DOCUMENTED_THRESHOLD_PASS format=B4 LRA=139 Nsym=12 RX=64 threshold=%.17g conformance_qualified=0\n',d.Threshold);
fixture=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios', ...
    'lls_causal_tdd_ra_retry_fixture.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(fixture,tempname);
assert(string(cfg.random_access.detection_threshold_mode)=="fixed" && cfg.random_access.detection_threshold==0.5);
assert(string(cfg.lls6g.resolvedConfig.meta.research_class)=="optional_research_experiment");
ok=true; disp('PRACH_THRESHOLD_POLICY_PASS: actual decoder threshold, array dependence, fixed-mode compatibility and honest metadata.');
end
