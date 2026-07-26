function tests = testPDCCHWrongFormatAndSize()
tests = functiontests(localfunctions);
end
function testProduction(~)
assert(pdcchPhaseCase("testPDCCHWrongFormatAndSize"));
end
