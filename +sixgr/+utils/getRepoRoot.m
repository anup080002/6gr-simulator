function root = getRepoRoot()
%GETREPOROOT Return the repository root for Prompt 9 compatibility helpers.

root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end
