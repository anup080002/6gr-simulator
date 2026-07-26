function tests = testCORESETInterleavedMapping()
tests = functiontests(localfunctions);
end
function testProduction(~)
assert(pdcchPhaseCase("testCORESETInterleavedMapping"));
end
