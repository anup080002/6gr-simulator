function tests = testDCISchema11()
tests = functiontests(localfunctions);
end
function testProduction(~)
assert(pdcchPhaseCase("testDCISchema11"));
end
