function tests = testPDCCHBlindSearchAllAL()
tests = functiontests(localfunctions);
end
function testProduction(~)
assert(pdcchPhaseCase("testPDCCHBlindSearchAllAL"));
end
