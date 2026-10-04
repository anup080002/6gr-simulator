function sources=grantSourceIdentity()
%GRANTSOURCEIDENTITY Shared source/environment authority for grant calibration.
% No cache: collection and installation must detect edits in a live session.
root=fileparts(fileparts(fileparts(mfilename('fullpath'))));
files=dir(fullfile(root,'+sixgr','**','*.m'));
catalogs=[dir(fullfile(root,'simulator','configs','schema','*.yaml')); ...
    dir(fullfile(root,'simulator','configs','schema','*.json'))];
paths=sort([string(fullfile({files.folder},{files.name})).'; ...
    string(fullfile({catalogs.folder},{catalogs.name})).'; ...
    string(fullfile(root,'run_grant_calibration.m'))]);
hashes=strings(size(paths));
for k=1:numel(paths), hashes(k)=sixgr.csi.studyFileSHA256(paths(k)); end
sources=struct('Paths',erase(paths,string(root)+string(filesep)), ...
    'SHA256',hashes,'MATLAB',version,'Toolboxes',ver);
end
