function tests = testPDCCHCFOAndTiming()
tests = functiontests(localfunctions);
end
function testProduction(~)
assert(pdcchPhaseCase("testPDCCHCFOAndTiming"));
end
