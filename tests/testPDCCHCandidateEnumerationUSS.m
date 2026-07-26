function tests = testPDCCHCandidateEnumerationUSS()
tests = functiontests(localfunctions);
end
function testProduction(~)
assert(pdcchPhaseCase("testPDCCHCandidateEnumerationUSS"));
end
