function p = resolveResultsRoot(inPath)
%RESOLVERESULTSROOT Resolve a repository or explicitly authorized evidence root.
%
% Relative paths are always interpreted from the repository root, never the
% caller's current working directory. Absolute paths are accepted when they
% live under <repo>/results or the explicit <repo>/logs diagnostic tree.
% An absolute production evidence directory can be explicitly authorized by
% SIXGR_RESULTS_ROOT (also used by the WebGUI). Only that directory and its
% descendants are admitted; relative paths retain their legacy repo meaning.
% Regression workers may additionally opt into
% one externally configured scratch tree through
% SIXGR_REGRESSION_SCRATCH_ROOT; no other external path is accepted.

repoRoot = localRepoRoot();
repoResults = localNormalizePath(fullfile(repoRoot, "results"));
repoLogs = localNormalizePath(fullfile(repoRoot, "logs"));

p = localNormalizePath(inPath);
if strlength(string(p)) == 0
    p = repoResults;
    return;
end

if localIsAbsolutePath(p)
    % Resolve dot segments before containment checks: callers may later
    % clean a run leaf, so lexical prefix matching alone is insufficient.
    p = localNormalizePath(char(java.io.File(p).getCanonicalPath()));
    productionRoot = localProductionResultsRoot(repoRoot);
    regressionScratch = localRegressionScratchRoot();
    if localPathStartsWith(p, repoResults) || localPathStartsWith(p, repoLogs) || ...
            (strlength(string(productionRoot)) > 0 && ...
            localPathStartsWith(p, productionRoot)) || ...
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

if strcmpi(p, "logs") || startsWith(lower(string(p)), lower("logs" + filesep))
    p = localNormalizePath(char(java.io.File(fullfile(repoRoot,p)).getCanonicalPath()));
    if ~localPathStartsWith(p,repoLogs), p=repoResults; end
elseif strcmpi(p, "results") || startsWith(lower(string(p)), lower("results" + filesep))
    p = localNormalizePath(fullfile(repoRoot, p));
else
    p = localNormalizePath(fullfile(repoResults, p));
end
end

function root = localProductionResultsRoot(repoRoot)
root = localNormalizePath(getenv('SIXGR_RESULTS_ROOT'));
if strlength(string(root)) == 0, return; end
assert(localIsAbsolutePath(root),'sixgr:report:InvalidExternalResultsRoot', ...
    'SIXGR_RESULTS_ROOT must be an absolute evidence directory.');
rootFile = java.io.File(root).getCanonicalFile();
root = localNormalizePath(char(rootFile.getPath()));
% A drive root or an ancestor of the source tree is too broad an allowlist
% for downstream run-leaf cleanup. An explicit results child is required.
assert(~isempty(char(rootFile.getParent())) && ~localPathStartsWith(repoRoot,root), ...
    'sixgr:report:InvalidExternalResultsRoot', ...
    'SIXGR_RESULTS_ROOT must not be a filesystem root or contain the source checkout.');
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
