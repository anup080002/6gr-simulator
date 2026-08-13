classdef EvidenceClassifier
    %EVIDENCECLASSIFIER Fail-closed evidence taxonomy for AI 10.5.1.3.

    methods (Static)
        function values = allowed()
            values = ["ANALYTICAL_EXACT","ANALYTICAL_SCREENING", ...
                "SOURCE_REPRODUCTION","CALIBRATED_LLS","PROCEDURE_SLS", ...
                "ASSUMPTION_ONLY","PROCEDURE_SCHEMATIC"];
        end

        function value = require(value)
            value = upper(strtrim(string(value)));
            if ~isscalar(value) || ~ismember(value,sixgr.bwop.EvidenceClassifier.allowed())
                error("sixgr:bwop:InvalidEvidenceClass", ...
                    "Evidence class '%s' is invalid. Allowed classes: %s.", ...
                    value,strjoin(sixgr.bwop.EvidenceClassifier.allowed(),", "));
            end
        end

        function tf = mayEnterTDocReady(value,status,statisticsQualified)
            value = sixgr.bwop.EvidenceClassifier.require(value);
            status = upper(strtrim(string(status)));
            if nargin < 3
                statisticsQualified = true;
            end
            tf = status == "PASS" && logical(statisticsQualified) && ...
                ismember(value,["SOURCE_REPRODUCTION","CALIBRATED_LLS", ...
                "PROCEDURE_SLS"]);
        end

        function assertNotProxy(primaryTable)
            if ~istable(primaryTable) || isempty(primaryTable)
                return;
            end
            names = string(primaryTable.Properties.VariableNames);
            for field = ["Source","ExecutionBackend","ApproximationMode", ...
                    "EvidenceClass"]
                index = find(strcmpi(names,field),1);
                if isempty(index), continue; end
                values = lower(string(primaryTable.(names(index))));
                bad = contains(values,["proxy","fallback","synthetic", ...
                    "logistic","lut"]);
            if any(bad,"all")
                    error("sixgr:bwop:ProxyInPrimaryEvidence", ...
                        "Primary BWOP table field %s contains proxy/fallback evidence.",field);
                end
            end
        end
    end
end
