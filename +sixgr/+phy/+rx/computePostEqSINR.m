function [sinr_dB, sinr_per_re_dB, info] = computePostEqSINR(hEstSym, nVar, varargin)
%COMPUTEPOSTEQSINR Estimate post-equalization SINR from EqualizerResult.
%
%   The preferred path supplies "EqualizerResult" from mimoDetect. If that
%   is not supplied, this helper constructs the same result through
%   equalizeMMSE using a zero receive-symbol vector, so there is still one
%   source of equalizer mathematics.

ip = inputParser;
ip.addParameter("Method", "mmse", @(s) any(strcmpi(char(string(s)), ["mmse","irc","zf","mrc"])));
ip.addParameter("Rint", [], @(x) isempty(x) || isnumeric(x));
ip.addParameter("Layers", [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x >= 1));
ip.addParameter("MaxTrustedSINR_dB", NaN, @(x) isempty(x) || (isnumeric(x) && isscalar(x)));
ip.addParameter("EqualizerResult", struct(), @(x) isempty(x) || isstruct(x));
ip.addParameter("RIncludesNoise", [], @(x) isempty(x) || islogical(x) || isnumeric(x));
ip.parse(varargin{:});
opt = ip.Results;

info = localDefaultInfo(opt);
sinr_dB = NaN;
sinr_per_re_dB = [];

eqResult = opt.EqualizerResult;
if ~(isstruct(eqResult) && isfield(eqResult, "PostEqSINRLinear") && ~isempty(eqResult.PostEqSINRLinear))
    if isempty(hEstSym) || ~isnumeric(hEstSym)
        info.NAReason = "empty_or_non_numeric_channel_estimate";
        sixgr.perf.TimeProfiler.markSkipped("sixgr.phy.rx.computePostEqSINR", ...
            "post_equalization_sinr", info.NAReason);
        return;
    end
    nVar = double(nVar);
    if ~(isscalar(nVar) && isfinite(nVar) && nVar > 0)
        info.NAReason = "invalid_or_unavailable_noise_variance";
        sixgr.perf.TimeProfiler.markSkipped("sixgr.phy.rx.computePostEqSINR", ...
            "post_equalization_sinr", info.NAReason);
        return;
    end
    [H, dims, badReason] = localNormalizeH(hEstSym);
    if strlength(badReason) > 0
        info.NAReason = char(badReason);
        sixgr.perf.TimeProfiler.markSkipped("sixgr.phy.rx.computePostEqSINR", ...
            "post_equalization_sinr", info.NAReason);
        return;
    end
    cacheKey = localEqualizerCacheKey(H, nVar, opt, dims);
    [cacheHit, eqResult] = localEqualizerResultCache("lookup", cacheKey);
    info.CacheEligible = true;
    info.CacheKey = string(cacheKey);
    info.CacheHit = logical(cacheHit);
    if cacheHit
        info.EqualizerResultSource = "computed_from_channel_estimate_cache";
    else
        profScope = sixgr.perf.TimeProfiler.scope("sixgr.phy.rx.computePostEqSINR", ...
            "Stage", "post_equalization_sinr", ...
            "Metadata", struct("NRE", double(dims.NRE), "NRx", double(dims.NumRxAnt), ...
            "NTx", double(dims.NumTxPorts), "NLayers", double(localResolveLayerCount(opt.Layers, dims)))); %#ok<NASGU>
        rxZeros = complex(zeros(dims.NRE, dims.NumRxAnt));
        args = {"Algorithm", upper(string(opt.Method)), "Rint", opt.Rint};
        if ~isempty(opt.RIncludesNoise)
            args = [args, {"RIncludesNoise", logical(opt.RIncludesNoise)}]; %#ok<AGROW>
        end
        [~, ~, eqInfo] = sixgr.phy.rx.equalizeMMSE(rxZeros, H, nVar, args{:});
        eqResult = eqInfo.EqualizerResult;
        localEqualizerResultCache("store", cacheKey, eqResult);
        info.EqualizerResultSource = "computed_from_channel_estimate";
    end
else
    info.EqualizerResultSource = "supplied_by_mimoDetect";
end

[sinrLin, layerCount] = localExtractSINR(eqResult, opt.Layers);
valid = isfinite(sinrLin) & sinrLin >= 0;
if ~any(valid(:))
    info.NAReason = "no_valid_post_equalization_sinr_samples";
    return;
end

perLayer = localGeometricLayerSINR(sinrLin);
validLayers = perLayer(isfinite(perLayer));
if isempty(validLayers)
    info.NAReason = "no_valid_post_equalization_sinr_layers";
    return;
end

rawPerLayer = double(perLayer);
rawSINR_dB = mean(validLayers, "omitnan");
sinr_dB = double(rawSINR_dB);
sinr_per_re_dB = 10 .* log10(max(sinrLin, eps));
sinr_per_re_dB(~valid) = NaN;

maxTrustedSINR = double(opt.MaxTrustedSINR_dB);
if ~(isscalar(maxTrustedSINR) && isfinite(maxTrustedSINR) && maxTrustedSINR > 0)
    maxTrustedSINR = inf;
end
if isfinite(maxTrustedSINR)
    sinr_dB = min(double(sinr_dB), double(maxTrustedSINR));
    perLayer = min(double(perLayer), double(maxTrustedSINR));
    sinr_per_re_dB = min(double(sinr_per_re_dB), double(maxTrustedSINR));
end

info.SINR_dB = double(sinr_dB);
info.ValueStatus = "OK";
info.NAReason = "";
info.Method = char(lower(string(sixgr.util.structGet(eqResult, "AlgorithmUsed", opt.Method))));
info.PerLayerSINR_dB = double(perLayer);
info.RawSINR_dB = double(rawSINR_dB);
info.RawPerLayerSINR_dB = double(rawPerLayer);
info.MaxTrustedSINR_dB = double(maxTrustedSINR);
if isfinite(maxTrustedSINR) && isfinite(rawSINR_dB) && rawSINR_dB > maxTrustedSINR
    info.ValueStatus = "OK_dynamic_range_limited";
    info.NAReason = sprintf("raw_post_eq_sinr_%.6g_dB_limited_to_max_trusted_%.6g_dB", ...
        double(rawSINR_dB), double(maxTrustedSINR));
end
info.NRE = double(size(sinrLin, 1));
info.NumRxAnt = double(sixgr.util.structGet(eqResult, "NumRxAnt", NaN));
info.NumTxPorts = double(sixgr.util.structGet(eqResult, "NumTxPorts", NaN));
info.NumLayers = double(layerCount);
info.NoiseVariance = double(sixgr.util.structGet(eqResult, "PreEqualizationNoiseVariance", nVar));
info.ImpairmentCovarianceUsed = ~strcmp(string(sixgr.util.structGet(eqResult, "CovarianceSource", "")), "white_noise_variance");
if logical(info.ImpairmentCovarianceUsed)
    info.ImpairmentCovarianceSource = "dmrs_residual_impairment_covariance";
end
info.EqualizerResultContract = string(sixgr.util.structGet(eqResult, "ContractVersion", ""));
info.EqualizerEquation = string(sixgr.util.structGet(eqResult, "Equation", ""));
info.EqualizerSolveCount = double(sixgr.util.structGet(eqResult, "SolveCount", NaN));
info.EqualizerUniqueSolveCount = double(sixgr.util.structGet(eqResult, "UniqueSolveCount", NaN));
info.EqualizerStaticChannelBatchApplied = logical(sixgr.util.structGet(eqResult, "StaticChannelBatchApplied", false));
info.EqualizerRegularizationApplied = logical(sixgr.util.structGet(eqResult, "RegularizationApplied", false));
info.DemapperReliability = localFirstLayers(sixgr.util.structGet(eqResult, "DemapperReliability", []), layerCount);
info.PostEqSINRLinear = sinrLin;
info.DemapperReliabilityMean = localFiniteMean(info.DemapperReliability);
info.ResidualInterLayerPowerMean = localFiniteMean(sixgr.util.structGet(eqResult, "ResidualInterLayerPower", []));
end

function info = localDefaultInfo(opt)
info = struct( ...
    "SINR_dB", NaN, ...
    "Method", char(lower(string(opt.Method))), ...
    "Source", "post_equalization_sinr_from_equalizer_channel_estimate", ...
    "ValueRole", "measured_post_equalization_scheduling_input", ...
    "ValueStatus", "unavailable", ...
    "NAReason", "not_computed", ...
    "PerLayerSINR_dB", NaN, ...
    "NRE", NaN, ...
    "NumRxAnt", NaN, ...
    "NumTxPorts", NaN, ...
    "NumLayers", NaN, ...
    "NoiseVariance", NaN, ...
    "RawSINR_dB", NaN, ...
    "RawPerLayerSINR_dB", NaN, ...
    "MaxTrustedSINR_dB", NaN, ...
    "ImpairmentCovarianceUsed", false, ...
    "ImpairmentCovarianceSource", "", ...
    "EqualizerResultSource", "", ...
    "EqualizerResultContract", "", ...
    "EqualizerEquation", "", ...
    "EqualizerSolveCount", NaN, ...
    "EqualizerUniqueSolveCount", NaN, ...
    "EqualizerStaticChannelBatchApplied", false, ...
    "EqualizerRegularizationApplied", false, ...
    "CacheEligible", false, ...
    "CacheHit", false, ...
    "CacheKey", "", ...
    "DemapperReliability", [], ...
    "PostEqSINRLinear", [], ...
    "DemapperReliabilityMean", NaN, ...
    "ResidualInterLayerPowerMean", NaN);
end

function key = localEqualizerCacheKey(H, nVar, opt, dims)
payload = struct();
payload.Contract = "sixgr.phy.rx.computePostEqSINR.equalizer_cache.v1";
payload.Method = char(lower(string(opt.Method)));
payload.Layers = double(localResolveLayerCount(opt.Layers, dims));
payload.NoiseVariance = double(nVar);
payload.RIncludesNoise = localOptionalLogicalToken(opt.RIncludesNoise);
payload.Channel = localNumericDigest(H);
payload.Rint = localNumericDigest(opt.Rint);
key = char(sixgr.util.sha256Hex(jsonencode(payload)));
end

function token = localOptionalLogicalToken(value)
if isempty(value)
    token = "unspecified";
else
    value = logical(value);
    token = string(value(1));
end
end

function digest = localNumericDigest(x)
digest = struct();
digest.Class = char(string(class(x)));
digest.Size = double(size(x));
digest.IsEmpty = isempty(x);
digest.IsComplex = ~isreal(x);
digest.IsSparse = issparse(x);
if isempty(x)
    digest.SHA256 = "";
    return;
end
if issparse(x)
    x = full(x);
end
bytes = localNumericBytes(x);
digest.SHA256 = char(sixgr.util.sha256Hex(bytes));
end

function bytes = localNumericBytes(x)
if islogical(x)
    bytes = uint8(x(:).');
    return;
end
if ~isnumeric(x)
    bytes = uint8(unicode2native(char(string(x)), "UTF-8"));
    return;
end
x = full(x);
if ~isreal(x)
    bytes = [typecast(real(x(:)).', "uint8"), typecast(imag(x(:)).', "uint8")];
else
    bytes = typecast(x(:).', "uint8");
end
end

function varargout = localEqualizerResultCache(action, key, eqResult)
persistent cache
if isempty(cache)
    cache = containers.Map("KeyType", "char", "ValueType", "any");
end
action = lower(string(action));
key = char(string(key));
switch action
    case "lookup"
        hit = isKey(cache, key);
        if hit
            varargout = {true, cache(key)};
        else
            varargout = {false, struct()};
        end
    case "store"
        if nargin < 3
            varargout = {};
            return;
        end
        if cache.Count >= 256 && ~isKey(cache, key)
            k = keys(cache);
            remove(cache, k{1});
        end
        cache(key) = eqResult;
        varargout = {};
    otherwise
        error("sixgr:phy:rx:PostEqSINR:BadCacheAction", ...
            "Unsupported post-equalization SINR cache action '%s'.", action);
end
end

function [H, dims, reason] = localNormalizeH(hEstSym)
reason = "";
H = hEstSym;
switch ndims(H)
    case 2
        nRE = size(H, 1);
        nRx = size(H, 2);
        nTx = 1;
        H = reshape(H, nRE, nRx, nTx);
    case 3
        nRE = size(H, 1);
        nRx = size(H, 2);
        nTx = size(H, 3);
    case 4
        sz = size(H);
        nRE = sz(1) * sz(2);
        nRx = sz(3);
        nTx = sz(4);
        H = reshape(H, nRE, nRx, nTx);
    otherwise
        dims = struct("NRE", NaN, "NumRxAnt", NaN, "NumTxPorts", NaN);
        reason = "unsupported_channel_estimate_rank";
        return;
end
if nRE < 1 || nRx < 1 || nTx < 1
    reason = "empty_channel_estimate_dimensions";
end
dims = struct("NRE", double(nRE), "NumRxAnt", double(nRx), "NumTxPorts", double(nTx));
end

function n = localResolveLayerCount(layers, dims)
if isempty(layers)
    n = min(double(dims.NumRxAnt), double(dims.NumTxPorts));
else
    n = max(1, min(round(double(layers)), min(double(dims.NumRxAnt), double(dims.NumTxPorts))));
end
end

function [sinrLin, layerCount] = localExtractSINR(eqResult, layers)
sinrLin = double(sixgr.util.structGet(eqResult, "PostEqSINRLinear", []));
if isempty(sinrLin)
    sinrLin = [];
    layerCount = 0;
    return;
end
if isvector(sinrLin)
    sinrLin = sinrLin(:);
end
maxLayers = size(sinrLin, 2);
if isempty(layers)
    layerCount = maxLayers;
else
    layerCount = max(1, min(round(double(layers)), maxLayers));
end
sinrLin = sinrLin(:, 1:layerCount);
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

function v = localFiniteMean(x)
if isempty(x)
    v = NaN;
    return;
end
x = double(x(:));
x = x(isfinite(x));
if isempty(x)
    v = NaN;
else
    v = mean(x, "omitnan");
end
end

function y = localFirstLayers(x, layerCount)
y = x;
if isempty(x) || ~isnumeric(x)
    y = [];
    return;
end
if isvector(x)
    y = x(:);
    return;
end
n = min(size(x, 2), max(1, round(double(layerCount))));
y = x(:, 1:n);
end
