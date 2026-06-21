function specs = loadVisualArtifactContract()
%LOADVISUALARTIFACTCONTRACT Load canonical LLS visual artifact contracts.

contractPath = localContractPath();
if exist(contractPath, "file") ~= 2
    specs = repmat(localDefaultSpec(), 0, 1);
    return;
end

raw = jsondecode(fileread(contractPath));
if ~isfield(raw, "contracts") || isempty(raw.contracts)
    specs = repmat(localDefaultSpec(), 0, 1);
    return;
end

entries = raw.contracts;
specs = repmat(localDefaultSpec(), 0, 1);
for i = 1:numel(entries)
    e = entries(i);
    spec = localDefaultSpec();
    spec.PlotId = string(localField(e, "plot_id", ""));
    spec.ImagePath = localNormalizeRelativePath(localField(e, "file_path", ""));
    spec.FilePath = spec.ImagePath;
    spec.SourceCSV = localNormalizeRelativePath(localField(e, "source_csv", ""));
    spec.RequiredColumns = localStringArray(localField(e, "required_columns", {}));
    [spec.XVariable, spec.YVariable] = localResolveAxisVariables(spec.PlotId, spec.RequiredColumns);
    spec.XSemantics = string(localField(e, "x_semantics", ""));
    spec.YSemantics = string(localField(e, "y_semantics", ""));
    spec.Units = localUnitsSummary(localField(e, "units", struct()));
    spec.MinRows = double(localField(e, "min_rows", 2));
    spec.MinUniqueX = double(localField(e, "min_unique_x", 1));
    spec.MinUniqueY = double(localField(e, "min_unique_y", 1));
    spec.AllowedTruthStatus = localStringArray(localField(e, "allowed_truth_status", "real_lls_evidence"));
    spec.AllowedCurveConstruction = localStringArray(localField(e, "allowed_curve_construction", "none"));
    spec.PlotType = lower(string(localField(e, "plot_kind", "relation")));
    spec.PlotKind = spec.PlotType;
    spec.LLSValidity = lower(string(localField(e, "lls_validity", "real_lls_evidence")));
    spec.AggregationMethod = localAggregationMethod(spec);
    specs(end + 1, 1) = spec; %#ok<AGROW>
end
end

function path = localContractPath()
visualDir = fileparts(mfilename("fullpath"));
repoRoot = fileparts(fileparts(visualDir));
path = fullfile(repoRoot, "simulator", "configs", "schema", "visual_artifact_contract.json");
end

function spec = localDefaultSpec()
spec = struct( ...
    "PlotId", "", ...
    "ImagePath", "", ...
    "FilePath", "", ...
    "SourceCSV", "", ...
    "RequiredColumns", strings(0, 1), ...
    "XVariable", "", ...
    "YVariable", "", ...
    "XSemantics", "", ...
    "YSemantics", "", ...
    "Units", "", ...
    "MinRows", 2, ...
    "MinUniqueX", 1, ...
    "MinUniqueY", 1, ...
    "AllowedTruthStatus", "real_lls_evidence", ...
    "AllowedCurveConstruction", "none", ...
    "PlotType", "relation", ...
    "PlotKind", "relation", ...
    "LLSValidity", "real_lls_evidence", ...
    "AggregationMethod", "none");
end

function value = localField(s, name, fallback)
if isstruct(s) && isfield(s, name)
    value = s.(name);
else
    value = fallback;
end
end

function out = localStringArray(value)
if isempty(value)
    out = strings(0, 1);
elseif isstring(value)
    out = value(:);
elseif ischar(value)
    out = string(value);
elseif iscell(value)
    out = strings(numel(value), 1);
    for i = 1:numel(value)
        out(i) = string(value{i});
    end
else
    try
        out = string(value(:));
    catch
        out = string(value);
    end
end
out = strtrim(out(:));
out = out(strlength(out) > 0);
end

function path = localNormalizeRelativePath(path)
path = replace(string(path), "\", "/");
path = regexprep(path, "^/+","");
end

function out = localUnitsSummary(units)
out = "";
if ~isstruct(units)
    return;
end
parts = strings(0, 1);
names = fieldnames(units);
for i = 1:numel(names)
    parts(end + 1, 1) = string(names{i}) + "=" + string(units.(names{i})); %#ok<AGROW>
end
out = strjoin(parts, "|");
end

function out = localAggregationMethod(spec)
allowed = string(spec.AllowedCurveConstruction);
if isempty(allowed)
    out = "none";
else
    out = allowed(1);
end
end

function [xVar, yVar] = localResolveAxisVariables(plotId, requiredColumns)
requiredColumns = string(requiredColumns(:));
plotId = lower(string(plotId));
xVar = "";
yVar = "";
if any(requiredColumns == "XValue") && any(requiredColumns == "YValue")
    xVar = "XValue";
    yVar = "YValue";
elseif any(requiredColumns == "snr_db") && plotId == "bler_vs_snr"
    xVar = "snr_db";
    yVar = "bler";
elseif any(requiredColumns == "snr_db") && plotId == "throughput_vs_snr"
    xVar = "snr_db";
    yVar = "throughput_mbps";
elseif any(requiredColumns == "BinCenterPostEqSINR_dB") && any(requiredColumns == "BLER")
    xVar = "BinCenterPostEqSINR_dB";
    yVar = "BLER";
elseif plotId == "prach_correlation_traces" && any(requiredColumns == "lag_samples") && any(requiredColumns == "correlation_abs")
    xVar = "lag_samples";
    yVar = "correlation_abs";
elseif plotId == "equalized_constellations" && any(requiredColumns == "equalized_i") && any(requiredColumns == "equalized_q")
    xVar = "equalized_i";
    yVar = "equalized_q";
elseif any(requiredColumns == "SNR_dB") && any(requiredColumns == "MetricValue")
    xVar = "SNR_dB";
    yVar = "MetricValue";
elseif any(requiredColumns == "latency_ms") && any(requiredColumns == "cdf_probability")
    xVar = "latency_ms";
    yVar = "cdf_probability";
elseif any(requiredColumns == "Entity") && any(requiredColumns == "PassRate")
    xVar = "Entity";
    yVar = "PassRate";
elseif any(requiredColumns == "CategoryCode") && any(requiredColumns == "MetricCount")
    xVar = "CategoryCode";
    yVar = "MetricCount";
elseif any(requiredColumns == "PAPR_dB") && any(requiredColumns == "CCDF")
    xVar = "PAPR_dB";
    yVar = "CCDF";
elseif any(requiredColumns == "ProcedureDelay_ms")
    xVar = "ProcedureDelay_ms";
    yVar = "ProcedureDelay_ms";
elseif any(requiredColumns == "successful_bits") && any(requiredColumns == "energy_j")
    xVar = "successful_bits";
    yVar = "energy_j";
elseif any(requiredColumns == "DecoderComplexityUnits") && any(requiredColumns == "PostEqSINR_dB")
    xVar = "DecoderComplexityUnits";
    yVar = "PostEqSINR_dB";
elseif any(requiredColumns == "Feature") && any(requiredColumns == "KPIValue")
    xVar = "Feature";
    yVar = "KPIValue";
elseif any(requiredColumns == "timestamp_sim_ms") && any(requiredColumns == "cumulative_energy_J")
    xVar = "timestamp_sim_ms";
    yVar = "cumulative_energy_J";
elseif numel(requiredColumns) >= 2
    xVar = requiredColumns(1);
    yVar = requiredColumns(2);
elseif numel(requiredColumns) == 1
    xVar = requiredColumns(1);
    yVar = requiredColumns(1);
end
end
