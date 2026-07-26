function tests = testPDCCHDMRS()
tests = functiontests(localfunctions);
end
function testProduction(~)
assert(pdcchPhaseCase("testPDCCHDMRS"));
end
