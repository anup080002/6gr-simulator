function [alloc, overlapT] = MRSSCoordinator(cfg, alloc, varargin)
%MRSSCoordinator NW-side only resource sharing hook for 5G/6G PDSCH.

mode = string(sixgr.util.structGet(cfg.MRSS, "Mode", "exclusive_6gr"));
mask = double(sixgr.util.structGet(cfg.MRSS, "ExternalOccupancyMask", []));
overlapT = table();
if ~logical(sixgr.util.structGet(cfg.MRSS, "Enabled", false)) || mode == "exclusive_6gr"
    return;
end

overlap = intersect(double(alloc.PRBSet(:).'), unique(mask));
if isempty(overlap)
    overlapT = table(string(mode), 0, "VariableNames", {"MRSSMode","OverlapCount"});
    return;
end

alloc.PRBSet = setdiff(double(alloc.PRBSet(:).'), overlap, "stable");
alloc.NumRB = numel(alloc.PRBSet);
if isempty(alloc.PRBSet)
    error("sixgr:pdsch:MRSSCoordinator:NoResourcesRemaining", ...
        "MRSS removed all scheduled PRBs for the 6GR allocation.");
end
alloc.RBStart = min(alloc.PRBSet);
overlapT = table(repmat(string(mode), numel(overlap), 1), double(overlap(:)), ...
    "VariableNames", {"MRSSMode","OverlappedPRB"});
end
