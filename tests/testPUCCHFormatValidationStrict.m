function tests = testPUCCHFormatValidationStrict
tests = functiontests(localfunctions);
end

function testFormatMatrixWithoutMutation(~)
root = fileparts(fileparts(mfilename("fullpath")));
input = readtable(fullfile(root, "tests", "vectors", "pucch", ...
    "pucch_format_matrix_test_vectors.csv"), "TextType", "string");
expected = readtable(fullfile(root, "tests", "vectors", "pucch", ...
    "expected_pucch_format_validation.csv"), "TextType", "string");
for index = 1:height(input)
    actual = sixgr.phy.pucch.PUCCHFormatValidator.validateVector(input(index,:));
    reference = expected(index,:);
    assert(actual.Valid == localTruth(reference.ExpectedValid));
    assert(actual.Format == double(reference.ExpectedFormat));
    assert(~actual.ParameterMutated);
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
