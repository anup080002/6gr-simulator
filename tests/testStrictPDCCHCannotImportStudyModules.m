function tests = testStrictPDCCHCannotImportStudyModules()
tests = functiontests(localfunctions);
end
function testProduction(~)
assert(pdcchPhaseCase("testStrictPDCCHCannotImportStudyModules"));
end
