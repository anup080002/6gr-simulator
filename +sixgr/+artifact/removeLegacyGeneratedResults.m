function inventory = removeLegacyGeneratedResults(resultsRoot, varargin)
%REMOVELEGACYGENERATEDRESULTS Remove obsolete generated CSV/image files.
%
% This migration utility is intentionally restricted to the repository's
% exact results/ root.  It does not touch the checked-in artifacts/ evidence
% or tests/vectors contracts.  Use Execute=true only after inspecting the
% returned dry-run inventory.

parser = inputParser();
parser.addParameter("Execute", false, @(x) islogical(x) && isscalar(x));
parser.parse(varargin{:});
execute = parser.Results.Execute;

repositoryRoot = sixgr.artifact.ContractCatalog.repositoryRoot();
expectedRoot = localCanonical(fullfile(repositoryRoot, "results"));
if nargin < 1 || strlength(string(resultsRoot)) == 0
    resultsRoot = expectedRoot;
end
resultsRoot = localCanonical(resultsRoot);
if ~strcmpi(resultsRoot, expectedRoot)
    error("sixgr:artifact:UnsafeLegacyCleanupRoot", ...
        "Legacy cleanup is restricted to exact results root %s; received %s.", ...
        expectedRoot, resultsRoot);
end
if ~isfolder(resultsRoot)
    inventory = localEmptyInventory();
    return;
end

extensions = [".csv", ".png", ".jpg", ".jpeg", ".svg"];
listing = dir(fullfile(resultsRoot, "**", "*"));
listing = listing(~[listing.isdir]);
paths = strings(0, 1);
relative = strings(0, 1);
bytes = zeros(0, 1);
fileExtensions = strings(0, 1);
for index = 1:numel(listing)
    absolutePath = string(fullfile(listing(index).folder, listing(index).name));
    [~, ~, extension] = fileparts(absolutePath);
    if ~any(lower(string(extension)) == extensions)
        continue;
    end
    canonical = localCanonical(absolutePath);
    localAssertChild(canonical, resultsRoot);
    paths(end + 1, 1) = canonical; %#ok<AGROW>
    relative(end + 1, 1) = extractAfter(canonical, ... %#ok<AGROW>
        strlength(resultsRoot) + strlength(string(filesep)));
    bytes(end + 1, 1) = listing(index).bytes; %#ok<AGROW>
    fileExtensions(end + 1, 1) = lower(string(extension)); %#ok<AGROW>
end
deleted = false(numel(paths), 1);
if execute
    for index = 1:numel(paths)
        localAssertChild(paths(index), resultsRoot);
        delete(paths(index));
        deleted(index) = ~isfile(paths(index));
    end
end
inventory = table(paths, relative, fileExtensions, bytes, deleted, ...
    'VariableNames', {'AbsolutePath', 'RelativePath', 'Extension', 'Bytes', 'Deleted'});
inventory = sortrows(inventory, "RelativePath");
end

function localAssertChild(pathValue, ownerRoot)
prefix = string(ownerRoot) + string(filesep);
if string(pathValue) == string(ownerRoot) || ...
        ~startsWith(string(pathValue), prefix, "IgnoreCase", ispc)
    error("sixgr:artifact:UnsafeLegacyCleanupTarget", ...
        "Refusing to delete a generated artifact outside %s: %s", ...
        ownerRoot, pathValue);
end
end

function value = localCanonical(pathValue)
value = char(java.io.File(char(string(pathValue))).getCanonicalPath());
end

function inventory = localEmptyInventory()
inventory = table(strings(0, 1), strings(0, 1), strings(0, 1), ...
    zeros(0, 1), false(0, 1), 'VariableNames', ...
    {'AbsolutePath', 'RelativePath', 'Extension', 'Bytes', 'Deleted'});
end
