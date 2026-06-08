function ss = SearchSpaceConfig(raw, ctrlCfg, coreset)
%SearchSpaceConfig Resolve a CSS or USS definition for the 6GR study chain.

if nargin < 1 || isempty(raw)
    raw = struct();
end

ss = struct();
ss.SearchSpaceID = double(sixgr.util.structGet(raw, "SearchSpaceID", 1));
ss.SearchSpaceType = upper(string(sixgr.util.structGet(raw, "SearchSpaceType", "CSS")));
ss.AssociatedCORESETID = double(sixgr.util.structGet(raw, "AssociatedCORESETID", coreset.CORESETID));
ss.MonitoringSymbolsWithinSlot = double(sixgr.util.structGet(raw, "MonitoringSymbolsWithinSlot", coreset.StartSymbol + (0:coreset.DurationSymbols-1)));
ss.MonitoringSlotsPeriodicity = max(1, round(double(sixgr.util.structGet(raw, "MonitoringSlotsPeriodicity", ctrlCfg.MonitoringPeriodicitySlots))));
ss.MonitoringSlotOffset = max(0, round(double(sixgr.util.structGet(raw, "MonitoringSlotOffset", 0))));
ss.CandidateCountPerAL = localResolveCandidateMap(sixgr.util.structGet(raw, "CandidateCountPerAL", struct("AL1", 8, "AL2", 4, "AL4", 2, "AL8", 1, "AL16", 1)));
ss.AggregationLevels = unique(round(double(sixgr.util.structGet(raw, "AggregationLevels", [1 2 4 8 16]))));
ss.HashFunctionMode = char(string(sixgr.util.structGet(raw, "HashFunctionMode", "baseline_hash")));
ss.EnableSlotLevelMonitoring = logical(sixgr.util.structGet(raw, "EnableSlotLevelMonitoring", true));
ss.EnableNonSlotMonitoringStudy = logical(sixgr.util.structGet(raw, "EnableNonSlotMonitoringStudy", false));
ss.UETransparentToMRSS = logical(sixgr.util.structGet(raw, "UETransparentToMRSS", true));
ss.StudyLabel = "study_item_candidate";

if ~ismember(ss.SearchSpaceType, ["CSS","USS"])
    error("sixgr:ctrl:SearchSpaceConfig:BadType", ...
        "SearchSpaceType must be CSS or USS.");
end
if ss.AssociatedCORESETID ~= coreset.CORESETID
    error("sixgr:ctrl:SearchSpaceConfig:CORESETMismatch", ...
        "Search space %d points to CORESET %d, but the active CORESET is %d.", ...
        ss.SearchSpaceID, ss.AssociatedCORESETID, coreset.CORESETID);
end
if any(~ismember(ss.AggregationLevels, [1 2 4 8 16 32]))
    error("sixgr:ctrl:SearchSpaceConfig:BadAL", ...
        "AggregationLevels must be chosen from {1,2,4,8,16,32}.");
end
validPeriods = [1 2 4 5 8 10 16 20 40 80 160 320 640 1280 2560];
if ~any(ss.MonitoringSlotsPeriodicity == validPeriods)
    warning("sixgr:ctrl:SearchSpaceConfig:InvalidPeriodicity", ...
        "MonitoringSlotsPeriodicity=%d is not a standard NR monitoring periodicity.", ss.MonitoringSlotsPeriodicity);
end
end

function out = localResolveCandidateMap(raw)
out = struct("AL1", 0, "AL2", 0, "AL4", 0, "AL8", 0, "AL16", 0, "AL32", 0);
if isnumeric(raw)
    vec = double(raw(:).');
    keys = ["AL1","AL2","AL4","AL8","AL16","AL32"];
    for i = 1:min(numel(vec), numel(keys))
        out.(keys(i)) = max(0, round(vec(i)));
    end
elseif isstruct(raw)
    fn = fieldnames(out);
    for i = 1:numel(fn)
        out.(fn{i}) = max(0, round(double(sixgr.util.structGet(raw, fn{i}, out.(fn{i})))));
    end
else
    error("sixgr:ctrl:SearchSpaceConfig:BadCandidateMap", ...
        "CandidateCountPerAL must be a struct or numeric vector.");
end
end
