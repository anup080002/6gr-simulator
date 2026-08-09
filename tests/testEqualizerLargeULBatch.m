function ok = testEqualizerLargeULBatch()
%TESTEQUALIZERLARGEULBATCH Exercise exact rank-2/64-branch UL grid scale.

ok = false;
rng(6402, "twister");
nRE = 3276;
nRx = 64;
nLayers = 2;
rxSym = complex(randn(nRE, nRx), randn(nRE, nRx)) / sqrt(2);
hSym = complex(randn(nRE, nRx, nLayers), ...
    randn(nRE, nRx, nLayers)) / sqrt(2 * nRx);
noiseVariance = 0.125;
interferenceCovariance = diag(linspace(0.01, 0.04, nRx));

started = tic;
[eqSym, reliability, info] = sixgr.phy.rx.equalizeMMSE( ...
    rxSym, hSym, noiseVariance, ...
    "Algorithm", "IRC", ...
    "Rint", interferenceCovariance, ...
    "RIncludesNoise", false);
elapsed = toc(started);

assert(isequal(size(eqSym), [nRE nLayers]) && ...
    isequal(size(reliability), [nRE nLayers]));
assert(all(isfinite(real(eqSym)), "all") && ...
    all(isfinite(imag(eqSym)), "all") && ...
    all(isfinite(reliability), "all") && all(reliability > 0, "all"));
assert(string(info.EngineUsed) == "batchedStaticCovarianceVariableChannel");
assert(info.CovarianceFactorizationCount == 1 && ...
    info.SolveCount == nRE && info.UniqueSolveCount == nRE);
assert(info.NumRxAnt == nRx && info.NumTxPorts == nLayers);

fprintf(["PASS testEqualizerLargeULBatch: %d RE, %dx%d exact IRC, " + ...
    "one covariance factorization, %.3f s.\n"], ...
    nRE, nRx, nLayers, elapsed);
ok = true;
end
