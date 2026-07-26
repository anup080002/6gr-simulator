function tests = testPDCCHWrongRNTI()
tests = functiontests(localfunctions);
end
function testProduction(~)
assert(pdcchPhaseCase("testPDCCHWrongRNTI"));
end
