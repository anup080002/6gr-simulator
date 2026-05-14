function [NCellID, timingOffset, freqOffsetHz, info] = cellSearch(rxWaveform, cfg, varargin)
%cellSearch Coarse NR cell search and synchronization using SSB (PSS/SSS).
%
%   [NCellID, timingOffset, freqOffsetHz, info] = sixgr.phy.sync.cellSearch(rxWaveform, cfg)
%
%   This utility is designed for simulation/verification. It performs:
%     1) PSS-based coarse frequency correction (+ NID2 selection)
%     2) Timing estimation using nrTimingEstimate
%     3) SSS correlation to obtain NID1
%
%   Inputs:
%     rxWaveform : Complex baseband samples (Nsamp x Nrx)
%     cfg        : sixgr config struct (fields optional)
%
%   Name-Value pairs:
%     'SampleRate_Hz' : Override sample rate (Hz)
%     'BlockPattern'  : SSB block pattern ('Case A'..'Case E')
%     'Lmax'          : Max SSB blocks (4/8/64)
%     'SearchBW_Hz'   : Frequency search half-span (Hz)
%     'Debug'         : true/false
%
%   Outputs:
%     NCellID      : Physical cell ID (0..1007)
%     timingOffset : Sample offset to the symbol *preceding* the PSS symbol
%     freqOffsetHz : Estimated freq offset applied (Hz)
%     info         : Diagnostics

% ---- Parse inputs ----
p = inputParser;
p.addParameter('SampleRate_Hz', [], @(x) isempty(x) || (isscalar(x) && isnumeric(x) && x>0));
p.addParameter('BlockPattern', '', @(x) ischar(x) || isstring(x));
p.addParameter('Lmax', [], @(x) isempty(x) || (isscalar(x) && isnumeric(x) && x>=1));
p.addParameter('SearchBW_Hz', [], @(x) isempty(x) || (isscalar(x) && isnumeric(x) && x>0));
p.addParameter('Debug', false, @(x) islogical(x) && isscalar(x));
p.parse(varargin{:});

% Ensure column-major waveform
if isrow(rxWaveform)
    rxWaveform = rxWaveform.';
end

blockPattern = string(p.Results.BlockPattern);
if strlength(blockPattern)==0
    blockPattern = string(sixgr.util.structGet(cfg, 'phy.ssb.blockPattern', 'Case B'));
end

Lmax = p.Results.Lmax;
if isempty(Lmax)
    Lmax = sixgr.util.structGet(cfg, 'phy.ssb.Lmax', 4);
end

sampleRateHz = p.Results.SampleRate_Hz;
if isempty(sampleRateHz)
    % Try config, else derive from an SSB-sized carrier (approx)
    sampleRateHz = sixgr.util.structGet(cfg, 'phy.sampleRate_Hz', []);
    if isempty(sampleRateHz)
        try
            scsSSB_kHz = localSSBSubcarrierSpacing_kHz(blockPattern);
            tmpCarrier = nrCarrierConfig;
            tmpCarrier.NSizeGrid = 20; % 240 subcarriers
            tmpCarrier.SubcarrierSpacing = scsSSB_kHz;
            tmpCarrier.CyclicPrefix = 'normal';
            ofdm = nrOFDMInfo(tmpCarrier);
            sampleRateHz = ofdm.SampleRate;
        catch
            sampleRateHz = 30.72e6;
        end
    end
end

searchBW_Hz = p.Results.SearchBW_Hz;
if isempty(searchBW_Hz)
    searchBW_Hz = sixgr.util.structGet(cfg, 'phy.sync.searchBW_Hz', 1.2e6);
end

% ---- 1) Coarse frequency correction + NID2 ----
[rxF, freqOffsetHz, NID2, fInfo] = sixgr.phy.sync.freqOffsetCorrect(rxWaveform, blockPattern, sampleRateHz, ...
    'SearchBW_Hz', searchBW_Hz);

% ---- 2) Timing estimate (offset to symbol preceding PSS) ----
[timingOffset, tInfo] = sixgr.phy.sync.timingEstimate(rxF, NID2, blockPattern, sampleRateHz);
timingResolution = sixgr.phy.sync.resolveTimingApplication(timingOffset, ...
    "EstimateUsed", isfinite(double(timingOffset)), ...
    "ApplicationMode", "positive_crop_only", ...
    "Source", "nrTimingEstimate_pss");

% ---- 3) OFDM demodulate and SSS correlation for NID1 ----
scsSSB_kHz = localSSBSubcarrierSpacing_kHz(blockPattern);
carrierSSB = nrCarrierConfig;
carrierSSB.NSizeGrid = 20;
carrierSSB.SubcarrierSpacing = scsSSB_kHz;
carrierSSB.CyclicPrefix = 'normal';

appliedTiming = double(timingResolution.AppliedCorrection_samples);
if appliedTiming >= size(rxF,1)
    appliedTiming = 0;
end

rxCut = rxF(1+appliedTiming:end,:);

% Demodulate a bit more than needed; then take symbols 2:5 as in MathWorks example
try
    [rxGrid, ofdmInfo] = sixgr.phy.waveform.ofdmDemodulate(carrierSSB, rxCut, 'SampleRate', sampleRateHz);
catch
    [rxGrid, ofdmInfo] = sixgr.phy.waveform.ofdmDemodulate(carrierSSB, rxCut);
end

if ndims(rxGrid) < 3
    rxGrid = reshape(rxGrid, size(rxGrid,1), size(rxGrid,2), 1);
end

if size(rxGrid,2) < 5
    % Not enough symbols; pad with zeros
    rxGrid = cat(2, rxGrid, complex(zeros(size(rxGrid,1), 5-size(rxGrid,2), size(rxGrid,3))));
end

rxSSB = rxGrid(:,2:5,:); % 4 symbols

% Extract SSS from first RX antenna for ID detection
sssInd = nrSSSIndices();
sssRx  = nrExtractResources(sssInd, rxSSB(:,:,1));

sssMetric = zeros(336,1);
for nid1 = 0:335
    sssRef = localNRSSS(nid1, NID2);
    sssMetric(nid1+1) = abs(sum(conj(sssRef(:)).*sssRx(:)));
end
[~, bestIdx] = max(sssMetric);
NID1 = bestIdx - 1;

NCellID = 3*NID1 + NID2;

info = struct();
info.BlockPattern = char(blockPattern);
info.Lmax = double(Lmax);
info.SampleRate_Hz = double(sampleRateHz);
info.SearchBW_Hz = double(searchBW_Hz);
info.NID1 = double(NID1);
info.NID2 = double(NID2);
info.SSSMetric = sssMetric;
info.OFDMInfo = ofdmInfo;
info.Freq = fInfo;
info.Timing = tInfo;
info.RawTimingEstimate_samples = double(timingResolution.RawEstimate_samples);
info.AppliedTimingCorrection_samples = double(timingResolution.AppliedCorrection_samples);
info.TimingEstimateApplicationPolicy = char(string(timingResolution.ApplicationPolicy));
info.TimingEstimateStatus = char(string(timingResolution.Status));
info.TimingEstimateWasClipped = logical(timingResolution.WasClipped);
info.Debug = p.Results.Debug;

if p.Results.Debug
    info.RxSSBGrid = rxSSB; %#ok<STRNU>
end

end

% -------------------------------------------------------------------------
function scs = localSSBSubcarrierSpacing_kHz(blockPattern)
blockPattern = upper(string(blockPattern));
switch blockPattern
    case "CASE A"
        scs = 15;
    case {"CASE B","CASE C"}
        scs = 30;
    case "CASE D"
        scs = 120;
    case "CASE E"
        scs = 240;
    otherwise
        scs = 30;
end
end

function sss = localNRSSS(nid1, nid2)
% Handle signature differences across releases.
NCellID = 3*double(nid1) + double(nid2);
try
    sss = nrSSS(NCellID);
catch
    sss = nrSSS(double(nid1), double(nid2));
end
end
