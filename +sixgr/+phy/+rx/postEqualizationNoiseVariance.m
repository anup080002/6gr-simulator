function [nVarEff, info] = postEqualizationNoiseVariance(nVarPreEq, varargin)
%POSTEQUALIZATIONNOISEVARIANCE Convert receiver noise to decoder symbol domain.
%
% nrPDSCHDecode/nrPUSCHDecode demap equalized symbols, so the scalar noise
% variance used for LLR generation must be in the same post-equalization
% unit-constellation domain as the symbols. Prefer measured post-eq SINR
% from the actual equalizer channel estimate, then fall back to CSI weights.

ip = inputParser;
ip.addParameter("PostEqSINRPerRE_dB", [], @(x) isempty(x) || isnumeric(x));
ip.addParameter("PostEqSINR_dB", NaN, @(x) isempty(x) || (isnumeric(x) && isscalar(x)));
ip.addParameter("CSI", [], @(x) isempty(x) || isnumeric(x));
ip.addParameter("SignalPower", 1, @(x) isempty(x) || (isnumeric(x) && isscalar(x)));
ip.parse(varargin{:});
opt = ip.Results;

signalPower = double(opt.SignalPower);
if ~(isfinite(signalPower) && signalPower > 0)
    signalPower = 1;
end

info = struct( ...
    "ValueStatus", "unavailable", ...
    "Source", "post_equalization_noise_variance_unavailable", ...
    "ValueRole", "post_equalization_decoder_noise_variance", ...
    "NAReason", "not_computed", ...
    "PreEqualizationNoiseVar", double(localScalarOrNaN(nVarPreEq)), ...
    "PostEqualizationNoiseVar", NaN, ...
    "ReductionMethod", "", ...
    "SampleCount", 0);
nVarEff = double(localScalarOrNaN(nVarPreEq));

perRE = double(opt.PostEqSINRPerRE_dB);
sinrLin = 10 .^ (perRE(:) ./ 10);
sinrLin = sinrLin(isfinite(sinrLin) & sinrLin > 0);
if ~isempty(sinrLin)
    candidates = signalPower ./ sinrLin;
    [nVarEff, info] = localAcceptCandidates(candidates, info, ...
        "post_equalization_sinr_per_re", "mean_inverse_post_eq_sinr");
    return;
end

widebandSINR = double(opt.PostEqSINR_dB);
if isfinite(widebandSINR)
    sinr = 10 .^ (widebandSINR ./ 10);
    if isfinite(sinr) && sinr > 0
        [nVarEff, info] = localAcceptCandidates(signalPower ./ sinr, info, ...
            "post_equalization_wideband_sinr", "inverse_wideband_post_eq_sinr");
        return;
    end
end

csi = double(real(opt.CSI(:)));
csi = csi(isfinite(csi) & csi > 0);
if ~isempty(csi)
    if max(csi) <= 1 + sqrt(eps)
        csi = min(max(csi, eps), 1 - sqrt(eps));
        sinr = csi ./ max(1 - csi, eps);
    else
        sinr = csi;
    end
    sinr = sinr(isfinite(sinr) & sinr > 0);
    if ~isempty(sinr)
        [nVarEff, info] = localAcceptCandidates(signalPower ./ sinr, info, ...
            "equalizer_csi_weights", "mean_inverse_csi_sinr");
        return;
    end
end

if isfinite(nVarEff) && nVarEff > 0
    info.ValueStatus = "OK";
    info.Source = "pre_equalization_noise_variance_no_post_eq_scaling_available";
    info.NAReason = "post_equalization_sinr_and_csi_unavailable";
    info.PostEqualizationNoiseVar = double(nVarEff);
    info.ReductionMethod = "identity_preserve_valid_input";
    info.SampleCount = 1;
else
    info.NAReason = "invalid_noise_variance_and_no_post_equalization_evidence";
end
end

function [nVarEff, info] = localAcceptCandidates(candidates, info, source, method)
candidates = double(candidates(:));
candidates = candidates(isfinite(candidates) & candidates > 0);
if isempty(candidates)
    nVarEff = double(info.PostEqualizationNoiseVar);
    return;
end
nVarEff = mean(candidates, "omitnan");
info.ValueStatus = "OK";
info.Source = char(string(source));
info.NAReason = "";
info.PostEqualizationNoiseVar = double(nVarEff);
info.ReductionMethod = char(string(method));
info.SampleCount = double(numel(candidates));
end

function value = localScalarOrNaN(raw)
value = NaN;
if isempty(raw)
    return;
end
raw = double(raw);
raw = raw(isfinite(raw));
if ~isempty(raw)
    value = raw(1);
end
end
