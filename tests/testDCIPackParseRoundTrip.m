function tests = testDCIPackParseRoundTrip()
tests = functiontests(localfunctions);
end
function testProduction(~)
assert(pdcchPhaseCase("testDCIPackParseRoundTrip"));
end
