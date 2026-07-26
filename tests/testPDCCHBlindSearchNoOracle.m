function tests = testPDCCHBlindSearchNoOracle()
tests = functiontests(localfunctions);
end
function testProduction(~)
assert(pdcchPhaseCase("testPDCCHBlindSearchNoOracle"));
end
