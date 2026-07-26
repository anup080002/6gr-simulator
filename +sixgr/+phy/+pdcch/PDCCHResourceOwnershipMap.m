classdef PDCCHResourceOwnershipMap
    %PDCCHRESOURCEOWNERSHIPMAP Explicit data/DM-RS ownership for every REG.

    methods (Static)
        function result = build(definition)
            if ~isa(definition, "sixgr.phy.pdcch.CORESETDefinition")
                definition = sixgr.phy.pdcch.CORESETDefinition(definition);
            end
            mapping = sixgr.phy.pdcch.CORESETMapper.map(definition);
            nRows = definition.Data.NREG * 12;
            rows = repmat(localRow(), nRows, 1);
            dmrsOffsets = [1 5 9];
            cursor = 1;
            for cce = 0:definition.Data.NCCE-1
                regs = mapping.Rows(cce+1).REGIndexVector;
                for reg = regs
                    [symbol, prb] = sixgr.phy.pdcch.CORESETMapper.regCoordinates(reg, definition);
                    for subcarrier = 0:11
                        row = localRow();
                        row.Slot = 0;
                        row.Symbol = symbol;
                        row.PRB = prb;
                        row.Subcarrier = subcarrier;
                        row.REGIndex = reg;
                        row.CCEIndex = cce;
                        if ismember(subcarrier, dmrsOffsets)
                            row.Owner = "PDCCH_DMRS";
                            row.DMRSPort = 0;
                        else
                            row.Owner = "PDCCH_DATA";
                            row.DMRSPort = NaN;
                        end
                        row.CollisionCount = 0;
                        row.Status = "PASS";
                        rows(cursor) = row;
                        cursor = cursor + 1;
                    end
                end
            end
            coordinates = strcat(string([rows.Symbol].'), ":", string([rows.PRB].'), ...
                ":", string([rows.Subcarrier].'));
            if numel(unique(coordinates)) ~= numel(rows)
                error("sixgr:phy:pdcch:coreset_reg_collision", ...
                    "PDCCH resource ownership contains duplicate RE coordinates.");
            end
            result = struct("Rows", rows, ...
                "Table", struct2table(rows, "AsArray", true), ...
                "DataRECount", sum(string({rows.Owner}) == "PDCCH_DATA"), ...
                "DMRSRECount", sum(string({rows.Owner}) == "PDCCH_DMRS"), ...
                "CollisionCount", 0, "Status", "PASS");
        end
    end
end

function row = localRow()
row = struct("Slot", NaN, "Symbol", NaN, "PRB", NaN, ...
    "Subcarrier", NaN, "REGIndex", NaN, "CCEIndex", NaN, ...
    "Owner", "", "DMRSPort", NaN, "CollisionCount", NaN, "Status", "");
end
