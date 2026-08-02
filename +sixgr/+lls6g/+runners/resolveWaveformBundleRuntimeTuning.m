function tuning = resolveWaveformBundleRuntimeTuning(scfg, cfg, snrGrid)
%RESOLVEWAVEFORMBUNDLERUNTIMETUNING Resolve exact YAML-owned truth runtime.

if nargin < 3
    snrGrid = [];
end

numUsers = max(1, round(double(scfg.get("users.n_users", 1))));
requestedSlots = max(1, round(double(sixgr.util.structGet(cfg, "run.totalSlots", ...
    sixgr.util.structGet(cfg, "run.numTTI", sixgr.util.structGet(cfg, "run.numFrames", 1))))));
mcIterations = max(1, round(double(scfg.get("simulation.monte_carlo_iterations", 1))));
requestedPrimaryTrials = requestedSlots * mcIterations;
referenceSweepEnabled = logical(sixgr.util.structGet(cfg, ...
    "run.referenceSweepEnabled", false));
sixgr.config.assertRuntimeFeatureUse(cfg, "reference_sweep", ...
    referenceSweepEnabled, "resolveWaveformBundleRuntimeTuning");
requestedReferenceTrials = round(double(sixgr.util.structGet(cfg, ...
    "run.referenceTrialsPerSNR", NaN)));
if ~referenceSweepEnabled
    requestedReferenceTrials = 0;
elseif requestedReferenceTrials < 1
    error("sixgr:lls6g:InvalidReferenceSweepTrials", ...
        "simulation.reference_trials_per_snr must be at least 1 when reference_sweep_enabled=true.");
end
harqDiagnosticsEnabled = logical(sixgr.util.structGet(cfg, ...
    "run.harqDiagnosticsEnabled", false));
sixgr.config.assertRuntimeFeatureUse(cfg, "harq_diagnostics", ...
    harqDiagnosticsEnabled, "resolveWaveformBundleRuntimeTuning");
adaptiveSweepEnabled = logical(sixgr.util.structGet(cfg, ...
    "run.adaptiveSweepEnabled", false));
sixgr.config.assertRuntimeFeatureUse(cfg, "adaptive_sweep", ...
    adaptiveSweepEnabled, "resolveWaveformBundleRuntimeTuning");
adaptiveSweepStep_dB = double(sixgr.util.structGet(cfg, ...
    "run.adaptiveSweepStep_dB", NaN));
adaptiveSweepMaxPoints = round(double(sixgr.util.structGet(cfg, ...
    "run.adaptiveSweepMaxPoints", NaN)));
maxRawRowsPerSweep = round(double(sixgr.util.structGet(cfg, ...
    "run.maxRawRowsPerSweep", NaN)));
if adaptiveSweepEnabled && adaptiveSweepMaxPoints < 1
    error("sixgr:lls6g:InvalidAdaptiveSweepPoints", ...
        "simulation.adaptive_sweep_max_points must be at least 1 when adaptive_sweep_enabled=true.");
end
snrPointCount = max(1, numel(unique(sort(double(snrGrid(:))))));
requestedRawRowsPerSweep = 2 * numUsers * requestedPrimaryTrials;

if maxRawRowsPerSweep > 0 && requestedRawRowsPerSweep > maxRawRowsPerSweep
    error("sixgr:lls6g:RuntimeRowBudgetExceeded", ...
        "The YAML requests %d raw DL/UL rows per SNR point, exceeding " + ...
        "simulation.max_raw_rows_per_sweep=%d. Increase that YAML limit, reduce users.n_users, " + ...
        "simulation.n_slots, or simulation.monte_carlo_iterations. MATLAB will not auto-reduce a truth run.", ...
        requestedRawRowsPerSweep, maxRawRowsPerSweep);
end

tuning = struct();
tuning.Policy = "yaml_exact_truth_runtime";
tuning.AutoTuned = false;
tuning.NumUsers = double(numUsers);
tuning.RequestedPrimaryTrialsPerSNR = double(requestedPrimaryTrials);
tuning.PrimaryTrialsPerSNR = double(requestedPrimaryTrials);
tuning.RequestedReferenceTrialsPerSNR = double(requestedReferenceTrials);
tuning.ReferenceTrialsPerSNR = double(requestedReferenceTrials);
tuning.RequestedRawRowsPerSweep = double(requestedRawRowsPerSweep);
tuning.RawRowsPerSweep = double(requestedRawRowsPerSweep);
tuning.RawRowsAcrossAllSweeps = double(requestedRawRowsPerSweep * snrPointCount);
tuning.ReferenceSweepEnabled = referenceSweepEnabled;
tuning.HARQDiagnosticsEnabled = harqDiagnosticsEnabled;
tuning.AdaptiveSweepEnabled = adaptiveSweepEnabled;
tuning.AdaptiveSweepStep_dB = adaptiveSweepStep_dB;
tuning.AdaptiveSweepMaxPoints = double(adaptiveSweepMaxPoints);
if maxRawRowsPerSweep == 0
    tuning.MaxRawRowsPerSweep = NaN;
else
    tuning.MaxRawRowsPerSweep = double(maxRawRowsPerSweep);
end
tuning.Notes = "exact_yaml_runtime_no_auto_reduction";
end
