function [total_mW, perPort_mW, info] = measureActiveOFDMTotalPower(x, txInfo, varargin)
%MEASUREACTIVEOFDMTOTALPOWER Measure power on transmitted OFDM symbols.
%
% NR transmit-power limits and UL power-control equations apply while the
% physical signal is transmitted.  Averaging a one-symbol SRS or PUCCH
% waveform over the zero-valued remainder of a slot creates a duty-cycle
% power boost when the waveform is subsequently normalized.  This helper
% therefore identifies OFDM symbols that contain actual useful-sample
% energy, excludes cyclic-prefix samples, and averages only those active
% symbol intervals.  It is shared by the physical-power scaler and the
% receiver-noise bridge so both sides use one dimensional reference plane.

if nargin < 2 || ~isstruct(txInfo)
    txInfo = struct();
end
ip = inputParser;
ip.FunctionName = "sixgr.rf.measureActiveOFDMTotalPower";
ip.addParameter("ActiveSymbolIndices", [], @(v) isnumeric(v) && isvector(v));
ip.parse(varargin{:});
requestedActiveSymbolIndices = double(ip.Results.ActiveSymbolIndices(:));
if isempty(x)
    total_mW = NaN;
    perPort_mW = zeros(1, 0);
    info = struct( ...
        "ReferenceDomain", "empty", ...
        "SampleCount", 0, ...
        "ActiveSymbolCount", 0, ...
        "TotalSymbolCount", 0, ...
        "ActiveSymbolIndices", zeros(0, 1));
    return;
end

ofdmInfo = sixgr.util.structGet(txInfo, "OFDM", struct());
nfft = round(double(sixgr.util.structGet(ofdmInfo, "Nfft", NaN)));
cpLengths = round(double(sixgr.util.structGet( ...
    ofdmInfo, "CyclicPrefixLengths", [])));

if ~(isscalar(nfft) && isfinite(nfft) && nfft > 0 && ...
        ~isempty(cpLengths) && all(isfinite(cpLengths(:))) && ...
        all(cpLengths(:) >= 0))
    perPort_mW = mean(abs(double(x)).^2, 1, "omitnan");
    total_mW = sum(perPort_mW, "omitnan");
    info = struct( ...
        "ReferenceDomain", "all_waveform_samples_metadata_unavailable", ...
        "SampleCount", double(numel(x)), ...
        "ActiveSymbolCount", NaN, ...
        "TotalSymbolCount", NaN, ...
        "ActiveSymbolIndices", zeros(0, 1));
    return;
end

[usefulBySymbol, symbolPower] = localUsefulSymbolIntervals(x, nfft, cpLengths);
validSymbol = ~cellfun(@isempty, usefulBySymbol);
finitePower = isfinite(symbolPower) & symbolPower >= 0 & validSymbol;
if ~any(finitePower)
    perPort_mW = mean(abs(double(x)).^2, 1, "omitnan");
    total_mW = sum(perPort_mW, "omitnan");
    info = struct( ...
        "ReferenceDomain", "all_waveform_samples_no_complete_ofdm_symbol", ...
        "SampleCount", double(numel(x)), ...
        "ActiveSymbolCount", NaN, ...
        "TotalSymbolCount", double(nnz(validSymbol)), ...
        "ActiveSymbolIndices", zeros(0, 1));
    return;
end

maximumSymbolPower = max(symbolPower(finitePower));
% An exactly empty resource-grid symbol demodulates to zero.  Windowing and
% finite precision can leave very small tails, so use a scale-relative
% numerical floor rather than treating every nonzero floating value as an
% active transmission.
activityFloor = max(realmin("double"), maximumSymbolPower * 1e-12);
if isempty(requestedActiveSymbolIndices)
    activeMask = finitePower & symbolPower > activityFloor;
    referenceDomain = "active_nonzero_ofdm_symbols_excluding_cp";
else
    if any(~isfinite(requestedActiveSymbolIndices)) || ...
            any(requestedActiveSymbolIndices < 0) || ...
            any(requestedActiveSymbolIndices ~= fix(requestedActiveSymbolIndices))
        error("sixgr:rf:InvalidActiveOFDMSymbolIndices", ...
            "ActiveSymbolIndices must contain finite zero-based integer indices.");
    end
    requestedOneBased = unique(requestedActiveSymbolIndices + 1, "stable");
    if any(requestedOneBased > numel(validSymbol)) || ...
            any(~validSymbol(requestedOneBased))
        error("sixgr:rf:ActiveOFDMSymbolOutsideWaveform", ...
            ["The requested active OFDM-symbol set contains a symbol that " ...
             "is not completely represented by the waveform."]);
    end
    activeMask = false(size(validSymbol));
    activeMask(requestedOneBased) = true;
    referenceDomain = "specified_active_ofdm_symbols_excluding_cp";
end
if ~any(activeMask)
    perPort_mW = zeros(1, size(x, 2));
    total_mW = 0;
    activeIndices = zeros(0, 1);
    referenceSamples = zeros(0, size(x, 2), "like", x);
else
    activeIndices = find(activeMask);
    usefulIndices = vertcat(usefulBySymbol{activeMask});
    referenceSamples = x(usefulIndices, :);
    perPort_mW = mean(abs(double(referenceSamples)).^2, 1, "omitnan");
    total_mW = sum(perPort_mW, "omitnan");
end

info = struct( ...
    "ReferenceDomain", char(referenceDomain), ...
    "SampleCount", double(numel(referenceSamples)), ...
    "ActiveSymbolCount", double(numel(activeIndices)), ...
    "TotalSymbolCount", double(nnz(validSymbol)), ...
    "ActiveSymbolIndices", double(activeIndices(:) - 1), ...
    "ActivityPowerFloor_mW", double(activityFloor), ...
    "MaximumSymbolPower_mW", double(maximumSymbolPower));
end

function [usefulBySymbol, symbolPower] = ...
        localUsefulSymbolIntervals(x, nfft, cpLengths)
nSamples = size(x, 1);
usefulBySymbol = cell(0, 1);
symbolPower = zeros(0, 1);
offset = 0;
symbolIndex = 0;
while offset < nSamples
    progressed = false;
    for cpIndex = 1:numel(cpLengths)
        cpLength = double(cpLengths(cpIndex));
        firstUseful = offset + cpLength + 1;
        lastUseful = offset + cpLength + nfft;
        if firstUseful > nSamples
            offset = nSamples;
            break;
        end
        useful = (firstUseful:min(lastUseful, nSamples)).';
        symbolIndex = symbolIndex + 1;
        if numel(useful) == nfft
            usefulBySymbol{symbolIndex, 1} = useful; %#ok<AGROW>
            samples = double(x(useful, :));
            symbolPower(symbolIndex, 1) = mean( ...
                sum(abs(samples).^2, 2), "omitnan"); %#ok<AGROW>
        else
            usefulBySymbol{symbolIndex, 1} = zeros(0, 1); %#ok<AGROW>
            symbolPower(symbolIndex, 1) = NaN; %#ok<AGROW>
        end
        offset = offset + cpLength + nfft;
        progressed = true;
        if offset >= nSamples
            break;
        end
    end
    if ~progressed
        break;
    end
end
end
