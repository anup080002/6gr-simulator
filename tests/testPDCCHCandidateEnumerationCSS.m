function tests = testPDCCHCandidateEnumerationCSS()
tests = functiontests(localfunctions);
end
function testProduction(~)
assert(pdcchPhaseCase("testPDCCHCandidateEnumerationCSS"));
end
