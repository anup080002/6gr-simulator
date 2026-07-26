classdef MonitoringOccasionResolver
    %MONITORINGOCCASIONRESOLVER Derive every configured slot/symbol occasion.

    methods (Static)
        function result = resolve(searchSpace, windowSlots)
            if ~isa(searchSpace, "sixgr.phy.pdcch.SearchSpaceDefinition")
                searchSpace = sixgr.phy.pdcch.SearchSpaceDefinition(searchSpace);
            end
            windowSlots = double(windowSlots);
            if ~(isscalar(windowSlots) && isfinite(windowSlots) && ...
                    windowSlots >= 1 && windowSlots == fix(windowSlots))
                error("sixgr:phy:pdcch:invalid_search_space_periodicity", ...
                    "WindowSlots must be a positive integer.");
            end
            data = searchSpace.Data;
            rows = repmat(localRow(), 0, 1);
            symbols = find(data.MonitoringSymbolsWithinSlot) - 1;
            for slot = 0:windowSlots-1
                relative = mod(slot - data.OffsetSlots, data.PeriodSlots);
                monitored = slot >= data.OffsetSlots && relative < data.DurationSlots;
                if ~monitored
                    continue;
                end
                row = localRow();
                row.AbsoluteSlot = slot;
                row.MonitoringOccasion = true;
                row.MonitoringSymbols = join(string(symbols), "|");
                row.MonitoringSymbolVector = symbols;
                row.Status = "PASS";
                rows(end+1,1) = row; %#ok<AGROW>
            end
            result = struct("Rows", rows, ...
                "Table", struct2table(rmfield(rows, "MonitoringSymbolVector"), "AsArray", true), ...
                "MonitoredSlots", [rows.AbsoluteSlot], ...
                "MonitoredSlotCount", numel(rows), ...
                "Status", "PASS");
        end
    end
end

function row = localRow()
row = struct("AbsoluteSlot", NaN, "MonitoringOccasion", false, ...
    "MonitoringSymbols", "", "MonitoringSymbolVector", [], "Status", "");
end
