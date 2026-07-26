function tests = testDCIContextValidation()
tests = functiontests(localfunctions);
end
function testProduction(~)
assert(pdcchPhaseCase("testDCIContextValidation"));
end
