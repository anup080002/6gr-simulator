function ok = testChannelEstimatePTRSIRC()
%TESTCHANNELESTIMATEPTRSIRC Validate CPE and IRC helper primitives.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);

K = 12;
L = 4;
rxGrid = complex(ones(K, L, 1));
knownCPE = 0.31;
rxGrid(:, 2, :) = rxGrid(:, 2, :) .* exp(1j * knownCPE);
ptrsInd = sub2ind([K, L], [3; 8], [2; 2]);
ptrsSym = complex(ones(2, 1));
carrier = struct("SymbolsPerSlot", L);
[corrected, cpeVec, info] = sixgr.phy.rx.correctCPEFromPTRS(rxGrid, ptrsInd, ptrsSym, carrier);
assert(logical(info.Enabled), "PTRS CPE correction must enable when pilots are present.");
assert(abs(double(cpeVec(2)) - knownCPE) < 1e-6, "Estimated CPE must match the known pilot phase.");
assert(abs(angle(mean(corrected(:, 2, 1), "all"))) < 1e-6, ...
    "CPE-corrected OFDM symbol must have near-zero residual common phase.");

if exist("nrExtractResources", "file") == 2
    Nr = 2;
    Nt = 1;
    rxGridIRC = complex(zeros(K, L, Nr));
    hEst = complex(zeros(K, L, Nr, Nt));
    refInd = sub2ind([K, L], [2; 5; 8; 11], [1; 2; 3; 4]);
    for n = 1:numel(refInd)
        [k, l] = ind2sub([K, L], refInd(n));
        rxGridIRC(k, l, 1) = 1 + 0.05j * n;
        rxGridIRC(k, l, 2) = 0.45 - 0.02j * n;
        hEst(k, l, 1, 1) = 1;
        hEst(k, l, 2, 1) = 0.5;
    end
    [Rint, rinfo] = sixgr.phy.rx.estimateInterferenceCovarianceIRC( ...
        rxGridIRC, hEst, refInd, ones(numel(refInd), 1), 0.01, ...
        "MinSamples", numel(refInd));
    assert(isequal(size(Rint), [Nr Nr]), "IRC covariance must be Nr-by-Nr.");
    assert(all(isfinite(Rint), "all"), "IRC covariance must be finite.");
    assert(norm(Rint - Rint', "fro") < 1e-10, "IRC covariance must be Hermitian.");
    assert(logical(rinfo.Available), "IRC covariance must be available for valid pilot residuals.");
end

ok = true;
end
