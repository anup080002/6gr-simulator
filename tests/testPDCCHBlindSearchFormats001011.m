function tests = testPDCCHBlindSearchFormats001011()
tests = functiontests(localfunctions);
end
function testProduction(~)
assert(pdcchPhaseCase("testPDCCHBlindSearchFormats001011"));
end
