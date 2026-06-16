function ok = testPRACHMultiOccasionRARNTI()
%TESTPRACHMULTIOCCASIONRARNTI Multi-occasion PRACH and RA-RNTI evidence.

setup6GRSimToolkit("Verbose", false);

b = prachStrictAnchorResult();
multiT = b.Result.ArtifactTables.prach_multi_occasion_trials;
assert(height(multiT) >= 2, "Strict PRACH multi-occasion sweep must contain multiple occasions.");
assert(all(logical(multiT.DetectedOnCorrectOccasion)), ...
    "Multi-occasion PRACH detections must bind to the correct occasion.");
assert(all(isfinite(double(multiT.RARNTI)) & double(multiT.RARNTI) >= 1), ...
    "Multi-occasion PRACH rows must export finite RA-RNTI values.");
assert(numel(unique(double(multiT.OccasionSlot))) >= 2 || numel(unique(double(multiT.RARNTI))) >= 2, ...
    "Multi-occasion evidence must vary either occasion slot or derived RA-RNTI.");

ok = true;
end
