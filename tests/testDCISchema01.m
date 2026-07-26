function tests = testDCISchema01()
tests = functiontests(localfunctions);
end
function testProduction(~)
assert(pdcchPhaseCase("testDCISchema01"));
end
