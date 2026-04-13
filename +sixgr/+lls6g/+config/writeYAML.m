function writeYAML(filePath, data)
%WRITEYAML Write a struct/cell/numeric/string object as YAML text.

filePath = char(string(filePath));
txt = localSerializeValue(data, 0, false);
sixgr.util.writeTextFile(filePath, txt, ...
    "MimeType", "application/x-yaml; charset=UTF-8", ...
    "ArtifactKind", "yaml");
end

function txt = localSerializeValue(v, indentLevel, inline)
if builtin("isstruct", v)
    txt = localSerializeStruct(v, indentLevel);
    return;
end
if iscell(v)
    txt = localSerializeCell(v, indentLevel);
    return;
end
if isa(v, "string")
    if isscalar(v)
        txt = localScalarString(v, inline);
    else
        txt = localSerializeCell(cellstr(v(:)), indentLevel);
    end
    return;
end
if ischar(v)
    txt = localScalarString(string(v), inline);
    return;
end
if islogical(v)
    if isscalar(v)
        txt = lower(string(v));
    else
        txt = localSerializeCell(num2cell(v(:)), indentLevel);
    end
    return;
end
if isnumeric(v)
    if isempty(v)
        txt = "[]";
    elseif isscalar(v)
        txt = localScalarNumeric(v);
    else
        items = strings(1, numel(v));
        for ii = 1:numel(v)
            items(ii) = localScalarNumeric(v(ii));
        end
        txt = "[" + strjoin(items, ", ") + "]";
    end
    return;
end
if isempty(v)
    txt = "null";
    return;
end
txt = localScalarString(string(evalc("disp(v)")), inline);
end

function txt = localSerializeStruct(s, indentLevel)
f = fieldnames(s);
if isempty(f)
    txt = "{}";
    return;
end
lines = strings(0,1);
for i = 1:numel(f)
    key = string(f{i});
    value = s.(f{i});
    indent = string(repmat(' ', 1, 2*indentLevel));
    if builtin("isstruct", value)
        if isempty(value)
            lines(end+1,1) = indent + key + ": {}"; %#ok<AGROW>
        else
            lines(end+1,1) = indent + key + ":"; %#ok<AGROW>
            lines = [lines; splitlines(string(localSerializeStruct(value, indentLevel+1)))]; %#ok<AGROW>
        end
    elseif iscell(value)
        if isempty(value)
            lines(end+1,1) = indent + key + ": []"; %#ok<AGROW>
        else
            lines(end+1,1) = indent + key + ":"; %#ok<AGROW>
            lines = [lines; splitlines(string(localSerializeCell(value, indentLevel+1)))]; %#ok<AGROW>
        end
    else
        lines(end+1,1) = indent + key + ": " + localSerializeValue(value, indentLevel+1, true); %#ok<AGROW>
    end
end
txt = strjoin(lines, newline);
end

function txt = localSerializeCell(c, indentLevel)
if isempty(c)
    txt = "[]";
    return;
end
lines = strings(0,1);
for i = 1:numel(c)
    value = c{i};
    indent = string(repmat(' ', 1, 2*indentLevel));
    if builtin("isstruct", value)
        lines(end+1,1) = indent + "-"; %#ok<AGROW>
        lines = [lines; splitlines(string(localSerializeStruct(value, indentLevel+1)))]; %#ok<AGROW>
    else
        lines(end+1,1) = indent + "- " + localSerializeValue(value, indentLevel+1, true); %#ok<AGROW>
    end
end
txt = strjoin(lines, newline);
end

function txt = localScalarString(v, ~)
v = string(v);
if strlength(v) == 0
    txt = '""';
else
    escaped = replace(v, "\", "\\");
    escaped = replace(escaped, '"', '\"');
    escaped = replace(escaped, sprintf('\r'), '\r');
    escaped = replace(escaped, sprintf('\n'), '\n');
    escaped = replace(escaped, sprintf('\t'), '\t');
    txt = '"' + escaped + '"';
end
end

function txt = localScalarNumeric(v)
if ~isscalar(v)
    error("sixgr:lls6g:config:NonScalarNumericToken", ...
        "Numeric YAML token helper requires a scalar value.");
end
if isnan(v)
    txt = ".nan";
    return;
end
if isinf(v)
    if v > 0
        txt = ".inf";
    else
        txt = "-.inf";
    end
    return;
end
txt = string(v);
if contains(lower(txt), "e") && ~contains(txt, ".")
    txt = regexprep(txt, '^([+-]?\d+)e([+-]?\d+)$', '$1.0e$2');
end
end
