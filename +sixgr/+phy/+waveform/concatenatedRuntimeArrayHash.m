function [digest,evidence]=concatenatedRuntimeArrayHash(parts,chunkElements)
%CONCATENATEDRUNTIMEARRAYHASH Exact runtimeArray(cat(1,parts{:})) without CAT.
% Retain the historical class/dimensions/real-double/imaginary-double byte
% stream. MATLAB is column-major: concatenating segment byte streams would
% give the WRONG digest for multi-column path-gain tensors.
arguments
    parts cell
    chunkElements (1,1) double {mustBeFinite,mustBeInteger,mustBePositive} = 262144
end
assert(isvector(parts) && ~isempty(parts) && ...
    all(cellfun(@(v)isnumeric(v) || islogical(v),parts)) && ...
    all(cellfun(@(v)~issparse(v),parts)), ...
    'WAVEFORM:InvalidConcatenatedArrayParts','Use dense numeric/logical executed segments.');
parts=parts(:);
prototype=parts{1}; shape=size(prototype); rows=zeros(numel(parts),1);
for k=1:numel(parts)
    actual=size(parts{k});
    assert(strcmp(class(parts{k}),class(prototype)) && ...
        numel(actual)==numel(shape) && isequal(actual(2:end),shape(2:end)), ...
        'WAVEFORM:ConcatenatedArrayShapeMismatch', ...
        'Segments must preserve class and every non-time dimension; implicit casts are forbidden.');
    rows(k)=actual(1);
end
shape(1)=sum(rows);
count=prod(shape);
assert(count<=flintmax,'WAVEFORM:ConcatenatedArrayIndexRange','Linear indices must be represented exactly.');
md=javaMethod('getInstance','java.security.MessageDigest','SHA-256');
header=uint8(char("runtime_array:"+string(class(prototype))+":"));
md.update(typecast(header(:),'int8'));
dimensions=typecast(uint64(shape),'uint8');
md.update(typecast(dimensions(:),'int8'));
limits=[0;cumsum(rows)];
maxWorking=0;
for component=1:2
    for first=1:chunkElements:count
        last=min(count,first+chunkElements-1);
        index=(first-1:last-1).';
        column=floor(index/shape(1));
        timeRow=mod(index,shape(1));
        % Hash components separately. No complex tensor or whole byte copy
        % is allocated, even if all retained physical segments are complex.
        values=zeros(numel(index),1);
        for k=1:numel(parts)
            take=timeRow>=limits(k) & timeRow<limits(k+1);
            if ~any(take), continue; end
            source=timeRow(take)-limits(k)+1+column(take)*rows(k);
            piece=parts{k}(source);
            if component==1
                values(take)=double(real(piece));
            else
                values(take)=double(imag(piece));
            end
        end
        bytes=typecast(values,'uint8');
        md.update(typecast(bytes(:),'int8'));
        maxWorking=max(maxWorking,numel(index));
    end
end
digest=lower(string(reshape(dec2hex(typecast(md.digest(),'uint8'),2).',1,[])));
evidence=struct('Source',"exact_column_major_virtual_time_concatenation_runtime_array_hash", ...
    'Dimensions',shape,'ElementCount',count,'SegmentCount',numel(parts), ...
    'FullConcatenationAllocated',false,'MaximumWorkingElementCount',maxWorking, ...
    'WorkingElementLimit',chunkElements,'AdditionalChannelExecutions',0);
end
