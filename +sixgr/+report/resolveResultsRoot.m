function p = resolveResultsRoot(inPath)
%RESOLVERESULTSROOT Anchor campaign results under the repo-local results tree.
%
% Relative paths are always interpreted from the repository root, never the
% caller's current working directory. Absolute paths are accepted when they
% live under <repo>/results.  Regression workers may additionally opt into
% one externally configured scratch tree through
% SIXGR_REGRESSION_SCRATCH_ROOT; no other external path is accepted.

repoRoot = localRepoRoot();
repoResults = localNormalizePath(fullfile(repoRoot, "results"));

p = localNormalizePath(inPath);
if strlength(string(p)) == 0
    p = repoResults;
    return;
end

if localIsAbsolutePath(p)
    regressionScratch = localRegressionScratchRoot();
    if localPathStartsWith(p, repoResults) || ...
            (strlength(string(regressionScratch)) > 0 && ...
            localPathStartsWith(p, regressionScratch))
        return;
    end
    p = repoResults;
    return;
end

if strcmpi(p, ".") || strcmpi(p, filesep)
    p = repoResults;
    return;
end

if strcmpi(p, "results") || startsWith(lower(string(p)), lower("results" + filesep))
    p = localNormalizePath(fullfile(repoRoot, p));
else
    p = localNormalizePath(fullfile(repoResults, p));
end
end

function root = localRegressionScratchRoot()
root = localNormalizePath(getenv("SIXGR_REGRESSION_SCRATCH_ROOT"));
if strlength(string(root)) == 0 || ~localIsAbsolutePath(root)
    root = "";
end
end

function root = localRepoRoot()
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
root = localNormalizePath(root);
end

function tf = localIsAbsolutePath(p)
p = char(string(p));
if ispc
    tf = ~isempty(regexp(p, '^[A-Za-z]:[\\/]', 'once')) || startsWith(p, "\\");
else
    tf = startsWith(p, "/");
end
end

function tf = localPathStartsWith(pathValue, rootValue)
pathValue = char(string(localNormalizePath(pathValue)));
rootValue = char(string(localNormalizePath(rootValue)));

if ispc
    pathCmp = lower(pathValue);
    rootCmp = lower(rootValue);
else
    pathCmp = pathValue;
    rootCmp = rootValue;
end

tf = strcmp(pathCmp, rootCmp) || startsWith(pathCmp, [rootCmp filesep]);
end

function p = localNormalizePath(inPath)
p = char(string(strtrim(string(inPath))));
if strlength(string(p)) == 0
    p = "";
    return;
end

p = strrep(p, "/", filesep);
p = strrep(p, "\", filesep);

while contains(p, [filesep filesep])
    p = strrep(p, [filesep filesep], filesep);
end

if strlength(string(p)) > 1 && endsWith(p, filesep) && ~(ispc && numel(p) == 3 && p(2) == ':')
    p = extractBefore(string(p), strlength(string(p)));
    p = char(p);
end
end
