function tests = testPDCCHBWPAndCrossCarrier()
tests = functiontests(localfunctions);
end
function testProduction(~)
assert(pdcchPhaseCase("testPDCCHBWPAndCrossCarrier"));
end
