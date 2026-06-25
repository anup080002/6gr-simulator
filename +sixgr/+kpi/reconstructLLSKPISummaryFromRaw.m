function out = reconstructLLSKPISummaryFromRaw(raw, varargin)
%RECONSTRUCTLLSKPISUMMARYFROMRAW Direction-safe LLS KPI reconstruction.

ip = inputParser;
ip.addParameter("RunId", "", @(x) ischar(x) || isstring(x) || isnumeric(x));
ip.addParameter("ScenarioName", "", @(x) ischar(x) || isstring(x));
ip.addParameter("SourcePaths", struct(), @(x) isempty(x) || isstruct(x));
ip.addParameter("ExportedSummary", table(), @(x) isempty(x) || istable(x));
ip.addParameter("StrictMode", false, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
ip.parse(varargin{:});

runId = string(ip.Results.RunId);
scenarioName = string(ip.Results.ScenarioName);
sourcePaths = ip.Results.SourcePaths;
exportedSummary = ip.Results.ExportedSummary;
strictMode = logical(ip.Results.StrictMode);

registry = sixgr.kpi.KPIFormulaRegistry();
schemaAudit = sixgr.kpi.validateRawKPITables(raw);

[ulMetrics, ulContrib, ulTrace] = localComputeDirection(raw, sourcePaths, "UL", runId, scenarioName);
[dlMetrics, dlContrib, dlTrace] = localComputeDirection(raw, sourcePaths, "DL", runId, scenarioName);

summary = localBuildLegacySummary(runId, scenarioName, ulMetrics, dlMetrics, strictMode);
recon = localBuildReconstructionSummary(runId, scenarioName, registry, ulMetrics, dlMetrics, exportedSummary);
dirAudit = localBuildDirectionIsolationAudit(runId, ulMetrics, dlMetrics);
aliasMap = localBuildLegacyAliasMap(runId, registry, summary, recon);
knownBug = sixgr.kpi.guardNoULGoodputCopiedFromDL(summary, ulMetrics, dlMetrics);
unitAudit = localBuildUnitAudit(runId, recon);
durationAudit = localBuildDurationAudit(runId, scenarioName, ulMetrics, dlMetrics);
sourceManifest = localBuildSourceManifest(runId, scenarioName, raw, sourcePaths);

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
out.ObjectiveBinding = localBuildObjectiveBinding(runId, scenarioName, registry, recon);
out.RowContributionsUL = ulContrib;
out.RowContributionsDL = dlContrib;
out.HARQDeliveryTraceUL = ulTrace;
out.HARQDeliveryTraceDL = dlTrace;
out.StrictOk = all(localColumnBool(recon, "StrictOk", false)) && ...
    all(localColumnBool(dirAudit, "Status", "pass")) && ...
    all(localColumnBool(knownBug, "BugPrevented", false)) && ...
    all(localColumnBool(unitAudit, "Pass", true)) && ...
    all(localColumnBool(durationAudit, "Pass", false));
out.Status = string(localTernary(out.StrictOk, "pass", "fail"));
end

function [metrics, contribT, traceT] = localComputeDirection(raw, sourcePaths, direction, runId, scenarioName)
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
    "DurationSource", "unavailable", ...
    "ScheduledBits", NaN, ...
    "DeliveredBits", NaN, ...
    "GoodputMax_Mbps", NaN, ...
    "ScheduledThroughput_Mbps", NaN, ...
    "TBGooDput_Mbps", NaN, ...
    "TBGoodput_Mbps", NaN, ...
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

[durationSec, durationSource] = localDurationSec(E);
metrics.AggregationDurationSec = durationSec;
metrics.DurationSource = durationSource;
metrics.ScheduledBits = sum(scheduledBits, "omitnan");
if ~(isfinite(durationSec) && durationSec > 0)
    metrics.Status = "invalid_duration";
    metrics.FailureReason = "radio_duration_unavailable";
    return;
end

[deliveryBits, duplicateCount, traceT] = localDeduplicateDeliveries(E, direction, runId, scheduledBits, goodBits, crcPass);
metrics.DeliveredBits = deliveryBits;
metrics.DuplicateDeliveryCount = duplicateCount;
if isfinite(durationSec) && durationSec > 0
    metrics.ScheduledThroughput_Mbps = metrics.ScheduledBits / durationSec / 1e6;
    metrics.TBGoodput_Mbps = metrics.DeliveredBits / durationSec / 1e6;
    metrics.TBGooDput_Mbps = metrics.TBGoodput_Mbps;
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
contribT = localBuildContributionTable(E, direction, runId, scenarioName, sourcePath, scheduledBits, goodBits, durationSec);
end

function [bits, duplicateCount, traceT] = localDeduplicateDeliveries(T, direction, runId, scheduledBits, goodBits, crcPass)
traceRows = repmat(localHARQTraceRow(), height(T), 1);
keys = strings(height(T), 1);
for i = 1:height(T)
    keys(i) = localTransportBlockKey(T, i);
end
seenDelivered = strings(0, 1);
bits = 0;
duplicateCount = 0;
for i = 1:height(T)
    delivered = logical(crcPass(i)) && isfinite(goodBits(i)) && goodBits(i) > 0;
    duplicate = false;
    counted = 0;
    if delivered
        if any(seenDelivered == keys(i))
            duplicate = true;
            duplicateCount = duplicateCount + 1;
        else
            seenDelivered(end+1, 1) = keys(i); %#ok<AGROW>
            counted = goodBits(i);
            bits = bits + counted;
        end
    end
    traceRows(i).RunId = string(runId);
    traceRows(i).Direction = direction;
    traceRows(i).TransportBlockId = keys(i);
    traceRows(i).HARQProcessId = localRowNum(T, "HARQProcessId", i, NaN);
    traceRows(i).AttemptIndex = i;
    traceRows(i).RV = localRowNum(T, "RV", i, NaN);
    traceRows(i).NDI = localRowNum(T, "NDI", i, NaN);
    traceRows(i).ScheduledBits = scheduledBits(i);
    traceRows(i).TBCrcPass = logical(crcPass(i));
    traceRows(i).DeliveredThisAttempt = delivered;
    traceRows(i).DuplicateDelivery = duplicate;
    traceRows(i).CountedGoodputBits = counted;
    traceRows(i).DeliveryStatus = string(localTernary(delivered, "delivered", "not_delivered"));
    traceRows(i).Status = "pass";
end
traceT = struct2table(traceRows);
end

function key = localTransportBlockKey(T, i)
vars = string(T.Properties.VariableNames);
for name = ["TransportBlockId","TBId","MACPDUId","MACSDUId","GrantContextId"]
    if ismember(name, vars)
        raw = string(T.(name)(i));
        if strlength(strtrim(raw)) > 0 && raw ~= "NaN"
            key = raw;
            return;
        end
    end
end
ue = localRowNum(T, "UEIndex", i, localRowNum(T, "UEId", i, NaN));
harq = localRowNum(T, "HARQProcessId", i, NaN);
ndi = localRowNum(T, "NDI", i, NaN);
frame = localRowNum(T, "Frame", i, NaN);
slot = localRowNum(T, "Slot", i, NaN);
rv = localRowNum(T, "RV", i, NaN);
key = "derived_ue" + string(ue) + "_harq" + string(harq) + "_ndi" + string(ndi) + "_f" + string(frame) + "_s" + string(slot) + "_rv" + string(rv);
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

function T = localBuildReconstructionSummary(runId, scenarioName, registry, ul, dl, exportedSummary)
defs = [
    localRecon("UL_Goodput_Max_Mbps", ul, "GoodputMax_Mbps", "Goodput_UL_max_Mbps");
    localRecon("DL_Goodput_Max_Mbps", dl, "GoodputMax_Mbps", "Goodput_DL_max_Mbps");
    localRecon("UL_PHY_ScheduledThroughput_Mbps", ul, "ScheduledThroughput_Mbps", "");
    localRecon("DL_PHY_ScheduledThroughput_Mbps", dl, "ScheduledThroughput_Mbps", "");
    localRecon("UL_TB_Delivery_Goodput_Mbps", ul, "TBGoodput_Mbps", "");
    localRecon("DL_TB_Delivery_Goodput_Mbps", dl, "TBGoodput_Mbps", "");
    localRecon("UL_BLER", ul, "BLER", "BLER_UL_min");
    localRecon("DL_BLER", dl, "BLER", "BLER_DL_min");
    localRecon("UL_BER", ul, "BER", "");
    localRecon("DL_BER", dl, "BER", "")
    ];
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
    rows(i).AggregationDurationSec = d.Metrics.AggregationDurationSec;
    rows(i).DurationSource = d.Metrics.DurationSource;
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
    rows(i).FormulaExecuted = strcmp(d.Metrics.Status, "pass");
    rows(i).ExportedSummaryValue = exported;
    rows(i).ReconstructionValue = value;
    rows(i).ReconstructionDelta = delta;
    rows(i).ReconciliationTolerance = tolerance;
    rows(i).ReconciliationPass = pass;
    rows(i).StrictOk = pass && strcmp(d.Metrics.Status, "pass");
    rows(i).Status = string(localTernary(rows(i).StrictOk, "pass", "fail"));
    rows(i).FailureReason = string(localTernary(rows(i).StrictOk, "", d.Metrics.FailureReason));
end
T = struct2table(rows);
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
rows = repmat(struct("RunId","", "KPIName","", "Direction","", "Bits",NaN, "DurationSec",NaN, ...
    "ExpectedMbps",NaN, "ComputedMbps",NaN, "Delta",NaN, "Tolerance",1e-9, "Pass",false, "Status","", "FailureReason",""), 0, 1);
mask = contains(string(recon.KPIName), "ScheduledThroughput_Mbps") | ...
    contains(string(recon.KPIName), "TB_Delivery_Goodput_Mbps");
idxs = find(mask(:).');
for j = 1:numel(idxs)
    i = idxs(j);
    row = struct("RunId",string(runId), "KPIName",string(recon.KPIName(i)), "Direction",string(recon.Direction(i)), ...
        "Bits",double(recon.NumeratorValue(i)), "DurationSec",double(recon.AggregationDurationSec(i)), ...
        "ExpectedMbps",NaN, "ComputedMbps",double(recon.Value(i)), "Delta",NaN, "Tolerance",1e-9, ...
        "Pass",false, "Status","fail", "FailureReason","duration_or_bits_unavailable");
    if isfinite(row.Bits) && isfinite(row.DurationSec) && row.DurationSec > 0
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

function T = localBuildObjectiveBinding(runId, scenarioName, registry, recon)
rows = repmat(struct("RunId","", "ScenarioName","", "KPIName","", "Direction","", ...
    "Layer","", "MandatoryInScenarioObjective",false, "FormulaId","", ...
    "RawEvidenceAvailable",false, "ReconstructionPass",false, "StrictOk",false, ...
    "ScenarioObjectiveContribution","not_configured", "Status","not_evaluated", "FailureReason",""), 0, 1);
for i = 1:height(registry)
    kpiName = string(registry.KPIName(i));
    idx = find(strcmp(string(recon.KPIName), kpiName), 1);
    row = struct("RunId",string(runId), "ScenarioName",string(scenarioName), ...
        "KPIName",kpiName, "Direction",string(registry.Direction(i)), ...
        "Layer",string(registry.Layer(i)), ...
        "MandatoryInScenarioObjective",logical(registry.StrictAllowed(i)), ...
        "FormulaId",kpiName, "RawEvidenceAvailable",false, ...
        "ReconstructionPass",false, "StrictOk",false, ...
        "ScenarioObjectiveContribution","not_configured", "Status","not_applicable", ...
        "FailureReason","not_in_current_reconstruction_scope");
    if ~isempty(idx)
        row.RawEvidenceAvailable = ~logical(recon.MissingRawData(idx));
        row.ReconstructionPass = logical(recon.ReconciliationPass(idx));
        row.StrictOk = logical(recon.StrictOk(idx));
        row.ScenarioObjectiveContribution = string(localTernary(row.MandatoryInScenarioObjective, "mandatory", "optional"));
        row.Status = string(localTernary(row.StrictOk || ~row.MandatoryInScenarioObjective, "pass", "fail"));
        row.FailureReason = string(localTernary(strcmp(row.Status, "pass"), "", string(recon.FailureReason(idx))));
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
    "AggregationDurationSec",double(m.AggregationDurationSec), "WallClockUsedForRadioThroughput",false, ...
    "Pass",isfinite(double(m.AggregationDurationSec)) && double(m.AggregationDurationSec) > 0 && ~contains(string(m.DurationSource), "wall"), ...
    "Status","", "FailureReason","");
row.Status = string(localTernary(row.Pass, "pass", "fail"));
row.FailureReason = string(localTernary(row.Pass, "", "invalid_radio_duration"));
end

function T = localBuildSourceManifest(runId, scenarioName, raw, sourcePaths)
rows = [localManifestRow(runId, scenarioName, raw, sourcePaths, "UL"); localManifestRow(runId, scenarioName, raw, sourcePaths, "DL")];
T = struct2table(rows);
end

function row = localManifestRow(runId, scenarioName, raw, paths, direction)
T = table();
if isstruct(raw) && isfield(raw, char(direction)) && istable(raw.(char(direction)))
    T = raw.(char(direction));
end
path = localSourcePath(paths, direction);
row = struct("RunId",string(runId), "ScenarioName",string(scenarioName), ...
    "SourceTablePath",string(path), "SourceTableName",string(localSourceName(direction)), ...
    "Direction",string(direction), "Layer","PHY", "RequiredForObjective",true, ...
    "Exists",istable(T) && ~isempty(T), "RowCount",height(T), "ColumnCount",width(T), ...
    "FileHash",sixgr.kpi.hashKPISourceRows(T), "SchemaHash","kpi_schema_v1", ...
    "ProducerModule","sixgr.kpi.reconstructLLSKPISummaryFromRaw", ...
    "ModifiedTime","", "Status","", "FailureReason","");
row.Status = string(localTernary(row.Exists, "pass", "missing"));
row.FailureReason = string(localTernary(row.Exists, "", "source_table_missing_or_empty"));
end

function path = localSourcePath(paths, direction)
path = "";
if isstruct(paths) && isfield(paths, char(direction))
    path = string(paths.(char(direction)));
end
if strlength(path) == 0
    if direction == "UL"
        path = "air_interface/csv/ul_pusch_trials.csv";
    else
        path = "air_interface/csv/dl_pdsch_trials.csv";
    end
end
end

function T = localBuildContributionTable(E, direction, runId, scenarioName, sourcePath, scheduledBits, goodBits, durationSec)
rows = repmat(localContributionRow(), height(E), 1);
perRowDuration = durationSec / max(height(E), 1);
if ismember("DurationSec", string(E.Properties.VariableNames))
    perRowDuration = localOptionalNumeric(E, "DurationSec", repmat(perRowDuration, height(E), 1));
elseif ismember("AirInterfaceObservation_ms", string(E.Properties.VariableNames))
    perRowDuration = localOptionalNumeric(E, "AirInterfaceObservation_ms", repmat(perRowDuration * 1e3, height(E), 1)) ./ 1e3;
elseif ismember("AirInterfaceTTI_ms", string(E.Properties.VariableNames))
    perRowDuration = localOptionalNumeric(E, "AirInterfaceTTI_ms", repmat(perRowDuration * 1e3, height(E), 1)) ./ 1e3;
end
perRowDuration = localDistributeUniqueSlotDuration(E, perRowDuration, durationSec);
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
    rows(i).TransportBlockId = localTransportBlockKey(E, i);
    rows(i).HARQProcessId = localRowNum(E, "HARQProcessId", i, NaN);
    rows(i).RV = localRowNum(E, "RV", i, NaN);
    rows(i).NDI = localRowNum(E, "NDI", i, NaN);
    rows(i).TBCrcPass = crcPass(i);
    rows(i).ScheduledBitsContribution = scheduledBits(i);
    rows(i).DeliveredBitsContribution = goodBits(i);
    rows(i).GoodputBitsContribution = goodBits(i);
    rows(i).DurationContributionSec = perRowDuration(i);
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
if ismember("DurationSec", string(T.Properties.VariableNames))
    vals = localOptionalNumeric(T, "DurationSec", NaN(height(T), 1));
    [durationSec, source] = localUniqueSlotDurationSec(T, vals, "raw_duration_sec_unique_slot");
    if ~(isfinite(durationSec) && durationSec > 0)
        durationSec = sum(vals(isfinite(vals) & vals >= 0), "omitnan");
        source = "raw_duration_sec_sum";
    end
elseif ismember("AirInterfaceObservation_ms", string(T.Properties.VariableNames))
    vals = localOptionalNumeric(T, "AirInterfaceObservation_ms", NaN(height(T), 1));
    [durationSec, source] = localUniqueSlotDurationSec(T, vals ./ 1e3, "air_interface_observation_ms_unique_slot");
    if ~(isfinite(durationSec) && durationSec > 0)
        durationSec = sum(vals(isfinite(vals) & vals >= 0), "omitnan") / 1e3;
        source = "air_interface_observation_ms_sum";
    end
elseif ismember("AirInterfaceTTI_ms", string(T.Properties.VariableNames))
    vals = localOptionalNumeric(T, "AirInterfaceTTI_ms", NaN(height(T), 1));
    [durationSec, source] = localUniqueSlotDurationSec(T, vals ./ 1e3, "air_interface_tti_ms_unique_slot");
    if ~(isfinite(durationSec) && durationSec > 0)
        durationSec = sum(vals(isfinite(vals) & vals >= 0), "omitnan") / 1e3;
        source = "air_interface_tti_ms_sum";
    end
end
if ~(isfinite(durationSec) && durationSec > 0)
    slotDurationSec = localTrialSlotDurationSec(T);
    finalized = true(height(T), 1);
    if ismember("FinalizedFlag", string(T.Properties.VariableNames))
        finalized = localOptionalLogical(T, "FinalizedFlag", finalized);
    end
    durationSec = sum(finalized) * slotDurationSec;
    source = "geometry_trial_count_slot_duration";
end
if ~(isfinite(durationSec) && durationSec > 0)
    durationSec = NaN;
    source = "unavailable";
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
if contains(kpiName, "ScheduledThroughput")
    v = metrics.ScheduledBits;
elseif contains(kpiName, "Goodput")
    v = metrics.DeliveredBits;
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
if contains(kpiName, "Throughput") || contains(kpiName, "Goodput")
    v = metrics.AggregationDurationSec;
else
    v = metrics.SourceRowCount;
end
end

function name = localSourceName(direction)
if direction == "UL"
    name = "ul_pusch_trials";
else
    name = "dl_pdsch_trials";
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
    "GoodputBitsContribution",NaN, "DurationContributionSec",NaN, "Included",false, ...
    "ExcludedReason","", "Status","not_evaluated");
end

function T = localEmptyHARQTraceTable()
T = struct2table(repmat(localHARQTraceRow(), 0, 1));
end

function row = localHARQTraceRow()
row = struct("RunId","", "Direction","", "UEId",NaN, "TransportBlockId","", ...
    "HARQProcessId",NaN, "AttemptIndex",NaN, "RV",NaN, "NDI",NaN, ...
    "ScheduledBits",NaN, "TBCrcPass",false, "DeliveredThisAttempt",false, ...
    "DuplicateDelivery",false, "CountedGoodputBits",NaN, "DeliveryStatus","", ...
    "Status","", "FailureReason","");
end

function row = localReconRow()
row = struct("RunId","", "ScenarioName","", "KPIName","", "Direction","", "Layer","", ...
    "Units","", "FormulaId","", "FormulaVersion","", "NumeratorValue",NaN, ...
    "DenominatorValue",NaN, "Value",NaN, "AggregationDurationSec",NaN, ...
    "DurationSource","", "SourceTablePaths","", "SourceRowCount",0, "EligibleRowCount",0, ...
    "ExcludedRowCount",0, "SourceRowsHash","", "SourceDirection","", "ProxyRowsExcluded",0, ...
    "SkippedRowsExcluded",0, "FailedRowsIncluded",true, "HARQDeduplicationApplied",false, ...
    "DuplicateDeliveryCount",0, "MissingRawData",true, "SchemaValid",false, ...
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
