classdef PUSCHMCSResolver
    %PUSCHMCSRESOLVER Resolve a pinned PUSCH MCS-table row.

    methods (Static)
        function result = resolve(tableName, mcsIndex, transformPrecoding)
            tableName = lower(strrep(strtrim(string(tableName)), "-", ""));
            mcsIndex = double(mcsIndex);
            if ~(isscalar(mcsIndex) && isfinite(mcsIndex) ...
                    && mcsIndex == fix(mcsIndex) && mcsIndex >= 0)
                error("sixgr:pusch:InvalidMCSContext", ...
                    "PUSCH MCS index must be a nonnegative integer.");
            end
            transformPrecoding = logical(transformPrecoding);
            catalog = nrPUSCHMCSTables;
            switch tableName
                case {"qam64","table1","64qam"}
                    if transformPrecoding
                        sourceTable = catalog.TransformPrecodingQAM64Table;
                    else
                        sourceTable = catalog.QAM64Table;
                    end
                    canonical = "qam64";
                case {"qam256","table2","256qam"}
                    if transformPrecoding
                        error("sixgr:pusch:InvalidMCSContext", ...
                            "The selected strict transform-precoded profile does not use the 256QAM MCS table.");
                    end
                    sourceTable = catalog.QAM256Table;
                    canonical = "qam256";
                case {"qam64lowse","table3","lowse"}
                    if transformPrecoding
                        sourceTable = catalog.TransformPrecodingQAM64LowSETable;
                    else
                        sourceTable = catalog.QAM64LowSETable;
                    end
                    canonical = "qam64LowSE";
                otherwise
                    error("sixgr:pusch:InvalidMCSContext", ...
                        "Unsupported PUSCH MCS table '%s'.", tableName);
            end
            row = sourceTable(double(sourceTable.MCSIndex) == mcsIndex, :);
            if height(row) ~= 1 || isempty(row.Modulation{1}) ...
                    || ~isfinite(double(row.Qm)) ...
                    || ~isfinite(double(row.TargetCodeRate))
                error("sixgr:pusch:ReservedMCS", ...
                    "PUSCH MCS index %d is reserved in table %s.", ...
                    mcsIndex, canonical);
            end
            modulation = string(row.Modulation{1});
            modulation = sixgr.phy.ul.pusch.PUSCHModulator.normalizeModulation(modulation);
            result = struct( ...
                "MCSTable", canonical, ...
                "MCSIndex", mcsIndex, ...
                "Modulation", modulation, ...
                "Qm", double(row.Qm), ...
                "TargetCodeRate", double(row.TargetCodeRate), ...
                "SpectralEfficiency", double(row.SpectralEfficiency), ...
                "TransformPrecoding", transformPrecoding, ...
                "Source", "nrPUSCHMCSTables_R2026a_pinned_adapter");
        end
    end
end
