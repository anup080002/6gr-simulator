function tests = testPDCCHLowSNRDetection()
tests = functiontests(localfunctions);
end
function testProduction(~)
assert(pdcchPhaseCase("testPDCCHLowSNRDetection"));
end
