function tests = testPUCCHK1TDDTiming
tests = functiontests(localfunctions);
end

function testExactDueSlotAndNoSymbolShift(~)
root = fileparts(fileparts(mfilename("fullpath")));
input = readtable(fullfile(root, "tests", "vectors", "pucch", ...
    "pucch_k1_tdd_test_vectors.csv"), "TextType", "string");
expected = readtable(fullfile(root, "tests", "vectors", "pucch", ...
    "expected_pucch_timing_resolution.csv"), "TextType", "string");
for index = 1:height(input)
    actual = sixgr.phy.pucch.PUCCHTimingResolver.resolveVector(input(index,:));
    reference = expected(index,:);
    assert(actual.DueSlot == reference.ExpectedDueSlot);
    assert(actual.Legal == localTruth(reference.ExpectedLegal));
    assert(actual.StartSymbol == reference.ExpectedStartSymbol);
    assert(~actual.SymbolShiftApplied);
    assert(actual.ErrorID == localText(reference.ExpectedErrorID));
end

function value = localText(input)
value = string(input);
if ismissing(value), value = ""; end
end
end

function value = localTruth(input)
value = ismember(upper(string(input)), ["TRUE","1","PASS"]);
end
