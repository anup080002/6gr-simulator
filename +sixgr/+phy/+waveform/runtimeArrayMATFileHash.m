function [digest,evidence]=runtimeArrayMATFileHash(archive,name,maxElements,checkBlock)
%RUNTIMEARRAYMATFILEHASH Exact runtime-array hash with bounded MAT-file reads.
% Same class/dimensions/real-then-imaginary byte stream as runtimeArray.
% Every element is checked; this is not a sampled hash or a preview.
arguments
    archive (1,1) matlab.io.MatFile
    name (1,1) string
    maxElements (1,1) double {mustBeInteger,mustBePositive} = 1048576
    checkBlock = []
end
assert(isvarname(char(name)) && (isempty(checkBlock) || isa(checkBlock,'function_handle')), ...
    'sixgr:channel:ChannelArtifactArrayMismatch');
assert(H5F.is_hdf5(archive.Properties.Source)>0, ...
    'sixgr:channel:ChannelArtifactStreamingFormat', ...
    'Bounded coefficient reads require v7.3; never silently load a whole v7 variable.');
variable=char(name); % MatFile SUBSREF requires char even on releases accepting string field names elsewhere.
inventory=whos(archive,char(name));
assert(isscalar(inventory) && any(string(inventory.class)==["double","single"]) && ...
    ~inventory.sparse,'sixgr:channel:ChannelArtifactArrayMismatch', ...
    'Channel coefficients must be a real stored floating-point array.');
dims=size(archive,char(name));
assert(all(dims>0),'sixgr:channel:ChannelArtifactArrayMismatch');
axis=find(cumprod(dims)>maxElements,1);
if isempty(axis), axis=numel(dims); end
inner=prod(dims(1:axis-1));
step=max(1,floor(maxElements/inner));
outerCount=prod(dims(axis+1:end));
md=javaMethod('getInstance','java.security.MessageDigest','SHA-256');
md.update(typecast(uint8(char("runtime_array:"+string(inventory.class)+":")),'int8'));
md.update(typecast(typecast(uint64(dims),'uint8'),'int8'));
blocks=0; peak=0; finite=true;
for component=1:2
    for outer=0:outerCount-1
        indices=cell(1,numel(dims));
        for d=1:axis-1, indices{d}=1:dims(d); end
        value=outer;
        for d=axis+1:numel(dims)
            indices{d}=mod(value,dims(d))+1;
            value=floor(value/dims(d));
        end
        for first=1:step:dims(axis)
            indices{axis}=first:min(first+step-1,dims(axis));
            piece=archive.(variable)(indices{:});
            assert(numel(piece)<=maxElements,'sixgr:channel:ChannelArtifactReadBudget');
            if component==1
                finite=finite && all(isfinite(piece),'all');
                if ~isempty(checkBlock), checkBlock(piece,indices); end
                bytes=typecast(double(real(piece(:))),'uint8');
            else
                bytes=typecast(double(imag(piece(:))),'uint8');
            end
            md.update(typecast(bytes,'int8'));
            blocks=blocks+1; peak=max(peak,numel(piece));
        end
    end
end
digest=lower(string(reshape(dec2hex(typecast(md.digest(),'uint8'),2).',1,[])));
evidence=struct('Dimensions',dims,'Class',string(inventory.class), ...
    'ElementCount',prod(dims),'AllFinite',finite,'BlocksRead',blocks, ...
    'MaxBlockElements',peak,'ReadBudgetElements',maxElements,'FullArrayLoaded',false);
end
