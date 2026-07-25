function ok = testPDSCHFrequencySelectivePrecoderEndToEnd()
%TESTPDSCHFREQUENCYSELECTIVEPRECODERENDTOEND Resolve every effective channel.

setup6GRSimToolkit("Verbose", false);
rng(8233, "twister");
bundle = localBundle();
resourceCount = 32;
prb = repmat(0:7, 1, 4);
symbol = repelem(0:3, 8);
layers = complex(randn(2, resourceCount), randn(2, resourceCount));
[ports, txTrace] = bundle.apply(layers, prb, symbol, "Domain", "data");

H = [1.0+0.1j, 0.2-0.3j, -0.1+0.4j, 0.3+0.2j; ...
     0.1-0.2j, 0.9+0.1j, 0.4+0.1j, -0.2+0.3j];
received = H * ports;
recovered = complex(zeros(size(layers)));
wrongRecovered = complex(zeros(size(layers)));
widebandPage = bundle.slice(0, 0);
for idx = 1:resourceCount
    page = bundle.slice(prb(idx), symbol(idx));
    recovered(:, idx) = (H * page) \ received(:, idx);
    wrongRecovered(:, idx) = (H * widebandPage) \ received(:, idx);
end
correctError = max(abs(recovered(:) - layers(:)));
wrongError = max(abs(wrongRecovered(:) - layers(:)));
assert(correctError < 5e-12, ...
    "Frequency-selective effective-channel recovery error %.3g.", correctError);
assert(wrongError > 1e-3, ...
    "A stale wideband slice unexpectedly reproduced frequency-selective recovery.");
assert(numel(unique(txTrace.AppliedMatrixDigest)) == bundle.NPRG, ...
    "Frequency-selective execution did not apply every PRG matrix.");

fprintf(['PDSCH frequency-selective end-to-end: %d resources pass; ' ...
    'correct error %.3g stale-wideband error %.3g\n'], ...
    resourceCount, correctError, wrongError);
ok = true;
end

function bundle = localBundle()
nPorts = 4;
nLayers = 2;
nPRG = 4;
F = dftmtx(nPorts) / sqrt(nPorts);
W = complex(zeros(nPorts,nLayers,nPRG,1));
columnPairs = {[1 2],[1 3],[2 4],[3 4]};
for prg = 1:nPRG
    W(:,:,prg,1) = diag(exp(1j*(0:nPorts-1).' * prg/7)) ...
        * F(:,columnPairs{prg});
end
spec = struct("Mode","prg_noncodebook", "NPorts",nPorts, ...
    "NLayers",nLayers, "NPRG",nPRG, "NSymbolGroups",1, ...
    "PRGSize",2, "PRBSet",0:7, "ScheduledSymbols",0:3, ...
    "SymbolGroupMap",zeros(1,4), "W",W, ...
    "MatrixSource","frequency_selective_e2e_test", ...
    "CodebookIdentifier","", ...
    "NormalizationConvention","semi_unitary", ...
    "NormalizationTolerance",2e-12);
bundle = sixgr.pdsch.PDSCHPrecoderBundle(spec);
end
