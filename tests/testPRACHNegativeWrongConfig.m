function ok = testPRACHNegativeWrongConfig()
%TESTPRACHNEGATIVEWRONGCONFIG Negative wrong-config guard.

setup6GRSimToolkit("Verbose", false);

b = prachStrictAnchorResult();
negT = b.Result.ArtifactTables.prach_negative_trials;
trialT = b.Result.ArtifactTables.prach_trials;
negTrial = trialT(string(trialT.TrialType) == "negative_wrong_root", :);

assert(height(negT) >= 1, "Strict PRACH must export negative wrong-config trials.");
assert(all(~logical(negT.StrictOk) & logical(negT.NegativeExpectedOk)), ...
    "Negative wrong-config trials must fail strict detection but pass negative expectation.");
assert(all(~logical(negTrial.StrictOk)), ...
    "Negative wrong-root waveform trials must never be promoted to strict positives.");
assert(any(contains(string(negT.FailureReason), "wrong_root_sequence")), ...
    "Negative wrong-config evidence must disclose the wrong-root rejection reason.");

ok = true;
end
