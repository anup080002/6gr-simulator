function tables = buildLLSPublicOutputTables(baseTables, contract, meta, receivedCSIReports)
%BUILDLLSPUBLICOUTPUTTABLES Build public family-specific LLS tables.
if nargin < 4, receivedCSIReports = table(); end

tables = struct();
tables.pdsch_runtime_event_table = iDataRuntimeEventTable(iTable(baseTables, "pdsch_table"), meta, "PDSCH");
tables.pusch_runtime_event_table = iDataRuntimeEventTable(iTable(baseTables, "pusch_table"), meta, "PUSCH");
tables.pdcch_dci_public_table = iPDCCHTable(iTable(baseTables, "pdcch_dci_table"), meta);
tables.pucch_uci_table = iPUCCHTable(iTable(baseTables, "pucch_table"), meta);
tables.prach_detection_table = iPRACHTable(iTable(baseTables, "prach_table"), meta);
tables.srs_measurement_table = iSRSTable(iTable(baseTables, "srs_table"), meta);
tables.csi_rs_runtime_event_table = iCSIRSTable(iTable(baseTables, "csi_rs_table"), meta);
tables.csi_report_table = iCSIReportTable(receivedCSIReports, meta);
tables.trs_receiver_tracking_public_table = iTRSTable(iTable(baseTables, "trs_receiver_tracking_table"), meta);
tables.ssb_pbch_cell_search_table = iSSBPBCHTable(iTable(baseTables, "ssb_pbch_table"), meta);
tables.noise_variance_evidence_table = iNoiseVarianceTable(tables, meta);
tables.mcs_cqi_decision_trace_table = iMCSCQITable(iTable(baseTables, "table_mcs_tbs_evolution"), meta);
tables.lls_output_contract = contract.Outputs;
tables.metric_definition_catalog = contract.Metrics;
tables.metric_unit_role_catalog = iMetricUnitRoleCatalog(contract.Metrics, meta);
tables.runtime_issue_registry = iRuntimeIssueRegistryTable(iTable(baseTables, "result_issue_registry"), meta);
end

function T = iTable(S, name)
if isstruct(S) && isfield(S, char(name))
    T = S.(char(name));
else
    T = table();
end
end

function out = iFirstNum(row, names, defaultValue)
out = double(defaultValue);
for i = 1:numel(names)
    name = string(names(i));
    if ismember(name, string(row.Properties.VariableNames))
        try
            out = double(row.(name)(1));
        catch
            out = str2double(string(row.(name)(1)));
        end
        return;
    end
end
end

function out = iFirstText(row, names, defaultValue)
out = string(defaultValue);
for i = 1:numel(names)
    name = string(names(i));
    if ismember(name, string(row.Properties.VariableNames))
        out = string(row.(name)(1));
        return;
    end
end
end

function out = iFirstLogical(row, names, defaultValue)
out = logical(defaultValue);
for i = 1:numel(names)
    name = string(names(i));
    if ismember(name, string(row.Properties.VariableNames))
        raw = row.(name)(1);
        try
            out = logical(raw);
        catch
            out = any(lower(strtrim(string(raw))) == ["1","true","yes","on","pass"]);
        end
        return;
    end
end
end

function values = iColumnNum(T, names)
values = nan(height(T), 1);
for i = 1:numel(names)
    name = string(names(i));
    if ismember(name, string(T.Properties.VariableNames))
        try
            values = double(T.(name));
        catch
            values = str2double(string(T.(name)));
        end
        values = values(:);
        return;
    end
end
end

function values = iColumnText(T, names)
values = repmat("", height(T), 1);
for i = 1:numel(names)
    name = string(names(i));
    if ismember(name, string(T.Properties.VariableNames))
        values = string(T.(name));
        values = values(:);
        return;
    end
end
end

function values = iColumnLogical(T, names)
values = false(height(T), 1);
for i = 1:numel(names)
    name = string(names(i));
    if ismember(name, string(T.Properties.VariableNames))
        raw = T.(name);
        try
            values = logical(raw);
        catch
            txt = lower(strtrim(string(raw)));
            values = ismember(txt, ["1","true","yes","on","pass"]);
        end
        values = values(:);
        return;
    end
end
end

function [value, source] = iSINR(row)
value = iFirstNum(row, ["PostEqSINR_dB","MeasuredTrialSINR_dB","MeasuredWidebandSINR_dB","SINR_dB","LargeScaleSINR_dB"], NaN);
if isfinite(iFirstNum(row, ["PostEqSINR_dB","MeasuredTrialSINR_dB","MeasuredWidebandSINR_dB"], NaN))
    source = "post_equalization_receiver_measurement";
elseif isfinite(iFirstNum(row, ["SINR_dB"], NaN))
    source = "runtime_primary_sinr";
elseif isfinite(iFirstNum(row, ["LargeScaleSINR_dB"], NaN))
    source = "large_scale_model";
else
    source = "unavailable";
end
end

function [noiseVar, noiseSource, noiseStatus, noiseReason] = iNoise(row)
noiseVar = iFirstNum(row, ["NoiseVar","NoiseVariance","nVar"], NaN);
noiseSource = iFirstText(row, ["NoiseVarSource"], "");
noiseStatus = iFirstText(row, ["NoiseVarStatus"], "");
noiseReason = iFirstText(row, ["NoiseVarReason"], "");
noiseSource = strtrim(string(noiseSource));
noiseStatus = upper(strtrim(string(noiseStatus)));
noiseReason = strtrim(string(noiseReason));
if ismissing(noiseSource), noiseSource = ""; end
if ismissing(noiseStatus), noiseStatus = ""; end
if ismissing(noiseReason), noiseReason = ""; end
if strlength(noiseStatus) == 0 || ~ismember(noiseStatus, ["OK","NOT_AVAILABLE"])
    noiseStatus = iIf(isfinite(noiseVar) && noiseVar > 0, "OK", "NOT_AVAILABLE");
end
if strlength(noiseSource) == 0
    if isfinite(noiseVar) && noiseVar > 0
        noiseSource = "runtime_metadata";
    elseif isfinite(noiseVar) && noiseVar <= 0
        noiseSource = "unavailable_invalid_nonpositive";
    else
        noiseSource = "unavailable_missing";
    end
end
if strlength(noiseReason) == 0 && (~isfinite(noiseVar) || noiseVar <= 0)
    noiseReason = "missing_or_invalid_noise_variance";
end
end

function [evmPercent, evmSource] = iEVMPercent(row)
evmPercent = NaN;
evmSource = "";
evmPct = iFirstNum(row, ["EVM_percent","EVM_rms_percent"], NaN);
if isfinite(evmPct) && evmPct >= 0
    evmPercent = evmPct;
    evmSource = "explicit_percent";
    return;
end
evmRaw = iFirstNum(row, ["EVM_rms","EVM","PostEqEVM"], NaN);
if ~(isfinite(evmRaw) && evmRaw >= 0)
    return;
end
if evmRaw <= 1.0
    evmPercent = 100 * evmRaw;
    evmSource = "fractional_rms";
elseif evmRaw <= 100
    evmPercent = evmRaw;
    evmSource = "percent_rms";
else
    persistent warnedAmbiguous;
    if isempty(warnedAmbiguous)
        warning("sixgr:output:EVMUnitAmbiguous", ...
            "EVM value is outside the expected fractional/percent range. Emitting NaN for ambiguous EVM units.");
        warnedAmbiguous = true;
    end
end
explicitSource = iFirstText(row, ["EVMSource"], "");
if strlength(strtrim(string(explicitSource))) > 0
    evmSource = explicitSource;
end
end

function outcome = iCRCOutcome(applicable, passFlag)
if ~logical(applicable)
    outcome = "not_applicable";
elseif logical(passFlag)
    outcome = "pass";
else
    outcome = "fail";
end
end

function out = iIf(cond, a, b)
if cond
    out = a;
else
    out = b;
end
end

function runId = iLogicalRunId(meta)
% Logical run identity is the filesystem/WebGUI run tag.  The lowercase
% meta.run_id field is an optional numeric database key and must never be
% substituted into the public RunId column for filesystem-only runs.
runId = strtrim(string(sixgr.util.structGet(meta, "logical_run_id", ...
    sixgr.util.structGet(meta, "run_tag", ""))));
if strlength(runId) == 0
    databaseRunId = double(sixgr.util.structGet(meta, "run_id", NaN));
    if isfinite(databaseRunId)
        runId = string(databaseRunId);
    end
end
if strlength(runId) == 0
    error("sixgr:truth:buildLLSPublicOutputTables:MissingRunIdentity", ...
        "Public LLS output tables require a nonblank logical run identity.");
end
end

function T = iDataRuntimeEventTable(sourceT, meta, channelType)
if ~(istable(sourceT) && ~isempty(sourceT))
    T = table();
    return;
end
n = height(sourceT);
rows = repmat(struct( ...
    "OutputId", lower(channelType) + "_runtime_event_table", "RunId", iLogicalRunId(meta), "TrialId", NaN, ...
    "SFN", NaN, "Slot", NaN, "UEId", NaN, "RNTI", NaN, "BWPId", NaN, "CellId", NaN, ...
    "PRBStart", NaN, "PRBLength", NaN, "SymbolStart", NaN, "SymbolLength", NaN, "NumLayers", NaN, ...
    "Modulation", "", "TargetCodeRate", NaN, "MCS", NaN, "TBSBits", NaN, "NREPerPRB", NaN, "DMRSConfigId", "", ...
    "PTRSConfigId", "", "NoiseVar", NaN, "NoiseVarSource", "", "NoiseVarStatus", "", "NoiseVarReason", "", ...
    "ConfiguredSNR_dB", NaN, "AppliedAWGNSNR_dB", NaN, "ChannelEstimationSource", "", "EqualizerType", "", ...
    "EVM_dB", NaN, "EVM_percent", NaN, "EVMSource", "", "SINR_dB", NaN, "SINRSource", "", "SINRValueRole", "", ...
    "SINRValueStatus", "", ...
    "CRCApplicable", false, "CRCPass", NaN, "DecodeAttempted", false, "DecodeUsable", false, ...
    "HARQProcessId", NaN, "NDI", NaN, "RV", NaN, "TPMI", NaN, "AppliedPrecoderPMI", NaN, ...
    "AppliedPrecoderSource", "", "AppliedBeamIndexSet", "", "BeamIndexSetMaterialized", false, ...
    "TransformPrecodingEnabled", false, "UCIOnPUSCHFlag", false, "RuntimeEvidenceStatus", "", ...
    "FailureReason", "", "run_id", meta.run_id, "producer_module", "sixgr.truth.buildLLSPublicOutputTables", ...
    "source_artifact_ref", "", "runtime_evidence", ""), n, 1);
for i = 1:n
    row = sourceT(i, :);
    % Preserve the receiver's numeric/provenance tuple. A generic field-name
    % label cannot distinguish data post-EQ SINR from pilot/model/proxy SINR.
    [sinrValue,sinrSource,sinrRole,sinrStatus]=sixgr.link.selectReceiverDataSINR(row);
    if ~isfinite(sinrValue)
        sinrSource="unavailable"; sinrRole="unavailable"; sinrStatus="NOT_AVAILABLE";
    end
    [noiseVar, noiseSource, noiseStatus, noiseReason] = iNoise(row);
    [evmPercent, evmSource] = iEVMPercent(row);
    evmDb = iFirstNum(row, ["EVM_dB"], NaN);
    if ~isfinite(evmDb) && isfinite(evmPercent) && evmPercent > 0
        evmDb = 20 * log10(evmPercent / 100);
    end
    crcApplicable = iFirstLogical(row, ["CRCApplicable"], channelType ~= "PUCCH");
    rows(i).TrialId = i;
    rows(i).SFN = iFirstNum(row, ["Frame", "SFN"], NaN);
    rows(i).Slot = iFirstNum(row, ["Slot"], NaN);
    rows(i).UEId = iFirstNum(row, ["UEId", "ue_id", "UEID", "UEIndex", "UE", "RNTI"], NaN);
    rows(i).RNTI = iFirstNum(row, ["RNTI"], NaN);
    rows(i).BWPId = iFirstNum(row, ["BWPId", "bwp_id", "BWPID"], NaN);
    rows(i).CellId = iFirstNum(row, ["CellID", "cell_id", "ServingCell"], NaN);
    rows(i).PRBStart = iFirstNum(row, ["PRBStart", "RBOffset"], NaN);
    rows(i).PRBLength = iFirstNum(row, ["PRBCount", "NumRB"], NaN);
    rows(i).SymbolStart = iFirstNum(row, ["SymbolStart"], NaN);
    rows(i).SymbolLength = iFirstNum(row, ["NumSymbols"], NaN);
    rows(i).NumLayers = iFirstNum(row, ["NumLayers", "Layers", "PrecodingNumLayers"], NaN);
    rows(i).Modulation = iFirstText(row, ["Modulation"], "");
    rows(i).TargetCodeRate = iFirstNum(row, ["TargetCodeRate", "target_code_rate", "CodeRate"], NaN);
    rows(i).MCS = iFirstNum(row, ["MCSIndex", "mcs_selected"], NaN);
    rows(i).TBSBits = iFirstNum(row, ["TBSBits", "TBSize_bits", "TransportBlockSize", "TB_size_bits"], NaN);
    rows(i).NREPerPRB = iFirstNum(row, ["NREPerPRB", "nrePerPRB", "NRE_per_PRB"], NaN);
    rows(i).DMRSConfigId = iFirstText(row, ["DMRSConfigId"], "");
    rows(i).PTRSConfigId = iFirstText(row, ["PTRSConfigId"], "");
    rows(i).NoiseVar = noiseVar;
    rows(i).NoiseVarSource = noiseSource;
    rows(i).NoiseVarStatus = noiseStatus;
    rows(i).NoiseVarReason = noiseReason;
    rows(i).ConfiguredSNR_dB = iFirstNum(row, ["ConfiguredSNR_dB"], NaN);
    rows(i).AppliedAWGNSNR_dB = iFirstNum(row, ["AppliedAWGNSNR_dB"], NaN);
    rows(i).ChannelEstimationSource = iFirstText(row, ["ChannelEstimationSource", "ChannelEstimatorType"], "");
    rows(i).EqualizerType = iFirstText(row, ["EqualizerType"], "");
    rows(i).EVM_dB = evmDb;
    rows(i).EVM_percent = evmPercent;
    rows(i).EVMSource = evmSource;
    rows(i).SINR_dB = sinrValue;
    rows(i).SINRSource = sinrSource;
    rows(i).SINRValueRole = sinrRole;
    rows(i).SINRValueStatus = sinrStatus;
    rows(i).CRCApplicable = crcApplicable;
    rows(i).CRCPass = iIf(crcApplicable, double(iFirstLogical(row, ["CRCPass", "tb_crc_pass_flag", "DecodeSuccess"], false)), NaN);
    rows(i).DecodeAttempted = iFirstLogical(row, ["DecodeAttempted", "DetectionAttempted"], false);
    rows(i).DecodeUsable = iFirstLogical(row, ["DecodeUsable", "ReceiverUsable"], false);
    rows(i).HARQProcessId = iFirstNum(row, ["HarqID", "HARQProcessId", "harq_id"], NaN);
    rows(i).NDI = iFirstNum(row, ["NDI"], NaN);
    rows(i).RV = iFirstNum(row, ["RV"], NaN);
    rows(i).TPMI = iFirstNum(row, ["TPMI", "RequestedPrecoderPMI"], NaN);
    rows(i).AppliedPrecoderPMI = iFirstNum(row, ["AppliedPrecoderPMI"], NaN);
    rows(i).AppliedPrecoderSource = iFirstText(row, ["AppliedPrecoderSource", "AppliedPrecoderPMIApplicationSource"], "");
    rows(i).AppliedBeamIndexSet = iFirstText(row, ["AppliedBeamIndexSet"], "");
    rows(i).BeamIndexSetMaterialized = iFirstText(row, ["AppliedBeamTruthClassification"], "") == "applied_runtime_value";
    rows(i).TransformPrecodingEnabled = iFirstLogical(row, ["TransformPrecodingApplied", "TransformPrecodingEnabled"], false);
    rows(i).UCIOnPUSCHFlag = iFirstLogical(row, ["UCIOnPUSCHFlag"], false);
    rows(i).RuntimeEvidenceStatus = iFirstText(row, ["RuntimeEvidenceStatus", "runtime_evidence"], "persisted_runtime_trial_row");
    rows(i).FailureReason = iFirstText(row, ["FailureReason"], "");
    rows(i).source_artifact_ref = iFirstText(row, ["source_artifact_ref"], "");
    rows(i).runtime_evidence = iFirstText(row, ["runtime_evidence"], "");
end
T = struct2table(rows);
if channelType ~= "PUSCH"
    T(:, intersect(["TPMI","AppliedPrecoderPMI","AppliedPrecoderSource","AppliedBeamIndexSet","BeamIndexSetMaterialized","TransformPrecodingEnabled","UCIOnPUSCHFlag"], string(T.Properties.VariableNames), 'stable')) = [];
end
end

function T = iBuildMinimalTable(sourceT, meta, outputId, mapping)
if ~(istable(sourceT) && ~isempty(sourceT))
    T = table();
    return;
end
n = height(sourceT);
rows = repmat(struct("OutputId", outputId, "RunId", iLogicalRunId(meta), "TrialId", NaN, "run_id", meta.run_id, ...
    "producer_module", "sixgr.truth.buildLLSPublicOutputTables", "source_artifact_ref", "", "runtime_evidence", ""), n, 1);
for i = 1:n
    row = sourceT(i, :);
    rows(i).TrialId = i;
    rows(i).source_artifact_ref = iFirstText(row, ["source_artifact_ref"], "");
    rows(i).runtime_evidence = iFirstText(row, ["runtime_evidence"], "");
    for k = 1:size(mapping, 1)
        outName = mapping{k, 1};
        sourceNames = string(mapping{k, 2});
        if any(contains(outName, ["Applicable","Attempted","Usable","Detected","Observed","Consumed","Transmitted","Scheduled","Recovered","Flag"]))
            rows(i).(outName) = iFirstLogical(row, sourceNames, false);
        elseif endsWith(outName, "Status") || contains(outName, "Source") || contains(outName, "Format") || contains(outName, "Type") || contains(outName, "Outcome") || contains(outName, "Locations") || contains(outName, "Consumer")
            rows(i).(outName) = iFirstText(row, sourceNames, "");
        else
            val = iFirstNum(row, sourceNames, NaN);
            if isfinite(val)
                rows(i).(outName) = val;
            else
                rows(i).(outName) = iFirstText(row, sourceNames, "");
            end
        end
    end
end
T = struct2table(rows);
end

function T = iPDCCHTable(sourceT, meta)
T = iBuildMinimalTable(sourceT, meta, "pdcch_dci_table", { ...
    "SFN", ["Frame", "SFN"]; "Slot", ["Slot"]; "UEId", ["UEIndex","UEID","UE","RNTI"]; "RNTI", ["RNTI"]; ...
    "CORESETId", ["CORESETId"]; "SearchSpaceId", ["SearchSpaceId"]; "AggregationLevel", ["AggregationLevel"]; ...
    "CandidateIndex", ["CandidateIndex"]; "CCEStart", ["CCEStart"]; "CCELength", ["CCELength"]; ...
    "DCIFormat", ["DCIFormat"]; "DCIPayloadBits", ["DCIPayloadBits","PayloadBits"]; "RNTIType", ["RNTIType"]; ...
    "BlindDecodeAttempted", ["BlindDecodeAttempted","DecodeAttempted"]; "DetectionMetric", ["DetectionMetric"]; ...
    "CRCApplicable", ["CRCApplicable"]; "CRCPass", ["CRCPass","DecodeSuccess"]; "FalseAlarmFlag", ["FalseAlarmFlag"]; ...
    "MissedDetectionFlag", ["MissedDetectionFlag"]; "LinkedGrantId", ["LinkedGrantId"]; "LinkedPDSCHOrPUSCH", ["LinkedPDSCHOrPUSCH"]; ...
    "RuntimeEvidenceStatus", ["RuntimeEvidenceStatus","runtime_evidence"]});
end

function T = iPUCCHTable(sourceT, meta)
if ~(istable(sourceT) && ~isempty(sourceT))
    T = table();
    return;
end
rows = repmat(struct("OutputId", "pucch_uci_table", "RunId", iLogicalRunId(meta), "TrialId", NaN, "SFN", NaN, "Slot", NaN, ...
    "UEId", NaN, "RNTI", NaN, "PUCCHFormat", "", "ResourceId", "", "HARQACKBitsTx", NaN, "HARQACKBitsRx", NaN, ...
    "SRBitTx", NaN, "SRBitRx", NaN, "CSIBitsTx", NaN, "CSIBitsRx", NaN, "UCIContentMatch", false, ...
    "DetectionAttempted", false, "DetectionUsable", false, "DetectionOutcome", "", "DetectionMetric", NaN, "NoiseVar", NaN, ...
    "NoiseVarSource", "", "NoiseVarStatus", "", "NoiseVarReason", "", "CRCApplicable", false, "CRCOutcome", "", ...
    "SINR_dB", NaN, "SINRSource", "", "DTXFlag", false, "DTXReason", "", "BitErrors", NaN, "BitsCompared", NaN, ...
    "ChannelGain_dB", NaN, "ConditionNumber_dB", NaN, "AirInterfaceTTI_ms", NaN, "ComputeLatency_ms", NaN, ...
    "RuntimeEvidenceStatus", "", "FailureReason", "", "ReceiverUsable", false, "run_id", meta.run_id, ...
    "producer_module", "sixgr.truth.buildLLSPublicOutputTables", "source_artifact_ref", "", "runtime_evidence", ""), height(sourceT), 1);
for i = 1:height(sourceT)
    row = sourceT(i, :);
    [noiseVar, noiseSource, noiseStatus, noiseReason] = iNoise(row);
    [sinrValue, sinrSource] = iSINR(row);
    crcApplicable = iFirstLogical(row, ["CRCApplicable"], false);
    crcPass = iFirstLogical(row, ["CRCPass","DecodeSuccess"], false);
    rawCRCOutcome = iFirstText(row, ["CRCOutcome"], "");
    rawDetectionOutcome = iFirstText(row, ["DetectionOutcome"], "");
    rows(i).TrialId = i;
    rows(i).SFN = iFirstNum(row, ["Frame","SFN"], NaN);
    rows(i).Slot = iFirstNum(row, ["Slot"], NaN);
    rows(i).UEId = iFirstNum(row, ["UEIndex","UEID","UE","RNTI"], NaN);
    rows(i).RNTI = iFirstNum(row, ["RNTI"], NaN);
    rows(i).PUCCHFormat = iFirstText(row, ["ResolvedFormat","RequestedFormat","PUCCHFormat"], "");
    rows(i).ResourceId = iFirstText(row, ["PUCCHResourceId"], "");
    rows(i).HARQACKBitsTx = iBitCount(row, ["HARQACKBitsTx","ExpectedAck"]);
    rows(i).HARQACKBitsRx = iBitCount(row, ["HARQACKBitsRx","ObservedAck","DecodedAck"]);
    rows(i).SRBitTx = iBitCount(row, ["SRBitTx"]);
    rows(i).SRBitRx = iBitCount(row, ["SRBitRx"]);
    rows(i).CSIBitsTx = iBitCount(row, ["CSIBitsTx"]);
    rows(i).CSIBitsRx = iBitCount(row, ["CSIBitsRx"]);
    rows(i).UCIContentMatch = iFirstLogical(row, ["UCIContentMatch"], false);
    rows(i).DetectionAttempted = iFirstLogical(row, ["DetectionAttempted","DecodeAttempted"], false);
    rows(i).ReceiverUsable = iFirstLogical(row, ["ReceiverUsable"], false);
    rows(i).DetectionUsable = iFirstLogical(row, ["DetectionUsable"], rows(i).ReceiverUsable);
    if strlength(rawDetectionOutcome) > 0
        rows(i).DetectionOutcome = rawDetectionOutcome;
    else
        rows(i).DetectionOutcome = "unavailable";
    end
    rows(i).DetectionMetric = iFirstNum(row, ["DetectionMetric"], NaN);
    rows(i).NoiseVar = noiseVar;
    rows(i).NoiseVarSource = noiseSource;
    rows(i).NoiseVarStatus = noiseStatus;
    rows(i).NoiseVarReason = noiseReason;
    rows(i).SINR_dB = sinrValue;
    rows(i).SINRSource = sinrSource;
    rows(i).DTXFlag = iFirstLogical(row, ["DTXFlag"], false);
    rows(i).DTXReason = iFirstText(row, ["DTXReason"], "");
    rows(i).BitErrors = iFirstNum(row, ["BitErrors"], NaN);
    rows(i).BitsCompared = iFirstNum(row, ["BitsCompared"], NaN);
    rows(i).ChannelGain_dB = iFirstNum(row, ["ChannelGain_dB"], NaN);
    rows(i).ConditionNumber_dB = iFirstNum(row, ["ConditionNumber_dB"], NaN);
    rows(i).AirInterfaceTTI_ms = iFirstNum(row, ["AirInterfaceTTI_ms"], NaN);
    rows(i).ComputeLatency_ms = iFirstNum(row, ["ComputeLatency_ms", "DecodeLatency_ms"], NaN);
    rows(i).CRCApplicable = crcApplicable;
    if strlength(rawCRCOutcome) > 0
        rows(i).CRCOutcome = rawCRCOutcome;
    else
        rows(i).CRCOutcome = iCRCOutcome(crcApplicable, crcPass);
    end
    rows(i).RuntimeEvidenceStatus = iFirstText(row, ["RuntimeEvidenceStatus","runtime_evidence"], "persisted_runtime_trial_row");
    rows(i).FailureReason = iFirstText(row, ["FailureReason"], "");
    rows(i).source_artifact_ref = iFirstText(row, ["source_artifact_ref"], "");
    rows(i).runtime_evidence = iFirstText(row, ["runtime_evidence"], "");
end
T = struct2table(rows);
end

function T = iPRACHTable(sourceT, meta)
T = iBuildMinimalTable(sourceT, meta, "prach_detection_table", { ...
    "SFN", ["Frame","SFN"]; "Slot", ["Slot"]; "CellId", ["CellID","cell_id","ServingCell"]; "UEId", ["UEIndex","UEID","UE"]; ...
    "PRACHFormat", ["PRACHFormat"]; "ConfigurationIndex", ["ConfigurationIndex"]; "PreambleIndex", ["PreambleIndex","preamble_id"]; ...
    "RootSequenceIndex", ["RootSequenceIndex","root_sequence_index"]; "ZeroCorrelationZone", ["ZeroCorrelationZone"]; "RestrictedSet", ["RestrictedSet"]; ...
    "OccasionIndex", ["OccasionIndex","prach_occasion_id"]; "FrequencyIndex", ["FrequencyIndex"]; "TimeIndex", ["TimeIndex"]; ...
    "CorrelationPeak", ["CorrelationPeak","peak_value","DetectionMetric"]; "DetectionThreshold", ["DetectionThreshold"]; ...
    "Detected", ["Detected","DecodeSuccess","CRCPass"]; "MissedDetection", ["MissedDetection"]; "FalseAlarm", ["FalseAlarm","FalseAlarmFlag"]; ...
    "CollisionDetected", ["CollisionDetected"]; "TimingOffsetSamplesRaw", ["RawTimingEstimate_samples","TimingOffsetSamplesRaw"]; ...
    "TimingOffsetSamplesApplied", ["AppliedTimingCorrection_samples","TimingOffsetSamplesApplied"]; "RA_RNTI", ["RA_RNTI"]; ...
    "AccessDelay_ms", ["AccessDelay_ms"]; "ProcedureDelay_ms", ["ProcedureDelay_ms"]; ...
    "RAResponseWindow_slots", ["RAResponseWindow_slots"]; "ContentionResolutionTimer_slots", ["ContentionResolutionTimer_slots"]; ...
    "SlotDuration_ms", ["SlotDuration_ms"]; "AirInterfaceObservation_ms", ["AirInterfaceObservation_ms"]; ...
    "RuntimeEvidenceStatus", ["RuntimeEvidenceStatus","runtime_evidence"]});
end

function T = iSRSTable(sourceT, meta)
if ~(istable(sourceT) && ~isempty(sourceT))
    T = table();
    return;
end
rows = repmat(struct("OutputId", "srs_measurement_table", "RunId", iLogicalRunId(meta), "TrialId", NaN, "SFN", NaN, "Slot", NaN, ...
    "UEId", NaN, "RNTI", NaN, "SRSResourceId", NaN, "SRSResourceSetId", NaN, "NumPorts", NaN, "CombSize", NaN, ...
    "CyclicShift", NaN, "SequenceId", NaN, "Bandwidth", NaN, "StartRB", NaN, "ChannelEstimateAvailable", false, ...
    "NMSE_dB", NaN, "RSRP_dB", NaN, "SINR_dB", NaN, "NoiseVar", NaN, "NoiseVarSource", "", "NoiseVarStatus", "", ...
    "RIEstimate", NaN, "TPMIEstimate", NaN, "RISource", "", "TPMISource", "", "DopplerEstimate_Hz", NaN, ...
    "DopplerError_Hz", NaN, "ConditionNumber_dB", NaN, "QCLAccuracy", NaN, "InterpolationLoss_dB", NaN, ...
    "MismatchSensitivity_dB", NaN, "AcquisitionTime_ms", NaN, "TrackingFailure", NaN, ...
    "NoiseVarReason", "", "MeasurementAttempted", false, "MeasurementUsable", false, "RuntimeEvidenceStatus", "", ...
    "run_id", meta.run_id, "producer_module", "sixgr.truth.buildLLSPublicOutputTables", "source_artifact_ref", "", "runtime_evidence", ""), height(sourceT), 1);
for i = 1:height(sourceT)
    row = sourceT(i, :);
    [noiseVar, noiseSource, noiseStatus, noiseReason] = iNoise(row);
    [sinrValue, ~] = iSINR(row);
    rows(i).TrialId = i;
    rows(i).SFN = iFirstNum(row, ["Frame","SFN"], NaN);
    rows(i).Slot = iFirstNum(row, ["Slot"], NaN);
    rows(i).UEId = iFirstNum(row, ["UEIndex","UEID","UE","RNTI"], NaN);
    rows(i).RNTI = iFirstNum(row, ["RNTI"], NaN);
    rows(i).SRSResourceId = iFirstNum(row, ["SRSResourceId","ResourceID"], NaN);
    rows(i).SRSResourceSetId = iFirstNum(row, ["SRSResourceSetId","ResourceSetID"], NaN);
    rows(i).NumPorts = iFirstNum(row, ["NumPorts","port_count"], NaN);
    rows(i).CombSize = iFirstNum(row, ["CombSize","comb"], NaN);
    rows(i).CyclicShift = iFirstNum(row, ["CyclicShift"], NaN);
    rows(i).SequenceId = iFirstNum(row, ["SequenceId","srs_seq_id"], NaN);
    rows(i).Bandwidth = iFirstNum(row, ["Bandwidth","NumRB"], NaN);
    rows(i).StartRB = iFirstNum(row, ["StartRB","RBOffset"], NaN);
    rows(i).ChannelEstimateAvailable = iFirstLogical(row, ["ChannelEstimateAvailable","MeasurementUsable"], isfinite(iFirstNum(row, ["NMSE_dB"], NaN)));
    rows(i).NMSE_dB = iFirstNum(row, ["NMSE_dB"], NaN);
    rows(i).RSRP_dB = iFirstNum(row, ["RSRP_dB","MeasurementRSRP_dB"], NaN);
    rows(i).SINR_dB = sinrValue;
    rows(i).NoiseVar = noiseVar;
    rows(i).NoiseVarSource = noiseSource;
    rows(i).NoiseVarStatus = noiseStatus;
    rows(i).NoiseVarReason = noiseReason;
    rows(i).RIEstimate = iFirstNum(row, ["RIEstimate", "EstimatedRI", "RI"], NaN);
    rows(i).TPMIEstimate = iFirstNum(row, ["TPMIEstimate", "EstimatedTPMI", "TPMI"], NaN);
    rows(i).RISource = iFirstText(row, ["RISource"], "");
    rows(i).TPMISource = iFirstText(row, ["TPMISource"], "");
    rows(i).DopplerEstimate_Hz = iFirstNum(row, ["EstimatedDopplerHz", "DopplerEstimate_Hz"], NaN);
    rows(i).DopplerError_Hz = iFirstNum(row, ["DopplerError_Hz"], NaN);
    rows(i).ConditionNumber_dB = iFirstNum(row, ["SRSConditionNumber_dB", "ConditionNumber_dB"], NaN);
    rows(i).QCLAccuracy = iFirstNum(row, ["QCLAccuracy"], NaN);
    rows(i).InterpolationLoss_dB = iFirstNum(row, ["InterpolationLoss_dB"], NaN);
    rows(i).MismatchSensitivity_dB = iFirstNum(row, ["MismatchSensitivity_dB"], NaN);
    rows(i).AcquisitionTime_ms = iFirstNum(row, ["AcquisitionTime_ms", "AirInterfaceObservation_ms"], NaN);
    rows(i).TrackingFailure = iFirstNum(row, ["TrackingFailure", "TrackingFailureProbability"], NaN);
    rows(i).MeasurementAttempted = iFirstLogical(row, ["MeasurementAttempted","DecodeAttempted"], false);
    rows(i).MeasurementUsable = iFirstLogical(row, ["MeasurementUsable","ReceiverUsable"], false);
    rows(i).RuntimeEvidenceStatus = iFirstText(row, ["RuntimeEvidenceStatus","runtime_evidence"], "persisted_runtime_trial_row");
    rows(i).source_artifact_ref = iFirstText(row, ["source_artifact_ref"], "");
    rows(i).runtime_evidence = iFirstText(row, ["runtime_evidence"], "");
end
T = struct2table(rows);
end

function T = iCSIRSTable(sourceT, meta)
T = iBuildMinimalTable(sourceT, meta, "csi_rs_runtime_event_table", { ...
    "SFN", ["Frame","SFN"]; "Slot", ["Slot"]; "CellId", ["CellID","cell_id"]; "BWPId", ["BWPID","BWPId","bwp_id"]; ...
    "UEId", ["UEIndex","UEID"]; "ResourceId", ["ResourceID","resource_id"]; "ResourceSetId", ["ResourceSetID","resource_set_id"]; ...
    "CSIRSType", ["CSIRSType","csirs_type"]; "NumPorts", ["NumPorts","num_ports"]; "Density", ["Density","density"]; ...
    "Periodicity", ["Periodicity","periodicity_slots"]; "SymbolLocations", ["SymbolLocations"]; "SubcarrierLocations", ["SubcarrierLocations"]; ...
    "Scheduled", ["Scheduled"]; "Transmitted", ["Transmitted"]; "Observed", ["Observed"]; "Consumed", ["Consumed"]; "Consumer", ["Consumer"]; ...
    "MeasurementRSRP_dB", ["MeasurementRSRP_dB"]; "MeasurementSource", ["MeasurementSource"]; "UpdateOutcome", ["UpdateOutcome"]; ...
    "RuntimeMaterializationStatus", ["RuntimeMaterializationStatus"]; "RuntimeEvidenceStatus", ["RuntimeEvidenceStatus","runtime_evidence","RuntimeEvidenceSource"]});
end

function T = iCSIReportTable(cqiTable, meta)
if ~(istable(cqiTable) && ~isempty(cqiTable))
    T = table();
    return;
end
% Scheduler selections and UE reference payloads are not received CSI.
required = ["SourceSignal","Direction","ReportIdentity","CSIUCIDecodeOk"];
assert(all(ismember(required,string(cqiTable.Properties.VariableNames))) && ...
    all(string(cqiTable.SourceSignal) == "received_CSI_UCI") && ...
    all(string(cqiTable.Direction) == "DL"), ...
    'sixgr:report:CSIReportReceiverAuthority', ...
    'Public CSI reports require independently received DL CSI-UCI records.');
rows = repmat(struct("OutputId", "csi_report_table", "RunId", iLogicalRunId(meta), "TrialId", NaN, "SFN", NaN, "Slot", NaN, ...
    "UEId", NaN, "RNTI", NaN, "CQI", NaN, "PMI", NaN, "RI", NaN, "LI", NaN, "CRI", NaN, "ReportType", "", ...
    "RankSelectionPolicy", "", "RankSelectionSource", "", "RankDecisionReason", "", ...
    "RankDowngradeApplied", false, "MaxSupportedLayers", NaN, ...
    "ReportQuantity", "", "WidebandOrSubband", "", "MeasurementSource", "", "CSIRSResourceId", NaN, ...
    "CQIDerivedMCS", NaN, "CQIDerivedModulation", "", "SubbandCQIVector", "", "SubbandPMIVector", "", ...
    "EffectiveSINR_dB", NaN, "CalibrationProfile", "", "RuntimeEvidenceStatus", "", ...
    "ReportIdentity", "", "CSIReportConfigID", "", "CSIConfigurationEpoch", NaN, ...
    "SourceSlot", NaN, "DueSlot", NaN, "DeliveredSlot", NaN, ...
    "CSIUCITransport", "", "CSIUCIDecodeOk", NaN, "CSIUCICRCPass", NaN, "DeliveryStatus", "", ...
    "run_id", meta.run_id, "producer_module", "sixgr.truth.buildLLSPublicOutputTables", "source_artifact_ref", "control/csv/received_csi_reports.csv", ...
    "runtime_evidence", "independently_received_csi_uci"), height(cqiTable), 1);
for i = 1:height(cqiTable)
    row = cqiTable(i, :);
    decoded = iFirstNum(row, "CSIUCIDecodeOk", NaN);
    usable = isfinite(decoded) && decoded == 1;
    rows(i).TrialId = i;
    rows(i).SFN = iFirstNum(row, ["Frame","SFN"], NaN);
    rows(i).Slot = iFirstNum(row, "DeliveredSlot", NaN);
    rows(i).UEId = iFirstNum(row, ["UEIndex","UEID"], NaN);
    rows(i).RNTI = iFirstNum(row, "RNTI", NaN);
    if usable
        for field = ["CQI","PMI","RI","LI","CRI"]
            rows(i).(field) = iFirstNum(row, field, NaN);
        end
        % Keep the actual installed-table mapping; MCS index alone does not
        % determine modulation across different 38.214 MCS tables.
        rows(i).CQIDerivedMCS = iFirstNum(row, "RawCQIDerivedMCS", NaN);
        rows(i).CQIDerivedModulation = iFirstText(row, "RawCQIDerivedModulation", "");
        rows(i).SubbandCQIVector = iFirstText(row, ["SubbandCQI","subbandCQI"], "");
        rows(i).SubbandPMIVector = iFirstText(row, "SubbandPMI", "");
    end
    rows(i).RankSelectionPolicy = iFirstText(row, ["rank_selection_policy", "RankSelectionPolicy"], "");
    rows(i).RankSelectionSource = iFirstText(row, ["rank_selection_source", "RankSelectionSource"], "");
    rows(i).RankDecisionReason = iFirstText(row, ["rank_decision_reason", "RankDecisionReason"], "");
    rows(i).RankDowngradeApplied = iFirstLogical(row, ["rank_downgrade_applied", "RankDowngradeApplied"], false);
    rows(i).MaxSupportedLayers = iFirstNum(row, ["max_supported_layers", "MaxSupportedLayers"], NaN);
    rows(i).ReportType = "received_CSI_UCI";
    rows(i).ReportQuantity = iFirstText(row, "ReportQuantity", "");
    rows(i).WidebandOrSubband = iFirstText(row, "FrequencyGranularity", "");
    rows(i).MeasurementSource = iFirstText(row, "MeasurementSource", "");
    rows(i).CSIRSResourceId = iFirstNum(row, "CSIRSResourceId", NaN);
    % Numeric UE SINR is not a decoded CQI/PMI/RI wire field. Never recover
    % it from UEReferenceRecordJSON or a scheduler threshold estimate.
    rows(i).CalibrationProfile = iFirstText(row, "CalibrationProfile", "");
    rows(i).RuntimeEvidenceStatus = "independently_received_csi_uci";
    for field = ["ReportIdentity","CSIReportConfigID","CSIUCITransport","DeliveryStatus"]
        rows(i).(field) = iFirstText(row, field, "");
    end
    for field = ["CSIConfigurationEpoch","SourceSlot", ...
            "DueSlot","DeliveredSlot","CSIUCIDecodeOk","CSIUCICRCPass"]
        rows(i).(field) = iFirstNum(row, field, NaN);
    end
end
T = struct2table(rows);
end

function T = iTRSTable(sourceT, meta)
T = iBuildMinimalTable(sourceT, meta, "trs_receiver_tracking_table", { ...
    "SFN", ["Frame"]; "Slot", ["Slot"]; "UEId", ["UEId"]; "CellId", ["ServingCell","TRSAssociatedCell"]; ...
    "TRSResourceId", ["TRSResourceId"]; "Observed", ["TRSProcessed"]; "Consumed", ["TRSProcessed"]; ...
    "TrackingStateBefore", ["TRSTrackingStateBefore"]; "TrackingStateAfter", ["TRSTrackingStateAfter"]; ...
    "TimingEstimateAvailability", ["TimingEstimateAvailability"]; "TimingEstimateSamples", ["TRSTimingEstimate_samples"]; ...
    "CFOEstimateAvailability", ["CFOEstimateAvailability"]; "CFOEstimateHz", ["TRSEstimatedCFO_Hz"]; ...
    "CorrectionLoopStatus", ["TRSReceiverIntegrationStatus"]; "RuntimeEvidenceStatus", ["RuntimeEvidenceStatus","runtime_evidence","TRSRuntimeEvidenceSource"]});
end

function T = iSSBPBCHTable(sourceT, meta)
if ~(istable(sourceT) && ~isempty(sourceT))
    T = table();
    return;
end
rows = repmat(struct("OutputId", "ssb_pbch_cell_search_table", "RunId", iLogicalRunId(meta), "TrialId", NaN, "SFN", NaN, "Slot", NaN, ...
    "CellId", NaN, "SSBIndex", NaN, "BeamIndex", NaN, "PSSDetected", false, "SSSDetected", false, ...
    "NCellIDRecovered", NaN, "PBCHDecodeAttempted", false, "PBCHCRC", "", "MIBRecovered", false, ...
    "RSRP_dB", NaN, "RSRQ_dB", NaN, "SINR_dB", NaN, "RuntimeEvidenceStatus", "", "run_id", meta.run_id, ...
    "producer_module", "sixgr.truth.buildLLSPublicOutputTables", "source_artifact_ref", "", "runtime_evidence", ""), height(sourceT), 1);
for i = 1:height(sourceT)
    row = sourceT(i, :);
    [sinrValue, ~] = iSINR(row);
    crcApplicable = iFirstLogical(row, ["CRCApplicable"], true);
    rows(i).TrialId = i;
    rows(i).SFN = iFirstNum(row, ["Frame","SFN"], NaN);
    rows(i).Slot = iFirstNum(row, ["Slot"], NaN);
    rows(i).CellId = iFirstNum(row, ["CellID","cell_id","BaseStationID","ServingCell"], NaN);
    rows(i).SSBIndex = iFirstNum(row, ["SSBIndex"], NaN);
    rows(i).BeamIndex = iFirstNum(row, ["BeamIndex"], NaN);
    rows(i).PSSDetected = iFirstLogical(row, ["PSSDetected"], false);
    rows(i).SSSDetected = iFirstLogical(row, ["SSSDetected"], false);
    rows(i).NCellIDRecovered = iFirstNum(row, ["NCellIDRecovered","NCellID"], NaN);
    rows(i).PBCHDecodeAttempted = iFirstLogical(row, ["PBCHDecodeAttempted","DecodeAttempted"], true);
    rows(i).PBCHCRC = iCRCOutcome(crcApplicable, iFirstLogical(row, ...
        ["BCHCrcPass","PBCHCRCPass","CRCPass","DecodeSuccess"], false));
    rows(i).MIBRecovered = iFirstLogical(row, ["MIBRecovered","MIBDecoded"], false);
    rows(i).RSRP_dB = iFirstNum(row, ["RSRP_dB"], NaN);
    rows(i).RSRQ_dB = iFirstNum(row, ["RSRQ_dB"], NaN);
    rows(i).SINR_dB = sinrValue;
    rows(i).RuntimeEvidenceStatus = iFirstText(row, ["RuntimeEvidenceStatus","runtime_evidence"], "persisted_runtime_trial_row");
    rows(i).source_artifact_ref = iFirstText(row, ["source_artifact_ref"], "");
    rows(i).runtime_evidence = iFirstText(row, ["runtime_evidence"], "");
end
T = struct2table(rows);
end

function T = iNoiseVarianceTable(publicTables, meta)
parts = { ...
    iNoiseRows(iTable(publicTables, "pdsch_runtime_event_table"), "PDSCH"), ...
    iNoiseRows(iTable(publicTables, "pusch_runtime_event_table"), "PUSCH"), ...
    iNoiseRows(iTable(publicTables, "pucch_uci_table"), "PUCCH"), ...
    iNoiseRows(iTable(publicTables, "srs_measurement_table"), "SRS")};
T = iVertcat(parts);
if isempty(T)
    return;
end
T.OutputId = repmat("noise_variance_evidence_table", height(T), 1);
runIdText = strtrim(string(T.RunId));
missingRunId = ismissing(runIdText) | strlength(runIdText) == 0;
T.RunId(missingRunId) = iLogicalRunId(meta);
T.run_id = repmat(meta.run_id, height(T), 1);
T.producer_module = repmat("sixgr.truth.buildLLSPublicOutputTables", height(T), 1);
T.source_artifact_ref = repmat("reports/csv/noise_variance_evidence_table.csv", height(T), 1);
T.runtime_evidence = repmat("derived_from_runtime_public_tables", height(T), 1);
end

function T = iNoiseRows(sourceT, channelType)
if ~(istable(sourceT) && ~isempty(sourceT))
    T = table();
    return;
end
configuredSNR = iColumnNum(sourceT, ["ConfiguredSNR_dB"]);
appliedSNR = iColumnNum(sourceT, ["AppliedAWGNSNR_dB"]);
if isempty(configuredSNR), configuredSNR = nan(height(sourceT), 1); end
if isempty(appliedSNR), appliedSNR = nan(height(sourceT), 1); end
T = table( ...
    repmat(string(channelType), height(sourceT), 1), iColumnText(sourceT, ["RunId","run_id"]), iColumnNum(sourceT, ["TrialId"]), ...
    iColumnNum(sourceT, ["UEId","ue_id"]), iColumnNum(sourceT, ["CellId","cell_id"]), iColumnNum(sourceT, ["Slot","slot"]), ...
    iColumnNum(sourceT, ["NoiseVar","NoiseVariance"]), iColumnText(sourceT, ["NoiseVarSource"]), iColumnText(sourceT, ["NoiseVarStatus"]), ...
    iColumnText(sourceT, ["NoiseVarReason"]), configuredSNR, appliedSNR, iSNRStatus(configuredSNR, appliedSNR), ...
    iColumnLogical(sourceT, ["ReceiverUsable","DecodeUsable","MeasurementUsable","DetectionUsable"]), iColumnLogical(sourceT, ["StrictFailure","NoiseVarStrictFailure"]), ...
    iColumnText(sourceT, ["RuntimeEvidenceStatus","runtime_evidence"]), iColumnText(sourceT, ["FailureReason"]), ...
    'VariableNames', ["ChannelType","RunId","TrialId","UEId","CellId","Slot","NoiseVar","NoiseVarSource","NoiseVarStatus","NoiseVarReason","ConfiguredSNR_dB","AppliedAWGNSNR_dB","SNRConsistencyStatus","ReceiverUsable","StrictFailure","RuntimeEvidenceStatus","FailureReason"]);
end

function T = iMCSCQITable(sourceT, meta)
if ~(istable(sourceT) && ~isempty(sourceT))
    T = table();
    return;
end
rows = repmat(struct("OutputId", "mcs_cqi_decision_trace_table", "RunId", iLogicalRunId(meta), "TrialId", NaN, ...
    "UEId", NaN, "CellId", NaN, "Slot", NaN, "SelectedMCS", NaN, "SelectedMCSSource", "", ...
    "SelectedMCSReason", "", "CQIDerivedMCS", NaN, "CQI", NaN, "CQISource", "", "CQICalibrationProfile", "", ...
    "LinkAdaptationMode", "", "SchedulerGrantSource", "", "HARQInfluence", "", "OLLAState", "", ...
    "MCSConsistencyBound", NaN, "MCSConsistencyBoundSource", "", ...
    "SelectedSpectralEfficiency", NaN, "BoundSpectralEfficiency", NaN, "MCSConsistencyDetail", "", ...
    "MCSMismatchStatus", "", "MCSMismatchReason", "", "RuntimeEvidenceStatus", "", "run_id", meta.run_id, ...
    "producer_module", "sixgr.truth.buildLLSPublicOutputTables", "source_artifact_ref", "reports/csv/table_mcs_tbs_evolution.csv", ...
    "runtime_evidence", "derived_from_runtime_scheduler_trace"), height(sourceT), 1);
for i = 1:height(sourceT)
    row = sourceT(i, :);
    selected = iFirstNum(row, ["mcs_selected","MCSIndex"], NaN);
    derived = iFirstNum(row, ["CQIDerivedMCS","cqi_derived_mcs"], NaN);
    [bound, boundSource] = iMCSConsistencyBound(row, derived);
    [status, selectedSE, boundSE, detail] = iMCSStatus(row, selected, derived, bound, boundSource);
    rows(i).TrialId = i;
    rows(i).UEId = iFirstNum(row, ["ue_id","UEId"], NaN);
    rows(i).CellId = iFirstNum(row, ["cell_id","CellId"], NaN);
    rows(i).Slot = iFirstNum(row, ["slot","Slot"], NaN);
    rows(i).SelectedMCS = selected;
    rows(i).SelectedMCSSource = iFirstText(row, ["SelectedMCSSource","selected_mcs_source"], "runtime_scheduler_grant");
    rows(i).SelectedMCSReason = iFirstText(row, ["scheduler_reason","GrantReason"], "");
    rows(i).CQIDerivedMCS = derived;
    rows(i).CQI = iFirstNum(row, ["cqi_input","wideband_cqi"], NaN);
    rows(i).CQISource = iFirstText(row, ["CQISource","cqi_source"], "runtime_scheduler_observation");
    rows(i).CQICalibrationProfile = iFirstText(row, ["CalibrationProfile","calibration_profile"], "heuristic");
    rows(i).LinkAdaptationMode = iFirstText(row, ["LinkAdaptationMode","link_adaptation_domain"], "");
    rows(i).SchedulerGrantSource = iFirstText(row, ["SchedulerGrantSource","source_artifact_ref"], "reports/csv/table_mcs_tbs_evolution.csv");
    rows(i).HARQInfluence = iFirstText(row, ["HARQInfluence","harq_state"], "");
    rows(i).OLLAState = iFirstText(row, ["OLLAState","olla_state"], "");
    rows(i).MCSConsistencyBound = bound;
    rows(i).MCSConsistencyBoundSource = boundSource;
    rows(i).SelectedSpectralEfficiency = selectedSE;
    rows(i).BoundSpectralEfficiency = boundSE;
    rows(i).MCSConsistencyDetail = detail;
    rows(i).MCSMismatchStatus = status;
    rows(i).MCSMismatchReason = iMismatchReason(status, rows(i).SelectedMCSReason, rows(i).HARQInfluence);
    rows(i).RuntimeEvidenceStatus = "derived_from_runtime_scheduler_trace";
end
T = struct2table(rows);
end

function T = iMetricUnitRoleCatalog(metricT, meta)
if ~(istable(metricT) && ~isempty(metricT))
    T = table();
    return;
end
T = metricT(:, intersect(["MetricName","Unit","Domain","Meaning","ThreeGPPAnchor","CanBePlotted","LogPlotAllowed","RequiresPositiveValue"], string(metricT.Properties.VariableNames), 'stable'));
T.run_id = repmat(meta.run_id, height(T), 1);
T.producer_module = repmat("sixgr.truth.llsOutputContract", height(T), 1);
end

function T = iRuntimeIssueRegistryTable(sourceT, meta)
if ~(istable(sourceT) && ~isempty(sourceT))
    T = table();
    return;
end
T = sourceT;
T.OutputId = repmat("runtime_issue_registry", height(T), 1);
T.run_id = repmat(meta.run_id, height(T), 1);
T.producer_module = repmat("sixgr.truth.buildLLSPublicOutputTables", height(T), 1);
end

function value = iBitCount(row, names)
value = iFirstNum(row, names, NaN);
if isfinite(value)
    return;
end
txt = iFirstText(row, names, "");
chars = char(txt);
value = sum(chars == '0' | chars == '1');
if value == 0
    value = NaN;
end
end

function status = iSNRStatus(configured, applied)
status = repmat("unavailable", numel(configured), 1);
for i = 1:numel(configured)
    if ~(isfinite(configured(i)) && isfinite(applied(i)))
        continue;
    end
    status(i) = iIf(abs(configured(i) - applied(i)) > 1, "configured_vs_applied_mismatch", "consistent");
end
end

function [bound, source] = iMCSConsistencyBound(row, derived)
bound = NaN;
source = "unavailable";
linkMCS = iFirstNum(row, ["LinkAdaptationMCSIndex", "link_adaptation_mcs", "AdaptedMCSIndex"], NaN);
if isfinite(linkMCS) && iUsesMeasuredFeedbackAdaptation(row)
    bound = double(linkMCS);
    source = "link_adaptation_mcs";
    return;
end
cqiBasedMCS = iFirstNum(row, ["CQIBasedMCS", "cqi_based_mcs"], NaN);
if isfinite(cqiBasedMCS) && iUsesMeasuredFeedbackAdaptation(row)
    ollaAdjustedMCS = iFirstNum(row, ["OLLAAdjustedMCSBeforeCQICeiling", "olla_adjusted_mcs_before_cqi_ceiling"], NaN);
    staticDelta = iFirstNum(row, ["StaticDeltaMCS", "static_delta_mcs"], 0);
    if ~isfinite(staticDelta), staticDelta = 0; end
    if isfinite(ollaAdjustedMCS)
        bound = floor(double(ollaAdjustedMCS) + double(staticDelta));
        source = "olla_required_sinr_adjusted_mcs";
    else
        bound = floor(double(cqiBasedMCS) + double(staticDelta));
        source = "cqi_based_mcs_without_legacy_olla_delta";
    end
    return;
end
if isfinite(derived)
    bound = double(derived);
    source = "cqi_derived_mcs";
end
end

function tf = iUsesMeasuredFeedbackAdaptation(row)
tokens = lower(strjoin([ ...
    iFirstText(row, ["MCSValueStatus", "mcs_value_status"], ""), ...
    iFirstText(row, ["MCSSelectionSource", "mcs_selection_source"], ""), ...
    iFirstText(row, ["MCSIndexAuthority", "mcs_index_authority"], ""), ...
    iFirstText(row, ["GrantOperatingPointSource", "grant_operating_point_source"], ""), ...
    iFirstText(row, ["LinkAdaptationDecisionReason", "link_adaptation_decision_reason"], "")], " "));
tf = contains(tokens, "feedback_adapted") || ...
    contains(tokens, "measured_feedback_adapted") || ...
    contains(tokens, "runtime_link_adaptation_decision");
end

function [status, selectedSE, boundSE, detail] = iMCSStatus(row, selected, derived, bound, boundSource)
selectedSE = NaN;
boundSE = NaN;
detail = "";
if ~isfinite(selected)
    status = "unavailable";
    detail = "missing_selected_mcs";
    return;
end
mcsTable = iFirstText(row, ["MCSTable", "mcs_table", "MCS_Table"], "qam64_table1");
selectedProfile = sixgr.link.resolveMCSProfile(char(mcsTable), selected);
if logical(sixgr.util.structGet(selectedProfile, "Valid", false))
    selectedSE = double(selectedProfile.SpectralEfficiency);
end
if ~isfinite(bound)
    status = "unavailable";
    detail = "selected_mcs_spectral_efficiency_available_bound_mcs_missing";
    return;
end
boundProfile = sixgr.link.resolveMCSProfile(char(mcsTable), bound);
if isfinite(selectedSE) && ...
        logical(sixgr.util.structGet(boundProfile, "Valid", false))
    boundSE = double(boundProfile.SpectralEfficiency);
    if selectedSE <= boundSE + 1e-9
        if isfinite(derived) && abs(double(selected) - double(derived)) < 0.5
            status = "match";
        elseif string(boundSource) == "cqi_derived_mcs"
            status = "match";
        else
            status = "within_link_adaptation_bound";
        end
    else
        status = "mismatch";
    end
    detail = "SelectedSE=" + string(selectedSE) + ";BoundSE=" + string(boundSE) + ";BoundSource=" + string(boundSource);
elseif abs(selected - bound) < 0.5
    status = "match";
    detail = "fallback_mcs_index_match";
else
    status = "mismatch";
    detail = "fallback_mcs_index_mismatch";
end
end

function reason = iMismatchReason(status, selectedReason, harqInfluence)
if status == "match"
    reason = "selected_matches_cqi_derived";
elseif status == "within_link_adaptation_bound"
    reason = "selected_within_sourced_link_adaptation_bound";
elseif status == "unavailable"
    reason = "mcs_consistency_evidence_unavailable";
elseif strlength(string(selectedReason)) > 0
    reason = string(selectedReason);
elseif strlength(string(harqInfluence)) > 0
    reason = "harq_influence:" + string(harqInfluence);
else
    reason = "decision_reason_unavailable";
end
end

function T = iVertcat(parts)
T = table();
for i = 1:numel(parts)
    if istable(parts{i}) && ~isempty(parts{i})
        if isempty(T)
            T = parts{i};
        else
            T = [T; parts{i}]; %#ok<AGROW>
        end
    end
end
end
