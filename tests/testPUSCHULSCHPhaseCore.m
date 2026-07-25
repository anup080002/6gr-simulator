function tests = testPUSCHULSCHPhaseCore
%TESTPUSCHULSCHPHASECORE Focused Prompt-03 production-chain regressions.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
repoRoot = fileparts(fileparts(mfilename("fullpath")));
addpath(repoRoot);
setup6GRSimToolkit("Verbose", false);
testCase.TestData.VectorRoot = fullfile(repoRoot, "tests", "vectors", "pusch");
end

function testFrozenPUSCHModulationVectors(testCase)
vectors = localReadStringTable(fullfile( ...
    testCase.TestData.VectorRoot, "pusch_modulation_test_vectors.csv"));
for row = 1:height(vectors)
    bits = localBinaryText(vectors.InputBits(row));
    if vectors.ExpectedStatus(row) == "PASS"
        [symbols, info] = sixgr.phy.ul.pusch.PUSCHModulator.modulate( ...
            bits, vectors.Modulation(row), ...
            localLogical(vectors.TransformPrecoding(row)));
        verifyEqual(testCase, info.Qm, str2double(vectors.Qm(row)), ...
            sprintf("Qm mismatch for %s.", vectors.CaseID(row)));
        verifyEqual(testCase, info.InputBitCount, numel(bits));
        verifyEqual(testCase, info.OutputSymbolCount, ...
            numel(bits) / info.Qm);
        verifyTrue(testCase, all(isfinite(symbols)));
    else
        actual = localCaptureIdentifier(@() ...
            sixgr.phy.ul.pusch.PUSCHModulator.modulate( ...
            bits, vectors.Modulation(row), ...
            localLogical(vectors.TransformPrecoding(row))));
        verifyEqual(testCase, actual, vectors.ExpectedError(row), ...
            sprintf("Wrong typed error for %s.", vectors.CaseID(row)));
    end
end
end

function testFrozenPUSCHLayerMappingVectors(testCase)
vectors = localReadStringTable(fullfile( ...
    testCase.TestData.VectorRoot, "pusch_layer_mapping_test_vectors.csv"));
for row = 1:height(vectors)
    rank = str2double(vectors.Rank(row));
    count = str2double(vectors.NumCodewords(row));
    streams = cell(1, count);
    if count >= 1
        streams{1} = localComplexText(vectors.Codeword0Symbols(row));
    end
    if count >= 2
        streams{2} = localComplexText(vectors.Codeword1Symbols(row));
    end
    input = streams;
    if count == 1
        input = streams{1};
    end
    if vectors.ExpectedStatus(row) == "PASS"
        [layers, info] = sixgr.phy.ul.pusch.PUSCHLayerMapper.map(input, rank);
        recovered = sixgr.phy.ul.pusch.PUSCHLayerMapper.demap(layers, rank);
        recovered = localAsCell(recovered, count);
        verifyEqual(testCase, info.Rank, rank);
        verifyEqual(testCase, info.NumCodewords, count);
        for cw = 1:count
            verifyEqual(testCase, recovered{cw}, streams{cw}, ...
                "AbsTol", 0, ...
                sprintf("Layer round-trip mismatch for %s CW%d.", ...
                vectors.CaseID(row), cw - 1));
        end
    else
        actual = localCaptureIdentifier(@() ...
            sixgr.phy.ul.pusch.PUSCHLayerMapper.map(input, rank));
        verifyEqual(testCase, actual, vectors.ExpectedError(row), ...
            sprintf("Wrong typed error for %s.", vectors.CaseID(row)));
    end
end
end

function testPUSCHULSCHTwoCodewordEightPortRoundTrip(testCase)
rng(47, "twister");
carrier = nrCarrierConfig( ...
    "NSizeGrid", 24, ...
    "SubcarrierSpacing", 30);
pusch = nrPUSCHConfig;
pusch.PRBSet = 0:23;
pusch.SymbolAllocation = [0 14];
pusch.MappingType = "A";
pusch.Modulation = {"QPSK","16QAM"};
pusch.NumLayers = 5;
pusch.TransmissionScheme = "codebook";
pusch.NumAntennaPorts = 8;
pusch.TPMI = 0;
pusch.TransformPrecoding = false;
pusch.DMRS.DMRSConfigurationType = 2;
pusch.DMRS.DMRSLength = 2;
pusch.DMRS.DMRSPortSet = 0:4;
cfg = struct( ...
    "run", struct("strictMode", false), ...
    "channel", struct("model", "AWGN"), ...
    "phy", struct( ...
        "ueArray", [8 1 1], ...
        "pusch", struct("NumAntennaPorts", 8), ...
        "channelEstimation", struct("method", "LS")));

[tx, ~] = sixgr.phy.ul.PUSCH_Tx(cfg, ...
    "Carrier", carrier, ...
    "PUSCH", pusch, ...
    "TargetCodeRate", [0.30 0.45], ...
    "RV", [0 0], ...
    "NumTxAnt", 8, ...
    "CompactOutput", false);
[rx, info] = sixgr.phy.ul.PUSCH_Rx(tx.Waveform, cfg, ...
    "Carrier", carrier, ...
    "PUSCH", pusch, ...
    "PUSCHIndices", tx.PUSCHIndices, ...
    "TransportBlockSize", tx.TransportBlockSize, ...
    "TargetCodeRate", [0.30 0.45], ...
    "RV", [0 0], ...
    "CodingLayout", tx.CodingLayouts, ...
    "NoiseVar", 1e-12, ...
    "NoiseVarDomain", "time", ...
    "FastAWGNPath", false, ...
    "SkipTimingEstimate", true, ...
    "CompactOutput", false);

verifyEqual(testCase, double(tx.PUSCH.NumLayers), 5);
verifyEqual(testCase, tx.NumCodewords, 2);
verifyEqual(testCase, size(tx.Waveform, 2), 8);
verifyEqual(testCase, rx.NumCodewords, 2);
verifyTrue(testCase, all(rx.CRCPass));
verifyEqual(testCase, rx.TransportBlocks{1}, tx.TransportBlocks{1});
verifyEqual(testCase, rx.TransportBlocks{2}, tx.TransportBlocks{2});
verifyEqual(testCase, string(rx.DecoderInputSymbolDomain), "layer");
verifyEqual(testCase, string(info.ExecutionBackend), ...
    "nrPUSCHDecode_nrULSCHDecoder_two_codeword_truth");
end

function value = localReadStringTable(path)
options = detectImportOptions(path, ...
    "Delimiter", ",", "VariableNamingRule", "preserve");
options = setvartype(options, options.VariableNames, "string");
value = readtable(path, options);
for index = 1:width(value)
    name = value.Properties.VariableNames{index};
    column = string(value.(name));
    column(ismissing(column)) = "";
    value.(name) = column;
end
end

function bits = localBinaryText(value)
text = char(string(value));
bits = zeros(numel(text), 1, "int8");
for index = 1:numel(text)
    bits(index) = int8(str2double(text(index)));
end
end

function values = localComplexText(value)
tokens = split(string(value), "|");
tokens(tokens == "") = [];
values = complex(zeros(numel(tokens), 1));
for index = 1:numel(tokens)
    values(index) = str2double(strrep(tokens(index), "j", "i"));
end
end

function value = localLogical(raw)
value = ismember(upper(strtrim(string(raw))), ...
    ["1","TRUE","YES","PASS"]);
end

function cells = localAsCell(value, count)
if count == 1 && ~iscell(value)
    cells = {value};
else
    cells = reshape(value, 1, []);
end
end

function identifier = localCaptureIdentifier(callback)
identifier = "";
try
    callback();
catch caught
    identifier = string(caught.identifier);
end
if identifier == ""
    error("sixgr:tests:ExpectedTypedErrorNotRaised", ...
        "The negative PUSCH vector did not raise an error.");
end
end
