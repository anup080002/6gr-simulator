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
                if ~((islogical(val) || isnumeric(val)) && isscalar(val) && ...
                        isreal(val) && isfinite(val) && any(val == [0 1]))
                    error("sixgr:phy:equalizeMMSE:BadNoiseInclusionFlag", ...
                        "RIncludesNoise must be a scalar logical value.");
                end
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
nVarSafe = localValidateNoiseVariance(nVar);
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
info.CovarianceFactorizationCount = double(result.CovarianceFactorizationCount);
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
% A 1-by-NRx row is one multi-antenna RE, not NRx SISO REs.
if isvector(rxSym) && size(hSym,2)==1 && numel(rxSym)==size(hSym,1)
    rxSym = rxSym(:);
end
if ~isnumeric(rxSym) || ~isnumeric(hSym)
    error("sixgr:phy:equalizeMMSE:BadInput", "rx and hEst must be numeric.");
end
if ~ismatrix(rxSym) || any(~isfinite(real(rxSym(:)))) || ...
        any(~isfinite(imag(rxSym(:)))) || any(~isfinite(real(hSym(:)))) || ...
        any(~isfinite(imag(hSym(:))))
    error("sixgr:phy:equalizeMMSE:InvalidObservation", ...
        "Extracted rx/Hest must have finite numeric samples and rx must be a matrix.");
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
covarianceFactorizationCount = 0;
staticChannelBatch = localIsStaticChannel(hSym) && Rmode ~= "per_re";

if nRx == 1 && nTx == 1 && alg ~= "ZF"
    H = double(hSym(:, 1, 1));
    Rdiag = localSISOCovarianceDiagonal(Rmode, Rstatic, RperRE, nRE, nVar);
    denom = abs(H).^2 + Rdiag;
    W = complex(zeros(size(H)));
    observed = denom > 0;
    W(observed) = conj(H(observed)) ./ denom(observed);
    eqSym(:, 1) = W .* rxSym(:, 1);
    WH = W .* H;
    noiseOut = abs(W).^2 .* Rdiag;
    signal = abs(WH).^2;
    gamma = localPhysicalSINR(signal,noiseOut);
    sinrLin(:, 1) = gamma;
    reliability(:, 1) = localReliability(gamma);
    Wout(:, 1, 1) = W;
    WHout(:, 1, 1) = WH;
    residualLayerPower(:, 1) = 0;
    outputCov(:, 1, 1) = noiseOut;
    solveCount = nRE;
    uniqueSolveCount = 0;
    covarianceFactorizationCount = 0;
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
    covarianceFactorizationCount = double(alg ~= "ZF");
    engine = "batchedStaticChannel";
elseif Rmode ~= "per_re" && alg ~= "ZF"
    % H varies per RE, but white/static disturbance covariance does not.
    % Factor the NRx-by-NRx covariance once for all channel right-hand
    % sides, then retain the exact per-RE small layer-domain solve.  This
    % is algebraically identical to the former per-RE path and avoids
    % thousands of repeated 64-by-64 Cholesky factorizations in 4x64 UL.
    R0 = localCovarianceAt(Rmode, Rstatic, RperRE, 1, nRx, nVar, RIncludesNoise);
    [eqSym, reliability, sinrLin, Wout, WHout, residualLayerPower, ...
        outputCov, regularized, covarianceFactorizationCount] = localApplyStaticCovariance( ...
        rxSym, hSym, R0, nRE, nTx, nRx);
    solveCount = nRE;
    uniqueSolveCount = nRE;
    engine = "batchedStaticCovarianceVariableChannel";
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
    covarianceFactorizationCount = double(alg ~= "ZF") * nRE;
end

result = struct();
result.ContractVersion = "EqualizerResult/v1";
result.AlgorithmUsed = alg;
result.EngineUsed = engine;
if alg == "ZF"
    result.Equation = "W=(H^H*H)^dagger*H^H; Gram-domain numerical rank tolerance";
else
    result.Equation = "W=H^H*(H*H^H+R)^dagger; equivalent whitened solve for positive-definite R";
end
result.SymbolCovarianceConvention = "unit_layer_symbol_covariance";
result.EqualizedSymbols = eqSym;
result.DemapperReliability = reliability;
result.CSI = reliability;
result.PostEqSINRLinear = sinrLin;
result.PostEqSINRPerRE_dB = 10 .* log10(sinrLin);
result.PerLayerSINR_dB = localGeometricLayerSINR(sinrLin);
result.W = Wout;
result.EffectiveResponseWH = WHout;
result.ResidualInterLayerPower = residualLayerPower;
result.OutputNoiseInterferenceCovariance = outputCov;
result.CovarianceIncludesNoise = logical(RIncludesNoise || isempty(Rint));
result.CovarianceSource = covarianceSource;
% Retain the validated physical covariance, not a loaded solve matrix.
% Downstream unit-gain receivers must use this same authority for W*R*W'.
if Rmode == "per_re"
    result.DisturbanceCovariance = RperRE;
else
    result.DisturbanceCovariance = Rstatic;
end
result.DisturbanceCovarianceMode = Rmode;
result.NoiseAddedExactlyOnce = true;
result.PreEqualizationNoiseVariance = double(nVar);
result.NRE = double(nRE);
result.NumRxAnt = double(nRx);
result.NumTxPorts = double(nTx);
result.SolveCount = double(solveCount);
result.UniqueSolveCount = double(uniqueSolveCount);
result.CovarianceFactorizationCount = double(covarianceFactorizationCount);
result.StaticChannelBatchApplied = logical(staticChannelBatch);
result.RegularizationApplied = any(regularized);
result.RegularizedRECount = double(nnz(regularized));
result.PhysicalCovarianceModifiedForSolve = false;
result.NumericalSolvePolicy = "scaled_positive_definite_or_minimum_norm_solve_without_noise_injection";
end

function [eqSym, reliability, sinrLin, Wout, WHout, ...
        residualLayerPower, outputCov, regularized, covarianceFactorizationCount] = ...
        localApplyStaticCovariance(rxSym, hSym, R, nRE, nTx, nRx)
% Apply one exact static disturbance-covariance factorization to all REs.
% R remains the actual physical covariance. A singular covariance uses the
% equivalent receive-covariance MMSE equation per RE; it is never loaded.
[L,p] = chol(R,"lower");
covarianceFactorizationCount = 1;
canWhiten = p==0;
if canWhiten
    allH = reshape(permute(hSym, [2 3 1]), nRx, nTx*nRE);
    allRinvH = L' \ (L \ allH);
end

eqSym = complex(zeros(nRE, nTx));
reliability = zeros(nRE, nTx);
sinrLin = NaN(nRE, nTx);
Wout = complex(NaN(nRE, nTx, nRx));
WHout = complex(NaN(nRE, nTx, nTx));
residualLayerPower = NaN(nRE, nTx);
outputCov = complex(NaN(nRE, nTx, nTx));
regularized = false(nRE, 1);
for kk = 1:nRE
    columns = (kk-1)*nTx + (1:nTx);
    Hk = localHAt(hSym, kk, nRx, nTx);
    if canWhiten
        RinvH = reshape(allRinvH(:, columns), nRx, nTx);
        [core, layerRegularized] = localEqualizerCoreFromRinvH(Hk, R, RinvH);
    else
        [solution,layerRegularized] = localStableLeftSolve(Hk*Hk'+R,Hk);
        core = localEqualizerOutputs(Hk,R,solution');
        covarianceFactorizationCount = covarianceFactorizationCount+1;
    end
    rk = rxSym(kk, :).';
    sk = core.W * rk;
    eqSym(kk, :) = sk.';
    reliability(kk, :) = core.Reliability.';
    sinrLin(kk, :) = core.SINRLinear.';
    Wout(kk, :, :) = core.W;
    WHout(kk, :, :) = core.WH;
    residualLayerPower(kk, :) = core.ResidualInterLayerPower.';
    outputCov(kk, :, :) = core.OutputCovariance;
    regularized(kk) = layerRegularized;
end
end

function [core, regularized] = localEqualizerCoreFromRinvH(H, R, RinvH)
% Complete the exact MMSE/IRC layer solve after a shared R\H operation.
A = H' * RinvH + eye(size(H, 2));
B = RinvH';
[W, regularized] = localStableLeftSolve(A, B);
core = localEqualizerOutputs(H, R, W);
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
elseif ndims(Rint) <= 3 && size(Rint, 1) == nRE && size(Rint, 2) == nRx && size(Rint, 3) == nRx
    mode = "per_re";
    RperRE = complex(zeros(nRE,nRx,nRx));
    for index=1:nRE
        value=localPrepareCovariance(reshape(Rint(index,:,:),nRx,nRx),nVar,logical(RIncludesNoise));
        RperRE(index,:,:) = reshape(value,1,nRx,nRx);
    end
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

function R = localCovarianceAt(mode, Rstatic, RperRE, kk, nRx, ~, ~)
switch string(mode)
    case "white"
        R = Rstatic;
    case "static"
        R = Rstatic;
    otherwise
        R = reshape(RperRE(kk, :, :),nRx,nRx);
end
end

function R = localPrepareCovariance(Rin, nVar, includesNoise)
R = localPhysicalCovariance(Rin);
if ~logical(includesNoise)
    R = R + double(nVar)*eye(size(R,1));
end
end

function Rdiag = localSISOCovarianceDiagonal(mode, Rstatic, RperRE, nRE, nVar)
switch string(mode)
    case "white"
        Rdiag = repmat(double(nVar), nRE, 1);
    case "static"
        Rdiag = repmat(real(Rstatic(1, 1)), nRE, 1);
    otherwise
        Rdiag = real(reshape(RperRE(:, 1, 1), [], 1));
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
H = double(H);
if alg == "ZF"
    [W,regularized] = localStableLeftSolve(H'*H,H');
else
    [L,p] = chol(R,"lower");
    if p==0
        RinvH = L' \ (L \ H);
        [core,regularized] = localEqualizerCoreFromRinvH(H,R,RinvH);
        return;
    end
    % Valid semidefinite/zero covariance: use H^H*(H*H^H+R)^dagger,
    % including the exact minimum-norm zero-noise limit, not invented noise.
    [solution,regularized] = localStableLeftSolve(H*H'+R,H);
    W = solution';
end
core = localEqualizerOutputs(H,R,W);
end

function core = localEqualizerOutputs(H, R, W)
% Derive all receiver outputs from the already-resolved exact filter W.
WH = W * H;
outCov = W * R * W';
nLayers = size(H, 2);
sinr = NaN(nLayers, 1);
interLayer = NaN(nLayers, 1);
for layer = 1:nLayers
    signal = abs(WH(layer, layer)).^2;
    other=[1:layer-1 layer+1:nLayers];
    interLayer(layer) = sum(abs(WH(layer,other)).^2);
    noiseOut = max(real(outCov(layer,layer)),0);
    sinr(layer) = localPhysicalSINR(signal,interLayer(layer)+noiseOut);
end
core = struct();
core.W = W;
core.WH = WH;
core.OutputCovariance = outCov;
core.ResidualInterLayerPower = interLayer;
core.SINRLinear = sinr;
core.Reliability = localReliability(sinr);
end

function R = localPhysicalCovariance(Rin)
if ~isnumeric(Rin) || ~ismatrix(Rin) || isempty(Rin) || ...
        size(Rin,1)~=size(Rin,2) || any(~isfinite(real(Rin(:)))) || ...
        any(~isfinite(imag(Rin(:))))
    error("sixgr:phy:equalizeMMSE:InvalidCovariance", ...
        "Provided physical covariance must be a finite square numeric matrix.");
end
R = double(Rin);
scale = norm(R,"fro");
tolerance = 128*size(R,1)*eps(scale);
if norm(R-R',"fro")>tolerance
    error("sixgr:phy:equalizeMMSE:NonHermitianCovariance", ...
        "Provided physical covariance must be Hermitian.");
end
R = (R+R')/2;
eigenvalues = real(eig(R));
if any(eigenvalues < -tolerance)
    error("sixgr:phy:equalizeMMSE:IndefiniteCovariance", ...
        "Provided physical covariance must be positive semidefinite.");
end
end

function [X, regularized] = localStableLeftSolve(A, B)
A = double(A);
B = double(B);
A = (A+A')/2;
regularized = false;
if any(~isfinite(real(A(:)))) || any(~isfinite(imag(A(:)))) || ...
        any(~isfinite(real(B(:)))) || any(~isfinite(imag(B(:))))
    error("sixgr:phy:equalizeMMSE:NonFiniteSolve", ...
        "Equalizer solve input contains non-finite values.");
end
scale = norm(A,"fro");
if scale==0
    if any(B(:)~=0)
        error("sixgr:phy:equalizeMMSE:InconsistentZeroSolve", ...
            "A zero system matrix cannot support a nonzero observation mapping.");
    end
    X = zeros(size(B));
    regularized = true;
    return;
end
% Normalize numerical scale only: no physical or solver diagonal loading.
A = A/scale;
B = B/scale;
[L,p] = chol(A,"lower");
if p==0 && rcond(A)>=1e-10
    X = L' \ (L \ B);
    return;
end
[V,D] = eig(A,"vector");
D = real(D);
tolerance = 128*size(A,1)*eps(max(abs(D)));
if any(D < -tolerance)
    error("sixgr:phy:equalizeMMSE:IndefiniteSolve", ...
        "Equalizer covariance/Gram matrix is not positive semidefinite.");
end
keep = D > size(A,1)*eps(max(abs(D)));
if any(keep)
    X = V(:,keep)*((V(:,keep)'*B)./D(keep));
else
    X = zeros(size(B));
end
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
    x = x(~isnan(x) & x >= 0);
    if ~isempty(x)
        perLayer(layer) = mean(10*log10(x),"omitnan");
    end
end
end

function value = localValidateNoiseVariance(nVar)
if ~isnumeric(nVar) || ~isscalar(nVar) || ~isreal(nVar) || ...
        ~isfinite(nVar) || nVar<0
    error("sixgr:phy:equalizeMMSE:InvalidNoiseVariance", ...
        "Noise variance must be a finite real nonnegative scalar.");
end
value = double(nVar);
end

function value = localPhysicalSINR(signal,disturbance)
value = signal./disturbance;
value(signal==0 & disturbance==0)=0;
end

function value = localReliability(sinr)
value = sinr./(1+sinr);
value(isinf(sinr) & sinr>0)=1;
end
