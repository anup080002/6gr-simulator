function feedback = resolveWidebandCQI(sinrInput, cfg, direction)
%RESOLVEWIDEBANDCQI Resolve wideband or per-RB SINR into NR CQI feedback.
%
% This helper is structured so callers can pass the same wideband SINR used
% by the simulator today, while allowing a future per-RB SINR array to slot
% into the same API without redesigning the feedback contract. The wideband
% fallback applies a configurable implementation margin because a single
% effective SINR is less informative than standards-style per-RB feedback.

if nargin < 2 || isempty(cfg)
    cfg = struct();
end
if nargin < 3 || isempty(direction)
    direction = "DL";
end

tableToken = localResolveCQITable(cfg, direction);
margin_dB = double(sixgr.util.structGet(cfg, "phy.csi.widebandSINRMargin_dB", 0));
if ~isfinite(margin_dB)
    margin_dB = 0;
end

[widebandSINR_dB, perRBSINR_dB] = localExtractSINRInputs(sinrInput);
widebandSE = localSINRToSpectralEfficiency(widebandSINR_dB - margin_dB);
perRBSE = localSINRToSpectralEfficiency(perRBSINR_dB - margin_dB);

feedback = struct( ...
    "Mode", "wideband_same_sinr_model", ...
    "Table", char(tableToken), ...
    "AppliedSINRMargin_dB", double(margin_dB), ...
    "WidebandSINR_dB", double(widebandSINR_dB), ...
    "WidebandEffectiveSINR_dB", double(widebandSINR_dB - margin_dB), ...
    "WidebandSpectralEfficiency", double(widebandSE), ...
    "WidebandCQI", double(localSelectCQIBySE(widebandSE, tableToken)), ...
    "PerRBSINR_dB", double(perRBSINR_dB), ...
    "PerRBEffectiveSINR_dB", double(perRBSINR_dB - margin_dB), ...
    "PerRBSpectralEfficiency", double(perRBSE), ...
    "PerRBCQI", double(localSelectCQIBySE(perRBSE, tableToken)));
end

function [widebandSINR_dB, perRBSINR_dB] = localExtractSINRInputs(sinrInput)
widebandSINR_dB = [];
perRBSINR_dB = [];

if isnumeric(sinrInput)
    widebandSINR_dB = double(sinrInput);
elseif isstruct(sinrInput)
    widebandSINR_dB = double(sixgr.util.structGet(sinrInput, "WidebandSINR_dB", []));
    perRBSINR_dB = double(sixgr.util.structGet(sinrInput, "PerRBSINR_dB", []));
end

if isempty(widebandSINR_dB) && ~isempty(perRBSINR_dB)
    try
        widebandSINR_dB = 10 * log10(mean(10 .^ (double(perRBSINR_dB) / 10), 2, "omitnan"));
    catch
        widebandSINR_dB = 10 * log10(mean(10 .^ (double(perRBSINR_dB) / 10), 2));
    end
end

if isempty(widebandSINR_dB)
    widebandSINR_dB = NaN;
end
end

function spectralEfficiency = localSINRToSpectralEfficiency(sinr_dB)
if isempty(sinr_dB)
    spectralEfficiency = [];
    return;
end
sinrLin = 10 .^ (double(sinr_dB) / 10);
sinrLin(~isfinite(sinrLin)) = 0;
sinrLin = max(sinrLin, 0);
spectralEfficiency = log2(1 + sinrLin);
end

function cqi = localSelectCQIBySE(spectralEfficiency, tableToken)
cqi = zeros(size(spectralEfficiency));
for i = 1:numel(cqi)
    seVal = double(spectralEfficiency(i));
    if ~(isfinite(seVal) && seVal > 0)
        cqi(i) = 0;
        continue;
    end
    bestCQI = 0;
    bestSE = -inf;
    for idx = 1:15
        profile = sixgr.link.resolveCQIProfile(tableToken, idx);
        if ~profile.Valid
            continue;
        end
        if profile.SpectralEfficiency <= seVal + 1e-9 && profile.SpectralEfficiency > bestSE + 1e-9
            bestCQI = idx;
            bestSE = profile.SpectralEfficiency;
        end
    end
    cqi(i) = bestCQI;
end
end

function tableToken = localResolveCQITable(cfg, direction)
tableToken = char(sixgr.link.resolveConfiguredCQITable(cfg, direction));
end
