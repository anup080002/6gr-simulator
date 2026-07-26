classdef PUCCHResourceSetResolver
    %PUCCHRESOURCESETRESOLVER Exact source-aware resource-set selection.

    methods (Static)
        function result = resolveVector(row)
            oUCI = sixgr.phy.pucch.PUCCHUtil.number(row,"OUCI");
            source = upper(sixgr.phy.pucch.PUCCHUtil.text(row,"ReportSource"));
            result = struct("Valid",true,"SelectedSetID",NaN, ...
                "SelectedResourceSource","","ErrorID","", ...
                "DefaultOrHashUsed",false, ...
                "ConfigurationEpoch",sixgr.phy.pucch.PUCCHUtil.number( ...
                row,"ConfigurationEpoch",NaN));
            if oUCI > 1706 || oUCI < 0 || oUCI ~= fix(oUCI)
                result.Valid = false;
                result.ErrorID = "sixgr:phy:pucch:NoSupportingResourceSet";
                return;
            end
            thresholds = sixgr.phy.pucch.PUCCHResourceSetResolver.parseThresholds( ...
                sixgr.phy.pucch.PUCCHUtil.text(row,"ResourceSetsJSON","{}"));
            switch source
                case "SR_ONLY"
                    result.SelectedResourceSource = "SR_CONFIG_RESOURCE";
                case "CSI_ONLY"
                    result.SelectedResourceSource = "CSI_REPORT_RESOURCE";
                otherwise
                    ids = sort(cell2mat(keys(thresholds)));
                    selected = NaN;
                    for index = 1:numel(ids)
                        if oUCI <= thresholds(ids(index))
                            selected = ids(index);
                            break;
                        end
                    end
                    if ~isfinite(selected)
                        result.Valid = false;
                        result.ErrorID = "sixgr:phy:pucch:NoSupportingResourceSet";
                        return;
                    end
                    if source == "HARQ_SPS"
                        result.SelectedResourceSource = "SPS_ENTRY_" + string(selected);
                    else
                        result.SelectedSetID = selected;
                        result.SelectedResourceSource = "SET_" + string(selected);
                    end
            end
        end

        function selected = resolve(report, rrcContext)
            if ~isa(report,"sixgr.phy.pucch.UCIReport") || ...
                    ~isa(rrcContext,"sixgr.phy.pucch.PUCCHRRCContext")
                error("sixgr:phy:pucch:MissingUCIReportContext", ...
                    "Resource-set resolution requires typed report and RRC context.");
            end
            if report.ConfigurationEpoch ~= rrcContext.ConfigurationEpoch
                error("sixgr:phy:pucch:StaleConfiguration", ...
                    "Report and PUCCH RRC configuration epochs differ.");
            end
            serialized = sixgr.phy.pucch.UCIReportSerializer.serialize(report);
            oUCI = serialized.InformationBitCount;
            sets = rrcContext.ResourceSets;
            selected = [];
            for index = 1:numel(sets)
                if oUCI <= sets(index).MaxPayloadBits
                    selected = sets(index);
                    break;
                end
            end
            if isempty(selected)
                error("sixgr:phy:pucch:NoSupportingResourceSet", ...
                    "No configured PUCCH resource set supports O_UCI=%d.",oUCI);
            end
        end
    end

    methods (Static, Access=private)
        function map = parseThresholds(json)
            tokens = regexp(char(json), '"(\d+)"\s*:\s*(\d+)', ...
                "tokens");
            map = containers.Map("KeyType","double","ValueType","double");
            for index = 1:numel(tokens)
                map(str2double(tokens{index}{1})) = str2double(tokens{index}{2});
            end
        end
    end
end
