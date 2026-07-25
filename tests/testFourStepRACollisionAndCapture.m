function tests = testFourStepRACollisionAndCapture
%TESTFOURSTEPRACOLLISIONANDCAPTURE Composite PRACH/Msg3 contention.
tests = functiontests(localfunctions);
end

function testNearFarSamePreambleCapture(testCase)
cfg = raStrictAnchorConfig();
actual = sixgr.phy.ra.runFourStepRAContentionGroup(cfg, ...
    "UEIds", [1 2], "PreambleIndices", [7 7], ...
    "RelativePowersdB", [0 -20], "SNRdB", 35, "Seed", 41001);
verifyTrue(testCase, actual.Resolved);
verifyTrue(testCase, actual.Groups.SamePreambleCollision);
verifyTrue(testCase, actual.Groups.CaptureDetected);
verifyTrue(testCase, actual.Groups.CapturedStrongest);
verifyEqual(testCase, actual.Groups.DecodedUEID, 1);
verifyEqual(testCase, nnz(actual.UEs.ContentionResolved), 1);
verifyEqual(testCase, actual.ExecutionBackend, ...
    "composite_PRACH_and_PUSCH_Tx/PUSCH_Rx");
end

function testDifferentPreamblesSeparate(testCase)
cfg = raStrictAnchorConfig();
actual = sixgr.phy.ra.runFourStepRAContentionGroup(cfg, ...
    "UEIds", [1 2], "PreambleIndices", [7 8], ...
    "RelativePowersdB", [0 0], "SNRdB", 35, "Seed", 41002);
verifyTrue(testCase, actual.Resolved);
verifyEqual(testCase, height(actual.Groups), 2);
verifyFalse(testCase, any(actual.Groups.SamePreambleCollision));
verifyTrue(testCase, all(actual.Groups.Msg3CRC));
verifyTrue(testCase, all(actual.UEs.ContentionResolved));
end
