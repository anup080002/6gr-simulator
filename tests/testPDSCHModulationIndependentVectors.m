function ok = testPDSCHModulationIndependentVectors()
%TESTPDSCHMODULATIONINDEPENDENTVECTORS Validate all square-QAM vectors.

setup6GRSimToolkit("Verbose", false);
vectorDir = fullfile(fileparts(mfilename("fullpath")), "vectors", "pdsch");
inputPath = fullfile(vectorDir, "pdsch_modulation_test_vectors.csv");
inputOptions = detectImportOptions(inputPath, "TextType", "string");
inputOptions = setvartype(inputOptions, ...
    ["Modulation", "InputBits", "ExpectedStatus", "ExpectedError"], "string");
inputT = readtable(inputPath, inputOptions);
expectedPath = fullfile(vectorDir, "expected_pdsch_modulation_vectors.csv");
expectedOptions = detectImportOptions(expectedPath, "TextType", "string");
expectedOptions = setvartype(expectedOptions, ...
    ["ExpectedSymbols", "Status", "ExpectedError"], "string");
expectedT = readtable(expectedPath, expectedOptions);

assert(height(inputT) == 24 && height(expectedT) == 24, ...
    "Modulation vector pack must contain exactly 24 input and expected rows.");
maxError = 0;
passCount = 0;
negativeCount = 0;
for idx = 1:height(inputT)
    row = inputT(idx, :);
    expected = expectedT(expectedT.CaseID == row.CaseID, :);
    assert(height(expected) == 1, "Missing expected row for %s.", row.CaseID);
    bits = localBits(row.InputBits);
    modulation = row.Modulation;

    if row.ExpectedStatus == "ERROR"
        suffix = row.ExpectedError;
        localAssertIdentifier(@() sixgr.pdsch.PDSCHModulator(bits, modulation), suffix);
        localAssertIdentifier(@() sixgr.pdsch.oracle.QAMMapperSpec(bits, modulation), suffix);
        negativeCount = negativeCount + 1;
        continue;
    end

    expectedSymbols = localComplexVector(expected.ExpectedSymbols);
    [actual, info] = sixgr.pdsch.PDSCHModulator(bits, modulation);
    oracle = sixgr.pdsch.oracle.QAMMapperSpec(bits, modulation);
    vectorError = max(abs(actual(:) - expectedSymbols));
    oracleError = max(abs(oracle(:) - expectedSymbols));
    maxError = max([maxError, vectorError, oracleError]);
    assert(vectorError < 5e-14 && oracleError < 5e-14, ...
        "%s QAM vector error %.3g/%.3g exceeds tolerance.", ...
        row.CaseID, vectorError, oracleError);
    assert(double(info.Qm) == double(row.Qm), "%s Qm mismatch.", row.CaseID);
    assert(double(info.NormalizationDenominatorSquared) ...
        == double(expected.NormalizationDenominatorSquared), ...
        "%s normalization mismatch.", row.CaseID);

    llr = sixgr.pdsch.PDSCHModulator(actual, modulation, ...
        "Operation", "soft-demap", "NoiseVariance", 1e-3);
    recovered = int8(llr < 0);
    assert(isequal(recovered(:), bits), "%s soft-LLR sign mismatch.", row.CaseID);
    hard = sixgr.pdsch.PDSCHModulator(actual, modulation, ...
        "Operation", "hard-demap");
    assert(isequal(hard(:), bits), "%s hard-demapper mismatch.", row.CaseID);
    passCount = passCount + 1;
end

assert(passCount == 20 && negativeCount == 4, ...
    "Expected 20 positive and four negative modulation cases.");
fprintf("PDSCH modulation vectors: 20/20 pass, negatives 4/4; max error %.3g\n", ...
    maxError);
ok = true;
end

function bits = localBits(text)
chars = char(string(text));
bits = int8(chars(:) - '0');
end

function values = localComplexVector(text)
parts = split(string(text), "|");
values = complex(zeros(numel(parts), 1));
pattern = "^([+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)" ...
    + "([+-](?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)j$";
for idx = 1:numel(parts)
    tokens = regexp(char(parts(idx)), char(pattern), "tokens", "once");
    assert(~isempty(tokens), "Cannot parse expected complex value '%s'.", parts(idx));
    values(idx) = complex(str2double(tokens{1}), str2double(tokens{2}));
end
end

function localAssertIdentifier(fn, suffix)
thrown = false;
try
    fn();
catch cause
    thrown = endsWith(string(cause.identifier), ":" + string(suffix));
    if ~thrown
        rethrow(cause);
    end
end
assert(thrown, "Expected typed error ending in :%s.", suffix);
end
