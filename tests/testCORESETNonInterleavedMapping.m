function tests = testCORESETNonInterleavedMapping()
tests = functiontests(localfunctions);
end
function testProduction(~)
assert(pdcchPhaseCase("testCORESETNonInterleavedMapping"));
end
