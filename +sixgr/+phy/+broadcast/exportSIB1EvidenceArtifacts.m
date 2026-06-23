function artifacts = exportSIB1EvidenceArtifacts(runFolder, tx, result, varargin)
%EXPORTSIB1EVIDENCEARTIFACTS Persist AUD-015 SIB1 evidence artifacts.

p = inputParser;
p.addParameter("NegativeResults", struct([]), @(x) isempty(x) || isstruct(x));
p.parse(varargin{:});

layout = sixgr.report.resultLayout(runFolder);
sixgr.util.ensureFolder(layout.ControlCSVDir);
sixgr.util.ensureFolder(layout.AirInterfaceCSVDir);
sixgr.util.ensureFolder(layout.ReportCSVDir);
jsonDir = fullfile(runFolder, "reports", "json");
binDir = fullfile(runFolder, "reports", "binary");
textDir = fullfile(runFolder, "reports", "text");
figDir = fullfile(runFolder, "reports", "figures");
for d = string([jsonDir, binDir, textDir, figDir])
    sixgr.util.ensureFolder(d);
end

runId = string(sixgr.util.structGet(tx, "RunId", "sib1_strict_mini_anchor"));
scenarioName = "lls_sib1_strict_mini_anchor";
trialT = table( ...
    runId, scenarioName, double(result.NCellID), 0, 0, double(result.SampleRateHz), ...
    double(sixgr.util.structGet(tx, "CarrierFrequencyHz", 4e9)), ...
    double(localGetStructOrObjectField(sixgr.util.structGet(tx, "Carrier", struct()), "SubcarrierSpacing", NaN)), "Case B", ...
    double(result.SSBIndex), double(result.TimingOffset), double(result.FrequencyOffsetHz), ...
    logical(result.BCHCrcPass), logical(result.MIBDecoded), double(result.PDCCHConfigSIB1), ...
    logical(result.CORESET0Present), double(result.CORESET0RBStart), double(result.CORESET0NumRB), ...
    double(result.CORESET0Duration), double(result.SearchSpace0ID), ...
    double(result.PDCCHCandidatesAttempted), logical(result.DCIBlindDecodeSuccess), ...
    logical(result.DCICrcPass), double(result.DCIRNTI), string(result.DCIFormat), ...
    string(result.DCIPayloadHex), double(result.WrongRNTIRejectCount), ...
    double(result.NoSignalRejectCount), double(result.FalseCandidateCount), ...
    double(result.PDSCHRBStart), double(result.PDSCHNumRB), double(result.PDSCHSymbolStart), ...
    double(result.PDSCHNumSymbols), string(result.PDSCHModulation), logical(result.PDSCHDMRSOk), ...
    logical(result.DLSCHCrcPass), double(numel(result.SIB1PayloadBits)), ...
    string(result.SIB1PayloadHashTx), string(result.SIB1PayloadHashRx), ...
    logical(result.SIB1ASN1DecodeOk), string(result.SIB1TxTreeHash), string(result.SIB1RxTreeHash), ...
    logical(result.SIB1TreeEqual), logical(result.ProxyUsed), logical(result.Skipped), ...
    string(strjoin(string(result.UsedOracleFields), "|")), logical(result.StrictOk), ...
    string(result.Status), string(result.FailureReason), ...
    'VariableNames', {'RunId','ScenarioName','CellId','Slot','Frame','SampleRateHz', ...
    'CarrierFrequencyHz','SCSCommonKHz','SSBPattern','SSBIndex','TimingOffsetSamples', ...
    'FrequencyOffsetHz','BCHCrcPass','MIBDecoded','PDCCHConfigSIB1','CORESET0Present', ...
    'CORESET0RBStart','CORESET0NumRB','CORESET0DurationSymbols','SearchSpace0ID', ...
    'PDCCHCandidatesAttempted','DCIBlindDecodeSuccess','DCICrcPass','DCIRNTI','DCIFormat', ...
    'DCIPayloadHex','WrongRNTIRejectCount','NoSignalRejectCount','FalseCandidateCount', ...
    'PDSCHRBStart','PDSCHNumRB','PDSCHSymbolStart','PDSCHNumSymbols','PDSCHModulation', ...
    'PDSCHDMRSOk','DLSCHCrcPass','SIB1PayloadNumBits','SIB1PayloadHashTx', ...
    'SIB1PayloadHashRx','SIB1ASN1DecodeOk','SIB1TxTreeHash','SIB1RxTreeHash', ...
    'SIB1TreeEqual','ProxyUsed','Skipped','UsedOracleFields','StrictOk','Status','FailureReason'});

candidateT = localCandidateTable(runId, result);
negativeT = localNegativeTable(runId, p.Results.NegativeResults);
roundtripT = localRoundtripTable(runId, tx.TxTree, result.SIB1RxTree, logical(result.SIB1TreeEqual));
traceT = localWaveformDecodeTraceTable(runId, result);
summaryT = table(runId, scenarioName, "AUD-015", logical(result.StrictOk), ...
    string(result.Status), string(result.FailureReason), string(result.SIB1PayloadHashTx), ...
    string(result.SIB1PayloadHashRx), string(result.SIB1TxTreeHash), string(result.SIB1RxTreeHash), ...
    logical(result.SIB1TreeEqual), "sixgr_sib1_anchor_profile_v1", ...
    'VariableNames', {'RunId','ScenarioName','IssueId','StrictOk','Status','FailureReason', ...
    'TxPayloadHash','RxPayloadHash','TxTreeHash','RxTreeHash','TreeEqual','SupportedProfile'});

paths = struct();
paths.RecoveryTrialsCSV = fullfile(layout.ControlCSVDir, "sib1_recovery_trials.csv");
paths.PDCCHCandidatesCSV = fullfile(layout.ControlCSVDir, "sib1_pdcch_candidates.csv");
paths.NegativeTrialsCSV = fullfile(layout.ControlCSVDir, "sib1_negative_trials.csv");
paths.ASN1RoundtripCSV = fullfile(layout.ControlCSVDir, "sib1_asn1_roundtrip.csv");
paths.WaveformDecodeTraceCSV = fullfile(layout.ControlCSVDir, "sib1_waveform_decode_trace.csv");
paths.ControlConformanceSummaryCSV = fullfile(layout.ControlCSVDir, "sib1_conformance_summary.csv");
paths.AirInterfaceCSV = fullfile(layout.AirInterfaceCSVDir, "pbch_mib_sib1_trials.csv");
paths.ConformanceSummaryCSV = fullfile(layout.ReportCSVDir, "sib1_conformance_summary.csv");
sixgr.util.csvWriteTable(paths.RecoveryTrialsCSV, trialT);
sixgr.util.csvWriteTable(paths.PDCCHCandidatesCSV, candidateT);
sixgr.util.csvWriteTable(paths.NegativeTrialsCSV, negativeT);
sixgr.util.csvWriteTable(paths.ASN1RoundtripCSV, roundtripT);
sixgr.util.csvWriteTable(paths.WaveformDecodeTraceCSV, traceT);
sixgr.util.csvWriteTable(paths.ControlConformanceSummaryCSV, summaryT);
sixgr.util.csvWriteTable(paths.AirInterfaceCSV, trialT);
sixgr.util.csvWriteTable(paths.ConformanceSummaryCSV, summaryT);

paths.TxTreeJSON = fullfile(jsonDir, "sib1_tx_tree.json");
paths.RxTreeJSON = fullfile(jsonDir, "sib1_rx_tree.json");
paths.RecoverySummaryJSON = fullfile(jsonDir, "sib1_recovery_summary.json");
paths.DCIDecodedJSON = fullfile(jsonDir, "sib1_dci_decoded.json");
paths.CORESET0JSON = fullfile(jsonDir, "sib1_coreset0_searchspace.json");
sixgr.util.jsonWrite(paths.TxTreeJSON, tx.TxTree);
sixgr.util.jsonWrite(paths.RxTreeJSON, result.SIB1RxTree);
sixgr.util.jsonWrite(paths.RecoverySummaryJSON, result);
sixgr.util.jsonWrite(paths.DCIDecodedJSON, tx.DCI);
sixgr.util.jsonWrite(paths.CORESET0JSON, struct("CORESET0", tx.CORESET0, "SearchSpace0", tx.SearchSpace0));

paths.TxPayloadBIN = fullfile(binDir, "sib1_tx_payload.bin");
paths.RxPayloadBIN = fullfile(binDir, "sib1_rx_payload.bin");
localWriteBytes(paths.TxPayloadBIN, tx.SIB1Bits);
localWriteBytes(paths.RxPayloadBIN, result.SIB1PayloadBits);
paths.TxPayloadHex = fullfile(textDir, "sib1_tx_payload.hex.txt");
paths.RxPayloadHex = fullfile(textDir, "sib1_rx_payload.hex.txt");
localWriteText(paths.TxPayloadHex, string(tx.SIB1PayloadHex));
localWriteText(paths.RxPayloadHex, sixgr.rrc.asn1.bitsToHex(result.SIB1PayloadBits));

paths.CORESET0GridPNG = fullfile(figDir, "sib1_coreset0_resource_grid.png");
paths.PDCCHMetricPNG = fullfile(figDir, "sib1_pdcch_candidate_metrics.png");
paths.PDSCHGridPNG = fullfile(figDir, "sib1_pdsch_resource_grid.png");
paths.PDSCHConstellationPNG = fullfile(figDir, "sib1_pdsch_constellation.png");
paths.DecodeFlowSVG = fullfile(figDir, "sib1_decode_flow.svg");
localWriteGridFigure(paths.CORESET0GridPNG, tx.SIB1Grid, "SIB1 CORESET0/PDSCH resource grid");
localWriteCandidateFigure(paths.PDCCHMetricPNG, candidateT);
localWriteGridFigure(paths.PDSCHGridPNG, tx.SIB1Grid, "SIB1 PDSCH resource grid");
localWriteGridFigure(paths.PDSCHConstellationPNG, tx.SIB1Grid, "SIB1 equalized constellation lineage grid");
localWriteSVG(paths.DecodeFlowSVG, logical(result.StrictOk));

artifacts = paths;
artifacts.RowCounts = struct("Recovery", height(trialT), "Candidates", height(candidateT), ...
    "Negative", height(negativeT), "Roundtrip", height(roundtripT), ...
    "WaveformDecodeTrace", height(traceT), "Summary", height(summaryT));
end

function T = localWaveformDecodeTraceTable(runId, result)
stages = [
    "SSB_PSS_SSS_CELL_SEARCH"
    "PBCH_BCH_MIB_RECOVERY"
    "CORESET0_SEARCHSPACE0_RESOLUTION"
    "SI_RNTI_DCI_1_0_BLIND_DECODE"
    "SIB1_PDSCH_DMRS_CHANNEL_ESTIMATION"
    "SIB1_PDSCH_EQUALIZATION"
    "SIB1_DLSCH_CRC"
    "SIB1_ASN1_DECODE"];
passVals = [
    logical(isfinite(double(sixgr.util.structGet(result, "NCellID", NaN))))
    logical(sixgr.util.structGet(result, "BCHCrcPass", false))
    logical(sixgr.util.structGet(result, "CORESET0Present", false))
    logical(sixgr.util.structGet(result, "DCIBlindDecodeSuccess", false)) && logical(sixgr.util.structGet(result, "DCICrcPass", false))
    logical(sixgr.util.structGet(result, "SIB1PDSCHChannelEstimateAvailable", false))
    logical(sixgr.util.structGet(result, "SIB1PDSCHEqualizationAvailable", false))
    logical(sixgr.util.structGet(result, "DLSCHCrcPass", false))
    logical(sixgr.util.structGet(result, "SIB1ASN1DecodeOk", false)) && logical(sixgr.util.structGet(result, "SIB1TreeEqual", false))];
evidenceFields = [
    "NCellID,SSBIndex,TimingOffsetSamples,FrequencyOffsetHz"
    "BCHCrcPass,MIBDecoded,PDCCHConfigSIB1"
    "CORESET0RBStart,CORESET0NumRB,CORESET0DurationSymbols,SearchSpace0ID"
    "PDCCHCandidatesAttempted,DCICrcPass,DCIRNTI,DCIFormat,DCIPayloadHex"
    "SIB1PDSCHReceiverHestSINR_dB,SIB1PDSCHReceiverHestSINRSource"
    "PDSCHModulation,PDSCHRBStart,PDSCHNumRB,PDSCHSymbolStart,PDSCHNumSymbols"
    "DLSCHCrcPass,SIB1PayloadNumBits,SIB1PayloadHashRx"
    "SIB1ASN1DecodeOk,SIB1RxTreeHash,SIB1TreeEqual"];
failure = string(sixgr.util.structGet(result, "FailureReason", ""));
usedOracle = string(strjoin(string(sixgr.util.structGet(result, "UsedOracleFields", strings(0, 1))), "|"));
n = numel(stages);
T = table(repmat(runId, n, 1), (1:n).', stages(:), evidenceFields(:), ...
    passVals(:), repmat(usedOracle, n, 1), repmat(failure, n, 1), ...
    repmat("sixgr.phy.broadcast.recoverSIB1FromWaveform", n, 1), ...
    'VariableNames', {'RunId','StageOrder','StageName','EvidenceFields', ...
    'StagePass','UsedOracleFields','FailureReason','ImplementationPath'});
end

function T = localCandidateTable(runId, result)
src = result.CandidateTable;
if istable(src) && ~isempty(src)
    n = height(src);
    T = table(repmat(runId, n, 1), (1:n).', nan(n,1), nan(n,1), ...
        repmat("Type0-PDCCH-CSS", n, 1), repmat(double(result.DCIRNTI), n, 1), ...
        repmat(65535, n, 1), localColumnLogical(src, "DecodeOK", false), ...
        repmat(string(result.DCIFormat), n, 1), localColumnDouble(src, "ReceiverHestSINR_dB", NaN), ...
        repmat("", n, 1), localColumnLogical(src, "DecodeOK", false), ...
        'VariableNames', {'RunId','CandidateIndex','AggregationLevel','CCEIndex', ...
        'SearchSpaceType','RNTIAttempted','ExpectedRNTI','CrcPass','DciFormatDecoded', ...
        'Metric','RejectedReason','IsSelectedCandidate'});
else
    T = table(runId, 1, NaN, NaN, "Type0-PDCCH-CSS", double(result.DCIRNTI), 65535, ...
        logical(result.DCICrcPass), string(result.DCIFormat), NaN, string(result.FailureReason), ...
        logical(result.DCICrcPass), ...
        'VariableNames', {'RunId','CandidateIndex','AggregationLevel','CCEIndex', ...
        'SearchSpaceType','RNTIAttempted','ExpectedRNTI','CrcPass','DciFormatDecoded', ...
        'Metric','RejectedReason','IsSelectedCandidate'});
end
end

function T = localNegativeTable(runId, negatives)
vars = {'RunId','NegativeTrialType','InjectedFault','ExpectedFailureStage','ObservedFailureStage', ...
    'WrongRNTIRejectCount','NoSignalRejectCount','FalseCandidateCount','StrictOk','Status','FailureReason'};
if isempty(negatives)
    T = table('Size', [0 numel(vars)], 'VariableTypes', ...
        {'string','string','string','string','string','double','double','double','logical','string','string'}, ...
        'VariableNames', vars);
    return;
end
n = numel(negatives);
rows = cell(n, numel(vars));
for i = 1:n
    rows{i,1} = runId;
    rows{i,2} = string(sixgr.util.structGet(negatives(i), "NegativeTrialType", ""));
    rows{i,3} = string(sixgr.util.structGet(negatives(i), "InjectedFault", ""));
    rows{i,4} = string(sixgr.util.structGet(negatives(i), "ExpectedFailureStage", ""));
    rows{i,5} = string(sixgr.util.structGet(negatives(i), "Status", ""));
    rows{i,6} = double(sixgr.util.structGet(negatives(i), "WrongRNTIRejectCount", 0));
    rows{i,7} = double(sixgr.util.structGet(negatives(i), "NoSignalRejectCount", 0));
    rows{i,8} = double(sixgr.util.structGet(negatives(i), "FalseCandidateCount", 0));
    rows{i,9} = logical(sixgr.util.structGet(negatives(i), "StrictOk", false));
    rows{i,10} = string(sixgr.util.structGet(negatives(i), "Status", ""));
    rows{i,11} = string(sixgr.util.structGet(negatives(i), "FailureReason", ""));
end
T = cell2table(rows, 'VariableNames', vars);
end

function T = localRoundtripTable(runId, txTree, rxTree, equal)
paths = ["message.c1.systemInformationBlockType1", ...
    "cellAccessRelatedInfo", "servingCellConfigCommon", "uplinkConfigCommon.initialUplinkBWP.rach_ConfigCommon"];
n = numel(paths);
T = table(repmat(runId, n, 1), paths(:), repmat("", n, 1), repmat("", n, 1), ...
    repmat(logical(equal), n, 1), nan(n, 1), nan(n, 1), repmat("anchor_profile_constraint", n, 1), ...
    repmat(string(ternary(equal, "PASS", "FAIL")), n, 1), ...
    'VariableNames', {'RunId','IEPath','TxValue','RxValue','Equal','EncodedBitOffsetStart', ...
    'EncodedBitOffsetEnd','ConstraintName','Status'});
if ~isempty(fieldnames(txTree)) && ~isempty(fieldnames(rxTree))
    T.TxValue(:) = "present";
    T.RxValue(:) = "present";
end
end

function vals = localColumnDouble(T, name, defaultVal)
if istable(T) && ismember(name, string(T.Properties.VariableNames))
    vals = double(T.(name));
else
    vals = repmat(defaultVal, height(T), 1);
end
end

function vals = localColumnLogical(T, name, defaultVal)
if istable(T) && ismember(name, string(T.Properties.VariableNames))
    vals = logical(T.(name));
else
    vals = repmat(logical(defaultVal), height(T), 1);
end
end

function localWriteBytes(pathValue, bits)
bits = int8(bits(:));
pad = mod(8 - mod(numel(bits), 8), 8);
if pad > 0
    bits = [bits; zeros(pad, 1, "int8")];
end
bytes = zeros(numel(bits)/8, 1, "uint8");
for i = 1:numel(bytes)
    v = uint8(0);
    for b = 1:8
        v = bitor(bitshift(v, 1), uint8(bits((i-1)*8+b) ~= 0));
    end
    bytes(i) = v;
end
sixgr.util.ensureDir(pathValue);
fid = fopen(pathValue, "w");
fwrite(fid, bytes, "uint8");
fclose(fid);
end

function localWriteText(pathValue, textValue)
sixgr.util.ensureDir(pathValue);
fid = fopen(pathValue, "w");
fprintf(fid, "%s\n", char(string(textValue)));
fclose(fid);
end

function localWriteGridFigure(pathValue, grid, titleText)
sixgr.util.ensureDir(pathValue);
fig = figure("Visible", "off");
imagesc(abs(sum(grid, 3)) > 0);
title(titleText);
xlabel("OFDM symbol");
ylabel("Subcarrier");
drawnow;
saveas(fig, pathValue);
close(fig);
end

function localWriteCandidateFigure(pathValue, T)
sixgr.util.ensureDir(pathValue);
fig = figure("Visible", "off");
if istable(T) && ~isempty(T)
    bar(double(T.CandidateIndex), double(T.CrcPass));
else
    bar(0, 0);
end
title("SIB1 SI-RNTI PDCCH candidate CRC results");
xlabel("Candidate");
ylabel("CRC pass");
drawnow;
saveas(fig, pathValue);
close(fig);
end

function localWriteSVG(pathValue, strictOk)
sixgr.util.ensureDir(pathValue);
status = ternary(strictOk, "PASS", "FAIL");
txt = sprintf(['<svg xmlns="http://www.w3.org/2000/svg" width="760" height="160">' ...
    '<rect width="100%%" height="100%%" fill="#f8fafc"/>' ...
    '<text x="24" y="44" font-family="monospace" font-size="18">SSB -> PBCH/MIB -> Type0-PDCCH SI-RNTI -> PDSCH/DL-SCH -> SIB1 ASN.1</text>' ...
    '<text x="24" y="92" font-family="monospace" font-size="16">Strict SIB1 evidence: %s</text>' ...
    '</svg>'], status);
localWriteText(pathValue, txt);
end

function out = ternary(cond, a, b)
if cond
    out = a;
else
    out = b;
end
end

function value = localGetStructOrObjectField(obj, fieldName, defaultValue)
value = defaultValue;
try
    if isstruct(obj) && isfield(obj, fieldName)
        value = obj.(fieldName);
        return;
    end
catch
end
try
    if isobject(obj) && isprop(obj, fieldName)
        value = obj.(fieldName);
    end
catch
    value = defaultValue;
end
end
