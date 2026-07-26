function tests = testDecodedDCIGrantAuthority()
tests = functiontests(localfunctions);
end
function testProduction(~)
assert(pdcchPhaseCase("testDecodedDCIGrantAuthority"));
end
