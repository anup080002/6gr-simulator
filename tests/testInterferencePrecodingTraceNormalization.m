function ok = testInterferencePrecodingTraceNormalization()
%TESTINTERFERENCEPRECODINGTRACENORMALIZATION Preserve multi-contributor truth.

replay = struct( ...
    "InterfererBeamformingAppliedCount", [1 0 1], ...
    "InterfererExplicitBeamWeightCount", [0 1 0], ...
    "InterfererTransformPrecodingCount", [1 1 0], ...
    "InterfererPrecoderSourceSet", ["codebook|measured" "codebook"], ...
    "InterfererPrecodingModeSet", ["tpmi" "transform"], ...
    "InterfererBeamIndexSetSummary", ["1|3" "3|5"]);
trace = sixgr.link.resolveInterferencePrecodingTrace(replay);
assert(trace.InterfererBeamformingAppliedCount == 2);
assert(trace.InterfererExplicitBeamWeightCount == 1);
assert(trace.InterfererTransformPrecodingCount == 2);
assert(string(trace.InterfererPrecoderSourceSet) == "codebook|measured");
assert(string(trace.InterfererPrecodingModeSet) == "tpmi|transform");
assert(string(trace.InterfererBeamIndexSetSummary) == "1|3|5");

localAssertIdentifier(@() sixgr.link.resolveInterferencePrecodingTrace( ...
    struct("InterfererBeamformingAppliedCount", [1 -1])), ...
    "sixgr:link:InvalidInterferenceCountEvidence");
ok = true;
end

function localAssertIdentifier(fn, expected)
try
    fn();
catch ME
    assert(string(ME.identifier) == string(expected), ...
        "Expected %s, got %s: %s", expected, ME.identifier, ME.message);
    return;
end
error("sixgr:test:ExpectedErrorNotRaised", ...
    "Expected error %s was not raised.", expected);
end
