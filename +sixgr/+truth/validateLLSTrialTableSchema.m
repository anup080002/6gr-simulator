function report = validateLLSTrialTableSchema(T, varargin)
%VALIDATELLSTRIALTABLESCHEMA Validate canonical LLS trace schema expectations.

ip = inputParser;
ip.addParameter("RequireHARQ", false, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
ip.addParameter("SourceLabel", "LLS trial table", @(x) ischar(x) || isstring(x));
ip.addParameter("FailOnError", true, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
ip.parse(varargin{:});
opt = ip.Results;

report = struct( ...
    "SourceLabel", char(string(opt.SourceLabel)), ...
    "Valid", true, ...
    "MissingColumns", strings(0, 1), ...
    "Issues", strings(0, 1), ...
    "HasLegacyPRBCountAlias", false, ...
    "HasRankEstimate", false, ...
    "HasRankIndicator", false);

if ~istable(T)
    report.Valid = false;
    report.Issues = "Input is not a table.";
    localMaybeThrow(report, opt.FailOnError);
    return;
end

vars = string(T.Properties.VariableNames);
required = ["Direction","SFN","Frame","Slot","UEID","RNTI","BaseStationID", ...
    "AllocatedPRBCount","PRBStart","MCS","Layers","Rank"];
if logical(opt.RequireHARQ)
    required = [required, "RV", "HARQProcess", "HARQRound", "IsRetransmission"];
end

missing = required(~ismember(required, vars));
if ~isempty(missing)
    report.Valid = false;
    report.MissingColumns = missing(:);
    report.Issues(end+1, 1) = "Missing required columns: " + strjoin(missing, ", ");
end

report.HasLegacyPRBCountAlias = ismember("PRBCount", vars);
report.HasRankEstimate = ismember("RankEstimate", vars);
report.HasRankIndicator = ismember("RankIndicator", vars);

if all(ismember(["AllocatedPRBCount","PRBCount"], vars))
    alloc = double(T.AllocatedPRBCount);
    legacy = double(T.PRBCount);
    mismatch = isfinite(alloc) & isfinite(legacy) & alloc ~= legacy;
    if any(mismatch)
        report.Valid = false;
        report.Issues(end+1, 1) = "AllocatedPRBCount conflicts with legacy PRBCount on one or more rows.";
    end
end

if all(ismember(["Rank","Layers"], vars))
    rankVal = double(T.Rank);
    layerVal = double(T.Layers);
    mismatch = isfinite(rankVal) & isfinite(layerVal) & rankVal ~= layerVal;
    if any(mismatch)
        report.Valid = false;
        report.Issues(end+1, 1) = "Rank must represent transmitted rank and therefore match Layers.";
    end
end

if ismember("Direction", vars)
    dirVal = string(T.Direction);
    bad = ~(dirVal == "DL" | dirVal == "UL" | strlength(dirVal) == 0);
    if any(bad)
        report.Valid = false;
        report.Issues(end+1, 1) = "Direction must be DL or UL for populated rows.";
    end
end

localMaybeThrow(report, opt.FailOnError);
end

function localMaybeThrow(report, failOnError)
if ~logical(failOnError) || logical(report.Valid)
    return;
end
msg = "LLS schema validation failed for " + string(report.SourceLabel);
if ~isempty(report.Issues)
    msg = msg + ": " + strjoin(report.Issues, " | ");
end
error("sixgr:truth:InvalidTrialTableSchema", "%s", char(msg));
end
