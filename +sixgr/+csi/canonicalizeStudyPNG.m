function canonicalizeStudyPNG(path)
%CANONICALIZEPNG Remove run-dependent ancillary chunks from a PNG file.
%
% MATLAB's PNG writers include tIME and, depending on the renderer, text
% metadata. Those chunks change the file SHA-256 even when every decoded
% raster pixel is identical. Preserve the image, palette, transparency and
% physical-resolution chunks, while removing only volatile metadata.
arguments
    path (1,1) string
end
bytes=localRead(path);
signature=uint8([137 80 78 71 13 10 26 10]).';
if numel(bytes)<8 || ~isequal(bytes(1:8),signature)
    error("sixgr:csi:InvalidPNG","Not a valid PNG file: %s.",path);
end
out=bytes(1:8); position=9; sawEnd=false;
volatile=["tIME","tEXt","zTXt","iTXt","eXIf"];
while position<=numel(bytes)
    if position+11>numel(bytes)
        error("sixgr:csi:TruncatedPNG","Truncated PNG chunk header: %s.",path);
    end
    lengthBytes=double(bytes(position:position+3));
    count=lengthBytes(1)*16777216+lengthBytes(2)*65536+ ...
        lengthBytes(3)*256+lengthBytes(4);
    chunkEnd=position+11+count;
    if chunkEnd>numel(bytes)
        error("sixgr:csi:TruncatedPNG","Truncated PNG chunk payload: %s.",path);
    end
    type=string(char(bytes(position+4:position+7).'));
    if ~ismember(type,volatile)
        out=[out;bytes(position:chunkEnd)]; %#ok<AGROW>
    end
    position=chunkEnd+1;
    if type=="IEND", sawEnd=true; break; end
end
if ~sawEnd
    error("sixgr:csi:MissingPNGIEND","PNG IEND chunk is missing: %s.",path);
end
folder=fileparts(char(path)); temp=string(tempname(folder))+".png";
cleanup=onCleanup(@()localDelete(temp)); %#ok<NASGU>
fid=fopen(temp,"w");
if fid<0, error("sixgr:csi:PNGWriteFailed","Cannot write %s.",temp); end
closeFile=onCleanup(@()fclose(fid)); %#ok<NASGU>
written=fwrite(fid,out,"uint8");
if written~=numel(out)
    error("sixgr:csi:PNGWriteFailed","Short write while canonicalizing %s.",path);
end
clear closeFile;
[ok,message]=movefile(temp,path,"f");
if ~ok, error("sixgr:csi:PNGWriteFailed","%s",message); end
end

function bytes=localRead(path)
fid=fopen(path,"r");
if fid<0, error("sixgr:csi:PNGReadFailed","Cannot read %s.",path); end
cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
bytes=fread(fid,inf,"*uint8");
end

function localDelete(path)
if exist(path,"file")==2, delete(path); end
end
