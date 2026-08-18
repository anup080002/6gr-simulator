classdef RawCSVArrayCodec
%RAWCSVARRAYCODEC Lossless scalar-text encoding for array-valued CSV cells.
%
% CSV is a two-dimensional scalar-field format. MATLAB table variables can
% nevertheless contain wide numeric matrices or cells holding variable-
% length vectors. writetable expands those values into physical columns,
% which makes a raw-evidence schema data-dependent and can exceed parser
% column limits. This codec preserves class, dimensions, complex parts, and
% exact in-memory bytes in one versioned JSON token per logical table row.

    methods (Static)
        function token = encode(value)
            payload = struct( ...
                "ContractVersion", "sixgr_raw_csv_array/v1", ...
                "Class", class(value), ...
                "Size", double(size(value)), ...
                "ValueKind", "", ...
                "RealHex", "", ...
                "ImagHex", "", ...
                "Values", {{}}, ...
                "MissingMask", false(0, 1));
            if isnumeric(value) || islogical(value)
                payload.ValueKind = "numeric_bytes";
                if islogical(value)
                    realValue = value;
                else
                    realValue = real(value);
                end
                payload.RealHex = char(sixgr.runtime.RawCSVArrayCodec. ...
                    bytesToHex(sixgr.runtime.RawCSVArrayCodec.toBytes(realValue)));
                if ~isreal(value)
                    payload.ImagHex = char(sixgr.runtime.RawCSVArrayCodec. ...
                        bytesToHex(sixgr.runtime.RawCSVArrayCodec.toBytes(imag(value))));
                end
            elseif ischar(value)
                payload.ValueKind = "char_utf16_bytes";
                payload.RealHex = char(sixgr.runtime.RawCSVArrayCodec. ...
                    bytesToHex(typecast(uint16(value(:)), "uint8")));
            elseif isstring(value)
                payload.ValueKind = "string_values";
                missingMask = ismissing(value(:));
                values = value(:);
                values(missingMask) = "";
                payload.Values = cellstr(values);
                payload.MissingMask = logical(missingMask(:));
            elseif iscell(value)
                payload.ValueKind = "cell_tokens";
                tokens = strings(numel(value), 1);
                for valueIndex = 1:numel(value)
                    tokens(valueIndex) = sixgr.runtime.RawCSVArrayCodec.encode( ...
                        value{valueIndex});
                end
                payload.Values = cellstr(tokens);
            else
                error("sixgr:runtime:RawCSVArrayTypeUnsupported", ...
                    "Raw CSV array codec does not support class %s.", class(value));
            end
            token = string(jsonencode(payload));
        end

        function value = decode(token)
            token = string(token);
            if ~isscalar(token) || strlength(strtrim(token)) == 0
                error("sixgr:runtime:RawCSVArrayTokenInvalid", ...
                    "Raw CSV array token must be one nonempty string scalar.");
            end
            try
                payload = jsondecode(char(token));
            catch ME
                error("sixgr:runtime:RawCSVArrayTokenInvalid", ...
                    "Raw CSV array token is invalid JSON: %s", ME.message);
            end
            required = ["ContractVersion","Class","Size","ValueKind", ...
                "RealHex","ImagHex","Values","MissingMask"];
            if ~isstruct(payload) || ~all(isfield(payload, cellstr(required))) || ...
                    string(payload.ContractVersion) ~= "sixgr_raw_csv_array/v1"
                error("sixgr:runtime:RawCSVArrayTokenInvalid", ...
                    "Raw CSV array token does not satisfy sixgr_raw_csv_array/v1.");
            end
            dims = double(payload.Size(:).');
            if isempty(dims) || any(~isfinite(dims)) || any(dims < 0) || ...
                    any(dims ~= fix(dims))
                error("sixgr:runtime:RawCSVArrayTokenInvalid", ...
                    "Raw CSV array token has invalid dimensions.");
            end
            cls = char(string(payload.Class));
            kind = string(payload.ValueKind);
            switch kind
                case "numeric_bytes"
                    re = sixgr.runtime.RawCSVArrayCodec.fromBytes( ...
                        sixgr.runtime.RawCSVArrayCodec.hexToBytes(payload.RealHex), cls);
                    if strlength(string(payload.ImagHex)) > 0
                        im = sixgr.runtime.RawCSVArrayCodec.fromBytes( ...
                            sixgr.runtime.RawCSVArrayCodec.hexToBytes(payload.ImagHex), cls);
                        if numel(im) ~= numel(re)
                            error("sixgr:runtime:RawCSVArrayTokenInvalid", ...
                                "Raw CSV real/imaginary payload lengths differ.");
                        end
                        value = complex(re, im);
                    else
                        value = re;
                    end
                    value = reshape(value, dims);
                case "char_utf16_bytes"
                    bytes = sixgr.runtime.RawCSVArrayCodec.hexToBytes(payload.RealHex);
                    if mod(numel(bytes), 2) ~= 0
                        error("sixgr:runtime:RawCSVArrayTokenInvalid", ...
                            "Raw CSV UTF-16 payload has an odd byte count.");
                    end
                    value = reshape(char(typecast(bytes, "uint16")), dims);
                case "string_values"
                    value = string(payload.Values);
                    value = reshape(value, dims);
                    missingMask = logical(payload.MissingMask(:));
                    if numel(missingMask) ~= numel(value)
                        error("sixgr:runtime:RawCSVArrayTokenInvalid", ...
                            "Raw CSV string missing-mask length differs from the value count.");
                    end
                    value(missingMask) = missing;
                case "cell_tokens"
                    tokens = string(payload.Values);
                    if numel(tokens) ~= prod(dims)
                        error("sixgr:runtime:RawCSVArrayTokenInvalid", ...
                            "Raw CSV cell token count differs from its declared shape.");
                    end
                    value = cell(dims);
                    for valueIndex = 1:numel(tokens)
                        value{valueIndex} = sixgr.runtime.RawCSVArrayCodec.decode( ...
                            tokens(valueIndex));
                    end
                otherwise
                    error("sixgr:runtime:RawCSVArrayTokenInvalid", ...
                        "Unknown raw CSV array value kind '%s'.", char(kind));
            end
            if ~strcmp(class(value), cls) || ~isequal(size(value), dims)
                error("sixgr:runtime:RawCSVArrayTokenInvalid", ...
                    "Decoded raw CSV array class/shape does not match its contract.");
            end
        end
    end

    methods (Static, Access = private)
        function bytes = toBytes(value)
            if islogical(value)
                bytes = uint8(value(:));
            else
                bytes = typecast(value(:), "uint8");
            end
            bytes = bytes(:);
        end

        function value = fromBytes(bytes, cls)
            if strcmp(cls, "logical")
                value = logical(bytes(:));
                return;
            end
            numericClasses = ["double","single","int8","uint8","int16", ...
                "uint16","int32","uint32","int64","uint64"];
            if ~any(string(cls) == numericClasses)
                error("sixgr:runtime:RawCSVArrayTokenInvalid", ...
                    "Unsupported numeric class '%s' in raw CSV token.", cls);
            end
            value = typecast(bytes(:), cls);
            value = value(:);
        end

        function value = bytesToHex(bytes)
            if isempty(bytes)
                value = "";
                return;
            end
            value = string(lower(reshape(dec2hex(uint8(bytes), 2).', 1, [])));
        end

        function bytes = hexToBytes(value)
            value = char(string(value));
            if isempty(value)
                bytes = zeros(0, 1, "uint8");
                return;
            end
            if mod(numel(value), 2) ~= 0 || ...
                    isempty(regexp(value, "^[0-9a-fA-F]+$", "once"))
                error("sixgr:runtime:RawCSVArrayTokenInvalid", ...
                    "Raw CSV hexadecimal payload is malformed.");
            end
            bytes = uint8(hex2dec(reshape(value, 2, []).'));
        end
    end
end
