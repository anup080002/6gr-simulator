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
% Publication is not a second clock or measurement producer. Frame can be
% a one-based runtime frame/ordinal; it is not an alias for zero-based SFN.
families={"pdsch_runtime_event_table","pdsch_table"; ...
    "pusch_runtime_event_table","pusch_table"; ...
    "pdcch_dci_public_table","pdcch_dci_table"; ...
    "pucch_uci_table","pucch_table"; "prach_detection_table","prach_table"; ...
    "srs_measurement_table","srs_table"; "csi_rs_runtime_event_table","csi_rs_table"; ...
    "trs_receiver_tracking_public_table","trs_receiver_tracking_table"; ...
    "ssb_pbch_cell_search_table","ssb_pbch_table"};
for k=1:size(families,1)
    name=families{k,1};
    tables.(name)=iPreserveClockAndMeasurementColumns(tables.(name),iTable(baseTables,families{k,2}));
end
tables.csi_report_table=iPreserveClockAndMeasurementColumns(tables.csi_report_table,receivedCSIReports);
tables.noise_variance_evidence_table = iNoiseVarianceTable(tables, meta);
tables.mcs_cqi_decision_trace_table = iMCSCQITable(iTable(baseTables, "table_mcs_tbs_evolution"), meta);
tables.lls_output_contract = contract.Outputs;
tables.metric_definition_catalog = contract.Metrics;
tables.metric_unit_role_catalog = iMetricUnitRoleCatalog(contract.Metrics, meta);
tables.runtime_issue_registry = iRuntimeIssueRegistryTable(iTable(baseTables, "result_issue_registry"), meta);
end

function T=iPreserveClockAndMeasurementColumns(T,sourceT)
if isempty(T), return; end
assert(height(T)==height(sourceT),'sixgr:report:PublicProjectionRowMismatch', ...
    'Clock/measurement projection requires the same original row population.');
names=string(sourceT.Properties.VariableNames);
% Explicit unknown SFN remains unknown. In particular do not reconstruct a
% source-observation SFN from a later delivery frame or current configuration.
T.SFN=nan(height(T),1);
fields=["SFN","Frame","SlotConvention","FrameConvention","SFNSource", ...
    "AbsoluteSlot","RuntimeAbsoluteSlotIndex0","CarrierNFrame","CarrierNSlot", ...
    "SourceObservationFrame","SourceObservationSlot","SourceObservationSFN", ...
    "ObservationDeliveryFrame","ObservationDeliverySlot","ObservationDeliverySFN", ...
    "EVMReferenceSource","EVMValueStatus","EVMStatus","EVMSource", ...
    "EVMComputationDomain","EVMEnergyUnit","EVMErrorEnergy","EVMReferenceEnergy", ...
    "EVMSymbolCount","ChannelEstimateSource","CRCApplicable","CRCPass","CRCOutcome"];
for name=fields(ismember(fields,names)), T.(name)=sourceT.(name); end
% Keep original scheduler decision receipts byte-for-byte in the public
% view. Empty source values remain unavailable; publication makes no decision.
decisionFields=startsWith(names,"MCSTransition")|startsWith(names,"ScheduledOperatingPoint")| ...
    ismember(names,["ScheduledMCS","ScheduledMCSIndex","ScheduledModulation","LinkAdaptationScheduled"]);
for name=names(decisionFields), T.(name)=sourceT.(name); end
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

function [evmPercent, evmSource, conversionSource] = iEVMPercent(row)
evmPercent = NaN;
% Measurement reference and mathematical unit conversion are different facts.
evmSource = iFirstText(row,["EVMReferenceSource","EVMSource"],"");
conversionSource = "unavailable_no_explicit_EVM_unit";
evmPct = iFirstNum(row, ["EVM_percent","EVM_rms_percent"], NaN);
if isfinite(evmPct) && evmPct >= 0
    evmPercent = evmPct;
    conversionSource = "explicit_percent";
    return;
end
evmRaw = iFirstNum(row, "EVM_rms", NaN);
if isfinite(evmRaw) && evmRaw >= 0
    % Fractional RMS error can exceed one. Its magnitude does not change
    % the unit: EVM_rms=1.5 is 150%, not 1.5%.
    evmPercent = 100 * evmRaw;
    conversionSource = "fractional_rms_times_100";
    return;
end
if any(ismember(["EVM","PostEqEVM"],string(row.Properties.VariableNames)))
    % Legacy unqualified field names are not a unit declaration. The
    % original producer must supply fractional RMS or explicit percent.
    conversionSource = "unavailable_ambiguous_legacy_EVM_unit";
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
    "EVM_dB", NaN, "EVM_percent", NaN, "EVMSource", "", "EVMUnitConversionSource", "", "SINR_dB", NaN, "SINRSource", "", "SINRValueRole", "", ...
    "SINRValueStatus", "", ...
    "CRCApplicable", false, "CRCPass", NaN, "DecodeAttempted", false, "DecodeUsable", false, ...
    "HARQProcessId", NaN, "NDI", NaN, "RV", NaN, "TPMI", NaN, "AppliedPrecoderPMI", NaN, ...
    "AppliedPrecoderSource", "", "AppliedBeamIndexSet", "", "BeamIndexSetMaterialized", false, ...
    "TransformPrecodingEnabled", false, "UCIOnPUSCHFlag", NaN, "RuntimeEvidenceStatus", "", ...
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
    [evmPercent, evmSource, evmConversionSource] = iEVMPercent(row);
    evmDb = iFirstNum(row, ["EVM_dB"], NaN);
    if ~isfinite(evmDb) && isfinite(evmPercent) && evmPercent > 0
        evmDb = 20 * log10(evmPercent / 100);
    end
    crcApplicable = iFirstLogical(row, ["CRCApplicable"], channelType ~= "PUCCH");
    rows(i).TrialId = i;
    rows(i).SFN = iFirstNum(row, "SFN", NaN);
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
    rows(i).ChannelEstimationSource = iFirstText(row, ["ChannelEstimateSource", "ChannelEstimationSource", "ChannelEstimatorType"], "");
    rows(i).EqualizerType = iFirstText(row, ["EqualizerType"], "");
    rows(i).EVM_dB = evmDb;
    rows(i).EVM_percent = evmPercent;
    rows(i).EVMSource = evmSource;
    rows(i).EVMUnitConversionSource = evmConversionSource;
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
    rows(i).RuntimeEvidenceStatus = iFirstText(row, ["RuntimeEvidenceStatus", "runtime_evidence"], "persisted_runtime_trial_row");
    rows(i).FailureReason = iFirstText(row, ["FailureReason"], "");
    rows(i).source_artifact_ref = iFirstText(row, ["source_artifact_ref"], "");
    rows(i).runtime_evidence = iFirstText(row, ["runtime_evidence"], "");
end
T = struct2table(rows);
if channelType ~= "PUSCH"
    T(:, intersect(["TPMI","AppliedPrecoderPMI","AppliedPrecoderSource","AppliedBeamIndexSet","BeamIndexSetMaterialized","TransformPrecodingEnabled","UCIOnPUSCHFlag"], string(T.Properties.VariableNames), 'stable')) = [];
end
if channelType == "PUSCH"
    % Keep accepted spatial computation A distinct from newest raw sounding
    % B and from the SRI associated with the scheduled transmission. These
    % are owner-provided facts, not decisions made by this public projection.
    names=string(sourceT.Properties.VariableNames);
    retained=names(startsWith(names,"AcceptedSRS")|startsWith(names,"RawSRS")| ...
        startsWith(names,"SweepAggregate")|ismember(names,[ ...
        "ScheduledSRI","ScheduledSRSResourceIndicator","GrantContextId","FrozenGrantContextId", ...
        "AppliedPrecoderMatrixSHA256","RequestedPrecoderSHA256","AppliedPrecoderSHA256","PrecoderDigestDomain", ...
        "SRSCausalMeasurementId","SRSCausalUsable","SRSCausalAgeSlots","SRSCausalStatus", ...
        "SRSValid","LastSuccessfulSRSSlot","SRSAgeSlots", ...
        "SRSCurrentInstallationJSON","SRSCurrentInstallationSHA256", ...
        "ExecutionID","ConfigHash","ScenarioID","RunFolder","RunTag","SourceRunID", ...
        "RandomSeed","ChannelSeed","SweepPointIndex","ObservationID", ...
        "ReceiverID","ReceiverWindowID","ReceiverClockDomain","ReceiverClockEpoch", ...
        "ObservationStartSample","ObservationEndSampleExclusive","ObservationSampleRateHz","ReceiverObservationSHA256"]));
    for name=retained, T.(name)=sourceT.(name); end
    if ~ismember("SourceRunID",names) && ismember("RunID",names), T.SourceRunID=sourceT.RunID; end
end
if channelType == "PDSCH"
    % Completion evidence is produced after actual shared RX/TX commits.
    % This projection must not promote a frozen grant or reconstruct CSI.
    names=string(sourceT.Properties.VariableNames);
    retained=names(startsWith(names,"CompletedCSIApplication")|ismember(names,[ ...
        "GrantContextId","FrozenGrantContextId","ReceivedAssignmentDigest", ...
        "ExecutionID","ConfigHash","ScenarioID","RunFolder","RunTag","SourceRunID", ...
        "RandomSeed","ChannelSeed","SweepPointIndex","ObservationID", ...
        "ReceiverID","ReceiverWindowID","ReceiverClockDomain","ReceiverClockEpoch", ...
        "ObservationStartSample","ObservationEndSampleExclusive","ObservationSampleRateHz", ...
        "ReceiverObservationSHA256"]));
    for name=retained, T.(name)=sourceT.(name); end
    if ~ismember("SourceRunID",names) && ismember("RunID",names), T.SourceRunID=sourceT.RunID; end
end
% Mapping/power receipts are already bound to the completed TX by the
% producer. Copy exact values and unknowns; do not recompute them from rank,
% antenna counts or a current YAML configuration at publication time.
names=string(sourceT.Properties.VariableNames);
retained=names(startsWith(names,"DataMapping")|startsWith(names,"DataAntenna")| ...
    startsWith(names,"DataWaveform")|startsWith(names,"FrozenData")| ...
    startsWith(names,"SharedStreamProjection")|ismember(names,[ ...
    "NumLogicalPorts","PrecodingNumLogicalPorts","NumPhysicalElements", ...
    "FrozenNumRFChains","SharedStreamAdditionalProjectionApplied"]));
for name=retained, T.(name)=sourceT.(name); end
T=iPreserveReceiverAuthorityColumns(T,sourceT);
if channelType == "PDSCH"
    % Final decoder receipts belong to the completed throughput owner. This
    % adapter preserves their original bytes/types, including negative and
    % absent outcomes; it does not turn a receipt into statistical evidence
    % or infer an individual codeword CRC from the aggregate row verdict.
    % The separate shared-completion binding does not replace/re-sign the
    % decoder capsule or imply unique delivery from a successful CRC.
    finalFields=["DLSCHFinalOutcomeAvailable","DLSCHFinalOutcomeStage", ...
        "DLSCHFinalOutcomeJSON","DLSCHFinalOutcomeSHA256", ...
        "DLSCHSuccessfulDecodedBits","DLSCHSuccessfulDecodedBitsScope", ...
        "DLSCHAggregateGoodBitsPolicy", ...
        "SharedDLSCHOutcomeAvailable","SharedDLSCHOutcomeStage", ...
        "SharedDLSCHOutcomeJSON","SharedDLSCHOutcomeSHA256", ...
        "SharedDLSCHOutcomeTransmissionID","SharedDLSCHOutcomeDecoderSHA256", ...
        "SharedDLSCHOutcomeTransportCreditBound"];
    retained=finalFields(ismember(finalFields,string(sourceT.Properties.VariableNames)));
    for name=retained, T.(name)=sourceT.(name); end
end
if channelType == "PUSCH", T=iProjectPUSCHUCIProcessing(T,sourceT); end
end

function T=iProjectPUSCHUCIProcessing(T,sourceT)
% Processing applicability/execution is not payload presence or decode
% success. Preserve raw producer facts and legacy planes without alias OR.
definition="receiver_uci_processing_applied_not_presence_or_decode_success";
names=string(sourceT.Properties.VariableNames);
raw=["UCIOnPUSCHApplied","UCIOnPUSCHSource","UCIOnPUSCHEvidenceSource", ...
    "PartialReception","CSIPresenceResolved","CSIReportDetected","CSIPart1Usable"];
for name=raw(ismember(raw,names)), T.(name)=sourceT.(name); end
legacy=["UCIOnPUSCHFlag","UCIOnPUSCHFlagDefinition","UCIOnPUSCHFlagSource","UCIOnPUSCHFlagStatus"];
for name=legacy
    inputName="Input"+name;
    if ismember(inputName,names), T.(inputName)=sourceT.(inputName); end
    if ~ismember(name,names), continue; end
    assert(~ismember(inputName,names) || isequaln(sourceT.(inputName),sourceT.(name)), ...
        'sixgr:truth:PUSCHUCIApplicabilityConflict', ...
        'Cannot overwrite a distinct original %s evidence column.',inputName);
    T.(inputName)=sourceT.(name);
end
T.UCIOnPUSCHFlag=nan(height(T),1);
T.UCIOnPUSCHFlagDefinition=repmat(definition,height(T),1);
T.UCIOnPUSCHFlagSource=strings(height(T),1);
T.UCIOnPUSCHFlagStatus=repmat("unavailable_receiver_processing_not_recorded",height(T),1);
for k=1:height(T)
    row=sourceT(k,:);
    [applied,hasApplied]=iUCIProcessingValue(row,"UCIOnPUSCHApplied");
    [legacyValue,hasLegacy]=iUCIProcessingValue(row,"UCIOnPUSCHFlag");
    [qualified,reason]=iUCIProcessingSource(row,applied, ...
        iFirstText(row,"UCIOnPUSCHSource",""));
    legacySource=iFirstText(row,"UCIOnPUSCHFlagSource","");
    samePlane=iFirstText(row,"UCIOnPUSCHFlagDefinition","")==definition;
    % Legacy authority is its explicit definition plus its own source, not
    % the raw Applied evidence marker (which describes a different fact).
    legacyQualified=samePlane && hasLegacy && iUCIProcessingSource(row,legacyValue,legacySource,false);
    if hasApplied
        assert(~(qualified && legacyQualified && applied~=legacyValue), ...
            'sixgr:truth:PUSCHUCIApplicabilityConflict', ...
            'Contradictory qualified receiver-processing facts in PUSCH row %d.',k);
        T.UCIOnPUSCHFlagStatus(k)=reason;
        if qualified
            T.UCIOnPUSCHFlag(k)=applied;
            T.UCIOnPUSCHFlagSource(k)=iFirstText(row,"UCIOnPUSCHSource","");
        end
    elseif legacyQualified
        T.UCIOnPUSCHFlag(k)=legacyValue;
        T.UCIOnPUSCHFlagSource(k)=legacySource;
        T.UCIOnPUSCHFlagStatus(k)="qualified_same_plane_legacy_receiver_processing";
    elseif hasLegacy
        T.UCIOnPUSCHFlagStatus(k)="unqualified_legacy_processing_plane_or_source";
    end
end
end

function [value,present]=iUCIProcessingValue(row,name)
present=ismember(name,string(row.Properties.VariableNames)); value=NaN;
if ~present, return; end
raw=row.(name);
if iscell(raw) && isscalar(raw), raw=raw{1}; end
if isempty(raw), return; end
if ischar(raw), raw=string(raw); end
if isstring(raw) && isscalar(raw)
    token=lower(strtrim(raw));
    if ismissing(token) || any(token==["","nan","<missing>"]), return; end
    if token=="true", raw=1; elseif token=="false", raw=0; else, raw=str2double(token); end
    assert(~isnan(raw),'sixgr:truth:InvalidPUSCHUCIProcessingValue', ...
        '%s must contain a binary or explicitly unavailable scalar.',name);
end
assert((isnumeric(raw) || islogical(raw)) && isreal(raw) && isscalar(raw) && ...
    (isnan(raw) || raw==0 || raw==1),'sixgr:truth:InvalidPUSCHUCIProcessingValue', ...
    '%s must contain a binary or explicitly unavailable scalar.',name);
value=double(raw);
end

function [qualified,reason]=iUCIProcessingSource(row,value,source,requirePositiveEvidence)
if nargin<4, requirePositiveEvidence=true; end
qualified=false;
if ~isfinite(value), reason="unavailable_applied_value"; return; end
% Exact emitted sources, including explicitly named component/research
% paths. None is upgraded to an independent-receiver or waveform claim.
receiverSources=["nrULSCHDemultiplex_nrUCIDecode_independent_receive_schema", ...
    "nrULSCHDemultiplex_nrUCIDecode_typed_payload", ...
    "experimental_explicit_Qm_UCI_typed_payload_component", ...
    "experimental_explicit_Qm_UCI_independent_receive_schema", ...
    "nrULSCHDemultiplex_nrUCIDecode_receive_schema_core", ...
    "independent_CSI_presence_interpretations_and_received_ULSCH_CRC", ...
    "received_LLR_with_configured_invariant_resource_mapping"];
if source=="no_uci_payload_requested"
    % TX and RX share this token; only the actual returned-RX annotation
    % disambiguates the explicit no-processing case.
    qualified=value==0 && ...
        iFirstText(row,"RuntimeEvidenceSource","")=="sixgr.link.runULPUSCHThroughput_returned_receiver" && ...
        iFirstText(row,"RuntimeMaterializationStatus","")=="active_waveform_pusch_runtime";
    reason="unqualified_shared_no_payload_source_without_returned_receiver";
elseif any(source==receiverSources)
    qualified=value==0 || ~requirePositiveEvidence || ...
        iFirstText(row,"UCIOnPUSCHEvidenceSource","")=="same_waveform_pusch_rx_uci_demultiplexer";
    reason="unqualified_positive_processing_evidence";
else
    reason="unqualified_applied_source";
end
if qualified, reason="qualified_receiver_processing_applied"; end
if qualified && value==0, reason="qualified_receiver_processing_not_applied"; end
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
    "SFN", "SFN"; "Slot", ["Slot"]; "UEId", ["UEIndex","UEID","UE","RNTI"]; "RNTI", ["RNTI"]; ...
    "CORESETId", ["CORESETId"]; "SearchSpaceId", ["SearchSpaceId"]; "AggregationLevel", ["AggregationLevel"]; ...
    "CandidateIndex", ["CandidateIndex"]; "CCEStart", ["CCEStart"]; "CCELength", ["CCELength"]; ...
    "DCIFormat", ["DCIFormat"]; "DCIPayloadBits", ["DCIPayloadBits","PayloadBits"]; "RNTIType", ["RNTIType"]; ...
    "BlindDecodeAttempted", ["BlindDecodeAttempted","DecodeAttempted"]; "DetectionMetric", ["DetectionMetric"]; ...
    "CRCApplicable", ["CRCApplicable"]; "CRCPass", ["CRCPass","DecodeSuccess"]; "FalseAlarmFlag", ["FalseAlarmFlag"]; ...
    "MissedDetectionFlag", ["MissedDetectionFlag"]; "LinkedGrantId", ["LinkedGrantId"]; "LinkedPDSCHOrPUSCH", ["LinkedPDSCHOrPUSCH"]; ...
    "RuntimeEvidenceStatus", ["RuntimeEvidenceStatus","runtime_evidence"]});
T=iPreserveReceiverAuthorityColumns(T,sourceT);
T=iPreserveControlFrequencyColumns(T,sourceT);
end

function T=iPreserveControlFrequencyColumns(T,sourceT)
% Original receiver values/receipt, never inferred from configured RF CFO.
if isempty(T), return; end
fields=["EstimatedCFO_Hz","EstimatedCommonFrequency_Hz","CFOEstimateSource", ...
    "CFOEstimateAvailable","CFOCorrectionEnabled", ...
    "CFOCorrectionApplied","CFOCorrectionApplied_Hz","CFOCorrectionSource", ...
    "CFOCorrectionSampleOrigin","CFOCorrectionAbsoluteSampleOrigin", ...
    "CFOCorrectionClockSource","ResidualCFOEstimatorConsistency_Hz", ...
    "ResidualCFOEstimateRole","ResidualCFOReusesAcquisitionObservation", ...
    "ResidualCFOEstimateAvailable","FrequencyEstimateDomain","FrequencyCorrectionStatus", ...
    "ReceiverFrequencyEvidenceJSON","ReceiverFrequencyEvidenceSHA256"];
for name=fields(ismember(fields,string(sourceT.Properties.VariableNames)))
    T.(name)=sourceT.(name);
end
end

function T=iPreserveReceiverAuthorityColumns(T,sourceT)
% Optional owner-provided evidence, not a second admission/coverage policy.
% Preserve explicit false, unknown NaN, strings and row order exactly. A
% missing producer field stays absent unless the existing public schema
% already declares it; never infer receiver execution from another column.
if isempty(T), return; end
fields=["Status","Crash","FailureReason","ReceiverUsable", ...
    "DecodeAttempted","DecodeUsable","CRCApplicable","CRCPass", ...
    "ChannelEstimateAttempted","ChannelEstimateAvailable","ChannelEstimateSource", ...
    "ResourceExtractionAttempted","ResourceExtractionAvailable", ...
    "EqualizationAttempted","EqualizationAvailable", ...
    "DLSCHDecodeAttempted","DLSCHDecodeAvailable", ...
    "ULSCHDecodeAttempted","ULSCHDecodeAvailable","LLRAvailable","LLRFinite", ...
    "NoiseVarStrictFailure","StrictReceiverEvidenceOk","StrictOk","TruthStatus", ...
    "PostEqSINRAvailable","PostEqSINRReceiverDerived","SINRValidationStatus", ...
    "DetectionApplicable","DetectionAttempted","DetectionSuccess","DetectionUsable", ...
    "DetectionStatus","DetectionSource", ...
    "MeasurementApplicable","MeasurementAttempted","MeasurementUsable", ...
    "MeasurementStatus","MeasurementSource","MeasurementDefinition", ...
    "MeasurementValue_dB","MeasurementValueRole","MeasurementValueStatus", ...
    "MeasurementSummarySource","MeasurementAttemptKnown", ...
    "ChannelModelApplied","ChannelFadingApplied","ChannelFadingExecutionStatus", ...
    "ChannelExecutionEvidenceAvailable","ChannelExecutionEvidenceStatus","ChannelExecutionEvidenceSource", ...
    "ChannelExecutionTransmitterID","ChannelExecutionReceiverID","ChannelExecutionLinkID", ...
    "ChannelExecutionStartSample","ChannelExecutionEndSampleExclusive", ...
    "ChannelExecutionSampleRateHz","ChannelExecutionConfigurationEpoch", ...
    "ChannelExecutionSegmentCount","ChannelExecutionDesiredSegmentCount", ...
    "PDCCHReceiverDecodeOk","PDCCHDataAdmissionOk","PDCCHTCIAdmissionStatus", ...
    "CountsTowardCoverage","PartialRowFlag","FinalizedFlag","IsWarmupFrame", ...
    "PrimaryTruthValueStatus","RowLifecycleState","NAReason","FallbackFlag","PlaceholderFlag", ...
    "RuntimeMaterializationStatus","RuntimeEvidenceSource","RuntimeEvidenceStatus"];
retained=fields(ismember(fields,string(sourceT.Properties.VariableNames)));
for name=retained, T.(name)=sourceT.(name); end
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
    rows(i).SFN = iFirstNum(row, "SFN", NaN);
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
% Post-reception scoring is audit evidence, never a receiver input. Preserve
% the retained identity/value representation rather than reconstructing H0
% from DTX, CRC, receive-only intent, or missing transmitter metadata.
numericFields=["SignalPresent","FalseAlarmFlag","FalseAcceptanceFlag", ...
    "DetectionMetricValid","DetectionThreshold","PresenceConfigurationEpoch", ...
    "PresenceTXStartSample","PresenceTXEndSampleExclusive", ...
    "PresenceRXStartSample","PresenceRXEndSampleExclusive","PresenceSampleRateHz", ...
    "PresenceTargetNonzeroInputSamples","PresenceObservationCount", ...
    "PresenceUEIndex","PresenceRNTI","PresenceServingCell", ...
    "PresenceIndependentTrialsEstablished","PresenceScoringUsedByReceiver", ...
    "ObservationStartSample","ObservationEndSampleExclusive","ObservationSampleRateHz", ...
    "ReceiverExpectedBitCount","ReceiverExpectedHARQBitCount","ReceiverExpectedSRBitCount", ...
    "ReceiverExpectedCSIPart1BitCount","ReceiverExpectedCSIPart2BitCount"];
numericFields=[numericFields "DecodeAttempted" "DTXDecisionAvailable"];
textFields=["TrialType","DetectionMetricSource","DetectionThresholdSource", ...
    "DetectionThresholdMode","PresenceScoringStatus","PresenceScoringSource", ...
    "PresenceObservationID","PresenceReceiverAssignmentDigest","PresenceReceiverContextDigest", ...
    "PresenceReceiverBackground","PresenceReceiverSchemaDigest","PresenceReceiverResourceDigest", ...
    "PresenceEvidenceJSON","PresenceEvidenceSHA256","PresenceNonzeroCountUnit", ...
    "PresencePhysicalOccasionID","ReceiverAssignmentDigest","ReceiverContextDigest"];
textFields=[textFields "ReceiverExecutionStatus" "ReceiverUnavailableReason" "FeedbackDisposition"];
for name=numericFields
    T.(name)=nan(height(T),1);
    if ismember(name,string(sourceT.Properties.VariableNames)), T.(name)=sourceT.(name); end
end
for name=textFields
    T.(name)=repmat("",height(T),1);
    if ismember(name,string(sourceT.Properties.VariableNames)), T.(name)=sourceT.(name); end
end
for name=string(sourceT.Properties.VariableNames)
    if startsWith(name,"Presence"), T.(name)=sourceT.(name); end
end
T=iPreserveControlFrequencyColumns(T,sourceT);
end

function T = iPRACHTable(sourceT, meta)
T = iBuildMinimalTable(sourceT, meta, "prach_detection_table", { ...
    "SFN", "SFN"; "Slot", ["Slot"]; "CellId", ["CellId","CellID","cell_id","ServingCell"]; "UEId", ["UEId","UEIndex","UEID","UE"]; ...
    "PRACHFormat", ["PRACHFormat"]; "RestrictedSet", ["RestrictedSet"]; "TimeIndex", ["TimeIndex"]; ...
    "CorrelationPeak", ["CorrelationPeak","peak_value","DetectionMetric"]; "DetectionThreshold", ["DetectionThreshold"]; ...
    "Detected", ["Detected","DecodeSuccess","CRCPass"]; "MissedDetection", ["MissedDetection"]; "FalseAlarm", ["FalseAlarm","FalseAlarmFlag"]; ...
    "CollisionDetected", ["CollisionDetected"]; "TimingOffsetSamplesRaw", ["RawTimingEstimate_samples","TimingOffsetSamplesRaw"]; ...
    "TimingOffsetSamplesApplied", ["AppliedTimingCorrection_samples","TimingOffsetSamplesApplied"]; ...
    "AccessDelay_ms", ["AccessDelay_ms"]; "ProcedureDelay_ms", ["ProcedureDelay_ms"]; ...
    "RAResponseWindow_slots", ["RAResponseWindow_slots"]; "ContentionResolutionTimer_slots", ["ContentionResolutionTimer_slots"]; ...
    "SlotDuration_ms", ["SlotDuration_ms"]; "AirInterfaceObservation_ms", ["AirInterfaceObservation_ms"]; ...
    "RuntimeEvidenceStatus", ["RuntimeEvidenceStatus","runtime_evidence"]});
if isempty(T), return; end
% Consume the original producer names without confusing an opaque occasion
% identity with an ordinal, or a transmitted preamble with a detected one.
aliases={"RA_RNTI",["RA_RNTI","RARNTI"]; ...
    "FrequencyIndex",["FrequencyIndex","PRACHFrequencyIndex"]; ...
    "PreambleIndex",["PreambleIndex","preamble_id"]; ...
    "ConfigurationIndex",["ConfigurationIndex","PRACHConfigurationIndex"]; ...
    "RootSequenceIndex",["RootSequenceIndex","root_sequence_index","PRACHRootSequenceIndex"]; ...
    "ZeroCorrelationZone",["ZeroCorrelationZone","ZeroCorrelationZoneConfig","PRACHZeroCorrelationZone"]; ...
    "OccasionIndex",["OccasionIndex","PRACHOccasionIndex","prach_occasion_id"]};
for k=1:size(aliases,1)
    T.(aliases{k,1})=nan(height(T),1);
    for j=1:height(T)
        T.(aliases{k,1})(j)=iPRACHNumericAlias(sourceT(j,:),aliases{k,2});
    end
end
T.OccasionID=strings(height(T),1);
for j=1:height(T)
    T.OccasionID(j)=iPRACHTextAlias(sourceT(j,:),["OccasionID","PRACHOccasionID"]);
end
% Additive original lineage only: absent historical columns stay absent.
% RA endpoint/attempt identities are not aliases for runtime UE ordinals.
names=string(sourceT.Properties.VariableNames);
fields=names(startsWith(names,"AssociatedSSB")|startsWith(names,"SIB1RACH")| ...
    startsWith(names,"PRACH")|startsWith(names,"SelectedSSBTiming")| ...
    startsWith(names,"SweepAggregate")|ismember(names,[ ...
    "RunId","RunID","ExecutionID","ConfigHash","ScenarioID","SweepPointIndex", ...
    "ConfiguredSNR_dB","ReceiverID","ObservationID","ReceiverObservationSHA256", ...
    "ObservationStartSample","ObservationEndSampleExclusive","ObservationSampleRateHz", ...
    "ResultAvailableAtSample","SampleRateHz","ClockEpoch", ...
    "RARunId","RAScenarioName","RACellId","RAUEId","RAAttemptId","AttemptId", ...
    "RAProcedureType","RABindingSource","RASlotTimeBase","Msg1ScheduledSlot", ...
    "RACHConfigHash","Msg1BeamPolicy","SSBToPRACHAssociationApplied", ...
    "RARNTI","PreambleIndexTx","PreambleIndexDetected","RequestedPreambleIndex", ...
    "DetectedPreambleIndex","DetectedPreambleSet","DetectedPreambleSetAvailable", ...
    "DetectionPopulationScope","MissedDetectionSource","FalseAlarmStatus", ...
    "PreambleDetectionMetric","PreambleDetectionThreshold","PreambleDetectionThresholdSource", ...
    "PreambleDetectionThresholdMode","PreambleDetectionThresholdCalibrationStatus", ...
    "TimingReferenceSource","TimingScoringReferenceJSON","TimingSampleRate_Hz", ...
    "TimingAdvanceRole","RFStageEvidenceArtifact","RuntimeEvidenceStatus"]));
for name=fields, T.(name)=sourceT.(name); end
T.PRACHProjectionScope=repmat( ...
    "original_row_projection_not_association_or_gnb_occasion_verification",height(T),1);
T.PRACHProjectionIndexScope=repmat( ...
    "preamble_frequency_ssb_indices_zero_based;occasion_id_opaque;frame_slot_use_original_convention",height(T),1);
% runPRACHDetection uses PreambleIndex for the detected index; the RA
% continuation uses it for transmitted identity. Keep that legacy value,
% but never silently select a TX or RX meaning for absent/other producers.
T.PreambleIndexRole=repmat("legacy_producer_defined;use_original_role_specific_preamble_fields",height(T),1);
if ismember("SSBToPRACHAssociationApplied",names)
    T.SSBToPRACHAssociationAppliedScope=repmat( ...
        "legacy_selected_ssb_metadata_not_validated_ro_or_preamble_association",height(T),1);
end
end

function value=iPRACHNumericAlias(row,names)
value=NaN;
for name=names
    if ~ismember(name,string(row.Properties.VariableNames)), continue; end
    raw=row.(name);
    if (isstring(raw)&&isscalar(raw)&&(ismissing(raw)||strlength(strtrim(raw))==0))|| ...
            (ischar(raw)&&isempty(raw)), continue; end
    assert(isnumeric(raw)&&isreal(raw)&&isscalar(raw), ...
        'sixgr:report:PRACHProvenanceType','%s must be one original numeric identity, not cast text.',name);
    if isnan(raw), continue; end
    if isinteger(raw)
        assert(raw<=cast(flintmax,'like',raw),'sixgr:report:PRACHProvenanceValue', ...
            '%s exceeds exact public numeric identity representation.',name);
    end
    candidate=double(raw);
    assert(isfinite(candidate)&&candidate>=0&&candidate<=flintmax&&candidate==fix(candidate), ...
        'sixgr:report:PRACHProvenanceValue','%s must be an exact nonnegative integer or unavailable.',name);
    assert(isnan(value)||value==candidate,'sixgr:report:PRACHProvenanceConflict', ...
        'Conflicting original PRACH aliases for %s.',names(1));
    value=candidate;
end
end

function value=iPRACHTextAlias(row,names)
value="";
for name=names
    if ~ismember(name,string(row.Properties.VariableNames)), continue; end
    raw=row.(name);
    if isnumeric(raw)&&isreal(raw)&&isscalar(raw)&&isnan(raw), continue; end
    assert((ischar(raw)&&(isrow(raw)||isempty(raw)))||isstring(raw)||iscellstr(raw), ...
        'sixgr:report:PRACHProvenanceType','%s must be original text, not numeric casting.',name);
    candidate=string(raw);
    assert(isscalar(candidate),'sixgr:report:PRACHProvenanceType','%s must be scalar text.',name);
    if ismissing(candidate)||strlength(strtrim(candidate))==0, continue; end
    assert(strlength(value)==0||value==candidate,'sixgr:report:PRACHProvenanceConflict', ...
        'Conflicting original PRACH aliases for %s.',names(1));
    value=candidate;
end
end

function T = iSRSTable(sourceT, meta)
if ~(istable(sourceT) && ~isempty(sourceT))
    T = table();
    return;
end
rows = repmat(struct("OutputId", "srs_measurement_table", "RunId", iLogicalRunId(meta), "TrialId", NaN, "SFN", NaN, "Slot", NaN, ...
    "UEId", NaN, "RNTI", NaN, "SRSResourceId", NaN, "SRSResourceSetId", NaN, "NumPorts", NaN, "CombSize", NaN, ...
    "CyclicShift", NaN, "SequenceId", NaN, "Bandwidth", NaN, "StartRB", NaN, "ChannelEstimateAvailable", false, ...
    "NMSE_dB", NaN, "RawChannelNMSE_dB", NaN, "NMSEQualificationMode", "", ...
    "ChannelNMSEPhaseAligned", false, "ChannelNMSEGainFitted", false, ...
    "ChannelNMSECommonPhaseRotation_rad", NaN, "NMSEReferenceSource", "", ...
    "PreRXClockChannelNMSE_dB", NaN, "ChannelNMSEReferencePlane", "", ...
    "ChannelNMSEReceiverTimingIncluded", NaN, "ChannelNMSERecordedReceiverTimingOffset_samples", NaN, ...
    "ChannelNMSEReceiverCFOIncluded", NaN, "ChannelNMSEExecutedReceiverCFO_Hz", NaN, ...
    "ResidualTimingOffset_samples", NaN, "CaptureExtractionOffset_samples", NaN, ...
    "ExpectedCaptureOffset_samples", NaN, "ExpectedReceiveCenterSample", NaN, "TimingSource", "", ...
    "RSRP_dB", NaN, "SINR_dB", NaN, "NoiseVar", NaN, "NoiseVarSource", "", "NoiseVarStatus", "", ...
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
    rows(i).SFN = iFirstNum(row, "SFN", NaN);
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
    rows(i).RawChannelNMSE_dB = iFirstNum(row, ["RawChannelNMSE_dB"], NaN);
    rows(i).NMSEQualificationMode = iFirstText(row, ["ChannelNMSEQualificationMode"], "");
    rows(i).ChannelNMSEPhaseAligned = iFirstLogical(row, ["ChannelNMSEPhaseAligned"], false);
    rows(i).ChannelNMSEGainFitted = iFirstLogical(row, ["ChannelNMSEGainFitted"], false);
    rows(i).ChannelNMSECommonPhaseRotation_rad = iFirstNum(row, ["ChannelNMSECommonPhaseRotation_rad"], NaN);
    rows(i).NMSEReferenceSource = iFirstText(row, ["NMSEReferenceSource"], "");
    % Preserve the scored plane, not an inferred receiver estimate. These
    % nullable flags distinguish absent legacy evidence from recorded zero.
    rows(i).PreRXClockChannelNMSE_dB = iFirstNum(row, ["PreRXClockChannelNMSE_dB"], NaN);
    rows(i).ChannelNMSEReferencePlane = iFirstText(row, ["ChannelNMSEReferencePlane"], "");
    rows(i).ChannelNMSEReceiverTimingIncluded = iFirstNum(row, ["ChannelNMSEReceiverTimingIncluded"], NaN);
    rows(i).ChannelNMSERecordedReceiverTimingOffset_samples = iFirstNum(row, ["ChannelNMSERecordedReceiverTimingOffset_samples"], NaN);
    rows(i).ChannelNMSEReceiverCFOIncluded = iFirstNum(row, ["ChannelNMSEReceiverCFOIncluded"], NaN);
    rows(i).ChannelNMSEExecutedReceiverCFO_Hz = iFirstNum(row, ["ChannelNMSEExecutedReceiverCFO_Hz"], NaN);
    rows(i).ResidualTimingOffset_samples = iFirstNum(row, ...
        ["SRSReceiveTimingOffset_samples","TimingOffset_samples"], NaN);
    rows(i).CaptureExtractionOffset_samples = iFirstNum(row, ...
        ["SRSCaptureExtractionOffset_samples","AppliedTimingCorrection_samples"], NaN);
    rows(i).ExpectedCaptureOffset_samples = iFirstNum(row, ...
        ["SRSExpectedCaptureOffset_samples"], NaN);
    rows(i).ExpectedReceiveCenterSample = iFirstNum(row, ...
        ["SRSExpectedReceiveCenterSample"], NaN);
    rows(i).TimingSource = iFirstText(row, ...
        ["SRSReceiveTimingSource","TimingEstimateSource"], "");
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
% Raw receiver observations retain their own source identity. Never attach
% the latest accepted tuple to an older/newer raw observation by slot alone.
T.SRSMeasurementEvidenceRole=repmat("raw_receiver_srs_measurement_not_accepted_spatial_decision",height(T),1);
names=string(sourceT.Properties.VariableNames);
retained=names(startsWith(names,"SweepAggregate")|startsWith(names,"SRSAbsolutePower")| ...
    startsWith(names,"SRS_RSRP_")|startsWith(names,"SRSRSRP")|ismember(names,[ ...
    "MeasurementId","MeasurementID","ObservationID","ResourceID","ResourceSetID", ...
    "SRSConfigurationContextID","SRSNumPorts", ...
    "SRSConfigurationContextVersion","SRSConfigurationEpoch","SRSResourceID","SRSResourceIDsJSON", ...
    "MeasurementSource","ProducerSlot","AvailableSlot","MeasurementClockDomain","MeasurementClockEpoch", ...
    "ObservationStartSample","ObservationEndSampleExclusive","ObservationSampleRateHz", ...
    "ResultCompletedAtSample","ResultAvailableAtSample","ReceiverID","ReceiverWindowID", ...
    "ReceiverClockDomain","ReceiverClockEpoch","ReceiverObservationSHA256", ...
    "ServingCell","CellID","UEIndex","ExecutionID","ConfigHash","ScenarioID", ...
    "RunFolder","RunTag","SourceRunID","RandomSeed","ChannelSeed","SweepPointIndex","ConfiguredSNR_dB"]));
for name=retained, T.(name)=sourceT.(name); end
if ~ismember("SourceRunID",names) && ismember("RunID",names), T.SourceRunID=sourceT.RunID; end
end

function T = iCSIRSTable(sourceT, meta)
T = iBuildMinimalTable(sourceT, meta, "csi_rs_runtime_event_table", { ...
    "SFN", "SFN"; "Slot", ["Slot"]; "CellId", ["CellID","cell_id"]; "BWPId", ["BWPID","BWPId","bwp_id"]; ...
    "UEId", ["UEIndex","UEID"]; "ResourceId", ["ResourceID","resource_id"]; "ResourceSetId", ["ResourceSetID","resource_set_id"]; ...
    "CSIRSType", ["CSIRSType","csirs_type"]; "NumPorts", ["NumPorts","num_ports"]; "Density", ["Density","density"]; ...
    "Periodicity", ["Periodicity","periodicity_slots"]; "SymbolLocations", ["SymbolLocations"]; "SubcarrierLocations", ["SubcarrierLocations"]; ...
    "Scheduled", ["Scheduled"]; "Transmitted", ["Transmitted"]; "Observed", ["Observed"]; "Consumed", ["Consumed"]; "Consumer", ["Consumer"]; ...
    "MeasurementRSRP_dB", ["MeasurementRSRP_dB"]; "MeasurementSource", ["MeasurementSource"]; "UpdateOutcome", ["UpdateOutcome"]; ...
    "RuntimeMaterializationStatus", ["RuntimeMaterializationStatus"]; "RuntimeEvidenceStatus", ["RuntimeEvidenceStatus","runtime_evidence","RuntimeEvidenceSource"]});
% Preserve the physical power plane and selected-resource/receive-branch
% identity. The legacy post-front-end grid-power scalar is not a substitute
% for port-3000 CSI-RSRP, nor is normalized power an absolute dBm value.
if ~isempty(T)
    names=string(sourceT.Properties.VariableNames);
    fields=names(startsWith(names,"Measurement") | startsWith(names,"PhysicalMeasurement") | ...
        startsWith(names,"CSISelectionQuality") | startsWith(names,"CSIObservationPopulation") | ...
        startsWith(names,"RankSelectionEvidence") | startsWith(names,"CQIModel") | ...
        ismember(names,["CSIMeasurementID","CSIMeasurementDigest","ReceiverID", ...
        "ReceiverWindowID","ReceiverClockDomain","ReceiverClockEpoch","ReceiverObservationSHA256", ...
        "ObservationStartSample","ObservationEndSampleExclusive","ResultAvailableAtSample", ...
        "ObservationSampleRateHz","RunFolder","RunTag","ExecutionID","ConfigHash","ScenarioID", ...
        "RandomSeed","ChannelSeed","NoiseStreamSeed","SweepPointIndex","ConfiguredSNR_dB"]) | ...
        startsWith(names,"ReferenceMeasuredSINR") | names=="ReferenceSINRMeasurementJSON" | ...
        startsWith(names,"CSIRSEmittedPowerComparison") | ...
        startsWith(names,"CSIRSEmittedSINRComparison") | ...
        startsWith(names,"CSIRSLinearPortModelComparison") | names=="PowerReferencePlane" | ...
        names=="CRI" | names=="RI" | names=="CQI" | names=="PMI");
    for field=fields
        T.(field)=sourceT.(field);
    end
    % RunId identifies the publication container. Keep the originating run
    % separate for multi-point/child populations; avoid RunId/RunID columns
    % differing only by case and never infer it from publication metadata.
    if ismember("RunID",names), T.SourceRunID=sourceT.RunID; end
end
T=iRetainDLMeasurementAuthority(T,sourceT);
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
    "CSIReferenceSlot", NaN, "SourceSlotAuthority", "", ...
    "SchedulerAcceptedRank", NaN, "SchedulerSpatialDecisionDeferred", NaN, ...
    "RankUpdateStatus", "", "RankIncreaseConfirmationCount", NaN, "RankIncreaseRequiredCount", NaN, ...
    "MCSIndex", NaN, "TargetCodeRate", NaN, "Modulation", "", ...
    "MCSSelectionSource", "", "MCSValueStatus", "", "LinkAdaptationDecisionReason", "", ...
    "SchedulerResolvedCQI", NaN, "Processed", NaN, ...
    "CSIUCITransport", "", "CSIUCIDecodeOk", NaN, "CSIUCICRCPass", NaN, "DeliveryStatus", "", ...
    "run_id", meta.run_id, "producer_module", "sixgr.truth.buildLLSPublicOutputTables", "source_artifact_ref", "control/csv/received_csi_reports.csv", ...
    "runtime_evidence", "independently_received_csi_uci"), height(cqiTable), 1);
for i = 1:height(cqiTable)
    row = cqiTable(i, :);
    decoded = iFirstNum(row, "CSIUCIDecodeOk", NaN);
    usable = isfinite(decoded) && decoded == 1;
    rows(i).TrialId = i;
    rows(i).SFN = iFirstNum(row, "SFN", NaN);
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
        % These are the consumer's recorded decisions, not fields decoded
        % from the CSI payload. In particular, raw CQI-to-MCS mapping is not
        % a substitute for MCSIndex when rank confirmation deferred admission.
        rows(i).MCSIndex = iFirstNum(row, "MCSIndex", NaN);
        rows(i).TargetCodeRate = iFirstNum(row, "TargetCodeRate", NaN);
        rows(i).Modulation = iFirstText(row, "Modulation", "");
        rows(i).SchedulerResolvedCQI = iFirstNum(row, "SchedulerResolvedCQI", NaN);
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
    for field = ["ReportIdentity","CSIReportConfigID","CSIUCITransport","DeliveryStatus", ...
            "SourceSlotAuthority","RankUpdateStatus","MCSSelectionSource", ...
            "MCSValueStatus","LinkAdaptationDecisionReason"]
        rows(i).(field) = iFirstText(row, field, "");
    end
    for field = ["CSIConfigurationEpoch","SourceSlot", ...
            "DueSlot","DeliveredSlot","CSIUCIDecodeOk","CSIUCICRCPass", ...
            "CSIReferenceSlot","SchedulerAcceptedRank","SchedulerSpatialDecisionDeferred", ...
            "RankIncreaseConfirmationCount","RankIncreaseRequiredCount","Processed"]
        rows(i).(field) = iFirstNum(row, field, NaN);
    end
end
T = struct2table(rows);
end

function T = iTRSTable(sourceT, meta)
T = iBuildMinimalTable(sourceT, meta, "trs_receiver_tracking_table", { ...
    "SFN", "SFN"; "Slot", ["Slot"]; "UEId", ["UEId"]; "CellId", ["ServingCell","TRSAssociatedCell"]; ...
    "TRSResourceId", ["TRSResourceId"]; "Observed", ["TRSProcessed"]; "Consumed", ["TRSProcessed"]; ...
    "TrackingStateBefore", ["TRSTrackingStateBefore"]; "TrackingStateAfter", ["TRSTrackingStateAfter"]; ...
    "TimingEstimateAvailability", ["TimingEstimateAvailability"]; "TimingEstimateSamples", ["TRSTimingEstimate_samples"]; ...
    "CFOEstimateAvailability", ["CFOEstimateAvailability"]; "CFOEstimateHz", ["TRSEstimatedCFO_Hz"]; ...
    "CorrectionLoopStatus", ["TRSReceiverIntegrationStatus"]; "RuntimeEvidenceStatus", ["RuntimeEvidenceStatus","runtime_evidence","TRSRuntimeEvidenceSource"]});
T=iRetainDLMeasurementAuthority(T,sourceT);
end

function T=iRetainDLMeasurementAuthority(T,sourceT)
% Retain original operational eligibility separately from diagnostic success.
% No defaults or installation authority are inferred for historical rows.
if isempty(T), return; end
assert(height(T)==height(sourceT),'sixgr:truth:DLMeasurementProjectionRows', ...
    'Preserve original row cardinality when projecting measurement authority.');
fields=["DLMeasurementConfigurationFamily","DLMeasurementConfigurationSHA256", ...
    "DLMeasurementNCellID","DLMeasurementInstallationSHA256", ...
    "DLMeasurementAuthorityRequired","DLMeasurementAuthorityEligible", ...
    "DLMeasurementAuthorityStatus","DLMeasurementAuthoritySource"];
fields=fields(ismember(fields,string(sourceT.Properties.VariableNames)));
for field=fields, T.(field)=sourceT.(field); end
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
    rows(i).TrialId = i;
    rows(i).SFN = iFirstNum(row, "SFN", NaN);
    rows(i).Slot = iFirstNum(row, ["Slot"], NaN);
    rows(i).CellId = iFirstNum(row, ["CellID","cell_id","BaseStationID","ServingCell"], NaN);
    rows(i).SSBIndex = iFirstNum(row, ["SSBIndex"], NaN);
    rows(i).BeamIndex = iFirstNum(row, ["BeamIndex"], NaN);
    rows(i).PSSDetected = iFirstLogical(row, ["PSSDetected"], false);
    rows(i).SSSDetected = iFirstLogical(row, ["SSSDetected"], false);
    rows(i).NCellIDRecovered = iFirstNum(row, ["NCellIDRecovered","NCellID"], NaN);
    [attempted,attemptKnown]=iOriginalPBCHFlag(row,["PBCHDecodeAttempted","DecodeAttempted"]);
    rows(i).PBCHDecodeAttempted = attempted;
    [crc,crcKnown]=iOriginalPBCHFlag(row,["BCHCRCValid","BCHCrcPass","PBCHCRCPass","CRCPass"]);
    [applicable,applicabilityKnown]=iOriginalPBCHFlag(row,"CRCApplicable");
    rows(i).PBCHCRC="unavailable";
    if applicabilityKnown && ~applicable
        rows(i).PBCHCRC="not_applicable";
    elseif attemptKnown && ~attempted
        rows(i).PBCHCRC="not_attempted";
    elseif attemptKnown && attempted && crcKnown
        rows(i).PBCHCRC=iCRCOutcome(true,crc);
    end
    rows(i).MIBRecovered = iOriginalPBCHFlag(row,["MIBRecovered","MIBDecoded"]);
    rows(i).RSRP_dB = iFirstNum(row, ["RSRP_dB"], NaN);
    rows(i).RSRQ_dB = iFirstNum(row, ["RSRQ_dB"], NaN);
    rows(i).SINR_dB = sinrValue;
    rows(i).RuntimeEvidenceStatus = iFirstText(row, ["RuntimeEvidenceStatus","runtime_evidence"], "persisted_runtime_trial_row");
    rows(i).source_artifact_ref = iFirstText(row, ["source_artifact_ref"], "");
    rows(i).runtime_evidence = iFirstText(row, ["runtime_evidence"], "");
end
T = struct2table(rows);
% Retain measured SSB power planes and post-decode PBCH scoring operands.
% Do not replace normalized occupied-RE power with fabricated dBm values.
scoreFields=string(fieldnames(sixgr.truth.scoreSharedPBCHReception())).';
powerFields=string(fieldnames(sixgr.link.ssbPowerReferenceEvidence())).';
frequencyFields=string(fieldnames(sixgr.phy.broadcast.measurePBCHResidualFrequency())).';
fields=[scoreFields powerFields frequencyFields "SS_RSRP_dBm" "SS_RSRP_dB_re_UnitOccupiedRE_Es" ...
    "PowerReferencePlane" "EVM_rms" "EVMReferenceSource" "EVMValueStatus" ...
    "BCHCrcPass" "BCHCRCValid" "MIBDecoded" "CandidateIdentityConsistent" ...
    "SSBIdentityVerified" "PBCHStrictReceiverEvidenceOk" "StrictReceiverEvidenceOk" ...
    "Status" "Crash" "Skipped" "CRCApplicable" "CRCPass" "CRCOutcome" ...
    "KSSBContractVersion" "Lmax" "MIBKSSBLow4" "PBCHKSSBMSB" ...
    "PBCHKSSBHighContribution" "KSSBHighBitApplicable" "DecodedKSSB" ...
    "MIBKSSBSubcarrierOffset" "k_SSB" "DetectionAttempted" "DecodeAttempted" ...
    "PSSDetected" "SSSDetected" "NCellIDRecovered" "NCellID" ...
    "PSSDetectionSource" "SSSDetectionSource" ...
    "BCHTransportBlockNumBits" "BCHTransportBlockHash" ...
    string(fieldnames(sixgr.phy.sync.ssbDetectionEvidence())).'];
for field=unique(fields,'stable')
    if ismember(field,string(sourceT.Properties.VariableNames))
        T.(field)=sourceT.(field);
    end
end
% A diagnostic derived from original accepted-MIB operands, never from raw
% CRC alone or the combined SIB1 Status. Missing historical operands fail
% closed; their absence is retained by the pass-through above.
T.MIBAcquisitionAccepted=sixgr.truth.pbchAcquisitionAccepted(sourceT);
T.MIBAcquisitionEvidenceComplete=true(height(sourceT),1);
for field=["BCHCRCValid","MIBDecoded","CandidateIdentityConsistent","SSBIdentityVerified"]
    if ~ismember(field,string(sourceT.Properties.VariableNames))
        T.MIBAcquisitionEvidenceComplete(:)=false; continue;
    end
    value=sourceT.(field);
    if ~((isnumeric(value)||islogical(value)) && isreal(value) && ...
            isequal(size(value),[height(sourceT),1]))
        T.MIBAcquisitionEvidenceComplete(:)=false; continue;
    end
    T.MIBAcquisitionEvidenceComplete=T.MIBAcquisitionEvidenceComplete & ...
        isfinite(value) & (value==0 | value==1);
end
end

function [value,known]=iOriginalPBCHFlag(row,names)
value=false; known=false;
for field=names
    if ~ismember(field,string(row.Properties.VariableNames)), continue; end
    raw=row.(field);
    known=(isnumeric(raw)||islogical(raw)) && isreal(raw) && isscalar(raw) && ...
        isfinite(raw) && (raw==0 || raw==1);
    if known, value=raw==1; end
    return; % Do not bypass an explicit unavailable/malformed original alias.
end
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
    "SelectedMCSReason", "", "MCSTable", "", "CQITable", "", ...
    "MCSValueStatus", "", "MCSIndexAuthority", "", "GrantOperatingPointSource", "", ...
    "LinkAdaptationDecisionReason", "", ...
    "Direction", "", "CQIProvenance", "", "SchedulerCQISource", "", ...
    "SchedulerCQIRawCQI", NaN, "SchedulerAdjustedSINR_dB", NaN, "SchedulerSINRBackoff_dB", NaN, ...
    "GrantContextId", "", "FrozenGrantContextId", "", "GrantSourceRow", NaN, "GrantSourceArtifactRef", "", ...
    "CQIDerivedMCS", NaN, "CQI", NaN, "CQISource", "", "CQICalibrationProfile", "", ...
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
    rows(i).SelectedMCSSource = iDecisionTextAlias(row, ...
        ["SelectedMCSSource","selected_mcs_source","MCSSelectionSource","mcs_selection_source"]);
    rows(i).SelectedMCSReason = iFirstText(row, ["scheduler_reason","GrantReason"], "");
    rows(i).MCSTable = iDecisionTextAlias(row,["MCSTable","mcs_table","MCS_Table"]);
    rows(i).CQITable = iDecisionTextAlias(row,["CQITable","cqi_table"]);
    rows(i).MCSValueStatus = iDecisionTextAlias(row,["MCSValueStatus","mcs_value_status"]);
    rows(i).MCSIndexAuthority = iDecisionTextAlias(row,["MCSIndexAuthority","mcs_index_authority"]);
    rows(i).GrantOperatingPointSource = iDecisionTextAlias(row,["GrantOperatingPointSource","grant_operating_point_source"]);
    rows(i).LinkAdaptationDecisionReason = iDecisionTextAlias(row,["LinkAdaptationDecisionReason","link_adaptation_decision_reason"]);
    rows(i).Direction=iDecisionTextAlias(row,["Direction","direction"]);
    for name=["CQIProvenance","SchedulerCQISource","GrantContextId","FrozenGrantContextId"]
        rows(i).(name)=iDecisionTextAlias(row,name);
    end
    for name=["SchedulerCQIRawCQI","SchedulerAdjustedSINR_dB","SchedulerSINRBackoff_dB","GrantSourceRow"]
        rows(i).(name)=iFirstNum(row,name,NaN);
    end
    rows(i).GrantSourceArtifactRef=iDecisionTextAlias(row,["GrantSourceArtifactRef","source_artifact_ref"]);
    rows(i).CQIDerivedMCS = derived;
    rows(i).CQI = iFirstNum(row, ["cqi_input","wideband_cqi"], NaN);
    rows(i).CQISource = iDecisionTextAlias(row,["CQISource","cqi_source"]);
    rows(i).CQICalibrationProfile = iDecisionTextAlias(row, ...
        ["CQICalibrationProfile","cqi_calibration_profile","CalibrationProfile","calibration_profile"]);
    rows(i).LinkAdaptationMode = iFirstText(row, ["LinkAdaptationMode","link_adaptation_domain"], "");
    rows(i).SchedulerGrantSource = iDecisionTextAlias(row,["SchedulerGrantSource","scheduler_grant_source"]);
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

function value=iDecisionTextAlias(row,names)
% Preserve actual decision provenance. An artifact location is not a grant
% source; a missing calibration profile is not evidence of a heuristic.
value="";
for name=names
    if ~ismember(name,string(row.Properties.VariableNames)), continue; end
    raw=row.(name);
    % Generic retained CSV imports can infer an entirely blank text column
    % as double NaN. Only this exact unavailable scalar is admissible; never
    % stringify finite numbers or accept an array as provenance.
    if isnumeric(raw)&&isreal(raw)&&isscalar(raw)&&isnan(raw), continue; end
    assert(ischar(raw)||isstring(raw)||iscellstr(raw), ...
        'sixgr:report:MCSCQIProvenanceType','%s must be scalar text.',name);
    candidate=string(raw);
    assert(isscalar(candidate),'sixgr:report:MCSCQIProvenanceShape', ...
        '%s must contain exactly one text value per original decision.',name);
    if ismissing(candidate)||strlength(strtrim(candidate))==0, continue; end
    assert(strlength(value)==0||value==candidate, ...
        'sixgr:report:MCSCQIProvenanceConflict', ...
        'Conflicting original decision aliases for %s; do not choose one silently.',names(1));
    value=candidate;
end
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
    iDecisionTextAlias(row, ["MCSValueStatus", "mcs_value_status"]), ...
    iDecisionTextAlias(row, ["SelectedMCSSource","selected_mcs_source","MCSSelectionSource", "mcs_selection_source"]), ...
    iDecisionTextAlias(row, ["MCSIndexAuthority", "mcs_index_authority"]), ...
    iDecisionTextAlias(row, ["GrantOperatingPointSource", "grant_operating_point_source"]), ...
    iDecisionTextAlias(row, ["LinkAdaptationDecisionReason", "link_adaptation_decision_reason"])], " "));
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
mcsTable = iDecisionTextAlias(row, ["MCSTable", "mcs_table", "MCS_Table"]);
if strlength(mcsTable)==0
    status="unavailable";
    detail="missing_original_mcs_table_no_spectral_efficiency_assumed";
    return;
end
selectedProfile = sixgr.link.resolveMCSProfile(char(mcsTable), selected);
if logical(sixgr.util.structGet(selectedProfile, "Valid", false))
    selectedSE = double(selectedProfile.SpectralEfficiency);
else
    status="unavailable";
    detail="unavailable_selected_mcs_profile_no_index_fallback";
    return;
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
else
    status = "unavailable";
    detail = "unavailable_bound_mcs_profile_no_index_fallback";
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
