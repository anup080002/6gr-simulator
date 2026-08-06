function jsonWrite(filePath, s)
%JSONWRITE Write a struct to JSON with stable pretty formatting.
%
%   sixgr.util.jsonWrite("config/suite_config.json", cfgStruct)

arguments
    filePath {mustBeTextScalar}
    s
end

filePath = char(filePath);
s = localJsonSafeValue(s);

% Pretty print if supported
try
    txt = jsonencode(s, "PrettyPrint", true);
catch
    txt = jsonencode(s);
end

% jsonencode returns string in some releases
txt = char(txt);

if sixgr.db.storeTextArtifact(filePath, [txt, newline], "application/json; charset=UTF-8", "json")
    return;
end

sixgr.util.ensureDir(filePath); % creates parent

fid = fopen(filePath, "w", "n", "UTF-8");
if fid < 0
    error("sixgr:util:jsonWrite:OpenFailed","Cannot open for writing: %s", filePath);
end
fwrite(fid, txt, "char");
fwrite(fid, newline, "char");
fclose(fid);

end

function mustBeTextScalar(x)
if ~(ischar(x) || (isstring(x) && isscalar(x)))
    error("sixgr:util:jsonWrite:BadType","Input must be a char vector or string scalar.");
end
end

function out = localJsonSafeValue(value)
if isa(value, "function_handle")
    out = struct("json_type", "function_handle", "text", func2str(value));
    return;
end
if isnumeric(value) && ~isreal(value)
    % JSON has no complex scalar type. Preserve measured complex evidence
    % losslessly and explicitly instead of dropping it or allowing
    % jsonencode to fail. Shape is retained so consumers can reconstruct
    % the original MATLAB array as complex(real, imag).
    out = struct();
    out.json_type = "complex_array_split";
    out.size = double(size(value));
    out.real = real(value);
    out.imag = imag(value);
    return;
end
if istable(value)
    out = localJsonSafeValue(table2struct(value));
    return;
end
if iscell(value)
    out = value;
    for i = 1:numel(value)
        out{i} = localJsonSafeValue(value{i});
    end
    return;
end
if isstruct(value)
    out = value;
    fields = fieldnames(value);
    for idx = 1:numel(value)
        for f = 1:numel(fields)
            out(idx).(fields{f}) = localJsonSafeValue(value(idx).(fields{f}));
        end
    end
    return;
end
out = value;
end
