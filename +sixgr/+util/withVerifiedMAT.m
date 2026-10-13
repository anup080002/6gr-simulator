function [result,evidence]=withVerifiedMAT(filePath,expectedSHA256,reader)
%WITHVERIFIEDMAT Read immutable archived bytes through a short local path.
% READER must finish all reads before returning; temporary paths are scoped
% to this call. Source/copy checks are streamed, not waveform-sized arrays.
arguments
    filePath (1,1) string
    expectedSHA256 (1,1) string
    reader (1,1) function_handle
end
assert(~ismissing(expectedSHA256) && ...
    ~isempty(regexp(char(expectedSHA256),'^[0-9a-f]{64}$','once')), ...
    'sixgr:util:VerifiedMATHashRequired','Supply the bound SHA-256 of the archived MAT bytes.');
source=sixgr.util.canonicalPath(filePath);
assert(isfile(source),'sixgr:util:VerifiedMATMissing','MAT archive does not exist: %s.',source);
assert(string(sixgr.util.sha256File(source))==expectedSHA256, ...
    'sixgr:util:VerifiedMATHashMismatch','MAT archive bytes differ from their bound SHA-256.');
readPath=source;
temporary="";
useReadback=ispc && strlength(source)>=248;
if useReadback
    temporary=string(tempname)+".mat";
    cleanup=onCleanup(@()localDelete(temporary)); %#ok<NASGU>
    [copied,message]=copyfile(source,temporary,'f');
    assert(copied,'sixgr:util:VerifiedMATCopyFailed','MAT readback copy failed: %s.',message);
    assert(string(sixgr.util.sha256File(temporary))==expectedSHA256, ...
        'sixgr:util:VerifiedMATReadbackHashMismatch','Short-path readback changed the archived bytes.');
    readPath=temporary;
end
result=reader(readPath);
assert(string(sixgr.util.sha256File(source))==expectedSHA256, ...
    'sixgr:util:VerifiedMATChangedDuringRead','MAT archive changed while it was read.');
evidence=struct('SourcePath',source,'VerifiedFileSHA256',expectedSHA256, ...
    'UsedShortReadback',useReadback,'TemporaryFilePath',temporary);
end

function localDelete(path)
if isfile(path), delete(path); end
end
