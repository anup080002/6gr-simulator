function tests = testPDCCHRNTIProcedureMatrix()
tests = functiontests(localfunctions);
end
function testProduction(~)
assert(pdcchPhaseCase("testPDCCHRNTIProcedureMatrix"));
end
