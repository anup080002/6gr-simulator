function tests = testMsg3HARQ
%TESTMSG3HARQ Waveform-backed Msg3 RV/NDI/soft-buffer lineage.
tests = functiontests(localfunctions);
end

function testHighSNRCompletesWithLineage(testCase)
cfg = raStrictAnchorConfig();
actual = sixgr.phy.ra.runMsg3HARQ(cfg, ...
    "SNRdB", 35, "RVSequence", [0 2 3 1], ...
    "Seed", 31001, "StopOnSuccess", true);
verifyTrue(testCase, actual.Completed);
verifyTrue(testCase, all(actual.Rounds.CRC));
verifyEqual(testCase, actual.Rounds.NDI, ...
    ones(height(actual.Rounds), 1));
verifyTrue(testCase, all(strlength( ...
    actual.Rounds.TBIdentitySHA256) == 64));
verifyTrue(testCase, all(strlength( ...
    actual.Rounds.RRCSetupRequestSHA256) == 64));
verifyTrue(testCase, all(strlength( ...
    actual.Rounds.SoftBufferSHA256) == 64));
verifyEqual(testCase, actual.ExecutionBackend, ...
    "PUSCH_Tx/PUSCH_Rx/UL-SCH");
verifyFalse(testCase, actual.ProxyUsed);
verifyFalse(testCase, actual.FallbackUsed);
end
