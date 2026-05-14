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
    if isfield(srsInfo,'CDMLengths')
        [Hest, nVarEst, estInfo] = nrChannelEstimate(carrier, rxGrid, srsInd, srsSym, 'CDMLengths', srsInfo.CDMLengths);
    else
        [Hest, nVarEst, estInfo] = nrChannelEstimate(carrier, rxGrid, srsInd, srsSym);
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
if isempty(noiseCandidate)
    noiseCandidate = nVarEst;
    noiseSource = "runtime_channel_estimate";
else
    noiseCandidate = localConvertNoiseVarToGridDomain(noiseCandidate, ofdmInfo);
end
configuredNoiseVariance = opt.ConfiguredNoiseVariance;
if ~isempty(configuredNoiseVariance)
    configuredNoiseVariance = localConvertNoiseVarToGridDomain(configuredNoiseVariance, ofdmInfo);
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

function nVarGrid = localConvertNoiseVarToGridDomain(nVarTime, ofdmInfo)
nVarGrid = double(nVarTime);
if nargin < 2 || ~isstruct(ofdmInfo)
    return;
end
nfft = double(sixgr.util.structGet(ofdmInfo, "Nfft", NaN));
if isfinite(nfft) && nfft > 0
    nVarGrid = nVarGrid * nfft;
end
end
