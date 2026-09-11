classdef PUCCHUtil
    %PUCCHUTIL Shared strict helpers for the canonical PUCCH/UCI package.

    methods (Static)
        function value = field(input, name, fallback)
            if nargin < 3
                fallback = [];
            end
            value = fallback;
            if istable(input)
                if height(input) ~= 1
                    error("sixgr:phy:pucch:InvalidVectorRow", ...
                        "A PUCCH vector operation requires exactly one table row.");
                end
                if ismember(string(name), string(input.Properties.VariableNames))
                    value = input.(char(name));
                    if iscell(value) && isscalar(value)
                        value = value{1};
                    end
                end
            elseif isstruct(input) && isfield(input, char(name))
                value = input.(char(name));
            end
            if isempty(value)
                value = fallback;
            end
        end

        function value = number(input, name, fallback)
            if nargin < 3
                fallback = NaN;
            end
            raw = sixgr.phy.pucch.PUCCHUtil.field(input, name, fallback);
            if isstring(raw) || ischar(raw) || iscellstr(raw)
                value = str2double(string(raw));
            else
                value = double(raw);
            end
            if isempty(value)
                value = fallback;
            end
            if ~isscalar(value)
                error("sixgr:phy:pucch:InvalidScalar", ...
                    "%s must resolve to one scalar.", string(name));
            end
        end

        function value = text(input, name, fallback)
            if nargin < 3
                fallback = "";
            end
            value = string(sixgr.phy.pucch.PUCCHUtil.field( ...
                input, name, fallback));
            if isempty(value)
                value = string(fallback);
            end
            value = value(1);
            if ismissing(value)
                value = string(fallback);
            end
        end

        function value = truth(input, name, fallback)
            if nargin < 3
                fallback = false;
            end
            raw = sixgr.phy.pucch.PUCCHUtil.field(input, name, fallback);
            if islogical(raw)
                value = logical(raw);
                return;
            end
            if isnumeric(raw)
                value = logical(raw);
                return;
            end
            value = ismember(upper(strtrim(string(raw))), ...
                ["1","TRUE","YES","PASS"]);
        end

        function bits = bits(input)
            if isempty(input)
                bits = int8(zeros(0,1));
                return;
            end
            if ischar(input) || isstring(input)
                token = char(string(input));
                if isempty(token)
                    bits = int8(zeros(0,1));
                    return;
                end
                if any(~ismember(token, ['0','1']))
                    error("sixgr:phy:pucch:InvalidUCIBit", ...
                        "UCI bit strings may contain only 0 and 1.");
                end
                bits = int8(token(:) - '0');
            else
                % Validate before conversion: int8 rounds fractional values
                % and can turn malformed UCI (e.g. 0.2) into a valid zero.
                if ~((isnumeric(input) || islogical(input)) && isreal(input)) || ...
                        any(~isfinite(input(:))) || any(input(:) ~= 0 & input(:) ~= 1)
                    error("sixgr:phy:pucch:InvalidUCIBit", ...
                        "UCI values must be finite real binary values before conversion.");
                end
                bits = int8(input(:));
            end
        end

        function value = bitString(bits)
            bits = sixgr.phy.pucch.PUCCHUtil.bits(bits);
            if isempty(bits)
                value = "";
            else
                value = join(string(bits.'), "");
            end
        end

        function value = hash(input)
            if ischar(input)
                encoded = input;
            elseif isstring(input) && isscalar(input)
                encoded = char(string(input));
            else
                encoded = jsonencode(input);
            end
            bytes = uint8(unicode2native(encoded, "UTF-8"));
            value = string(sixgr.rrc.asn1.asn1SHA256Hex(bytes));
        end

        function value = boolString(input)
            if logical(input)
                value = "true";
            else
                value = "false";
            end
        end

        function value = readAllStrings(path)
            options = detectImportOptions(path, "Delimiter", ",", ...
                "VariableNamingRule", "preserve");
            options = setvartype(options, options.VariableNames, "string");
            value = readtable(path, options);
        end

        function assertInteger(value, minimum, maximum, identifier, name)
            if ~(isscalar(value) && isfinite(value) && value == fix(value) && ...
                    value >= minimum && value <= maximum)
                error(identifier, "%s must be an integer in [%g,%g]; observed %s.", ...
                    string(name), minimum, maximum, string(value));
            end
        end
    end
end
