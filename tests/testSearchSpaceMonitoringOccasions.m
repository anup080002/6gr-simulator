function tests = testSearchSpaceMonitoringOccasions()
tests = functiontests(localfunctions);
end
function testProduction(~)
assert(pdcchPhaseCase("testSearchSpaceMonitoringOccasions"));
end
