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
configuredSRS = logical(sixgr.util.structGet(cfg, "phy.srs.enable", false));
sixgr.config.assertRuntimeFeatureUse(cfg, "srs", configuredSRS, ...
    "SRS_Tx");
if ~configuredSRS
    error("sixgr:phy:srs:DisabledByYAML", ...
        "SRS Tx cannot execute when SRS is disabled by YAML.");
end

% Carrier
if isempty(opt.Carrier)
    [carrier, cinfo] = sixgr.phy.grid.makeCarrier(cfg);
else
    carrier = opt.Carrier;
    cinfo = struct();
end

% SRS config
if isempty(opt.SRS)
    strictSRS = sixgr.phy.srs.buildSRSConfigFromScenario(cfg);
    srs = strictSRS.ToolboxSRS;
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
srsCoverage = localSRSFrequencyCoverage(carrier, srs, srsInd);

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
[windowingSamples, windowingInfo] = sixgr.phy.waveform.resolveOFDMWindowing(cfg, carrier);
[waveform, ofdmInfo] = sixgr.phy.waveform.ofdmModulate(carrier, txGrid, ...
    "Windowing", double(windowingSamples));

% Outputs
tex = struct();
tex.Waveform = waveform;
tex.Grid = txGrid;
tex.Carrier = carrier;
tex.SRS = srs;
tex.SRSIndices = srsInd;
tex.SRSSymbols = srsSym;
tex.OFDMWindowingSamples = double(windowingSamples);
tex.OFDMWindowingSource = char(string(windowingInfo.OFDMWindowingSource));
tex.OFDMWindowingEnabled = logical(windowingInfo.OFDMWindowingEnabled);
tex.SRSOccupiedPRBCount = double(srsCoverage.OccupiedPRBCount);
tex.SRSCarrierPRBCount = double(srsCoverage.CarrierPRBCount);
tex.SRSBandwidthFraction = double(srsCoverage.BandwidthFraction);
tex.SRSFrequencyPRBStart = double(srsCoverage.PRBStart);
tex.SRSFrequencyPRBEnd = double(srsCoverage.PRBEnd);
tex.SRSBandwidthCoverageStatus = char(string(srsCoverage.CoverageStatus));

info = struct();
info.CarrierInfo = cinfo;
info.SRSInfo = srsInfo;
info.OFDMInfo = ofdmInfo;
info.OFDMWindowing = windowingInfo;
info.SRSBandwidth = srsCoverage;

tx = tex;
end

% -------------------------------------------------------------------------
function coverage = localSRSFrequencyCoverage(carrier, srs, srsInd)
K = max(1, round(double(carrier.NSizeGrid)) * 12);
L = max(1, round(double(carrier.SymbolsPerSlot)));
P = 1;
if isprop(srs, "NumSRSPorts")
    P = max(1, round(double(srs.NumSRSPorts)));
end
nCarrierPRB = max(1, round(double(carrier.NSizeGrid)));
coverage = struct( ...
    "OccupiedPRBCount", NaN, ...
    "CarrierPRBCount", double(nCarrierPRB), ...
    "BandwidthFraction", NaN, ...
    "PRBStart", NaN, ...
    "PRBEnd", NaN, ...
    "CoverageStatus", "unavailable_no_srs_indices");
if isempty(srsInd)
    coverage.OccupiedPRBCount = 0;
    coverage.BandwidthFraction = 0;
    coverage.CoverageStatus = "no_srs_re_mapped";
    return;
end
idx = round(double(srsInd(:)));
idx = idx(isfinite(idx) & idx >= 1 & idx <= K * L * P);
if isempty(idx)
    coverage.OccupiedPRBCount = 0;
    coverage.BandwidthFraction = 0;
    coverage.CoverageStatus = "no_valid_srs_re_indices";
    return;
end
[kSub, ~, ~] = ind2sub([K L P], idx);
prb = unique(floor((double(kSub(:)) - 1) / 12));
prb = prb(prb >= 0 & prb < nCarrierPRB);
coverage.OccupiedPRBCount = double(numel(prb));
coverage.BandwidthFraction = double(numel(prb)) / double(nCarrierPRB);
if ~isempty(prb)
    coverage.PRBStart = double(min(prb));
    coverage.PRBEnd = double(max(prb));
end
if coverage.OccupiedPRBCount >= nCarrierPRB
    coverage.CoverageStatus = "full_carrier_bandwidth";
elseif coverage.OccupiedPRBCount > 0
    coverage.CoverageStatus = "partial_carrier_bandwidth";
else
    coverage.CoverageStatus = "no_srs_prb_occupied";
end
end
