classdef SpecSupport
    %SPECSUPPORT Small dependency-free helpers for frozen PUCCH oracles.
    %
    % This package must not call the production PUCCH implementation or
    % MATLAB nrPUCCH* functions. It is used only to interpret independent
    % vectors and to document the specification arithmetic being checked.

    methods (Static)
        function value = field(row,name,fallback)
            value = fallback;
            if istable(row) && height(row) == 1 && ...
                    ismember(name,string(row.Properties.VariableNames))
                value = row.(char(name))(1);
            elseif isstruct(row) && isfield(row,char(name))
                value = row.(char(name));
            end
        end

        function value = truth(input)
            value = ismember(upper(strtrim(string(input))), ...
                ["TRUE","1","YES","PASS"]);
        end

        function bits = bitText(input)
            token = regexprep(char(string(input)),"[^01]","");
            bits = int8(token(:)-'0');
        end

        function meta = metadata(name)
            meta = struct("OracleImplementation","independent_spec_arithmetic", ...
                "OracleVersion","PUCCH-R18-2026.1", ...
                "OracleSource","3GPP_TS_38.211_38.212_38.213", ...
                "OracleClass",string(name), ...
                "UsesProductionImplementation",false, ...
                "UsesMATLABNRPUCCHFunctions",false);
        end
    end
end
