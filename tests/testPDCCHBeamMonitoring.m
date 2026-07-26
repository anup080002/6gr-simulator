function tests = testPDCCHBeamMonitoring()
tests = functiontests(localfunctions);
end
function testProduction(~)
assert(pdcchPhaseCase("testPDCCHBeamMonitoring"));
end
