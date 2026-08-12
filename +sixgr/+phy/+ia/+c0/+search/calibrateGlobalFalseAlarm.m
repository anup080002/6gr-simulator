function calibration = calibrateGlobalFalseAlarm(bundle,cfg)
%CALIBRATEGLOBALFALSEALARM Calibrate production global PSS threshold.
nTrials = double(cfg.false_alarm.calibration_trials);
nRx = double(cfg.mimo.num_rx_antennas);
guard = double(cfg.search.timing_uncertainty_samples);
nSamples = size(bundle.Waveform,1)+2*guard;
metrics = zeros(nTrials,1);
seed0 = double(cfg.run.seed_set_calibration);
for trial = 1:nTrials
    old = rng;
    cleanup = onCleanup(@()rng(old)); %#ok<NASGU>
    rng(seed0+trial,"twister");
    noise = (randn(nSamples,nRx)+1j*randn(nSamples,nRx))/sqrt(2);
    search = sixgr.phy.ia.c0.search.runBlindPSSSearch(noise,bundle,cfg);
    metrics(trial) = search.Metric;
end
pfa = double(cfg.false_alarm.target_probability);
sorted = sort(metrics);
allowedExceedances = floor(pfa*nTrials);
if allowedExceedances == 0
    threshold = sorted(end)+max(eps(sorted(end)),1e-12);
else
    lowerIndex = nTrials-allowedExceedances;
    threshold = 0.5*(sorted(lowerIndex)+sorted(lowerIndex+1));
end
calibration = struct( ...
    "Threshold",double(threshold), ...
    "Metrics",metrics, ...
    "TargetPFA",pfa, ...
    "TrialCount",nTrials, ...
    "ExceedanceCount",nnz(metrics>=threshold), ...
    "SeedBase",seed0, ...
    "Statistic","maximum_normalized_pss_correlation_over_timing_cfo_nid2_structure_raster_hypotheses", ...
    "SearchConfigurationHash",string(sixgr.util.sha256Hex(uint8(unicode2native(jsonencode(cfg.search),"UTF-8")))));
end
