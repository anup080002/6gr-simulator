function tests = testPDCCHPhysicalScrambling()
tests = functiontests(localfunctions);
end
function testProduction(~)
assert(pdcchPhaseCase("testPDCCHPhysicalScrambling"));
end
