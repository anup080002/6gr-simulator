function auditT = validateRawKPITables(raw, varargin)
%VALIDATERAWKPITABLES Audit raw DL/UL KPI source schemas.

ip = inputParser;
ip.addParameter("RunId", "", @(x)ischar(x) || isstring(x) || isnumeric(x));
ip.addParameter("SourcePaths", struct(), @(x)isempty(x) || isstruct(x));
ip.parse(varargin{:});
runId = string(ip.Results.RunId);
sourcePaths = ip.Results.SourcePaths;

dirs = ["UL"; "DL"];
rows = repmat(localRow(), 0, 1);
for d = 1:numel(dirs)
    direction = dirs(d);
    T = table();
    if isstruct(raw) && isfield(raw, char(direction))
        T = raw.(char(direction));
    end
    required = localRequiredColumns(direction);
    vars = string([]);
    if istable(T)
        vars = string(T.Properties.VariableNames);
    end
    for i = 1:numel(required)
        row = localRow();
        row.RunId = runId;
        row.SourceTablePath = localSourcePath(sourcePaths, direction);
        row.SchemaName = "canonical_lls_raw_phy_trial_v1";
        row.Direction = direction;
        row.SourceTableName = localSourceName(direction);
        row.RequiredColumn = required(i);
        [present, chosenColumn] = localColumnPresent(required(i), vars);
        row.Present = istable(T) && present;
        row.TypeValid = row.Present;
        row.RowCount = localHeight(T);
        row.MissingCount = 0;
        row.InvalidCount = 0;
        if row.Present
            col = T.(chosenColumn);
            if required(i) == "Direction"
                values = upper(strtrim(string(col)));
                row.InvalidCount = sum(values ~= direction);
                row.TypeValid = row.InvalidCount == 0;
            else
                row.MissingCount = localMissingCount(col);
            end
        end
        if ~row.Present
            row.Status = "missing_required_column";
            row.FailureReason = "required_column_missing";
        elseif ~row.TypeValid
            row.Status = "invalid";
            row.FailureReason = "direction_mismatch_or_invalid_type";
        else
            row.Status = "pass";
            row.FailureReason = "";
        end
        rows(end+1, 1) = row; %#ok<AGROW>
    end
end
auditT = struct2table(rows);
end

function value = localSourcePath(sourcePaths, direction)
value = "";
if ~(isstruct(sourcePaths) && isscalar(sourcePaths))
    return;
end
fieldName = char(upper(string(direction)));
if isfield(sourcePaths, fieldName)
    value = string(sourcePaths.(fieldName));
end
end

function cols = localRequiredColumns(direction)
if direction == "UL"
    cols = ["Direction","Goodput_Mbps","CRCPass_or_TBCrcPass","BitErrors","BitsCompared"];
else
    cols = ["Direction","Goodput_Mbps","CRCPass_or_TBCrcPass","BitErrors","BitsCompared"];
end
end

function [present, chosen] = localColumnPresent(required, vars)
required = string(required);
chosen = required;
if contains(required, "_or_")
    choices = split(required, "_or_");
    presentMask = ismember(choices, vars);
    present = any(presentMask);
    if present
        chosen = choices(find(presentMask, 1));
    end
else
    present = ismember(required, vars);
end
end

function n = localHeight(T)
if istable(T)
    n = height(T);
else
    n = 0;
end
end

function n = localMissingCount(col)
try
    if isnumeric(col)
        n = sum(~isfinite(double(col)));
    else
        n = sum(strlength(strtrim(string(col))) == 0);
    end
catch
    n = 0;
end
end

function name = localSourceName(direction)
if direction == "UL"
    name = "ul_pusch_trials";
else
    name = "dl_pdsch_trials";
end
end

function row = localRow()
row = struct( ...
    "RunId", "", ...
    "SourceTablePath", "", ...
    "SchemaName", "", ...
    "SourceTableName", "", ...
    "Direction", "", ...
    "RequiredColumn", "", ...
    "Present", false, ...
    "TypeValid", false, ...
    "RowCount", 0, ...
    "MissingCount", 0, ...
    "InvalidCount", 0, ...
    "Status", "not_evaluated", ...
    "FailureReason", "");
end
