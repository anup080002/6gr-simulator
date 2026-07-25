function ok = testPDSCHPrecoderBundleVectors()
%TESTPDSCHPRECODERBUNDLEVECTORS Execute all 15 frozen precoder cases.

setup6GRSimToolkit("Verbose", false);
vectorDir = fullfile(fileparts(mfilename("fullpath")), "vectors", "pdsch");
inputPath = fullfile(vectorDir, "pdsch_precoding_prg_test_vectors.csv");
inputOptions = detectImportOptions(inputPath, "TextType", "string");
inputOptions = setvartype(inputOptions, ...
    ["Mode","PRBSet","MatrixShape","ExpectedStatus","ExpectedError"], "string");
inputT = readtable(inputPath, inputOptions);
expectedPath = fullfile(vectorDir, "expected_pdsch_precoding_behavior.csv");
expectedOptions = detectImportOptions(expectedPath, "TextType", "string");
expectedOptions = setvartype(expectedOptions, ...
    ["ExpectedStatus","ExpectedError"], "string");
expectedT = readtable(expectedPath, expectedOptions);
assert(height(inputT) == 15 && height(expectedT) == 15, ...
    "Precoder vector pack must contain exactly 15 rows.");

positiveCount = 0;
negativeCount = 0;
applicationCount = 0;
consumptionCount = 0;
maxInverseError = 0;
for idx = 1:height(inputT)
    row = inputT(idx, :);
    expected = expectedT(expectedT.CaseID == row.CaseID, :);
    assert(height(expected) == 1, "Missing expected behavior for %s.", row.CaseID);
    spec = localSpec(row);
    if row.ExpectedStatus == "ERROR"
        localAssertIdentifier( ...
            @() sixgr.pdsch.PDSCHPrecoderBundle(spec), row.ExpectedError);
        negativeCount = negativeCount + 1;
        continue;
    end

    bundle = sixgr.pdsch.PDSCHPrecoderBundle(spec);
    expectedShape = localShape(row.MatrixShape);
    assert(isequal(bundle.MatrixShape, expectedShape), ...
        "%s canonical matrix shape mismatch.", row.CaseID);
    assert(bundle.MatrixRank == double(expected.ExpectedMatrixRank), ...
        "%s canonical matrix rank mismatch.", row.CaseID);
    assert(numel(bundle.PRGIndexPerPRB) == numel(bundle.PRBSet) ...
        && all(ismember(0:bundle.NPRG-1, bundle.PRGIndexPerPRB)), ...
        "%s PRG coverage is incomplete.", row.CaseID);
    assert(numel(bundle.SymbolGroupIndexPerSymbol) == numel(bundle.ScheduledSymbols) ...
        && all(ismember(0:bundle.NSymbolGroups-1, ...
        bundle.SymbolGroupIndexPerSymbol)), ...
        "%s symbol-group coverage is incomplete.", row.CaseID);

    [prb, symbol] = localOneResourcePerSlice(bundle);
    layers = complex(reshape(1:(bundle.NLayerPorts * numel(prb)), ...
        bundle.NLayerPorts, []), -0.25);
    [ports, txTrace] = bundle.apply(layers, prb, symbol, "Domain", "data");
    [recovered, rxTrace] = bundle.deapply(ports, prb, symbol, ...
        "Domain", "effective_channel");
    inverseError = max(abs(recovered(:) - layers(:)));
    maxInverseError = max(maxInverseError, inverseError);
    assert(inverseError < 2e-12, "%s precoder inverse error %.3g.", ...
        row.CaseID, inverseError);
    assert(height(txTrace) == double(expected.ExpectedAppliedSlices) ...
        && height(rxTrace) == double(expected.ExpectedAppliedSlices), ...
        "%s applied-slice count mismatch.", row.CaseID);
    assert(all(txTrace.ResolvedMatrixDigest == txTrace.AppliedMatrixDigest) ...
        && all(rxTrace.ResolvedMatrixDigest == rxTrace.AppliedMatrixDigest), ...
        "%s resolution/application matrix digest mismatch.", row.CaseID);
    assert(height(txTrace) > 0 == logical(expected.ExpectedTXApplication) ...
        && height(rxTrace) > 0 == logical(expected.ExpectedRXApplication), ...
        "%s TX/RX application evidence mismatch.", row.CaseID);
    applicationCount = applicationCount + height(txTrace);
    consumptionCount = consumptionCount + height(rxTrace);
    positiveCount = positiveCount + 1;
end

assert(positiveCount == 9 && negativeCount == 6, ...
    "Expected nine valid and six invalid frozen precoder cases.");
fprintf(['PDSCH precoder vectors: 9/9 valid, 6/6 typed negatives; ' ...
    'TX applications=%d RX consumptions=%d max inverse error=%.3g\n'], ...
    applicationCount, consumptionCount, maxInverseError);
ok = true;
end

function spec = localSpec(row)
nPorts = double(row.NPorts);
nLayers = double(row.NLayers);
nPRG = double(row.NPRG);
nSymbolGroups = double(row.NSymbolGroups);
shape = localShape(row.MatrixShape);
if isempty(shape)
    W = double(7);
else
    W = localMatrix(shape, row.ExpectedStatus == "PASS");
end
scheduledSymbols = 0:11;
symbolGroupMap = floor((0:numel(scheduledSymbols)-1) ...
    * nSymbolGroups / numel(scheduledSymbols));
spec = struct();
spec.Mode = row.Mode;
spec.NPorts = nPorts;
spec.NLayers = nLayers;
spec.NPRG = nPRG;
spec.NSymbolGroups = nSymbolGroups;
spec.PRGSize = double(row.PRGSize);
spec.PRBSet = localPRBSet(row.PRBSet);
spec.ScheduledSymbols = scheduledSymbols;
spec.SymbolGroupMap = symbolGroupMap;
spec.W = W;
spec.MatrixSource = "frozen_precoding_vector:" + row.CaseID;
spec.CodebookIdentifier = "frozen:" + row.Mode;
spec.NormalizationConvention = "semi_unitary";
spec.NormalizationTolerance = 2e-12;
end

function W = localMatrix(shape, makeValid)
W = complex(zeros(shape));
if ~makeValid
    return;
end
nPorts = shape(1);
nLayers = shape(2);
for prg = 1:shape(3)
    for group = 1:shape(4)
        row = (0:nPorts-1).';
        column = 0:nPorts-1;
        unitary = exp(-1j * 2*pi * row * column / nPorts) / sqrt(nPorts);
        phase = exp(1j * (0:nPorts-1).' * (prg + 2*group) / 17);
        W(:,:,prg,group) = diag(phase) * unitary(:,1:nLayers);
    end
end
end

function shape = localShape(text)
token = string(text);
if token == "scalar"
    shape = [];
else
    shape = str2double(split(token, "x")).';
end
end

function prbs = localPRBSet(text)
token = string(text);
if contains(token, "-")
    limits = str2double(split(token, "-"));
    prbs = limits(1):limits(2);
else
    prbs = str2double(split(token, "|")).';
end
end

function [prb, symbol] = localOneResourcePerSlice(bundle)
count = bundle.NPRG * bundle.NSymbolGroups;
prb = zeros(1, count);
symbol = zeros(1, count);
position = 0;
for group = 0:(bundle.NSymbolGroups - 1)
    selectedSymbol = bundle.ScheduledSymbols( ...
        find(bundle.SymbolGroupIndexPerSymbol == group, 1));
    for prg = 0:(bundle.NPRG - 1)
        position = position + 1;
        prb(position) = bundle.PRGToPRBMap{prg + 1}(1);
        symbol(position) = selectedSymbol;
    end
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
