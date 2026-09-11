function writeYAML(filePath, data)
%WRITEYAML Write a struct/cell/numeric/string object as YAML text.

filePath = char(string(filePath));
data = sixgr.lls6g.config.yamlArrayEnvelope(data,"encode");
txt = localSerializeValue(data, 0, false);
sixgr.util.writeTextFile(filePath, txt, ...
    "MimeType", "application/x-yaml; charset=UTF-8", ...
    "ArtifactKind", "yaml");
end

function txt = localSerializeValue(v, indentLevel, inline)
if builtin("isstruct", v)
    if isscalar(v)
        txt = localSerializeStruct(v, indentLevel);
    else
        txt = localSerializeStructSequence(v, indentLevel);
    end
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
        txt = localSerializeStringArray(v);
    end
    return;
end
if ischar(v)
    if isrow(v) || isempty(v)
        txt = localScalarString(string(v), inline);
    else
        txt = localSerializeStringArray(string(cellstr(v)));
    end
    return;
end
if islogical(v)
    if isscalar(v)
        txt = lower(string(v));
    else
        txt = localSerializeLogicalArray(v);
    end
    return;
end

if isnumeric(v)
    if isempty(v)
        txt = "[]";
    elseif isscalar(v)
        txt = localScalarNumeric(v);
    else
        txt = localSerializeNumericArray(v);
    end
    return;
end
if isempty(v)
    txt = "null";
    return;
end
txt = localScalarString(string(evalc("disp(v)")), inline);
end

function txt = localSerializeStringArray(v)
v = string(v);
if ndims(v) > 2
    error("sixgr:lls6g:config:UnsupportedStringArrayRank", ...
        "YAML serialization supports string scalars, vectors, and two-dimensional matrices only.");
end
if isempty(v)
    txt = "[]";
    return;
end
if isvector(v)
    items = strings(1, numel(v));
    for ii = 1:numel(v)
        items(ii) = localScalarString(v(ii), true);
    end
    txt = "[" + strjoin(items, ", ") + "]";
    return;
end
rows = strings(1, size(v,1));
for rowIndex = 1:size(v,1)
    items = strings(1, size(v,2));
    for columnIndex = 1:size(v,2)
        items(columnIndex) = localScalarString(v(rowIndex,columnIndex), true);
    end
    rows(rowIndex) = "[" + strjoin(items, ", ") + "]";
end
txt = "[" + strjoin(rows, ", ") + "]";
end

function txt = localSerializeNumericArray(v)
if ndims(v) > 2
    error("sixgr:lls6g:config:UnsupportedNumericArrayRank", ...
        "YAML serialization supports numeric scalars, vectors, and two-dimensional matrices only.");
end
if isvector(v)
    items = strings(1, numel(v));
    for ii = 1:numel(v)
        items(ii) = localScalarNumeric(v(ii));
    end
    txt = "[" + strjoin(items, ", ") + "]";
    return;
end
rows = strings(1, size(v,1));
for rowIndex = 1:size(v,1)
    items = strings(1, size(v,2));
    for columnIndex = 1:size(v,2)
        items(columnIndex) = localScalarNumeric(v(rowIndex,columnIndex));
    end
    rows(rowIndex) = "[" + strjoin(items, ", ") + "]";
end
txt = "[" + strjoin(rows, ", ") + "]";
end

function txt = localSerializeLogicalArray(v)
if ndims(v) > 2
    error("sixgr:lls6g:config:UnsupportedLogicalArrayRank", ...
        "YAML serialization supports logical scalars, vectors, and two-dimensional matrices only.");
end
if isvector(v)
    txt = "[" + strjoin(lower(string(v(:).')), ", ") + "]";
    return;
end
rows = strings(1, size(v,1));
for rowIndex = 1:size(v,1)
    rows(rowIndex) = "[" + ...
        strjoin(lower(string(v(rowIndex,:))), ", ") + "]";
end
txt = "[" + strjoin(rows, ", ") + "]";
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
        if isempty(value) || (isscalar(value) && isempty(fieldnames(value)))
            lines(end+1,1) = indent + key + ": {}"; %#ok<AGROW>
        elseif ~isscalar(value)
            lines(end+1,1) = indent + key + ":"; %#ok<AGROW>
            lines = [lines; splitlines(string(localSerializeStructSequence( ...
                value, indentLevel+1)))]; %#ok<AGROW>
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
        scalarText = localEnsureScalarYAMLText(localSerializeValue(value, indentLevel+1, true));
        lines(end+1,1) = indent + key + ": " + scalarText; %#ok<AGROW>
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
        if isempty(value) || (isscalar(value) && isempty(fieldnames(value)))
            lines(end+1,1) = indent + "- {}"; %#ok<AGROW>
        elseif ~isscalar(value)
            lines = [lines; splitlines(string(localSerializeStructSequence( ...
                value, indentLevel)))]; %#ok<AGROW>
        else
            lines(end+1,1) = indent + "-"; %#ok<AGROW>
            lines = [lines; splitlines(string(localSerializeStruct(value, indentLevel+1)))]; %#ok<AGROW>
        end
    else
        lines(end+1,1) = indent + "- " + localEnsureScalarYAMLText(localSerializeValue(value, indentLevel+1, true)); %#ok<AGROW>
    end
end
txt = strjoin(lines, newline);
end

function txt = localSerializeStructSequence(s, indentLevel)
items = cell(numel(s), 1);
for i = 1:numel(s)
    items{i} = s(i);
end
txt = localSerializeCell(items, indentLevel);
end

function txt = localEnsureScalarYAMLText(txt)
txt = string(txt);
if isempty(txt)
    txt = "null";
elseif ~isscalar(txt)
    txt = "[" + strjoin(txt(:).', ", ") + "]";
end
end

function txt = localScalarString(v, ~)
v = string(v);
if ~isscalar(v)
    error("sixgr:lls6g:config:NonScalarStringToken", ...
        "String YAML token helper requires a scalar value.");
end
if ismissing(v)
    txt = "null";
elseif strlength(v) == 0
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
if isa(v,"double")
    txt = string(sprintf('%.17g',v));
elseif isa(v,"single")
    txt = string(sprintf('%.9g',v));
else
    txt = string(v);
end
if contains(lower(txt), "e") && ~contains(txt, ".")
    txt = regexprep(txt, '^([+-]?\d+)e([+-]?\d+)$', '$1.0e$2');
end
end
