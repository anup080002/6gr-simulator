function [rx, info] = SRS_Rx(rxWaveform, cfg, varargin)
%SRS_Rx Receive and estimate channel from an SRS-only waveform.
%
%   [RX,INFO] = sixgr.phy.ul.SRS_Rx(RXWAVEFORM, CFG) demodulates the OFDM
%   waveform, extracts SRS REs, and estimates the channel response.
%
%   Name-Value options:
%     "Carrier"   : nrCarrierConfig override
%     "SRS"       : nrSRSConfig override
%     "NoiseVar"  : noise variance override (if known)
%
%   Outputs (RX struct):
%     .Hest        : estimated channel (K-by-L-by-NRx-by-NTxPorts)
%     .NoiseVar    : estimated or provided noise variance
%     .RxGrid      : received resource grid
%     .SRSIndices  : SRS indices
%     .SRSSymbols  : reference SRS symbols

% ---------------------- Parse inputs ----------------------
ip = inputParser;
ip.addParameter('Carrier', [], @(x) isempty(x) || isobject(x));
ip.addParameter('SRS', [], @(x) isempty(x) || isobject(x));
ip.addParameter('NoiseVar', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x>=0));
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

nVar = opt.NoiseVar;
if isempty(nVar)
    if ~isempty(nVarEst) && isfinite(nVarEst) && nVarEst >= 0
        nVar = nVarEst;
    else
        nVar = 1e-10;
    end
end

rx = struct();
rx.Hest = Hest;
rx.NoiseVar = double(nVar);
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
