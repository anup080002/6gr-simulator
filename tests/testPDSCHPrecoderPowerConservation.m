function ok = testPDSCHPrecoderPowerConservation()
%TESTPDSCHPRECODERPOWERCONSERVATION Verify every resolved slice.

setup6GRSimToolkit("Verbose", false);
rng(8249, "twister");
nPorts = 8;
nLayers = 4;
nPRG = 3;
nGroups = 3;
F = dftmtx(nPorts) / sqrt(nPorts);
W = complex(zeros(nPorts,nLayers,nPRG,nGroups));
for group = 1:nGroups
    for prg = 1:nPRG
        W(:,:,prg,group) = diag(exp(1j*(0:nPorts-1).' ...
            * (2*prg + group)/19)) * F(:,1:nLayers);
    end
end
spec = struct("Mode","prg_symbol_selective", "NPorts",nPorts, ...
    "NLayers",nLayers, "NPRG",nPRG, "NSymbolGroups",nGroups, ...
    "PRGSize",4, "PRBSet",4:15, "ScheduledSymbols",0:11, ...
    "SymbolGroupMap",repelem(0:2,4), "W",W, ...
    "MatrixSource","power_conservation_test", ...
    "CodebookIdentifier","test_dft_rank4", ...
    "NormalizationConvention","semi_unitary", ...
    "NormalizationTolerance",2e-12);
bundle = sixgr.pdsch.PDSCHPrecoderBundle(spec);

maxRelativeError = 0;
sliceCount = 0;
for group = 0:(nGroups - 1)
    symbol = bundle.ScheduledSymbols( ...
        find(bundle.SymbolGroupIndexPerSymbol == group, 1));
    for prg = 0:(nPRG - 1)
        prb = bundle.PRGToPRBMap{prg + 1}(1);
        layers = complex(randn(nLayers,64), randn(nLayers,64));
        ports = bundle.apply(layers, prb, symbol);
        relativeError = abs(sum(abs(ports(:)).^2) ...
            - sum(abs(layers(:)).^2)) / sum(abs(layers(:)).^2);
        maxRelativeError = max(maxRelativeError, relativeError);
        assert(relativeError < 2e-12, ...
            "PRG %d group %d power error %.3g.", prg, group, relativeError);
        sliceCount = sliceCount + 1;
    end
end
assert(max(bundle.PowerRelativeErrorPerSlice(:)) < 2e-12, ...
    "Stored slice normalization evidence exceeds tolerance.");

fprintf("PDSCH precoder power: %d/%d slices pass; max relative error %.3g\n", ...
    sliceCount, sliceCount, maxRelativeError);
ok = true;
end
