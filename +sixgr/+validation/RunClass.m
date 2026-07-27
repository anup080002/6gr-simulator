classdef RunClass
    %RUNCLASS Physically isolated validation run classes.
    properties (Constant)
        FIXED_LINK_CALIBRATION = "FIXED_LINK_CALIBRATION"
        GEOMETRY_LINK_LEVEL = "GEOMETRY_LINK_LEVEL"
        SYSTEM_LEVEL = "SYSTEM_LEVEL"
        CONTROL_ONLY = "CONTROL_ONLY"
        PROTOCOL_SYSTEM_STUDY = "PROTOCOL_SYSTEM_STUDY"
    end
    methods (Static)
        function out = values()
            out = ["FIXED_LINK_CALIBRATION","GEOMETRY_LINK_LEVEL", ...
                "SYSTEM_LEVEL","CONTROL_ONLY","PROTOCOL_SYSTEM_STUDY"];
        end
        function out = parse(input)
            out = upper(strtrim(string(input)));
            if ~(isscalar(out) && ismember(out,sixgr.validation.RunClass.values()))
                error("sixgr:validation:UnknownRunClass", ...
                    "Unknown validation RunClass '%s'.",string(input));
            end
        end
        function require(required,evidence)
            required = sixgr.validation.RunClass.parse(required);
            evidence = sixgr.validation.RunClass.parse(evidence);
            if required ~= evidence
                error("sixgr:validation:RunClassSubstitution", ...
                    "Required run class %s cannot be satisfied by %s evidence.", ...
                    required,evidence);
            end
        end
    end
end
