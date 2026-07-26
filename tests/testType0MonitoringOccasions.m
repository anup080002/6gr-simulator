function tests = testType0MonitoringOccasions()
tests = functiontests(localfunctions);
end
function testProduction(~)
assert(pdcchPhaseCase("testType0MonitoringOccasions"));
end
