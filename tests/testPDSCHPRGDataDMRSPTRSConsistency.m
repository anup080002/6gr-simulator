function ok = testPDSCHPRGDataDMRSPTRSConsistency()
%TESTPDSCHPRGDATADMRSPTRSCONSISTENCY Ensure one slice owns all domains.

setup6GRSimToolkit("Verbose", false);
bundle = localBundle();
prb = [0 1 2 3 4 5 6 7];
symbol = [0 1 2 3 4 5 6 7];
layers = complex([1:8; 11:18], [-1:-1:-8; 3:10]);

[dataPorts, dataTrace] = bundle.apply(layers, prb, symbol, "Domain", "data");
[dmrsPorts, dmrsTrace] = bundle.apply(layers, prb, symbol, "Domain", "dmrs");
[ptrsPorts, ptrsTrace] = bundle.apply(layers, prb, symbol, "Domain", "ptrs");
assert(isequal(dataPorts, dmrsPorts) && isequal(dataPorts, ptrsPorts), ...
    "Data, DM-RS, and PT-RS must use the identical resolved matrices.");
assert(isequal(dataTrace.AppliedMatrixDigest, dmrsTrace.AppliedMatrixDigest) ...
    && isequal(dataTrace.AppliedMatrixDigest, ptrsTrace.AppliedMatrixDigest), ...
    "Data/DM-RS/PT-RS applied-matrix digests differ.");
assert(all(dataTrace.ResolvedMatrixDigest == dataTrace.AppliedMatrixDigest), ...
    "Resolved and applied matrix digests differ.");

localAssertIdentifier(@() bundle.apply(layers(:,1), 99, 0), "UnscheduledPRB");
localAssertIdentifier(@() bundle.apply(layers(:,1), 0, 13), "UnscheduledSymbol");
fprintf("PDSCH data/DM-RS/PT-RS consistency: 24/24 applications pass\n");
ok = true;
end

function bundle = localBundle()
nPorts = 4;
nLayers = 2;
nPRG = 4;
nGroups = 2;
F = dftmtx(nPorts) / sqrt(nPorts);
W = complex(zeros(nPorts,nLayers,nPRG,nGroups));
for group = 1:nGroups
    for prg = 1:nPRG
        W(:,:,prg,group) = diag(exp(1j*(0:nPorts-1).' ...
            * (prg + 3*group)/11)) * F(:,1:nLayers);
    end
end
spec = struct("Mode","prg_symbol_selective", "NPorts",nPorts, ...
    "NLayers",nLayers, "NPRG",nPRG, "NSymbolGroups",nGroups, ...
    "PRGSize",2, "PRBSet",0:7, "ScheduledSymbols",0:11, ...
    "SymbolGroupMap",[zeros(1,6),ones(1,6)], "W",W, ...
    "MatrixSource","domain_consistency_test", ...
    "CodebookIdentifier","test_symbol_selective", ...
    "NormalizationConvention","semi_unitary", ...
    "NormalizationTolerance",2e-12);
bundle = sixgr.pdsch.PDSCHPrecoderBundle(spec);
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
