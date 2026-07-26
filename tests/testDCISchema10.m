function tests = testDCISchema10()
tests = functiontests(localfunctions);
end
function testProduction(~)
assert(pdcchPhaseCase("testDCISchema10"));
end
