function testDLMUMIMOReceiverEvidence
%TESTDLMUMIMORECEIVEREVIDENCE Guard measured DL MU receiver semantics.

T = table();
T.Direction = ["DL"; "DL"];
T.MUMIMOEnabled = [true; false];
T.MUMIMOGroupSize = [2; 1];
T.InterferenceContributorCount = [1; 0];
T.FullInterfererChannelTruthUsed = [true; false];
T.InterferenceCovarianceAvailable = [true; false];
T.InterferenceCovarianceSource = [ ...
    "oracle_separated_shared_slot_per_prb_symbol_contribution_grid_covariance"; ...
    "not_applicable"];
T.EqualizationAvailable = [true; true];
T.EqualizerType = ["MMSE-IRC"; "MMSE"];
T.EqualizerEngine = ["sixgr.phy.rx.nrEqualizeMMSEIRC"; "sixgr.phy.rx.nrEqualizeMMSE"];
T.MUMIMOReceiveCombinerApplied = [false; false];

actual = sixgr.link.applyMeasuredDLMUMIMOReceiverEvidence(T);
assert(actual.MUMIMOReceiveProcessingApplied(1));
assert(actual.MUMIMOReceiveProcessingStatus(1) == ...
    "applied_oracle_separated_shared_slot_covariance_resource_selective_per_re_mmse_irc");
assert(actual.MUMIMOReceiveProcessingModeApplied(1) == ...
    "resource_selective_per_re_mmse_irc");
assert(actual.MUMIMOReceiverAlgorithmApplied(1) == "MMSE-IRC");
assert(~actual.MUMIMOReceiveCombinerApplied(1));
assert(startsWith(actual.MUMIMOReceiveCombinerStatus(1), "not_applicable_"));
assert(~actual.MUMIMOReceiveProcessingApplied(2));
assert(actual.MUMIMOReceiveProcessingStatus(2) == "not_applicable_mu_mimo_disabled");

bad = T(1, :);
bad.InterferenceCovarianceAvailable(:) = false;
threw = false;
try
    sixgr.link.applyMeasuredDLMUMIMOReceiverEvidence(bad);
catch ME
    threw = strcmp(ME.identifier, ...
        "sixgr:link:MissingMeasuredDLMUMIMOReceiverEvidence");
end
assert(threw, "Missing covariance-backed DL MU receiver evidence must fail closed.");

fprintf("testDLMUMIMOReceiverEvidence passed.\n");
end
