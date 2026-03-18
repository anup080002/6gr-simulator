function jsonWrite(filePath, s)
%JSONWRITE Write a struct to JSON with stable pretty formatting.
%
%   sixgr.util.jsonWrite("config/suite_config.json", cfgStruct)

arguments
    filePath {mustBeTextScalar}
    s
end

filePath = char(filePath);
sixgr.util.ensureDir(filePath); % creates parent

% Pretty print if supported
try
    txt = jsonencode(s, "PrettyPrint", true);
catch
    txt = jsonencode(s);
end

% jsonencode returns string in some releases
txt = char(txt);

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
