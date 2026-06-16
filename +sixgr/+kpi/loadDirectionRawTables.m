function raw = loadDirectionRawTables(details, varargin)
%LOADDIRECTIONRAWTABLES Resolve raw DL/UL KPI source rows without direction inference.

ip = inputParser;
ip.addParameter("RunFolder", "", @(x) ischar(x) || isstring(x));
ip.parse(varargin{:});
runFolder = string(ip.Results.RunFolder);

raw = struct();
raw.DL = table();
raw.UL = table();
raw.Paths = struct("DL", "", "UL", "");

if isstruct(details)
    rt = sixgr.util.structGet(details, "RawTrials", struct());
    if isstruct(rt)
        [raw.DL, raw.Paths.DL] = localResolveTable(sixgr.util.structGet(rt, "DL", table()), "air_interface/csv/dl_pdsch_trials.csv");
        [raw.UL, raw.Paths.UL] = localResolveTable(sixgr.util.structGet(rt, "UL", table()), "air_interface/csv/ul_pusch_trials.csv");
    end

    if isempty(raw.DL)
        cases = sixgr.util.structGet(details, "Cases", struct());
        if isstruct(cases)
            dlCase = sixgr.util.structGet(cases, "DL_PDSCH_Throughput", struct());
            [raw.DL, raw.Paths.DL] = localResolveTable(sixgr.util.structGet(dlCase, "TrialTable", table()), "details.Cases.DL_PDSCH_Throughput.TrialTable");
        end
    end
    if isempty(raw.UL)
        cases = sixgr.util.structGet(details, "Cases", struct());
        if isstruct(cases)
            ulCase = sixgr.util.structGet(cases, "UL_PUSCH_Throughput", struct());
            [raw.UL, raw.Paths.UL] = localResolveTable(sixgr.util.structGet(ulCase, "TrialTable", table()), "details.Cases.UL_PUSCH_Throughput.TrialTable");
        end
    end
end

if strlength(runFolder) > 0
    if isempty(raw.DL)
        p = localCandidatePath(runFolder, "air_interface/csv/dl_pdsch_trials.csv", "csv/dl_pdsch_trials.csv");
        [raw.DL, raw.Paths.DL] = localResolveTable(p, string(p));
    end
    if isempty(raw.UL)
        p = localCandidatePath(runFolder, "air_interface/csv/ul_pusch_trials.csv", "csv/ul_pusch_trials.csv");
        [raw.UL, raw.Paths.UL] = localResolveTable(p, string(p));
    end
end
end

function p = localCandidatePath(runFolder, canonicalRel, localRel)
runFolder = char(string(runFolder));
p = fullfile(runFolder, canonicalRel);
if exist(p, "file") == 2
    return;
end
pLocal = fullfile(runFolder, localRel);
if exist(pLocal, "file") == 2
    p = pLocal;
    return;
end
parent = fileparts(runFolder);
if strlength(string(parent)) > 0
    pParent = fullfile(parent, canonicalRel);
    if exist(pParent, "file") == 2
        p = pParent;
    end
end
end

function [T, path] = localResolveTable(value, defaultPath)
T = table();
path = string(defaultPath);
if istable(value)
    T = value;
    return;
end
if isstruct(value) && isscalar(value)
    if isfield(value, "Table") && istable(value.Table)
        T = value.Table;
    end
    if isfield(value, "Path")
        path = string(value.Path);
    elseif isfield(value, "File")
        path = string(value.File);
    end
    if ~isempty(T)
        return;
    end
end
if ischar(value) || (isstring(value) && isscalar(value))
    path = string(value);
    if strlength(path) > 0 && exist(char(path), "file") == 2
        T = readtable(char(path), "VariableNamingRule", "preserve");
    end
end
end
