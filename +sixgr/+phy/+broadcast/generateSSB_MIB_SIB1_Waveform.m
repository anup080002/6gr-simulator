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
localRequireBroadcastFeature(cfg, "ssb", "phy.ssb.enable");
localRequireBroadcastFeature(cfg, "pbch", "phy.pbch.enable");
localRequireBroadcastFeature(cfg, "pdcch", "phy.pdcch.enable");
localRequireBroadcastFeature(cfg, "sib1", "phy.sib1.enable");
localRequireEnabledPath(cfg, "phy.pdsch.enable", "SIB1 PDSCH");

cfg = localNormalizeBroadcastCfg(cfg);
tree = sixgr.rrc.asn1.buildBCCHDLSCHMessage(cfg);
[sib1Bits, asn1Meta] = sixgr.rrc.asn1.encodeSIB1UPER(tree);
[carrier, ~] = sixgr.phy.grid.makeCarrier(cfg);
[pdcch, cfgSI, carrierSI, type0, sib1AbsoluteSlot] = ...
    localSIB1PDCCHConfig(carrier, cfg);
[pdsch, dci, targetCodeRate, paddedBits] = ...
    localSelectSIB1Allocation(carrierSI, cfgSI, sib1Bits);
cfgSI = localSanitizeSIB1PDSCHPrecoding(cfgSI, pdsch);

[pdcchTx, pdcchInfo] = sixgr.phy.dl.PDCCH_Tx(cfgSI, ...
    "Carrier", carrierSI, "PDCCH", pdcch, "DCIBits", dci.Bits, ...
    "K", double(numel(dci.Bits)), "RNTI", 65535, "NCellID", double(carrierSI.NCellID), ...
    "PDCCHScramblingRNTI", 0, ...
    "OFDMModulate", true);
[controlRx, controlInfo] = sixgr.phy.dl.PDCCH_Rx( ...
    pdcchTx.Waveform, cfgSI, "Carrier", carrierSI, "PDCCH", pdcch, ...
    "K", double(numel(dci.Bits)), "RNTI", 65535, ...
    "PDCCHScramblingRNTI", 0, ...
    "ExpectedDCIBits", int8(dci.Bits(:)));
controlEvent = sixgr.pdsch.RASIPDSCHContext.decodedControlEvent( ...
    controlRx, controlInfo, "sib1", 65535, "1_0", dci.Bits, ...
    "PDCCHAbsoluteSlot", sib1AbsoluteSlot, ...
    "PDCCHDataIndicesOneBased", pdcchTx.PDCCHInd, ...
    "PDCCHDMRSIndicesOneBased", pdcchTx.DMRSInd, ...
    "EvidenceRole", "transmit_loopback_decode");
strict = sixgr.pdsch.RASIPDSCHContext.materialize( ...
    carrierSI, pdsch, controlEvent, ...
    localProcedureContext(cfgSI, carrierSI, dci, pdsch), ...
    "TransportBlockSize", numel(paddedBits), ...
    "ChannelModel", "AWGN");
[pdschTx, pdschInfo] = sixgr.phy.dl.PDSCH_Tx(cfgSI, ...
    "Carrier", carrierSI, "TransportBlockBits", paddedBits, ...
    "Assignment", strict.Assignment, ...
    "ResourcePlan", strict.ResourcePlan, ...
    "ReferenceSignalConfig", strict.ReferenceSignalConfig, ...
    "PrecoderBundle", strict.PrecoderBundle, ...
    "IntegrationContext", strict.IntegrationContext, ...
    "ExecutionProfile", "ra_si_strict");

siGrid = localAddGrids(pdcchTx.Grid, pdschTx.Grid);
siWaveform = sixgr.phy.waveform.ofdmModulate(carrierSI, siGrid);
[ssbWaveform, ~, ssbInfo] = sixgr.phy.dl.SSB_Tx(cfg, "NumSubframes", localSSBObservationSubframes(cfg), ...
    "SSBIndex", double(sixgr.util.structGet(cfg, "phy.ssb.runtimeSSBIndex", 0)));
sampleRate = double(sixgr.util.structGet(ssbInfo, "SampleRate_Hz", localSampleRate(carrier)));
sib1StartSample = localAbsoluteSlotStartSample( ...
    sib1AbsoluteSlot, carrierSI, sampleRate);
waveform = localComposeAbsoluteTimeline( ...
    ssbWaveform, siWaveform, sib1StartSample);
waveform = localApplyAWGN(waveform, p.Results.SNRdB);

[~, treeHash] = sixgr.rrc.asn1.compareSIB1Trees(tree, tree);
tx = struct();
tx.Waveform = waveform;
tx.SSBWaveform = ssbWaveform;
tx.SIB1Waveform = siWaveform;
tx.SIB1WaveformStartSample = sib1StartSample;
tx.SIB1AbsoluteSlot = sib1AbsoluteSlot;
tx.Type0MonitoringOccasion = type0.MonitoringOccasions( ...
    localMonitoringOccasionOrdinal(cfg), :);
tx.SampleRateHz = sampleRate;
tx.Carrier = carrierSI;
tx.PDCCH = pdcch;
tx.PDSCH = pdsch;
% Preserve the exact resource indices materialized by the production
% transmitters.  Downstream evidence must describe the transmitted grid,
% not regenerate indices from configuration after the fact.
tx.PDCCHTx = pdcchTx;
tx.PDSCHTx = pdschTx;
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
tx.PDSCHControlEvent = strict.ControlEvent;
tx.PDSCHAssignment = strict.Assignment;
tx.PDSCHResourcePlan = strict.ResourcePlan;
tx.PDSCHReferenceSignalConfig = strict.ReferenceSignalConfig;
tx.PDSCHPrecoderBundle = strict.PrecoderBundle;
tx.PDSCHIntegrationContext = strict.IntegrationContext;
tx.PDSCHExecutionProfile = "ra_si_strict";
tx.SSBInfo = ssbInfo;
tx.MIBPDCCHConfigSIB1 = double(sixgr.util.structGet(cfgSI, "phy.sib1.decodedPDCCHConfigSIB1", ...
    localPDCCHConfigSIB1(cfg)));
tx.CORESET0 = sixgr.util.structGet(cfgSI, "phy.sib1.resolvedCORESET0", ...
    struct("CORESETID", 0, "Duration", double(pdcch.CORESET.Duration), ...
    "RBStart", 0, "NumRB", double(min(carrier.NSizeGrid, 6 * numel(pdcch.CORESET.FrequencyResources)))));
tx.SearchSpace0 = sixgr.util.structGet(cfgSI, "phy.sib1.resolvedSearchSpace0", ...
    struct("SearchSpaceID", 0, "Type", "Type0-PDCCH CSS", "RNTI", 65535));
tx.UsedOracleFields = strings(0, 1);
tx.ProxyUsed = false;
tx.Skipped = false;
tx.ToolboxMissing = false;
end

function context = localProcedureContext(cfg, carrier, dci, pdsch)
absoluteSlot = double(sixgr.util.structGet( ...
    cfg, "phy.sib1.pdcchAbsoluteSlot", NaN));
if ~(isscalar(absoluteSlot) && isfinite(absoluteSlot) && ...
        absoluteSlot >= 0 && absoluteSlot == round(absoluteSlot))
    error("sixgr:phy:broadcast:MissingSIB1AbsoluteSlot", ...
        "SIB1 PDCCH/PDSCH absolute slot must be resolved before materialization.");
end
context = struct( ...
    "Procedure", "sib1", ...
    "RNTI", 65535, "RNTIType", "SI-RNTI", ...
    "UEId", 0, ...
    "ServingCellId", double(carrier.NCellID), ...
    "SchedulingCellId", double(carrier.NCellID), ...
    "CCId", 0, "BWPId", 0, "ConfigurationEpoch", 0, ...
    "PDCCHAbsoluteSlot", absoluteSlot, ...
    "PDSCHAbsoluteSlot", absoluteSlot, "K0", 0, ...
    "MCSTable", "qam64", "MCSIndex", double(dci.MCSIndex), ...
    "TargetCodeRate", double(dci.TargetCodeRate), ...
    "XOverhead", sixgr.phy.dl.resolvePDSCHXOverhead( ...
        cfg, pdsch.SymbolAllocation), ...
    "RV", double(dci.RV), "NDI", 1, ...
    "HARQProcessId", 0, "TCIStateId", 0, ...
    "ActiveBWPContextPresent", true, "EpochCurrent", true, ...
    "ServingCellActive", true, "MCSContextSupported", true, ...
    "TCIStateActive", true, "UECapability1024QAM", false, ...
    "RRCEnabled1024QAM", false, "DeploymentAllows1024QAM", false, ...
    "FrequencyRange", string(sixgr.util.structGet(cfg, ...
        "frequency.range_name", sixgr.util.structGet(cfg, ...
        "phy.frequencyRange", "FR1"))), ...
    "OperatingBand", string(sixgr.util.structGet(cfg, ...
        "frequency.band_name", sixgr.util.structGet(cfg, ...
        "initial_access.band_context", "unspecified"))), ...
    "DeploymentClass", "common_search_space_ra_si", ...
    "FrequencyRangeAllows1024QAM", false, ...
    "BandAllows1024QAM", false);
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
end

function localRequireBroadcastFeature(cfg, featureName, runtimePath)
actual = sixgr.util.structGet(cfg, runtimePath, []);
sixgr.config.assertRuntimeFeatureUse(cfg, featureName, actual, ...
    "generateSSB_MIB_SIB1_Waveform:" + featureName);
if ~logical(actual)
    error("sixgr:phy:broadcast:FeatureDisabledByConfiguration", ...
        "Cannot generate the SIB1 acquisition waveform because YAML feature %s is disabled.", ...
        char(featureName));
end
end

function localRequireEnabledPath(cfg, runtimePath, label)
actual = sixgr.util.structGet(cfg, runtimePath, []);
if ~((islogical(actual) || isnumeric(actual)) && isscalar(actual) && ...
        isfinite(double(actual)) && any(double(actual) == [0 1]))
    error("sixgr:phy:broadcast:MissingFeatureConfiguration", ...
        "%s requires an explicit boolean %s.", char(label), char(runtimePath));
end
if ~logical(actual)
    error("sixgr:phy:broadcast:FeatureDisabledByConfiguration", ...
        "%s is disabled by %s=false.", char(label), char(runtimePath));
end
end

function [pdsch, dci, targetCodeRate, paddedBits] = localSelectSIB1Allocation(carrier, cfg, sib1Bits)
allocation = sixgr.util.structGet(cfg, ...
    "initial_access.sib1.pdsch", sixgr.util.structGet(cfg, ...
    "phy.sib1.pdsch", struct()));
required = ["prb_start","num_prb","symbol_start","num_symbols","mcs","rv"];
if ~(isstruct(allocation) && isscalar(allocation))
    error("sixgr:phy:broadcast:MissingSIB1Allocation", ...
        "Strict SIB1 generation requires initial_access.sib1.pdsch.");
end
for ii = 1:numel(required)
    if ~isfield(allocation, required(ii)) || isempty(allocation.(required(ii)))
        error("sixgr:phy:broadcast:MissingSIB1Allocation", ...
            "Strict SIB1 allocation is missing %s.", required(ii));
    end
end
prbStart = localNonnegativeInteger(allocation.prb_start, "prb_start");
nRB = localPositiveInteger(allocation.num_prb, "num_prb");
symbolStart = localNonnegativeInteger( ...
    allocation.symbol_start, "symbol_start");
numSymbols = localPositiveInteger( ...
    allocation.num_symbols, "num_symbols");
mcs = localNonnegativeInteger(allocation.mcs, "mcs");
rv = localNonnegativeInteger(allocation.rv, "rv");
if prbStart + nRB > double(carrier.NSizeGrid)
    error("sixgr:phy:broadcast:SIB1AllocationOutsideBWP", ...
        "Configured SIB1 PRB interval [%d,%d) exceeds NSizeGrid=%d.", ...
        prbStart, prbStart + nRB, double(carrier.NSizeGrid));
end
[dci, pdsch] = sixgr.phy.broadcast.buildSIB1DCI10(carrier, cfg, ...
    "PRBStart", prbStart, "PRBCount", nRB, ...
    "SymbolStart", symbolStart, "NumSymbols", numSymbols, ...
    "MCSIndex", mcs, "RV", rv);
[pdschIndices, info] = nrPDSCHIndices(carrier, pdsch);
nrePerPRB = localResolveSIB1DataNREPerPRB( ...
    info, nRB, pdsch.Modulation, pdsch.NumLayers, ...
    numel(pdschIndices));
xOverhead = sixgr.phy.dl.resolvePDSCHXOverhead( ...
    cfg, pdsch.SymbolAllocation);
tbs = nrTBS(pdsch.Modulation, pdsch.NumLayers, nRB, ...
    nrePerPRB, dci.TargetCodeRate, xOverhead);
if tbs < numel(sib1Bits)
    error("sixgr:phy:broadcast:SIB1AllocationTooSmall", ...
        "Configured SIB1 allocation provides TBS=%d for %d payload bits.", ...
        tbs, numel(sib1Bits));
end
targetCodeRate = dci.TargetCodeRate;
paddedBits = int8([sib1Bits(:); ...
    zeros(tbs - numel(sib1Bits), 1, "int8")]);
end

function value = localNonnegativeInteger(raw, fieldName)
value = double(raw);
if ~(isscalar(value) && isfinite(value) && value == fix(value) && ...
        value >= 0)
    error("sixgr:phy:broadcast:InvalidSIB1Allocation", ...
        "%s must be a nonnegative integer.", fieldName);
end
end

function value = localPositiveInteger(raw, fieldName)
value = localNonnegativeInteger(raw, fieldName);
if value < 1
    error("sixgr:phy:broadcast:InvalidSIB1Allocation", ...
        "%s must be a positive integer.", fieldName);
end
end

function nrePerPRB = localResolveSIB1DataNREPerPRB( ...
        pdschInfo, nPRB, modStr, nLayers, mappedDataRECount)
% Keep SIB1 allocation TBS aligned with PDSCH_Tx's actual data-RE resolver.
qm = localQm(modStr);
nrePerPRB = double(mappedDataRECount) ...
    / max(double(nPRB) * double(nLayers), 1);
if ~(isfinite(nrePerPRB) && nrePerPRB > 0 ...
        && nrePerPRB == fix(nrePerPRB))
    error("sixgr:phy:broadcast:SIB1NonUniformDataRE", ...
        "SIB1 requires an integer uniform mapped data-RE count per PRB/layer.");
end
% Retain the Toolbox G cross-check, but never use a metadata-field shape
% heuristic as the owner of the TBS resource count.
if isfield(pdschInfo, "G")
    gBits = double(pdschInfo.G);
    if isscalar(gBits) && isfinite(gBits) && gBits > 0
        expectedG = nrePerPRB * qm * double(nLayers) * double(nPRB);
        if gBits ~= expectedG
            error("sixgr:phy:broadcast:SIB1DataREGMismatch", ...
                "Toolbox G=%d differs from mapped-data exact G=%d.", ...
                gBits, expectedG);
        end
    end
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

function [pdcch, cfgSI, carrierSI, resolution, absoluteSlot] = ...
        localSIB1PDCCHConfig(carrier, cfg)
mib = sixgr.phy.broadcast.splitPDCCHConfigSIB1(localPDCCHConfigSIB1(cfg), ...
    "Source", "tx_configured_mib_pdcch_ConfigSIB1");
mib.DMRSTypeAPosition = double(sixgr.util.structGet(cfg, "phy.mib.dmrsTypeAPosition", 2));
[resolution, cfgSI] = sixgr.phy.broadcast.deriveType0PDCCHFromMIB(carrier, cfg, mib, "RNTI", 65535);
ordinal = localMonitoringOccasionOrdinal(cfg);
if ordinal > height(resolution.MonitoringOccasions)
    error("sixgr:phy:broadcast:InvalidType0MonitoringOccasion", ...
        "Type0 monitoring occasion ordinal %d exceeds the %d resolved occasions.", ...
        ordinal, height(resolution.MonitoringOccasions));
end
absoluteSlot = double( ...
    resolution.MonitoringOccasions.AbsoluteSlot(ordinal));
carrierSI = localCarrierAtAbsoluteSlot(carrier, absoluteSlot);
cfgSI = sixgr.util.structSet(cfgSI, ...
    "phy.carrier.NSlot", double(carrierSI.NSlot));
cfgSI = sixgr.util.structSet(cfgSI, ...
    "phy.carrier.NFrame", double(carrierSI.NFrame));
cfgSI = sixgr.util.structSet(cfgSI, ...
    "phy.sib1.pdcchAbsoluteSlot", absoluteSlot);
pdcch = resolution.PDCCH;
cfgSI = sixgr.util.structSet(cfgSI, "phy.sib1.resolvedCORESET0", resolution.CORESET0);
cfgSI = sixgr.util.structSet(cfgSI, "phy.sib1.resolvedSearchSpace0", resolution.SearchSpace0);
end

function cfgSI = localSanitizeSIB1PDSCHPrecoding(cfgSI, pdsch)
% SI-RNTI SIB1 is a broadcast PDSCH allocation; it must not inherit
% UE-data rank/precoder state from scenario PDSCH grants.
nLayers = max(1, round(double(pdsch.NumLayers)));
cfgSI = sixgr.util.structSet(cfgSI, "phy.pdsch.numLayers", nLayers);
cfgSI = sixgr.util.structSet(cfgSI, "phy.pdsch.nLayers", nLayers);

paths = ["phy.pdsch.precoding.matrix", "phy.pdsch.precodingMatrix", "phy.pdsch.W"];
for i = 1:numel(paths)
    cfgSI = sixgr.util.structSet(cfgSI, paths(i), []);
end
cfgSI = sixgr.util.structSet(cfgSI, "phy.pdsch.numPorts", nLayers);
cfgSI = sixgr.util.structSet(cfgSI, "phy.pdsch.nPorts", nLayers);
cfgSI = sixgr.util.structSet(cfgSI, "phy.pdsch.precoding.enabled", false);
cfgSI = sixgr.util.structSet(cfgSI, "phy.pdsch.precoding.mode", "broadcast_single_port");
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

function value = localPDCCHConfigSIB1(cfg)
configured = sixgr.util.structGet(cfg, "phy.mib.pdcchConfigSIB1", []);
if isempty(configured)
    coreset0 = double(sixgr.util.structGet(cfg, "phy.sib1.coreset0Index", 0));
    search0 = double(sixgr.util.structGet(cfg, "phy.sib1.searchSpaceZero", 0));
    configured = coreset0 * 16 + search0;
end
value = round(double(configured));
if ~(isscalar(value) && isfinite(value) && value >= 0 && value <= 255)
    error("sixgr:phy:broadcast:InvalidPDCCHConfigSIB1", ...
        "MIB pdcch-ConfigSIB1 must resolve to an integer in [0,255].");
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

function waveform = localComposeAbsoluteTimeline( ...
        ssbWaveform, siWaveform, siStartSample)
numCols = max(size(ssbWaveform, 2), size(siWaveform, 2));
ssbWaveform = localPadWaveformColumns(ssbWaveform, numCols);
siWaveform = localPadWaveformColumns(siWaveform, numCols);
siStartSample = localNonnegativeInteger( ...
    siStartSample, "SIB1 absolute start sample");
numSamples = max(size(ssbWaveform, 1), ...
    siStartSample + size(siWaveform, 1));
waveform = complex(zeros(numSamples, numCols, "like", ssbWaveform));
waveform(1:size(ssbWaveform, 1), :) = ssbWaveform;
siRows = siStartSample + (1:size(siWaveform, 1));
waveform(siRows, :) = waveform(siRows, :) + siWaveform;
end

function wave = localPadWaveformColumns(wave, numCols)
if size(wave, 2) >= numCols
    return;
end
wave(:, end+1:numCols) = 0;
end

function sampleRate = localSampleRate(carrier)
sampling = sixgr.phy.frame.OFDMSamplingResolver.resolve(carrier);
sampleRate = double(sampling.SampleRateHz);
end

function ordinal = localMonitoringOccasionOrdinal(cfg)
raw = sixgr.util.structGet(cfg, ...
    "initial_access.type0.monitoring_occasion_ordinal", ...
    sixgr.util.structGet(cfg, ...
    "phy.sib1.monitoringOccasionOrdinal", []));
if isempty(raw)
    error("sixgr:phy:broadcast:MissingType0MonitoringOccasion", ...
        "Strict SIB1 scheduling requires initial_access.type0.monitoring_occasion_ordinal.");
end
ordinal = localPositiveInteger(raw, "monitoring_occasion_ordinal");
end

function carrier = localCarrierAtAbsoluteSlot(carrier, absoluteSlot)
absoluteSlot = localNonnegativeInteger(absoluteSlot, "absoluteSlot");
slotsPerFrame = 10 * round(double(carrier.SlotsPerSubframe));
carrier.NFrame = floor(absoluteSlot / slotsPerFrame);
carrier.NSlot = mod(absoluteSlot, slotsPerFrame);
end

function startSample = localAbsoluteSlotStartSample( ...
        absoluteSlot, carrier, sampleRate)
slotsPerSubframe = round(double(carrier.SlotsPerSubframe));
if ~(isscalar(slotsPerSubframe) && isfinite(slotsPerSubframe) && ...
        slotsPerSubframe >= 1)
    error("sixgr:phy:broadcast:InvalidType0MonitoringOccasion", ...
        "Carrier SlotsPerSubframe is invalid.");
end
slotDurationSeconds = 1e-3 / slotsPerSubframe;
startSample = round(double(absoluteSlot) * ...
    slotDurationSeconds * double(sampleRate));
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
