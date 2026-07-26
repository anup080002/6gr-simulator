function tests = testPDCCHResourceOwnership()
tests = functiontests(localfunctions);
end
function testProduction(~)
assert(pdcchPhaseCase("testPDCCHResourceOwnership"));
end
