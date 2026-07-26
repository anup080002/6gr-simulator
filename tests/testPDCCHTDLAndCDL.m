function tests = testPDCCHTDLAndCDL()
tests = functiontests(localfunctions);
end
function testProduction(~)
assert(pdcchPhaseCase("testPDCCHTDLAndCDL"));
end
