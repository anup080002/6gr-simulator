function tests = testPUCCHResourceSetSelection
tests = functiontests(localfunctions);
end

function testIndependentResourceSetVectors(~)
root = fileparts(fileparts(mfilename("fullpath")));
input = readtable(fullfile(root, "tests", "vectors", "pucch", ...
    "pucch_resource_set_test_vectors.csv"), "TextType", "string");
expected = readtable(fullfile(root, "tests", "vectors", "pucch", ...
    "expected_pucch_resource_selection.csv"), "TextType", "string");
for index = 1:height(input)
    actual = sixgr.phy.pucch.PUCCHResourceSetResolver.resolveVector(input(index,:));
    reference = expected(index,:);
    assert(actual.Valid == localTruth(reference.ExpectedValid));
    expectedSet = double(reference.SelectedSetID);
    assert((isnan(actual.SelectedSetID) && isnan(expectedSet)) || ...
        actual.SelectedSetID == expectedSet || ~actual.Valid);
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
