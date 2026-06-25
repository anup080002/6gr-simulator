function [rx, info] = SRS_Rx(rxWaveform, cfg, varargin)
%SRS_Rx Receive and estimate channel from an SRS-only waveform.
%
%   [RX,INFO] = sixgr.phy.ul.SRS_Rx(RXWAVEFORM, CFG) demodulates the OFDM
%   waveform, extracts SRS REs, and estimates the channel response.
%
%   Name-Value options:
%     "Carrier"   : nrCarrierConfig override
%     "SRS"       : nrSRSConfig override
%     "NoiseVar"  : explicit runtime noise variance metadata
%     "NoiseVarDomain": "time", "grid", "frequency", or "auto"
%     "ConfiguredNoiseVariance": explicit configured/derived AWGN variance
%
%   Outputs (RX struct):
%     .Hest        : estimated channel (K-by-L-by-NRx-by-NTxPorts)
%     .NoiseVar    : estimated or provided noise variance
%     .NoiseVarStatus : "OK" or "NOT_AVAILABLE"
%     .NoiseVarSource : provenance for the used/unavailable noise variance
%     .RxGrid      : received resource grid
%     .SRSIndices  : SRS indices
%     .SRSSymbols  : reference SRS symbols

% ---------------------- Parse inputs ----------------------
ip = inputParser;
ip.addParameter('Carrier', [], @(x) isempty(x) || isobject(x));
ip.addParameter('SRS', [], @(x) isempty(x) || isobject(x));
ip.addParameter('NoiseVar', [], @(x) isempty(x) || isnumeric(x));
ip.addParameter('NoiseVarDomain', 'auto', @(x) any(strcmpi(char(string(x)), {'time','grid','frequency','auto'})));
ip.addParameter('ConfiguredNoiseVariance', [], @(x) isempty(x) || isnumeric(x));
ip.addParameter('ConfiguredNoiseVarianceSource', 'configured_awgn_derivation', @(x) ischar(x) || isstring(x));
ip.addParameter('StrictNoiseVarianceRequired', [], @(x) isempty(x) || islogical(x) || (isnumeric(x) && isscalar(x)));
ip.parse(varargin{:});
opt = ip.Results;

% Carrier
if isempty(opt.Carrier)
    [carrier, cinfo] = sixgr.phy.grid.makeCarrier(cfg);
else
    carrier = opt.Carrier;
    cinfo = struct();
end

% SRS config
if isempty(opt.SRS)
    srs = nrSRSConfig;
    srs = localApplySRSFromCfg(srs, cfg);
else
    srs = opt.SRS;
end

% OFDM demod
[rxGrid, ofdmInfo] = sixgr.phy.waveform.ofdmDemodulate(carrier, rxWaveform);

% SRS indices and symbols
[srsInd, srsInfo] = nrSRSIndices(carrier, srs);
srsSym = nrSRS(carrier, srs);

% Channel estimation
Hest = [];
nVarEst = [];
estInfo = struct();
try
    [avgWindow, srsSymbols] = localSRSChannelEstimateWindow(carrier, srs, srsInd, srsInfo);
    if localSRSFrequencyHoppingEnabled(srs) && numel(srsSymbols) > 1
        [Hest, nVarEst, estInfo] = localEstimateSRSHopped(carrier, rxGrid, srsInd, srsSym, srsSymbols, srsInfo);
    else
        [Hest, nVarEst, estInfo] = localEstimateSRSNoHop(carrier, rxGrid, srsInd, srsSym, srsInfo, avgWindow);
    end
catch
    try
        [Hest, nVarEst, estInfo] = sixgr.phy.rx.channelEstimate(carrier, rxGrid, srsInd, srsSym);
    catch
        Hest = [];
        nVarEst = [];
    end
end
noiseCandidate = opt.NoiseVar;
noiseSource = "runtime_metadata";
noiseTransformInfo = struct( ...
    "InputDomain", "grid", ...
    "OutputDomain", "resource_grid_pre_equalization", ...
    "TransformSource", "runtime_channel_estimate_grid_domain");
configuredNoiseTransformInfo = struct( ...
    "InputDomain", "time", ...
    "OutputDomain", "resource_grid_pre_equalization", ...
    "TransformSource", "not_requested");
if isempty(noiseCandidate)
    noiseCandidate = nVarEst;
    noiseSource = "runtime_channel_estimate";
else
    [noiseCandidate, noiseTransformInfo] = sixgr.phy.waveform.convertNoiseVarianceToGridDomain( ...
        noiseCandidate, ofdmInfo, ...
        "InputDomain", opt.NoiseVarDomain, ...
        "Source", noiseSource);
end
configuredNoiseVariance = opt.ConfiguredNoiseVariance;
if ~isempty(configuredNoiseVariance)
    [configuredNoiseVariance, configuredNoiseTransformInfo] = sixgr.phy.waveform.convertNoiseVarianceToGridDomain( ...
        configuredNoiseVariance, ofdmInfo, ...
        "InputDomain", "time", ...
        "Source", opt.ConfiguredNoiseVarianceSource);
end
[nVar, noiseStatus] = sixgr.phy.ul.resolveULNoiseVariance(noiseCandidate, cfg, ...
    "ChannelType", "SRS", ...
    "OriginalSource", noiseSource, ...
    "StrictRequired", opt.StrictNoiseVarianceRequired, ...
    "ConfiguredNoiseVariance", configuredNoiseVariance, ...
    "ConfiguredNoiseVarianceSource", opt.ConfiguredNoiseVarianceSource);
nVar = double(nVar);

rx = struct();
rx.Hest = Hest;
rx.NoiseVar = nVar;
rx.NoiseVarDomain = "resource_grid_pre_equalization";
rx.NoiseVarTransformSource = char(string(sixgr.util.structGet(noiseTransformInfo, "TransformSource", "")));
rx.SampleToGridNoiseVarianceGain = double(sixgr.util.structGet(noiseTransformInfo, "SampleToGridNoiseVarianceGain", NaN));
rx.NoiseVarStatus = char(string(noiseStatus.Status));
rx.NoiseVarSource = char(string(noiseStatus.Source));
rx.NoiseVarReason = char(string(noiseStatus.Reason));
rx.NoiseVarStrictFailure = logical(noiseStatus.StrictFailure);
rx.MeasurementAttempted = logical(noiseStatus.IsValid);
rx.MeasurementUsable = logical(noiseStatus.IsValid);
rx.FailureReason = "";
if ~logical(noiseStatus.IsValid)
    rx.FailureReason = char(string(noiseStatus.Reason));
end
rx.RxGrid = rxGrid;
rx.Carrier = carrier;
rx.SRS = srs;
rx.SRSIndices = srsInd;
rx.SRSSymbols = srsSym;

info = struct();
info.CarrierInfo = cinfo;
info.OFDMInfo = ofdmInfo;
info.SRSInfo = srsInfo;
info.ChannelEstimation = estInfo;
info.NoiseVariance = noiseStatus;
info.OFDMNoiseTransform = sixgr.util.structGet(ofdmInfo, "NoiseTransform", struct());
info.NoiseVarianceTransform = noiseTransformInfo;
info.ConfiguredNoiseVarianceTransform = configuredNoiseTransformInfo;

end

function [Hest, nVarEst, estInfo] = localEstimateSRSNoHop(carrier, rxGrid, srsInd, srsSym, srsInfo, avgWindow)
if isfield(srsInfo,'CDMLengths')
    [Hest, nVarEst, estInfo] = nrChannelEstimate(carrier, rxGrid, srsInd, srsSym, ...
        'CDMLengths', srsInfo.CDMLengths, 'AveragingWindow', avgWindow);
else
    [Hest, nVarEst, estInfo] = nrChannelEstimate(carrier, rxGrid, srsInd, srsSym, ...
        'AveragingWindow', avgWindow);
end
if isstruct(estInfo)
    estInfo.AveragingWindow = avgWindow;
    estInfo.FrequencyHoppingHandled = false;
end
end

function [Hest, nVarEst, estInfo] = localEstimateSRSHopped(carrier, rxGrid, srsInd, srsSym, srsSymbols, srsInfo)
Hest = [];
nVals = [];
estInfo = struct("AveragingWindow", [0 0], "FrequencyHoppingHandled", true, "HopCount", numel(srsSymbols));
if isempty(srsInd)
    nVarEst = NaN;
    return;
end
K = double(carrier.NSizeGrid) * 12;
L = double(carrier.SymbolsPerSlot);
nPorts = max(1, ceil(max(double(srsInd(:))) / max(K * L, 1)));
[~, symIdx, ~] = ind2sub([K, L, max(1, nPorts)], double(srsInd(:)));
srsSymVec = srsSym(:);
for ii = 1:numel(srsSymbols)
    sym = double(srsSymbols(ii));
    mask = symIdx == sym;
    if ~any(mask)
        continue;
    end
    [Hpart, nPart, infoPart] = localEstimateSRSNoHop(carrier, rxGrid, srsInd(mask), srsSymVec(mask), srsInfo, [0 0]);
    if isempty(Hpart)
        continue;
    end
    if isempty(Hest)
        Hest = complex(zeros(size(Hpart), "like", Hpart));
    end
    if ndims(Hpart) >= 2 && sym >= 1 && sym <= size(Hpart, 2)
        Hest(:, sym, :, :) = Hpart(:, sym, :, :);
    else
        Hest = Hpart;
    end
    if isfinite(double(nPart)) && double(nPart) >= 0
        nVals(end+1, 1) = double(nPart); %#ok<AGROW>
    end
    if ii == 1 && isstruct(infoPart)
        estInfo.FirstHopInfo = infoPart;
    end
end
if isempty(nVals)
    nVarEst = NaN;
else
    nVarEst = mean(nVals, "omitnan");
end
end

function [avgWindow, srsSymbols] = localSRSChannelEstimateWindow(carrier, srs, srsInd, srsInfo)
combSize = double(sixgr.util.structGet(srsInfo, "CombSize", sixgr.util.structGet(srsInfo, "KSRS", NaN)));
if ~isfinite(combSize)
    combSize = double(sixgr.util.structGet(srs, "CombSize", NaN));
end
if ~isfinite(combSize)
    combSize = 2;
end
srsSymbols = [];
if ~isempty(srsInd)
    K = double(carrier.NSizeGrid) * 12;
    L = double(carrier.SymbolsPerSlot);
    nPorts = max(1, round(double(sixgr.util.structGet(srs, "NumSRSPorts", 1))));
    [~, symIdx, ~] = ind2sub([K, L, nPorts], double(srsInd(:)));
    srsSymbols = unique(double(symIdx(:)), "stable");
end
if combSize >= 4 || numel(srsSymbols) <= 1
    avgWindow = [0 0];
else
    avgWindow = [0 max(0, numel(srsSymbols) - 1)];
end
end

function tf = localSRSFrequencyHoppingEnabled(srs)
raw = [];
try
    raw = srs.FrequencyHopping;
catch
    tf = false;
    return;
end
if ischar(raw) || isstring(raw)
    token = lower(strtrim(string(raw)));
    tf = ~(token == "" || token == "neither" || token == "disabled" || token == "off" || token == "none");
elseif isnumeric(raw) || islogical(raw)
    tf = any(double(raw(:)) ~= 0);
else
    tf = false;
end
end

% -------------------------------------------------------------------------
function srs = localApplySRSFromCfg(srs, cfg)
    nPorts = sixgr.util.structGet(cfg, 'phy.srs.nPorts', []);
    if ~isempty(nPorts) && isprop(srs,'NumSRSPorts')
        srs.NumSRSPorts = double(nPorts);
    end

    period = sixgr.util.structGet(cfg, 'phy.srs.period_slots', []);
    if ~isempty(period) && isprop(srs,'SRSPeriod')
        srs.SRSPeriod = [double(period) 0];
    end

    fields = {
        'BandwidthIndex',
        'NumSRSSymbols',
        'SymbolStart',
        'NumRepetition',
        'CyclicShift',
        'FrequencyStart',
        'FrequencyShift',
        'FrequencyHopping',
        'GroupOrSequenceHopping',
        'SequenceId'};

    for k = 1:numel(fields)
        f = fields{k};
        v = sixgr.util.structGet(cfg, ['phy.srs.' f], []);
        if ~isempty(v) && isprop(srs, f)
            try
                srs.(f) = v;
            catch
            end
        end
    end
end
