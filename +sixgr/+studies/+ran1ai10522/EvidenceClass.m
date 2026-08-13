classdef EvidenceClass
    %EVIDENCECLASS Closed evidence taxonomy for the RAN1 10.5.2.2 study.

    methods (Static)
        function values = allowed()
            values = ["ANALYTICAL_DERIVATION","CONCEPTUAL_DIAGRAM", ...
                "QUICK_SANITY_MODEL","CONTROLLED_LLS","COMMON_EVM_LLS", ...
                "MULTICELL_SLS","EXTERNAL_REFERENCE_REPRODUCTION","BLOCKED"];
        end

        function value = validate(value)
            value = upper(strtrim(string(value)));
            if ~isscalar(value) || ~any(value == sixgr.studies.ran1ai10522.EvidenceClass.allowed())
                error("sixgr:ran1ai10522:InvalidEvidenceClass", ...
                    "EvidenceClass must be one of: %s.", ...
                    strjoin(sixgr.studies.ran1ai10522.EvidenceClass.allowed(), ", "));
            end
        end

        function tf = canEnterTDocReady(value)
            value = sixgr.studies.ran1ai10522.EvidenceClass.validate(value);
            tf = any(value == ["CONTROLLED_LLS","COMMON_EVM_LLS","MULTICELL_SLS"]);
        end
    end
end
