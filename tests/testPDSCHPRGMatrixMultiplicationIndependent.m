function ok = testPDSCHPRGMatrixMultiplicationIndependent()
%TESTPDSCHPRGMATRIXMULTIPLICATIONINDEPENDENT Compare every PRG multiply.

setup6GRSimToolkit("Verbose", false);
rng(8211, "twister");
bundle = localBundle();
resourceCount = 48;
prb = repmat(0:7, 1, 6);
symbol = repelem(0:5, 8);
layers = complex(randn(2, resourceCount), randn(2, resourceCount));
[actual, trace] = bundle.apply(layers, prb, symbol, "Domain", "data");

expected = complex(zeros(size(actual)));
for idx = 1:resourceCount
    page = bundle.slice(prb(idx), symbol(idx));
    expected(:, idx) = sixgr.pdsch.oracle.PrecodingMultiplySpec( ...
        page, layers(:, idx));
end
maxMultiplyError = max(abs(actual(:) - expected(:)));
assert(maxMultiplyError < 2e-14, ...
    "Independent PRG matrix multiplication error %.3g.", maxMultiplyError);

[recovered, rxTrace] = bundle.deapply(actual, prb, symbol, ...
    "Domain", "effective_channel");
oracleRecovered = complex(zeros(size(layers)));
for idx = 1:resourceCount
    page = bundle.slice(prb(idx), symbol(idx));
    oracleRecovered(:, idx) = sixgr.pdsch.oracle.PrecodingMultiplySpec( ...
        page, actual(:, idx), "Operation", "deapply");
end
maxInverseError = max(abs(recovered(:) - layers(:)));
assert(maxInverseError < 2e-12 ...
    && max(abs(recovered(:) - oracleRecovered(:))) < 2e-12, ...
    "Independent PRG inverse error %.3g.", maxInverseError);
assert(height(trace) == resourceCount && height(rxTrace) == resourceCount, ...
    "Every PRG resource must emit TX/RX application evidence.");

fprintf("PDSCH PRG independent multiplies: %d/%d pass; max error %.3g\n", ...
    resourceCount, resourceCount, maxMultiplyError);
ok = true;
end

function bundle = localBundle()
nPorts = 4;
nLayers = 2;
nPRG = 4;
W = complex(zeros(nPorts,nLayers,nPRG,1));
F = dftmtx(nPorts) / sqrt(nPorts);
for prg = 1:nPRG
    W(:,:,prg,1) = diag(exp(1j*(0:nPorts-1).' * prg/9)) * F(:,1:nLayers);
end
spec = struct("Mode","prg_codebook", "NPorts",nPorts, ...
    "NLayers",nLayers, "NPRG",nPRG, "NSymbolGroups",1, ...
    "PRGSize",2, "PRBSet",0:7, "ScheduledSymbols",0:5, ...
    "SymbolGroupMap",zeros(1,6), "W",W, ...
    "MatrixSource","independent_multiply_test", ...
    "CodebookIdentifier","test_dft", ...
    "NormalizationConvention","semi_unitary", ...
    "NormalizationTolerance",2e-12);
bundle = sixgr.pdsch.PDSCHPrecoderBundle(spec);
end
