function txBundle = PDSCHWaveformBuilder(cfg, fdraAlloc, tdraAlloc, amc, varargin)
%PDSCHWaveformBuilder Build truthful PDSCH waveform copies for one HARQ tx.

ip = inputParser;
ip.addParameter("QueueBits", cfg.QueueBits, @(x) isnumeric(x) && isscalar(x) && x >= 1);
ip.addParameter("RV", 0, @(x) isnumeric(x) && isscalar(x) && x >= 0);
ip.addParameter("TransmissionIndex", 1, @(x) isnumeric(x) && isscalar(x) && x >= 1);
ip.parse(varargin{:});
opt = ip.Results;

copies = tdraAlloc.CopyTable;

layerTrace = sixgr.pdsch.CodewordLayerMapper(cfg);
copyBundles = cell(height(copies), 1);
queueFitStatus = "";
payloadBitsOriginal = [];
transportBlockSize = NaN;
transportBlockBits = [];

for i = 1:height(copies)
    slotNumber = cfg.SlotNumber + double(copies.SlotOffset(i)) + double(cfg.TDRA.SchedulingOffsetSlots);
    symbolAllocation = [double(copies.StartSymbol(i)) + double(cfg.TDRA.SchedulingOffsetSymbols), double(copies.NumSymbols(i))];
    runtimeCfg = localBuildRuntimeCfg(cfg, fdraAlloc, symbolAllocation, slotNumber, amc);
    [carrier, ~] = sixgr.pdsch.CarrierConfig6GR(runtimeCfg);
    pdsch = localBuildPDSCHConfig(runtimeCfg, carrier, amc, fdraAlloc, symbolAllocation);
    [pdsch, amc, payloadBitsOriginal, queueFitStatus, transportBlockSize] = localFitGrantToQueue(cfg, carrier, pdsch, amc, double(opt.QueueBits));
    if isempty(transportBlockBits)
        transportBlockBits = localMakeTransportBlocks(double(transportBlockSize), payloadBitsOriginal, cfg.Seed + double(opt.TransmissionIndex));
    elseif ~isequal(double(localTransportBlockSizes(transportBlockBits)), double(transportBlockSize(:).'))
        error("sixgr:pdsch:PDSCHWaveformBuilder:RepetitionTBSMismatch", ...
            "PDSCH repetition copies must carry the same per-codeword transport block size. First copy TBS=%s, copy %d TBS=%s.", ...
            mat2str(localTransportBlockSizes(transportBlockBits)), i, mat2str(double(transportBlockSize(:).')));
    end
    tbBits = transportBlockBits;
    [tx, txInfo] = sixgr.phy.dl.PDSCH_Tx(runtimeCfg, ...
        "Carrier", carrier, ...
        "PDSCH", pdsch, ...
        "TransportBlockBits", tbBits, ...
        "TargetCodeRate", amc.TargetCodeRate, ...
        "RV", double(opt.RV));
    tx = localApplyWidebandPhaseErrors(tx, cfg, i);
    [dmrs, dmrsT] = sixgr.pdsch.PDSCHDMRS(carrier, pdsch);
    [ptrs, ptrsT] = sixgr.pdsch.PDSCHPTRS(carrier, pdsch);
    copyBundles{i} = struct( ...
        "Tx", tx, ...
        "TxInfo", txInfo, ...
        "RuntimeCfg", runtimeCfg, ...
        "Carrier", carrier, ...
        "PDSCH", pdsch, ...
        "FDRA", fdraAlloc, ...
        "TDRA", struct("SlotNumber", slotNumber, "SymbolAllocation", symbolAllocation), ...
        "DMRS", dmrs, ...
        "DMRSTable", dmrsT, ...
        "PTRS", ptrs, ...
        "PTRSTable", ptrsT, ...
        "LayerMappingTrace", layerTrace, ...
        "ScramblingMeta", sixgr.pdsch.PDSCHScrambler(runtimeCfg, carrier, pdsch), ...
        "ModulationMeta", sixgr.pdsch.PDSCHModulator(tx), ...
        "EncoderMeta", sixgr.pdsch.DLSCHEncoder(tx, txInfo), ...
        "GridMap", sixgr.pdsch.PDSCHGridMapper(tx), ...
        "QueueFitStatus", queueFitStatus, ...
        "PayloadBitsBeforePadding", double(localPayloadBitCount(payloadBitsOriginal)), ...
        "TransportBlockSize", double(transportBlockSize), ...
        "TransportBlockBits", {tbBits});
end

txBundle = struct();
txBundle.Copies = copyBundles;
txBundle.ActiveAMC = amc;
txBundle.FDRA = fdraAlloc;
txBundle.TDRA = tdraAlloc;
txBundle.LayerMappingTrace = layerTrace;
txBundle.QueueFitStatus = char(queueFitStatus);
txBundle.PayloadBitsBeforePadding = double(localPayloadBitCount(payloadBitsOriginal));
txBundle.RV = double(opt.RV);
txBundle.RepetitionMode = char(cfg.RepetitionMode);
txBundle.RepetitionCount = height(copies);
txBundle.TransportBlockSize = double(copyBundles{1}.TransportBlockSize(:).');
txBundle.TransportBlockBits = copyBundles{1}.TransportBlockBits;
end

function runtimeCfg = localBuildRuntimeCfg(cfg, fdraAlloc, symbolAllocation, slotNumber, amc)
numerology = localResolveNumerology(cfg);
runtimeCfg = struct();
runtimeCfg.CellID = double(cfg.CellID);
runtimeCfg.RNTI = double(cfg.RNTI);
runtimeCfg.NumLayers = double(cfg.NumLayers);
runtimeCfg.NumCodewords = double(localPDSCHCodewordCount(cfg.NumLayers));
runtimeCfg.Numerology = double(numerology.Mu);
runtimeCfg.NSizeGrid = double(cfg.NSizeGrid);
runtimeCfg.SlotNumber = double(slotNumber);
runtimeCfg.FrameNumber = double(cfg.FrameNumber);
runtimeCfg.DMRS = cfg.DMRS;
runtimeCfg.PTRS = cfg.PTRS;
runtimeCfg.phy = struct();
runtimeCfg.phy.fc_Hz = double(cfg.CarrierFrequencyHz);
runtimeCfg.phy.carrier = struct( ...
    "NCellID", double(cfg.CellID), ...
    "SubcarrierSpacing", double(numerology.SubcarrierSpacingKHz), ...
    "NSizeGrid", double(cfg.NSizeGrid), ...
    "NStartGrid", 0, ...
    "NSlot", double(slotNumber), ...
    "NFrame", double(cfg.FrameNumber), ...
    "CyclicPrefix", char(string(numerology.CyclicPrefix)));
runtimeCfg.phy.numerology = struct( ...
    "mu", double(numerology.Mu), ...
    "slotsPerFrame", double(numerology.SlotsPerFrame));
runtimeCfg.phy.pdsch = struct( ...
    "modulation", {localModulationForCodewords(amc.Modulation, cfg.NumLayers)}, ...
    "numLayers", double(cfg.NumLayers), ...
    "nLayers", double(cfg.NumLayers), ...
    "numCodewords", double(localPDSCHCodewordCount(cfg.NumLayers)), ...
    "RNTI", double(cfg.RNTI), ...
    "mappingType", "A", ...
    "prbSet", double(fdraAlloc.PRBSet), ...
    "symbolAllocation", double(symbolAllocation), ...
    "codeRate", double(amc.TargetCodeRate), ...
    "mcsTable", char(amc.MCSTable), ...
    "rv", 0, ...
    "xOverhead", 0, ...
    "enablePTRS", logical(cfg.PTRS.PTRSEnabled), ...
    "dmrs", struct( ...
        "configurationType", double(cfg.DMRS.ConfigType), ...
        "additionalPosition", double(cfg.DMRS.AdditionalPosition), ...
        "numCDMGroupsWithoutData", double(cfg.DMRS.CDMGroupsWithoutData), ...
        "nPorts", double(cfg.DMRS.NumPorts), ...
        "portSet", double(cfg.DMRS.PortSet)));
runtimeCfg.phy.impairments = struct("cfoHz", 0, "timingOffsetSamples", 0);
profile = upper(strtrim(char(string(cfg.ChannelModel))));
tdlProfile = "";
cdlProfile = "";
if startsWith(profile, "TDL")
    tdlProfile = profile;
elseif startsWith(profile, "CDL")
    cdlProfile = profile;
end
runtimeCfg.channel = struct( ...
    "model", char(cfg.ChannelModel), ...
    "tdlProfile", char(tdlProfile), ...
    "cdlProfile", char(cdlProfile), ...
    "fading", struct("delaySpread_s", double(cfg.DelaySpread_s)), ...
    "doppler_Hz", double(cfg.DopplerHz), ...
    "snr_dB", double(cfg.SNRdB), ...
    "nTxAnt", double(cfg.NTx), ...
    "nRxAnt", double(cfg.NRx));
runtimeCfg.run = struct("seed", double(cfg.Seed), "strictMode", true, "useMex", false, "useParallel", false);
end

function numerology = localResolveNumerology(cfg)
base = sixgr.phy.frame.AbsoluteTime.resolveNumerology(double(cfg.Numerology));
cp = string(sixgr.util.structGet(cfg, "CyclicPrefix", "normal"));
numerology = sixgr.phy.frame.NumerologyCatalog.resolve( ...
    base.SCSKHz, cp, "generic_waveform_test", "");
end

function pdsch = localBuildPDSCHConfig(cfg, carrier, amc, fdraAlloc, symbolAllocation)
numLayers = double(sixgr.util.structGet(cfg, "NumLayers", sixgr.util.structGet(cfg, "phy.pdsch.nLayers", 1)));
rnti = double(sixgr.util.structGet(cfg, "RNTI", sixgr.util.structGet(cfg, "phy.pdsch.RNTI", 1)));
cellId = double(sixgr.util.structGet(cfg, "CellID", sixgr.util.structGet(cfg, "phy.carrier.NCellID", 1)));
dmrsCfg = sixgr.util.structGet(cfg, "DMRS", struct());
ptrsCfg = sixgr.util.structGet(cfg, "PTRS", struct());
[~, ~, pdsch] = sixgr.phy.grid.allocREsPDSCH(carrier, cfg, ...
    "PRBSet", double(fdraAlloc.PRBSet), ...
    "SymbolAllocation", double(symbolAllocation), ...
    "Modulation", localModulationForCodewords(amc.Modulation, numLayers), ...
    "NumLayers", numLayers, ...
    "RNTI", rnti);
pdsch.Modulation = localModulationForCodewords(amc.Modulation, numLayers);
pdsch.NumLayers = numLayers;
pdsch.PRBSet = double(fdraAlloc.PRBSet(:).');
pdsch.SymbolAllocation = double(symbolAllocation);
pdsch.RNTI = rnti;
try
    pdsch.MappingType = "A";
catch
end
try
    pdsch.DMRS.DMRSConfigurationType = double(sixgr.util.structGet(dmrsCfg, "ConfigType", 1));
catch
end
try
    pdsch.DMRS.DMRSTypeAPosition = 2;
catch
end
try
    pdsch.DMRS.DMRSAdditionalPosition = double(sixgr.util.structGet(dmrsCfg, "AdditionalPosition", 1));
catch
end
try
    pdsch.DMRS.DMRSPortSet = double(sixgr.util.structGet(dmrsCfg, "PortSet", 0:(numLayers - 1)));
catch
end
try
    pdsch.DMRS.NumCDMGroupsWithoutData = double(sixgr.util.structGet(dmrsCfg, "CDMGroupsWithoutData", 1));
catch
end
try
    pdsch.NID = cellId;
catch
end
try
    pdsch.EnablePTRS = logical(sixgr.util.structGet(ptrsCfg, "PTRSEnabled", false));
catch
end
if logical(sixgr.util.structGet(ptrsCfg, "PTRSEnabled", false))
    try
        pdsch.PTRS.TimeDensity = double(sixgr.util.structGet(ptrsCfg, "TimeDensity", 2));
        pdsch.PTRS.FrequencyDensity = double(sixgr.util.structGet(ptrsCfg, "FrequencyDensity", 2));
        pdsch.PTRS.REOffset = char(string(sixgr.util.structGet(ptrsCfg, "REOffset", "00")));
        pdsch.PTRS.PTRSPortSet = double(sixgr.util.structGet(dmrsCfg, "PortSet", 0));
    catch
    end
end
end

function [pdsch, amc, payloadBits, status, tbs] = localFitGrantToQueue(cfg, carrier, pdsch, amc, queueBits)
payloadBits = max(1, round(double(queueBits)));
status = "queue_fits_initial_grant";
tbs = NaN;
attempts = 0;
while attempts < 256
    tbs = sixgr.pdsch.TBSCalculator(carrier, pdsch, amc.TargetCodeRate, 0);
    if localTotalBits(tbs) <= payloadBits
        return;
    end
    attempts = attempts + 1;
    if amc.MCSIndex > 0
        amc = localAMCFromIndex(cfg, amc.MCSIndex - 1);
        pdsch.Modulation = localModulationForCodewords(amc.Modulation, pdsch.NumLayers);
        status = "queue_limited_mcs_backoff_before_tx";
        continue;
    end
    if numel(pdsch.PRBSet) > 1
        pdsch.PRBSet = pdsch.PRBSet(1:end-1);
        status = "queue_limited_prb_backoff_before_tx";
        continue;
    end
    status = "queue_smaller_than_minimum_tbs_padding_applied_before_tx";
    return;
end
error("sixgr:pdsch:PDSCHWaveformBuilder:QueueFitFailed", ...
    "Unable to fit the scheduled PDSCH grant to the queue size.");
end

function amc = localAMCFromIndex(cfg, mcsIndex)
amc = sixgr.pdsch.AMCSelector(cfg, "EstimatedSNR_dB", cfg.SNRdB);
amc.MCSIndex = double(mcsIndex);
profile = sixgr.link.resolveMCSProfile(amc.MCSTable, amc.MCSIndex);
amc.Modulation = char(profile.Modulation);
amc.TargetCodeRate = double(profile.TargetCodeRate);
amc.SpectralEfficiency = double(profile.SpectralEfficiency);
end

function bits = localMakeTransportBlocks(tbsBits, payloadBits, seed)
rng(double(seed), "twister");
payloadBitCount = localPayloadBitCount(payloadBits);
tbsBits = double(tbsBits(:).');
if numel(tbsBits) > 1
    totalBits = sum(tbsBits);
    if payloadBitCount <= 0
        payloadVec = int8(randi([0 1], totalBits, 1));
    elseif isnumeric(payloadBits) && isscalar(payloadBits)
        payloadVec = int8(randi([0 1], payloadBitCount, 1));
    else
        payloadVec = int8(payloadBits(:) ~= 0);
    end
    bits = cell(1, numel(tbsBits));
    offset = 0;
    for c = 1:numel(tbsBits)
        n = round(tbsBits(c));
        bits{c} = int8(zeros(n, 1));
        take = min(n, max(0, numel(payloadVec) - offset));
        if take > 0
            bits{c}(1:take) = payloadVec(offset + (1:take));
        end
        if take < n
            bits{c}(take+1:end) = int8(randi([0 1], n - take, 1));
        end
        offset = offset + take;
    end
    return;
end
tbsBits = tbsBits(1);
if payloadBitCount <= 0
    payloadBits = int8(randi([0 1], tbsBits, 1));
elseif isnumeric(payloadBits) && isscalar(payloadBits)
    payloadBits = int8(randi([0 1], payloadBitCount, 1));
else
    payloadBits = int8(payloadBits(:) ~= 0);
end
bits = int8(zeros(tbsBits, 1));
L = min(tbsBits, numel(payloadBits));
if L > 0
    bits(1:L) = payloadBits(1:L);
end
if L < tbsBits
    bits(L+1:end) = int8(randi([0 1], tbsBits - L, 1));
end
end

function sizes = localTransportBlockSizes(bits)
if iscell(bits)
    sizes = double(cellfun(@numel, bits));
else
    sizes = double(numel(bits));
end
sizes = sizes(:).';
end

function total = localTotalBits(bits)
total = sum(double(bits(:)));
end

function n = localPDSCHCodewordCount(numLayers)
n = 1 + double(round(double(numLayers)) > 4);
end

function modulation = localModulationForCodewords(modulationIn, numLayers)
nCodewords = localPDSCHCodewordCount(numLayers);
tokens = string(modulationIn);
tokens = tokens(:).';
tokens = tokens(strlength(strtrim(tokens)) > 0);
if isempty(tokens)
    tokens = "QPSK";
end
if numel(tokens) == 1 && nCodewords > 1
    tokens = repmat(tokens, 1, nCodewords);
elseif numel(tokens) < nCodewords
    tokens(end+1:nCodewords) = tokens(end);
elseif numel(tokens) > nCodewords
    tokens = tokens(1:nCodewords);
end
if nCodewords == 1
    modulation = char(tokens(1));
else
    modulation = cellstr(tokens);
end
end

function tx = localApplyWidebandPhaseErrors(tx, cfg, copyIndex)
if ~logical(cfg.EnableWidebandUncalibratedPhaseErrors)
    return;
end
wave = sixgr.util.structGet(tx, "Waveform", []);
if isempty(wave) || size(wave, 2) <= 1
    return;
end
rng(double(cfg.Seed + 100 * copyIndex), "twister");
phaseOffsets = zeros(1, size(wave, 2));
phaseOffsets(2:end) = 2 * pi * rand(1, size(wave, 2) - 1);
tx.Waveform = wave .* exp(1j * phaseOffsets);
end

function count = localPayloadBitCount(payloadBits)
if isempty(payloadBits)
    count = 0;
elseif isnumeric(payloadBits) && isscalar(payloadBits)
    count = max(0, round(double(payloadBits)));
else
    count = numel(payloadBits);
end
end
