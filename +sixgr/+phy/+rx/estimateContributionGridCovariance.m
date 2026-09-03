function [Rint, info] = estimateContributionGridCovariance(contributionTensor, carrier, ...
        dataInd, appliedTimingCorrection, source, domain, signalName, varargin)
%ESTIMATECONTRIBUTIONGRIDCOVARIANCE Covariance from shared-slot contributors.
%   CONTRIBUTIONTENSOR is Nsamp-by-Nrx-by-Nsrc in receiver sample domain.
%   The estimator demodulates each simulator-separated interference
%   contribution and measures a local covariance on the exact data REs used
%   by the victim receiver. This is data-aided truth/oracle evidence, not a
%   blind over-the-air covariance estimator, and the exported source label
%   preserves that distinction.

if nargin < 7 || strlength(strtrim(string(signalName))) == 0
    signalName = "data";
end
ip = inputParser;
ip.addParameter("EstimatorMode", "per_prb_symbol_contribution_sample_covariance", ...
    @(x) ischar(x) || (isstring(x) && isscalar(x)));
ip.addParameter("FrequencyWindowPRBs", 1, ...
    @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 1 && x == fix(x));
ip.addParameter("TimeWindowSymbols", 1, ...
    @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 1 && x == fix(x));
ip.addParameter("ShrinkageFactor", 0.05, ...
    @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0 && x < 1);
ip.addParameter("MinimumSamples", 4, ...
    @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 2 && x == fix(x));
ip.parse(varargin{:});
estimatorMode = lower(strtrim(string(ip.Results.EstimatorMode)));
if estimatorMode ~= "per_prb_symbol_contribution_sample_covariance"
    error("sixgr:phy:rx:UnsupportedContributionCovarianceEstimator", ...
        "Unsupported contribution-grid covariance estimator '%s'.", ...
        char(estimatorMode));
end
signalName = lower(strtrim(string(signalName)));
Rint = [];
info = struct("Available", false, ...
    "Source", "shared_slot_contribution_grid_covariance_unavailable", ...
    "Status", "unavailable", ...
    "NAReason", "no_interference_contribution_tensor", ...
    "Domain", "resource_grid_" + signalName + "_re_receive_antenna_covariance", ...
    "CovarianceIncludesNoise", false, ...
    "EstimatorMode", char(estimatorMode), ...
    "FrequencyWindowPRBs", double(ip.Results.FrequencyWindowPRBs), ...
    "TimeWindowSymbols", double(ip.Results.TimeWindowSymbols), ...
    "ShrinkageFactor", double(ip.Results.ShrinkageFactor), ...
    "MinimumSamples", double(ip.Results.MinimumSamples), ...
    "NumSamples", 0, ...
    "ContributionSource", char(string(source)), ...
    "ContributionDomain", char(string(domain)));

if isempty(contributionTensor)
    return;
end
if ~isnumeric(contributionTensor) || size(contributionTensor, 1) < 1 || size(contributionTensor, 2) < 1
    info.NAReason = "contribution_tensor_must_have_sample_and_rx_dimensions";
    return;
end

try
    nSource = size(contributionTensor, 3);
    extractedBySource = cell(nSource, 1);
    for sourceIndex = 1:nSource
        interferenceWave = contributionTensor(:, :, sourceIndex);
        interferenceWave = localApplyTimingCorrection(interferenceWave, appliedTimingCorrection);
        interferenceGrid = sixgr.phy.waveform.ofdmDemodulate(carrier, interferenceWave);
        extractedBySource{sourceIndex} = nrExtractResources(dataInd, interferenceGrid);
    end
catch ME
    info.Status = "contribution_grid_covariance_failed";
    info.NAReason = string(ME.identifier);
    return;
end

if isempty(extractedBySource) || isempty(extractedBySource{1})
    info.NAReason = "no_" + signalName + "_re_interference_samples";
    return;
end

referenceRE = extractedBySource{1};
if isvector(referenceRE), referenceRE = referenceRE(:); end
nRE = size(referenceRE, 1);
nRx = size(referenceRE, 2);
for sourceIndex = 1:numel(extractedBySource)
    current = extractedBySource{sourceIndex};
    if isvector(current), current = current(:); end
    current = double(current);
    if ~isequal(size(current), [nRE nRx])
        info.NAReason = "contribution_resource_shape_mismatch";
        return;
    end
    extractedBySource{sourceIndex} = current;
end

[subcarrier0, symbol0, coordinateOk] = localDataCoordinates(dataInd, carrier, nRE);
if ~coordinateOk
    info.NAReason = "data_index_coordinate_shape_mismatch";
    return;
end

windowPRBs = double(ip.Results.FrequencyWindowPRBs);
windowSymbols = double(ip.Results.TimeWindowSymbols);
minimumSamples = double(ip.Results.MinimumSamples);
shrinkage = double(ip.Results.ShrinkageFactor);
prb0 = floor(subcarrier0 ./ 12);
RperRE = complex(zeros(nRE, nRx, nRx));
sampleCounts = zeros(nRE, 1);
for reIndex = 1:nRE
    prbStart = prb0(reIndex) - floor((windowPRBs - 1) / 2);
    prbEnd = prbStart + windowPRBs - 1;
    symbolStart = symbol0(reIndex) - floor((windowSymbols - 1) / 2);
    symbolEnd = symbolStart + windowSymbols - 1;
    mask = prb0 >= prbStart & prb0 <= prbEnd & ...
        symbol0 >= symbolStart & symbol0 <= symbolEnd;
    R = complex(zeros(nRx, nRx));
    validSampleCount = 0;
    for sourceIndex = 1:numel(extractedBySource)
        samples = extractedBySource{sourceIndex}(mask, :);
        finiteRows = all(isfinite(real(samples)) & isfinite(imag(samples)), 2);
        nonzeroRows = sum(abs(samples).^2, 2) > 0;
        samples = samples(finiteRows & nonzeroRows, :);
        if isempty(samples)
            continue;
        end
        R = R + (samples' * samples) ./ size(samples, 1);
        validSampleCount = validSampleCount + size(samples, 1);
    end
    if validSampleCount < minimumSamples
        info.NAReason = "insufficient_local_" + signalName + ...
            "_re_interference_samples";
        return;
    end
    R = (R + R') ./ 2;
    meanPower = real(trace(R)) ./ max(1, nRx);
    R = (1 - shrinkage) .* R + shrinkage .* meanPower .* eye(nRx);
    if any(~isfinite(real(R(:)))) || any(~isfinite(imag(R(:))))
        info.NAReason = "nonfinite_contribution_covariance";
        return;
    end
    RperRE(reIndex, :, :) = R;
    sampleCounts(reIndex) = validSampleCount;
end

Rint = RperRE;
info.Available = true;
info.Source = "oracle_separated_shared_slot_per_prb_symbol_contribution_grid_covariance";
info.Status = "OK";
info.NAReason = "";
info.NumSamples = double(sum(sampleCounts));
info.NumSamplesMinPerRE = double(min(sampleCounts));
info.NumSamplesMeanPerRE = double(mean(sampleCounts));
info.NumSamplesMaxPerRE = double(max(sampleCounts));
info.NumRxAnt = double(nRx);
info.NumRE = double(nRE);
info.PerRECovariance = true;
end

function [subcarrier0, symbol0, ok] = localDataCoordinates(dataInd, carrier, nRE)
ok = false;
subcarrier0 = zeros(0, 1);
symbol0 = zeros(0, 1);
if ~(isnumeric(dataInd) && ~isempty(dataInd))
    return;
end
if size(dataInd, 1) == nRE
    firstPlaneIndices = double(dataInd(:, 1));
elseif isvector(dataInd) && numel(dataInd) == nRE
    firstPlaneIndices = double(dataInd(:));
else
    return;
end
nSubcarrier = 12 * double(carrier.NSizeGrid);
nSymbol = double(carrier.SymbolsPerSlot);
planeSize = nSubcarrier * nSymbol;
firstPlaneIndices = mod(round(firstPlaneIndices) - 1, planeSize) + 1;
[subcarrier, symbol] = ind2sub([nSubcarrier nSymbol], firstPlaneIndices);
subcarrier0 = double(subcarrier(:)) - 1;
symbol0 = double(symbol(:)) - 1;
ok = all(isfinite(subcarrier0)) && all(isfinite(symbol0));
end

function y = localApplyTimingCorrection(x, timingOffset)
y = x;
timingOffset = double(timingOffset);
if ~(isscalar(timingOffset) && isfinite(timingOffset) && abs(timingOffset) > 0)
    return;
end
shift = round(timingOffset);
if shift > 0
    if shift < size(x, 1)
        y = x(shift+1:end, :);
        y(end+1:size(x,1), :) = cast(0, "like", x);
    end
elseif shift < 0
    shift = abs(shift);
    y = [zeros(shift, size(x,2), "like", x); x];
    y = y(1:size(x,1), :);
end
end
