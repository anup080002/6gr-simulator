function evidence=writeTimeChunkedMATPayload(path,payload,variables)
% Lossless v7.3 storage for time-by-path-by-TX-by-RX captured arrays.
% Native SAVE writes the MAT header, metadata and numeric type templates.
% Only explicitly named top-level numeric datasets are then replaced with
% time-contiguous, shuffled gzip chunks. No coefficient is regenerated,
% quantized, decimated or converted to another precision.
% Caller owns atomic publication and final-file hashing; PATH must be new.
arguments
    path {mustBeTextScalar}
    payload (1,1) struct
    variables (1,:) string
end
assert(~isfile(path) && ~isempty(variables) && numel(unique(variables))==numel(variables) && ...
    all(isfield(payload,cellstr(variables))), ...
    'sixgr:util:InvalidTimeChunkedMATRequest','Use a new destination and distinct existing numeric fields.');
template=payload;
for name=variables
    value=payload.(name);
    assert((isa(value,'double') || isa(value,'single')) && ~issparse(value) && ...
        ~isempty(value) && ndims(value)<=4, ...
        'sixgr:util:InvalidTimeChunkedMATArray','Only nonempty full single/double arrays of at most four dimensions are supported.');
    shape=localSize(value);
    template.(name)=value(1:min(shape(1),2),1:min(shape(2),2), ...
        1:min(shape(3),2),1:min(shape(4),2));
    if ~isreal(value)
        % An initial all-real/zero slice must still describe a complex
        % dataset when later captured samples contain imaginary values.
        template.(name)=complex(real(template.(name)),imag(template.(name)));
    end
end
save(char(path),'-struct','template','-v7.3');
clear template
file=H5F.open(char(path),'H5F_ACC_RDWR','H5P_DEFAULT');
closeFile=onCleanup(@()H5F.close(file));
peak=0; count=0;
for name=variables
    [n,block]=localWrite(file,char(name),payload.(name));
    count=count+n; peak=max(peak,block);
end
H5F.flush(file,'H5F_SCOPE_GLOBAL');
clear closeFile
% Native readers must recognize the unchanged numeric class/shape/complexity.
inventory=whos('-file',char(path));
for name=variables
    value=payload.(name); item=inventory(strcmp({inventory.name},name));
    assert(isscalar(item),'sixgr:util:TimeChunkedMATInventoryMismatch');
    shape=item.size; shape(end+1:4)=1;
    assert(strcmp(item.class,class(value)) && ...
        isequal(shape,localSize(value)) && item.complex==~isreal(value), ...
        'sixgr:util:TimeChunkedMATInventoryMismatch','Native MATLAB must recognize every exact numeric variable.');
end
evidence=struct('NumericValuesChanged',false,'PrecisionChanged',false, ...
    'FullArrayReadback',false,'Variables',variables,'ElementCount',count, ...
    'MaxWriteBlockElements',peak,'Compression',"HDF5_shuffle_then_deflate_6", ...
    'ChunkAxis',"time_first_MATLAB_dimension");
end

function [count,peak]=localWrite(file,name,value)
old=H5D.open(file,['/' name]); closeOld=onCleanup(@()H5D.close(old));
type=H5D.get_type(old); closeType=onCleanup(@()H5T.close(type));
% Reuse the numeric datatype produced by native SAVE, including the exact
% real/imag compound representation. Do not invent a MAT datatype layout.
attribute=H5A.open(old,'MATLAB_class'); closeAttribute=onCleanup(@()H5A.close(attribute));
classType=H5A.get_type(attribute); closeClassType=onCleanup(@()H5T.close(classType));
classSpace=H5A.get_space(attribute); closeClassSpace=onCleanup(@()H5S.close(classSpace));
classValue=H5A.read(attribute);
assert(H5A.get_num_attrs(old)==1, ...
    'sixgr:util:UnsupportedNumericMATAttributes','Preserve new MATLAB numeric attributes explicitly before supporting this format.');
clear closeAttribute closeOld
H5L.delete(file,['/' name],'H5P_DEFAULT');
shape=localSize(value);
space=H5S.create_simple(4,fliplr(shape),[]); closeSpace=onCleanup(@()H5S.close(space));
properties=H5P.create('H5P_DATASET_CREATE'); closeProperties=onCleanup(@()H5P.close(properties));
chunk=min(shape,[2048 4 2 1]);
H5P.set_chunk(properties,fliplr(chunk));
H5P.set_shuffle(properties);
H5P.set_deflate(properties,6);
dataset=H5D.create(file,['/' name],type,space,'H5P_DEFAULT',properties,'H5P_DEFAULT');
closeDataset=onCleanup(@()H5D.close(dataset));
newAttribute=H5A.create(dataset,'MATLAB_class',classType,classSpace,'H5P_DEFAULT');
closeNewAttribute=onCleanup(@()H5A.close(newAttribute));
H5A.write(newAttribute,classType,classValue);
clear closeNewAttribute
peak=0; count=0;
for r=1:chunk(4):shape(4)
 for t=1:chunk(3):shape(3)
  for p=1:chunk(2):shape(2)
   for first=1:chunk(1):shape(1)
    start=[first p t r]; extent=min(chunk,shape-start+1);
    block=value(first:first+extent(1)-1,p:p+extent(2)-1, ...
        t:t+extent(3)-1,r:r+extent(4)-1);
    assert(all(isfinite(block),'all'),'sixgr:util:NonfiniteTimeChunkedMATArray', ...
        'Invalid channel coefficients must not be silently dropped.');
    memory=H5S.create_simple(4,fliplr(extent),[]);
    closeMemory=onCleanup(@()H5S.close(memory));
    H5S.select_hyperslab(space,'H5S_SELECT_SET',fliplr(start-1),[],fliplr(extent),[]);
    if isreal(value), data=block;
    else, data=struct('real',real(block),'imag',imag(block)); end
    H5D.write(dataset,'H5ML_DEFAULT',memory,space,'H5P_DEFAULT',data);
    count=count+numel(block); peak=max(peak,numel(block));
    clear closeMemory
   end
  end
 end
end
assert(count==numel(value),'sixgr:util:IncompleteTimeChunkedMATArray');
end

function shape=localSize(value)
shape=[size(value,1) size(value,2) size(value,3) size(value,4)];
end
