classdef OracleType
    %ORACLETYPE Independent and regression-only oracle classifications.
    properties (Constant)
        PURE_MATH = "PURE_MATH"
        FROZEN_EXTERNAL_VECTOR = "FROZEN_EXTERNAL_VECTOR"
        ANALYTICAL_INVARIANT = "ANALYTICAL_INVARIANT"
        STATISTICAL_DISTRIBUTION = "STATISTICAL_DISTRIBUTION"
        SAME_TOOLBOX_SELF_CONSISTENCY = "SAME_TOOLBOX_SELF_CONSISTENCY"
        DUT_REGRESSION = "DUT_REGRESSION"
    end
    methods (Static)
        function out = values()
            out = ["PURE_MATH","FROZEN_EXTERNAL_VECTOR", ...
                "ANALYTICAL_INVARIANT","STATISTICAL_DISTRIBUTION", ...
                "SAME_TOOLBOX_SELF_CONSISTENCY","DUT_REGRESSION"];
        end
        function out = qualifyingValues()
            out = ["PURE_MATH","FROZEN_EXTERNAL_VECTOR", ...
                "ANALYTICAL_INVARIANT","STATISTICAL_DISTRIBUTION"];
        end
        function out = parse(input)
            out = upper(strtrim(string(input)));
            if ~(isscalar(out) && ismember(out,sixgr.validation.OracleType.values()))
                error("sixgr:validation:UnknownOracleType", ...
                    "Unknown validation OracleType '%s'.",string(input));
            end
        end
        function out = qualifies(input)
            out = ismember(sixgr.validation.OracleType.parse(input), ...
                sixgr.validation.OracleType.qualifyingValues());
        end
    end
end
