function tests = testDCICRC24CAndRNTIMask()
tests = functiontests(localfunctions);
end
function testProduction(~)
assert(pdcchPhaseCase("testDCICRC24CAndRNTIMask"));
end
