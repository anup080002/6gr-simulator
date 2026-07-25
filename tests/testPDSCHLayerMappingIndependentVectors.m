function ok = testPDSCHLayerMappingIndependentVectors()
%TESTPDSCHLAYERMAPPINGINDEPENDENTVECTORS Validate rank one through eight.

setup6GRSimToolkit("Verbose", false);
vectorDir = fullfile(fileparts(mfilename("fullpath")), "vectors", "pdsch");
inputPath = fullfile(vectorDir, "pdsch_layer_mapping_test_vectors.csv");
inputOptions = detectImportOptions(inputPath, "TextType", "string");
inputOptions = setvartype(inputOptions, ...
    ["LayerCountPerCodeword", "Codeword0Symbols", "Codeword1Symbols", ...
    "ExpectedStatus", "ExpectedError"], "string");
inputT = readtable(inputPath, inputOptions);
expectedPath = fullfile(vectorDir, "expected_pdsch_layer_mapping.csv");
expectedOptions = detectImportOptions(expectedPath, "TextType", "string");
expectedOptions = setvartype(expectedOptions, ...
    ["ExpectedSymbols", "Status", "ExpectedError"], "string");
expectedT = readtable(expectedPath, expectedOptions);

assert(height(inputT) == 12 && height(expectedT) == 40, ...
    "Layer vector pack must contain 12 cases and 40 expected rows.");
layerRowsChecked = 0;
negativeCount = 0;
for idx = 1:height(inputT)
    row = inputT(idx, :);
    rank = double(row.Rank);
    codewords = localCodewords(row, double(row.NumCodewords));

    if row.ExpectedStatus == "ERROR"
        suffix = row.ExpectedError;
        localAssertIdentifier( ...
            @() sixgr.pdsch.CodewordLayerMapper(codewords, rank), suffix);
        localAssertIdentifier( ...
            @() sixgr.pdsch.oracle.LayerMapperSpec(codewords, rank), suffix);
        negativeCount = negativeCount + 1;
        continue;
    end

    actual = sixgr.pdsch.CodewordLayerMapper(codewords, rank);
    oracle = sixgr.pdsch.oracle.LayerMapperSpec(codewords, rank);
    assert(isequal(actual, oracle), "%s production/oracle layer mismatch.", row.CaseID);
    caseExpected = expectedT(expectedT.CaseID == row.CaseID, :);
    assert(height(caseExpected) == rank, "%s expected layer-row count mismatch.", row.CaseID);
    for layerIndex = 0:(rank - 1)
        expectedRow = caseExpected(caseExpected.LayerIndex == layerIndex, :);
        expectedSymbols = localNumbers(expectedRow.ExpectedSymbols);
        assert(isequal(actual(:, layerIndex + 1), expectedSymbols), ...
            "%s layer %d symbol mismatch.", row.CaseID, layerIndex);
        layerRowsChecked = layerRowsChecked + 1;
    end

    recovered = sixgr.pdsch.CodewordLayerMapper(actual, rank, ...
        "Operation", "demap");
    oracleRecovered = sixgr.pdsch.oracle.LayerMapperSpec(oracle, rank, ...
        "Operation", "demap");
    if numel(codewords) == 1
        assert(isequal(recovered, codewords{1}) && isequal(oracleRecovered, codewords{1}), ...
            "%s one-codeword inverse mismatch.", row.CaseID);
    else
        assert(isequal(recovered, codewords) && isequal(oracleRecovered, codewords), ...
            "%s two-codeword inverse mismatch.", row.CaseID);
    end
end

assert(layerRowsChecked == 36 && negativeCount == 4, ...
    "Expected 36 positive layer rows and four negative cases.");
localAssertExactIdentifier(@() sixgr.pdsch.CodewordLayerMapper( ...
    struct("NumLayers", 6, ...
        "CodewordLayer", struct("Rank", 6, "NumCodewords", 2))), ...
    "sixgr:pdsch:CodewordLayerMapper:LegacyMetadataForbidden");

fprintf("PDSCH layer vectors: 8/8 ranks, 36/36 layers, negatives 5/5 pass\n");
ok = true;
end

function codewords = localCodewords(row, count)
codewords = cell(1, count);
for idx = 1:count
    field = "Codeword" + string(idx - 1) + "Symbols";
    raw = row.(field);
    if ismissing(raw) || strlength(raw) == 0
        codewords{idx} = zeros(1, 1);
    else
        codewords{idx} = localNumbers(raw);
    end
end
end

function values = localNumbers(text)
parts = split(string(text), "|");
values = str2double(parts(:));
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

function localAssertExactIdentifier(fn, expected)
try
    fn();
catch cause
    assert(string(cause.identifier) == string(expected), ...
        "Observed %s, expected %s.", cause.identifier, expected);
    return;
end
error("sixgr:test:ExpectedErrorNotThrown", ...
    "Expected error %s was not thrown.", expected);
end
