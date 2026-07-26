function tests = testPDCCHArtifactGeneration()
tests = functiontests(localfunctions);
end
function testProduction(~)
assert(pdcchPhaseCase("testPDCCHArtifactGeneration"));
end
