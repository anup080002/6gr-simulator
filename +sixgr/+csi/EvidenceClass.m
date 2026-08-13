classdef EvidenceClass
    %EVIDENCECLASS Closed evidence taxonomy for RAN1 10.5.3.1 outputs.

    methods (Static)
        function values = allowed()
            values = ["ANALYTICAL","SANITY","PROCEDURE", ...
                "LLS_CONTROLLED","LLS_COMMON_EVM","SLS","NOT_EVALUATED"];
        end

        function values = allowedFigures()
            values = ["ARCHITECTURE_DIAGRAM","PROCEDURE_TIMELINE", ...
                "RESOURCE_GRID_DIAGRAM","ANALYTICAL_SANITY", ...
                "SANITY_MONTE_CARLO","CONTROLLED_WAVEFORM_LLS", ...
                "CONTROLLED_PROCEDURE_PLUS_LLS","SLS_REQUIRED", ...
                "COMMON_EVM_LLS","NOT_EVALUATED"];
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


        function value = validateFigure(value)
            value = upper(strtrim(string(value)));
            if ~isscalar(value) || ...
                    ~any(value == sixgr.csi.EvidenceClass.allowedFigures())
                error("sixgr:csi:InvalidFigureEvidenceClass", ...
                    "Figure EvidenceClass must be one of: %s.", ...
                    strjoin(sixgr.csi.EvidenceClass.allowedFigures(),", "));
            end
        end
    end
end
