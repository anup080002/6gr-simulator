function hash=csiSelectionArchiveDigest(value)
%CSISELECTIONARCHIVEDIGEST Original v1 typed/shape/exact-byte archive seal.
% Hash classes/shapes and exact numeric bytes, including imaginary values.
% Never pass a complex struct directly through JSON (which loses its phase).
d=struct('Class',string(class(value)),'Shape',size(value));
if isnumeric(value)
    assert(~issparse(value),'sixgr:truth:CSISelectionArchiveSourceType','Retain full explicit numerical operands.');
    d.RealBytesSHA256=sixgr.util.sha256Hex(typecast(real(value(:)),'uint8'));
    d.ImagBytesSHA256=sixgr.util.sha256Hex(typecast(imag(value(:)),'uint8'));
elseif islogical(value)
    d.BytesSHA256=sixgr.util.sha256Hex(uint8(value(:)));
elseif ischar(value)
    d.BytesSHA256=sixgr.util.sha256Hex(typecast(uint16(value(:)),'uint8'));
elseif isstring(value)
    d.Missing=ismissing(value); text=value; text(d.Missing)=""; d.Values=text;
elseif iscell(value)
    children=strings(size(value));
    for k=1:numel(value), children(k)=sixgr.truth.csiSelectionArchiveDigest(value{k}); end
    d.Children=children;
elseif isstruct(value)
    fields=sort(string(fieldnames(value))); children=strings(numel(value),numel(fields));
    for k=1:numel(value)
        for j=1:numel(fields), children(k,j)=sixgr.truth.csiSelectionArchiveDigest(value(k).(fields(j))); end
    end
    d.Fields=fields; d.Children=children;
else
    error('sixgr:truth:CSISelectionArchiveSourceType','Unsupported retained operand class %s.',class(value));
end
hash=sixgr.util.sha256Hex(jsonencode(d));
end
