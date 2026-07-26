function tests = testPDCCHQPSK()
tests = functiontests(localfunctions);
end
function testProduction(~)
assert(pdcchPhaseCase("testPDCCHQPSK"));
end
