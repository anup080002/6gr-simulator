function digest=evidenceArraySHA256(value)
% Hash type, dimensions, real/complex identity and native numeric bits.
assert((isnumeric(value) || islogical(value)) && ~issparse(value), ...
    'sixgr:calibration:ArrayPoolType','Require dense numeric/logical evidence.');
metadata=struct('Class',class(value),'Size',size(value), ...
    'IsReal',isreal(value),'ByteOrder','little_endian');
realBytes=canonicalBytes(real(value));
metadata.RealSHA256=sixgr.util.sha256Hex(realBytes);
metadata.ImaginarySHA256="";
if ~isreal(value)
    metadata.ImaginarySHA256=sixgr.util.sha256Hex( ...
        canonicalBytes(imag(value)));
end
digest=string(sixgr.util.sha256Hex(uint8(unicode2native(jsonencode(metadata),'UTF-8'))));
end

function bytes=canonicalBytes(value)
if islogical(value)
    bytes=uint8(value(:));
else
    [~,~,endian]=computer;
    if endian=='B', value=swapbytes(value); end
    bytes=typecast(reshape(value,[],1),'uint8');
end
end
