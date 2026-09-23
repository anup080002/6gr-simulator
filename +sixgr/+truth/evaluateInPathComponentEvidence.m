function result = evaluateInPathComponentEvidence(cfg, rawTrials, component)
%EVALUATEINPATHCOMPONENTEVIDENCE Validate actual slot-runtime component rows.
%
% This function never launches a component waveform, reads an old artifact,
% or changes evidence scope.  It accepts only the in-memory tables emitted by
% CoupledTruthRuntime during the active scenario execution.

component = lower(strtrim(string(component)));
if ~isscalar(component) || ~ismember(component, ...
        ["prach","pdcch","pucch","pusch_uci","srs","trs","sib1"])
    error("sixgr:truth:UnsupportedInPathComponent", ...
        "Unsupported in-path component '%s'.", component);
end
if ~(isstruct(rawTrials) && isscalar(rawTrials))
    error("sixgr:truth:InPathRuntimeEvidenceRequired", ...
        "In-path %s evaluation requires the active raw-trial struct.", component);
end

[tableField, artifactField] = localTableNames(component);
T = sixgr.util.structGet(rawTrials, tableField, table());
if component == "pusch_uci" && istable(T) && ~isempty(T)
    % A PUSCH table also contains data-only transmissions. The strict UCI
    % component is limited to rows where the same receiver actually
    % demultiplexed a configured HARQ-ACK payload from that PUSCH waveform.
    % CSI-only UCI multiplexing and data-only rows are not HARQ-ACK attempts.
    feedbackCount = localNumericColumn(T, ...
        "UCIOnPUSCHFeedbackBitCount", nan(height(T), 1));
    T = T(localLogicalColumn(T, "UCIOnPUSCHApplied", ...
        false(height(T), 1)) & isfinite(feedbackCount) & feedbackCount > 0, :);
end
if ~(istable(T) && ~isempty(T))
    result = localResult(component, table(), artifactField, false, ...
        "missing_active_runtime_" + component + "_rows", 0, 0, 0);
    return;
end

genericOk = localGenericTruthMask(T);
identityOk = localRuntimeIdentityMask(T, cfg);
componentOk = localComponentMask(component, T, cfg);
rowOk = genericOk & identityOk & componentOk;
attemptOk = true(height(T), 1);
if component == "prach"
    attemptOk = localPRACHRuntimeAttemptMask(T);
elseif component == "pucch"
    attemptOk = componentOk | localQuietStandaloneSRMask(T);
end
requiredEntities = localRequiredEntityCount(cfg, component);
observedEntities = localObservedEntityCount(T, rowOk, component);
coverageOk = observedEntities >= requiredEntities;
if component == "prach"
    % A physical PRACH campaign must preserve real receiver outcomes. A
    % missed detection at low SNR is valid truth evidence, not a malformed
    % row. Require every row to be an identity-bound, same-chain four-step
    % attempt and at least one successful terminal access per configured UE.
    strictOk = all(genericOk) && all(identityOk) && all(attemptOk) && ...
        any(rowOk) && coverageOk;
elseif component == "pucch"
    % A monitored negative SR has no payload transmission to decode. Keep
    % it in the evidence/identity audit, but do not count it as a successful
    % reception or allow it alone to qualify the PUCCH component.
    strictOk = all(genericOk) && all(identityOk) && all(attemptOk) && ...
        any(rowOk) && coverageOk;
else
    strictOk = any(rowOk) && all(rowOk) && coverageOk;
end

failure = "";
if ~all(genericOk)
    failure = "proxy_placeholder_skipped_or_crashed_runtime_rows";
elseif ~all(identityOk)
    failure = "runtime_scenario_or_config_identity_mismatch";
elseif component == "prach" && ~all(attemptOk)
    failure = "prach_row_not_same_chain_four_step_ra_attempt";
elseif component == "pucch" && ~all(attemptOk)
    failure = "component_receiver_or_causal_chain_failure";
elseif ~any(component == ["prach","pucch"]) && ~all(componentOk)
    failure = "component_receiver_or_causal_chain_failure";
elseif ~coverageOk
    if component == "prach"
        failure = "runtime_successful_entity_coverage_" + observedEntities + "_of_" + requiredEntities;
    else
        failure = "runtime_entity_coverage_" + observedEntities + "_of_" + requiredEntities;
    end
end
result = localResult(component, T, artifactField, strictOk, failure, ...
    nnz(rowOk), height(T), requiredEntities);
result.ObservedEntityCount = observedEntities;
result.AllRowsTruthEligible = all(genericOk);
result.AllRowsRuntimeIdentityBound = all(identityOk);
result.AllRowsComponentPass = all(componentOk);
result.AllRowsValidRuntimeAttempts = all(attemptOk);
if component == "pucch"
    result.NoTransmissionSRObservationCount = nnz(localQuietStandaloneSRMask(T));
end
result.SuccessfulEntityCount = observedEntities;
result.InPathRuntimeValidationComplete = true;
result.ValidationAuthority = ...
    "sixgr.truth.evaluateInPathComponentEvidence/v1";
result.SourceTableSHA256 = sixgr.kpi.hashKPISourceRows(T);
end

function mask = localQuietStandaloneSRMask(T)
% Only explicit, completed, independently received no-TX SR observations.
% Missing evidence, false detection, missed positive SR or HARQ/CSI DTX
% cannot use this exception. It is not statistical detector qualification.
n=height(T); empty=repmat("",n,1); unknown=nan(n,1);
mask = localStringColumn(T,"UCIType",empty)=="standalone_sr" & ...
    localStringColumn(T,"Status",empty)=="NA" & ...
    localStringColumn(T,"ExecutionBackend",empty)=="pucch_shared_gnb_SR_reception" & ...
    localNumericColumn(T,"ReceiverExpectedHARQBitCount",unknown)==0 & ...
    localNumericColumn(T,"ReceiverExpectedSRBitCount",unknown)==1 & ...
    localNumericColumn(T,"ReceiverExpectedCSIPart1BitCount",unknown)==0 & ...
    localNumericColumn(T,"ReceiverExpectedCSIPart2BitCount",unknown)==0 & ...
    localNumericColumn(T,"PUCCHTransmissionPrepared",unknown)==0 & ...
    localNumericColumn(T,"ReceiverOnlyAssignment",unknown)==1 & ...
    localNumericColumn(T,"PositiveSRDetected",unknown)==0 & ...
    localNumericColumn(T,"PUCCHDecodeOk",unknown)==0 & ...
    localNumericColumn(T,"FalseSRDetection",unknown)==0 & ...
    localNumericColumn(T,"MissedSRDetection",unknown)==0 & ...
    localNumericColumn(T,"DTXFlag",unknown)==1 & ...
    localNumericColumn(T,"DetectionAttempted",unknown)==1 & ...
    localNumericColumn(T,"DetectionMetricValid",unknown)==1 & ...
    localNumericColumn(T,"ResourceExtractionAvailable",unknown)==1 & ...
    localNumericColumn(T,"ReceiverTimingOracleUsed",unknown)==0 & ...
    localNumericColumn(T,"ReceiverZeroPaddingUsed",unknown)==0 & ...
    localNumericColumn(T,"OraclePayloadBitsUsed",unknown)==0 & ...
    isnan(localNumericColumn(T,"UCIContentMatch",unknown));
first=localNumericColumn(T,"ObservationStartSample",unknown);
last=localNumericColumn(T,"ObservationEndSampleExclusive",unknown);
fs=localNumericColumn(T,"ObservationSampleRateHz",unknown);
mask=mask & ismember("UCIContentMatch",string(T.Properties.VariableNames)) & ...
    isfinite(first) & first>=0 & isfinite(last) & last>first & ...
    isfinite(fs) & fs>0 & ...
    isfinite(localNumericColumn(T,"DetectionMetric",unknown)) & ...
    isfinite(localNumericColumn(T,"DetectionThreshold",unknown)) & ...
    strlength(localStringColumn(T,"ReceiverAssignmentDigest",empty))>0 & ...
    strlength(localStringColumn(T,"ReceiverContextDigest",empty))>0;
end

function mask = localPRACHRuntimeAttemptMask(T)
n = height(T);
vars = string(T.Properties.VariableNames);
requiredColumns = ["DetectionAttempted","RAProcedureType", ...
    "FullRAEvidenceSource","RuntimeStageWaveformsUsed", ...
    "RuntimeChannelStateUsed","RuntimeNoiseApplied"];
if ~all(ismember(requiredColumns, vars))
    mask = false(n, 1);
    return;
end
procedure = lower(strtrim(string(T.RAProcedureType)));
source = lower(strtrim(string(T.FullRAEvidenceSource)));
mask = localLogicalColumn(T, "DetectionAttempted", false(n, 1)) & ...
    procedure == "contention_based_four_step" & ...
    source == "sixgr.phy.ra.runfourstepra" & ...
    localLogicalColumn(T, "RuntimeStageWaveformsUsed", false(n, 1)) & ...
    localLogicalColumn(T, "RuntimeChannelStateUsed", false(n, 1)) & ...
    localLogicalColumn(T, "RuntimeNoiseApplied", false(n, 1));
end

function mask = localRuntimeIdentityMask(T, cfg)
n = height(T);
mask = true(n, 1);
expectedScenario = strtrim(string(sixgr.util.structGet(cfg, ...
    "run.scenarioID", sixgr.util.structGet(cfg, "meta.scenarioID", ""))));
expectedHash = lower(strtrim(string(sixgr.util.structGet(cfg, ...
    "meta.configHash", ""))));
if strlength(expectedScenario) > 0
    if ~ismember("ScenarioID", string(T.Properties.VariableNames))
        mask(:) = false;
    else
        mask = mask & strtrim(string(T.ScenarioID)) == expectedScenario;
    end
end
if strlength(expectedHash) > 0
    if strlength(expectedHash) ~= 64 || ...
            ~ismember("ConfigHash", string(T.Properties.VariableNames))
        mask(:) = false;
    else
        mask = mask & lower(strtrim(string(T.ConfigHash))) == expectedHash;
    end
end
end

function [tableField, artifactField] = localTableNames(component)
switch component
    case "sib1"
        tableField = "PBCH";
        artifactField = "pbch_trials";
    case "pusch_uci"
        tableField = "UL";
        artifactField = "pusch_uci_trials";
    otherwise
        tableField = upper(component);
        artifactField = component + "_trials";
end
end

function mask = localGenericTruthMask(T)
n = height(T);
mask = true(n, 1);
mask = mask & ~localLogicalColumn(T, "Crash", false(n, 1));
mask = mask & ~localLogicalColumn(T, "Skipped", false(n, 1));
mask = mask & ~localLogicalColumn(T, "ToolboxMissing", false(n, 1));
mask = mask & ~localLogicalColumn(T, "ProxyUsed", false(n, 1));
mask = mask & ~localLogicalColumn(T, "FallbackFlag", false(n, 1));
mask = mask & ~localLogicalColumn(T, "PlaceholderFlag", false(n, 1));
for field = ["SourceClassification","ExecutionBackend", ...
        "ApproximationMode","E2EAirModel"]
    if ~ismember(field, string(T.Properties.VariableNames))
        continue;
    end
    values = lower(strtrim(string(T.(char(field)))));
    mask = mask & ~contains(values, ["proxy","fallback","synthetic", ...
        "logistic","lookup","lut"]);
end
end

function mask = localComponentMask(component, T, cfg)
n = height(T);
mask = localStatusPassMask(T);
switch component
    case "prach"
        mask = mask & localLogicalColumn(T, "StrictOk", false(n, 1)) & ...
            localLogicalColumn(T, "RACompleted", false(n, 1)) & ...
            localLogicalColumn(T, "PreambleDetected", false(n, 1)) & ...
            localLogicalColumn(T, "Msg2DCICrcPass", false(n, 1)) & ...
            localLogicalColumn(T, "Msg2PDSCHCrcPass", false(n, 1)) & ...
            localLogicalColumn(T, "Msg3PUSCHCrcPass", false(n, 1)) & ...
            localLogicalColumn(T, "Msg4PDCCHCrcPass", false(n, 1)) & ...
            localLogicalColumn(T, "Msg4PDSCHCrcPass", false(n, 1)) & ...
            localLogicalColumn(T, "ContentionIdentityMatches", false(n, 1));
        requireRRC = logical(sixgr.util.structGet(cfg, ...
            "initial_access.rrc.require_setup_complete", ...
            sixgr.util.structGet(cfg, ...
            "canonical_control.initial_access.rrc.require_setup_complete", false)));
        if requireRRC
            expectedTransaction = localNumericColumn(T, "RRCTransactionID", nan(n, 1));
            decodedTransaction = localNumericColumn(T, ...
                "RRCSetupCompleteDecodedTransactionID", nan(n, 1));
            expectedLCID = localNumericColumn(T, "SRB1LCID", nan(n, 1));
            decodedLCID = localNumericColumn(T, ...
                "RRCSetupCompleteDecodedSRB1LCID", nan(n, 1));
            runtimeUEId = localFirstFiniteNumericColumns(T, ...
                ["UEIndex","UEId","UEID"], nan(n, 1));
            expectedIdentity = "UE-" + string(round(runtimeUEId));
            decodedIdentity = localStringColumn(T, ...
                "RRCSetupCompleteDecodedUEIdentity", repmat("", n, 1));
            payloadHash = localStringColumn(T, ...
                "RRCSetupCompletePayloadSHA256", repmat("", n, 1));
            demapperCount = localNumericColumn(T, ...
                "SetupCompleteDemapperLLRCount", nan(n, 1));
            mask = mask & ...
                localLogicalColumn(T, "RequireRRCSetupComplete", false(n, 1)) & ...
                localLogicalColumn(T, "RRCSetupRequestDecoded", false(n, 1)) & ...
                localLogicalColumn(T, "RRCSetupDecoded", false(n, 1)) & ...
                localLogicalColumn(T, "SRB1Installed", false(n, 1)) & ...
                localLogicalColumn(T, "RRCSetupCompleteCRC", false(n, 1)) & ...
                localLogicalColumn(T, "RRCSetupCompleteDecoded", false(n, 1)) & ...
                localLogicalColumn(T, "RRCConnected", false(n, 1)) & ...
                localLogicalColumn(T, "SetupCompleteReceiverOk", false(n, 1)) & ...
                localLogicalColumn(T, "SetupCompleteChannelEstimateAvailable", false(n, 1)) & ...
                localLogicalColumn(T, "SetupCompleteEqualizationAvailable", false(n, 1)) & ...
                localLogicalColumn(T, "SetupCompleteLLRFinite", false(n, 1)) & ...
                isfinite(expectedTransaction) & decodedTransaction == expectedTransaction & ...
                isfinite(expectedLCID) & decodedLCID == expectedLCID & ...
                strlength(expectedIdentity) > 3 & decodedIdentity == expectedIdentity & ...
                strlength(payloadHash) == 64 & isfinite(demapperCount) & demapperCount > 0;
        end
    case "pdcch"
        mask = mask & localLogicalColumn(T, "StrictOk", false(n, 1)) & ...
            localLogicalColumn(T, "DCICrcPass", false(n, 1)) & ...
            localLogicalColumn(T, "PDCCHPayloadMatch", false(n, 1)) & ...
            localLogicalColumn(T, "PDCCHCausalGrantDecodeOk", false(n, 1)) & ...
            localLogicalColumn(T, "GrantValid", false(n, 1)) & ...
            ~localLogicalColumn(T, "PDCCHMissedDetection", false(n, 1)) & ...
            ~localLogicalColumn(T, "PDCCHFalseAlarm", false(n, 1));
    case "pucch"
        crcApplicable = localLogicalColumn(T, "CRCApplicable", ...
            localLogicalColumn(T, "UCICRCApplicable", false(n, 1)));
        crcPass = localLogicalColumn(T, "CRCPass", false(n, 1));
        crcOutcome = lower(localStringColumn(T, "CRCOutcome", repmat("", n, 1)));
        crcPass = crcPass | ismember(crcOutcome, ["pass","ok","success"]);
        mask = mask & localLogicalColumn(T, "StrictOk", false(n, 1)) & ...
            (~crcApplicable | crcPass) & ...
            localLogicalColumn(T, "UCIContentMatch", false(n, 1)) & ...
            localLogicalColumn(T, "PUCCHDecodeOk", false(n, 1)) & ...
            localLogicalColumn(T, "DetectionAttempted", false(n, 1)) & ...
            localLogicalColumn(T, "DetectionUsable", false(n, 1)) & ...
            localLogicalColumn(T, "ReceiverUsable", false(n, 1)) & ...
            localLogicalColumn(T, "StrictReceiverEvidenceOk", false(n, 1));
    case "pusch_uci"
        % UL-SCH and UCI are independently encoded and decoded on the same
        % PUSCH waveform. A valid HARQ-ACK may therefore decode when the
        % transport block CRC fails. Gate this component on the actual UCI
        % demultiplex/decode evidence, not the unrelated UL-SCH CRC/status.
        mask = true(n, 1);
        feedbackCount = localNumericColumn(T, "UCIOnPUSCHFeedbackBitCount", nan(n, 1));
        expected = localStringColumn(T, "ExpectedHARQACKBits", repmat("", n, 1));
        decoded = localStringColumn(T, "DecodedHARQACKBits", repmat("", n, 1));
        decodeStatus = lower(localStringColumn(T, "HARQACKDecodeStatus", repmat("", n, 1)));
        evidenceSource = lower(localStringColumn(T, "UCIOnPUSCHEvidenceSource", repmat("", n, 1)));
        mask = mask & localLogicalColumn(T, "UCIOnPUSCHApplied", false(n, 1)) & ...
            isfinite(feedbackCount) & feedbackCount > 0 & ...
            strlength(expected) > 0 & decoded == expected & ...
            localLogicalColumn(T, "HARQACKContentMatch", false(n, 1)) & ...
            decodeStatus == "decoded_match" & ...
            contains(evidenceSource, "same_waveform_pusch_rx");
    case "srs"
        mask = mask & localLogicalColumn(T, "StrictOk", false(n, 1)) & ...
            localLogicalColumn(T, "DetectionSuccess", false(n, 1)) & ...
            localLogicalColumn(T, "ResourceExtractionAvailable", false(n, 1)) & ...
            localLogicalColumn(T, "SRSChannelEstimateAvailable", false(n, 1)) & ...
            localLogicalColumn(T, "SRSRuntimeEvidenceUsable", false(n, 1));
    case "trs"
        mask = mask & localLogicalColumn(T, "StrictOk", false(n, 1)) & ...
            localLogicalColumn(T, "DetectionSuccess", false(n, 1)) & ...
            localLogicalColumn(T, "MeasurementUsable", false(n, 1)) & ...
            localLogicalColumn(T, "TRSProcessed", false(n, 1)) & ...
            localLogicalColumn(T, "TRSTimingEstimateUsable", false(n, 1)) & ...
            localLogicalColumn(T, "TRSCFOEstimateUsable", false(n, 1)) & ...
            localLogicalColumn(T, "TRSChannelEstimateAvailable", false(n, 1)) & ...
            localLogicalColumn(T, "TRSRuntimeEvidenceUsable", false(n, 1));
    case "sib1"
        mask = mask & localLogicalColumn(T, "StrictOk", false(n, 1)) & ...
            localLogicalColumn(T, "BCHCrcPass", false(n, 1)) & ...
            localLogicalColumn(T, "MIBDecoded", false(n, 1)) & ...
            localLogicalColumn(T, "SIB1StrictOk", false(n, 1)) & ...
            localLogicalColumn(T, "SIB1TreeEqual", false(n, 1)) & ...
            localLogicalColumn(T, "SIB1DCICrcPass", false(n, 1)) & ...
            localLogicalColumn(T, "SIB1DLSCHCrcPass", false(n, 1)) & ...
            localLogicalColumn(T, "SIB1ASN1DecodeOk", false(n, 1));
end
end

function mask = localTransportBlockCRCMask(T)
% Accept the canonical production schema (CRCApplicable/CRCPass) while
% retaining exact compatibility with legacy runtime rows that carried the
% inverse CRCError flag. Missing CRC evidence remains a hard failure.
n = height(T);
vars = string(T.Properties.VariableNames);
if ismember("CRCPass", vars)
    applicable = localLogicalColumn(T, "CRCApplicable", true(n, 1));
    passed = localLogicalColumn(T, "CRCPass", false(n, 1));
    mask = ~applicable | passed;
elseif ismember("CRCError", vars)
    mask = ~localLogicalColumn(T, "CRCError", true(n, 1));
else
    mask = false(n, 1);
end
mask = logical(mask(:));
end

function mask = localStatusPassMask(T)
n = height(T);
if ismember("Status", string(T.Properties.VariableNames))
    values = upper(strtrim(string(T.Status)));
    mask = ismember(values, ["PASS","OK","SUCCESS","COMPLETED"]);
elseif ismember("StrictOk", string(T.Properties.VariableNames))
    mask = localLogicalColumn(T, "StrictOk", false(n, 1));
else
    mask = false(n, 1);
end
end

function value = localLogicalColumn(T, field, defaultValue)
if ~ismember(string(field), string(T.Properties.VariableNames))
    value = defaultValue;
    return;
end
raw = T.(char(field));
if islogical(raw)
    value = raw;
elseif isnumeric(raw)
    value = isfinite(raw) & raw ~= 0;
else
    value = ismember(lower(strtrim(string(raw))), ...
        ["true","1","yes","pass","ok","success","completed"]);
end
value = logical(value(:));
end

function value = localNumericColumn(T, field, defaultValue)
if ~ismember(string(field), string(T.Properties.VariableNames))
    value = double(defaultValue(:));
    return;
end
raw = T.(char(field));
if isnumeric(raw) || islogical(raw)
    value = double(raw(:));
else
    value = str2double(string(raw(:)));
end
end

function value = localFirstFiniteNumericColumns(T, fields, defaultValue)
value = double(defaultValue(:));
for field = string(fields(:).')
    candidate = localNumericColumn(T, field, nan(size(value)));
    use = ~isfinite(value) & isfinite(candidate);
    value(use) = candidate(use);
end
end

function value = localStringColumn(T, field, defaultValue)
if ~ismember(string(field), string(T.Properties.VariableNames))
    value = string(defaultValue(:));
    return;
end
value = strtrim(string(T.(char(field))));
value = value(:);
end

function required = localRequiredEntityCount(cfg, component)
if any(component == ["trs","pdcch","pucch"])
    required = 1;
    return;
end
required = double(sixgr.util.structGet(cfg, "runtime.multi_user.NumUsers", ...
    sixgr.util.structGet(cfg, "system.users.count", ...
    sixgr.util.structGet(cfg, "users.n_users", 1))));
if ~(isscalar(required) && isfinite(required) && required >= 1)
    required = 1;
end
required = max(1, round(required));
end

function count = localObservedEntityCount(T, rowOk, component)
vars = string(T.Properties.VariableNames);
if component == "trs"
    candidates = ["ServingCell","CellId","BaseStationID"];
else
    candidates = ["UEIndex","UEID","UEId"];
end
count = 0;
for field = candidates
    if ~ismember(field, vars)
        continue;
    end
    raw = T.(char(field));
    if isnumeric(raw) || islogical(raw)
        values = double(raw(rowOk));
        values = values(isfinite(values));
    else
        values = string(raw(rowOk));
        values = values(~ismissing(values) & strlength(strtrim(values)) > 0);
    end
    count = numel(unique(values));
    if count > 0
        return;
    end
end
if any(rowOk)
    count = 1;
end
end

function result = localResult(component, T, artifactField, ok, failure, passRows, totalRows, requiredEntities)
summary = table(component, logical(ok), double(totalRows), double(passRows), ...
    double(requiredEntities), string(failure), ...
    'VariableNames', {'Component','StrictOk','ObservedRows','PassingRows', ...
    'RequiredEntityCount','FailureReason'});
tables = struct();
tables.(char(artifactField)) = T;
result = struct( ...
    "Ok", logical(ok), ...
    "StrictOk", logical(ok), ...
    "FailureReason", string(failure), ...
    "EvidenceScope", "in_path", ...
    "SameScenarioInPathEligible", true, ...
    "RuntimeEvidenceSource", "CoupledTruthRuntime.RawTrials", ...
    "LaunchedSupplementalWaveform", false, ...
    "ArtifactTables", tables, ...
    "SummaryTable", summary);
end
