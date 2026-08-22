function out = reconstructLLSKPISummaryFromRaw(raw, varargin)
%RECONSTRUCTLLSKPISUMMARYFROMRAW Direction-safe LLS KPI reconstruction.

ip = inputParser;
ip.addParameter("RunId", "", @(x) ischar(x) || isstring(x) || isnumeric(x));
ip.addParameter("ScenarioName", "", @(x) ischar(x) || isstring(x));
ip.addParameter("SourcePaths", struct(), @(x) isempty(x) || isstruct(x));
ip.addParameter("ExportedSummary", table(), @(x) isempty(x) || istable(x));
ip.addParameter("StrictMode", false, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
ip.addParameter("MeasurementWindowSec", NaN, @(x) isnumeric(x) && isscalar(x));
ip.addParameter("WarmupDurationSec", 0, @(x) isnumeric(x) && isscalar(x));
ip.addParameter("EffectiveBandwidthHz", NaN, @(x) isnumeric(x) && isscalar(x));
ip.addParameter("FeatureApplicability", struct(), @(x) isempty(x) || isstruct(x));
ip.parse(varargin{:});

runId = string(ip.Results.RunId);
scenarioName = string(ip.Results.ScenarioName);
sourcePaths = ip.Results.SourcePaths;
exportedSummary = ip.Results.ExportedSummary;
strictMode = logical(ip.Results.StrictMode);
measurementWindowSec = double(ip.Results.MeasurementWindowSec);
warmupDurationSec = max(0, double(ip.Results.WarmupDurationSec));
effectiveBandwidthHz = double(ip.Results.EffectiveBandwidthHz);
featureApplicability = localResolveFeatureApplicability(ip.Results.FeatureApplicability);

registry = sixgr.kpi.KPIFormulaRegistry();
schemaAudit = sixgr.kpi.validateRawKPITables(raw, ...
    "RunId", runId, "SourcePaths", sourcePaths);

[ulMetrics, ulContrib, ulTrace] = localComputeDirection(raw, sourcePaths, "UL", runId, scenarioName, ...
    measurementWindowSec, warmupDurationSec, effectiveBandwidthHz);
[dlMetrics, dlContrib, dlTrace] = localComputeDirection(raw, sourcePaths, "DL", runId, scenarioName, ...
    measurementWindowSec, warmupDurationSec, effectiveBandwidthHz);
[ulMetrics, ulPacketSDU, ulAppPackets] = localAttachPacketMetrics(raw, sourcePaths, "UL", ulMetrics, measurementWindowSec, warmupDurationSec, strictMode);
[dlMetrics, dlPacketSDU, dlAppPackets] = localAttachPacketMetrics(raw, sourcePaths, "DL", dlMetrics, measurementWindowSec, warmupDurationSec, strictMode);
ulMetrics = localAttachHARQAndSchedulerMetrics(raw, sourcePaths, "UL", ulMetrics);
dlMetrics = localAttachHARQAndSchedulerMetrics(raw, sourcePaths, "DL", dlMetrics);

summary = localBuildLegacySummary(runId, scenarioName, ulMetrics, dlMetrics, strictMode);
recon = localBuildReconstructionSummary(runId, scenarioName, registry, ulMetrics, dlMetrics, exportedSummary, featureApplicability);
dirAudit = localBuildDirectionIsolationAudit(runId, ulMetrics, dlMetrics);
aliasMap = localBuildLegacyAliasMap(runId, registry, summary, recon);
knownBug = sixgr.kpi.guardNoULGoodputCopiedFromDL(summary, ulMetrics, dlMetrics);
unitAudit = localBuildUnitAudit(runId, recon);
durationAudit = localBuildDurationAudit(runId, scenarioName, ulMetrics, dlMetrics);
sourceManifest = localBuildSourceManifest( ...
    runId, scenarioName, raw, sourcePaths, featureApplicability);

out = struct();
out.FormulaRegistry = registry;
out.SchemaAudit = schemaAudit;
out.SummaryAliases = summary;
out.ReconstructionSummary = recon;
out.DirectionIsolationAudit = dirAudit;
out.LegacyAliasMap = aliasMap;
out.KnownBugRegression = knownBug;
out.UnitConversionAudit = unitAudit;
out.DurationSourceAudit = durationAudit;
out.SourceManifest = sourceManifest;
out.ObjectiveBinding = localBuildObjectiveBinding( ...
    runId, scenarioName, registry, recon, featureApplicability);
out.RowContributionsUL = ulContrib;
out.RowContributionsDL = dlContrib;
out.HARQDeliveryTraceUL = ulTrace;
out.HARQDeliveryTraceDL = dlTrace;
out.TBDeliveryLedgerUL = ulTrace;
out.TBDeliveryLedgerDL = dlTrace;
out.PacketSDUDeliveryLedgerUL = ulPacketSDU;
out.PacketSDUDeliveryLedgerDL = dlPacketSDU;
out.ApplicationPacketDeliveryLedgerUL = ulAppPackets;
out.ApplicationPacketDeliveryLedgerDL = dlAppPackets;
out.StrictOk = all(localColumnBool(recon, "StrictOk", false)) && ...
    all(localColumnBool(dirAudit, "Status", "pass")) && ...
    all(localColumnBool(knownBug, "BugPrevented", false)) && ...
    all(localColumnBool(unitAudit, "Pass", true)) && ...
    all(localColumnBool(durationAudit, "Pass", false));
out.Status = string(localTernary(out.StrictOk, "pass", "fail"));
end

function [metrics, contribT, traceT] = localComputeDirection(raw, sourcePaths, direction, runId, scenarioName, measurementWindowSec, warmupDurationSec, effectiveBandwidthHz)
direction = upper(string(direction));
if isstruct(raw) && isfield(raw, char(direction)) && istable(raw.(char(direction)))
    T = raw.(char(direction));
else
    T = table();
end
sourcePath = localSourcePath(sourcePaths, direction);

metrics = struct( ...
    "Direction", direction, ...
    "SourceTablePath", sourcePath, ...
    "SourceRowCount", height(T), ...
    "EligibleRowCount", 0, ...
    "ExcludedRowCount", 0, ...
    "RowsWithExpectedDirection", 0, ...
    "RowsWithWrongDirection", 0, ...
    "SourceRowsHash", "empty", ...
    "MissingRawData", true, ...
    "SchemaValid", false, ...
    "ProxyRowsExcluded", 0, ...
    "SkippedRowsExcluded", 0, ...
    "AggregationDurationSec", NaN, ...
    "ScheduledResourceExposureSec", NaN, ...
    "MeasurementWindowSec", NaN, ...
    "WarmupDurationSec", double(warmupDurationSec), ...
    "DurationSource", "unavailable", ...
    "ScheduledBits", NaN, ...
    "DeliveredBits", NaN, ...
    "GoodputMax_Mbps", NaN, ...
    "ScheduledThroughput_Mbps", NaN, ...
    "TBGooDput_Mbps", NaN, ...
    "TBGoodput_Mbps", NaN, ...
    "SpectralEfficiency_bpsHz", NaN, ...
    "FirstSuccessDeliveryCount", 0, ...
    "RetransmissionAttemptCount", 0, ...
    "MeanDeliveryLatency_ms", NaN, ...
    "P95DeliveryLatency_ms", NaN, ...
    "BLER", NaN, ...
    "BER", NaN, ...
    "DuplicateDeliveryCount", 0, ...
    "Status", "missing_raw_data", ...
    "FailureReason", "raw_table_missing_or_empty");

contribT = localEmptyContributionTable();
traceT = localEmptyHARQTraceTable();
if ~(istable(T) && ~isempty(T))
    return;
end

vars = string(T.Properties.VariableNames);
if ~ismember("Direction", vars)
    metrics.MissingRawData = false;
    metrics.Status = "schema_invalid";
    metrics.FailureReason = "direction_column_missing";
    return;
end

dirValues = upper(strtrim(string(T.Direction)));
expectedMask = dirValues == direction;
metrics.RowsWithExpectedDirection = sum(expectedMask);
metrics.RowsWithWrongDirection = sum(~expectedMask);
if metrics.RowsWithExpectedDirection == 0 || metrics.RowsWithWrongDirection > 0
    metrics.MissingRawData = false;
    metrics.Status = "direction_invalid";
    metrics.FailureReason = "raw_table_contains_wrong_or_missing_direction_rows";
    return;
end

proxyMask = localOptionalLogical(T, "ProxyUsed", false(height(T), 1));
skippedMask = localOptionalLogical(T, "Skipped", false(height(T), 1));
eligible = expectedMask & ~proxyMask & ~skippedMask;
metrics.ProxyRowsExcluded = sum(proxyMask);
metrics.SkippedRowsExcluded = sum(skippedMask);
metrics.EligibleRowCount = sum(eligible);
metrics.ExcludedRowCount = height(T) - metrics.EligibleRowCount;
metrics.MissingRawData = false;
if metrics.EligibleRowCount == 0
    metrics.Status = "no_eligible_rows";
    metrics.FailureReason = "all_rows_proxy_skipped_or_wrong_direction";
    return;
end

E = T(eligible, :);
missingCore = localMissingCoreColumns(E);
if strlength(missingCore) > 0
    metrics.Status = "schema_invalid";
    metrics.FailureReason = "missing_required_columns:" + missingCore;
    return;
end
metrics.SourceRowsHash = sixgr.kpi.hashKPISourceRows(E);
metrics.SchemaValid = true;
metrics.GoodputMax_Mbps = localMaxFinite(localOptionalNumeric(E, "Goodput_Mbps", NaN(height(E), 1)));
scheduledBits = localFirstNumeric(E, ["ScheduledBits","TBSize_bits","OfferedBits","TBS"], NaN(height(E), 1));
goodBitsRaw = localFirstNumeric(E, ["GoodputBits","GoodBits","DeliveredBits","PayloadBits"], NaN(height(E), 1));
crcPass = localOptionalLogical(E, "TBCrcPass", localOptionalLogical(E, "CRCPass", true(height(E), 1)));
goodBits = goodBitsRaw;
tbSize = localFirstNumeric(E, ["TBSize_bits","TBS","ScheduledBits"], NaN(height(E), 1));
missingGoodBits = ~isfinite(goodBits);
goodBits(missingGoodBits & crcPass & isfinite(tbSize)) = tbSize(missingGoodBits & crcPass & isfinite(tbSize));
goodBits(~crcPass) = 0;
goodBits(~isfinite(goodBits)) = 0;
scheduledBits(~isfinite(scheduledBits)) = 0;

[resourceExposureSec, resourceExposureSource] = localDurationSec(E);
[durationSec, durationSource] = localMeasurementWindowSec(E, resourceExposureSec, resourceExposureSource, measurementWindowSec, warmupDurationSec);
metrics.AggregationDurationSec = durationSec;
metrics.ScheduledResourceExposureSec = resourceExposureSec;
metrics.MeasurementWindowSec = durationSec;
metrics.DurationSource = durationSource;
metrics.ScheduledBits = sum(scheduledBits, "omitnan");
if ~(isfinite(durationSec) && durationSec > 0) || ~(isfinite(resourceExposureSec) && resourceExposureSec > 0)
    metrics.Status = "invalid_duration";
    metrics.FailureReason = "radio_duration_unavailable";
    return;
end

[deliveryBits, duplicateCount, traceT] = localDeduplicateDeliveries(E, direction, runId, scheduledBits, goodBits, crcPass, resourceExposureSec, durationSec);
metrics.DeliveredBits = deliveryBits;
metrics.DuplicateDeliveryCount = duplicateCount;
metrics.FirstSuccessDeliveryCount = sum(logical(traceT.FirstSuccessDelivery));
metrics.RetransmissionAttemptCount = sum(logical(traceT.RetransmissionFlag));
lat = double(traceT.DeliveryLatency_ms(logical(traceT.FirstSuccessDelivery)));
lat = lat(isfinite(lat));
if ~isempty(lat)
    metrics.MeanDeliveryLatency_ms = mean(lat, "omitnan");
    metrics.P95DeliveryLatency_ms = localPercentile(lat, 95);
end
if isfinite(resourceExposureSec) && resourceExposureSec > 0
    metrics.ScheduledThroughput_Mbps = metrics.ScheduledBits / resourceExposureSec / 1e6;
end
if isfinite(durationSec) && durationSec > 0
    metrics.TBGoodput_Mbps = metrics.DeliveredBits / durationSec / 1e6;
    metrics.TBGooDput_Mbps = metrics.TBGoodput_Mbps;
    if isfinite(effectiveBandwidthHz) && effectiveBandwidthHz > 0
        metrics.SpectralEfficiency_bpsHz = metrics.DeliveredBits / durationSec / effectiveBandwidthHz;
    end
end
if ~isfinite(metrics.TBGoodput_Mbps) && isfinite(metrics.GoodputMax_Mbps)
    metrics.TBGoodput_Mbps = metrics.GoodputMax_Mbps;
end

if any(isfinite(double(crcPass)))
    metrics.BLER = sum(~crcPass) / max(numel(crcPass), 1);
end
bitErrors = localOptionalNumeric(E, "BitErrors", NaN(height(E), 1));
bitsCompared = localOptionalNumeric(E, "BitsCompared", NaN(height(E), 1));
if sum(bitsCompared(isfinite(bitsCompared)), "omitnan") > 0
    metrics.BER = sum(bitErrors(isfinite(bitErrors)), "omitnan") / sum(bitsCompared(isfinite(bitsCompared)), "omitnan");
end
metrics.Status = "pass";
metrics.FailureReason = "";
contribT = localBuildContributionTable(E, direction, runId, scenarioName, sourcePath, scheduledBits, goodBits, traceT, resourceExposureSec, durationSec);
end

function [metrics, macLedger, appLedger] = localAttachPacketMetrics(raw, sourcePaths, direction, metrics, measurementWindowSec, warmupDurationSec, strictMode)
direction = upper(string(direction));
macSourcePath = localSourcePath(sourcePaths, "PacketSDU");
appSourcePath = localSourcePath(sourcePaths, "ApplicationPackets");
macLedger = localFilterRawDirectionTable(localRawTable(raw, "PacketSDU"), direction);
appLedger = localFilterRawDirectionTable(localRawTable(raw, "ApplicationPackets"), direction);

metrics.MAC = localEmptyLayerMetrics(metrics, "MAC", macSourcePath);
metrics.Application = localEmptyLayerMetrics(metrics, "application", appSourcePath);

if istable(macLedger) && ~isempty(macLedger)
    metrics.MAC.SourceRowCount = height(macLedger);
    metrics.MAC.RowsWithExpectedDirection = height(macLedger);
    metrics.MAC.MissingRawData = false;
    missing = localMissingPacketColumns(macLedger, ["MACSDUId","PayloadBits","DeliverySuccess"]);
    if strlength(missing) > 0
        metrics.MAC.Status = "schema_invalid";
        metrics.MAC.FailureReason = "missing_required_columns:" + missing;
    else
        success = localOptionalLogical(macLedger, "DeliverySuccess", false(height(macLedger), 1));
        protocolEvidenceRejected = false;
        if strictMode && ismember("ProtocolPayloadSameWaveformTruth", ...
                string(macLedger.Properties.VariableNames)) && ...
                any(logical(macLedger.ProtocolPayloadSameWaveformTruth))
            protocolRequired = ["ProtocolDecodedBitCount", ...
                "ProtocolDecodedBitExact", "ProtocolDecodedMACSHA256", ...
                "ProtocolDecodedRLC_SHA256", "ProtocolMACSHA256", ...
                "ProtocolEncodedRLC_SHA256", "ProtocolMACPDUBytes"];
            protocolMissing = localMissingPacketColumns(macLedger, protocolRequired);
            if strlength(protocolMissing) > 0
                metrics.MAC.Status = "schema_invalid";
                metrics.MAC.FailureReason = ...
                    "missing_same_waveform_decoder_columns:" + protocolMissing;
                metrics.MAC.SchemaValid = false;
                protocolEvidenceRejected = true;
            else
                bound = logical(macLedger.ProtocolPayloadSameWaveformTruth);
                decodedExact = logical(macLedger.ProtocolDecodedBitExact);
                decodedCount = double(macLedger.ProtocolDecodedBitCount);
                expectedCount = 8 .* double(macLedger.ProtocolMACPDUBytes);
                macHashExact = lower(strtrim(string( ...
                    macLedger.ProtocolDecodedMACSHA256))) == lower(strtrim(string( ...
                    macLedger.ProtocolMACSHA256)));
                rlcHashExact = lower(strtrim(string( ...
                    macLedger.ProtocolDecodedRLC_SHA256))) == lower(strtrim(string( ...
                    macLedger.ProtocolEncodedRLC_SHA256)));
                invalidDelivered = success & (~bound | ~decodedExact | ...
                    ~isfinite(decodedCount) | decodedCount ~= expectedCount | ...
                    ~macHashExact | ~rlcHashExact);
                if any(invalidDelivered)
                    metrics.MAC.Status = "schema_invalid";
                    metrics.MAC.FailureReason = ...
                        "delivered_mac_sdu_not_backed_by_exact_phy_decoder_bytes";
                    metrics.MAC.SchemaValid = false;
                    protocolEvidenceRejected = true;
                end
            end
        end
        if ~protocolEvidenceRejected
            bits = localFirstNumeric(macLedger, ["PayloadBits","DeliveredBits","ApplicationPayloadBits"], NaN(height(macLedger), 1));
            ids = string(macLedger.MACSDUId);
            [deliveredBits, duplicateCount, firstCount] = localUniqueDeliveredPayloadBits(ids, bits, success);
            durationSec = localPacketMeasurementWindowSec(macLedger, metrics, measurementWindowSec, warmupDurationSec);
            metrics.MAC = localFinalizeLayerMetrics(metrics.MAC, macLedger, deliveredBits, duplicateCount, firstCount, durationSec);
        end
    end
end

if istable(appLedger) && ~isempty(appLedger)
    metrics.Application.SourceRowCount = height(appLedger);
    metrics.Application.RowsWithExpectedDirection = height(appLedger);
    metrics.Application.MissingRawData = false;
    missing = localMissingPacketColumns(appLedger, ["PacketId","DeliverySuccess"]);
    if strlength(missing) > 0
        metrics.Application.Status = "schema_invalid";
        metrics.Application.FailureReason = "missing_required_columns:" + missing;
    else
        success = localOptionalLogical(appLedger, "DeliverySuccess", false(height(appLedger), 1));
        applicationEvidenceRejected = false;
        if strictMode
            if ~ismember("SameWaveformProtocolComplete", string(appLedger.Properties.VariableNames))
                metrics.Application.Status = "schema_invalid";
                metrics.Application.FailureReason = "same_waveform_protocol_completion_evidence_missing";
                metrics.Application.SchemaValid = false;
                applicationEvidenceRejected = true;
            else
                protocolComplete = logical(appLedger.SameWaveformProtocolComplete);
                if any(success & ~protocolComplete)
                    metrics.Application.Status = "schema_invalid";
                    metrics.Application.FailureReason = "application_delivery_claim_not_backed_by_same_waveform_protocol_completion";
                    metrics.Application.SchemaValid = false;
                    applicationEvidenceRejected = true;
                end
            end
        end
        if ~applicationEvidenceRejected
            bits = localFirstNumeric(appLedger, ["DeliveredBits","ApplicationPayloadBits","OfferedBits","PayloadBits"], NaN(height(appLedger), 1));
            ids = string(appLedger.PacketId);
            if ismember("ApplicationPacketId", string(appLedger.Properties.VariableNames))
                appIds = string(appLedger.ApplicationPacketId);
                ids(strlength(strtrim(appIds)) > 0) = appIds(strlength(strtrim(appIds)) > 0);
            end
            [deliveredBits, duplicateCount, firstCount] = localUniqueDeliveredPayloadBits(ids, bits, success);
            durationSec = localPacketMeasurementWindowSec(appLedger, metrics, measurementWindowSec, warmupDurationSec);
            metrics.Application = localFinalizeLayerMetrics(metrics.Application, appLedger, deliveredBits, duplicateCount, firstCount, durationSec);
            [lat, latencyOk, latencyReason] = localPacketLatencyMs(appLedger, success);
            if ~latencyOk
                metrics.Application.Status = "schema_invalid";
                metrics.Application.FailureReason = latencyReason;
                metrics.Application.SchemaValid = false;
            elseif ~isempty(lat)
                metrics.Application.MeanDeliveryLatency_ms = mean(lat, "omitnan");
                metrics.Application.P95DeliveryLatency_ms = localPercentile(lat, 95);
                metrics.MeanDeliveryLatency_ms = metrics.Application.MeanDeliveryLatency_ms;
                metrics.P95DeliveryLatency_ms = metrics.Application.P95DeliveryLatency_ms;
            end
        end
    end
end
end

function metrics = localAttachHARQAndSchedulerMetrics(raw, sourcePaths, direction, metrics)
direction = upper(string(direction));
metrics.HARQ = localHARQMetrics(raw, sourcePaths, direction, metrics);
metrics.Scheduler = localSchedulerMetrics(raw, sourcePaths, direction, metrics);
end

function layer = localHARQMetrics(raw, sourcePaths, direction, parent)
layer = localEmptyLayerMetrics(parent, "HARQ", localSourcePath(sourcePaths, "HARQTimeline"));
layer.NACKCount = NaN;
layer.ACKNACKEventCount = NaN;
layer.NACKRate = NaN;
layer.RetransmissionAttemptCount = NaN;
layer.TotalAttemptCount = NaN;
layer.RetransmissionRate = NaN;
layer.FailureReason = "harq_timeline_missing_or_empty";

T = localFilterRawDirectionTable(localRawTable(raw, "HARQTimeline"), direction);
if isempty(T)
    return;
end
layer.SourceRowCount = height(T);
layer.RowsWithExpectedDirection = height(T);
layer.MissingRawData = false;
vars = string(T.Properties.VariableNames);
hasProcess = any(ismember(["HarqID","HARQProcessId","HARQProcess"], vars));
hasTime = any(ismember(["EventTimeSec","Slot","CanonicalSlot","FeedbackDueSlot"], vars));
hasOutcome = any(ismember(["AckNack","CombinedDecodeOK","Ack"], vars));
hasRetx = any(ismember(["IsRetransmission","RetransmissionFlag","HARQIsRetransmission"], vars));
if ~(ismember("Direction", vars) && hasProcess && hasTime && hasOutcome && hasRetx)
    layer.Status = "schema_invalid";
    layer.FailureReason = "harq_timeline_missing_direction_process_time_outcome_or_retransmission_fields";
    return;
end

proxy = localOptionalLogical(T, "ProxyUsed", false(height(T), 1));
skipped = localOptionalLogical(T, "Skipped", false(height(T), 1));
eligible = ~proxy & ~skipped;
layer.ProxyRowsExcluded = sum(proxy);
layer.SkippedRowsExcluded = sum(skipped);
layer.EligibleRowCount = sum(eligible);
layer.ExcludedRowCount = height(T) - layer.EligibleRowCount;
if ~any(eligible)
    layer.Status = "no_eligible_rows";
    layer.FailureReason = "all_harq_rows_proxy_or_skipped";
    return;
end
E = T(eligible, :);
[ack, validOutcome] = localHARQAckOutcome(E);
retx = localFirstLogical(E, ["IsRetransmission","RetransmissionFlag","HARQIsRetransmission"], false(height(E), 1));
if ~all(validOutcome)
    layer.Status = "schema_invalid";
    layer.FailureReason = "harq_timeline_contains_invalid_ack_nack_outcomes";
    return;
end
layer.SourceRowsHash = sixgr.kpi.hashKPISourceRows(E);
layer.SchemaValid = true;
layer.NACKCount = sum(~ack);
layer.ACKNACKEventCount = numel(ack);
layer.NACKRate = layer.NACKCount / max(layer.ACKNACKEventCount, 1);
layer.RetransmissionAttemptCount = sum(retx);
layer.TotalAttemptCount = numel(retx);
layer.RetransmissionRate = layer.RetransmissionAttemptCount / max(layer.TotalAttemptCount, 1);
layer.Status = "pass";
layer.FailureReason = "";
end

function [ack, valid] = localHARQAckOutcome(T)
n = height(T);
ack = false(n, 1);
valid = false(n, 1);
vars = string(T.Properties.VariableNames);
if ismember("AckNack", vars)
    token = upper(strtrim(string(T.AckNack)));
    valid = token == "ACK" | token == "NACK";
    ack = token == "ACK";
elseif ismember("CombinedDecodeOK", vars)
    ack = logical(T.CombinedDecodeOK);
    valid = true(n, 1);
elseif ismember("Ack", vars)
    ack = logical(T.Ack);
    valid = true(n, 1);
end
end

function layer = localSchedulerMetrics(raw, sourcePaths, direction, parent)
grantField = direction + "Grants";
layer = localEmptyLayerMetrics(parent, "scheduler", localSourcePath(sourcePaths, grantField));
layer.AllocatedPRBSymbols = NaN;
layer.AvailablePRBSymbols = NaN;
layer.PRBUtilization = NaN;
layer.FailureReason = "scheduler_grants_or_slot_trace_missing";
G = localFilterRawDirectionTable(localRawTable(raw, grantField), direction);
S = localRawTable(raw, "SlotTrace");
if isempty(G) || isempty(S)
    return;
end
layer.SourceRowCount = height(G);
layer.RowsWithExpectedDirection = height(G);
layer.MissingRawData = false;
gvars = string(G.Properties.VariableNames);
requiredGroups = { ["PRBStart"], ["PRBCount","AllocatedPRBCount","NumPRB"], ...
    ["SymbolStart"], ["NumSymbols"], ["Slot","CanonicalSlot","TTI"] };
for i = 1:numel(requiredGroups)
    if ~any(ismember(requiredGroups{i}, gvars))
        layer.Status = "schema_invalid";
        layer.FailureReason = "scheduler_grant_missing_exact_allocation_fields";
        return;
    end
end
nRB = double(sixgr.util.structGet(raw, "GridNumRBs", NaN));
nCells = double(sixgr.util.structGet(raw, "NumResourceCells", NaN));
nSymbolsPerSlot = double(sixgr.util.structGet(raw, "SymbolsPerSlot", NaN));
if ~(isscalar(nRB) && isfinite(nRB) && nRB >= 1)
    layer.Status = "schema_invalid";
    layer.FailureReason = "active_grid_num_rbs_unavailable";
    return;
end
if ~(isscalar(nSymbolsPerSlot) && isfinite(nSymbolsPerSlot) && ...
        nSymbolsPerSlot >= 1 && nSymbolsPerSlot == fix(nSymbolsPerSlot))
    layer.Status = "schema_invalid";
    layer.FailureReason = "symbols_per_slot_unavailable";
    return;
end

cellValues = localFirstNumeric(G, ["BaseStationID","CellID","ServingCell"], NaN(height(G), 1));
finiteCells = unique(cellValues(isfinite(cellValues)));
if ~(isscalar(nCells) && isfinite(nCells) && nCells >= 1)
    if numel(finiteCells) == 1
        nCells = 1;
    else
        layer.Status = "schema_invalid";
        layer.FailureReason = "resource_cell_count_unavailable";
        return;
    end
end
nCells = round(nCells);
if isempty(finiteCells) && nCells == 1
    cellValues(:) = 1;
elseif any(~isfinite(cellValues))
    layer.Status = "schema_invalid";
    layer.FailureReason = "scheduler_grant_cell_identity_missing";
    return;
end

proxy = localOptionalLogical(G, "ProxyUsed", false(height(G), 1));
skipped = localOptionalLogical(G, "Skipped", false(height(G), 1));
eligible = ~proxy & ~skipped;
layer.ProxyRowsExcluded = sum(proxy);
layer.SkippedRowsExcluded = sum(skipped);
layer.EligibleRowCount = sum(eligible);
layer.ExcludedRowCount = height(G) - layer.EligibleRowCount;
if ~any(eligible)
    layer.Status = "no_eligible_rows";
    layer.FailureReason = "all_scheduler_grants_proxy_or_skipped";
    return;
end
G = G(eligible, :);
cellValues = cellValues(eligible);

[available, slotIndex, slotSweep, symStart, symCount, slotOk, slotReason] = ...
    localAvailablePRBSymbols(S, direction, nRB, nCells, nSymbolsPerSlot);
if ~slotOk
    layer.Status = "schema_invalid";
    layer.FailureReason = slotReason;
    return;
end
grantSlot = localFirstNumeric(G, ["CanonicalSlot","TTI","Slot"], NaN(height(G), 1));
grantSweep = localFirstNumeric(G, ["SweepPointIndex"], NaN(height(G), 1));
prbStart = localFirstNumeric(G, ["PRBStart"], NaN(height(G), 1));
prbCount = localFirstNumeric(G, ["PRBCount","AllocatedPRBCount","NumPRB"], NaN(height(G), 1));
grantSymStart = localFirstNumeric(G, ["SymbolStart"], NaN(height(G), 1));
grantSymCount = localFirstNumeric(G, ["NumSymbols"], NaN(height(G), 1));
occupiedKeys = strings(0, 1);
for i = 1:height(G)
    traceMatch = slotIndex == grantSlot(i);
    if isfinite(grantSweep(i))
        traceMatch = traceMatch & slotSweep == grantSweep(i);
    elseif sum(traceMatch) > 1
        layer.Status = "schema_invalid";
        layer.FailureReason = "scheduler_grant_sweep_identity_missing_for_repeated_slot";
        return;
    end
    traceRow = find(traceMatch, 1);
    if isempty(traceRow)
        layer.Status = "schema_invalid";
        layer.FailureReason = "scheduler_grant_has_no_matching_slot_trace";
        return;
    end
    values = [prbStart(i), prbCount(i), grantSymStart(i), grantSymCount(i)];
    if any(~isfinite(values)) || prbStart(i) < 0 || prbCount(i) < 1 || ...
            prbStart(i) + prbCount(i) > nRB || grantSymCount(i) < 1 || ...
            grantSymStart(i) < symStart(traceRow) || ...
            grantSymStart(i) + grantSymCount(i) > symStart(traceRow) + symCount(traceRow)
        layer.Status = "schema_invalid";
        layer.FailureReason = "scheduler_grant_allocation_outside_active_slot_grid";
        return;
    end
    for prb = round(prbStart(i)):(round(prbStart(i) + prbCount(i)) - 1)
        for sym = round(grantSymStart(i)):(round(grantSymStart(i) + grantSymCount(i)) - 1)
            occupiedKeys(end+1, 1) = "s" + string(grantSweep(i)) + ... %#ok<AGROW>
                "_t" + string(grantSlot(i)) + "_c" + string(cellValues(i)) + ...
                "_p" + string(prb) + "_y" + string(sym);
        end
    end
end
allocated = numel(unique(occupiedKeys));
if allocated > available
    layer.Status = "schema_invalid";
    layer.FailureReason = "allocated_prb_symbols_exceed_available_resources";
    return;
end
layer.SourceRowsHash = sixgr.kpi.hashKPISourceRows(G);
layer.SchemaValid = true;
layer.AllocatedPRBSymbols = allocated;
layer.AvailablePRBSymbols = available;
layer.PRBUtilization = allocated / available;
layer.Status = "pass";
layer.FailureReason = "";
end

function [available, slotIndex, slotSweep, symStart, symCount, ok, reason] = localAvailablePRBSymbols(S, direction, nRB, nCells, symbolsPerSlot)
available = NaN;
slotIndex = [];
slotSweep = [];
symStart = [];
symCount = [];
ok = false;
reason = "slot_trace_schema_invalid";
vars = string(S.Properties.VariableNames);
if ~any(ismember(["CanonicalSlot","Slot","TTI"], vars))
    return;
end
if direction == "DL"
    startName = "DLSymbolStart";
    countName = "DLNumSymbols";
else
    startName = "ULSymbolStart";
    countName = "ULNumSymbols";
end
if ~all(ismember([startName,countName], vars))
    reason = "slot_trace_directional_symbol_partition_missing";
    return;
end
slotIndex = localFirstNumeric(S, ["CanonicalSlot","Slot","TTI"], NaN(height(S), 1));
slotSweep = localFirstNumeric(S, ["SweepPointIndex"], NaN(height(S), 1));
symStart = double(S.(char(startName)));
symCount = double(S.(char(countName)));
if any(~isfinite(slotIndex)) || any(~isfinite(symStart)) || any(~isfinite(symCount)) || ...
        any(symStart < 0) || any(symCount < 0) || ...
        any(symStart + symCount > double(symbolsPerSlot))
    reason = "slot_trace_contains_invalid_slot_or_symbol_partition";
    return;
end
slotKey = "s" + string(slotSweep) + "_t" + string(slotIndex);
if numel(unique(slotKey)) ~= height(S)
    reason = "slot_trace_contains_duplicate_resource_opportunities";
    return;
end
available = sum(symCount, "omitnan") * double(nRB) * double(nCells);
if ~(isfinite(available) && available > 0)
    reason = "direction_has_no_available_prb_symbol_resources";
    return;
end
ok = true;
reason = "";
end

function values = localFirstLogical(T, names, defaultValue)
values = defaultValue;
vars = string(T.Properties.VariableNames);
for name = string(names)
    if ismember(name, vars)
        values = logical(T.(char(name)));
        return;
    end
end
end

function layer = localEmptyLayerMetrics(parent, layerName, sourcePath)
layer = parent;
layer.Layer = string(layerName);
layer.SourceTablePath = string(sourcePath);
layer.SourceRowCount = 0;
layer.EligibleRowCount = 0;
layer.ExcludedRowCount = 0;
layer.RowsWithExpectedDirection = 0;
layer.RowsWithWrongDirection = 0;
layer.SourceRowsHash = "empty";
layer.MissingRawData = true;
layer.SchemaValid = false;
layer.ProxyRowsExcluded = 0;
layer.SkippedRowsExcluded = 0;
layer.DeliveredBits = NaN;
layer.ComputedGoodput_Mbps = NaN;
layer.FirstSuccessDeliveryCount = 0;
layer.DuplicateDeliveryCount = 0;
layer.MeanDeliveryLatency_ms = NaN;
layer.P95DeliveryLatency_ms = NaN;
layer.Status = "missing_raw_data";
layer.FailureReason = "packet_delivery_ledger_missing_or_empty";
end

function layer = localFinalizeLayerMetrics(layer, T, deliveredBits, duplicateCount, firstCount, durationSec)
layer.EligibleRowCount = height(T);
layer.ExcludedRowCount = 0;
layer.SourceRowsHash = sixgr.kpi.hashKPISourceRows(T);
layer.SchemaValid = true;
layer.DeliveredBits = double(deliveredBits);
layer.DuplicateDeliveryCount = double(duplicateCount);
layer.FirstSuccessDeliveryCount = double(firstCount);
layer.MeasurementWindowSec = double(durationSec);
layer.AggregationDurationSec = double(durationSec);
layer.DurationSource = "packet_delivery_measurement_window";
if isfinite(durationSec) && durationSec > 0
    layer.ComputedGoodput_Mbps = double(deliveredBits) / double(durationSec) / 1e6;
    layer.Status = "pass";
    layer.FailureReason = "";
else
    layer.Status = "invalid_duration";
    layer.FailureReason = "packet_delivery_duration_unavailable";
end
end

function T = localRawTable(raw, fieldName)
T = table();
if isstruct(raw) && isfield(raw, char(fieldName)) && istable(raw.(char(fieldName)))
    T = raw.(char(fieldName));
end
end

function T = localFilterRawDirectionTable(Tin, direction)
direction = upper(string(direction));
T = table();
if ~(istable(Tin) && ~isempty(Tin))
    return;
end
if ~ismember("Direction", string(Tin.Properties.VariableNames))
    T = Tin;
    return;
end
mask = upper(strtrim(string(Tin.Direction))) == direction;
T = Tin(mask, :);
end

function missing = localMissingPacketColumns(T, names)
vars = string(T.Properties.VariableNames);
missingNames = strings(0, 1);
for name = string(names)
    if ~ismember(name, vars)
        missingNames(end+1, 1) = name; %#ok<AGROW>
    end
end
missing = strjoin(missingNames, ",");
end

function [bits, duplicateCount, firstCount] = localUniqueDeliveredPayloadBits(ids, payloadBits, success)
ids = string(ids(:));
payloadBits = double(payloadBits(:));
success = logical(success(:));
n = min([numel(ids), numel(payloadBits), numel(success)]);
ids = ids(1:n);
payloadBits = payloadBits(1:n);
success = success(1:n);
seen = strings(0, 1);
bits = 0;
duplicateCount = 0;
firstCount = 0;
for i = 1:n
    if ~success(i) || ~(isfinite(payloadBits(i)) && payloadBits(i) > 0)
        continue;
    end
    id = strtrim(ids(i));
    if strlength(id) == 0 || lower(id) == "nan"
        id = "row_" + string(i);
    end
    if any(seen == id)
        duplicateCount = duplicateCount + 1;
        continue;
    end
    seen(end+1, 1) = id; %#ok<AGROW>
    bits = bits + payloadBits(i);
    firstCount = firstCount + 1;
end
end

function durationSec = localPacketMeasurementWindowSec(T, parentMetrics, requestedWindowSec, warmupDurationSec)
durationSec = double(sixgr.util.structGet(parentMetrics, "MeasurementWindowSec", NaN));
if isfinite(durationSec) && durationSec > 0
    return;
end
[durationSec, ~] = localMeasurementWindowSec(T, NaN, "packet_delivery_ledger", requestedWindowSec, warmupDurationSec);
end

function [lat, ok, failureReason] = localPacketLatencyMs(T, success)
lat = [];
ok = true;
failureReason = "";
if ~(istable(T) && ~isempty(T))
    return;
end
vars = string(T.Properties.VariableNames);
precomputed = NaN(height(T), 1);
if ismember("Latency_ms", vars)
    precomputed = localOptionalNumeric(T, "Latency_ms", NaN(height(T), 1));
end
hasTimes = all(ismember(["EnqueueTime_s","DeliveryTime_s"], vars));
if hasTimes
    enqueueTime = localOptionalNumeric(T, "EnqueueTime_s", NaN(height(T), 1));
    deliveryTime = localOptionalNumeric(T, "DeliveryTime_s", NaN(height(T), 1));
    vals = (deliveryTime - enqueueTime) * 1e3;
    bothFinite = isfinite(precomputed) & isfinite(vals);
    mismatch = logical(success(:)) & bothFinite(:) & abs(precomputed(:) - vals(:)) > 1e-6;
    if any(mismatch)
        ok = false;
        failureReason = "packet_latency_precomputed_mismatch";
        return;
    end
else
    vals = precomputed;
end

succ = logical(success(:));
negative = succ & isfinite(vals(:)) & vals(:) < -1e-9;
if any(negative)
    ok = false;
    failureReason = "negative_successful_packet_latency";
    return;
end
if all(ismember(["EnqueueCanonicalSlot","DeliveryCanonicalSlot"], vars))
    enqueueSlot = localOptionalNumeric(T, "EnqueueCanonicalSlot", NaN(height(T), 1));
    deliverySlot = localOptionalNumeric(T, "DeliveryCanonicalSlot", NaN(height(T), 1));
elseif all(ismember(["EnqueueSlot","DeliverySlot"], vars))
    enqueueSlot = localOptionalNumeric(T, "EnqueueSlot", NaN(height(T), 1));
    deliverySlot = localOptionalNumeric(T, "DeliverySlot", NaN(height(T), 1));
else
    enqueueSlot = NaN(height(T), 1);
    deliverySlot = NaN(height(T), 1);
end
slotBackwards = succ & isfinite(enqueueSlot(:)) & isfinite(deliverySlot(:)) & deliverySlot(:) < enqueueSlot(:);
if any(slotBackwards)
    ok = false;
    failureReason = "delivery_slot_before_enqueue_slot";
    return;
end
lat = vals(succ & isfinite(vals(:)));
end

function [bits, duplicateCount, traceT] = localDeduplicateDeliveries(T, direction, runId, scheduledBits, goodBits, crcPass, resourceExposureSec, measurementWindowSec)
traceRows = repmat(localHARQTraceRow(), height(T), 1);
keys = localTransportBlockKeys(T, direction);
seenDelivered = strings(0, 1);
bits = 0;
duplicateCount = 0;
slotDur = localTrialSlotDurationSec(T);
rowDur = localRowDurationSec(T, resourceExposureSec);
attemptTime = localAttemptStartTimes(T, slotDur);
firstSchedule = containers.Map("KeyType", "char", "ValueType", "double");
for i = 1:height(T)
    keyChar = char(keys(i));
    if ~isKey(firstSchedule, keyChar)
        firstSchedule(keyChar) = attemptTime(i);
    end
    delivered = logical(crcPass(i)) && isfinite(goodBits(i)) && goodBits(i) > 0;
    duplicate = false;
    counted = 0;
    firstSuccess = false;
    firstSuccessTime = NaN;
    deliveryLatencyMs = NaN;
    if delivered
        if any(seenDelivered == keys(i))
            duplicate = true;
            duplicateCount = duplicateCount + 1;
        else
            seenDelivered(end+1, 1) = keys(i); %#ok<AGROW>
            counted = goodBits(i);
            bits = bits + counted;
            firstSuccess = true;
            firstSuccessTime = attemptTime(i) + rowDur(i);
            deliveryLatencyMs = (firstSuccessTime - firstSchedule(keyChar)) * 1e3;
        end
    end
    traceRows(i).RunId = string(runId);
    traceRows(i).Direction = direction;
    traceRows(i).TransportBlockId = keys(i);
    traceRows(i).Codeword = localRowNum(T, "Codeword", i, localRowNum(T, "CodewordIndex", i, 0));
    traceRows(i).UEId = localRowNum(T, "UEIndex", i, localRowNum(T, "UEId", i, NaN));
    traceRows(i).HARQProcessId = localRowNum(T, "HARQProcessId", i, NaN);
    traceRows(i).AttemptIndex = i;
    traceRows(i).RV = localRowNum(T, "RV", i, NaN);
    traceRows(i).NDI = localRowNum(T, "NDI", i, NaN);
    traceRows(i).NewDataFlag = localNewDataFlag(T, i);
    traceRows(i).RetransmissionFlag = localRetransmissionFlag(T, i);
    traceRows(i).ScheduleTime_s = firstSchedule(keyChar);
    traceRows(i).AttemptStartTime_s = attemptTime(i);
    traceRows(i).AttemptEndTime_s = attemptTime(i) + rowDur(i);
    traceRows(i).FirstSuccessTime_s = firstSuccessTime;
    traceRows(i).DeliveryLatency_ms = deliveryLatencyMs;
    traceRows(i).ScheduledBits = scheduledBits(i);
    traceRows(i).TBCrcPass = logical(crcPass(i));
    traceRows(i).DeliveredThisAttempt = delivered;
    traceRows(i).FirstSuccessDelivery = firstSuccess;
    traceRows(i).DuplicateDelivery = duplicate;
    traceRows(i).CountedGoodputBits = counted;
    traceRows(i).ScheduledResourceExposureSec = resourceExposureSec;
    traceRows(i).MeasurementWindowSec = measurementWindowSec;
    traceRows(i).DeliveryStatus = string(localTernary(delivered, "delivered", "not_delivered"));
    if duplicate
        traceRows(i).DeliveryStatus = "duplicate_delivery_not_counted";
    elseif firstSuccess
        traceRows(i).DeliveryStatus = "first_success_delivery_counted";
    end
    traceRows(i).Status = "pass";
end
traceT = struct2table(traceRows);
end

function keys = localTransportBlockKeys(T, direction)
keys = strings(height(T), 1);
active = containers.Map("KeyType", "char", "ValueType", "char");
delivered = containers.Map("KeyType", "char", "ValueType", "logical");
instance = containers.Map("KeyType", "char", "ValueType", "double");
for i = 1:height(T)
    explicit = localExplicitTransportBlockKey(T, i);
    if strlength(explicit) > 0
        keys(i) = explicit;
        continue;
    end
    base = localTransportBlockBaseKey(T, i, direction);
    baseChar = char(base);
    isNew = localNewDataFlag(T, i);
    if ~isKey(active, baseChar) || isNew
        nextInstance = 1;
        if isKey(instance, baseChar)
            nextInstance = instance(baseChar) + 1;
        end
        instance(baseChar) = nextInstance;
        active(baseChar) = char(base + "_tb" + string(nextInstance));
        delivered(active(baseChar)) = false;
    end
    keys(i) = string(active(baseChar));
    if localOptionalLogical(T(i, :), "TBCrcPass", localOptionalLogical(T(i, :), "CRCPass", false)) && ...
            localFirstNumeric(T(i, :), ["GoodputBits","GoodBits","DeliveredBits","PayloadBits","TBSize_bits"], NaN) > 0
        delivered(active(baseChar)) = true;
    end
end
end

function key = localExplicitTransportBlockKey(T, i)
vars = string(T.Properties.VariableNames);
% A grant context identifies the frozen scheduling/PHY contract, not a
% transport-block lifecycle.  Multiple new-data TBs can legitimately reuse
% one grant context (for example, a fixed-link campaign operating point).
% Treating GrantContextId as a TB identity collapses distinct successful
% new-data attempts into duplicate deliveries and corrupts goodput.  Only
% explicit packet/TB lifecycle identifiers are authoritative here; when
% they are absent localTransportBlockKeys derives a new-data-instance key
% from UE/HARQ/NDI/codeword state.
for name = ["TransportBlockId","TBId","MACPDUId","MACSDUId"]
    if ismember(name, vars)
        raw = string(T.(name)(i));
        if strlength(strtrim(raw)) > 0 && raw ~= "NaN"
            key = raw;
            return;
        end
    end
end
key = "";
end

function key = localTransportBlockBaseKey(T, i, direction)
ue = localRowNum(T, "UEIndex", i, localRowNum(T, "UEId", i, NaN));
rnti = localRowNum(T, "RNTI", i, NaN);
harq = localRowNum(T, "HARQProcessId", i, NaN);
if ~isfinite(harq)
    harq = localRowNum(T, "HARQProcess", i, NaN);
end
ndi = localRowNum(T, "NDI", i, NaN);
cw = localRowNum(T, "Codeword", i, localRowNum(T, "CodewordIndex", i, 0));
key = "derived_" + upper(string(direction)) + "_ue" + localKeyToken(ue) + "_rnti" + localKeyToken(rnti) + ...
    "_harq" + localKeyToken(harq) + "_ndi" + localKeyToken(ndi) + "_cw" + localKeyToken(cw);
end

function token = localKeyToken(value)
value = double(value);
if isempty(value) || ~isfinite(value(1))
    token = "nan";
else
    token = string(value(1));
end
end

function tf = localNewDataFlag(T, i)
tf = localOptionalLogical(T(i, :), "NewDataFlag", false);
if tf
    return;
end
isRetx = localRetransmissionFlag(T, i);
rv = localRowNum(T, "RV", i, NaN);
tf = ~isRetx && (~isfinite(rv) || abs(rv) < 1e-12);
end

function tf = localRetransmissionFlag(T, i)
tf = localOptionalLogical(T(i, :), "RetransmissionFlag", false);
if tf
    return;
end
tf = localOptionalLogical(T(i, :), "HARQIsRetransmission", false);
if tf
    return;
end
rv = localRowNum(T, "RV", i, localRowNum(T, "HARQRV", i, NaN));
tf = isfinite(rv) && abs(rv) > 1e-12;
end

function summary = localBuildLegacySummary(runId, scenarioName, ul, dl, strictMode)
row = struct();
row.RunId = runId;
row.ScenarioName = scenarioName;
row.BLER_DL_min = dl.BLER;
row.BLER_UL_min = ul.BLER;
row.Goodput_DL_max_Mbps = dl.GoodputMax_Mbps;
row.Goodput_UL_max_Mbps = ul.GoodputMax_Mbps;
row.RequiredSNR_DL_10pctBLER = NaN;
row.RequiredSNR_UL_10pctBLER = NaN;
row.KPIFormulaVersion = "kpi_registry_v1";
row.KPIReconciliationPass = strcmp(ul.Status, "pass") && strcmp(dl.Status, "pass");
row.StrictOk = row.KPIReconciliationPass || ~strictMode;
row.Status = string(localTernary(row.KPIReconciliationPass, "pass", "fail"));
row.FailureReason = strjoin(unique([string(ul.FailureReason); string(dl.FailureReason)], "stable"), "|");
row.ULSourceRowsHash = ul.SourceRowsHash;
row.DLSourceRowsHash = dl.SourceRowsHash;
row.ULSourceRowCount = ul.SourceRowCount;
row.DLSourceRowCount = dl.SourceRowCount;
row.ULEligibleRowCount = ul.EligibleRowCount;
row.DLEligibleRowCount = dl.EligibleRowCount;
row.ULSourceDirection = "UL";
row.DLSourceDirection = "DL";
summary = struct2table(row);
end

function T = localBuildReconstructionSummary(runId, scenarioName, registry, ul, dl, exportedSummary, featureApplicability)
defs = [
    localRecon("UL_Goodput_Max_Mbps", ul, "GoodputMax_Mbps", "Goodput_UL_max_Mbps");
    localRecon("DL_Goodput_Max_Mbps", dl, "GoodputMax_Mbps", "Goodput_DL_max_Mbps");
    localRecon("UL_PHY_ScheduledThroughput_Mbps", ul, "ScheduledThroughput_Mbps", "");
    localRecon("DL_PHY_ScheduledThroughput_Mbps", dl, "ScheduledThroughput_Mbps", "");
    localRecon("UL_TB_Delivery_Goodput_Mbps", ul, "TBGoodput_Mbps", "");
    localRecon("DL_TB_Delivery_Goodput_Mbps", dl, "TBGoodput_Mbps", "");
    localRecon("UL_SpectralEfficiency_bpsHz", ul, "SpectralEfficiency_bpsHz", "");
    localRecon("DL_SpectralEfficiency_bpsHz", dl, "SpectralEfficiency_bpsHz", "");
    localRecon("UL_Latency_ms", ul, "MeanDeliveryLatency_ms", "");
    localRecon("DL_Latency_ms", dl, "MeanDeliveryLatency_ms", "");
    localRecon("UL_BLER", ul, "BLER", "BLER_UL_min");
    localRecon("DL_BLER", dl, "BLER", "BLER_DL_min");
    localRecon("UL_BER", ul, "BER", "");
    localRecon("DL_BER", dl, "BER", "");
    localRecon("UL_HARQ_NACK_Rate", ul.HARQ, "NACKRate", "");
    localRecon("DL_HARQ_NACK_Rate", dl.HARQ, "NACKRate", "");
    localRecon("UL_Retransmission_Rate", ul.HARQ, "RetransmissionRate", "");
    localRecon("DL_Retransmission_Rate", dl.HARQ, "RetransmissionRate", "");
    localRecon("UL_PRB_Utilization", ul.Scheduler, "PRBUtilization", "");
    localRecon("DL_PRB_Utilization", dl.Scheduler, "PRBUtilization", "");
    localRecon("Scenario_Total_UL_DeliveredBits", ul, "DeliveredBits", "");
    localRecon("Scenario_Total_DL_DeliveredBits", dl, "DeliveredBits", "");
    localRecon("Scenario_Total_UL_ScheduledBits", ul, "ScheduledBits", "");
    localRecon("Scenario_Total_DL_ScheduledBits", dl, "ScheduledBits", "")
    ];
if localLayerEvidencePresent(ul, "MAC")
    defs = [defs; localRecon("UL_MAC_Goodput_Mbps", ul.MAC, "ComputedGoodput_Mbps", "")]; %#ok<AGROW>
end
if localLayerEvidencePresent(dl, "MAC")
    defs = [defs; localRecon("DL_MAC_Goodput_Mbps", dl.MAC, "ComputedGoodput_Mbps", "")]; %#ok<AGROW>
end
if localLayerEvidencePresent(ul, "Application")
    defs = [defs; localRecon("UL_Application_Goodput_Mbps", ul.Application, "ComputedGoodput_Mbps", "")]; %#ok<AGROW>
end
if localLayerEvidencePresent(dl, "Application")
    defs = [defs; localRecon("DL_Application_Goodput_Mbps", dl.Application, "ComputedGoodput_Mbps", "")]; %#ok<AGROW>
end
rows = repmat(localReconRow(), numel(defs), 1);
for i = 1:numel(defs)
    d = defs(i);
    r = registry(strcmp(string(registry.KPIName), d.KPIName), :);
    if isempty(r)
        formulaVersion = "";
        units = "";
        layer = "";
        tolerance = 1e-9;
    else
        formulaVersion = string(r.FormulaVersion(1));
        units = string(r.Units(1));
        layer = string(r.Layer(1));
        tolerance = double(r.Tolerance(1));
    end
    exported = localExportedValue(exportedSummary, d.LegacyAlias);
    value = double(d.Value);
    delta = abs(exported - value);
    if ~isfinite(exported)
        delta = NaN;
        pass = isfinite(value);
    else
        pass = isfinite(value) && delta <= tolerance;
    end
    rows(i).RunId = runId;
    rows(i).ScenarioName = scenarioName;
    rows(i).KPIName = d.KPIName;
    rows(i).Direction = d.Metrics.Direction;
    rows(i).Layer = layer;
    rows(i).Units = units;
    rows(i).FormulaId = d.KPIName;
    rows(i).FormulaVersion = formulaVersion;
    rows(i).NumeratorValue = localNumeratorValue(d.Metrics, d.KPIName);
    rows(i).DenominatorValue = localDenominatorValue(d.Metrics, d.KPIName);
    rows(i).Value = value;
    rows(i).AggregationDurationSec = localAggregationDurationValue(d.Metrics, d.KPIName);
    rows(i).DurationSource = localDurationSourceValue(d.Metrics, d.KPIName);
    rows(i).ScheduledResourceExposureSec = d.Metrics.ScheduledResourceExposureSec;
    rows(i).MeasurementWindowSec = d.Metrics.MeasurementWindowSec;
    rows(i).WarmupDurationSec = d.Metrics.WarmupDurationSec;
    rows(i).FirstSuccessDeliveryCount = d.Metrics.FirstSuccessDeliveryCount;
    rows(i).RetransmissionAttemptCount = d.Metrics.RetransmissionAttemptCount;
    rows(i).MeanDeliveryLatency_ms = d.Metrics.MeanDeliveryLatency_ms;
    rows(i).P95DeliveryLatency_ms = d.Metrics.P95DeliveryLatency_ms;
    rows(i).SourceTablePaths = d.Metrics.SourceTablePath;
    rows(i).SourceRowCount = d.Metrics.SourceRowCount;
    rows(i).EligibleRowCount = d.Metrics.EligibleRowCount;
    rows(i).ExcludedRowCount = d.Metrics.ExcludedRowCount;
    rows(i).SourceRowsHash = d.Metrics.SourceRowsHash;
    rows(i).SourceDirection = d.Metrics.Direction;
    rows(i).ProxyRowsExcluded = d.Metrics.ProxyRowsExcluded;
    rows(i).SkippedRowsExcluded = d.Metrics.SkippedRowsExcluded;
    rows(i).FailedRowsIncluded = true;
    rows(i).HARQDeduplicationApplied = contains(d.KPIName, "Goodput");
    rows(i).DuplicateDeliveryCount = d.Metrics.DuplicateDeliveryCount;
    rows(i).MissingRawData = d.Metrics.MissingRawData;
    rows(i).SchemaValid = d.Metrics.SchemaValid;
    [applicable, applicabilityReason] = localKPIApplicability(d.KPIName, featureApplicability);
    rows(i).Applicable = logical(applicable);
    rows(i).ApplicabilityReason = string(applicabilityReason);
    rows(i).FormulaExecuted = applicable && strcmp(d.Metrics.Status, "pass");
    rows(i).ExportedSummaryValue = exported;
    rows(i).ReconstructionValue = value;
    rows(i).ReconstructionDelta = delta;
    rows(i).ReconciliationTolerance = tolerance;
    if applicable
        rows(i).ReconciliationPass = pass;
        rows(i).StrictOk = pass && strcmp(d.Metrics.Status, "pass");
        rows(i).Status = string(localTernary(rows(i).StrictOk, "pass", "fail"));
        rows(i).FailureReason = string(localTernary(rows(i).StrictOk, "", d.Metrics.FailureReason));
    else
        rows(i).ReconciliationPass = true;
        rows(i).StrictOk = true;
        rows(i).Status = "not_applicable";
        rows(i).FailureReason = "";
    end
end
T = struct2table(rows);
end

function applicability = localResolveFeatureApplicability(input)
% An omitted applicability contract preserves the historical strict API:
% direct callers must provide all registry evidence. Production exporters
% pass the resolved configuration explicitly.
applicability = struct("HARQ",true,"Scheduler",true,"Latency",true, ...
    "MAC",true,"Application",true);
if isempty(input), return; end
for name = ["HARQ","Scheduler","Latency","MAC","Application"]
    raw = sixgr.util.structGet(input, name, applicability.(char(name)));
    if ~((islogical(raw) || isnumeric(raw)) && isscalar(raw) && isfinite(double(raw)))
        error("sixgr:kpi:InvalidFeatureApplicability", ...
            "FeatureApplicability.%s must be a finite logical scalar.", name);
    end
    applicability.(char(name)) = logical(raw);
end
end

function [applicable, reason] = localKPIApplicability(kpiName, applicability)
kpiName = string(kpiName);
if contains(kpiName, ["HARQ_NACK_Rate","Retransmission_Rate"])
    applicable = logical(applicability.HARQ);
    reason = localTernary(applicable, "harq_enabled", "harq_disabled_by_resolved_configuration");
elseif contains(kpiName, "PRB_Utilization")
    applicable = logical(applicability.Scheduler);
    reason = localTernary(applicable, "scheduler_enabled", "independent_fixed_link_has_no_scheduler");
elseif contains(kpiName, "Latency")
    applicable = logical(applicability.Latency);
    reason = localTernary(applicable, "packet_timing_required", "independent_fixed_link_has_no_application_latency");
elseif contains(kpiName, "MAC_Goodput_Mbps")
    applicable = logical(applicability.MAC);
    reason = localTernary(applicable, "same_waveform_mac_enabled", ...
        "same_waveform_protocol_stack_disabled");
elseif contains(kpiName, "Application_Goodput_Mbps")
    applicable = logical(applicability.Application);
    reason = localTernary(applicable, "same_waveform_application_delivery_enabled", ...
        "same_waveform_protocol_stack_disabled");
else
    applicable = true;
    reason = "always_applicable_raw_phy_kpi";
end
end

function tf = localLayerEvidencePresent(metrics, layerName)
tf = false;
if ~(isstruct(metrics) && isfield(metrics, char(layerName)))
    return;
end
layer = metrics.(char(layerName));
tf = isstruct(layer) && (~logical(sixgr.util.structGet(layer, "MissingRawData", true)) || ...
    double(sixgr.util.structGet(layer, "SourceRowCount", 0)) > 0);
end

function def = localRecon(name, metrics, field, alias)
def = struct("KPIName", string(name), "Metrics", metrics, ...
    "Value", double(metrics.(field)), "LegacyAlias", string(alias));
end

function T = localBuildDirectionIsolationAudit(runId, ul, dl)
rows = [localDirRow(runId, ul, dl); localDirRow(runId, dl, ul)];
T = struct2table(rows);
end

function row = localDirRow(runId, m, opp)
copySuspected = m.SourceRowsHash ~= "empty" && m.SourceRowsHash == opp.SourceRowsHash && m.Direction ~= opp.Direction;
row = struct( ...
    "RunId", string(runId), ...
    "KPIName", string(m.Direction) + "_directional_kpi_sources", ...
    "Direction", string(m.Direction), ...
    "SourceTablePath", string(m.SourceTablePath), ...
    "SourceDirection", string(m.Direction), ...
    "RowsWithExpectedDirection", double(m.RowsWithExpectedDirection), ...
    "RowsWithWrongDirection", double(m.RowsWithWrongDirection), ...
    "CrossDirectionSourceUsed", m.RowsWithWrongDirection > 0, ...
    "SourceRowsHash", string(m.SourceRowsHash), ...
    "OppositeDirectionRowsHash", string(opp.SourceRowsHash), ...
    "HashCollisionOrCopySuspected", logical(copySuspected), ...
    "Status", string(localTernary(m.RowsWithWrongDirection == 0 && ~copySuspected && ~m.MissingRawData, "pass", "fail")), ...
    "FailureReason", string(localTernary(m.RowsWithWrongDirection == 0 && ~copySuspected && ~m.MissingRawData, "", "direction_isolation_failed")));
end

function T = localBuildLegacyAliasMap(runId, registry, summary, recon)
aliases = [
    "Goodput_UL_max_Mbps", "UL_Goodput_Max_Mbps";
    "Goodput_DL_max_Mbps", "DL_Goodput_Max_Mbps";
    "BLER_UL_min", "UL_BLER";
    "BLER_DL_min", "DL_BLER"
    ];
rows = repmat(localAliasRow(), size(aliases, 1), 1);
for i = 1:size(aliases, 1)
    alias = aliases(i, 1);
    kpi = aliases(i, 2);
    idx = strcmp(string(recon.KPIName), kpi);
    ridx = strcmp(string(registry.KPIName), kpi);
    if any(ridx)
        firstRegistry = find(ridx, 1);
        layer = string(registry.Layer(firstRegistry));
        formulaVersion = string(registry.FormulaVersion(firstRegistry));
    else
        layer = "";
        formulaVersion = "";
    end
    aliasValue = localExportedValue(summary, alias);
    canonical = NaN;
    if any(idx)
        canonical = double(recon.ReconstructionValue(find(idx, 1)));
    end
    rows(i).RunId = runId;
    rows(i).LegacyAliasName = alias;
    rows(i).KPIName = kpi;
    rows(i).Direction = string(extractBefore(kpi, "_"));
    rows(i).Layer = layer;
    rows(i).FormulaId = kpi;
    rows(i).FormulaVersion = formulaVersion;
    rows(i).AliasValue = aliasValue;
    rows(i).CanonicalValue = canonical;
    rows(i).Equal = (isnan(aliasValue) && isnan(canonical)) || abs(aliasValue - canonical) <= 1e-9;
    rows(i).Status = string(localTernary(rows(i).Equal, "pass", "fail"));
    rows(i).FailureReason = string(localTernary(rows(i).Equal, "", "legacy_alias_mismatch"));
end
T = struct2table(rows);
end

function T = localBuildUnitAudit(runId, recon)
rows = repmat(struct("RunId","", "KPIName","", "Direction","", ...
    "Applicable",true, "ApplicabilityReason","", ...
    "Bits",NaN, "DurationSec",NaN, "ExpectedMbps",NaN, ...
    "ComputedMbps",NaN, "Delta",NaN, "Tolerance",1e-9, ...
    "Pass",false, "Status","", "FailureReason",""), 0, 1);
mask = contains(string(recon.KPIName), "ScheduledThroughput_Mbps") | ...
    contains(string(recon.KPIName), "TB_Delivery_Goodput_Mbps") | ...
    contains(string(recon.KPIName), "MAC_Goodput_Mbps") | ...
    contains(string(recon.KPIName), "Application_Goodput_Mbps");
idxs = find(mask(:).');
for j = 1:numel(idxs)
    i = idxs(j);
    applicable = true;
    applicabilityReason = "always_applicable_raw_phy_kpi";
    if ismember("Applicable", string(recon.Properties.VariableNames))
        applicable = logical(recon.Applicable(i));
    end
    if ismember("ApplicabilityReason", string(recon.Properties.VariableNames))
        applicabilityReason = string(recon.ApplicabilityReason(i));
    end
    row = struct("RunId",string(runId), "KPIName",string(recon.KPIName(i)), "Direction",string(recon.Direction(i)), ...
        "Applicable",applicable, "ApplicabilityReason",applicabilityReason, ...
        "Bits",double(recon.NumeratorValue(i)), "DurationSec",double(recon.AggregationDurationSec(i)), ...
        "ExpectedMbps",NaN, "ComputedMbps",double(recon.Value(i)), "Delta",NaN, "Tolerance",1e-9, ...
        "Pass",false, "Status","fail", "FailureReason","duration_or_bits_unavailable");
    if ~applicable
        row.Pass = true;
        row.Status = "not_applicable";
        row.FailureReason = "";
    elseif isfinite(row.Bits) && isfinite(row.DurationSec) && row.DurationSec > 0
        row.ExpectedMbps = row.Bits / row.DurationSec / 1e6;
        row.Delta = abs(row.ExpectedMbps - row.ComputedMbps);
        row.Pass = row.Delta <= row.Tolerance;
        row.Status = string(localTernary(row.Pass, "pass", "fail"));
        row.FailureReason = string(localTernary(row.Pass, "", "unit_conversion_mismatch"));
    end
    rows(end+1, 1) = row; %#ok<AGROW>
end
if isempty(rows)
    T = table();
else
    T = struct2table(rows);
end
end

function T = localBuildObjectiveBinding( ...
        runId, scenarioName, registry, recon, featureApplicability)
rows = repmat(struct("RunId","", "ScenarioName","", "KPIName","", "Direction","", ...
    "Layer","", "MandatoryInScenarioObjective",false, "FormulaId","", ...
    "Applicable",true, "ApplicabilityReason","", ...
    "RawEvidenceAvailable",false, "ReconstructionPass",false, "StrictOk",false, ...
    "ScenarioObjectiveContribution","not_configured", "Status","not_evaluated", "FailureReason",""), 0, 1);
for i = 1:height(registry)
    kpiName = string(registry.KPIName(i));
    idx = find(strcmp(string(recon.KPIName), kpiName), 1);
    [configuredApplicable, configuredApplicabilityReason] = ...
        localKPIApplicability(kpiName, featureApplicability);
    row = struct("RunId",string(runId), "ScenarioName",string(scenarioName), ...
        "KPIName",kpiName, "Direction",string(registry.Direction(i)), ...
        "Layer",string(registry.Layer(i)), ...
        "MandatoryInScenarioObjective",logical(registry.StrictAllowed(i)) && ...
        logical(configuredApplicable), ...
        "FormulaId",kpiName, "Applicable",logical(configuredApplicable), ...
        "ApplicabilityReason",string(configuredApplicabilityReason), ...
        "RawEvidenceAvailable",false, ...
        "ReconstructionPass",false, "StrictOk",false, ...
        "ScenarioObjectiveContribution","not_applicable", "Status","not_applicable", ...
        "FailureReason",string(configuredApplicabilityReason));
    if configuredApplicable
        row.ScenarioObjectiveContribution = string(localTernary( ...
            row.MandatoryInScenarioObjective, "mandatory", "optional"));
        row.Status = "not_evaluated";
        row.FailureReason = "applicable_kpi_missing_reconstruction_evidence";
    end
    if ~isempty(idx)
        applicable = true;
        if ismember("Applicable", string(recon.Properties.VariableNames))
            applicable = logical(recon.Applicable(idx));
        end
        row.Applicable = applicable;
        if ismember("ApplicabilityReason", string(recon.Properties.VariableNames))
            row.ApplicabilityReason = string(recon.ApplicabilityReason(idx));
        end
        row.MandatoryInScenarioObjective = row.MandatoryInScenarioObjective && applicable;
        row.RawEvidenceAvailable = ~logical(recon.MissingRawData(idx));
        row.ReconstructionPass = logical(recon.ReconciliationPass(idx));
        row.StrictOk = logical(recon.StrictOk(idx));
        row.ScenarioObjectiveContribution = string(localTernary(row.MandatoryInScenarioObjective, "mandatory", "optional"));
        if ~applicable
            row.Status = "not_applicable";
            row.FailureReason = row.ApplicabilityReason;
            row.ScenarioObjectiveContribution = "not_applicable";
        elseif ~row.RawEvidenceAvailable
            row.Status = string(localTernary(row.MandatoryInScenarioObjective, "fail", "not_evaluated"));
            row.FailureReason = string(recon.FailureReason(idx));
        elseif row.StrictOk
            row.Status = "pass";
            row.FailureReason = "";
        else
            row.Status = "fail";
            row.FailureReason = string(recon.FailureReason(idx));
        end
    end
    rows(end+1, 1) = row; %#ok<AGROW>
end
T = struct2table(rows);
end

function T = localBuildDurationAudit(runId, scenarioName, ul, dl)
rows = [localDurationRow(runId, scenarioName, ul); localDurationRow(runId, scenarioName, dl)];
T = struct2table(rows);
end

function row = localDurationRow(runId, scenarioName, m)
row = struct("RunId",string(runId), "ScenarioName",string(scenarioName), "Direction",string(m.Direction), ...
    "DurationSource",string(m.DurationSource), "SlotCount",double(m.EligibleRowCount), "Numerology",NaN, ...
    "SlotDurationSec",NaN, "RadioDurationSec",double(m.AggregationDurationSec), "WallClockDurationSec",NaN, ...
    "ScheduledResourceExposureSec",double(m.ScheduledResourceExposureSec), ...
    "MeasurementWindowSec",double(m.MeasurementWindowSec), "WarmupDurationSec",double(m.WarmupDurationSec), ...
    "AggregationDurationSec",double(m.AggregationDurationSec), "WallClockUsedForRadioThroughput",false, ...
    "Pass",isfinite(double(m.AggregationDurationSec)) && double(m.AggregationDurationSec) > 0 && ~contains(string(m.DurationSource), "wall"), ...
    "Status","", "FailureReason","");
row.Status = string(localTernary(row.Pass, "pass", "fail"));
row.FailureReason = string(localTernary(row.Pass, "", "invalid_radio_duration"));
end

function T = localBuildSourceManifest( ...
        runId, scenarioName, raw, sourcePaths, featureApplicability)
rows = [localManifestRow(runId, scenarioName, raw, sourcePaths, "UL", true); ...
    localManifestRow(runId, scenarioName, raw, sourcePaths, "DL", true); ...
    localManifestRow(runId, scenarioName, raw, sourcePaths, "PacketSDU", ...
    featureApplicability.MAC); ...
    localManifestRow(runId, scenarioName, raw, sourcePaths, "ApplicationPackets", ...
    featureApplicability.Application); ...
    localManifestRow(runId, scenarioName, raw, sourcePaths, "HARQTimeline", ...
    featureApplicability.HARQ); ...
    localManifestRow(runId, scenarioName, raw, sourcePaths, "ULGrants", ...
    featureApplicability.Scheduler); ...
    localManifestRow(runId, scenarioName, raw, sourcePaths, "DLGrants", ...
    featureApplicability.Scheduler); ...
    localManifestRow(runId, scenarioName, raw, sourcePaths, "SlotTrace", ...
    featureApplicability.Scheduler)];
T = struct2table(rows);
end

function row = localManifestRow( ...
        runId, scenarioName, raw, paths, direction, required)
T = table();
if isstruct(raw) && isfield(raw, char(direction)) && istable(raw.(char(direction)))
    T = raw.(char(direction));
end
path = localSourcePath(paths, direction);
layer = "PHY";
if string(direction) == "PacketSDU"
    layer = "MAC";
elseif string(direction) == "ApplicationPackets"
    layer = "application";
elseif string(direction) == "HARQTimeline"
    layer = "HARQ";
elseif any(string(direction) == ["ULGrants","DLGrants","SlotTrace"])
    layer = "scheduler";
end
row = struct("RunId",string(runId), "ScenarioName",string(scenarioName), ...
    "SourceTablePath",string(path), "SourceTableName",string(localSourceName(direction)), ...
    "Direction",string(direction), "Layer",string(layer), "RequiredForObjective",logical(required), ...
    "Exists",istable(T) && ~isempty(T), "RowCount",height(T), "ColumnCount",width(T), ...
    "FileHash",sixgr.kpi.hashKPISourceRows(T), "SchemaHash","kpi_schema_v1", ...
    "DLSubsetRowCount",0, "DLSubsetRowsHash","empty", ...
    "ULSubsetRowCount",0, "ULSubsetRowsHash","empty", ...
    "ProducerModule","sixgr.kpi.reconstructLLSKPISummaryFromRaw", ...
    "ModifiedTime","", "Status","", "FailureReason","");
if istable(T) && ~isempty(T) && ismember("Direction", string(T.Properties.VariableNames))
    dlSubset = localFilterRawDirectionTable(T, "DL");
    ulSubset = localFilterRawDirectionTable(T, "UL");
    row.DLSubsetRowCount = height(dlSubset);
    row.DLSubsetRowsHash = sixgr.kpi.hashKPISourceRows(dlSubset);
    row.ULSubsetRowCount = height(ulSubset);
    row.ULSubsetRowsHash = sixgr.kpi.hashKPISourceRows(ulSubset);
end
if row.Exists
    row.Status = "pass";
    row.FailureReason = "";
elseif row.RequiredForObjective
    row.Status = "missing";
    row.FailureReason = "source_table_missing_or_empty";
else
    row.Status = "not_applicable";
    row.FailureReason = "source_not_required_by_resolved_feature_applicability";
end
end

function path = localSourcePath(paths, direction)
path = "";
if isstruct(paths) && isfield(paths, char(direction))
    path = string(paths.(char(direction)));
end
if strlength(path) == 0
    direction = string(direction);
    if direction == "UL"
        path = "air_interface/csv/ul_pusch_trials.csv";
    elseif direction == "DL"
        path = "air_interface/csv/dl_pdsch_trials.csv";
    elseif direction == "PacketSDU"
        path = "packet_flow/csv/live_packet_sdu_delivery_ledger.csv";
    elseif direction == "ApplicationPackets"
        path = "packet_flow/csv/live_application_packet_delivery_ledger.csv";
    elseif direction == "HARQTimeline"
        path = "harq/csv/live_harq_observation_timeline.csv";
    elseif direction == "ULGrants"
        path = "packet_flow/csv/live_ul_scheduler_grants.csv";
    elseif direction == "DLGrants"
        path = "packet_flow/csv/live_dl_scheduler_grants.csv";
    elseif direction == "SlotTrace"
        path = "packet_flow/csv/slot_trace.csv";
    else
        path = "";
    end
end
end

function T = localBuildContributionTable(E, direction, runId, scenarioName, sourcePath, scheduledBits, goodBits, traceT, resourceExposureSec, measurementWindowSec)
rows = repmat(localContributionRow(), height(E), 1);
perRowDuration = resourceExposureSec / max(height(E), 1);
perRowDuration = localBestPerRowDurationSec(E, repmat(perRowDuration, height(E), 1));
perRowDuration = localDistributeUniqueSlotDuration(E, perRowDuration, resourceExposureSec);
crcPass = localOptionalLogical(E, "TBCrcPass", localOptionalLogical(E, "CRCPass", true(height(E), 1)));
for i = 1:height(E)
    rows(i).RunId = string(runId);
    rows(i).ScenarioName = string(scenarioName);
    rows(i).KPIName = direction + "_TB_Delivery_Goodput_Mbps";
    rows(i).FormulaId = direction + "_TB_Delivery_Goodput_Mbps";
    rows(i).Direction = direction;
    rows(i).SourceTablePath = string(sourcePath);
    rows(i).SourceRowIndex = i;
    rows(i).UEId = localRowNum(E, "UEIndex", i, localRowNum(E, "UEId", i, NaN));
    rows(i).TrialId = localRowNum(E, "TrialId", i, i);
    rows(i).Slot = localRowNum(E, "Slot", i, NaN);
    rows(i).Frame = localRowNum(E, "Frame", i, NaN);
    rows(i).TransportBlockId = string(traceT.TransportBlockId(i));
    rows(i).HARQProcessId = localRowNum(E, "HARQProcessId", i, NaN);
    rows(i).RV = localRowNum(E, "RV", i, NaN);
    rows(i).NDI = localRowNum(E, "NDI", i, NaN);
    rows(i).NewDataFlag = logical(traceT.NewDataFlag(i));
    rows(i).RetransmissionFlag = logical(traceT.RetransmissionFlag(i));
    rows(i).TBCrcPass = crcPass(i);
    rows(i).ScheduledBitsContribution = scheduledBits(i);
    rows(i).DeliveredBitsContribution = double(traceT.CountedGoodputBits(i));
    rows(i).GoodputBitsContribution = double(traceT.CountedGoodputBits(i));
    rows(i).DurationContributionSec = perRowDuration(i);
    rows(i).MeasurementWindowContributionSec = measurementWindowSec / max(height(E), 1);
    rows(i).ScheduleTime_s = double(traceT.ScheduleTime_s(i));
    rows(i).AttemptStartTime_s = double(traceT.AttemptStartTime_s(i));
    rows(i).AttemptEndTime_s = double(traceT.AttemptEndTime_s(i));
    rows(i).FirstSuccessTime_s = double(traceT.FirstSuccessTime_s(i));
    rows(i).DeliveryLatency_ms = double(traceT.DeliveryLatency_ms(i));
    rows(i).FirstSuccessDelivery = logical(traceT.FirstSuccessDelivery(i));
    rows(i).DuplicateDelivery = logical(traceT.DuplicateDelivery(i));
    rows(i).Included = true;
    rows(i).Status = "pass";
end
T = struct2table(rows);
end

function perRowDuration = localDistributeUniqueSlotDuration(T, perRowDuration, durationSec)
perRowDuration = double(perRowDuration(:));
if height(T) == 0
    return;
end
if ~ismember("Slot", string(T.Properties.VariableNames)) || ~(isfinite(durationSec) && durationSec > 0)
    if numel(perRowDuration) ~= height(T)
        perRowDuration = repmat(durationSec / max(height(T), 1), height(T), 1);
    end
    return;
end
slotVals = localOptionalNumeric(T, "Slot", NaN(height(T), 1));
valid = isfinite(slotVals) & isfinite(perRowDuration) & perRowDuration >= 0;
if ~any(valid)
    perRowDuration = repmat(durationSec / max(height(T), 1), height(T), 1);
    return;
end
out = zeros(height(T), 1);
slots = unique(slotVals(valid));
for i = 1:numel(slots)
    mask = slotVals == slots(i);
    vals = perRowDuration(mask & valid);
    if isempty(vals)
        continue;
    end
    slotDuration = max(vals);
    out(mask) = slotDuration / max(nnz(mask), 1);
end
missing = ~(out > 0);
if any(missing)
    out(missing) = durationSec / max(height(T), 1);
end
scale = sum(out, "omitnan");
if isfinite(scale) && scale > 0
    out = out .* (durationSec / scale);
end
perRowDuration = out;
end

function [durationSec, source] = localDurationSec(T)
durationSec = NaN;
source = "unavailable";
sources = [
    "DurationSec", "raw_duration_sec"
    "AirInterfaceObservation_ms", "air_interface_observation_ms"
    "AirInterfaceTTI_ms", "air_interface_tti_ms"];
for i = 1:size(sources, 1)
    [vals, exists] = localDurationColumnSec(T, sources(i, 1));
    if ~exists
        continue;
    end
    finitePositive = isfinite(vals) & vals > 0;
    if ~any(finitePositive)
        continue;
    end
    [durationSec, source] = localUniqueSlotDurationSec(T, vals, sources(i, 2) + "_unique_slot");
    if ~(isfinite(durationSec) && durationSec > 0)
        durationSec = sum(vals(isfinite(vals) & vals >= 0), "omitnan");
        source = sources(i, 2) + "_sum";
    end
    if isfinite(durationSec) && durationSec > 0
        return;
    end
end
if ~(isfinite(durationSec) && durationSec > 0)
    if localHasExplicitSlotDuration(T)
        slotDurationSec = localTrialSlotDurationSec(T);
        finalized = true(height(T), 1);
        if ismember("FinalizedFlag", string(T.Properties.VariableNames))
            finalized = localOptionalLogical(T, "FinalizedFlag", finalized);
        end
        durationSec = sum(finalized) * slotDurationSec;
        source = "explicit_slot_duration_trial_count";
    end
end
if ~(isfinite(durationSec) && durationSec > 0)
    durationSec = NaN;
    source = "unavailable";
end
end

function tf = localHasExplicitSlotDuration(T)
tf = any(ismember(["SlotDuration_s","slot_duration_s","SlotDuration_ms","slot_duration_ms"], string(T.Properties.VariableNames)));
end

function [durationSec, source] = localMeasurementWindowSec(T, resourceExposureSec, resourceExposureSource, requestedWindowSec, warmupDurationSec)
durationSec = NaN;
source = "unavailable";
requestedWindowSec = double(requestedWindowSec);
warmupDurationSec = max(0, double(warmupDurationSec));
if isfinite(requestedWindowSec) && requestedWindowSec > 0
    durationSec = max(requestedWindowSec - warmupDurationSec, eps);
    source = "configured_measurement_window_sec";
    return;
end
for name = ["MeasurementWindowSec","MeasurementWindow_s","ScenarioMeasurementWindowSec","ScenarioDurationSec","RunDurationSec"]
    if ismember(name, string(T.Properties.VariableNames))
        vals = localOptionalNumeric(T, name, NaN(height(T), 1));
        vals = vals(isfinite(vals) & vals > 0);
        if ~isempty(vals)
            durationSec = max(vals) - warmupDurationSec;
            if isfinite(durationSec) && durationSec > 0
                source = lower(string(name));
                return;
            end
        end
    end
end
for name = ["MeasurementWindow_ms","ScenarioDuration_ms","RunDuration_ms"]
    if ismember(name, string(T.Properties.VariableNames))
        vals = localOptionalNumeric(T, name, NaN(height(T), 1));
        vals = vals(isfinite(vals) & vals > 0);
        if ~isempty(vals)
            durationSec = max(vals) / 1e3 - warmupDurationSec;
            if isfinite(durationSec) && durationSec > 0
                source = lower(string(name));
                return;
            end
        end
    end
end
if isfinite(resourceExposureSec) && resourceExposureSec > 0
    durationSec = resourceExposureSec;
    source = "active_resource_exposure_fallback:" + string(resourceExposureSource);
end
end

function rowDur = localRowDurationSec(T, resourceExposureSec)
n = height(T);
rowDur = repmat(resourceExposureSec / max(n, 1), n, 1);
if n == 0
    return;
end
rowDur = localBestPerRowDurationSec(T, rowDur);
rowDur = double(rowDur(:));
rowDur(~isfinite(rowDur) | rowDur < 0) = resourceExposureSec / max(n, 1);
end

function rowDur = localBestPerRowDurationSec(T, fallbackSec)
n = height(T);
rowDur = double(fallbackSec(:));
if numel(rowDur) ~= n
    rowDur = repmat(double(fallbackSec(1)), n, 1);
end
filled = isfinite(rowDur) & rowDur > 0;
for name = ["DurationSec","AirInterfaceObservation_ms","AirInterfaceTTI_ms"]
    [vals, exists] = localDurationColumnSec(T, name);
    if ~exists
        continue;
    end
    vals = double(vals(:));
    mask = isfinite(vals) & vals > 0 & ~filled;
    rowDur(mask) = vals(mask);
    filled(mask) = true;
end
invalid = ~(isfinite(rowDur) & rowDur >= 0);
if any(invalid)
    fallbackVals = double(fallbackSec(:));
    if isempty(fallbackVals) || ~isfinite(fallbackVals(1))
        fallbackVals = 0;
    end
    rowDur(invalid) = fallbackVals(1);
end
end

function [valsSec, exists] = localDurationColumnSec(T, name)
name = string(name);
exists = ismember(name, string(T.Properties.VariableNames));
valsSec = NaN(height(T), 1);
if ~exists
    return;
end
vals = localOptionalNumeric(T, name, NaN(height(T), 1));
if endsWith(name, "_ms")
    valsSec = vals ./ 1e3;
else
    valsSec = vals;
end
end

function t = localAttemptStartTimes(T, slotDurationSec)
n = height(T);
t = NaN(n, 1);
for name = ["AttemptStartTime_s","ScheduleTime_s","EventTime_s","Time_s","RuntimeSlotStartTime_s"]
    if ismember(name, string(T.Properties.VariableNames))
        vals = localOptionalNumeric(T, name, NaN(n, 1));
        mask = isfinite(vals);
        t(mask) = vals(mask);
        if all(isfinite(t))
            return;
        end
    end
end
frame = localOptionalNumeric(T, "Frame", NaN(n, 1));
slot = localOptionalNumeric(T, "Slot", NaN(n, 1));
slotDurationSec = max(eps, double(slotDurationSec));
for i = 1:n
    if isfinite(frame(i)) && isfinite(slot(i))
        t(i) = max(0, double(frame(i) - 1)) * 0.01 + max(0, double(slot(i) - 1)) * slotDurationSec;
    elseif isfinite(slot(i))
        t(i) = max(0, double(slot(i) - 1)) * slotDurationSec;
    else
        t(i) = max(0, i - 1) * slotDurationSec;
    end
end
end

function value = localPercentile(x, pct)
x = sort(double(x(:)));
x = x(isfinite(x));
if isempty(x)
    value = NaN;
    return;
end
pct = min(max(double(pct), 0), 100);
pos = 1 + (numel(x) - 1) * pct / 100;
lo = floor(pos);
hi = ceil(pos);
if lo == hi
    value = x(lo);
else
    value = x(lo) + (x(hi) - x(lo)) * (pos - lo);
end
end

function slotDurationSec = localTrialSlotDurationSec(T)
slotDurationSec = NaN;
for name = ["SlotDuration_s","slot_duration_s"]
    if ismember(name, string(T.Properties.VariableNames))
        vals = localOptionalNumeric(T, name, NaN(height(T), 1));
        vals = vals(isfinite(vals) & vals > 0);
        if ~isempty(vals)
            slotDurationSec = vals(1);
            return;
        end
    end
end
for name = ["SlotDuration_ms","slot_duration_ms","AirInterfaceTTI_ms"]
    if ismember(name, string(T.Properties.VariableNames))
        vals = localOptionalNumeric(T, name, NaN(height(T), 1));
        vals = vals(isfinite(vals) & vals > 0);
        if ~isempty(vals)
            slotDurationSec = vals(1) / 1e3;
            return;
        end
    end
end
slotDurationSec = 0.5e-3;
end

function [durationSec, source] = localUniqueSlotDurationSec(T, rowDurSec, sourceToken)
durationSec = NaN;
source = "unavailable";
if ~ismember("Slot", string(T.Properties.VariableNames))
    return;
end
slotVals = localOptionalNumeric(T, "Slot", NaN(height(T), 1));
rowDurSec = double(rowDurSec(:));
valid = isfinite(slotVals) & isfinite(rowDurSec) & rowDurSec >= 0;
if ~any(valid)
    return;
end
slotVals = slotVals(valid);
rowDurSec = rowDurSec(valid);
slots = unique(slotVals);
slotDur = NaN(numel(slots), 1);
for i = 1:numel(slots)
    vals = rowDurSec(slotVals == slots(i));
    vals = vals(isfinite(vals) & vals >= 0);
    if ~isempty(vals)
        slotDur(i) = max(vals);
    end
end
durationSec = sum(slotDur(isfinite(slotDur) & slotDur >= 0), "omitnan");
if isfinite(durationSec) && durationSec > 0
    source = string(sourceToken);
end
end

function missing = localMissingCoreColumns(T)
vars = string(T.Properties.VariableNames);
missingParts = strings(0, 1);
if ~ismember("Goodput_Mbps", vars)
    missingParts(end+1, 1) = "Goodput_Mbps"; %#ok<AGROW>
end
if ~any(ismember(["CRCPass","TBCrcPass"], vars))
    missingParts(end+1, 1) = "CRCPass_or_TBCrcPass"; %#ok<AGROW>
end
if ~ismember("BitErrors", vars)
    missingParts(end+1, 1) = "BitErrors"; %#ok<AGROW>
end
if ~ismember("BitsCompared", vars)
    missingParts(end+1, 1) = "BitsCompared"; %#ok<AGROW>
end
if ~any(ismember(["ScheduledBits","TBSize_bits","OfferedBits","TBS"], vars))
    missingParts(end+1, 1) = "ScheduledBits_or_TBSize_bits_or_OfferedBits_or_TBS"; %#ok<AGROW>
end
missing = strjoin(missingParts, ",");
end

function x = localFirstNumeric(T, names, defaultValue)
x = defaultValue;
for name = string(names)
    if ismember(name, string(T.Properties.VariableNames))
        x = localOptionalNumeric(T, name, defaultValue);
        return;
    end
end
end

function x = localOptionalNumeric(T, name, defaultValue)
x = defaultValue;
if istable(T) && ismember(string(name), string(T.Properties.VariableNames))
    try
        x = double(T.(string(name)));
    catch
        x = str2double(string(T.(string(name))));
    end
    x = x(:);
end
end

function x = localOptionalLogical(T, name, defaultValue)
x = defaultValue;
if istable(T) && ismember(string(name), string(T.Properties.VariableNames))
    raw = T.(string(name));
    if islogical(raw)
        x = logical(raw(:));
    elseif isnumeric(raw)
        x = double(raw(:)) ~= 0;
    else
        s = lower(strtrim(string(raw(:))));
        x = ismember(s, ["true","1","yes","pass","ok"]);
    end
end
end

function v = localRowNum(T, name, i, defaultValue)
v = defaultValue;
if istable(T) && ismember(string(name), string(T.Properties.VariableNames))
    try
        raw = T.(string(name));
        v = double(raw(i));
    catch
        v = str2double(string(T.(string(name))(i)));
    end
end
end

function v = localMaxFinite(x)
x = double(x(:));
x = x(isfinite(x));
if isempty(x)
    v = NaN;
else
    v = max(x);
end
end

function v = localExportedValue(T, name)
v = NaN;
name = string(name);
if strlength(name) == 0 || ~(istable(T) && ~isempty(T)) || ~ismember(name, string(T.Properties.VariableNames))
    return;
end
try
    raw = T.(name);
    v = double(raw(1));
catch
    v = str2double(string(T.(name)(1)));
end
end

function b = localColumnBool(T, name, defaultValue)
if islogical(defaultValue)
    b = repmat(defaultValue, height(T), 1);
else
    b = false(height(T), 1);
end
if istable(T) && ismember(string(name), string(T.Properties.VariableNames))
    if islogical(T.(string(name)))
        b = logical(T.(string(name)));
    elseif isstring(T.(string(name))) || iscellstr(T.(string(name))) || ischar(T.(string(name)))
        b = strcmpi(string(T.(string(name))), string(defaultValue));
    else
        b = logical(T.(string(name)));
    end
end
end

function v = localNumeratorValue(metrics, kpiName)
if contains(kpiName, "HARQ_NACK_Rate")
    v = metrics.NACKCount;
elseif contains(kpiName, "Retransmission_Rate")
    v = metrics.RetransmissionAttemptCount;
elseif contains(kpiName, "PRB_Utilization")
    v = metrics.AllocatedPRBSymbols;
elseif contains(kpiName, "_ScheduledBits")
    v = metrics.ScheduledBits;
elseif contains(kpiName, "_DeliveredBits")
    v = metrics.DeliveredBits;
elseif contains(kpiName, "ScheduledThroughput")
    v = metrics.ScheduledBits;
elseif contains(kpiName, "Goodput")
    v = metrics.DeliveredBits;
elseif contains(kpiName, "SpectralEfficiency")
    v = metrics.DeliveredBits;
elseif contains(kpiName, "Latency")
    v = metrics.MeanDeliveryLatency_ms;
elseif contains(kpiName, "BLER")
    v = NaN;
elseif contains(kpiName, "BER")
    v = NaN;
else
    v = NaN;
end
if contains(kpiName, "Goodput_Max")
    v = metrics.GoodputMax_Mbps;
end
end

function v = localDenominatorValue(metrics, kpiName)
if contains(kpiName, "HARQ_NACK_Rate")
    v = metrics.ACKNACKEventCount;
elseif contains(kpiName, "Retransmission_Rate")
    v = metrics.TotalAttemptCount;
elseif contains(kpiName, "PRB_Utilization")
    v = metrics.AvailablePRBSymbols;
elseif contains(kpiName, "ScheduledThroughput")
    v = metrics.ScheduledResourceExposureSec;
elseif contains(kpiName, "Goodput")
    v = metrics.MeasurementWindowSec;
elseif contains(kpiName, "SpectralEfficiency")
    v = metrics.MeasurementWindowSec;
elseif contains(kpiName, "Latency")
    v = metrics.FirstSuccessDeliveryCount;
elseif contains(kpiName, "Throughput")
    v = metrics.AggregationDurationSec;
else
    v = metrics.SourceRowCount;
end
end

function v = localAggregationDurationValue(metrics, kpiName)
if contains(kpiName, "ScheduledThroughput")
    v = metrics.ScheduledResourceExposureSec;
elseif contains(kpiName, "Goodput") || contains(kpiName, "SpectralEfficiency")
    v = metrics.MeasurementWindowSec;
else
    v = metrics.AggregationDurationSec;
end
end

function source = localDurationSourceValue(metrics, kpiName)
if contains(kpiName, "ScheduledThroughput")
    source = "scheduled_resource_exposure:" + string(metrics.DurationSource);
elseif contains(kpiName, "Goodput") || contains(kpiName, "SpectralEfficiency")
    source = "measurement_window:" + string(metrics.DurationSource);
else
    source = string(metrics.DurationSource);
end
end

function name = localSourceName(direction)
direction = string(direction);
if direction == "UL"
    name = "ul_pusch_trials";
elseif direction == "DL"
    name = "dl_pdsch_trials";
elseif direction == "PacketSDU"
    name = "packet_sdu_delivery_ledger";
elseif direction == "ApplicationPackets"
    name = "application_packet_delivery_ledger";
elseif direction == "HARQTimeline"
    name = "harq_observation_timeline";
elseif direction == "ULGrants"
    name = "scheduler_ul_grants";
elseif direction == "DLGrants"
    name = "scheduler_dl_grants";
elseif direction == "SlotTrace"
    name = "slot_trace";
else
    name = "unknown";
end
end

function T = localEmptyContributionTable()
T = struct2table(repmat(localContributionRow(), 0, 1));
end

function row = localContributionRow()
row = struct("RunId","", "ScenarioName","", "KPIName","", "FormulaId","", "Direction","", ...
    "SourceTablePath","", "SourceRowIndex",NaN, "CellId",NaN, "UEId",NaN, "TrialId",NaN, ...
    "Slot",NaN, "Frame",NaN, "TransportBlockId","", "MACPDUId","", "MACSDUId","", ...
    "HARQProcessId",NaN, "RV",NaN, "NDI",NaN, "NewDataFlag",false, "RetransmissionFlag",false, ...
    "TBCrcPass",false, "ScheduledBitsContribution",NaN, "DeliveredBitsContribution",NaN, ...
    "GoodputBitsContribution",NaN, "DurationContributionSec",NaN, "MeasurementWindowContributionSec",NaN, ...
    "ScheduleTime_s",NaN, "AttemptStartTime_s",NaN, "AttemptEndTime_s",NaN, ...
    "FirstSuccessTime_s",NaN, "DeliveryLatency_ms",NaN, ...
    "FirstSuccessDelivery",false, "DuplicateDelivery",false, "Included",false, ...
    "ExcludedReason","", "Status","not_evaluated");
end

function T = localEmptyHARQTraceTable()
T = struct2table(repmat(localHARQTraceRow(), 0, 1));
end

function row = localHARQTraceRow()
row = struct("RunId","", "Direction","", "UEId",NaN, "TransportBlockId","", ...
    "Codeword",NaN, "HARQProcessId",NaN, "AttemptIndex",NaN, "RV",NaN, "NDI",NaN, ...
    "NewDataFlag",false, "RetransmissionFlag",false, ...
    "ScheduleTime_s",NaN, "AttemptStartTime_s",NaN, "AttemptEndTime_s",NaN, ...
    "FirstSuccessTime_s",NaN, "DeliveryLatency_ms",NaN, ...
    "ScheduledBits",NaN, "TBCrcPass",false, "DeliveredThisAttempt",false, ...
    "FirstSuccessDelivery",false, "DuplicateDelivery",false, "CountedGoodputBits",NaN, ...
    "ScheduledResourceExposureSec",NaN, "MeasurementWindowSec",NaN, "DeliveryStatus","", ...
    "Status","", "FailureReason","");
end

function row = localReconRow()
row = struct("RunId","", "ScenarioName","", "KPIName","", "Direction","", "Layer","", ...
    "Units","", "FormulaId","", "FormulaVersion","", "NumeratorValue",NaN, ...
    "DenominatorValue",NaN, "Value",NaN, "AggregationDurationSec",NaN, ...
    "ScheduledResourceExposureSec",NaN, "MeasurementWindowSec",NaN, "WarmupDurationSec",NaN, ...
    "FirstSuccessDeliveryCount",NaN, "RetransmissionAttemptCount",NaN, ...
    "MeanDeliveryLatency_ms",NaN, "P95DeliveryLatency_ms",NaN, ...
    "DurationSource","", "SourceTablePaths","", "SourceRowCount",0, "EligibleRowCount",0, ...
    "ExcludedRowCount",0, "SourceRowsHash","", "SourceDirection","", "ProxyRowsExcluded",0, ...
    "SkippedRowsExcluded",0, "FailedRowsIncluded",true, "HARQDeduplicationApplied",false, ...
    "DuplicateDeliveryCount",0, "MissingRawData",true, "SchemaValid",false, ...
    "Applicable",true, "ApplicabilityReason","", ...
    "FormulaExecuted",false, "ExportedSummaryValue",NaN, "ReconstructionValue",NaN, ...
    "ReconstructionDelta",NaN, "ReconciliationTolerance",1e-9, "ReconciliationPass",false, ...
    "StrictOk",false, "Status","fail", "FailureReason","");
end

function row = localAliasRow()
row = struct("RunId","", "LegacyAliasName","", "KPIName","", "Direction","", "Layer","", ...
    "FormulaId","", "FormulaVersion","", "AliasValue",NaN, "CanonicalValue",NaN, ...
    "Equal",false, "Status","", "FailureReason","");
end

function y = localTernary(cond, a, b)
if cond
    y = a;
else
    y = b;
end
end
