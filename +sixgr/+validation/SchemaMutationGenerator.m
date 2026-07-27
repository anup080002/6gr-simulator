classdef SchemaMutationGenerator
    %SCHEMAMUTATIONGENERATOR Deterministic negative schema fixtures.
    methods (Static)
        function out = apply(input,mutation,target)
            out = input;
            mutation = upper(strtrim(string(mutation)));
            target = string(target);
            switch mutation
                case "NONE"
                case "DELETE_COLUMN"
                    out.(char(target)) = [];
                case "SET_NAN"
                    out.(char(target))(1) = NaN;
                case "SET_INF"
                    out.(char(target))(1) = Inf;
                case "SET_STRING"
                    out.(char(target)) = repmat("wrong_type",height(out),1);
                case "SET_UNKNOWN_ENUM"
                    out.(char(target))(1) = "BOGUS";
                case "DUPLICATE_PRIMARY_KEY"
                    out = [out;out(1,:)];
                case "EMPTY_TABLE"
                    out = out([],:);
                case "SET_INVALID_RELATION"
                    if target == "ErrorCount>TrialCount"
                        out.ErrorCount(1) = out.TrialCount(1)+1;
                    elseif target == "CILow>CIHigh"
                        out.CILow(1) = 0.8; out.CIHigh(1) = 0.2;
                    else
                        error("sixgr:validation:UnknownSchemaMutation", ...
                            "Unknown relation mutation %s.",target);
                    end
                case "SET_OUT_OF_RANGE"
                    out.(char(target))(1) = 2;
                case "SET_ZERO"
                    out.(char(target))(1) = 0;
                case "SET_BAD_HASH"
                    out.(char(target))(1) = "bad";
                otherwise
                    error("sixgr:validation:UnknownSchemaMutation", ...
                        "Unknown schema mutation %s.",mutation);
            end
        end
    end
end
