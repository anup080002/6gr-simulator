function raw = loadDirectionRawTables(details, varargin)
%LOADDIRECTIONRAWTABLES Resolve raw DL/UL KPI source rows without direction inference.

ip = inputParser;
ip.addParameter("RunFolder", "", @(x) ischar(x) || isstring(x));
ip.addParameter("PreferPersistedPrimary", false, ...
    @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
ip.parse(varargin{:});
runFolder = string(ip.Results.RunFolder);
preferPersistedPrimary = logical(ip.Results.PreferPersistedPrimary);

raw = struct();
raw.DL = table();
raw.UL = table();
raw.PacketSDU = table();
raw.ApplicationPackets = table();
raw.HARQTimeline = table();
raw.DLGrants = table();
raw.ULGrants = table();
raw.SlotTrace = table();
raw.GridNumRBs = NaN;
raw.NumResourceCells = NaN;
raw.SymbolsPerSlot = NaN;
raw.PrimarySourceReconciliation = table();
raw.Paths = struct("DL", "", "UL", "", "PacketSDU", "", ...
    "ApplicationPackets", "", "HARQTimeline", "", ...
    "DLGrants", "", "ULGrants", "", "SlotTrace", "");

if isstruct(details)
    rt = sixgr.util.structGet(details, "RawTrials", struct());
    if isstruct(rt)
        [raw.DL, raw.Paths.DL] = localResolveTable(sixgr.util.structGet(rt, "DL", table()), "air_interface/csv/dl_pdsch_trials.csv");
        [raw.UL, raw.Paths.UL] = localResolveTable(sixgr.util.structGet(rt, "UL", table()), "air_interface/csv/ul_pusch_trials.csv");
        raw.Paths.DL = localRuntimeTrialPath(raw.DL, "DL", raw.Paths.DL);
        raw.Paths.UL = localRuntimeTrialPath(raw.UL, "UL", raw.Paths.UL);
        [raw.PacketSDU, raw.Paths.PacketSDU] = localResolveTable(sixgr.util.structGet(rt, "PacketSDU", table()), "packet_flow/csv/live_packet_sdu_delivery_ledger.csv");
        [raw.ApplicationPackets, raw.Paths.ApplicationPackets] = localResolveTable(sixgr.util.structGet(rt, "ApplicationPackets", table()), "packet_flow/csv/live_application_packet_delivery_ledger.csv");
        [raw.HARQTimeline, raw.Paths.HARQTimeline] = localResolveTable(sixgr.util.structGet(rt, "HARQTimeline", table()), "harq/csv/live_harq_observation_timeline.csv");
        [raw.DLGrants, raw.Paths.DLGrants] = localResolveTable(sixgr.util.structGet(rt, "DLGrants", table()), "packet_flow/csv/live_dl_scheduler_grants.csv");
        [raw.ULGrants, raw.Paths.ULGrants] = localResolveTable(sixgr.util.structGet(rt, "ULGrants", table()), "packet_flow/csv/live_ul_scheduler_grants.csv");
        [raw.SlotTrace, raw.Paths.SlotTrace] = localResolveTable(sixgr.util.structGet(rt, "SlotTrace", table()), "packet_flow/csv/slot_trace.csv");
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
    if isempty(raw.HARQTimeline)
        [raw.HARQTimeline, raw.Paths.HARQTimeline] = localResolveTable( ...
            sixgr.util.structGet(details, "HARQTimelineTable", ...
            sixgr.util.structGet(details, "LiveDerived.HARQ.TimelineTable", table())), ...
            "harq/csv/live_harq_observation_timeline.csv");
    end
    if isempty(raw.DLGrants)
        [raw.DLGrants, raw.Paths.DLGrants] = localResolveTable( ...
            sixgr.util.structGet(details, "DLGrantTraceTable", ...
            sixgr.util.structGet(details, "DLGrantTable", table())), ...
            "packet_flow/csv/live_dl_scheduler_grants.csv");
    end
    if isempty(raw.ULGrants)
        [raw.ULGrants, raw.Paths.ULGrants] = localResolveTable( ...
            sixgr.util.structGet(details, "ULGrantTraceTable", ...
            sixgr.util.structGet(details, "ULGrantTable", table())), ...
            "packet_flow/csv/live_ul_scheduler_grants.csv");
    end
    if isempty(raw.SlotTrace)
        [raw.SlotTrace, raw.Paths.SlotTrace] = localResolveTable( ...
            sixgr.util.structGet(details, "SlotTraceTable", table()), ...
            "packet_flow/csv/slot_trace.csv");
    end
    cfg = sixgr.util.structGet(details, "Config", struct());
    if isstruct(cfg)
        raw.GridNumRBs = localFirstFiniteScalar(cfg, [ ...
            "phy.numerology.activeGridNumRBs", "phy.carrier.NSizeGrid"]);
        raw.NumResourceCells = localFirstFiniteScalar(cfg, [ ...
            "scenario.layout.nCells", "deployment_topology.num_cells"]);
        raw.SymbolsPerSlot = localResolveSymbolsPerSlot(cfg);
    end
end

if strlength(runFolder) > 0
    if isempty(raw.DL)
        p = localCandidatePath(runFolder, "air_interface/csv/dl_pdsch_trials.csv", "csv/dl_pdsch_trials.csv", ...
            "air_interface/csv/dl_fixed_link_campaign_trials.csv");
        [raw.DL, raw.Paths.DL] = localResolveTable(p, string(p));
    end
    if isempty(raw.UL)
        p = localCandidatePath(runFolder, "air_interface/csv/ul_pusch_trials.csv", "csv/ul_pusch_trials.csv", ...
            "air_interface/csv/ul_fixed_link_campaign_trials.csv");
        [raw.UL, raw.Paths.UL] = localResolveTable(p, string(p));
    end
    if isempty(raw.PacketSDU)
        p = localCandidatePath(runFolder, "packet_flow/csv/live_packet_sdu_delivery_ledger.csv", "reports/csv/kpi_packet_sdu_delivery_ledger.csv");
        [raw.PacketSDU, raw.Paths.PacketSDU] = localResolveTable(p, string(p));
    end
    if isempty(raw.ApplicationPackets)
        p = localCandidatePath(runFolder, "packet_flow/csv/live_application_packet_delivery_ledger.csv", "reports/csv/kpi_application_packet_delivery_ledger.csv");
        [raw.ApplicationPackets, raw.Paths.ApplicationPackets] = localResolveTable(p, string(p));
    end
    if isempty(raw.HARQTimeline)
        p = localCandidatePath(runFolder, "harq/csv/live_harq_observation_timeline.csv", "reports/csv/live_harq_timeline.csv");
        [raw.HARQTimeline, raw.Paths.HARQTimeline] = localResolveTable(p, string(p));
    end
    if isempty(raw.DLGrants)
        p = localCandidatePath(runFolder, "packet_flow/csv/live_dl_scheduler_grants.csv", "reports/csv/live_dl_scheduler_grants.csv");
        [raw.DLGrants, raw.Paths.DLGrants] = localResolveTable(p, string(p));
    end
    if isempty(raw.ULGrants)
        p = localCandidatePath(runFolder, "packet_flow/csv/live_ul_scheduler_grants.csv", "reports/csv/live_ul_scheduler_grants.csv");
        [raw.ULGrants, raw.Paths.ULGrants] = localResolveTable(p, string(p));
    end
    if isempty(raw.SlotTrace)
        p = localCandidatePath(runFolder, "packet_flow/csv/slot_trace.csv", "reports/csv/slot_trace.csv");
        [raw.SlotTrace, raw.Paths.SlotTrace] = localResolveTable(p, string(p));
    end

    if preferPersistedPrimary
        [raw.DL, raw.Paths.DL, dlAudit] = localSelectPersistedPrimary( ...
            raw.DL, raw.Paths.DL, runFolder, "DL", ...
            "air_interface/csv/dl_pdsch_trials.csv");
        [raw.UL, raw.Paths.UL, ulAudit] = localSelectPersistedPrimary( ...
            raw.UL, raw.Paths.UL, runFolder, "UL", ...
            "air_interface/csv/ul_pusch_trials.csv");
        raw.PrimarySourceReconciliation = [dlAudit; ulAudit];
    end
end
end

function [selected, selectedPath, auditT] = localSelectPersistedPrimary( ...
        inMemory, inMemoryPath, runFolder, direction, relativePath)
% Final reducers must consume the canonical rows already published for the
% run.  Live callbacks can retain an earlier, narrower table schema while
% the persisted primary table has subsequently been finalized.  Selecting
% that stale table loses real runtime fields and is not a valid fallback.
selected = inMemory;
selectedPath = string(inMemoryPath);
persistedPath = fullfile(char(runFolder), char(relativePath));
persisted = table();
if isfile(persistedPath)
    persisted = sixgr.util.csvReadTable(persistedPath);
end

memoryRows = localHeight(inMemory);
persistedRows = localHeight(persisted);
memoryHash = localTableHash(inMemory);
persistedHash = localTableHash(persisted);
status = "in_memory_only";

if persistedRows > 0
    if memoryRows > 0 && memoryRows ~= persistedRows
        error("sixgr:kpi:PersistedPrimaryRowCountMismatch", ...
            ["Canonical %s primary rows (%d) disagree with the in-memory " ...
             "runtime snapshot (%d). Refusing to reduce mismatched evidence."], ...
            char(direction), persistedRows, memoryRows);
    end
    if memoryRows > 0
        localAssertSamePrimaryIdentity(inMemory, persisted, direction);
        if memoryHash == persistedHash
            status = "canonical_persisted_matches_in_memory";
        else
            status = "canonical_persisted_selected_after_schema_finalization";
        end
    else
        status = "canonical_persisted_selected";
    end
    selected = persisted;
    selectedPath = string(relativePath);
end

auditT = table(string(direction), memoryRows, persistedRows, memoryHash, ...
    persistedHash, string(selectedPath), status, ...
    'VariableNames', {'Direction','InMemoryRowCount','PersistedRowCount', ...
    'InMemoryRowsHash','PersistedRowsHash','SelectedSourcePath','Status'});
end

function localAssertSamePrimaryIdentity(inMemory, persisted, direction)
memoryKey = localPrimaryIdentity(inMemory);
persistedKey = localPrimaryIdentity(persisted);
if isempty(memoryKey) || isempty(persistedKey)
    return;
end
if numel(memoryKey) ~= numel(persistedKey) || ...
        ~isequal(sort(memoryKey), sort(persistedKey))
    error("sixgr:kpi:PersistedPrimaryIdentityMismatch", ...
        ["Canonical %s primary trial identities disagree with the in-memory " ...
         "runtime snapshot. Refusing to reduce a different trial set."], ...
        char(direction));
end
end

function key = localPrimaryIdentity(T)
key = strings(0, 1);
if ~(istable(T) && height(T) > 0)
    return;
end
frame = localIdentityColumn(T, ["Frame","SFN"]);
slot = localIdentityColumn(T, ["Slot","AbsoluteSlot"]);
ue = localIdentityColumn(T, ["UEID","UEId","UEIndex"]);
if isempty(frame) || isempty(slot) || isempty(ue) || ...
        any(~isfinite(frame)) || any(~isfinite(slot)) || any(~isfinite(ue))
    return;
end
key = "frame=" + string(frame) + "|slot=" + string(slot) + ...
    "|ue=" + string(ue);
end

function value = localIdentityColumn(T, candidates)
value = [];
vars = string(T.Properties.VariableNames);
for candidate = string(candidates)
    if ismember(candidate, vars)
        try
            value = double(T.(candidate));
        catch
            value = str2double(string(T.(candidate)));
        end
        value = value(:);
        return;
    end
end
end

function n = localHeight(T)
n = 0;
if istable(T)
    n = height(T);
end
end

function hash = localTableHash(T)
hash = "empty";
if istable(T) && height(T) > 0
    hash = string(sixgr.kpi.hashKPISourceRows(T));
end
end

function value = localResolveSymbolsPerSlot(cfg)
value = localFirstFiniteScalar(cfg, [ ...
    "phy.numerology.symbolsPerSlot", "frame_timing.symbols_per_slot"]);
if isfinite(value)
    return;
end
try
    [~, numerology] = sixgr.time.slotDurationSec(cfg);
    value = double(numerology.SymbolsPerSlot);
catch
    value = NaN;
end
end

function value = localFirstFiniteScalar(cfg, paths)
value = NaN;
for i = 1:numel(paths)
    candidate = double(sixgr.util.structGet(cfg, char(paths(i)), NaN));
    if isscalar(candidate) && isfinite(candidate) && candidate > 0
        value = candidate;
        return;
    end
end
end

function p = localCandidatePath(runFolder, canonicalRel, localRel, fallbackRel)
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
if nargin >= 4 && strlength(strtrim(string(fallbackRel))) > 0
    pFallback = fullfile(runFolder, char(string(fallbackRel)));
    if exist(pFallback, "file") == 2
        p = pFallback;
        return;
    end
end
parent = fileparts(runFolder);
if strlength(string(parent)) > 0
    pParent = fullfile(parent, canonicalRel);
    if exist(pParent, "file") == 2
        p = pParent;
    end
end
end

function path = localRuntimeTrialPath(T, direction, currentPath)
% The source manifest must name the table that actually owns the rows.  A
% fixed-link campaign persists its primary trials under versioned fixed-link
% filenames; describing those in-memory rows as ordinary connected-run
% dl_pdsch/ul_pusch files produces a manifest path that does not exist and
% cannot be independently hashed.
path = string(currentPath);
if ~(istable(T) && height(T) > 0 && ...
        ismember("FixedLinkCampaign", string(T.Properties.VariableNames)))
    return;
end
raw = T.FixedLinkCampaign;
if islogical(raw) || isnumeric(raw)
    fixed = isfinite(double(raw)) & double(raw) ~= 0;
else
    token = lower(strtrim(string(raw)));
    fixed = ismember(token, ["1","true","yes","on","enabled"]);
end
if numel(fixed) ~= height(T) || ~all(fixed)
    return;
end
if upper(string(direction)) == "DL"
    path = "air_interface/csv/dl_fixed_link_campaign_trials.csv";
else
    path = "air_interface/csv/ul_fixed_link_campaign_trials.csv";
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
        T = sixgr.util.csvReadTable(path);
    end
end
end
