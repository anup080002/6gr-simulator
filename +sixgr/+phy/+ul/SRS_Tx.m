function [tx, info] = SRS_Tx(cfg, varargin)
%SRS_Tx Generate a basic SRS waveform (UL sounding reference signal).
%
%   [TX,INFO] = sixgr.phy.ul.SRS_Tx(CFG) builds a carrier and SRS
%   configuration from CFG and generates an OFDM waveform containing only
%   SRS (no PUSCH/PUCCH) for channel sounding.
%
%   Name-Value options:
%     "Carrier"      : nrCarrierConfig override
%     "SRS"          : nrSRSConfig override
%     "NumSRSPorts"  : override number of SRS ports
%     "SRSPeriod"    : override periodicity as [P offset] (slots)
%
%   Outputs (TX struct):
%     .Waveform     : time-domain OFDM waveform
%     .Grid         : resource grid containing SRS
%     .Carrier      : carrier config object
%     .SRS          : nrSRSConfig object
%     .SRSIndices   : indices used to map SRS
%     .SRSSymbols   : generated SRS symbols

% ---------------------- Parse inputs ----------------------
ip = inputParser;
ip.addParameter('Carrier', [], @(x) isempty(x) || isobject(x));
ip.addParameter('SRS', [], @(x) isempty(x) || isobject(x));
ip.addParameter('NumSRSPorts', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x>=1));
ip.addParameter('SRSPeriod', [], @(x) isempty(x) || (isnumeric(x) && numel(x)==2));
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

% Overrides
if ~isempty(opt.NumSRSPorts) && isprop(srs,'NumSRSPorts')
    srs.NumSRSPorts = double(opt.NumSRSPorts);
end
if ~isempty(opt.SRSPeriod) && isprop(srs,'SRSPeriod')
    srs.SRSPeriod = double(opt.SRSPeriod(:).');
end

% Indices and symbols
[srsInd, srsInfo] = nrSRSIndices(carrier, srs);
srsSym = nrSRS(carrier, srs);

% Grid mapping
K = carrier.NSizeGrid*12;
L = carrier.SymbolsPerSlot;
P = 1;
if isprop(srs,'NumSRSPorts')
    P = max(1, double(srs.NumSRSPorts));
end

try
    txGrid = nrResourceGrid(carrier, P);
catch
    txGrid = complex(zeros(K, L, P));
end

txGrid(srsInd) = srsSym;

% OFDM modulation
[waveform, ofdmInfo] = sixgr.phy.waveform.ofdmModulate(carrier, txGrid);

% Outputs
tex = struct();
tex.Waveform = waveform;
tex.Grid = txGrid;
tex.Carrier = carrier;
tex.SRS = srs;
tex.SRSIndices = srsInd;
tex.SRSSymbols = srsSym;

info = struct();
info.CarrierInfo = cinfo;
info.SRSInfo = srsInfo;
info.OFDMInfo = ofdmInfo;

tx = tex;
end

% -------------------------------------------------------------------------
function srs = localApplySRSFromCfg(srs, cfg)
    % Enable flag is handled by caller; here we just map parameters.

    nPorts = sixgr.util.structGet(cfg, 'phy.srs.nPorts', []);
    if ~isempty(nPorts) && isprop(srs,'NumSRSPorts')
        srs.NumSRSPorts = double(nPorts);
    end

    % Periodicity (slots) in cfg.phy.srs.period_slots
    period = sixgr.util.structGet(cfg, 'phy.srs.period_slots', []);
    if ~isempty(period) && isprop(srs,'SRSPeriod')
        srs.SRSPeriod = [double(period) 0];
    end

    % Allow users to override typical SRSConfig fields if present
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
