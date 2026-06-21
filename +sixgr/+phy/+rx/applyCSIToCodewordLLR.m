function [llrOut, info] = applyCSIToCodewordLLR(llrIn, csi, modScheme, varargin)
%APPLYCSITOCODEWORDLLR Apply equalizer CSI reliability to demapper LLRs.
%   MATLAB NR receiver examples weight demapper LLRs by MMSE CSI. This
%   helper keeps that behavior, but rejects the numerically unsafe case
%   where CSI carries absolute path-gain scale instead of bounded
%   reliability and would collapse otherwise valid decoder soft bits.

postEqSINR_dB = NaN;
for i = 1:2:numel(varargin)
    key = lower(string(varargin{i}));
    val = varargin{i+1};
    switch key
        case "posteqsinr_db"
            postEqSINR_dB = double(val);
    end
end

info = localDefaultInfo();
info.PostEqSINR_dB = localScalarOrNaN(postEqSINR_dB);
llrOut = double(llrIn(:));
info.InputLLRMeanAbs = localMeanAbs(llrOut);
info.OutputLLRMeanAbs = info.InputLLRMeanAbs;

if isempty(csi)
    info.Status = "not_applied_no_csi";
    info.Source = "decoder_noise_variance_only_no_csi";
    return;
end

csiVec = localCodewordCSI(csi);
csiVec = double(real(csiVec(:)));
csiVec(~isfinite(csiVec) | csiVec < 0) = 0;
if isempty(csiVec) || ~any(csiVec > 0)
    info.Status = "not_applied_no_positive_csi";
    info.Source = "decoder_noise_variance_only_invalid_csi";
    return;
end

posRaw = csiVec(csiVec > 0 & isfinite(csiVec));
info.RawCSIMin = min(posRaw, [], "omitnan");
info.RawCSIMedian = median(posRaw, "omitnan");
info.RawCSIMax = max(posRaw, [], "omitnan");

[weights, inputKind] = localCSIToReliabilityWeights(csiVec);
info.InputKind = inputKind;

qm = max(1, round(double(localQm(modScheme))));
if numel(weights) * qm == numel(llrOut)
    weights = repelem(weights, qm);
elseif numel(weights) ~= numel(llrOut)
    info.Status = "not_applied_csi_llr_length_mismatch";
    info.Source = "decoder_noise_variance_only_csi_length_mismatch";
    info.CSISymbolCount = double(numel(csiVec));
    info.LLRCount = double(numel(llrOut));
    info.Qm = double(qm);
    return;
end

posW = weights(weights > 0 & isfinite(weights));
if isempty(posW)
    info.Status = "not_applied_no_positive_weights";
    info.Source = "decoder_noise_variance_only_invalid_csi_weights";
    return;
end
info.WeightMedianBeforeNormalization = median(posW, "omitnan");
info.WeightMaxBeforeNormalization = max(posW, [], "omitnan");

[weights, normStatus, normScale] = localNormalizePathGainScaledWeights(weights, info);
info.NormalizationScale = double(normScale);
info.Status = normStatus;
if normStatus == "applied_normalized_path_gain_scaled_csi"
    info.Source = "equalizer_csi_weights_normalized_from_path_gain_scale";
else
    info.Source = "equalizer_csi_weights";
end

llrOut = llrOut .* weights(:);
info.Applied = true;
info.CSISymbolCount = double(numel(csiVec));
info.LLRCount = double(numel(llrOut));
info.Qm = double(qm);
info.OutputLLRMeanAbs = localMeanAbs(llrOut);
end

function info = localDefaultInfo()
info = struct( ...
    "Applied", false, ...
    "Status", "not_applied", ...
    "Source", "decoder_noise_variance_only", ...
    "InputKind", "", ...
    "PostEqSINR_dB", NaN, ...
    "RawCSIMin", NaN, ...
    "RawCSIMedian", NaN, ...
    "RawCSIMax", NaN, ...
    "WeightMedianBeforeNormalization", NaN, ...
    "WeightMaxBeforeNormalization", NaN, ...
    "NormalizationScale", NaN, ...
    "InputLLRMeanAbs", NaN, ...
    "OutputLLRMeanAbs", NaN, ...
    "CSISymbolCount", NaN, ...
    "LLRCount", NaN, ...
    "Qm", NaN);
end

function csiVec = localCodewordCSI(csi)
try
    csiCW = nrLayerDemap(csi);
    if iscell(csiCW)
        csiVec = csiCW{1};
    else
        csiVec = csiCW;
    end
catch
    csiVec = csi;
end
end

function [weights, inputKind] = localCSIToReliabilityWeights(csiVec)
weights = double(csiVec(:));
if any(weights > 1 + sqrt(eps))
    % Some non-MMSE paths expose CSI as post-equalization SINR. Convert it
    % to the bounded reliability convention used with MMSE demodulation.
    weights = weights ./ max(1 + weights, eps);
    inputKind = "sinr_like_converted_to_bounded_reliability";
else
    weights = min(max(weights, 0), 1);
    inputKind = "bounded_reliability";
end
end

function [weights, status, scale] = localNormalizePathGainScaledWeights(weights, info)
status = "applied";
scale = 1;
pos = weights(weights > 0 & isfinite(weights));
if isempty(pos)
    return;
end

medW = median(pos, "omitnan");
maxW = max(pos, [], "omitnan");
postEq = double(info.PostEqSINR_dB);

% A CSI median near zero while post-equalization SINR is usable means the
% vector is carrying absolute channel-gain scale. Multiplying LLRs by that
% scale erases soft information and violates the intended MMSE CSI role.
scaleLooksLikePathGain = isfinite(medW) && medW > 0 && medW < 1e-3 && ...
    isfinite(maxW) && maxW < 1e-2;
symbolsAreUsable = isfinite(postEq) && postEq > -3;

if ~(scaleLooksLikePathGain && symbolsAreUsable)
    return;
end

scale = medW;
weights = weights ./ max(scale, realmin);
weights(~isfinite(weights) | weights < 0) = 0;
weights = min(weights, 2.0);
status = "applied_normalized_path_gain_scaled_csi";
end

function qm = localQm(modScheme)
switch upper(char(string(modScheme)))
    case {'PI/2-BPSK','BPSK'}
        qm = 1;
    case 'QPSK'
        qm = 2;
    case '16QAM'
        qm = 4;
    case '64QAM'
        qm = 6;
    case '256QAM'
        qm = 8;
    case '1024QAM'
        qm = 10;
    case '4096QAM'
        qm = 12;
    otherwise
        qm = 2;
end
end

function v = localMeanAbs(x)
x = double(x(:));
x = x(isfinite(x));
if isempty(x)
    v = NaN;
else
    v = mean(abs(x), "omitnan");
end
end

function x = localScalarOrNaN(x)
x = double(x);
x = x(isfinite(x));
if isempty(x)
    x = NaN;
else
    x = x(1);
end
end
