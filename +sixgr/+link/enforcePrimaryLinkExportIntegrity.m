function [kpiOut, meta] = enforcePrimaryLinkExportIntegrity(cfg, kpiIn, rawTrials)
%ENFORCEPRIMARYLINKEXPORTINTEGRITY Keep primary link exports free of sidecar data.

arguments
    cfg struct
    kpiIn table
    rawTrials struct = struct()
end

kpiOut = kpiIn;
meta = struct();

if ~istable(kpiOut)
    error("sixgr:link:PrimarySummaryBadType", "kpiIn must be a table.");
end

if isempty(kpiOut)
    return;
end

reqModel = localResolveRequestedChannelModel(cfg);
kpiOut = localEnsureKPIColumns(kpiOut);
localValidateSummaryCoverage(kpiOut);
localValidateSummaryNotes(kpiOut);

caseSpecs = [ ...
    struct("Case", "CellSearch_MIB_SIB1", "Field", "PBCH"); ...
    struct("Case", "PRACH_Detection", "Field", "PRACH"); ...
    struct("Case", "DL_PDSCH_Throughput", "Field", "DL"); ...
    struct("Case", "UL_PUSCH_Throughput", "Field", "UL"); ...
    struct("Case", "UL_SRS_ChannelEst", "Field", "SRS")];

for i = 1:numel(caseSpecs)
    spec = caseSpecs(i);
    T = localResolveTrialTable(rawTrials, spec.Field);
    stats = localTrialStats(T);
    meta.(char(spec.Field)) = stats;

    if isempty(T)
        observedModel = "";
    else
        localValidateTrialNotes(T, spec.Field);
        observedModel = localValidateTrialChannelModels(T, reqModel, spec.Field);
    end

    rowMask = strcmpi(string(kpiOut.Case), spec.Case);
    if ~any(rowMask)
        continue;
    end

    kpiOut = localAssignOrValidateNumericColumn(kpiOut, "TrialCount", rowMask, stats.rows, ...
        "sixgr:link:PrimarySummaryCountMismatch", ...
        "%s primary summary TrialCount disagrees with raw primary trials.", spec.Case);
    kpiOut = localAssignOrValidateNumericColumn(kpiOut, "PassCount", rowMask, stats.pass, ...
        "sixgr:link:PrimarySummaryCountMismatch", ...
        "%s primary summary PassCount disagrees with raw primary trials.", spec.Case);
    kpiOut = localAssignOrValidateNumericColumn(kpiOut, "FailCount", rowMask, stats.fail, ...
        "sixgr:link:PrimarySummaryCountMismatch", ...
        "%s primary summary FailCount disagrees with raw primary trials.", spec.Case);
    kpiOut = localAssignOrValidateNumericColumn(kpiOut, "CrashCount", rowMask, stats.crash, ...
        "sixgr:link:PrimarySummaryCountMismatch", ...
        "%s primary summary CrashCount disagrees with raw primary trials.", spec.Case);
    kpiOut = localAssignOrValidateStringColumn(kpiOut, "RequestedChannelModel", rowMask, reqModel, ...
        "sixgr:link:PrimarySummaryChannelModelMismatch", ...
        "%s primary summary RequestedChannelModel disagrees with the requested channel model.", spec.Case);
    kpiOut = localAssignOrValidateStringColumn(kpiOut, "ObservedChannelModel", rowMask, observedModel, ...
        "sixgr:link:PrimarySummaryChannelModelMismatch", ...
        "%s primary summary ObservedChannelModel disagrees with raw primary trials.", spec.Case);
    kpiOut = localAssignOrValidateLogicalColumn(kpiOut, "FallbackUsed", rowMask, false, ...
        "sixgr:link:PrimarySummaryFallbackMismatch", ...
        "%s primary summary marks fallback data inside the primary table.", spec.Case);
end
end

function T = localResolveTrialTable(rawTrials, fieldName)
T = table();
if ~(isstruct(rawTrials) && isscalar(rawTrials) && isfield(rawTrials, char(fieldName)))
    return;
end

v = rawTrials.(char(fieldName));
if istable(v)
    T = v;
    return;
end

if isstring(v) || ischar(v)
    p = char(string(v));
    if exist(p, "file") == 2
        T = sixgr.util.csvReadTable(p);
    end
    return;
end

if isstruct(v) && isscalar(v)
    if isfield(v, "Table") && istable(v.Table)
        T = v.Table;
        return;
    end
    if isfield(v, "Path") || isfield(v, "File")
        p = string("");
        if isfield(v, "Path")
            p = string(v.Path);
        else
            p = string(v.File);
        end
        if strlength(p) > 0 && exist(char(p), "file") == 2
            T = sixgr.util.csvReadTable(p);
        end
    end
end
end

function stats = localTrialStats(T)
stats = struct("rows", 0, "pass", 0, "fail", 0, "crash", 0);
if ~(istable(T) && ~isempty(T))
    return;
end

if ismember("IsWarmupFrame", string(T.Properties.VariableNames))
    warmMask = logical(T.IsWarmupFrame);
    if any(~warmMask)
        T = T(~warmMask, :);
    end
end

if isempty(T)
    return;
end

stats.rows = height(T);
if ismember("Status", string(T.Properties.VariableNames))
    s = upper(strtrim(string(T.Status)));
    stats.pass = sum(s == "PASS");
    stats.fail = sum(s == "FAIL");
    stats.crash = sum(s == "CRASH");
    return;
end

if ismember("Crash", string(T.Properties.VariableNames))
    c = logical(T.Crash);
    stats.crash = sum(c);
    stats.fail = stats.rows - stats.crash;
end
end

function localValidateSummaryCoverage(kpiTable)
if ismember("Skipped", string(kpiTable.Properties.VariableNames)) && any(logical(kpiTable.Skipped))
    error("sixgr:link:PrimarySummarySkipped", ...
        "Primary link KPI summary contains skipped rows and cannot represent completed coverage.");
end
end

function localValidateSummaryNotes(kpiTable)
if ~ismember("Notes", string(kpiTable.Properties.VariableNames))
    return;
end

notes = string(kpiTable.Notes);
if any(localContainsNonPrimaryMarker(notes))
    error("sixgr:link:PrimarySummaryContainsNonPrimaryNote", ...
        "Primary link KPI summary contains proxy/fallback/debug/synthetic notes.");
end
end

function localValidateTrialNotes(T, fieldName)
if ~ismember("Notes", string(T.Properties.VariableNames))
    return;
end

notes = string(T.Notes);
if any(localContainsSidecarMarker(notes))
    error("sixgr:link:PrimaryTrialContainsFallbackNote", ...
        "%s primary trial table contains fallback/debug/rescue notes.", fieldName);
end
end

function observedModel = localValidateTrialChannelModels(T, reqModel, fieldName)
observedModel = "";
if ~ismember("ChannelModel", string(T.Properties.VariableNames))
    return;
end

obs = localNormalizeChannelModel(string(T.ChannelModel));
obs = unique(obs(strlength(obs) > 0));
if isempty(obs)
    return;
end

if numel(obs) ~= 1
    error("sixgr:link:PrimaryTrialChannelModelMismatch", ...
        "%s primary trial table contains multiple channel models.", fieldName);
end

observedModel = obs(1);
if strlength(reqModel) > 0 && observedModel ~= reqModel
    error("sixgr:link:PrimaryTrialChannelModelMismatch", ...
        "%s primary trial table channel model %s does not match requested %s.", ...
        fieldName, observedModel, reqModel);
end
end

function mask = localContainsSidecarMarker(s)
s = lower(string(s));
mask = contains(s, "fallback") | contains(s, "debug_") | contains(s, "rescue_");
end

function mask = localContainsNonPrimaryMarker(s)
s = lower(string(s));
mask = startsWith(strtrim(s), "skipped:") ...
    | contains(s, "fallback") ...
    | contains(s, "debug_") ...
    | contains(s, "rescue_") ...
    | contains(s, "proxy") ...
    | contains(s, "synthetic") ...
    | contains(s, "abstraction");
end

function T = localEnsureKPIColumns(T)
numCols = ["TrialCount","PassCount","FailCount","CrashCount"];
for i = 1:numel(numCols)
    name = numCols(i);
    if ~ismember(name, string(T.Properties.VariableNames))
        T.(char(name)) = NaN(height(T), 1);
    end
end

strCols = ["RequestedChannelModel","ObservedChannelModel"];
for i = 1:numel(strCols)
    name = strCols(i);
    if ~ismember(name, string(T.Properties.VariableNames))
        T.(char(name)) = strings(height(T), 1);
    end
end

if ~ismember("FallbackUsed", string(T.Properties.VariableNames))
    T.FallbackUsed = false(height(T), 1);
end
end

function T = localAssignOrValidateNumericColumn(T, name, mask, value, errId, msg, caseName)
current = double(T.(char(name))(mask));
if any(isfinite(current) & (current ~= double(value)))
    error(errId, msg, caseName);
end
T.(char(name))(mask) = double(value);
end

function T = localAssignOrValidateStringColumn(T, name, mask, value, errId, msg, caseName)
current = strtrim(string(T.(char(name))(mask)));
value = strtrim(string(value));
if any(strlength(current) > 0 & current ~= value)
    error(errId, msg, caseName);
end
T.(char(name))(mask) = value;
end

function T = localAssignOrValidateLogicalColumn(T, name, mask, value, errId, msg, caseName)
current = logical(T.(char(name))(mask));
if any(current ~= logical(value))
    error(errId, msg, caseName);
end
T.(char(name))(mask) = logical(value);
end

function model = localResolveRequestedChannelModel(cfg)
model = localNormalizeChannelModel(string(sixgr.util.structGet(cfg, "channel.model", "AWGN")));
if strlength(model) == 0
    model = "AWGN";
end

if model == "TDL"
    prof = localNormalizeChannelModel(string(sixgr.util.structGet(cfg, "channel.tdlProfile", ...
        sixgr.util.structGet(cfg, "channel.fading.profile", ""))));
    if strlength(prof) > 0
        model = prof;
    end
elseif model == "CDL"
    prof = localNormalizeChannelModel(string(sixgr.util.structGet(cfg, "channel.cdlProfile", ...
        sixgr.util.structGet(cfg, "channel.fading.profile", ""))));
    if strlength(prof) > 0
        model = prof;
    end
end
end

function model = localNormalizeChannelModel(model)
model = upper(strtrim(string(model)));
model(model == "NONE" | model == "OFF") = "AWGN";
end
