function s = jsonRead(filePath)
%JSONREAD Read JSON with optional //, /* */, #, % comments and trailing commas.
%
%   s = sixgr.util.jsonRead("config/suite_config.json")
%
% This reader is intentionally forgiving for hand-edited config files.

arguments
    filePath {mustBeTextScalar}
end

filePath = char(filePath);
if ~isfile(filePath)
    error("sixgr:util:jsonRead:FileNotFound","File not found: %s", filePath);
end

txt = localReadUtf8(filePath);
txt = localStripBOM(txt);
txt = localStripComments(txt);
txt = localStripTrailingCommas(txt);

try
    s = jsondecode(txt);
catch ME
    error("sixgr:util:jsonRead:DecodeFailed", ...
        "jsondecode failed for '%s': %s", filePath, ME.message);
end

end

function txt = localReadUtf8(fp)
fid = fopen(fp,"r","n","UTF-8");
if fid < 0
    error("sixgr:util:jsonRead:OpenFailed","Cannot open file: %s", fp);
end
c = fread(fid, Inf, "*char").';
fclose(fid);
txt = string(c);
end

function txt = localStripBOM(txt)
% Remove UTF-8 BOM if present
if strlength(txt) >= 1 && txt(1) == char(65279) % U+FEFF
    txt = extractAfter(txt, 1);
end
end

function out = localStripComments(in)
% Remove // line comments, /* */ block comments, and #/% line comments.
s = char(in);
n = length(s);
buf = char(zeros(1,n));
k = 0;

inStr = false;
esc = false;

i = 1;
while i <= n
    c = s(i);

    if inStr
        k = k + 1; buf(k) = c;
        if esc
            esc = false;
        else
            if c == '\'
                esc = true;
            elseif c == '"'
                inStr = false;
            end
        end
        i = i + 1;
        continue;
    end

    % Not in string
    if c == '"'
        inStr = true;
        k = k + 1; buf(k) = c;
        i = i + 1;
        continue;
    end

    % // comment
    if c == '/' && i < n && s(i+1) == '/'
        i = i + 2;
        while i <= n && s(i) ~= newline && s(i) ~= char(13)
            i = i + 1;
        end
        continue;
    end

    % /* */ comment
    if c == '/' && i < n && s(i+1) == '*'
        i = i + 2;
        while i < n && ~(s(i) == '*' && s(i+1) == '/')
            i = i + 1;
        end
        i = i + 2; % skip */
        continue;
    end

    % # or % comment (line)
    if c == '#' || c == '%'
        i = i + 1;
        while i <= n && s(i) ~= newline && s(i) ~= char(13)
            i = i + 1;
        end
        continue;
    end

    k = k + 1; buf(k) = c;
    i = i + 1;
end

out = string(buf(1:k));

end

function out = localStripTrailingCommas(in)
% Remove trailing commas before ] or } (outside strings).
s = char(in);
n = length(s);
buf = char(zeros(1,n));
k = 0;

inStr = false;
esc = false;

i = 1;
while i <= n
    c = s(i);

    if inStr
        k = k + 1; buf(k) = c;
        if esc
            esc = false;
        else
            if c == '\'
                esc = true;
            elseif c == '"'
                inStr = false;
            end
        end
        i = i + 1;
        continue;
    end

    if c == '"'
        inStr = true;
        k = k + 1; buf(k) = c;
        i = i + 1;
        continue;
    end

    if c == ','
        j = i + 1;
        while j <= n && isspace(s(j))
            j = j + 1;
        end
        if j <= n && (s(j) == ']' || s(j) == '}')
            % skip this comma
            i = i + 1;
            continue;
        end
    end

    k = k + 1; buf(k) = c;
    i = i + 1;
end

out = string(buf(1:k));

end

function mustBeTextScalar(x)
if ~(ischar(x) || (isstring(x) && isscalar(x)))
    error("sixgr:util:jsonRead:BadType","Input must be a char vector or string scalar.");
end
end
