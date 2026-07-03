function audit = auditLLSArtifacts(outputRoot, varargin)
%AUDITLLSARTIFACTS Fail-closed invariant audit over generated LLS artifacts.
%
%   audit = sixgr.validation.auditLLSArtifacts(outputRoot)
%   reads primary CSV artifacts from an existing run folder and writes:
%     reports/csv/strict_invariant_audit.csv
%     reports/json/strict_invariant_audit.json
%
%   This audit is intentionally artifact-only. It does not repair missing
%   evidence, synthesize fallback rows, or reinterpret proxy outputs.

p = inputParser;
p.addParameter("Strict", true, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
p.addParameter("WriteOutputs", true, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
p.addParameter("FailOnNegativeLatency", true, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
p.addParameter("FailOnImpossibleCodeRate", true, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
p.addParameter("FailOnEmptyDerivedCurveWhenRawExists", true, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
p.addParameter("FailOnConfiguredEffectiveMismatchInFixedMode", true, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
p.parse(varargin{:});
opt = p.Results;

outputRoot = char(string(outputRoot));
if exist(outputRoot, "dir") ~= 7
    error("sixgr:validation:auditLLSArtifacts:OutputRootMissing", ...
        "Output root does not exist: %s", outputRoot);
end

layout = sixgr.report.resultLayout(outputRoot);
artifacts = localReadArtifacts(outputRoot);
rows = repmat(localEmptyRow(), 0, 1);

packetFiles = [
    "reports/csv/live_application_packet_ledger.csv"
    "reports/csv/dl_application_packet_ledger.csv"
    "reports/csv/ul_application_packet_ledger.csv"
    ];
for rel = packetFiles.'
    T = artifacts.(localKey(rel)).Table;
    present = artifacts.(localKey(rel)).Present;
    rows = [rows; localPacketLatencyRows(rel, T, present, logical(opt.FailOnNegativeLatency))]; %#ok<AGROW>
end

rows = [rows; localCodeRateRows("air_interface/csv/dl_pdsch_trials.csv", ...
    artifacts.dl_pdsch_trials.Table, artifacts.dl_pdsch_trials.Present, logical(opt.FailOnImpossibleCodeRate))]; %#ok<AGROW>
rows = [rows; localCodeRateRows("air_interface/csv/ul_pusch_trials.csv", ...
    artifacts.ul_pusch_trials.Table, artifacts.ul_pusch_trials.Present, logical(opt.FailOnImpossibleCodeRate))]; %#ok<AGROW>
rows = [rows; localULCurveMaterializationRow(artifacts, logical(opt.FailOnEmptyDerivedCurveWhenRawExists))]; %#ok<AGROW>
rows = [rows; localThroughputReconciliationRow(artifacts.throughput_reconciliation.Table, ...
    artifacts.throughput_reconciliation.Present)]; %#ok<AGROW>
rows = [rows; localPDSCHObjectiveRow(artifacts.dl_pdsch_raw_bler_ber_objective.Table, ...
    artifacts.dl_pdsch_raw_bler_ber_objective.Present)]; %#ok<AGROW>
rows = [rows; localConfiguredEffectiveRow(artifacts.configured_effective_operating_point.Table, ...
    artifacts.configured_effective_operating_point.Present, logical(opt.FailOnConfiguredEffectiveMismatchInFixedMode))]; %#ok<AGROW>

T = localRowsToTable(rows);
failMask = string(T.Status) == "FAIL";
warnMask = string(T.Status) == "WARN";

audit = struct();
audit.OutputRoot = string(outputRoot);
audit.Ok = ~any(failMask);
audit.Status = string(localTernary(audit.Ok, "pass", "fail"));
audit.Strict = logical(opt.Strict);
audit.RowCount = height(T);
audit.FailureCount = double(nnz(failMask));
audit.WarningCount = double(nnz(warnMask));
audit.FailureCodes = unique(string(T.FailureCode(failMask)), "stable");
audit.Table = T;
audit.Artifacts = localArtifactInventory(artifacts);
audit.Options = opt;

if logical(opt.WriteOutputs)
    sixgr.analytics.writeAnalysisTable(fullfile(layout.ReportCSVDir, "strict_invariant_audit.csv"), T);
    jsonAudit = audit;
    sixgr.util.jsonWrite(fullfile(layout.ReportDir, "json", "strict_invariant_audit.json"), jsonAudit);
end

if logical(opt.Strict) && ~audit.Ok
    error("sixgr:validation:auditLLSArtifacts:StrictInvariantFailure", ...
        "Strict LLS invariant audit failed with %d failure row(s): %s", ...
        audit.FailureCount, strjoin(audit.FailureCodes, ", "));
end
end

function artifacts = localReadArtifacts(outputRoot)
files = [
    "reports/csv/live_application_packet_ledger.csv"
    "reports/csv/dl_application_packet_ledger.csv"
    "reports/csv/ul_application_packet_ledger.csv"
    "air_interface/csv/dl_pdsch_trials.csv"
    "air_interface/csv/ul_pusch_trials.csv"
    "air_interface/csv/dl_measured_sinr_bler_curve.csv"
    "air_interface/csv/ul_measured_sinr_bler_curve.csv"
    "reports/csv/configured_effective_operating_point.csv"
    "reports/csv/dl_pdsch_raw_bler_ber_objective.csv"
    "reports/csv/throughput_reconciliation.csv"
    "reports/csv/scenario_objective_gates.csv"
    ];
artifacts = struct();
for rel = files.'
    key = localKey(rel);
    path = fullfile(outputRoot, strrep(char(rel), "/", filesep));
    [T, present, readable, reason] = localReadOptionalTable(path);
    artifacts.(key) = struct("RelativePath", rel, "Path", string(path), ...
        "Present", present, "Readable", readable, "ReadFailureReason", reason, "Table", T);
end
artifacts.live_application_packet_ledger = artifacts.(localKey("reports/csv/live_application_packet_ledger.csv"));
artifacts.dl_application_packet_ledger = artifacts.(localKey("reports/csv/dl_application_packet_ledger.csv"));
artifacts.ul_application_packet_ledger = artifacts.(localKey("reports/csv/ul_application_packet_ledger.csv"));
artifacts.dl_pdsch_trials = artifacts.(localKey("air_interface/csv/dl_pdsch_trials.csv"));
artifacts.ul_pusch_trials = artifacts.(localKey("air_interface/csv/ul_pusch_trials.csv"));
artifacts.dl_measured_sinr_bler_curve = artifacts.(localKey("air_interface/csv/dl_measured_sinr_bler_curve.csv"));
artifacts.ul_measured_sinr_bler_curve = artifacts.(localKey("air_interface/csv/ul_measured_sinr_bler_curve.csv"));
artifacts.configured_effective_operating_point = artifacts.(localKey("reports/csv/configured_effective_operating_point.csv"));
artifacts.dl_pdsch_raw_bler_ber_objective = artifacts.(localKey("reports/csv/dl_pdsch_raw_bler_ber_objective.csv"));
artifacts.throughput_reconciliation = artifacts.(localKey("reports/csv/throughput_reconciliation.csv"));
artifacts.scenario_objective_gates = artifacts.(localKey("reports/csv/scenario_objective_gates.csv"));
end

function rows = localPacketLatencyRows(rel, T, present, failEnabled)
rows = repmat(localEmptyRow(), 0, 1);
if ~present
    rows(end+1, 1) = localRow("packet_delivery_time_monotonic", rel, 0, 0, NaN, ">=0", ...
        "SKIP", "", "packet ledger artifact not present");
    rows(end+1, 1) = localRow("packet_latency_nonnegative", rel, 0, 0, NaN, ">=0", ...
        "SKIP", "", "packet ledger artifact not present");
    rows(end+1, 1) = localRow("packet_slot_monotonic", rel, 0, 0, NaN, ">=0", ...
        "SKIP", "", "packet ledger artifact not present");
    return;
end
if ~istable(T) || height(T) == 0
    rows(end+1, 1) = localRow("packet_delivery_time_monotonic", rel, 0, 0, NaN, ">=0", ...
        "SKIP", "", "packet ledger artifact empty");
    rows(end+1, 1) = localRow("packet_latency_nonnegative", rel, 0, 0, NaN, ">=0", ...
        "SKIP", "", "packet ledger artifact empty");
    rows(end+1, 1) = localRow("packet_slot_monotonic", rel, 0, 0, NaN, ">=0", ...
        "SKIP", "", "packet ledger artifact empty");
    return;
end
delivered = localDeliveredMask(T);

if localHasColumn(T, "DeliveryTime_s") && localHasColumn(T, "EnqueueTime_s")
    delivery = localNumericColumn(T, "DeliveryTime_s", NaN);
    enqueue = localNumericColumn(T, "EnqueueTime_s", NaN);
    mask = delivered & isfinite(delivery) & isfinite(enqueue);
    delta = delivery - enqueue;
    fail = mask & delta < -1e-12;
    rows(end+1, 1) = localInvariantRow("packet_delivery_time_monotonic", rel, nnz(mask), nnz(fail), ...
        localMinOrNaN(delta(mask)), ">=0", failEnabled, "negative_packet_latency_detected", ...
        "DeliveryTime_s must be greater than or equal to EnqueueTime_s for delivered packets");
else
    rows(end+1, 1) = localRow("packet_delivery_time_monotonic", rel, 0, 0, NaN, ">=0", ...
        "SKIP", "", "DeliveryTime_s or EnqueueTime_s column absent");
end

if localHasColumn(T, "Latency_ms")
    latency = localNumericColumn(T, "Latency_ms", NaN);
    mask = delivered & isfinite(latency);
    fail = mask & latency < -1e-9;
    rows(end+1, 1) = localInvariantRow("packet_latency_nonnegative", rel, nnz(mask), nnz(fail), ...
        localMinOrNaN(latency(mask)), ">=0", failEnabled, "negative_packet_latency_detected", ...
        "Latency_ms must be non-negative for delivered packets");
else
    rows(end+1, 1) = localRow("packet_latency_nonnegative", rel, 0, 0, NaN, ">=0", ...
        "SKIP", "", "Latency_ms column absent");
end

if localHasColumn(T, "DeliverySlot") && localHasColumn(T, "EnqueueSlot")
    deliverySlot = localNumericColumn(T, "DeliverySlot", NaN);
    enqueueSlot = localNumericColumn(T, "EnqueueSlot", NaN);
    mask = delivered & isfinite(deliverySlot) & isfinite(enqueueSlot);
    delta = deliverySlot - enqueueSlot;
    fail = mask & delta < 0;
    rows(end+1, 1) = localInvariantRow("packet_slot_monotonic", rel, nnz(mask), nnz(fail), ...
        localMinOrNaN(delta(mask)), ">=0", failEnabled, "delivery_slot_before_enqueue_slot", ...
        "DeliverySlot must be greater than or equal to EnqueueSlot for delivered packets");
else
    rows(end+1, 1) = localRow("packet_slot_monotonic", rel, 0, 0, NaN, ">=0", ...
        "SKIP", "", "DeliverySlot or EnqueueSlot column absent");
end
end

function row = localCodeRateRows(rel, T, present, failEnabled)
if ~present || ~istable(T) || height(T) == 0
    row = localRow("code_rate_physical_bounds", rel, 0, 0, NaN, "(0,1]", ...
        "SKIP", "", "trial artifact missing or empty");
    return;
end
rates = localCodeRates(T);
mask = isfinite(rates);
fail = mask & (rates <= 0 | rates > 1 + 1e-9);
row = localInvariantRow("code_rate_physical_bounds", rel, nnz(mask), nnz(fail), ...
    localMaxOrNaN(rates(mask)), "(0,1]", failEnabled, "impossible_code_rate_detected", ...
    "Explicit or derived code rate must stay within physical bounds");
end

function row = localULCurveMaterializationRow(artifacts, failEnabled)
raw = artifacts.ul_pusch_trials.Table;
curve = artifacts.ul_measured_sinr_bler_curve.Table;
rawPresent = artifacts.ul_pusch_trials.Present && istable(raw) && height(raw) > 0;
rawFiniteSINR = 0;
if rawPresent
    sinr = localFirstNumericColumn(raw, ["PostEqSINR_dB","MeasuredTrialSINR_dB","SINR_dB", ...
        "ReceiverHestSINR_dB","WidebandSINR_dB"], NaN);
    rawFiniteSINR = nnz(isfinite(sinr));
end
curveRows = 0;
if artifacts.ul_measured_sinr_bler_curve.Present && istable(curve)
    curveRows = height(curve);
end
failed = rawFiniteSINR > 0 && curveRows == 0;
row = localInvariantRow("ul_measured_sinr_curve_materialized", ...
    "air_interface/csv/ul_measured_sinr_bler_curve.csv", rawFiniteSINR, double(failed) * rawFiniteSINR, ...
    curveRows, ">=1 when finite UL SINR raw rows exist", failEnabled, ...
    "ul_raw_trials_present_but_curve_empty", ...
    "UL PUSCH raw rows contain finite SINR but the derived UL measured-SINR BLER curve is empty or missing");
end

function row = localThroughputReconciliationRow(T, present)
if ~present || ~istable(T) || height(T) == 0
    row = localRow("throughput_reconciliation_passed", "reports/csv/throughput_reconciliation.csv", ...
        0, 0, NaN, "all rows pass", "SKIP", "", "throughput reconciliation artifact missing or empty");
    return;
end
fail = localFailureMask(T, ["ThroughputReconciliationOk","ReconciliationPass","ResultOk","Pass","Ok"], ...
    ["Status"], ["FailureReason","Reason"]);
row = localInvariantRow("throughput_reconciliation_passed", "reports/csv/throughput_reconciliation.csv", ...
    height(T), nnz(fail), nnz(~fail), "all rows pass", true, ...
    "throughput_reconciliation_failed", "throughput_reconciliation.csv reported a failed KPI reconciliation");
end

function row = localPDSCHObjectiveRow(T, present)
if ~present || ~istable(T) || height(T) == 0
    row = localRow("dl_pdsch_bler_ber_objective_passed", "reports/csv/dl_pdsch_raw_bler_ber_objective.csv", ...
        0, 0, NaN, "all rows pass", "SKIP", "", "DL PDSCH BLER/BER objective artifact missing or empty");
    return;
end
fail = localFailureMask(T, ["ObjectivePass","ScenarioObjectiveOk","ResultOk","Pass","Ok"], ...
    ["Status","TruthStatus"], ["FailureReason","FailureCode"]);
row = localInvariantRow("dl_pdsch_bler_ber_objective_passed", "reports/csv/dl_pdsch_raw_bler_ber_objective.csv", ...
    height(T), nnz(fail), nnz(~fail), "all rows pass", true, ...
    "dl_pdsch_objective_failed", "dl_pdsch_raw_bler_ber_objective.csv reported a failed BLER/BER objective");
end

function row = localConfiguredEffectiveRow(T, present, failEnabled)
scope = "reports/csv/configured_effective_operating_point.csv";
if ~present || ~istable(T) || height(T) == 0
    row = localRow("fixed_anchor_configured_effective_match_rate", scope, ...
        0, 0, NaN, ">=0.99", "SKIP", "", "configured/effective operating point artifact missing or empty");
    return;
end
mode = lower(strtrim(string(localColumn(T, "ScenarioMode", repmat("", height(T), 1)))));
adaptive = localBoolColumn(T, "AdaptiveMode", false(height(T), 1));
fixedMode = any((contains(mode, "fixed") | contains(mode, "anchor")) & ~adaptive);
if ~fixedMode
    row = localRow("fixed_anchor_configured_effective_match_rate", scope, ...
        height(T), 0, NaN, ">=0.99", "SKIP", "", "artifact is not fixed-anchor mode");
    return;
end
eligible = localBoolColumn(T, "StrictEligible", true(height(T), 1)) & ~adaptive;
if ~localHasColumn(T, "ExactOperatingPointMatch")
    row = localRow("fixed_anchor_configured_effective_match_rate", scope, ...
        nnz(eligible), nnz(eligible), NaN, ">=0.99", localStatus(nnz(eligible) > 0, failEnabled), ...
        "configured_effective_operating_point_mismatch", "ExactOperatingPointMatch column absent");
    return;
end
match = localBoolColumn(T, "ExactOperatingPointMatch", false(height(T), 1));
denom = nnz(eligible);
if denom == 0
    row = localRow("fixed_anchor_configured_effective_match_rate", scope, ...
        0, 0, NaN, ">=0.99", "SKIP", "", "no fixed-anchor strict-eligible rows");
    return;
end
rate = nnz(eligible & match) / denom;
failed = rate + eps < 0.99;
row = localInvariantRow("fixed_anchor_configured_effective_match_rate", scope, denom, ...
    double(failed) * (denom - nnz(eligible & match)), rate, ">=0.99", failEnabled, ...
    "configured_effective_operating_point_mismatch", ...
    "fixed-anchor configured/effective exact match rate is below threshold");
end

function fail = localFailureMask(T, boolNames, statusNames, reasonNames)
n = height(T);
matched = false(n, 1);
fail = false(n, 1);
for name = string(boolNames)
    if localHasColumn(T, name)
        values = localBoolColumn(T, name, false(n, 1));
        matched = true(n, 1);
        fail = fail | ~values;
    end
end
for name = string(statusNames)
    if localHasColumn(T, name)
        status = lower(strtrim(string(localColumn(T, name, repmat("", n, 1)))));
        bad = ismember(status, ["fail","failed","error","strict_objective_failed","false","0"]);
        good = ismember(status, ["pass","passed","ok","success","true","1"]);
        fail = fail | bad;
        matched = matched | bad | good;
    end
end
for name = string(reasonNames)
    if localHasColumn(T, name)
        reason = strtrim(string(localColumn(T, name, repmat("", n, 1))));
        badReason = strlength(reason) > 0 & ~ismissing(reason) & ...
            ~ismember(lower(reason), ["pass","passed","ok","none",""]);
        fail = fail | badReason;
        matched = matched | badReason;
    end
end
if ~any(matched)
    fail = false(n, 1);
end
end

function rates = localCodeRates(T)
n = height(T);
rates = nan(n, 1);
explicit = localFirstNumericColumn(T, ["CodeRate","TargetCodeRate","EffectiveCodeRate", ...
    "ActualCodeRate","NominalCodeRate"], NaN);
rates(isfinite(explicit)) = explicit(isfinite(explicit));
tbs = localFirstNumericColumn(T, ["TBSize_bits","TBSBits","TBS","TransportBlockSize"], NaN);
g = localFirstNumericColumn(T, ["RateMatchedBitCount","CodedBitCountG","G","G_bits", ...
    "CodedBits","CodedBitCount"], NaN);
derived = tbs ./ g;
fill = ~isfinite(rates) & isfinite(derived);
rates(fill) = derived(fill);
end

function delivered = localDeliveredMask(T)
n = height(T);
delivered = false(n, 1);
matched = false;
for name = ["DeliverySuccess","Delivered","PacketDelivered","FirstSuccessDelivery"]
    if localHasColumn(T, name)
        delivered = delivered | localBoolColumn(T, name, false(n, 1));
        matched = true;
    end
end
if ~matched && localHasColumn(T, "DeliveryTime_s")
    delivered = isfinite(localNumericColumn(T, "DeliveryTime_s", NaN));
end
end

function row = localInvariantRow(checkName, scope, rowsChecked, rowsFailed, metricValue, threshold, failEnabled, failureCode, details)
status = localStatus(rowsFailed > 0, failEnabled);
code = "";
if status == "FAIL" || status == "WARN"
    code = failureCode;
end
row = localRow(checkName, scope, rowsChecked, rowsFailed, metricValue, threshold, status, code, details);
end

function status = localStatus(failed, failEnabled)
if failed && failEnabled
    status = "FAIL";
elseif failed
    status = "WARN";
else
    status = "PASS";
end
end

function row = localEmptyRow()
row = struct("CheckName", "", "Scope", "", "RowsChecked", NaN, "RowsFailed", NaN, ...
    "MetricValue", NaN, "Threshold", "", "Status", "", "FailureCode", "", "Details", "");
end

function row = localRow(checkName, scope, rowsChecked, rowsFailed, metricValue, threshold, status, failureCode, details)
row = struct("CheckName", string(checkName), "Scope", string(scope), ...
    "RowsChecked", double(rowsChecked), "RowsFailed", double(rowsFailed), ...
    "MetricValue", double(metricValue), "Threshold", string(threshold), ...
    "Status", string(status), "FailureCode", string(failureCode), "Details", string(details));
end

function T = localRowsToTable(rows)
if isempty(rows)
    T = struct2table(repmat(localEmptyRow(), 0, 1), "AsArray", true);
else
    T = struct2table(rows, "AsArray", true);
end
end

function inventory = localArtifactInventory(artifacts)
names = fieldnames(artifacts);
inventory = struct();
for i = 1:numel(names)
    a = artifacts.(names{i});
    inventory.(names{i}) = struct("RelativePath", string(a.RelativePath), ...
        "Present", logical(a.Present), "Readable", logical(a.Readable), ...
        "RowCount", double(height(a.Table)), "ReadFailureReason", string(a.ReadFailureReason));
end
end

function [T, present, readable, reason] = localReadOptionalTable(path)
present = exist(char(path), "file") == 2;
readable = false;
reason = "";
T = table();
if ~present
    reason = "artifact_missing";
    return;
end
try
    T = readtable(char(path), "VariableNamingRule", "preserve", "TextType", "string");
    readable = true;
catch ME
    reason = string(ME.identifier) + ":" + string(ME.message);
end
end

function key = localKey(relPath)
key = matlab.lang.makeValidName(regexprep(char(string(relPath)), "[/\\.-]", "_"));
end

function tf = localHasColumn(T, name)
tf = istable(T) && any(strcmpi(string(T.Properties.VariableNames), string(name)));
end

function values = localColumn(T, name, defaultValue)
if nargin < 3
    defaultValue = strings(height(T), 1);
end
idx = find(strcmpi(string(T.Properties.VariableNames), string(name)), 1, "first");
if isempty(idx)
    values = defaultValue;
else
    values = T.(T.Properties.VariableNames{idx});
end
values = values(:);
end

function values = localNumericColumn(T, name, defaultValue)
raw = localColumn(T, name, defaultValue);
if isnumeric(raw) || islogical(raw)
    values = double(raw);
else
    values = str2double(string(raw));
end
values = values(:);
end

function values = localFirstNumericColumn(T, names, defaultValue)
values = repmat(double(defaultValue), height(T), 1);
for name = string(names)
    if localHasColumn(T, name)
        candidate = localNumericColumn(T, name, NaN);
        fill = ~isfinite(values) & isfinite(candidate);
        values(fill) = candidate(fill);
        if all(isfinite(values))
            return;
        end
    end
end
end

function values = localBoolColumn(T, name, defaultValue)
raw = localColumn(T, name, defaultValue);
if islogical(raw)
    values = raw;
elseif isnumeric(raw)
    values = raw ~= 0;
else
    s = lower(strtrim(string(raw)));
    values = ismember(s, ["true","1","yes","ok","pass","passed","success"]);
end
values = values(:);
if numel(values) ~= height(T)
    values = repmat(logical(defaultValue(1)), height(T), 1);
end
end

function x = localMinOrNaN(values)
values = double(values);
values = values(isfinite(values));
if isempty(values)
    x = NaN;
else
    x = min(values);
end
end

function x = localMaxOrNaN(values)
values = double(values);
values = values(isfinite(values));
if isempty(values)
    x = NaN;
else
    x = max(values);
end
end

function out = localTernary(cond, a, b)
if logical(cond)
    out = a;
else
    out = b;
end
end
