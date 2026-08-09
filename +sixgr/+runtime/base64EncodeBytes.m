function encoded = base64EncodeBytes(bytes)
%BASE64ENCODEBYTES Encode an exact byte vector, including an empty file.

% matlab.net.base64encode rejects MATLAB's canonical 0-by-0 empty array
% because it is not considered a vector.  Source-provenance bundles must be
% able to represent a legitimate zero-byte file, whose canonical base64
% payload is the empty string.

arguments
    bytes {mustBeNumericOrLogical}
end

if isempty(bytes)
    encoded = "";
    return;
end

validateattributes(bytes, {'numeric','logical'}, ...
    {'integer','vector','>=',0,'<=',255}, mfilename, 'bytes');
encoded = string(matlab.net.base64encode(uint8(bytes(:))));
end

function mustBeNumericOrLogical(value)
if ~(isnumeric(value) || islogical(value))
    error("sixgr:runtime:base64EncodeBytes:InvalidInput", ...
        "bytes must be a numeric or logical byte vector.");
end
end
