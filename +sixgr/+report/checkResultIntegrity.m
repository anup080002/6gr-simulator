function [T, summary] = checkResultIntegrity(results, varargin)
%CHECKRESULTINTEGRITY Validate provenance, totals, and physical ranges.

p = inputParser;
p.addParameter("StrictMode", false, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
p.addParameter("ContextLabel", "results", @(x) ischar(x) || isstring(x));
p.parse(varargin{:});
strictMode = logical(p.Results.StrictMode);
contextLabel = string(p.Results.ContextLabel);

summaryTable = localGetTable(results, "SummaryTable");
packetIntegrityTable = localGetTable(results, "PacketIntegrityTable");
flowSummaryTable = localGetTable(results, "FlowSummaryTable");
bearerSummaryTable = localGetTable(results, "BearerSummaryTable");
packetTraceTable = localGetTable(results, "PacketTraceTable");
checkTable = localGetTable(results, "CheckTable");

[hasTruth, hasFallback, hasProxy, provenanceNotes] = localClassifyProvenance( ...
    summaryTable, packetIntegrityTable, flowSummaryTable, bearerSummaryTable, packetTraceTable, checkTable);

[summaryTotalsPass, summaryTotalsNotes] = localCheckSummaryTotals( ...
    summaryTable, packetIntegrityTable, flowSummaryTable, bearerSummaryTable, packetTraceTable);
[physicalPass, physicalNotes] = localCheckPhysicalValues( ...
    summaryTable, packetIntegrityTable, flowSummaryTable, bearerSummaryTable, packetTraceTable);

rows = repmat(struct("Check", "", "Pass", false, "Notes", ""), 4, 1);
rows(1) = struct( ...
    "Check", "mixed_truth_fallback_data", ...
    "Pass", ~(hasTruth && hasFallback), ...
    "Notes", provenanceNotes);
rows(2) = struct( ...
    "Check", "mixed_truth_proxy_data", ...
    "Pass", ~(hasTruth && hasProxy), ...
    "Notes", provenanceNotes);
rows(3) = struct( ...
    "Check", "inconsistent_summary_totals", ...
    "Pass", summaryTotalsPass, ...
    "Notes", summaryTotalsNotes);
rows(4) = struct( ...
    "Check", "impossible_physical_values", ...
    "Pass", physicalPass, ...
    "Notes", physicalNotes);

T = struct2table(rows);

summary = struct();
summary.Ok = all(logical(T.Pass));
summary.FailedChecks = string(T.Check(~logical(T.Pass)));

if strictMode && ~summary.Ok
    error("sixgr:report:ResultIntegrityFailed", ...
        "%s result integrity checks failed: %s", ...
        char(contextLabel), strjoin(cellstr(summary.FailedChecks), ", "));
end
end

function T = localGetTable(results, fieldName)
T = table();
if ~(isstruct(results) && isscalar(results) && isfield(results, fieldName))
    return;
end
v = results.(fieldName);
if istable(v)
    T = v;
end
end

function [hasTruth, hasFallback, hasProxy, notes] = localClassifyProvenance(varargin)
textCols = [ ...
    "ExecutionMode", "DataSemantics", "TraceSemantics", "ExecutionBackend", ...
    "PHYMode", "E2EAirModel", "E2EAirModelSource", "ArtifactMode", ...
    "SummaryArtifact", "PacketIntegrityArtifact", "PacketTraceArtifact", ...
    "SchedulerTraceArtifact", "HARQTraceArtifact", "Notes"];
tokens = strings(0,1);
for i = 1:nargin
    T = varargin{i};
    if ~(istable(T) && ~isempty(T))
        continue;
    end
    vars = string(T.Properties.VariableNames);
    keep = textCols(ismember(textCols, vars));
    for j = 1:numel(keep)
        vals = lower(strtrim(string(T.(char(keep(j))))));
        vals = vals(strlength(vals) > 0);
        tokens = [tokens; vals(:)]; %#ok<AGROW>
    end
end

hasTruth = any(contains(tokens, "truth") | contains(tokens, "full_stack_replay") | contains(tokens, "real_"));
hasFallback = any(contains(tokens, "fallback") | contains(tokens, "rescue") | contains(tokens, "debug"));
hasProxy = any(contains(tokens, "proxy") | contains(tokens, "synthetic") | contains(tokens, "logistic") ...
    | contains(tokens, "lut") | contains(tokens, "abstraction"));

labels = strings(0,1);
if hasTruth
    labels(end+1,1) = "truth"; %#ok<AGROW>
end
if hasFallback
    labels(end+1,1) = "fallback"; %#ok<AGROW>
end
if hasProxy
    labels(end+1,1) = "proxy"; %#ok<AGROW>
end
if isempty(labels)
    notes = "no_provenance_markers";
else
    notes = "provenance_markers=" + strjoin(labels, ",");
end
end

function [pass, notes] = localCheckSummaryTotals(summaryTable, packetIntegrityTable, flowSummaryTable, bearerSummaryTable, packetTraceTable)
tol = 1e-6;
issues = strings(0,1);

if ~(istable(summaryTable) && height(summaryTable) == 1)
    issues(end+1,1) = "summary_row_missing"; %#ok<AGROW>
else
    S = summaryTable(1,:);
    issues = [issues; localCompareSummaryPacketRows(S, packetIntegrityTable, tol)]; %#ok<AGROW>
    issues = [issues; localCompareSummaryFlowTotals(S, flowSummaryTable, tol)]; %#ok<AGROW>
    issues = [issues; localCompareBearerFlowTotals(flowSummaryTable, bearerSummaryTable, tol)]; %#ok<AGROW>
    issues = [issues; localCompareTracePacketIntegrity(packetTraceTable, packetIntegrityTable, tol)]; %#ok<AGROW>
end

issues = unique(issues(strlength(issues) > 0), "stable");
pass = isempty(issues);
if pass
    notes = "summary_totals_consistent";
else
    notes = strjoin(issues, ";");
end
end

function issues = localCompareSummaryPacketRows(S, packetIntegrityTable, tol)
issues = strings(0,1);
if ~(istable(packetIntegrityTable) && ~isempty(packetIntegrityTable))
    issues(end+1,1) = "packet_integrity_missing"; %#ok<AGROW>
    return;
end

issues = [issues; localCompareSummaryPacketField(S, packetIntegrityTable, "DeliveryRatio", "ALL", "PacketDeliveryRatio", tol)]; %#ok<AGROW>
issues = [issues; localCompareSummaryPacketField(S, packetIntegrityTable, "DeliveryRatioDL", "DL", "PacketDeliveryRatio", tol)]; %#ok<AGROW>
issues = [issues; localCompareSummaryPacketField(S, packetIntegrityTable, "DeliveryRatioUL", "UL", "PacketDeliveryRatio", tol)]; %#ok<AGROW>
issues = [issues; localCompareSummaryPacketField(S, packetIntegrityTable, "SemanticCheckPassRate_pct", "ALL", "SemanticPass", tol, true)]; %#ok<AGROW>
issues = [issues; localCompareSummaryPacketField(S, packetIntegrityTable, "PacketAccountingPassRate_pct", "ALL", "AccountingIntegrityPass", tol, true)]; %#ok<AGROW>
end

function issues = localCompareSummaryFlowTotals(S, flowSummaryTable, tol)
issues = strings(0,1);
if ~(istable(flowSummaryTable) && ~isempty(flowSummaryTable))
    return;
end
simDur = localScalarFromRow(S, "SimulatedDuration_s", NaN);
if ~(isfinite(simDur) && simDur > 0)
    issues(end+1,1) = "simulated_duration_invalid"; %#ok<AGROW>
    return;
end

[goodputAll, goodputDL, goodputUL] = localGoodputFromFlow(flowSummaryTable, simDur);
issues = [issues; localCompareScalar(localScalarFromRow(S, "Goodput_Mbps", NaN), goodputAll, tol, "goodput_all_mismatch")]; %#ok<AGROW>
issues = [issues; localCompareScalar(localScalarFromRow(S, "GoodputDL_Mbps", NaN), goodputDL, tol, "goodput_dl_mismatch")]; %#ok<AGROW>
issues = [issues; localCompareScalar(localScalarFromRow(S, "GoodputUL_Mbps", NaN), goodputUL, tol, "goodput_ul_mismatch")]; %#ok<AGROW>
end

function issues = localCompareBearerFlowTotals(flowSummaryTable, bearerSummaryTable, tol)
issues = strings(0,1);
if ~(istable(flowSummaryTable) && ~isempty(flowSummaryTable) && istable(bearerSummaryTable) && ~isempty(bearerSummaryTable))
    return;
end

for dir = ["DL", "UL"]
    flowRows = flowSummaryTable(upper(string(flowSummaryTable.Direction)) == dir, :);
    bearerRows = bearerSummaryTable(upper(string(bearerSummaryTable.Direction)) == dir, :);
    issues = [issues; localCompareScalar(sum(double(flowRows.GeneratedPackets)), sum(double(bearerRows.GeneratedPackets)), tol, ...
        lower(dir) + "_generated_packets_flow_bearer_mismatch")]; %#ok<AGROW>
    issues = [issues; localCompareScalar(sum(double(flowRows.DeliveredPackets)), sum(double(bearerRows.DeliveredPackets)), tol, ...
        lower(dir) + "_delivered_packets_flow_bearer_mismatch")]; %#ok<AGROW>
    issues = [issues; localCompareScalar(sum(double(flowRows.DroppedPackets)), sum(double(bearerRows.DroppedPackets)), tol, ...
        lower(dir) + "_dropped_packets_flow_bearer_mismatch")]; %#ok<AGROW>
    issues = [issues; localCompareScalar(sum(double(flowRows.GeneratedBytes)), sum(double(bearerRows.GeneratedBytes)), tol, ...
        lower(dir) + "_generated_bytes_flow_bearer_mismatch")]; %#ok<AGROW>
    issues = [issues; localCompareScalar(sum(double(flowRows.DeliveredBytes)), sum(double(bearerRows.DeliveredBytes)), tol, ...
        lower(dir) + "_delivered_bytes_flow_bearer_mismatch")]; %#ok<AGROW>
    issues = [issues; localCompareScalar(sum(double(flowRows.DroppedBytes)), sum(double(bearerRows.DroppedBytes)), tol, ...
        lower(dir) + "_dropped_bytes_flow_bearer_mismatch")]; %#ok<AGROW>
end
end

function issues = localCompareTracePacketIntegrity(packetTraceTable, packetIntegrityTable, tol)
issues = strings(0,1);
if ~(istable(packetTraceTable) && ~isempty(packetTraceTable) && istable(packetIntegrityTable) && ~isempty(packetIntegrityTable))
    return;
end

dirs = ["DL", "UL", "ALL"];
for i = 1:numel(dirs)
    dirTag = dirs(i);
    row = localDirectionRow(packetIntegrityTable, dirTag);
    if isempty(row)
        issues(end+1,1) = lower(dirTag) + "_packet_integrity_row_missing"; %#ok<AGROW>
        continue;
    end
    stats = localPacketTraceStats(packetTraceTable, dirTag);
    issues = [issues; localCompareScalar(double(row.GeneratedPackets), stats.generated, tol, lower(dirTag) + "_generated_packets_trace_mismatch")]; %#ok<AGROW>
    issues = [issues; localCompareScalar(double(row.DeliveredPackets), stats.delivered, tol, lower(dirTag) + "_delivered_packets_trace_mismatch")]; %#ok<AGROW>
    issues = [issues; localCompareScalar(double(row.UndeliveredPackets), stats.undelivered, tol, lower(dirTag) + "_undelivered_packets_trace_mismatch")]; %#ok<AGROW>
end
end

function [pass, notes] = localCheckPhysicalValues(summaryTable, packetIntegrityTable, flowSummaryTable, bearerSummaryTable, packetTraceTable)
issues = strings(0,1);

if istable(summaryTable) && height(summaryTable) == 1
    S = summaryTable(1,:);
    issues = [issues; localCheckUnitInterval(localScalarFromRow(S, "DeliveryRatio", NaN), "summary_delivery_ratio")]; %#ok<AGROW>
    issues = [issues; localCheckUnitInterval(localScalarFromRow(S, "DeliveryRatioDL", NaN), "summary_delivery_ratio_dl")]; %#ok<AGROW>
    issues = [issues; localCheckUnitInterval(localScalarFromRow(S, "DeliveryRatioUL", NaN), "summary_delivery_ratio_ul")]; %#ok<AGROW>
    issues = [issues; localCheckUnitInterval(localScalarFromRow(S, "ACKRate", NaN), "summary_ack_rate")]; %#ok<AGROW>
    issues = [issues; localCheckUnitInterval(localScalarFromRow(S, "ACKRateDL", NaN), "summary_ack_rate_dl")]; %#ok<AGROW>
    issues = [issues; localCheckUnitInterval(localScalarFromRow(S, "ACKRateUL", NaN), "summary_ack_rate_ul")]; %#ok<AGROW>
    issues = [issues; localCheckUnitInterval(localScalarFromRow(S, "NACKRate", NaN), "summary_nack_rate")]; %#ok<AGROW>
    issues = [issues; localCheckUnitInterval(localScalarFromRow(S, "NACKRateDL", NaN), "summary_nack_rate_dl")]; %#ok<AGROW>
    issues = [issues; localCheckUnitInterval(localScalarFromRow(S, "NACKRateUL", NaN), "summary_nack_rate_ul")]; %#ok<AGROW>
    issues = [issues; localCheckUnitInterval(localScalarFromRow(S, "HARQ_RetxProbability", NaN), "summary_retx_rate")]; %#ok<AGROW>
    issues = [issues; localCheckUnitInterval(localScalarFromRow(S, "HARQ_RetxProbabilityDL", NaN), "summary_retx_rate_dl")]; %#ok<AGROW>
    issues = [issues; localCheckUnitInterval(localScalarFromRow(S, "HARQ_RetxProbabilityUL", NaN), "summary_retx_rate_ul")]; %#ok<AGROW>
    issues = [issues; localCheckUnitInterval(localScalarFromRow(S, "JainFairness", NaN), "summary_jain_fairness")]; %#ok<AGROW>
    issues = [issues; localCheckPercent(localScalarFromRow(S, "SemanticCheckPassRate_pct", NaN), "summary_semantic_pass_rate")]; %#ok<AGROW>
    issues = [issues; localCheckPercent(localScalarFromRow(S, "PacketAccountingPassRate_pct", NaN), "summary_packet_accounting_pass_rate")]; %#ok<AGROW>
    issues = [issues; localCheckPercent(localScalarFromRow(S, "ComponentCheckPassRate_pct", NaN), "summary_component_pass_rate")]; %#ok<AGROW>
    issues = [issues; localCheckPercent(localScalarFromRow(S, "ResultIntegrityPassRate_pct", NaN), "summary_result_integrity_pass_rate")]; %#ok<AGROW>
    issues = [issues; localCheckUnitInterval(localScalarFromRow(S, "DeliveryRatioTarget", NaN), "summary_delivery_ratio_target_out_of_range")]; %#ok<AGROW>
    issues = [issues; localCheckNonNegativeOrNaN(localScalarFromRow(S, "ObservedP95Latency_ms", NaN), "summary_observed_p95_latency_negative")]; %#ok<AGROW>
    issues = [issues; localCheckNonNegativeOrNaN(localScalarFromRow(S, "LatencyBudgetTarget_ms", NaN), "summary_latency_budget_target_negative")]; %#ok<AGROW>
    issues = [issues; localCheckNonNegativeOrNaN(localScalarFromRow(S, "ThroughputTargetFractionOfOffered", NaN), "summary_throughput_target_fraction_negative")]; %#ok<AGROW>
    issues = [issues; localCheckNonNegativeOrNaN(localScalarFromRow(S, "ThroughputTarget_Mbps", NaN), "summary_throughput_target_negative")]; %#ok<AGROW>
    issues = [issues; localCheckNonNegative(localScalarFromRow(S, "Offered_Mbps", NaN), "summary_offered_mbps")]; %#ok<AGROW>
    issues = [issues; localCheckNonNegative(localScalarFromRow(S, "OfferedDL_Mbps", NaN), "summary_offered_dl_mbps")]; %#ok<AGROW>
    issues = [issues; localCheckNonNegative(localScalarFromRow(S, "OfferedUL_Mbps", NaN), "summary_offered_ul_mbps")]; %#ok<AGROW>
    issues = [issues; localCheckNonNegative(localScalarFromRow(S, "Goodput_Mbps", NaN), "summary_goodput_mbps")]; %#ok<AGROW>
    issues = [issues; localCheckNonNegative(localScalarFromRow(S, "GoodputDL_Mbps", NaN), "summary_goodput_dl_mbps")]; %#ok<AGROW>
    issues = [issues; localCheckNonNegative(localScalarFromRow(S, "GoodputUL_Mbps", NaN), "summary_goodput_ul_mbps")]; %#ok<AGROW>
    issues = [issues; localCheckOfferedVsGoodput(S, "Goodput_Mbps", "Offered_Mbps", "summary_goodput_exceeds_offered")]; %#ok<AGROW>
    issues = [issues; localCheckOfferedVsGoodput(S, "GoodputDL_Mbps", "OfferedDL_Mbps", "summary_goodput_dl_exceeds_offered")]; %#ok<AGROW>
    issues = [issues; localCheckOfferedVsGoodput(S, "GoodputUL_Mbps", "OfferedUL_Mbps", "summary_goodput_ul_exceeds_offered")]; %#ok<AGROW>
    issues = [issues; localCheckRateSum(S, "ACKRate", "NACKRate", "summary_ack_plus_nack_exceeds_one")]; %#ok<AGROW>
    issues = [issues; localCheckRateSum(S, "ACKRateDL", "NACKRateDL", "summary_ack_plus_nack_dl_exceeds_one")]; %#ok<AGROW>
    issues = [issues; localCheckRateSum(S, "ACKRateUL", "NACKRateUL", "summary_ack_plus_nack_ul_exceeds_one")]; %#ok<AGROW>
end

issues = [issues; localCheckPacketIntegrityValues(packetIntegrityTable)]; %#ok<AGROW>
issues = [issues; localCheckFlowValues(flowSummaryTable)]; %#ok<AGROW>
issues = [issues; localCheckBearerValues(bearerSummaryTable)]; %#ok<AGROW>
issues = [issues; localCheckTraceValues(packetTraceTable)]; %#ok<AGROW>

issues = unique(issues(strlength(issues) > 0), "stable");
pass = isempty(issues);
if pass
    notes = "physical_values_valid";
else
    notes = strjoin(issues, ";");
end
end

function issues = localCheckPacketIntegrityValues(T)
issues = strings(0,1);
if ~(istable(T) && ~isempty(T))
    return;
end
for i = 1:height(T)
    issues = [issues; localCheckNonNegative(double(T.GeneratedPackets(i)), "packet_integrity_generated_negative")]; %#ok<AGROW>
    issues = [issues; localCheckNonNegative(double(T.DeliveredPackets(i)), "packet_integrity_delivered_negative")]; %#ok<AGROW>
    issues = [issues; localCheckNonNegative(double(T.UndeliveredPackets(i)), "packet_integrity_undelivered_negative")]; %#ok<AGROW>
    issues = [issues; localCheckNonNegative(double(T.DeadlineMissPackets(i)), "packet_integrity_deadline_miss_negative")]; %#ok<AGROW>
    issues = [issues; localCheckNonNegative(double(T.DuplicatePackets(i)), "packet_integrity_duplicate_negative")]; %#ok<AGROW>
    issues = [issues; localCheckNonNegative(double(T.OutOfOrderPackets(i)), "packet_integrity_reorder_negative")]; %#ok<AGROW>
    issues = [issues; localCheckUnitInterval(double(T.PacketDeliveryRatio(i)), "packet_integrity_pdr_out_of_range")]; %#ok<AGROW>
    issues = [issues; localCheckUnitInterval(double(T.DeadlineMissRate(i)), "packet_integrity_deadline_miss_rate_out_of_range")]; %#ok<AGROW>
    issues = [issues; localCheckBooleanColumn(T, i, "DuplicateInflationFreePass", "packet_integrity_duplicate_inflation_pass_invalid")]; %#ok<AGROW>
    issues = [issues; localCheckBooleanColumn(T, i, "OrderingIntegrityPass", "packet_integrity_ordering_pass_invalid")]; %#ok<AGROW>
    issues = [issues; localCheckBooleanColumn(T, i, "DeadlineAccountingPass", "packet_integrity_deadline_accounting_pass_invalid")]; %#ok<AGROW>
    issues = [issues; localCheckBooleanColumn(T, i, "AccountingIntegrityPass", "packet_integrity_accounting_pass_invalid")]; %#ok<AGROW>
    issues = [issues; localCheckBooleanColumn(T, i, "SemanticPass", "packet_integrity_semantic_pass_invalid")]; %#ok<AGROW>
    issues = [issues; localCheckNonNegativeOrNaN(double(T.MeanLatency_ms(i)), "packet_integrity_mean_latency_negative")]; %#ok<AGROW>
    issues = [issues; localCheckNonNegativeOrNaN(double(T.P95Latency_ms(i)), "packet_integrity_p95_latency_negative")]; %#ok<AGROW>
    if double(T.DeliveredPackets(i)) > double(T.GeneratedPackets(i)) + 1e-9
        issues(end+1,1) = "packet_integrity_delivered_exceeds_generated"; %#ok<AGROW>
    end
    if double(T.UndeliveredPackets(i)) > double(T.GeneratedPackets(i)) + 1e-9
        issues(end+1,1) = "packet_integrity_undelivered_exceeds_generated"; %#ok<AGROW>
    end
end
end

function issues = localCheckFlowValues(T)
issues = strings(0,1);
if ~(istable(T) && ~isempty(T))
    return;
end
for i = 1:height(T)
    issues = [issues; localCheckNonNegative(double(T.GeneratedPackets(i)), "flow_generated_packets_negative")]; %#ok<AGROW>
    issues = [issues; localCheckNonNegative(double(T.DeliveredPackets(i)), "flow_delivered_packets_negative")]; %#ok<AGROW>
    issues = [issues; localCheckNonNegative(double(T.DroppedPackets(i)), "flow_dropped_packets_negative")]; %#ok<AGROW>
    issues = [issues; localCheckNonNegative(double(T.GeneratedBytes(i)), "flow_generated_bytes_negative")]; %#ok<AGROW>
    issues = [issues; localCheckNonNegative(double(T.DeliveredBytes(i)), "flow_delivered_bytes_negative")]; %#ok<AGROW>
    issues = [issues; localCheckNonNegative(double(T.DroppedBytes(i)), "flow_dropped_bytes_negative")]; %#ok<AGROW>
    issues = [issues; localCheckUnitInterval(double(T.PacketDeliveryRatio(i)), "flow_pdr_out_of_range")]; %#ok<AGROW>
    issues = [issues; localCheckNonNegativeOrNaN(double(T.MeanLatency_ms(i)), "flow_mean_latency_negative")]; %#ok<AGROW>
    issues = [issues; localCheckNonNegativeOrNaN(double(T.P95Latency_ms(i)), "flow_p95_latency_negative")]; %#ok<AGROW>
    issues = [issues; localCheckNonNegativeOrNaN(double(T.Goodput_Mbps(i)), "flow_goodput_negative")]; %#ok<AGROW>
    if double(T.DeliveredPackets(i)) > double(T.GeneratedPackets(i)) + 1e-9
        issues(end+1,1) = "flow_delivered_exceeds_generated"; %#ok<AGROW>
    end
    if double(T.DroppedPackets(i)) > double(T.GeneratedPackets(i)) + 1e-9
        issues(end+1,1) = "flow_dropped_exceeds_generated"; %#ok<AGROW>
    end
end
end

function issues = localCheckBearerValues(T)
issues = strings(0,1);
if ~(istable(T) && ~isempty(T))
    return;
end
for i = 1:height(T)
    issues = [issues; localCheckNonNegative(double(T.GeneratedPackets(i)), "bearer_generated_packets_negative")]; %#ok<AGROW>
    issues = [issues; localCheckNonNegative(double(T.DeliveredPackets(i)), "bearer_delivered_packets_negative")]; %#ok<AGROW>
    issues = [issues; localCheckNonNegative(double(T.DroppedPackets(i)), "bearer_dropped_packets_negative")]; %#ok<AGROW>
    issues = [issues; localCheckNonNegative(double(T.GeneratedBytes(i)), "bearer_generated_bytes_negative")]; %#ok<AGROW>
    issues = [issues; localCheckNonNegative(double(T.DeliveredBytes(i)), "bearer_delivered_bytes_negative")]; %#ok<AGROW>
    issues = [issues; localCheckNonNegative(double(T.DroppedBytes(i)), "bearer_dropped_bytes_negative")]; %#ok<AGROW>
    issues = [issues; localCheckUnitInterval(double(T.PacketDeliveryRatio(i)), "bearer_pdr_out_of_range")]; %#ok<AGROW>
    if double(T.DeliveredPackets(i)) > double(T.GeneratedPackets(i)) + 1e-9
        issues(end+1,1) = "bearer_delivered_exceeds_generated"; %#ok<AGROW>
    end
    if double(T.DroppedPackets(i)) > double(T.GeneratedPackets(i)) + 1e-9
        issues(end+1,1) = "bearer_dropped_exceeds_generated"; %#ok<AGROW>
    end
end
end

function issues = localCheckTraceValues(T)
issues = strings(0,1);
if ~(istable(T) && ~isempty(T))
    return;
end
if ismember("Latency_ms", string(T.Properties.VariableNames))
    vals = double(T.Latency_ms);
    if any(isfinite(vals) & vals < -1e-9)
        issues(end+1,1) = "packet_trace_negative_latency"; %#ok<AGROW>
    end
end
if ismember("PacketBytes", string(T.Properties.VariableNames))
    vals = double(T.PacketBytes);
    if any(isfinite(vals) & vals < -1e-9)
        issues(end+1,1) = "packet_trace_negative_bytes"; %#ok<AGROW>
    end
end
end

function issues = localCompareSummaryPacketField(S, packetIntegrityTable, summaryField, dirTag, packetField, tol, varargin)
issues = strings(0,1);
if ~ismember(summaryField, string(S.Properties.VariableNames))
    return;
end
row = localDirectionRow(packetIntegrityTable, dirTag);
if isempty(row)
    issues(end+1,1) = lower(dirTag) + "_packet_integrity_row_missing"; %#ok<AGROW>
    return;
end

expected = NaN;
if nargin >= 7 && ~isempty(varargin) && logical(varargin{1})
    if ismember(packetField, string(packetIntegrityTable.Properties.VariableNames))
        expected = 100 * mean(double(packetIntegrityTable.(char(packetField))));
    else
        expected = NaN;
    end
else
    expected = double(row.(packetField));
end
actual = double(S.(summaryField));
issues = [issues; localCompareScalar(actual, expected, tol, lower(summaryField) + "_mismatch")]; %#ok<AGROW>
end

function [goodputAll, goodputDL, goodputUL] = localGoodputFromFlow(flowSummaryTable, simDur)
goodputAll = 8 * sum(double(flowSummaryTable.DeliveredBytes)) / max(simDur, eps) / 1e6;
dlRows = flowSummaryTable(upper(string(flowSummaryTable.Direction)) == "DL", :);
ulRows = flowSummaryTable(upper(string(flowSummaryTable.Direction)) == "UL", :);
goodputDL = 8 * sum(double(dlRows.DeliveredBytes)) / max(simDur, eps) / 1e6;
goodputUL = 8 * sum(double(ulRows.DeliveredBytes)) / max(simDur, eps) / 1e6;
end

function row = localDirectionRow(T, dirTag)
row = table();
if ~(istable(T) && ~isempty(T) && ismember("Direction", string(T.Properties.VariableNames)))
    return;
end
idx = find(upper(string(T.Direction)) == upper(string(dirTag)), 1, "first");
if ~isempty(idx)
    row = T(idx,:);
end
end

function stats = localPacketTraceStats(T, dirTag)
stats = struct("generated", 0, "delivered", 0, "undelivered", 0);
if ~(istable(T) && ~isempty(T))
    return;
end
mask = true(height(T), 1);
if ismember("Direction", string(T.Properties.VariableNames)) && dirTag ~= "ALL"
    mask = upper(string(T.Direction)) == dirTag;
end
dropCause = strings(height(T), 1);
if ismember("DropCause", string(T.Properties.VariableNames))
    dropCause = string(T.DropCause);
end
deliveredMask = mask & (strlength(dropCause) == 0);
stats.generated = sum(mask);
stats.delivered = sum(deliveredMask);
stats.undelivered = sum(mask & ~deliveredMask);
end

function issues = localCompareScalar(actual, expected, tol, issueId)
issues = strings(0,1);
if ~(isfinite(actual) && isfinite(expected))
    return;
end
scale = max([1, abs(actual), abs(expected)]);
if abs(actual - expected) > tol * scale
    issues(end+1,1) = string(issueId); %#ok<AGROW>
end
end

function issues = localCheckUnitInterval(x, issueId)
issues = strings(0,1);
if ~isfinite(x)
    return;
end
if x < -1e-9 || x > 1 + 1e-9
    issues(end+1,1) = string(issueId); %#ok<AGROW>
end
end

function issues = localCheckPercent(x, issueId)
issues = strings(0,1);
if ~isfinite(x)
    return;
end
if x < -1e-9 || x > 100 + 1e-9
    issues(end+1,1) = string(issueId); %#ok<AGROW>
end
end

function issues = localCheckNonNegative(x, issueId)
issues = strings(0,1);
if ~isfinite(x)
    return;
end
if x < -1e-9
    issues(end+1,1) = string(issueId); %#ok<AGROW>
end
end

function issues = localCheckNonNegativeOrNaN(x, issueId)
issues = strings(0,1);
if isnan(x)
    return;
end
issues = localCheckNonNegative(x, issueId);
end

function issues = localCheckBooleanColumn(T, rowIdx, fieldName, issueId)
issues = strings(0,1);
if ~(ismember(fieldName, string(T.Properties.VariableNames)) && rowIdx >= 1 && rowIdx <= height(T))
    return;
end
v = T.(char(fieldName))(rowIdx);
if ~(islogical(v) || (isnumeric(v) && isfinite(double(v)) && any(abs(double(v) - [0 1]) <= 1e-9)))
    issues(end+1,1) = string(issueId); %#ok<AGROW>
end
end

function issues = localCheckOfferedVsGoodput(S, goodputField, offeredField, issueId)
issues = strings(0,1);
if ~(ismember(goodputField, string(S.Properties.VariableNames)) && ismember(offeredField, string(S.Properties.VariableNames)))
    return;
end
goodput = double(S.(goodputField));
offered = double(S.(offeredField));
if isfinite(goodput) && isfinite(offered) && goodput > offered + 1e-6
    issues(end+1,1) = string(issueId); %#ok<AGROW>
end
end

function issues = localCheckRateSum(S, ackField, nackField, issueId)
issues = strings(0,1);
if ~(ismember(ackField, string(S.Properties.VariableNames)) && ismember(nackField, string(S.Properties.VariableNames)))
    return;
end
ack = double(S.(ackField));
nack = double(S.(nackField));
if isfinite(ack) && isfinite(nack) && (ack + nack) > 1 + 1e-6
    issues(end+1,1) = string(issueId); %#ok<AGROW>
end
end

function x = localScalarFromRow(S, fieldName, fallback)
x = fallback;
if ~(istable(S) && height(S) == 1 && ismember(fieldName, string(S.Properties.VariableNames)))
    return;
end
try
    x = double(S.(fieldName));
catch
    x = fallback;
end
end
