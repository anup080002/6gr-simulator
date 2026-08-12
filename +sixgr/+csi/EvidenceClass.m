classdef EvidenceClass
    %EVIDENCECLASS Closed evidence taxonomy for RAN1 10.5.3.1 outputs.

    methods (Static)
        function values = allowed()
            values = ["ANALYTICAL","SANITY","PROCEDURE", ...
                "LLS_CONTROLLED","LLS_COMMON_EVM","SLS","NOT_EVALUATED"];
        end

        function value = validate(value)
            value = upper(strtrim(string(value)));
            if ~isscalar(value) || ~any(value == sixgr.csi.EvidenceClass.allowed())
                error("sixgr:csi:InvalidEvidenceClass", ...
                    "EvidenceClass must be one of: %s.", ...
                    strjoin(sixgr.csi.EvidenceClass.allowed(),", "));
            end
        end

        function tf = tdocQuantitativeEligible(value)
            value = sixgr.csi.EvidenceClass.validate(value);
            tf = any(value == ["LLS_COMMON_EVM","SLS"]);
        end
    end
end
