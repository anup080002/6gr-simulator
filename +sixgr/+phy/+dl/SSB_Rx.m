function [rxSSBGrid, sync] = SSB_Rx(rxWaveform, cfg, varargin)
%sixgr.phy.dl.SSB_Rx  Receiver-side SS/PBCH block extraction (grid)
%
%   [rxSSBGrid, sync] = sixgr.phy.dl.SSB_Rx(rxWaveform, cfg, ...)
%
%   This is a simulator-oriented wrapper that follows the MathWorks example
%   flow (PSS-based coarse sync) but is tolerant to single-antenna grid
%   dimensionality (240x4 vs 240x4xNr).
%
%   Outputs
%     rxSSBGrid : 240-by-4-by-Nr resource grid containing the SS/PBCH block
%     sync      : struct with timing/frequency estimates and IDs

% Parse inputs
p = inputParser;
p.addParameter('SampleRate_Hz', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x>0));
p.addParameter('TimingOnly', false, @(x) islogical(x) && isscalar(x));
p.parse(varargin{:});

% Burst parameters use the same canonical timing object as the transmitter.
blockPattern = char(sixgr.util.structGet(cfg,'phy.ssb.blockPattern','Case B'));
timing = sixgr.phy.frame.SSBTimingResolver.resolveFromConfig(cfg);
Lmax = double(timing.Lmax);
if p.Results.TimingOnly
    rxSSBGrid = complex(zeros(0, 0, 0));
    sync = struct( ...
        'TimingOnly', true, ...
        'TimingStatus', 'canonical_timing_resolved_without_waveform', ...
        'BlockPattern', char(timing.BlockPattern), ...
        'Lmax', Lmax, ...
        'SSBTiming', timing);
    return;
end

fs = p.Results.SampleRate_Hz;
if isempty(fs)
    fs = sixgr.util.structGet(cfg,'phy.sampleRate_Hz',[]);
end
if isempty(fs)
    error('SSB_Rx:SampleRateMissing','SampleRate_Hz must be provided (or cfg.phy.sampleRate_Hz set).');
end

% Ensure waveform is 2-D (Nsamp-by-Nr)
if isvector(rxWaveform)
    rxWaveform = rxWaveform(:);
end

% Coarse frequency correction + NID2 detection
try
    [rxF, fOffHz, NID2, finfo] = sixgr.phy.sync.freqOffsetCorrect(rxWaveform, blockPattern, fs, ...
        'SearchBW_Hz', sixgr.util.structGet(cfg,'phy.sync.freqSearchBW_Hz',[]), ...
        'SSBCenterFrequencyOffsetHz', localSSBCenterFrequencyOffsetHz(timing), ...
        'CFOHypothesesHz', sixgr.util.structGet(cfg,'phy.sync.cfoHypothesesHz',[]), ...
        'NID2Candidates', sixgr.util.structGet(cfg,'phy.sync.nid2Hypotheses',0:2), ...
        'FineCFOEnabled', sixgr.util.structGet(cfg,'phy.sync.fineCFOEnabled',false), ...
        'FineCFOMethod', sixgr.util.structGet(cfg,'phy.sync.fineCFOMethod',"cyclic_prefix"), ...
        'FineCFOMaxResidualHz', sixgr.util.structGet(cfg,'phy.sync.fineCFOMaxResidualHz',Inf), ...
        'FineCFOMinimumSymbols', sixgr.util.structGet(cfg,'phy.sync.fineCFOMinimumSymbols',2), ...
        'TimingSearchGuardSamples', sixgr.util.structGet( ...
            cfg, 'phy.synchronization.maxTimingUncertaintySamples', 0), ...
        'SSBTiming', timing);
catch ME
    error('sixgr:phy:ia:SSBNotDetected', ...
        'PSS/NID2 frequency search failed without transmitter-cell-ID oracle: %s', ME.message);
end
NID2 = mod(double(NID2),3);

% The blind PSS/NID2 search already evaluates every canonical SS/PBCH
% candidate window.  Reuse its winning correlation lag as the timing
% estimate; a second broad search can lock to later PDSCH symbols.
tOff = double(sixgr.util.structGet( ...
    finfo, "SelectedTimingOffsetSamples", NaN));
tinfo = struct( ...
    "Detector", "blind_pss_candidate_window_correlation", ...
    "SelectedCandidateWindowIndex", double(sixgr.util.structGet( ...
        finfo, "SelectedCandidateWindowIndex", NaN)), ...
    "SelectedCorrelationLagSamples", double(sixgr.util.structGet( ...
        finfo, "SelectedCorrelationLagSamples", NaN)), ...
    "SearchWindows", sixgr.util.structGet( ...
        finfo, "CandidateSearchWindows", zeros(0, 2)), ...
    "SSBTiming", timing);
if ~(isscalar(tOff) && isfinite(double(tOff)))
    error('sixgr:phy:ia:SSBNotDetected', ...
        'PSS timing search did not return a finite hypothesis.');
end
timingResolution = sixgr.phy.sync.resolveTimingApplication(tOff, ...
    "EstimateUsed", isfinite(double(tOff)), ...
    "ApplicationMode", "positive_crop_only", ...
    "Source", "nrTimingEstimate_pss");

% Synchronize waveform
startIdx = 1 + max(0, round(double(timingResolution.AppliedCorrection_samples)));
if startIdx > size(rxF,1)
    error('sixgr:phy:ia:SSBNotDetected', ...
        'Resolved SSB timing starts beyond the received waveform.');
end

% OFDM demodulation at SSB numerology (nrbSSB=20).  The PSS timing points
% to the selected SSB candidate symbol, which is not generally slot symbol
% zero.  Start demodulation at that candidate's slot boundary and extract
% the four symbols at their true within-slot positions so the applicable
% cyclic-prefix sequence remains exact.
nrbSSB = 20;
scsSSB = double(timing.SSBSubcarrierSpacingKHz);
candidateStartSymbol = double(sixgr.util.structGet( ...
    finfo, "SelectedCandidateStartSymbol", NaN));
if ~(isscalar(candidateStartSymbol) && isfinite(candidateStartSymbol) && ...
        candidateStartSymbol >= 0 && candidateStartSymbol == round(candidateStartSymbol))
    error('sixgr:phy:ia:SSBNotDetected', ...
        'PSS timing search did not identify a canonical candidate symbol.');
end
nSlot = floor(candidateStartSymbol / 14);
symbolWithinSlot = mod(candidateStartSymbol, 14);

ssbCarrier = nrCarrierConfig;
ssbCarrier.NCellID = 0;
ssbCarrier.NSizeGrid = nrbSSB;
ssbCarrier.NStartGrid = 0;
ssbCarrier.SubcarrierSpacing = scsSSB;
ssbCarrier.CyclicPrefix = "normal";
ssbCarrier.NFrame = 0;
ssbCarrier.NSlot = nSlot;
ssbSampling = sixgr.phy.frame.OFDMSamplingResolver.resolve( ...
    ssbCarrier, "SampleRate", fs);
slotSymbolLengths = double(ssbSampling.CyclicPrefixLengthsPerSlot(:)).' + ...
    double(ssbSampling.Nfft);
prefixSamples = sum(slotSymbolLengths(1:symbolWithinSlot));
demodStartIdx = startIdx - prefixSamples;
if demodStartIdx >= 1
    rxSync = rxF(demodStartIdx:end, :);
else
    rxSync = [complex(zeros(1 - demodStartIdx, size(rxF, 2), ...
        "like", rxF)); rxF];
end
rxGrid = sixgr.phy.waveform.ofdmDemodulate( ...
    ssbCarrier, rxSync, ...
    "Nfft", ssbSampling.Nfft, ...
    "SampleRate", ssbSampling.SampleRateHz);

% Normalize dimensionality: force 3-D grid (Nsc-by-Nsym-by-Nr)
if ndims(rxGrid) == 2
    rxGrid = reshape(rxGrid, size(rxGrid,1), size(rxGrid,2), 1);
end


ssbSymbolColumns = symbolWithinSlot + (1:4);
if size(rxGrid,2) < ssbSymbolColumns(end)
    error('sixgr:phy:ia:SSBNotDetected', ...
        'The synchronized waveform contains fewer than four SSB symbols.');
end

% Extract the four SS/PBCH symbols at the canonical candidate location.
rxSSBGrid = rxGrid(:, ssbSymbolColumns, :);

% Ensure 240-by-4-by-Nr
if ndims(rxSSBGrid) == 2
    rxSSBGrid = reshape(rxSSBGrid, size(rxSSBGrid,1), size(rxSSBGrid,2), 1);
end

try
    [NCellID, NID1, sssInfo] = ...
        localRecoverPhysicalCellIDFromSSS(rxSSBGrid, NID2);
catch ME
    error('sixgr:phy:ia:SSBNotDetected', ...
        'SSS physical-cell-ID search failed: %s', ME.message);
end

sync = struct();
sync.SampleRate_Hz = fs;
sync.BlockPattern = blockPattern;
sync.Lmax = Lmax;
sync.NID2 = NID2;
sync.NID1 = double(NID1);
sync.FreqOffset_Hz = fOffHz;
sync.TimingOffset = double(timingResolution.RawEstimate_samples);
sync.RawTimingEstimate_samples = double(timingResolution.RawEstimate_samples);
sync.AppliedTimingCorrection_samples = double(timingResolution.AppliedCorrection_samples);
sync.TimingEstimateApplicationPolicy = char(string(timingResolution.ApplicationPolicy));
sync.TimingEstimateStatus = char(string(timingResolution.Status));
sync.TimingEstimateWasClipped = logical(timingResolution.WasClipped);
sync.SCS_SSB_kHz = scsSSB;
sync.nRBSSB = nrbSSB;
sync.NCellID = double(NCellID);
sync.NCellIDSource = 'blind_pss_sss_correlation';
sync.ConfiguredCellIDUsed = false;
sync.UsedConfiguredCellID = false;

% Attach debug info
sync.FreqInfo = finfo;
sync.TimingInfo = tinfo;
sync.SSSInfo = sssInfo;
sync.SSBTiming = timing;
sync.SelectedCandidateStartSymbol = candidateStartSymbol;
sync.DemodulationSlot = double(nSlot);
sync.SSBSymbolColumnsOneBased = double(ssbSymbolColumns);
sync.SSBCenterFrequencyOffsetHz = double(sixgr.util.structGet( ...
    finfo, "SSBCenterFrequencyOffsetHz", NaN));
sync.SSBPlacementCorrectionAppliedHz = double(sixgr.util.structGet( ...
    finfo, "SSBPlacementCorrectionAppliedHz", NaN));

end

function offsetHz = localSSBCenterFrequencyOffsetHz(timing)
grid = sixgr.util.structGet(timing, "GridRelationship", struct());
required = ["SSBLowOffsetFromPointAHz", "SSBHighOffsetFromPointAHz", ...
    "CarrierLowOffsetFromPointAHz", "CarrierHighOffsetFromPointAHz"];
if ~all(isfield(grid, cellstr(required)))
    error("sixgr:phy:dl:SSB_Rx:MissingSSBGridRelationship", ...
        "SSB synchronization requires the canonical Point-A grid relationship.");
end
ssbCenterHz = 0.5 * (double(grid.SSBLowOffsetFromPointAHz) + ...
    double(grid.SSBHighOffsetFromPointAHz));
carrierCenterHz = 0.5 * (double(grid.CarrierLowOffsetFromPointAHz) + ...
    double(grid.CarrierHighOffsetFromPointAHz));
offsetHz = ssbCenterHz - carrierCenterHz;
if ~(isscalar(offsetHz) && isfinite(offsetHz))
    error("sixgr:phy:dl:SSB_Rx:InvalidSSBFrequencyPlacement", ...
        "The canonical SSB/carrier centre-frequency relationship is not finite.");
end
end

function [ncellid, nid1, info] = localRecoverPhysicalCellIDFromSSS(rxSSBGrid, nid2)
sssInd = nrSSSIndices;
sssRx = nrExtractResources(sssInd, rxSSBGrid);
if isvector(sssRx)
    sssRx = sssRx(:);
end
metrics = zeros(336, 1);
for candNID1 = 0:335
    candNCellID = 3 * candNID1 + double(nid2);
    ref = nrSSS(candNCellID);
    metric = 0;
    for rxAnt = 1:size(sssRx, 2)
        rx = sssRx(:, rxAnt);
        denom = max(norm(ref(:)) * norm(rx(:)), realmin);
        metric = metric + abs(sum(conj(ref(:)) .* rx(:))) / denom;
    end
    metrics(candNID1 + 1) = metric;
end
[bestMetric, bestIdx] = max(metrics);
nid1 = double(bestIdx - 1);
ncellid = double(3 * nid1 + double(nid2));
if ~(isfinite(bestMetric) && bestMetric > 0 && ncellid >= 0 && ncellid <= 1007)
    error('sixgr:phy:dl:SSB_Rx:SSSDetectionFailed', ...
        'SSS search did not produce a valid physical-cell-ID candidate.');
end
sortedMetrics = sort(metrics, "descend");
if numel(sortedMetrics) >= 2
    margin = sortedMetrics(1) - sortedMetrics(2);
else
    margin = NaN;
end
info = struct();
info.NID2 = double(nid2);
info.NID1 = double(nid1);
info.NCellID = double(ncellid);
info.Metric = double(bestMetric);
info.MetricMargin = double(margin);
info.Metrics = metrics;
info.SearchSpaceSize = 336;
info.NumberReceiveAntennas = double(size(sssRx,2));
info.Detector = 'sss_correlation_all_nid1_candidates';
end
