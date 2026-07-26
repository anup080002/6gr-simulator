function tests = testPDCCHPolarCodingAndRateMatching()
tests = functiontests(localfunctions);
end
function testProduction(~)
assert(pdcchPhaseCase("testPDCCHPolarCodingAndRateMatching"));
end
