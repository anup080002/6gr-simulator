function tests = testPDCCHNoSignalFalseAlarm()
tests = functiontests(localfunctions);
end
function testProduction(~)
assert(pdcchPhaseCase("testPDCCHNoSignalFalseAlarm"));
end
