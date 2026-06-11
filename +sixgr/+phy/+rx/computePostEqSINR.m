function [sinr_dB, sinr_per_re_dB, info] = computePostEqSINR(hEstSym, nVar, varargin)
%COMPUTEPOSTEQSINR Estimate post-equalization SINR from data-RE channel estimates.
%
%   This helper returns a scheduler-eligible data-domain SINR from the same
%   extracted resource-element channel estimate and noise variance used by
%   the linear equalizer. Pilot/Hest residual metrics and post-decode EVM
%   proxies must not be fed to CQI/MCS selection as if they were this value.

ip = inputParser;
ip.addParameter("Method", "mmse", @(s) any(strcmpi(char(string(s)), ["mmse","irc","zf","mrc"])));
ip.addParameter("Rint", [], @(x) isempty(x) || isnumeric(x));
ip.addParameter("Layers", [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x >= 1));
ip.parse(varargin{:});
opt = ip.Results;

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
    "ImpairmentCovarianceUsed", false, ...
    "ImpairmentCovarianceSource", "");
sinr_dB = NaN;
sinr_per_re_dB = [];

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
        info.NAReason = "unsupported_channel_estimate_rank";
        sixgr.perf.TimeProfiler.markSkipped("sixgr.phy.rx.computePostEqSINR", ...
            "post_equalization_sinr", info.NAReason);
        return;
end
if nRE < 1 || nRx < 1 || nTx < 1
    info.NAReason = "empty_channel_estimate_dimensions";
    sixgr.perf.TimeProfiler.markSkipped("sixgr.phy.rx.computePostEqSINR", ...
        "post_equalization_sinr", info.NAReason);
    return;
end
nLayers = min(nRx, nTx);
if ~isempty(opt.Layers)
    nLayers = max(1, min(round(double(opt.Layers)), min(nRx, nTx)));
end
profScope = sixgr.perf.TimeProfiler.scope("sixgr.phy.rx.computePostEqSINR", ...
    "Stage", "post_equalization_sinr", ...
    "Metadata", struct("NRE", double(nRE), "NRx", double(nRx), "NTx", double(nTx), ...
    "NLayers", double(nLayers))); %#ok<NASGU>
method = lower(string(opt.Method));
rint = opt.Rint;
usePerRERint = ~isempty(rint) && ndims(rint) == 3 && size(rint, 1) == nRE && size(rint, 2) == nRx && size(rint, 3) == nRx;
useStaticRint = ~isempty(rint) && ismatrix(rint) && size(rint, 1) == nRx && size(rint, 2) == nRx;
if method == "irc" && ~(usePerRERint || useStaticRint)
    method = "mmse";
    info.Method = "mmse";
end

sinrLin = nan(nRE, nLayers);
for k = 1:nRE
    Hk = squeeze(H(k, :, :));
    if isvector(Hk)
        Hk = reshape(Hk, nRx, nTx);
    end
    if any(~isfinite(real(Hk(:)))) || any(~isfinite(imag(Hk(:))))
        continue;
    end

    switch method
        case {"mmse","irc"}
            whiteCov = nVar * eye(nRx);
            actualCov = whiteCov;
            impairmentCovUsed = false;
            if method == "irc" && usePerRERint
                Rnn = localRegularizeCovariance(squeeze(rint(k, :, :)), nVar);
                actualCov = Rnn;
                impairmentCovUsed = true;
            elseif method == "irc" && useStaticRint
                Rnn = localRegularizeCovariance(rint, nVar);
                actualCov = Rnn;
                impairmentCovUsed = true;
            else
                Rnn = whiteCov;
                if usePerRERint
                    actualCov = localRegularizeCovariance(squeeze(rint(k, :, :)), nVar);
                    impairmentCovUsed = true;
                elseif useStaticRint
                    actualCov = localRegularizeCovariance(rint, nVar);
                    impairmentCovUsed = true;
                end
            end
            W = localStableRightSolve(Hk', Hk * Hk' + Rnn);
            if isempty(W)
                continue;
            end
            G = W * Hk;
            noiseCov = W * actualCov * W';
            for layer = 1:nLayers
                signalPower = abs(G(layer, layer)) .^ 2;
                interferencePower = sum(abs(G(layer, :)) .^ 2) - signalPower;
                noisePower = real(noiseCov(layer, layer));
                sinrLin(k, layer) = signalPower / max(interferencePower + noisePower, eps);
            end
            if impairmentCovUsed
                info.ImpairmentCovarianceUsed = true;
            end

        case "zf"
            W = pinv(Hk);
            G = W * Hk;
            if usePerRERint
                actualCov = localRegularizeCovariance(squeeze(rint(k, :, :)), nVar);
                info.ImpairmentCovarianceUsed = true;
            elseif useStaticRint
                actualCov = localRegularizeCovariance(rint, nVar);
                info.ImpairmentCovarianceUsed = true;
            else
                actualCov = nVar * eye(nRx);
            end
            noiseCov = W * actualCov * W';
            for layer = 1:nLayers
                signalPower = abs(G(layer, layer)) .^ 2;
                interferencePower = sum(abs(G(layer, :)) .^ 2) - signalPower;
                noisePower = real(noiseCov(layer, layer));
                sinrLin(k, layer) = signalPower / max(interferencePower + noisePower, eps);
            end

        case "mrc"
            for layer = 1:nLayers
                h = Hk(:, layer);
                sinrLin(k, layer) = real(h' * h) / max(nVar, eps);
            end
    end
end

valid = isfinite(sinrLin) & sinrLin > 0;
if ~any(valid(:))
    info.NAReason = "no_valid_post_equalization_sinr_samples";
    return;
end

perLayer = nan(1, nLayers);
for layer = 1:nLayers
    values = sinrLin(valid(:, layer), layer);
    if ~isempty(values)
        perLayer(layer) = 10 * log10(exp(mean(log(values))));
    end
end
validLayers = perLayer(isfinite(perLayer));
if isempty(validLayers)
    info.NAReason = "no_valid_post_equalization_sinr_layers";
    return;
end

sinr_dB = mean(validLayers);
sinr_per_re_dB = 10 * log10(max(sinrLin, eps));
sinr_per_re_dB(~valid) = NaN;

info.SINR_dB = double(sinr_dB);
info.ValueStatus = "OK";
info.NAReason = "";
info.PerLayerSINR_dB = double(perLayer);
info.NRE = double(nRE);
info.NumRxAnt = double(nRx);
info.NumTxPorts = double(nTx);
info.NumLayers = double(nLayers);
info.NoiseVariance = double(nVar);
if logical(info.ImpairmentCovarianceUsed)
    info.ImpairmentCovarianceSource = "dmrs_residual_impairment_covariance";
end
end

function R = localRegularizeCovariance(Rin, nVar)
R = double(Rin);
R = (R + R') ./ 2;
if any(~isfinite(real(R(:)))) || any(~isfinite(imag(R(:))))
    R = max(double(nVar), eps) * eye(size(R, 1));
    return;
end
diagonalFloor = max(double(nVar) * 1e-6, eps);
R = R + diagonalFloor * eye(size(R, 1));
if rcond(R) < 1e-12
    R = R + max(diagonalFloor, norm(R, "fro") * 1e-10) * eye(size(R, 1));
end
end

function X = localStableRightSolve(B, A)
X = [];
if isempty(A) || isempty(B) || size(A, 1) ~= size(A, 2) || size(B, 2) ~= size(A, 1)
    return;
end
A = double(A);
B = double(B);
if any(~isfinite(real(A(:)))) || any(~isfinite(imag(A(:)))) || ...
        any(~isfinite(real(B(:)))) || any(~isfinite(imag(B(:))))
    return;
end
A = (A + A') ./ 2;
s = svd(A);
s = double(s(isfinite(s) & s >= 0));
if isempty(s)
    return;
end
sMax = max(s);
if ~(isfinite(sMax) && sMax > 0)
    return;
end
rcondEstimate = min(s) / max(sMax, eps);
if rcondEstimate < 1e-10
    diagonalLoad = max(sMax * 1e-8, eps(class(sMax)));
    A = A + diagonalLoad * eye(size(A, 1));
    s = svd(A);
    s = double(s(isfinite(s) & s >= 0));
    if isempty(s)
        return;
    end
    sMax = max(s);
    rcondEstimate = min(s) / max(sMax, eps);
end
if rcondEstimate < 1e-12
    X = B * pinv(A);
else
    X = B / A;
end
end
