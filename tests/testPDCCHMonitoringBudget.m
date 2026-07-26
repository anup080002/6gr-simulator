function tests = testPDCCHMonitoringBudget()
tests = functiontests(localfunctions);
end
function testProduction(~)
assert(pdcchPhaseCase("testPDCCHMonitoringBudget"));
end
