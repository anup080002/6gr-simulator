function [coordinated, overlapTable] = MRSSResourceCoordinator(~, coresetCfg, mode)
%MRSSResourceCoordinator Coordinate NW-side 5G/6G control sharing.
%
% The UE-visible CORESET/search space remains 6GR-only. This coordinator
% only mutates the network-side usable RB set and logs overlap events.

if nargin < 3 || strlength(string(mode)) == 0
    mode = "exclusive_6gr";
end

coordinated = coresetCfg;
mode = lower(string(mode));
rows = repmat(struct("MRSSMode", "", "RB", NaN, "OverlapType", "", "Action", ""), 0, 1);

switch mode
    case "exclusive_6gr"
        % No mutation.
    case "shared_dynamic"
        if mod(numel(coordinated.RBList), 2) > 0
            overlapRB = coordinated.RBList(end);
            coordinated.RBList = coordinated.RBList(1:end-1);
            coordinated.NumRB = numel(coordinated.RBList);
            rows(end+1,1) = struct("MRSSMode", "shared_dynamic", "RB", overlapRB, ... %#ok<AGROW>
                "OverlapType", "5g_6g_dynamic_request_overlap", "Action", "temporarily_removed_from_6gr");
        end
    case "semi_static_partitioned"
        if numel(coordinated.RBList) >= 4
            removed = coordinated.RBList(2:2:end);
            coordinated.RBList = coordinated.RBList(1:2:end);
            coordinated.NumRB = numel(coordinated.RBList);
            for i = 1:numel(removed)
                rows(end+1,1) = struct("MRSSMode", "semi_static_partitioned", "RB", removed(i), ... %#ok<AGROW>
                    "OverlapType", "semi_static_5g_partition", "Action", "reserved_for_5g");
            end
        end
    otherwise
        error("sixgr:ctrl:MRSSResourceCoordinator:BadMode", ...
            "MRSS mode must be exclusive_6gr, shared_dynamic, or semi_static_partitioned.");
end

coordinated.MRSSMode = char(mode);
overlapTable = struct2table(rows);
if strcmpi(mode, "exclusive_6gr") && isempty(rows)
    overlapTable = table();
end
end
