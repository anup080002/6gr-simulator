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
coordinates = [double(multiT.OccasionFrame), double(multiT.OccasionSlot), ...
    double(multiT.OccasionSymbol), double(multiT.OccasionFrequencyIndex)];
assert(size(unique(coordinates, "rows"), 1) >= 2, ...
    "Multi-occasion evidence must contain distinct absolute PRACH occasions.");
sameWithinFrameCoordinates = all(coordinates(:, 2:4) == coordinates(1, 2:4), 2);
if all(sameWithinFrameCoordinates)
    assert(numel(unique(double(multiT.RARNTI))) == 1, ...
        "TS 38.321 RA-RNTI must repeat across frames when s_id, t_id, f_id and UL carrier are unchanged.");
end

ok = true;
end
