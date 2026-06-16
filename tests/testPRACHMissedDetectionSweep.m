function ok = testPRACHMissedDetectionSweep()
%TESTPRACHMISSEDDETECTIONSWEEP Missed-detection sweep evidence guard.

setup6GRSimToolkit("Verbose", false);

b = prachStrictAnchorResult();
missT = b.Result.ArtifactTables.prach_missed_detection_sweep;
trialT = b.Result.ArtifactTables.prach_trials;
sweepRows = trialT(string(trialT.TrialType) == "missed_detection_sweep", :);

assert(height(missT) >= 2, "Strict PRACH missed-detection sweep must contain multiple SNR points.");
assert(any(double(missT.NumMissed) > 0), "Missed-detection sweep must include measured low-SNR misses.");
assert(any(double(missT.NumDetected) > 0), "Missed-detection sweep must include measured successful detections.");
assert(all(double(missT.DetectionProbability) >= 0 & double(missT.DetectionProbability) <= 1), ...
    "Missed-detection probabilities must be valid probabilities.");
assert(all(~logical(sweepRows.StrictOk)), ...
    "Missed-detection sweep rows must not be promoted to strict positive success.");

ok = true;
end
