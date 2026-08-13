function canonicalizePDF(path)
%CANONICALIZEPDF Remove volatile export metadata without rasterizing vectors.
% MATLAB exportgraphics writes the wall-clock time and a fresh trailer ID
% into every PDF. Replacing those fields with same-length canonical values
% preserves every cross-reference byte offset and all vector page content.
path=string(path);
fid=fopen(path,"rb");
if fid<0
    error("sixgr:csi:PDFReadFailed","Cannot open PDF for canonicalization: %s.",path);
end
cleanup=onCleanup(@() localClose(fid)); %#ok<NASGU>
bytes=fread(fid,Inf,"*uint8");
text=char(bytes.');

datePattern='/CreationDate \(D:\d{14}[+-]\d{2}''\d{2}''\)';
modPattern='/ModDate \(D:\d{14}[+-]\d{2}''\d{2}''\)';
text=localReplaceExactlyOnce(text,datePattern, ...
    "/CreationDate (D:20000101000000+00'00')","CreationDate",path);
text=localReplaceExactlyOnce(text,modPattern, ...
    "/ModDate (D:20000101000000+00'00')","ModDate",path);

% The XMP packet repeats the same volatile timestamps and adds a UUID.
% All replacements preserve byte length, so the PDF xref table remains
% valid and the vector content streams are untouched.
xmpDatePattern='20\d{2}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2}';
[xmpStart,xmpEnd]=regexp(text,xmpDatePattern);
for k=1:numel(xmpStart)
    replacement='2000-01-01T00:00:00+00:00';
    if xmpEnd(k)-xmpStart(k)+1~=numel(replacement)
        error("sixgr:csi:PDFMetadataLengthMismatch", ...
            "Canonical XMP timestamp must preserve PDF byte length.");
    end
    text(xmpStart(k):xmpEnd(k))=replacement;
end
uuidPattern='uuid:[0-9A-Fa-f-]{36}';
[uuidStart,uuidEnd]=regexp(text,uuidPattern);
for k=1:numel(uuidStart)
    text(uuidStart(k):uuidEnd(k))='uuid:00000000-0000-0000-0000-000000000000';
end

[idStart,idEnd]=regexp(text,'/ID \[ <[0-9A-Fa-f]+> <[0-9A-Fa-f]+> \]');
if numel(idStart)~=1
    error("sixgr:csi:PDFTrailerIDContract", ...
        "Expected exactly one PDF trailer ID in %s; found %d.",path,numel(idStart));
end
segment=text(idStart:idEnd);
[hexStart,hexEnd]=regexp(segment,'<[0-9A-Fa-f]+>');
if numel(hexStart)~=2
    error("sixgr:csi:PDFTrailerIDContract", ...
        "Expected two hexadecimal PDF trailer IDs in %s.",path);
end
for k=1:2
    first=hexStart(k)+1;
    last=hexEnd(k)-1;
    segment(first:last)=repmat('0',1,last-first+1);
end
text(idStart:idEnd)=segment;

clear cleanup;
fid=fopen(path,"wb");
if fid<0
    error("sixgr:csi:PDFWriteFailed","Cannot rewrite canonical PDF: %s.",path);
end
cleanup=onCleanup(@() localClose(fid)); %#ok<NASGU>
count=fwrite(fid,uint8(text),"uint8");
if count~=numel(bytes)
    error("sixgr:csi:PDFWriteFailed", ...
        "Short write while canonicalizing %s.",path);
end

function localClose(fid)
if isnumeric(fid) && isscalar(fid) && fid>=0
    try, fclose(fid); catch, end
end
end
end

function text=localReplaceExactlyOnce(text,pattern,replacement,label,path)
[first,last]=regexp(text,pattern);
if numel(first)~=1
    error("sixgr:csi:PDFMetadataContract", ...
        "Expected exactly one %s entry in %s; found %d.",label,path,numel(first));
end
if last-first+1~=strlength(replacement)
    error("sixgr:csi:PDFMetadataLengthMismatch", ...
        "Canonical %s metadata must preserve the PDF byte length.",label);
end
text(first:last)=char(replacement);
end
