function status = evaluateVisualArtifactContract(spec, sourceT)
%EVALUATEVISUALARTIFACTCONTRACT Validate source data against a plot contract.

if nargin < 2 || isempty(sourceT)
    sourceT = table();
end

if ~(isstruct(spec) && isfield(spec, "PlotType"))
    error("sixgr:visual:evaluateVisualArtifactContract:BadSpec", "Visual artifact contract spec is required.");
end

missingColumns = localMissingColumns(sourceT, spec.RequiredColumns);
if ~isempty(missingColumns)
    status = sixgr.visual.validatePlotData(spec.PlotType, [], [], ...
        "MinimumRows", spec.MinRows, ...
        "MinimumUniqueX", spec.MinUniqueX, ...
        "MinimumUniqueY", spec.MinUniqueY, ...
        "LLSValidity", "unavailable");
    status.PlotRenderStatus = "suppressed";
    status.PlotSuppressionReason = "missing_required_columns:" + strjoin(missingColumns, "|");
    status.CountsAsRealPlot = false;
    status.VisualValidity = "unavailable";
    status.WarningBannerText = "";
    status.RequiredColumnsPresent = false;
    status.MissingRequiredColumns = strjoin(missingColumns, "|");
    status.ContractPlotId = string(spec.PlotId);
    status.CurveConstructionStatus = "not_evaluated_missing_columns";
    status.TruthStatus = "not_evaluated_missing_columns";
    return;
end

x = localResolveColumn(sourceT, spec.XVariable);
y = localResolveColumn(sourceT, spec.YVariable);
status = sixgr.visual.validatePlotData(spec.PlotType, x, y, ...
    "MinimumRows", spec.MinRows, ...
    "MinimumUniqueX", spec.MinUniqueX, ...
    "MinimumUniqueY", spec.MinUniqueY, ...
    "LLSValidity", spec.LLSValidity);
status.RequiredColumnsPresent = true;
status.MissingRequiredColumns = "";
status.ContractPlotId = string(spec.PlotId);

[truthOk, truthStatus, truthReason] = localTruthStatusAllowed(sourceT, spec);
[curveOk, curveStatus, curveReason] = localCurveConstructionAllowed(sourceT, spec);
status.TruthStatus = truthStatus;
status.CurveConstructionStatus = curveStatus;

if string(status.PlotRenderStatus) ~= "rendered"
    status.CountsAsRealPlot = false;
    status.VisualValidity = "unavailable";
    status.WarningBannerText = "";
    return;
end

if ~(truthOk && curveOk)
    reasons = [truthReason; curveReason];
    reasons = reasons(strlength(reasons) > 0);
    if isempty(reasons)
        reasons = "visual_contract_not_satisfied";
    end
    status.PlotRenderStatus = "suppressed";
    status.PlotSuppressionReason = strjoin(reasons, "|");
    status.CountsAsRealPlot = false;
    status.VisualValidity = "unavailable";
    status.WarningBannerText = "";
    return;
end

validity = lower(string(spec.LLSValidity));
if validity == "diagnostic_only"
    status.CountsAsRealPlot = false;
    status.VisualValidity = "diagnostic_only";
    status.WarningBannerText = "DIAGNOSTIC ONLY - not counted as real LLS evidence";
else
    status.CountsAsRealPlot = true;
    status.VisualValidity = "real_lls_evidence";
    status.WarningBannerText = "";
end
end

function missing = localMissingColumns(T, requiredColumns)
requiredColumns = string(requiredColumns(:));
requiredColumns = requiredColumns(strlength(requiredColumns) > 0);
if isempty(requiredColumns)
    missing = strings(0, 1);
    return;
end
if ~istable(T) || isempty(T)
    missing = requiredColumns;
    return;
end
vars = string(T.Properties.VariableNames);
missing = requiredColumns(~ismember(requiredColumns, vars));
end

function values = localResolveColumn(T, columnName)
values = [];
if ~(istable(T) && ~isempty(T))
    return;
end
columnName = string(columnName);
if strlength(columnName) == 0
    values = (1:height(T)).';
    return;
end
if ~ismember(columnName, string(T.Properties.VariableNames))
    return;
end
raw = T.(columnName);
try
    values = double(raw);
catch
    values = str2double(string(raw));
end
end

function [ok, status, reason] = localTruthStatusAllowed(T, spec)
status = "not_declared";
reason = "";
ok = true;
if ~(istable(T) && ~isempty(T))
    status = "source_empty";
    ok = false;
    reason = "source_table_empty";
    return;
end
tokens = localCollectTextTokens(T, ["VisualTruthStatus","TruthStatus","RuntimeEvidenceStatus","RuntimeMaterializationStatus", ...
    "truth_status","runtime_evidence_status","Source","SourceType","SourceKind","ValueRole","SINRValueRole","ReceiverHestSINRValueRole", ...
    "ApproximationMode","approximation_mode","ExecutionBackend","execution_backend","E2EAirModel","Notes","notes"]);
if isempty(tokens)
    return;
end
status = strjoin(unique(tokens, "stable"), "|");
allowed = lower(string(spec.AllowedTruthStatus));
requiredColumns = lower(string(spec.RequiredColumns(:)));
if any(requiredColumns == "truth_status")
    declared = localCollectTextTokens(T, "truth_status");
    declared = declared(strlength(declared) > 0);
    if isempty(declared)
        ok = false;
        reason = "truth_status_empty";
        return;
    end
    unknown = declared(~ismember(declared, allowed));
    if ~isempty(unknown)
        ok = false;
        reason = "truth_status_not_allowed:" + strjoin(unique(unknown, "stable"), "|");
        return;
    end
end
forbidden = ["fallback","synthetic","proxy","fast_proxy","lut","logistic","configured_sinr","reference_sinr", ...
    "anchor_sinr","configured_cqi","reference_cqi","generic","measured_bin","fake","placeholder"];
if any(contains(tokens, forbidden), "all")
    diagnosticAllowed = any(allowed == "diagnostic_only") || lower(string(spec.LLSValidity)) == "diagnostic_only";
    if diagnosticAllowed
        ok = true;
    else
        ok = false;
        reason = "forbidden_truth_status:" + status;
    end
end
end

function [ok, status, reason] = localCurveConstructionAllowed(T, spec)
status = "not_declared";
reason = "";
ok = true;
tokens = localCollectTextTokens(T, ["CurveConstruction","curve_construction","CurveConstructionMode","curve_construction_mode", ...
    "CurveConstructionSource","curve_construction_source","ChartConstruction","chart_construction", ...
    "AggregationMethod","aggregation_method","SourceCurveConstruction","source_curve_construction","SeriesConstruction","series_construction"]);
if isempty(tokens)
    return;
end
status = strjoin(unique(tokens, "stable"), "|");
allowed = lower(string(spec.AllowedCurveConstruction(:)));
allowed = allowed(strlength(allowed) > 0);
if isempty(allowed) || any(allowed == "any")
    return;
end
tokensNoBlank = tokens(strlength(tokens) > 0);
unknown = tokensNoBlank(~ismember(tokensNoBlank, allowed));
if ~isempty(unknown)
    ok = false;
    reason = "curve_construction_not_allowed:" + strjoin(unique(unknown, "stable"), "|");
end
end

function tokens = localCollectTextTokens(T, candidateColumns)
tokens = strings(0, 1);
if ~(istable(T) && ~isempty(T))
    return;
end
vars = string(T.Properties.VariableNames);
for i = 1:numel(candidateColumns)
    name = string(candidateColumns(i));
    if ~ismember(name, vars)
        continue;
    end
    raw = string(T.(name));
    raw = lower(strtrim(raw(:)));
    raw = raw(strlength(raw) > 0 & raw ~= "<missing>" & raw ~= "nan");
    tokens = [tokens; raw]; %#ok<AGROW>
end
tokens = unique(tokens, "stable");
end
