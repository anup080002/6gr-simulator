function tests = testFourStepRAMultiAttempt
%TESTFOURSTEPRAMULTIATTEMPT Production retry, ramping and terminal bounds.
tests = functiontests(localfunctions);
end

function testMissThenComplete(testCase)
cfg = raStrictAnchorConfig();
actual = sixgr.phy.ra.runFourStepRAMultiAttempt(cfg, ...
    "AttemptFaults", {"no_prach_detected","none"}, ...
    "BackoffIndicatorMs", 20, ...
    "UniformDraws", [0.5 0.25], ...
    "WriteArtifacts", false);
verifyTrue(testCase, actual.Completed);
verifyEqual(testCase, actual.AttemptsUsed, 2);
verifyGreaterThan(testCase, ...
    actual.AttemptSummary.AppliedTxPower_dBm(2), ...
    actual.AttemptSummary.AppliedTxPower_dBm(1));
winner = actual.AttemptResults{2};
verifyTrue(testCase, winner.RACompleted);
verifyTrue(testCase, winner.RRCConnected);
verifyFalse(testCase, actual.ProxyUsed);
verifyFalse(testCase, actual.FallbackUsed);
end

function testPreambleTransMaxStops(testCase)
cfg = raStrictAnchorConfig();
cfg.random_access.preamble_trans_max = 1;
actual = sixgr.phy.ra.runFourStepRAMultiAttempt(cfg, ...
    "AttemptFaults", {"no_prach_detected"}, ...
    "WriteArtifacts", false);
verifyFalse(testCase, actual.Completed);
verifyTrue(testCase, actual.PreambleTransMaxReached);
verifyEqual(testCase, actual.AttemptsUsed, 1);
end
