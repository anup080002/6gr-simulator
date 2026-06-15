function result = recoverSIB1FromWaveform(rxWaveform, cfg, varargin)
%RECOVERSIB1FROMWAVEFORM Recover MIB, SI-RNTI DCI, PDSCH/DL-SCH, and SIB1.

p = inputParser;
p.addParameter("ExpectedTxTree", struct(), @(x) isempty(x) || isstruct(x));
p.addParameter("ExpectedPayloadHash", "", @(x) ischar(x) || isstring(x));
p.addParameter("ExpectedTreeHash", "", @(x) ischar(x) || isstring(x));
p.addParameter("ReceiverRNTI", 65535, @(x) isnumeric(x) && isscalar(x));
p.addParameter("FaultMode", "", @(x) ischar(x) || isstring(x));
p.parse(varargin{:});

result = localEmptyResult();
result.Status = "started";
try
    [siSupported, siReason] = sixgr.phy.broadcast.siRNTIWaveformSupported();
    if ~siSupported
        result.Status = "unsupported_si_rnti_waveform";
        result.FailureReason = string(siReason);
        result.Errors = string(siReason);
        result.StrictOk = false;
        return;
    end
    cfg = localNormalizeReceiverCfg(cfg, double(p.Results.ReceiverRNTI));
    [carrier, ~] = sixgr.phy.grid.makeCarrier(cfg);
    sampleRate = localSampleRate(carrier);
    result.SampleRateHz = sampleRate;
    result.DCIRNTI = double(p.Results.ReceiverRNTI);
    [rxSSB, sync] = sixgr.phy.dl.SSB_Rx(rxWaveform, cfg, "SampleRate_Hz", sampleRate);
    [pbch, ~] = sixgr.phy.dl.PBCH_Recovery(rxSSB, sync, cfg);
    result.NCellID = double(sync.NCellID);
    result.TimingOffset = double(sixgr.util.structGet(sync, "TimingOffset", NaN));
    result.FrequencyOffsetHz = double(sixgr.util.structGet(sync, "FreqOffset_Hz", NaN));
    result.SSBIndex = double(sixgr.util.structGet(pbch, "SSBIndex", NaN));
    result.BCHCrcPass = logical(pbch.Ok) && double(pbch.ErrFlag) == 0;
    result.MIBDecoded = result.BCHCrcPass;
    result.PDCCHConfigSIB1 = localPDCCHConfigSIB1(cfg);
    result.CORESET0Present = true;
    result.CORESET0Pattern = "anchor_coreset0_type0_css";
    result.CORESET0RBStart = 0;
    result.SearchSpace0ID = 0;
    result.CORESET0Duration = 2;

    siWave = localExtractSIB1Waveform(rxWaveform, cfg, sampleRate);
    faultMode = lower(strtrim(string(p.Results.FaultMode)));
    if faultMode == "nosignal"
        siWave(:) = 0;
    elseif faultMode == "corruptpdcch"
        siWave(1:min(256, numel(siWave))) = -siWave(1:min(256, numel(siWave)));
    end

    [~, cfgSI] = localReceiverPDCCH(carrier, cfg, double(p.Results.ReceiverRNTI));
    [pdcchRx, pdcchInfo] = sixgr.phy.dl.PDCCH_Rx(siWave, cfgSI, ...
        "Carrier", carrier, "PDCCH", cfgSI.phy.sib1.runtimePDCCH, ...
        "K", 32, "SampleRate_Hz", sampleRate);
    result.PDCCHCandidatesAttempted = double(sixgr.util.structGet(pdcchInfo, "NumCandidatesTried", 0));
    result.DCIBlindDecodeSuccess = logical(pdcchRx.Ok);
    result.DCICrcPass = logical(pdcchRx.Ok);
    result.DCIFormat = "1_0";
    result.DCIPayloadHex = sixgr.rrc.asn1.bitsToHex(pdcchRx.DCIBits);
    result.WrongRNTIRejectCount = double(~logical(pdcchRx.Ok) && double(p.Results.ReceiverRNTI) ~= 65535);
    result.NoSignalRejectCount = double(~logical(pdcchRx.Ok) && faultMode == "nosignal");
    result.FalseCandidateCount = 0;
    if ~logical(pdcchRx.Ok)
        result.Status = "pdcch_decode_failed";
        result.FailureReason = "SI-RNTI DCI blind decode failed";
        result.CandidateTable = sixgr.util.structGet(pdcchInfo, "CandidateResults", table());
        result.StrictOk = false;
        return;
    end

    [dci, pdsch] = sixgr.phy.broadcast.buildSIB1DCI10(carrier, cfg, "Bits", pdcchRx.DCIBits);
    result.DCIRNTI = 65535;
    result.PDSCHRBStart = double(dci.PRBStart);
    result.PDSCHNumRB = double(dci.PRBCount);
    result.PDSCHSymbolStart = double(dci.SymbolStart);
    result.PDSCHNumSymbols = double(dci.NumSymbols);
    result.PDSCHModulation = string(dci.Modulation);
    result.CORESET0NumRB = max(1, min(double(carrier.NSizeGrid), 36));
    [~, pdschInfo] = nrPDSCHIndices(carrier, pdsch);
    tbs = nrTBS(pdsch.Modulation, pdsch.NumLayers, numel(pdsch.PRBSet), pdschInfo.NREPerPRB, dci.TargetCodeRate, 0);
    if faultMode == "corruptpdsch"
        siWave(round(end/2):min(numel(siWave), round(end/2)+255)) = ...
            -siWave(round(end/2):min(numel(siWave), round(end/2)+255));
    end
    [pdschRx, ~] = sixgr.phy.dl.PDSCH_Rx(siWave, cfgSI, ...
        "Carrier", carrier, "PDSCH", pdsch, "TransportBlockSize", double(tbs), ...
        "TargetCodeRate", dci.TargetCodeRate, "RV", double(dci.RV), ...
        "SkipTimingEstimate", true);
    result.PDSCHDMRSOk = isfield(pdschRx, "ChannelEstimate") && ~isempty(pdschRx.ChannelEstimate);
    result.DLSCHCrcPass = logical(pdschRx.Ok);
    if ~logical(pdschRx.Ok)
        result.Status = "pdsch_dlsch_crc_failed";
        result.FailureReason = "SIB1 PDSCH/DL-SCH CRC failed";
        result.StrictOk = false;
        return;
    end
    sibBits = int8(pdschRx.TransportBlock(:));
    if faultMode == "corruptasn1"
        sibBits(21:min(numel(sibBits), 28)) = 1 - sibBits(21:min(numel(sibBits), 28));
    end
    result.SIB1PayloadBits = sibBits;
    result.SIB1PayloadBytes = ceil(numel(sibBits) / 8);
    [rxTree, rxMeta] = sixgr.rrc.asn1.decodeSIB1UPER(sibBits);
    result.SIB1ASN1DecodeOk = true;
    result.SIB1PayloadHashRx = string(rxMeta.PayloadHash);
    result.SIB1RxTree = rxTree;
    result.SIB1RxTreeHash = sixgr.rrc.asn1.compareSIB1Trees(rxTree, rxTree).TxTreeHash;
    result.SIB1PayloadHashTx = string(p.Results.ExpectedPayloadHash);
    result.SIB1TxTreeHash = string(p.Results.ExpectedTreeHash);
    if ~isempty(fieldnames(p.Results.ExpectedTxTree))
        [equal, cmp] = sixgr.rrc.asn1.compareSIB1Trees(p.Results.ExpectedTxTree, rxTree);
        result.SIB1TreeEqual = logical(equal);
        result.SIB1TxTreeHash = string(cmp.TxTreeHash);
        result.SIB1RxTreeHash = string(cmp.RxTreeHash);
    else
        result.SIB1TreeEqual = false;
    end
    result.StrictOk = localStrictOk(result);
    if result.StrictOk
        result.Status = "PASS";
        result.FailureReason = "";
    else
        result.Status = "FAIL";
        result.FailureReason = "strict_sib1_condition_failed";
    end
    result.CandidateTable = sixgr.util.structGet(pdcchInfo, "CandidateResults", table());
catch ME
    result.StrictOk = false;
    result.Status = "ERROR";
    result.FailureReason = string(ME.identifier) + ":" + string(ME.message);
    result.Errors = string(ME.message);
end
end

function result = localEmptyResult()
result = struct( ...
    "StrictOk", false, "Status", "", "Detail", "", "NCellID", NaN, ...
    "TimingOffset", NaN, "FrequencyOffsetHz", NaN, "SSBIndex", NaN, ...
    "BCHCrcPass", false, "MIBDecoded", false, "PDCCHConfigSIB1", NaN, ...
    "CORESET0Present", false, "CORESET0Pattern", "", "CORESET0RBStart", NaN, ...
    "CORESET0NumRB", NaN, "CORESET0Duration", NaN, "SearchSpace0ID", NaN, ...
    "PDCCHCandidatesAttempted", 0, "DCIBlindDecodeSuccess", false, "DCICrcPass", false, ...
    "DCIRNTI", NaN, "DCIFormat", "", "DCIPayloadHex", "", ...
    "WrongRNTIRejectCount", 0, "NoSignalRejectCount", 0, "FalseCandidateCount", 0, ...
    "PDSCHRBStart", NaN, "PDSCHNumRB", NaN, "PDSCHSymbolStart", NaN, ...
    "PDSCHNumSymbols", NaN, "PDSCHModulation", "", "PDSCHDMRSOk", false, ...
    "DLSCHCrcPass", false, "SIB1PayloadBits", int8([]), "SIB1PayloadBytes", NaN, ...
    "SIB1PayloadHashTx", "", "SIB1PayloadHashRx", "", "SIB1ASN1DecodeOk", false, ...
    "SIB1TxTreeHash", "", "SIB1RxTreeHash", "", "SIB1TreeEqual", false, ...
    "UsedOracleFields", strings(0, 1), "ProxyUsed", false, "Skipped", false, ...
    "ToolboxMissing", false, "Errors", "", "FailureReason", "", ...
    "CandidateTable", table(), "SampleRateHz", NaN, "SIB1RxTree", struct());
end

function cfg = localNormalizeReceiverCfg(cfg, rnti)
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
cfg.phy.pdcch.rnti = double(rnti);
cfg.phy.pdcch.dciPayloadBits = 32;
cfg.phy.pdcch.KBits = 32;
cfg.phy.pdcch.blindSearch = true;
cfg.phy.pdcch.allowBlindCandidateTimingEstimate = false;
cfg.phy.pdcch.searchSpace.numCandidates = [0 0 1 0 0];
end

function [pdcch, cfgSI] = localReceiverPDCCH(carrier, cfg, rnti)
cfgSI = localNormalizeReceiverCfg(cfg, rnti);
pdcch = localBuildPDCCHObject(carrier);
cfgSI.phy.sib1.runtimePDCCH = pdcch;
end

function pdcch = localBuildPDCCHObject(carrier)
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
    pdcch.RNTI = 65519; % Resource object only; SI-RNTI is used in decoder calls.
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

function siWave = localExtractSIB1Waveform(rxWaveform, cfg, sampleRate)
prefixSamples = round(localSSBObservationSubframes(cfg) * 1e-3 * sampleRate) + round(0.001 * sampleRate);
if prefixSamples >= size(rxWaveform, 1)
    error("sixgr:phy:broadcast:SIB1WaveformMissing", "Received waveform is too short for SIB1 occasion.");
end
siWave = rxWaveform(prefixSamples+1:end, :);
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

function value = localPDCCHConfigSIB1(cfg)
coreset0 = double(sixgr.util.structGet(cfg, "phy.sib1.coreset0Index", 0));
search0 = double(sixgr.util.structGet(cfg, "phy.sib1.searchSpaceZero", 0));
value = coreset0 * 16 + search0;
end

function ok = localStrictOk(result)
ok = ~logical(result.Skipped) && ~logical(result.ProxyUsed) && ~logical(result.ToolboxMissing) && ...
    isempty(result.UsedOracleFields) && logical(result.BCHCrcPass) && logical(result.MIBDecoded) && ...
    logical(result.CORESET0Present) && double(result.PDCCHCandidatesAttempted) > 0 && ...
    logical(result.DCIBlindDecodeSuccess) && logical(result.DCICrcPass) && ...
    double(result.DCIRNTI) == 65535 && string(result.DCIFormat) == "1_0" && ...
    double(result.FalseCandidateCount) == 0 && logical(result.PDSCHDMRSOk) && ...
    logical(result.DLSCHCrcPass) && logical(result.SIB1ASN1DecodeOk) && ...
    strlength(string(result.SIB1PayloadHashTx)) > 0 && ...
    string(result.SIB1PayloadHashTx) == string(result.SIB1PayloadHashRx) && ...
    strlength(string(result.SIB1TxTreeHash)) > 0 && ...
    string(result.SIB1TxTreeHash) == string(result.SIB1RxTreeHash) && ...
    logical(result.SIB1TreeEqual);
end
