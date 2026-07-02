function [eqSym, csi, info] = equalizeMMSE(rx, hEst, nVar, varargin)
%EQUALIZEMMSE Canonical linear MMSE/IRC/ZF equalizer for extracted REs.
%
%   [eqSym,csi,info] = sixgr.phy.rx.equalizeMMSE(rx,hEst,nVar,...)
%   returns legacy equalized symbols and CSI weights, and also exposes the
%   full EqualizerResult contract in info.EqualizerResult. The result is the
%   single source for symbols, WH effective response, residual inter-layer
%   power, output covariance, demapper reliability and post-EQ SINR.

ind = [];
alg = "MMSE";
Rint = [];
RIncludesNoise = [];
if ~isempty(varargin)
    if mod(numel(varargin), 2) ~= 0
        error("sixgr:phy:equalizeMMSE:InvalidNV", "Name-value inputs must be in pairs.");
    end
    for ii = 1:2:numel(varargin)
        name = varargin{ii};
        val = varargin{ii+1};
        if ~(ischar(name) || isstring(name))
            error("sixgr:phy:equalizeMMSE:InvalidNV", "Name must be char or string.");
        end
        switch lower(char(string(name)))
            case "indices"
                ind = val;
            case "algorithm"
                alg = upper(strtrim(string(val)));
            case "rint"
                Rint = val;
            case {"rincludesnoise","rintincludesnoise","covarianceincludesnoise"}
                RIncludesNoise = logical(val);
            otherwise
                error("sixgr:phy:equalizeMMSE:UnknownNV", "Unknown name-value: %s", char(string(name)));
        end
    end
end
if strlength(alg) == 0
    alg = "MMSE";
end

usedExtraction = false;
rxSym = rx;
hSym = hEst;
if ~isempty(ind)
    usedExtraction = true;
    if exist("nrExtractResources", "file") ~= 2
        error("sixgr:phy:equalizeMMSE:MissingFunc", "nrExtractResources not found.");
    end
    [rxSym, hSym] = nrExtractResources(ind, rx, hEst);
end

[rxSym, hSym, dims] = localNormalizeInputs(rxSym, hSym);
nVarSafe = localSafeNoiseVariance(nVar, rxSym);
if isempty(RIncludesNoise)
    RIncludesNoise = ~isempty(Rint);
end

result = localBuildEqualizerResult(rxSym, hSym, nVarSafe, alg, Rint, logical(RIncludesNoise));
eqSym = result.EqualizedSymbols;
csi = result.DemapperReliability;

info = struct();
info.EngineUsed = char(string(result.EngineUsed));
info.AlgorithmUsed = char(string(result.AlgorithmUsed));
info.UsedExtraction = logical(usedExtraction);
info.RxSize = size(rxSym);
info.HEstSize = size(hSym);
info.EqSize = size(eqSym);
info.NVar = double(nVarSafe);
info.EqualizerResult = result;
info.SolveCount = double(result.SolveCount);
info.UniqueSolveCount = double(result.UniqueSolveCount);
info.StaticChannelBatchApplied = logical(result.StaticChannelBatchApplied);
info.CovarianceIncludesNoise = logical(result.CovarianceIncludesNoise);
info.CovarianceSource = char(string(result.CovarianceSource));
info.NumRxAnt = double(dims.NumRxAnt);
info.NumTxPorts = double(dims.NumTxPorts);
end

function [rxSym, hSym, dims] = localNormalizeInputs(rxSym, hSym)
if isempty(rxSym) || isempty(hSym)
    error("sixgr:phy:equalizeMMSE:EmptyInput", "rx and hEst must be non-empty.");
end
if isvector(rxSym)
    rxSym = rxSym(:);
end
if ~isnumeric(rxSym) || ~isnumeric(hSym)
    error("sixgr:phy:equalizeMMSE:BadInput", "rx and hEst must be numeric.");
end
if ndims(hSym) == 2
    hSym = reshape(hSym, size(hSym, 1), size(hSym, 2), 1);
elseif ndims(hSym) ~= 3
    error("sixgr:phy:equalizeMMSE:BadHShape", "hEst must be NRE-by-NRx-by-NTx after extraction.");
end
if size(rxSym, 1) ~= size(hSym, 1)
    error("sixgr:phy:equalizeMMSE:RECountMismatch", ...
        "rx has %d RE rows but hEst has %d.", size(rxSym, 1), size(hSym, 1));
end
if size(rxSym, 2) ~= size(hSym, 2)
    error("sixgr:phy:equalizeMMSE:RxAntennaMismatch", ...
        "rx has %d receive columns but hEst has %d.", size(rxSym, 2), size(hSym, 2));
end
dims = struct("NRE", double(size(rxSym, 1)), ...
    "NumRxAnt", double(size(rxSym, 2)), ...
    "NumTxPorts", double(size(hSym, 3)));
end

function result = localBuildEqualizerResult(rxSym, hSym, nVar, alg, Rint, RIncludesNoise)
nRE = size(rxSym, 1);
nRx = size(rxSym, 2);
nTx = size(hSym, 3);
alg = localResolveAlgorithm(alg, Rint);

eqSym = complex(zeros(nRE, nTx));
reliability = zeros(nRE, nTx);
sinrLin = NaN(nRE, nTx);
Wout = complex(NaN(nRE, nTx, nRx));
WHout = complex(NaN(nRE, nTx, nTx));
residualLayerPower = NaN(nRE, nTx);
outputCov = complex(NaN(nRE, nTx, nTx));
regularized = false(nRE, 1);

[Rmode, Rstatic, RperRE, covarianceSource] = localNormalizeCovariance(Rint, nRE, nRx, nVar, RIncludesNoise);
solveCount = 0;
uniqueSolveCount = 0;
staticChannelBatch = localIsStaticChannel(hSym) && Rmode ~= "per_re";

if nRx == 1 && nTx == 1 && alg ~= "ZF"
    H = hSym(:, 1, 1);
    Rdiag = localSISOCovarianceDiagonal(Rmode, Rstatic, RperRE, nRE, nVar);
    denom = abs(H).^2 + Rdiag;
    W = conj(H) ./ max(denom, eps);
    eqSym(:, 1) = W .* rxSym(:, 1);
    WH = W .* H;
    noiseOut = abs(W).^2 .* Rdiag;
    signal = abs(WH).^2;
    gamma = signal ./ max(noiseOut, eps);
    sinrLin(:, 1) = gamma;
    reliability(:, 1) = gamma ./ max(1 + gamma, eps);
    Wout(:, 1, 1) = W;
    WHout(:, 1, 1) = WH;
    residualLayerPower(:, 1) = 0;
    outputCov(:, 1, 1) = noiseOut;
    solveCount = nRE;
    uniqueSolveCount = 0;
    engine = "vectorizedSISO";
elseif staticChannelBatch
    H0 = localHAt(hSym, 1, nRx, nTx);
    R0 = localCovarianceAt(Rmode, Rstatic, RperRE, 1, nRx, nVar, RIncludesNoise);
    [core, reg] = localEqualizerCore(H0, R0, alg);
    [eqSym, reliability, sinrLin, Wout, WHout, residualLayerPower, outputCov] = ...
        localApplyStaticCore(rxSym, core, nRE, nTx, nRx);
    regularized(:) = reg;
    solveCount = nRE;
    uniqueSolveCount = 1;
    engine = "batchedStaticChannel";
else
    engine = "perREStableSolve";
    for kk = 1:nRE
        Hk = localHAt(hSym, kk, nRx, nTx);
        Rk = localCovarianceAt(Rmode, Rstatic, RperRE, kk, nRx, nVar, RIncludesNoise);
        [core, reg] = localEqualizerCore(Hk, Rk, alg);
        rk = rxSym(kk, :).';
        sk = core.W * rk;
        eqSym(kk, :) = sk.';
        reliability(kk, :) = core.Reliability.';
        sinrLin(kk, :) = core.SINRLinear.';
        Wout(kk, :, :) = core.W;
        WHout(kk, :, :) = core.WH;
        residualLayerPower(kk, :) = core.ResidualInterLayerPower.';
        outputCov(kk, :, :) = core.OutputCovariance;
        regularized(kk) = reg;
        solveCount = solveCount + 1;
        uniqueSolveCount = uniqueSolveCount + 1;
    end
end

result = struct();
result.ContractVersion = "EqualizerResult/v1";
result.AlgorithmUsed = alg;
result.EngineUsed = engine;
result.Equation = "W=(H^H R^-1 H + I)^-1 H^H R^-1";
result.SymbolCovarianceConvention = "unit_layer_symbol_covariance";
result.EqualizedSymbols = eqSym;
result.DemapperReliability = reliability;
result.CSI = reliability;
result.PostEqSINRLinear = sinrLin;
result.PostEqSINRPerRE_dB = 10 .* log10(max(sinrLin, eps));
result.PerLayerSINR_dB = localGeometricLayerSINR(sinrLin);
result.W = Wout;
result.EffectiveResponseWH = WHout;
result.ResidualInterLayerPower = residualLayerPower;
result.OutputNoiseInterferenceCovariance = outputCov;
result.CovarianceIncludesNoise = logical(RIncludesNoise || isempty(Rint));
result.CovarianceSource = covarianceSource;
result.NoiseAddedExactlyOnce = true;
result.PreEqualizationNoiseVariance = double(nVar);
result.NRE = double(nRE);
result.NumRxAnt = double(nRx);
result.NumTxPorts = double(nTx);
result.SolveCount = double(solveCount);
result.UniqueSolveCount = double(uniqueSolveCount);
result.StaticChannelBatchApplied = logical(staticChannelBatch);
result.RegularizationApplied = any(regularized);
result.RegularizedRECount = double(nnz(regularized));
end

function alg = localResolveAlgorithm(alg, Rint)
alg = upper(strtrim(string(alg)));
if strlength(alg) == 0
    alg = "MMSE";
end
if alg == "IRC" && isempty(Rint)
    alg = "MMSE";
elseif ~(alg == "MMSE" || alg == "IRC" || alg == "ZF")
    error("sixgr:phy:equalizeMMSE:BadAlgorithm", "Unsupported Algorithm=%s", char(alg));
end
end

function [mode, Rstatic, RperRE, source] = localNormalizeCovariance(Rint, nRE, nRx, nVar, RIncludesNoise)
Rstatic = [];
RperRE = [];
if isempty(Rint)
    mode = "white";
    Rstatic = nVar * eye(nRx);
    source = "white_noise_variance";
    return;
end
if ismatrix(Rint) && size(Rint, 1) == nRx && size(Rint, 2) == nRx
    mode = "static";
    Rstatic = localPrepareCovariance(Rint, nVar, logical(RIncludesNoise));
    source = localCovarianceSource(RIncludesNoise);
elseif ndims(Rint) == 3 && size(Rint, 1) == nRE && size(Rint, 2) == nRx && size(Rint, 3) == nRx
    mode = "per_re";
    RperRE = Rint;
    source = localCovarianceSource(RIncludesNoise);
else
    error("sixgr:phy:equalizeMMSE:BadRint", "Rint must be NRx-by-NRx or NRE-by-NRx-by-NRx.");
end
end

function source = localCovarianceSource(RIncludesNoise)
if logical(RIncludesNoise)
    source = "provided_noise_plus_interference_covariance";
else
    source = "provided_interference_covariance_plus_runtime_noise_variance";
end
end

function R = localCovarianceAt(mode, Rstatic, RperRE, kk, nRx, nVar, RIncludesNoise)
switch string(mode)
    case "white"
        R = Rstatic;
    case "static"
        R = Rstatic;
    otherwise
        R = localPrepareCovariance(squeeze(RperRE(kk, :, :)), nVar, logical(RIncludesNoise));
end
if isempty(R)
    R = nVar * eye(nRx);
end
end

function R = localPrepareCovariance(Rin, nVar, includesNoise)
R = double(Rin);
if isempty(R)
    R = [];
    return;
end
R = (R + R') ./ 2;
if ~logical(includesNoise)
    R = R + max(double(nVar), eps) * eye(size(R, 1));
end
if any(~isfinite(real(R(:)))) || any(~isfinite(imag(R(:))))
    R = max(double(nVar), eps) * eye(size(R, 1));
end
end

function Rdiag = localSISOCovarianceDiagonal(mode, Rstatic, RperRE, nRE, nVar)
switch string(mode)
    case "white"
        Rdiag = repmat(double(nVar), nRE, 1);
    case "static"
        Rdiag = repmat(max(real(Rstatic(1, 1)), eps), nRE, 1);
    otherwise
        Rdiag = max(real(reshape(RperRE(:, 1, 1), [], 1)), eps);
end
end

function Hk = localHAt(hSym, kk, nRx, nTx)
Hk = squeeze(hSym(kk, :, :));
if isvector(Hk)
    Hk = reshape(Hk, nRx, nTx);
end
end

function tf = localIsStaticChannel(hSym)
if size(hSym, 1) <= 1
    tf = true;
    return;
end
flat = reshape(hSym, size(hSym, 1), []);
tf = all(flat == flat(1, :), "all");
end

function [core, regularized] = localEqualizerCore(H, R, alg)
regularized = false;
H = double(H);
R = localHermitianPositiveDefinite(R);
if alg == "ZF"
    A = H' * H;
    B = H';
    [W, regA] = localStableLeftSolve(A, B);
    regularized = regA;
else
    [RinvH, regR] = localStableLeftSolve(R, H);
    A = H' * RinvH + eye(size(H, 2));
    B = RinvH';
    [W, regA] = localStableLeftSolve(A, B);
    regularized = regR || regA;
end
WH = W * H;
outCov = W * R * W';
nLayers = size(H, 2);
sinr = NaN(nLayers, 1);
interLayer = NaN(nLayers, 1);
for layer = 1:nLayers
    signal = abs(WH(layer, layer)).^2;
    interLayer(layer) = max(sum(abs(WH(layer, :)).^2) - signal, 0);
    noiseOut = max(real(outCov(layer, layer)), eps);
    sinr(layer) = signal ./ max(interLayer(layer) + noiseOut, eps);
end
core = struct();
core.W = W;
core.WH = WH;
core.OutputCovariance = outCov;
core.ResidualInterLayerPower = interLayer;
core.SINRLinear = sinr;
core.Reliability = sinr ./ max(1 + sinr, eps);
end

function R = localHermitianPositiveDefinite(R)
R = double(R);
R = (R + R') ./ 2;
if isempty(R)
    return;
end
diagLoad = max(norm(R, "fro") * 1e-12, eps);
if any(~isfinite(real(R(:)))) || any(~isfinite(imag(R(:))))
    R = eye(size(R, 1));
end
R = R + diagLoad * eye(size(R, 1));
end

function [X, regularized] = localStableLeftSolve(A, B)
A = double(A);
B = double(B);
A = (A + A') ./ 2;
regularized = false;
if any(~isfinite(real(A(:)))) || any(~isfinite(imag(A(:)))) || ...
        any(~isfinite(real(B(:)))) || any(~isfinite(imag(B(:))))
    error("sixgr:phy:equalizeMMSE:NonFiniteSolve", "Equalizer solve input contains non-finite values.");
end
diagLoad = max(norm(A, "fro") * 1e-12, eps);
if rcond(A) < 1e-10
    A = A + diagLoad * eye(size(A, 1));
    diagLoad = diagLoad * 10;
    regularized = true;
end
for attempt = 1:4
    [L, p] = chol(A, "lower");
    if p == 0
        X = L' \ (L \ B);
        return;
    end
    A = A + diagLoad * eye(size(A, 1));
    diagLoad = diagLoad * 10;
    regularized = true;
end
X = A \ B;
regularized = true;
end

function [eqSym, reliability, sinrLin, Wout, WHout, residualLayerPower, outputCov] = ...
        localApplyStaticCore(rxSym, core, nRE, nTx, nRx)
eqSym = rxSym * core.W.';
reliability = repmat(core.Reliability.', nRE, 1);
sinrLin = repmat(core.SINRLinear.', nRE, 1);
Wout = repmat(reshape(core.W, 1, nTx, nRx), nRE, 1, 1);
WHout = repmat(reshape(core.WH, 1, nTx, nTx), nRE, 1, 1);
residualLayerPower = repmat(core.ResidualInterLayerPower.', nRE, 1);
outputCov = repmat(reshape(core.OutputCovariance, 1, nTx, nTx), nRE, 1, 1);
end

function perLayer = localGeometricLayerSINR(sinrLin)
nLayers = size(sinrLin, 2);
perLayer = NaN(1, nLayers);
for layer = 1:nLayers
    x = double(sinrLin(:, layer));
    x = x(isfinite(x) & x >= 0);
    if ~isempty(x)
        perLayer(layer) = 10 * log10(exp(mean(log(max(x, eps)), "omitnan")));
    end
end
end

function nVarSafe = localSafeNoiseVariance(nVar, rxSym)
nVarSafe = double(nVar);
if ~(isscalar(nVarSafe) && isfinite(nVarSafe) && nVarSafe > 0)
    p = mean(abs(rxSym(:)).^2 + eps, "omitnan");
    if ~(isfinite(p) && p > 0)
        p = 1;
    end
    nVarSafe = 1e-12 * p;
end
end
