function writeYAML(filePath, data)
%WRITEYAML Write a struct/cell/numeric/string object as YAML text.

filePath = char(string(filePath));
sixgr.util.ensureFolder(fileparts(filePath));
txt = localSerializeValue(data, 0, false);
fid = fopen(filePath, "w");
if fid < 0
    error("sixgr:lls6g:config:YAMLWriteFailed", ...
        "Unable to open YAML output '%s'.", string(filePath));
end
cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, "%s", txt);
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
        txt = string(v);
    else
        txt = "[" + strjoin(string(v(:).'), ", ") + "]";
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
        lines(end+1,1) = indent + key + ":"; %#ok<AGROW>
        lines = [lines; splitlines(string(localSerializeStruct(value, indentLevel+1)))]; %#ok<AGROW>
    elseif iscell(value)
        lines(end+1,1) = indent + key + ":"; %#ok<AGROW>
        lines = [lines; splitlines(string(localSerializeCell(value, indentLevel+1)))]; %#ok<AGROW>
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
    txt = '"' + replace(v, '"', '\"') + '"';
end
end
