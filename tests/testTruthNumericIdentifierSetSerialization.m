function ok = testTruthNumericIdentifierSetSerialization()
%TESTTRUTHNUMERICIDENTIFIERSETSERIALIZATION Preserve only applicable IDs.

setup6GRSimToolkit("Verbose", false);

assert(sixgr.truth.serializeFiniteNumericIdentifierSet([1 2 7]) == "1|2|7", ...
    "Finite runtime identities must retain their exact order and values.");
assert(sixgr.truth.serializeFiniteNumericIdentifierSet([0 NaN 3 Inf]) == "0|3", ...
    "Non-applicable/non-finite identities must be omitted without imputation.");
assert(sixgr.truth.serializeFiniteNumericIdentifierSet(NaN) == "", ...
    "CSI UCI without a HARQ process must serialize an empty process set.");
assert(sixgr.truth.serializeFiniteNumericIdentifierSet([]) == "", ...
    "An empty runtime identity set must remain empty.");

didThrow = false;
try
    sixgr.truth.serializeFiniteNumericIdentifierSet("1");
catch ME
    didThrow = strcmp(ME.identifier, "sixgr:truth:IdentifierSetType");
end
assert(didThrow, ...
    "Text identifiers must fail closed instead of being silently coerced.");

ok = true;
fprintf("testTruthNumericIdentifierSetSerialization: PASS\n");
end
