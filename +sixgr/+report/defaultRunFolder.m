function runFolder = defaultRunFolder(resultsRoot, varargin)
%DEFAULTRUNFOLDER Build a stable, human-readable run folder under /results.
%
%   runFolder = sixgr.report.defaultRunFolder(resultsRoot, "Bucket", "lls",
%       "Profile", "truth_validation")
%
% Results are written to:
%   <resultsRoot>/<bucket>/<profile>/current
%
% If resultsRoot already ends with the requested bucket and/or profile, the
% repeated path segments are not duplicated. Existing "current" folders are
% cleaned before reuse so repeated runs do not accumulate stale artifacts.

ip = inputParser;
ip.addRequired("resultsRoot", @(x)ischar(x) || isstring(x));
ip.addParameter("Bucket", "sls", @(x)ischar(x) || isstring(x));
ip.addParameter("Profile", "campaign", @(x)ischar(x) || isstring(x));
ip.addParameter("Leaf", "current", @(x)ischar(x) || isstring(x));
ip.addParameter("CleanExisting", true, @(x)islogical(x) || (isnumeric(x) && isscalar(x)));
ip.parse(resultsRoot, varargin{:});
opt = ip.Results;

root = sixgr.report.resolveResultsRoot(char(string(opt.resultsRoot)));
bucket = localSanitizeToken(opt.Bucket, "sls");
profile = localSanitizeToken(opt.Profile, "campaign");
leaf = localSanitizeToken(opt.Leaf, "current");

runFolder = localComposeRunFolder(root, bucket, profile, leaf);
if logical(opt.CleanExisting)
    localResetRunFolder(runFolder, root);
else
    sixgr.util.ensureFolder(runFolder);
end
end

function runFolder = localComposeRunFolder(root, bucket, profile, leaf)
root = localNormalizePath(root);
if localEndsWithSegments(root, [bucket profile])
    runFolder = fullfile(root, leaf);
elseif localEndsWithSegments(root, bucket)
    runFolder = fullfile(root, profile, leaf);
else
    runFolder = fullfile(root, bucket, profile, leaf);
end
runFolder = localNormalizePath(runFolder);
end

function localResetRunFolder(runFolder, root)
runFolder = localNormalizePath(runFolder);
root = localNormalizePath(root);

if isfolder(runFolder) && localPathStartsWith(runFolder, root) && ~strcmpi(runFolder, root)
    try
        rmdir(runFolder, "s");
    catch
    end
end
sixgr.util.ensureFolder(runFolder);
end

function tok = localSanitizeToken(inTok, fallback)
tok = lower(strtrim(char(string(inTok))));
if strlength(string(tok)) == 0
    tok = char(string(fallback));
end
tok = regexprep(tok, '[^a-z0-9]+', '_');
tok = regexprep(tok, '_+', '_');
tok = regexprep(tok, '^_+|_+$', '');
if strlength(string(tok)) == 0
    tok = char(string(fallback));
end
end

function tf = localEndsWithSegments(pathValue, segments)
pathParts = localPathParts(pathValue);
segParts = string(segments);
segParts = segParts(strlength(segParts) > 0);
if isempty(segParts)
    tf = true;
    return;
end
if numel(pathParts) < numel(segParts)
    tf = false;
    return;
end
tail = pathParts(end-numel(segParts)+1:end);
if ispc
    tf = all(strcmpi(tail, segParts));
else
    tf = all(strcmp(tail, segParts));
end
end

function parts = localPathParts(p)
p = string(localNormalizePath(p));
p = replace(p, "\", "/");
p = regexprep(p, "/+", "/");
parts = split(p, "/");
parts = parts(strlength(parts) > 0);
end

function tf = localPathStartsWith(pathValue, rootValue)
pathValue = localNormalizePath(pathValue);
rootValue = localNormalizePath(rootValue);
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
    p = char(extractBefore(string(p), strlength(string(p))));
end
end
