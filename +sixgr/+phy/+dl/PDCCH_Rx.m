function [rx, info] = PDCCH_Rx(rxWaveform, cfg, varargin)
%PDCCH_Rx Recover a basic PDCCH (DCI) transmission.
%
%   [RX,INFO] = sixgr.phy.dl.PDCCH_Rx(RXWAVEFORM, CFG) attempts to recover a
%   single-slot PDCCH from RXWAVEFORM using DMRS-aided timing, channel
%   estimation, MMSE equalization, and polar list decoding of DCI.
%
%   This is a "known-location" receiver by default (it uses the same PDCCH
%   resource mapping as the transmitter). You can enable a simple blind
%   candidate search by setting cfg.phy.pdcch.blindSearch=true.
%
%   Name-Value options:
%     "Carrier"        : nrCarrierConfig override
%     "PDCCH"          : nrPDCCHConfig override
%     "K"              : DCI payload length in bits (default 64)
%     "ListLength"     : polar list length for DCI decoding (default 8)
%     "NoiseVar"       : override noise variance (else estimate)
%     "SampleRate_Hz"  : sample rate (only needed for some timing APIs)
%
%   Outputs:
%     RX.DCIBits        : recovered DCI payload bits
%     RX.ErrFlag        : 0 if CRC passes, 1 otherwise (when available)
%     RX.Ok             : true when ErrFlag==0
%     RX.TimingOffset   : sample timing offset applied
%     RX.NoiseVar       : noise variance used

% ---------------------- Parse inputs ----------------------
ip = inputParser;
ip.addParameter('Carrier', [], @(x) isempty(x) || isobject(x));
ip.addParameter('PDCCH', [], @(x) isempty(x) || isobject(x));
ip.addParameter('K', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x>0));
ip.addParameter('ListLength', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x>0));
ip.addParameter('NoiseVar', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x>=0));
ip.addParameter('SampleRate_Hz', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x>0));
ip.parse(varargin{:});
opt = ip.Results;

% Carrier
if isempty(opt.Carrier)
    [carrier, cinfo] = sixgr.phy.grid.makeCarrier(cfg);
else
    carrier = opt.Carrier;
    cinfo = struct();
end

nCellID = double(sixgr.util.structGet(cfg, 'phy.carrier.NCellID', ...
    sixgr.util.structGet(cfg, 'scenario.NCellID', 1)));
rnti   = double(sixgr.util.structGet(cfg, 'phy.pdcch.rnti', 4660));

% PDCCH config
if isempty(opt.PDCCH)
    pdcch = localDefaultPDCCH(cfg, carrier, nCellID, rnti);
else
    pdcch = opt.PDCCH;
end

K = opt.K;
if isempty(K)
    K = double(sixgr.util.structGet(cfg, 'phy.pdcch.dciPayloadBits', 64));
end

listLen = opt.ListLength;
if isempty(listLen)
    listLen = double(sixgr.util.structGet(cfg, 'phy.pdcch.listLength', 8));
end

blind = logical(sixgr.util.structGet(cfg, 'phy.pdcch.blindSearch', false));

% ---------------------- Candidate resources ----------------------
% Known mapping (single candidate) or blind candidates
candSymInd = {};
candDMRSInd = {};
candDMRSSym = {};

if blind
    % This returns candidates for the configured search space.
    [allSymInd, allDMRSSym, allDMRSInd] = nrPDCCHSpace(carrier, pdcch);
    [candSymInd, candDMRSInd, candDMRSSym] = localCollectPDCCHCandidates(allSymInd, allDMRSInd, allDMRSSym);
    if isempty(candSymInd)
        [pdcchInd, dmrsSym, dmrsInd] = nrPDCCHResources(carrier, pdcch);
        candSymInd  = {pdcchInd};
        candDMRSInd = {dmrsInd};
        candDMRSSym = {dmrsSym};
    end
else
    [pdcchInd, dmrsSym, dmrsInd] = nrPDCCHResources(carrier, pdcch);
    candSymInd  = {pdcchInd};
    candDMRSInd = {dmrsInd};
    candDMRSSym = {dmrsSym};
end

% ---------------------- Timing estimation ----------------------
% Use the first candidate DMRS for timing.
% Some MATLAB versions expose multiple timing APIs; we keep it simple.
rxWave = rxWaveform;

sampleRateHz = opt.SampleRate_Hz;
if isempty(sampleRateHz)
    sampleRateHz = sixgr.util.structGet(cfg, 'phy.sampleRate_Hz', []);
end

timingOffset = 0;
try
    if isempty(sampleRateHz)
        timingOffset = nrTimingEstimate(carrier, rxWave, candDMRSInd{1}, candDMRSSym{1});
    else
        timingOffset = nrTimingEstimate(carrier, rxWave, candDMRSInd{1}, candDMRSSym{1}, 'SampleRate', sampleRateHz);
    end
catch
    % If timing estimation is unavailable, continue with zero offset.
    timingOffset = 0;
end

timingOffset = max(0, round(double(timingOffset)));
if timingOffset > 0
    rxWave = rxWave(1+timingOffset:end, :);
end

% Keep one full slot available for OFDM demod even when timing estimation
% trims a few leading samples on otherwise aligned captures.
try
    ofdmInfo = nrOFDMInfo(carrier);
    slotSymbols = max(1, round(double(ofdmInfo.SymbolsPerSlot)));
    symbolLengths = double(ofdmInfo.SymbolLengths(:).');
    if numel(symbolLengths) >= slotSymbols
        expectedSamples = sum(symbolLengths(1:slotSymbols));
    else
        expectedSamples = sum(symbolLengths);
    end
    if size(rxWave, 1) > expectedSamples
        rxWave = rxWave(1:expectedSamples, :);
    end
    if size(rxWave, 1) < expectedSamples
        rxWave(end+1:expectedSamples, :) = 0; %#ok<AGROW>
    end
catch
    % Continue without padding if OFDM info is unavailable.
end

% ---------------------- OFDM demod ----------------------
try
    rxGrid = sixgr.phy.waveform.ofdmDemodulate(carrier, rxWave);
catch
    % Fallback to toolbox directly
    rxGrid = nrOFDMDemodulate(carrier, rxWave);
end

% This receiver operates on a single slot. Some toolbox metadata paths
% describe a full subframe, so trim/pad the demodulated grid to one slot.
slotSymbols = max(1, round(double(carrier.SymbolsPerSlot)));
if size(rxGrid, 2) > slotSymbols
    rxGrid = rxGrid(:, 1:slotSymbols, :);
elseif size(rxGrid, 2) < slotSymbols
    pad = complex(zeros(size(rxGrid, 1), slotSymbols - size(rxGrid, 2), size(rxGrid, 3), ...
        'like', rxGrid));
    rxGrid = cat(2, rxGrid, pad);
end

% ---------------------- Try candidates ----------------------
noiseVarUsed = opt.NoiseVar;
if isempty(noiseVarUsed)
    noiseVarUsed = NaN;
end

rx = struct();
rx.DCIBits = int8([]);
rx.ErrFlag = 1;
rx.Ok = false;
rx.CandidateIndex = 0;
rx.TimingOffset = timingOffset;

for c = 1:numel(candSymInd)
    symInd  = candSymInd{c};
    dmrsInd = candDMRSInd{c};
    dmrsSym = candDMRSSym{c};

    % Channel estimate
    try
        [hEst, nVarEst] = nrChannelEstimate(carrier, rxGrid, dmrsInd, dmrsSym);
    catch
        [hEst, nVarEst] = sixgr.phy.rx.channelEstimate(carrier, rxGrid, dmrsInd, dmrsSym);
    end

    if isnan(noiseVarUsed)
        nVar = double(nVarEst);
    else
        nVar = double(noiseVarUsed);
    end

    % Extract + equalize
    [rxSym, hSym] = nrExtractResources(symInd, rxGrid, hEst);
    [eqSym, csi] = nrEqualizeMMSE(rxSym, hSym, nVar);

    % CSI weighting (as in MathWorks examples)
    if ~isempty(csi)
        eqSym = eqSym .* csi;
    end

    % PDCCH decode -> soft bits
    try
        rxCW = nrPDCCHDecode(eqSym, nCellID, rnti, nVar);
    catch
        rxCW = nrPDCCHDecode(eqSym, nCellID, rnti);
    end

    % DCI decode (polar list)
    errFlag = 1;
    dciBits = int8([]);
    try
        [dciBits, errFlag] = nrDCIDecode(rxCW, K, listLen, rnti);
    catch
        % Some versions return only bits; infer ErrFlag as unknown
        dciBits = nrDCIDecode(rxCW, K, listLen, rnti);
        errFlag = 1;
    end

    rx.DCIBits = int8(dciBits(:));
    rx.ErrFlag = double(errFlag);
    rx.Ok = (rx.ErrFlag == 0);
    rx.CandidateIndex = c;
    rx.NoiseVar = nVar;

    if rx.Ok
        break;
    end
end

info = struct();
info.CarrierInfo = cinfo;
info.NCellID = nCellID;
info.RNTI = rnti;
info.K = K;
info.ListLength = listLen;
info.BlindSearch = blind;
info.NumCandidatesTried = numel(candSymInd);

end

function [candSymInd, candDMRSInd, candDMRSSym] = localCollectPDCCHCandidates(allSymInd, allDMRSInd, allDMRSSym)
candSymInd = {};
candDMRSInd = {};
candDMRSSym = {};
if ~iscell(allSymInd)
    return;
end
for i = 1:numel(allSymInd)
    s = allSymInd{i};
    dIdx = allDMRSInd{i};
    dSym = allDMRSSym{i};
    if ~isempty(s) && ~isempty(dIdx) && ~isempty(dSym)
        candSymInd{end+1,1} = s; %#ok<AGROW>
        candDMRSInd{end+1,1} = dIdx; %#ok<AGROW>
        candDMRSSym{end+1,1} = dSym; %#ok<AGROW>
    end
end
end

% ---------------------- Local helper ----------------------
function pdcch = localDefaultPDCCH(cfg, carrier, nCellID, rnti)
% Create a minimal, valid PDCCH configuration.

% CORESET
coreset = nrCORESETConfig;
coresetID = double(sixgr.util.structGet(cfg, 'phy.pdcch.coreset.id', 0));
localSetPropIfPresent(coreset, {'CORESETID','ID'}, coresetID);
coreset.Duration = double(sixgr.util.structGet(cfg, 'phy.pdcch.coreset.duration', 2));

fr = sixgr.util.structGet(cfg, 'phy.pdcch.coreset.frequencyResources', []);
if isempty(fr)
    % Default: enable all 6 REG-bundle groups (common in examples)
    fr = ones(1, 6);
end
coreset.FrequencyResources = double(fr(:).');

% Search space
ss = nrSearchSpaceConfig;
searchSpaceID = double(sixgr.util.structGet(cfg, 'phy.pdcch.searchSpace.id', 1));
localSetPropIfPresent(ss, {'SearchSpaceID','ID'}, searchSpaceID);
ss.CORESETID = localGetFirstProp(coreset, {'CORESETID','ID'}, 0);
ss.StartSymbolWithinSlot = double(sixgr.util.structGet(cfg, 'phy.pdcch.searchSpace.startSymbol', 0));
ss.SlotPeriodAndOffset = double(sixgr.util.structGet(cfg, 'phy.pdcch.searchSpace.slotPeriodAndOffset', [1 0]));
ss.Duration = double(sixgr.util.structGet(cfg, 'phy.pdcch.searchSpace.duration', 1));

aggr = double(sixgr.util.structGet(cfg, 'phy.pdcch.aggregationLevel', 4));
if ~ismember(aggr, [1 2 4 8 16])
    aggr = 4;
end
numCand = sixgr.util.structGet(cfg, 'phy.pdcch.searchSpace.numCandidates', []);
numCand = double(numCand(:).');
if isempty(numCand)
    numCand = zeros(1,5);
end
if numel(numCand) < 5
    numCand(numel(numCand)+1:5) = 0;
end
numCand = numCand(1:5);
idxAgg = find([1 2 4 8 16] == aggr, 1, 'first');
if isempty(idxAgg)
    idxAgg = 3;
end
if numCand(idxAgg) < 1
    numCand(idxAgg) = 1;
end
ss.NumCandidates = double(numCand(:).');

% PDCCH config
pdcch = nrPDCCHConfig;
localSetPropIfPresent(pdcch, {'NCellID','DMRSScramblingID'}, double(nCellID));
pdcch.RNTI = double(rnti);
pdcch.CORESET = coreset;
pdcch.SearchSpace = ss;

pdcch.AggregationLevel = aggr;

% Some configurations require setting the NStartBWP/NSizeBWP. If present in
% your MATLAB version, set from carrier grid.
try
    pdcch.NStartBWP = double(sixgr.util.structGet(cfg, 'phy.pdcch.nStartBWP', carrier.NStartGrid));
    pdcch.NSizeBWP  = double(sixgr.util.structGet(cfg, 'phy.pdcch.nSizeBWP', carrier.NSizeGrid));
catch
    % Ignore if properties do not exist.
end

function tf = localSetPropIfPresent(obj, propNames, value)
tf = false;
for i = 1:numel(propNames)
    p = char(string(propNames{i}));
    if isprop(obj, p)
        try
            obj.(p) = value;
            tf = true;
            return;
        catch
        end
    end
end
end

function v = localGetFirstProp(obj, propNames, defaultVal)
v = defaultVal;
for i = 1:numel(propNames)
    p = char(string(propNames{i}));
    if isprop(obj, p)
        try
            v = obj.(p);
            return;
        catch
        end
    end
end
end

end
