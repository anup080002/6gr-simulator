function tests = testType0CORESETTables()
tests = functiontests(localfunctions);
end
function testProduction(~)
assert(pdcchPhaseCase("testType0CORESETTables"));
end
