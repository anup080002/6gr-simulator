function pOut = ensureDir(p)
%ENSUREDIR Create directories needed for a run and for exports.
%
%   out = sixgr.util.ensureDir(runFolder)
%     - ensures runFolder exists and creates:
%         runFolder/mat, runFolder/csv, runFolder/fig, runFolder/logs
%
%   out = sixgr.util.ensureDir(filePathWithExt)
%     - ensures parent folder exists (no run-tree creation).
%
%   out = sixgr.util.ensureDir(someSubFolder)
%     - if subfolder name is one of: mat,csv,fig,logs then only that folder
%       is created (no nested run-tree creation).

arguments
    p {mustBeTextScalar}
end

pOut = char(p);
[folder, name, ext] = fileparts(pOut);

% If p looks like a file path, create its parent folder only.
if ~isempty(ext)
    if ~isempty(folder) && ~isfolder(folder)
        mkdir(folder);
    end
    return;
end

% p is a directory path
if ~isfolder(pOut)
    mkdir(pOut);
end

leaf = lower(string(name));
isLeaf = any(leaf == ["mat","csv","fig","logs"]);

% If it's not a leaf folder, treat it as a run folder and create the tree
if ~isLeaf
    localMk(fullfile(pOut,"mat"));
    localMk(fullfile(pOut,"csv"));
    localMk(fullfile(pOut,"fig"));
    localMk(fullfile(pOut,"logs"));
end

end

function localMk(d)
if ~isfolder(d)
    mkdir(d);
end
end

function mustBeTextScalar(x)
if ~(ischar(x) || (isstring(x) && isscalar(x)))
    error("sixgr:util:ensureDir:BadType","Input must be a char vector or string scalar.");
end
end
