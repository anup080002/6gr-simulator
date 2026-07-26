function tests = testDCISizeAlignment()
tests = functiontests(localfunctions);
end
function testProduction(~)
assert(pdcchPhaseCase("testDCISizeAlignment"));
end
