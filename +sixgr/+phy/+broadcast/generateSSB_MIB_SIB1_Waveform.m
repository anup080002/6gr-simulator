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
cfgSI = localSanitizeSIB1PDSCHPrecoding(cfgSI, pdsch);

[pdcchTx, pdcchInfo] = sixgr.phy.dl.PDCCH_Tx(cfgSI, ...
    "Carrier", carrier, "PDCCH", pdcch, "DCIBits", dci.Bits, ...
    "K", double(numel(dci.Bits)), "RNTI", 65535, "NCellID", double(carrier.NCellID), ...
    "PDCCHScramblingRNTI", 0, ...
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
waveform = localConcatWaveformsWithGap(ssbWaveform, siWaveform, gapSamples);
waveform = localApplyAWGN(waveform, p.Results.SNRdB);

[~, treeHash] = sixgr.rrc.asn1.compareSIB1Trees(tree, tree);
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
    nrePerPRB = localResolveSIB1DataNREPerPRB(info, nRB, pdsch.Modulation, pdsch.NumLayers);
    xOverhead = sixgr.phy.dl.resolvePDSCHXOverhead(cfg, pdsch.SymbolAllocation);
    tbs = nrTBS(pdsch.Modulation, pdsch.NumLayers, nRB, nrePerPRB, dci.TargetCodeRate, xOverhead);
    if tbs >= numel(sib1Bits)
        targetCodeRate = dci.TargetCodeRate;
        paddedBits = int8([sib1Bits(:); zeros(tbs - numel(sib1Bits), 1, "int8")]);
        return;
    end
end
error("sixgr:phy:broadcast:SIB1AllocationTooSmall", ...
    "No anchor SIB1 PDSCH allocation fits %d payload bits.", numel(sib1Bits));
end

function nrePerPRB = localResolveSIB1DataNREPerPRB(pdschInfo, nPRB, modStr, nLayers)
% Keep SIB1 allocation TBS aligned with PDSCH_Tx's actual data-RE resolver.
qm = localQm(modStr);
nrePerPRB = NaN;
if isfield(pdschInfo, "G")
    gBits = double(pdschInfo.G);
    if isfinite(gBits) && gBits > 0
        nrePerPRB = floor(gBits / max(qm * double(nLayers) * max(double(nPRB), 1), 1));
    end
end
if ~(isfinite(nrePerPRB) && nrePerPRB > 0)
    if isfield(pdschInfo, "NRE")
        nrePerPRB = floor(double(pdschInfo.NRE) / max(double(nPRB), 1));
    elseif isfield(pdschInfo, "NREPerPRB")
        nrePerPRB = double(pdschInfo.NREPerPRB);
    end
end
if ~(isfinite(nrePerPRB) && nrePerPRB > 0)
    error("sixgr:phy:broadcast:SIB1NoDataRE", ...
        "SIB1 PDSCH allocation has no schedulable data RE.");
end
end

function qm = localQm(modStr)
switch upper(string(modStr))
    case "QPSK"
        qm = 2;
    case "16QAM"
        qm = 4;
    case "64QAM"
        qm = 6;
    case "256QAM"
        qm = 8;
    case "1024QAM"
        qm = 10;
    otherwise
        qm = 2;
end
end

function [pdcch, cfgSI] = localSIB1PDCCHConfig(carrier, cfg)
cfgSI = cfg;
cfgSI.phy.pdcch.rnti = 65535;
cfgSI.phy.pdcch.dciPayloadBits = 32;
cfgSI.phy.pdcch.KBits = 32;
cfgSI.phy.pdcch.blindSearch = true;
cfgSI.phy.pdcch.aggregationLevel = 4;
cfgSI.phy.pdcch.scramblingRNTI = 0;
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

function cfgSI = localSanitizeSIB1PDSCHPrecoding(cfgSI, pdsch)
% SI-RNTI SIB1 is a broadcast PDSCH allocation; it must not inherit
% UE-data rank/precoder state from scenario PDSCH grants.
nLayers = max(1, round(double(pdsch.NumLayers)));
cfgSI = sixgr.util.structSet(cfgSI, "phy.pdsch.numLayers", nLayers);
cfgSI = sixgr.util.structSet(cfgSI, "phy.pdsch.nLayers", nLayers);

paths = ["phy.pdsch.precoding.matrix", "phy.pdsch.precodingMatrix", "phy.pdsch.W"];
resolvedPorts = NaN;
for i = 1:numel(paths)
    path = paths(i);
    Wcfg = sixgr.util.structGet(cfgSI, path, []);
    if isempty(Wcfg)
        continue;
    end
    Wsib = localAdaptSIB1PrecoderMatrix(Wcfg, nLayers);
    if isempty(Wsib)
        cfgSI = sixgr.util.structSet(cfgSI, path, []);
    else
        cfgSI = sixgr.util.structSet(cfgSI, path, Wsib);
        resolvedPorts = size(Wsib, 1);
    end
end
if isfinite(resolvedPorts) && resolvedPorts >= nLayers
    cfgSI = sixgr.util.structSet(cfgSI, "phy.pdsch.numPorts", resolvedPorts);
    cfgSI = sixgr.util.structSet(cfgSI, "phy.pdsch.nPorts", resolvedPorts);
else
    cfgSI = sixgr.util.structSet(cfgSI, "phy.pdsch.numPorts", []);
    cfgSI = sixgr.util.structSet(cfgSI, "phy.pdsch.nPorts", []);
end
end

function Wout = localAdaptSIB1PrecoderMatrix(Wcfg, nLayers)
Wout = [];
if isempty(Wcfg)
    return;
end
nLayers = max(1, round(double(nLayers)));
if ndims(Wcfg) > 2
    if size(Wcfg, 3) == 1
        Wcfg = squeeze(Wcfg);
    else
        return;
    end
end
if ~isnumeric(Wcfg)
    return;
end
sz = size(Wcfg);
if sz(2) >= nLayers
    Wout = double(Wcfg(:, 1:nLayers));
elseif sz(1) >= nLayers
    Wout = double(Wcfg(1:nLayers, :).');
end
if isempty(Wout) || size(Wout, 1) < nLayers || size(Wout, 2) ~= nLayers
    Wout = [];
    return;
end
colNorm = sqrt(sum(abs(Wout).^2, 1));
if any(~isfinite(colNorm)) || any(colNorm <= eps)
    Wout = [];
    return;
end
Wout = Wout ./ colNorm;
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
    pdcch.RNTI = 0; % Type0 CSS physical scrambling uses nRNTI=0; DCI CRC mask uses SI-RNTI.
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
sa = size(a);
sb = size(b);
sa(end+1:3) = 1;
sb(end+1:3) = 1;
sz = max([sa(1:3); sb(1:3)], [], 1);
grid = complex(zeros(sz, "like", a));
grid(1:size(a,1), 1:size(a,2), 1:size(a,3)) = grid(1:size(a,1), 1:size(a,2), 1:size(a,3)) + a;
grid(1:size(b,1), 1:size(b,2), 1:size(b,3)) = grid(1:size(b,1), 1:size(b,2), 1:size(b,3)) + b;
end

function waveform = localConcatWaveformsWithGap(ssbWaveform, siWaveform, gapSamples)
numCols = max(size(ssbWaveform, 2), size(siWaveform, 2));
ssbWaveform = localPadWaveformColumns(ssbWaveform, numCols);
siWaveform = localPadWaveformColumns(siWaveform, numCols);
gap = complex(zeros(gapSamples, numCols, "like", ssbWaveform));
waveform = [ssbWaveform; gap; siWaveform]; %#ok<AGROW>
end

function wave = localPadWaveformColumns(wave, numCols)
if size(wave, 2) >= numCols
    return;
end
wave(:, end+1:numCols) = 0;
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
