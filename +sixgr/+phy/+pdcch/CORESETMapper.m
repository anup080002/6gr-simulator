classdef CORESETMapper
    %CORESETMAPPER Exact zero-based CCE-to-REG mapping.

    methods (Static)
        function result = map(definition)
            if ~isa(definition, "sixgr.phy.pdcch.CORESETDefinition")
                definition = sixgr.phy.pdcch.CORESETDefinition(definition);
            end
            data = definition.Data;
            nBundles = data.NREG / data.REGBundleSize;
            bundlesPerCCE = 6 / data.REGBundleSize;
            rows = repmat(localRow(), data.NCCE, 1);
            used = zeros(data.NREG, 1);
            for cce = 0:data.NCCE-1
                logicalBundles = cce*bundlesPerCCE + (0:bundlesPerCCE-1);
                mappedBundles = zeros(size(logicalBundles));
                if data.MappingType == "noninterleaved"
                    mappedBundles = logicalBundles;
                else
                    C = nBundles / data.InterleaverSize;
                    for jj = 1:numel(logicalBundles)
                        x = logicalBundles(jj);
                        r = mod(x, data.InterleaverSize);
                        c = floor(x / data.InterleaverSize);
                        mappedBundles(jj) = mod(r*C + c + data.ShiftIndex, nBundles);
                    end
                end
                regIndices = zeros(1, 6);
                cursor = 1;
                for jj = 1:numel(mappedBundles)
                    first = mappedBundles(jj) * data.REGBundleSize;
                    values = first + (0:data.REGBundleSize-1);
                    regIndices(cursor:cursor+numel(values)-1) = values;
                    cursor = cursor + numel(values);
                end
                if numel(unique(regIndices)) ~= 6 || any(regIndices < 0) || any(regIndices >= data.NREG)
                    error("sixgr:phy:pdcch:coreset_reg_collision", ...
                        "CCE %d does not resolve to six unique in-range REGs.", cce);
                end
                if any(used(regIndices+1) ~= 0)
                    error("sixgr:phy:pdcch:coreset_reg_collision", ...
                        "CORESET CCE mapping reuses a REG before all CCEs are assigned.");
                end
                used(regIndices+1) = cce + 1;
                row = localRow();
                row.CCEIndex = cce;
                row.BundleIndices = localJoin(mappedBundles);
                row.REGIndices = localJoin(regIndices);
                row.BundleIndexVector = mappedBundles;
                row.REGIndexVector = regIndices;
                row.REGCount = numel(regIndices);
                row.UniqueREGCount = numel(unique(regIndices));
                rows(cce+1) = row;
            end
            if any(used == 0)
                error("sixgr:phy:pdcch:coreset_reg_collision", ...
                    "CORESET mapping leaves %d REGs unassigned.", sum(used == 0));
            end
            result = struct( ...
                "Definition", definition, ...
                "Rows", rows, ...
                "Table", struct2table(rmfield(rows, {'BundleIndexVector','REGIndexVector'}), "AsArray", true), ...
                "REGOwnerCCE", used - 1, ...
                "MismatchCount", 0, ...
                "Status", "PASS");
        end

        function [symbol, prb] = regCoordinates(regIndex, definition)
            if ~isa(definition, "sixgr.phy.pdcch.CORESETDefinition")
                definition = sixgr.phy.pdcch.CORESETDefinition(definition);
            end
            regIndex = double(regIndex);
            if any(regIndex < 0 | regIndex >= definition.Data.NREG | regIndex ~= fix(regIndex))
                error("sixgr:phy:pdcch:invalid_coreset_frequency_resources", ...
                    "REG indices must be integer values in [0,NREG).");
            end
            symbol = mod(regIndex, definition.Data.DurationSymbols) + definition.Data.StartSymbol;
            prb = floor(regIndex / definition.Data.DurationSymbols) + definition.Data.RBStart;
        end
    end
end

function row = localRow()
row = struct("CCEIndex", NaN, "BundleIndices", "", "REGIndices", "", ...
    "BundleIndexVector", [], "REGIndexVector", [], "REGCount", NaN, ...
    "UniqueREGCount", NaN);
end

function value = localJoin(values)
value = join(string(double(values(:).')), "|");
end
