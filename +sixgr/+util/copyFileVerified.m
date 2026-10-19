function receipt = copyFileVerified(source, target, expectedSHA256)
%COPYFILEVERIFIED Publish exact file bytes through a sibling temporary file.
% The source is never changed. A failed copy/hash check leaves the previous
% destination intact. This is byte transport, not a table/data reconstruction.
arguments
    source (1,1) string
    target (1,1) string
    expectedSHA256 (1,1) string
end
source=sixgr.util.canonicalPath(source);
target=sixgr.util.canonicalPath(target);
assert(strlength(source)>0 && strlength(target)>0 && ...
    ~strcmp(source,target) && ~(ispc && strcmpi(source,target)), ...
    'sixgr:util:VerifiedCopy:InvalidTarget','Source and destination must be distinct nonempty paths.');
assert(~ismissing(expectedSHA256) && ...
    ~isempty(regexp(char(expectedSHA256),'^[0-9a-f]{64}$','once')), ...
    'sixgr:util:VerifiedCopy:HashRequired','Supply the expected SHA256 of the complete source file.');
assert(isfile(source),'sixgr:util:VerifiedCopy:MissingSource','Source file is missing: %s.',source);
assert(~isfolder(target),'sixgr:util:VerifiedCopy:InvalidTarget','Destination is a directory: %s.',target);
if isfile(target)
    sameFile=java.nio.file.Files.isSameFile(java.io.File(char(source)).toPath(), ...
        java.io.File(char(target)).toPath());
    assert(~sameFile,'sixgr:util:VerifiedCopy:InvalidTarget', ...
        'Destination aliases the source file through a link.');
end
folder=fileparts(target);
if ~isfolder(folder), mkdir(folder); end
temporary=string(tempname(folder))+".copy";
cleanup=onCleanup(@()localDeleteTemporary(temporary)); %#ok<NASGU>
[copied,message]=copyfile(source,temporary,'f');
assert(copied,'sixgr:util:VerifiedCopy:CopyFailed','Copy failed: %s.',message);
assert(string(sixgr.util.sha256File(temporary))==expectedSHA256 && ...
    string(sixgr.util.sha256File(source))==expectedSHA256, ...
    'sixgr:util:VerifiedCopy:HashMismatch', ...
    'Source changed or copied bytes differ from the expected source. Previous destination is unchanged.');
info=dir(temporary);
for attempt=1:12
    [published,message,identifier]=movefile(temporary,target,'f');
    if published, break; end
    if attempt<12, pause(min(.05*2^(attempt-1),1)); end
end
assert(published,'sixgr:util:VerifiedCopy:PublishFailed', ...
    'Cannot publish verified copy to %s (%s): %s.',target,identifier,message);
receipt=struct('SourcePath',source,'TargetPath',target, ...
    'SHA256',expectedSHA256,'ByteCount',double(info.bytes));
end

function localDeleteTemporary(path)
if isfile(path), delete(path); end
end
