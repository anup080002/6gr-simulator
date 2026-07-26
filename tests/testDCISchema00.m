function tests = testDCISchema00()
tests = functiontests(localfunctions);
end
function testProduction(~)
assert(pdcchPhaseCase("testDCISchema00"));
end
