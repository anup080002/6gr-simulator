classdef PDCCHTDocStudyEvidenceClass
    %EVIDENCECLASS Closed evidence taxonomy for PDCCH AI 10.5.2.1.

    methods (Static)
        function values = allowed()
            values = ["STATIC_VISUAL","ANALYTICAL_EXACT", ...
                "ENUMERATION_EXACT","SCHEDULER_PLACEMENT", ...
                "PROCEDURE_MODEL","LLS_CONTROLLED","LLS_COMMON_EVM", ...
                "SLS_FULL","NOT_EVALUATED"];
        end

        function value = require(value)
            value = upper(strtrim(string(value)));
            if ~isscalar(value) || ~ismember(value, ...
                    sixgr.phy.pdcch.tdoc.PDCCHTDocStudyEvidenceClass.allowed())
                error("sixgr:phy:pdcch:tdoc:InvalidEvidenceClass", ...
                    "Evidence class '%s' is invalid. Allowed: %s.", ...
                    value, strjoin(sixgr.phy.pdcch.tdoc.PDCCHTDocStudyEvidenceClass.allowed(), ", "));
            end
        end

        function tf = tdocEligible(value, status, statisticsQualified)
            value = sixgr.phy.pdcch.tdoc.PDCCHTDocStudyEvidenceClass.require(value);
            status = upper(strtrim(string(status)));
            if nargin < 3
                statisticsQualified = true;
            end
            tf = status == "PASS" && logical(statisticsQualified) && ...
                ismember(value, ["ANALYTICAL_EXACT","ENUMERATION_EXACT", ...
                "LLS_COMMON_EVM","SLS_FULL"]);
        end

        function assertPrimaryTruth(T)
            if ~istable(T) || isempty(T)
                return;
            end
            names = string(T.Properties.VariableNames);
            for field = ["Source","ExecutionBackend","ApproximationMode","PDCCHTDocStudyEvidenceClass"]
                idx = find(strcmpi(names, field), 1);
                if isempty(idx)
                    continue;
                end
                values = lower(string(T.(names(idx))));
                if any(contains(values, ["proxy","fallback","synthetic","lut","logistic"]), "all")
                    error("sixgr:phy:pdcch:tdoc:ProxyInPrimaryEvidence", ...
                        "Primary PDCCH TDoc table field %s contains proxy/fallback evidence.", field);
                end
            end
        end
    end
end
