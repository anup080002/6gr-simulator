function tuning = resolveWaveformBundleRuntimeTuning(scfg, cfg, snrGrid)
%RESOLVEWAVEFORMBUNDLERUNTIMETUNING Bound oversized truth runs sanely.

if nargin < 3
    snrGrid = [];
end

numUsers = max(1, round(double(scfg.get("users.n_users", 1))));
requestedFrames = max(1, round(double(sixgr.util.structGet(cfg, "run.numFrames", 1))));
mcIterations = max(1, round(double(scfg.get("simulation.monte_carlo_iterations", 1))));
requestedPrimaryTrials = max(requestedFrames, requestedFrames * mcIterations);
requestedReferenceTrials = max(requestedPrimaryTrials, ceil(1.5 * requestedPrimaryTrials));
snrPointCount = max(1, numel(unique(sort(double(snrGrid(:))))));
requestedRawRowsPerSweep = 2 * numUsers * requestedPrimaryTrials;

tuning = struct();
tuning.Policy = "default_truth_runtime";
tuning.AutoTuned = false;
tuning.NumUsers = double(numUsers);
tuning.RequestedPrimaryTrialsPerSNR = double(requestedPrimaryTrials);
tuning.PrimaryTrialsPerSNR = double(requestedPrimaryTrials);
tuning.RequestedReferenceTrialsPerSNR = double(requestedReferenceTrials);
tuning.ReferenceTrialsPerSNR = double(requestedReferenceTrials);
tuning.RequestedRawRowsPerSweep = double(requestedRawRowsPerSweep);
tuning.RawRowsPerSweep = double(requestedRawRowsPerSweep);
tuning.RawRowsAcrossAllSweeps = double(requestedRawRowsPerSweep * snrPointCount);
tuning.ReferenceSweepEnabled = true;
tuning.HARQDiagnosticsEnabled = true;
tuning.AdaptiveSweepEnabled = true;
tuning.AdaptiveSweepStep_dB = 2;
tuning.AdaptiveSweepMaxPoints = 12;
tuning.MaxRawRowsPerSweep = NaN;
tuning.Notes = "";

if requestedRawRowsPerSweep <= 4096
    return;
end

if numUsers >= 64
    maxRawRowsPerSweep = 2048;
elseif numUsers >= 32
    maxRawRowsPerSweep = 3072;
else
    maxRawRowsPerSweep = 4096;
end

tunedPrimaryTrials = max(8, floor(maxRawRowsPerSweep / max(2 * numUsers, 1)));
tunedPrimaryTrials = min(requestedPrimaryTrials, tunedPrimaryTrials);
tunedPrimaryTrials = max(8, tunedPrimaryTrials);

tuning.Policy = "large_multiuser_truth_runtime";
tuning.AutoTuned = tunedPrimaryTrials < requestedPrimaryTrials || numUsers >= 32;
tuning.PrimaryTrialsPerSNR = double(tunedPrimaryTrials);
tuning.ReferenceTrialsPerSNR = double(max(tunedPrimaryTrials, min(requestedReferenceTrials, 16)));
tuning.RawRowsPerSweep = double(2 * numUsers * tunedPrimaryTrials);
tuning.RawRowsAcrossAllSweeps = double(tuning.RawRowsPerSweep * snrPointCount);
tuning.MaxRawRowsPerSweep = double(maxRawRowsPerSweep);
tuning.AdaptiveSweepEnabled = numUsers < 16;

if numUsers >= 32
    tuning.ReferenceSweepEnabled = false;
    tuning.HARQDiagnosticsEnabled = false;
    tuning.AdaptiveSweepEnabled = false;
    tuning.ReferenceTrialsPerSNR = 0;
end

noteParts = strings(0, 1);
if tunedPrimaryTrials < requestedPrimaryTrials
    noteParts(end+1, 1) = "reduced_primary_trials_per_snr_to_" + string(tunedPrimaryTrials); %#ok<AGROW>
end
if ~tuning.ReferenceSweepEnabled
    noteParts(end+1, 1) = "disabled_reference_sweep"; %#ok<AGROW>
end
if ~tuning.HARQDiagnosticsEnabled
    noteParts(end+1, 1) = "disabled_harq_diagnostics"; %#ok<AGROW>
end
if ~tuning.AdaptiveSweepEnabled
    noteParts(end+1, 1) = "disabled_adaptive_refinement"; %#ok<AGROW>
end
if ~isempty(noteParts)
    tuning.Notes = strjoin(noteParts, ", ");
end
end
