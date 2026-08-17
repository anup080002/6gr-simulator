function value = canonicalPath(pathValue)
%CANONICALPATH Lexically normalize an absolute path without filesystem I/O.
% Java File.getCanonicalPath fails on some valid Windows extended-length
% paths.  This helper deliberately performs only absolute/./.. lexical
% normalization, so it is safe for long paths and paths that do not exist.

raw = strtrim(string(pathValue));
if ismissing(raw) || strlength(raw) == 0
    value = "";
    return;
end
raw = replace(raw, "/", string(filesep));
text = char(raw);

if ispc
    if startsWith(string(text), "\\?\UNC\", "IgnoreCase", true)
        text = char("\\" + extractAfter(string(text), 8));
    elseif startsWith(string(text), "\\?\", "IgnoreCase", true)
        text = text(5:end);
    end
end

if ~localLooksAbsolute(text)
    text = fullfile(pwd, text);
end

[root, tail] = localRootAndTail(text);
tokens = regexp(tail, '[\\/]+', 'split');
stack = cell(0, 1);
for i = 1:numel(tokens)
    token = tokens{i};
    if isempty(token) || strcmp(token, '.')
        continue;
    end
    if strcmp(token, '..')
        if ~isempty(stack)
            stack(end) = [];
        end
        continue;
    end
    stack{end + 1, 1} = token; %#ok<AGROW>
end

if isempty(stack)
    value = string(root);
else
    value = string([root strjoin(stack, filesep)]);
end
end

function [root, tail] = localRootAndTail(text)
if ispc && ~isempty(regexp(text, '^[A-Za-z]:[\\/]', 'once'))
    root = [text(1:2) filesep];
    tail = text(4:end);
    return;
end
if ispc && (startsWith(string(text), "\\") || startsWith(string(text), "//"))
    parts = regexp(text(3:end), '[\\/]+', 'split');
    parts = parts(~cellfun(@isempty, parts));
    if numel(parts) >= 2
        root = [filesep filesep parts{1} filesep parts{2} filesep];
        tail = strjoin(parts(3:end), filesep);
    else
        root = [filesep filesep];
        tail = strjoin(parts, filesep);
    end
    return;
end
if startsWith(string(text), "/")
    root = filesep;
    tail = text(2:end);
    return;
end
root = '';
tail = text;
end

function tf = localLooksAbsolute(text)
tf = ~isempty(regexp(text, '^[A-Za-z]:[\\/]', 'once')) || ...
    startsWith(string(text), "\\") || startsWith(string(text), "/");
end
