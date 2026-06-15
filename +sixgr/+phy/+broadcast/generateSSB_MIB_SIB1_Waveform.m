function tx = generateSSB_MIB_SIB1_Waveform(cfg, varargin)
%GENERATESSB_MIB_SIB1_WAVEFORM Generate SSB/PBCH plus SI-RNTI SIB1 waveform.

p = inputParser;
p.addParameter("SNRdB", Inf, @(x) isnumeric(x) && isscalar(x));
p.addParameter("Seed", [], @(x) isempty(x) || (isnumeric(x) && isscalar(x)));
p.parse(varargin{:});
if nargin < 1 || isempty(cfg)
    cfg = sixgr.config.defaultConfig();
end
[siSupported, siReason] = sixgr.phy.broadcast.siRNTIWaveformSupported();
if ~siSupported
    error("sixgr:phy:broadcast:SIRNTIUnsupported", ...
        "Strict SIB1 waveform generation requires SI-RNTI 65535 support: %s", siReason);
end
if ~isempty(p.Results.Seed)
    rng(round(double(p.Results.Seed)), "twister");
end

cfg = localNormalizeBroadcastCfg(cfg);
tree = sixgr.rrc.asn1.buildBCCHDLSCHMessage(cfg);
[sib1Bits, asn1Meta] = sixgr.rrc.asn1.encodeSIB1UPER(tree);
[carrier, ~] = sixgr.phy.grid.makeCarrier(cfg);
[pdsch, dci, targetCodeRate, paddedBits] = localSelectSIB1Allocation(carrier, cfg, sib1Bits);
[pdcch, cfgSI] = localSIB1PDCCHConfig(carrier, cfg);

[pdcchTx, pdcchInfo] = sixgr.phy.dl.PDCCH_Tx(cfgSI, ...
    "Carrier", carrier, "PDCCH", pdcch, "DCIBits", dci.Bits, ...
    "K", double(numel(dci.Bits)), "RNTI", 65535, "NCellID", double(carrier.NCellID), ...
    "OFDMModulate", false);
[pdschTx, pdschInfo] = sixgr.phy.dl.PDSCH_Tx(cfgSI, ...
    "Carrier", carrier, "PDSCH", pdsch, "TransportBlockBits", paddedBits, ...
    "TargetCodeRate", targetCodeRate, "RV", double(dci.RV));

siGrid = localAddGrids(pdcchTx.Grid, pdschTx.Grid);
siWaveform = sixgr.phy.waveform.ofdmModulate(carrier, siGrid);
[ssbWaveform, ~, ssbInfo] = sixgr.phy.dl.SSB_Tx(cfg, "NumSubframes", localSSBObservationSubframes(cfg), ...
    "SSBIndex", double(sixgr.util.structGet(cfg, "phy.ssb.runtimeSSBIndex", 0)));
sampleRate = double(sixgr.util.structGet(ssbInfo, "SampleRate_Hz", localSampleRate(carrier)));
gapSamples = round(0.001 * sampleRate);
waveform = [ssbWaveform; complex(zeros(gapSamples, size(ssbWaveform, 2))); siWaveform]; %#ok<AGROW>
waveform = localApplyAWGN(waveform, p.Results.SNRdB);

treeHash = sixgr.rrc.asn1.compareSIB1Trees(tree, tree);
tx = struct();
tx.Waveform = waveform;
tx.SSBWaveform = ssbWaveform;
tx.SIB1Waveform = siWaveform;
tx.SIB1WaveformStartSample = size(ssbWaveform, 1) + gapSamples;
tx.SampleRateHz = sampleRate;
tx.Carrier = carrier;
tx.PDCCH = pdcch;
tx.PDSCH = pdsch;
tx.SIB1Grid = siGrid;
tx.TxTree = tree;
tx.TxTreeHash = treeHash.TxTreeHash;
tx.SIB1Bits = sib1Bits;
tx.SIB1PaddedBits = paddedBits;
tx.SIB1PayloadHash = asn1Meta.PayloadHash;
tx.SIB1PayloadHex = asn1Meta.EncodedHex;
tx.SIB1PayloadNumBits = double(numel(sib1Bits));
tx.SIB1TransportBlockSize = double(numel(paddedBits));
tx.DCI = dci;
tx.DCIPayloadHex = dci.PayloadHex;
tx.PDCCHInfo = pdcchInfo;
tx.PDSCHInfo = pdschInfo;
tx.SSBInfo = ssbInfo;
tx.CORESET0 = struct("CORESETID", 0, "Duration", double(pdcch.CORESET.Duration), ...
    "RBStart", 0, "NumRB", double(min(carrier.NSizeGrid, 6 * numel(pdcch.CORESET.FrequencyResources))));
tx.SearchSpace0 = struct("SearchSpaceID", 0, "Type", "Type0-PDCCH CSS", "RNTI", 65535);
tx.UsedOracleFields = strings(0, 1);
tx.ProxyUsed = false;
tx.Skipped = false;
tx.ToolboxMissing = false;
end

function cfg = localNormalizeBroadcastCfg(cfg)
if ~isfield(cfg, "phy")
    cfg.phy = struct();
end
if ~isfield(cfg.phy, "carrier")
    cfg.phy.carrier = struct();
end
cfg.phy.carrier.NCellID = double(sixgr.util.structGet(cfg, "phy.carrier.NCellID", 1));
cfg.phy.carrier.SubcarrierSpacing = double(sixgr.util.structGet(cfg, "phy.carrier.SubcarrierSpacing", ...
    sixgr.util.structGet(cfg, "phy.carrier.SubcarrierSpacing_kHz", 30)));
cfg.phy.carrier.SubcarrierSpacing_kHz = cfg.phy.carrier.SubcarrierSpacing;
cfg.phy.carrier.NSizeGrid = double(sixgr.util.structGet(cfg, "phy.carrier.NSizeGrid", 52));
cfg.phy.carrier.NStartGrid = double(sixgr.util.structGet(cfg, "phy.carrier.NStartGrid", 0));
cfg.phy.carrier.NSlot = 0;
cfg.phy.carrier.NFrame = 0;
cfg.phy.carrier.CyclicPrefix = char(string(sixgr.util.structGet(cfg, "phy.carrier.CyclicPrefix", "normal")));
cfg.phy.ssb.enable = true;
cfg.phy.sib1.enable = true;
cfg.phy.pdcch.enable = true;
cfg.phy.pdsch.enable = true;
end

function [pdsch, dci, targetCodeRate, paddedBits] = localSelectSIB1Allocation(carrier, cfg, sib1Bits)
for nRB = 6:double(carrier.NSizeGrid)
    [dci, pdsch] = sixgr.phy.broadcast.buildSIB1DCI10(carrier, cfg, "PRBStart", 0, "PRBCount", nRB, ...
        "SymbolStart", 2, "NumSymbols", 12, "MCSIndex", 0, "RV", 0);
    [~, info] = nrPDSCHIndices(carrier, pdsch);
    tbs = nrTBS(pdsch.Modulation, pdsch.NumLayers, nRB, info.NREPerPRB, dci.TargetCodeRate, 0);
    if tbs >= numel(sib1Bits)
        targetCodeRate = dci.TargetCodeRate;
        paddedBits = int8([sib1Bits(:); zeros(tbs - numel(sib1Bits), 1, "int8")]);
        return;
    end
end
error("sixgr:phy:broadcast:SIB1AllocationTooSmall", ...
    "No anchor SIB1 PDSCH allocation fits %d payload bits.", numel(sib1Bits));
end

function [pdcch, cfgSI] = localSIB1PDCCHConfig(carrier, cfg)
cfgSI = cfg;
cfgSI.phy.pdcch.rnti = 65535;
cfgSI.phy.pdcch.dciPayloadBits = 32;
cfgSI.phy.pdcch.KBits = 32;
cfgSI.phy.pdcch.blindSearch = true;
cfgSI.phy.pdcch.aggregationLevel = 4;
cfgSI.phy.pdcch.allowBlindCandidateTimingEstimate = false;
cfgSI.phy.pdcch.searchSpace.numCandidates = [0 0 1 0 0];
cfgSI.phy.pdcch.searchSpace.id = 0;
cfgSI.phy.pdcch.searchSpace.startSymbol = 0;
cfgSI.phy.pdcch.searchSpace.duration = 1;
cfgSI.phy.pdcch.searchSpace.slotPeriodAndOffset = [1 0];
cfgSI.phy.pdcch.coreset.id = 0;
cfgSI.phy.pdcch.coreset.duration = 2;
cfgSI.phy.pdcch.coreset.frequencyResources = ones(1, max(1, min(6, ceil(double(carrier.NSizeGrid) / 6))));
cfgSI.phy.pdsch.RNTI = 65535;
cfgSI.phy.pdsch.rnti = 65535;
cfgSI.phy.pdsch.modulation = "QPSK";
cfgSI.phy.pdsch.numLayers = 1;
cfgSI.phy.pdsch.nLayers = 1;
pdcch = localBuildPDCCHObject(carrier, cfgSI);
end

function pdcch = localBuildPDCCHObject(carrier, cfgSI)
coreset = nrCORESETConfig;
try
    coreset.CORESETID = 0;
catch
end
coreset.Duration = 2;
coreset.FrequencyResources = ones(1, max(1, min(6, ceil(double(carrier.NSizeGrid) / 6))));
coreset.REGBundleSize = 6;
coreset.InterleaverSize = 2;
coreset.ShiftIndex = double(carrier.NCellID);
ss = nrSearchSpaceConfig;
try
    ss.SearchSpaceID = 0;
catch
end
ss.CORESETID = 0;
ss.StartSymbolWithinSlot = 0;
ss.SlotPeriodAndOffset = [1 0];
ss.Duration = 1;
ss.NumCandidates = [0 0 1 0 0];
pdcch = nrPDCCHConfig;
try
    pdcch.NCellID = double(carrier.NCellID);
catch
end
try
    pdcch.RNTI = 65519; % Object validator excludes SI-RNTI; TX/RX calls use 65535.
catch
end
pdcch.CORESET = coreset;
pdcch.SearchSpace = ss;
pdcch.AggregationLevel = 4;
try
    pdcch.NStartBWP = double(carrier.NStartGrid);
    pdcch.NSizeBWP = double(carrier.NSizeGrid);
catch
end
end

function grid = localAddGrids(a, b)
sz = max([size(a); size(b)], [], 1);
if numel(sz) < 3
    sz(3) = 1;
end
grid = complex(zeros(sz, "like", a));
grid(1:size(a,1), 1:size(a,2), 1:size(a,3)) = grid(1:size(a,1), 1:size(a,2), 1:size(a,3)) + a;
grid(1:size(b,1), 1:size(b,2), 1:size(b,3)) = grid(1:size(b,1), 1:size(b,2), 1:size(b,3)) + b;
end

function sampleRate = localSampleRate(carrier)
info = nrOFDMInfo(carrier);
sampleRate = double(info.SampleRate);
end

function n = localSSBObservationSubframes(cfg)
n = double(sixgr.util.structGet(cfg, "phy.sib1.ssbObservationSubframes", ...
    sixgr.util.structGet(cfg, "phy.ssb.pbchObservationSubframes", 5)));
n = max(1, round(n));
end

function y = localApplyAWGN(x, snrDB)
y = x;
snrDB = double(snrDB);
if ~isfinite(snrDB)
    return;
end
sigPower = mean(abs(x(:)).^2, "omitnan");
if ~(isfinite(sigPower) && sigPower > 0)
    return;
end
noiseVar = sigPower / 10^(snrDB / 10);
n = sqrt(noiseVar/2) * (randn(size(x), "like", real(x)) + 1j * randn(size(x), "like", real(x)));
y = x + n;
end
