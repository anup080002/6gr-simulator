function ok=testTimeChunkedMATPayload()
% Exact serialization/partial-read qualification, not a PHY performance test.
setup6GRSimToolkit('Verbose',false);
folder=tempname; mkdir(folder);
fprintf('TIME_CHUNKED_MAT_TEST_ROOT=%s\n',folder);
stream=RandStream('mt19937ar','Seed',2401411);
shapes={[4097 5 3 2],[17 1 1 1],[1 7 2 1],[1 1 1 1]};
for precision=["single","double"]
 for complexValues=[false,true]
  for index=1:numel(shapes)
    shape=shapes{index};
    value=cast(randn(stream,shape),precision);
    if complexValues, value=complex(value,cast(randn(stream,shape),precision)); end
    % Construct signed zero from its IEEE bits, not a constant expression
    % that an optimizer may fold to positive zero.
    if precision=="double", negativeZero=typecast(bitshift(uint64(1),63),'double');
    else, negativeZero=typecast(bitshift(uint32(1),31),'single'); end
    if complexValues
        value(1)=complex(negativeZero,negativeZero);
    else
        value(1)=negativeZero;
    end
    payload=struct('PathGains_000001',value, ...
        'ManifestJSON',"original_manifest_must_not_change", ...
        'CaptureMetadata',{{struct('Reference',struct('PathGainsVariable',"PathGains_000001"))}});
    path=fullfile(folder,sprintf('%s_complex%d_shape%d.mat',precision,complexValues,index));
    e=sixgr.util.writeTimeChunkedMATPayload(path,payload,"PathGains_000001");
    saved=load(path);
    assert(isequaln(saved,payload) && e.ElementCount==numel(value) && ...
        ~e.NumericValuesChanged && ~e.PrecisionChanged && ~e.FullArrayReadback && ...
        e.MaxWriteBlockElements<=2048*4*2);
    assert(isequal(typecast(real(saved.PathGains_000001(:)),'uint8'), ...
        typecast(real(value(:)),'uint8')) && ...
        isequal(typecast(imag(saved.PathGains_000001(:)),'uint8'), ...
        typecast(imag(value(:)),'uint8')),'Every numeric bit must survive, including signed zero.');
    file=matfile(path,'Writable',false);
    first=max(1,shape(1)-2);
    actual=file.PathGains_000001(first:shape(1),1:shape(2),1:shape(3),1:shape(4));
    assert(isequal(actual,value(first:shape(1),:,:,:)), ...
        'The existing channel-archive partial reader must retain native indexing.');
    info=h5info(path,'/PathGains_000001');
    assert(isequal(info.ChunkSize,min(shape,[2048 4 2 1])) && ...
        any(contains(lower(string({info.Filters.Name})),"shuffle")) && ...
        any(contains(lower(string({info.Filters.Name})),"deflate")));
    fprintf('TIME_CHUNKED_MAT_EXACT_PASS class=%s complex=%d shape=%s\n',precision,complexValues,mat2str(shape));
  end
 end
end
% Preserve complexity even when the native type-template slice contains
% only zeros, and independently preserve a second numeric variable plus
% nested metadata that is not part of the compression selection.
lateComplex=complex(zeros(17,1),zeros(17,1));
lateComplex(end)=3+4i;
payload=struct('PathGains_000001',lateComplex, ...
    'PathGains_000002',single(reshape(1:24,3,4,2)), ...
    'Unselected',struct('Values',[NaN Inf -Inf],'Label',"metadata_unchanged"));
path=fullfile(folder,'multiple_variables_late_complex.mat');
e=sixgr.util.writeTimeChunkedMATPayload(path,payload,["PathGains_000001","PathGains_000002"]);
assert(isequaln(load(path),payload) && e.ElementCount==41);
localReject(@()sixgr.util.writeTimeChunkedMATPayload(fullfile(folder,'duplicate.mat'), ...
    payload,["PathGains_000001","PathGains_000001"]),'sixgr:util:InvalidTimeChunkedMATRequest');
localReject(@()sixgr.util.writeTimeChunkedMATPayload(fullfile(folder,'nonnumeric.mat'), ...
    payload,"Unselected"),'sixgr:util:InvalidTimeChunkedMATArray');
invalid=struct('PathGains_000001',[1;NaN]);
localReject(@()sixgr.util.writeTimeChunkedMATPayload(fullfile(folder,'nonfinite.mat'), ...
    invalid,"PathGains_000001"),'sixgr:util:NonfiniteTimeChunkedMATArray');
% Smooth time-correlated data is the observed archive bottleneck. Require
% a real byte reduction without sacrificing any values or native metadata.
samples=(0:8191).';
gains=reshape(exp(1i*(samples*1e-7+(0:31)*.17)),8192,4,4,2);
payload=struct('PathGains_000001',gains,'ManifestJSON',"compression_only");
native=fullfile(folder,'native.mat'); save(native,'-struct','payload','-v7.3');
chunked=fullfile(folder,'time_chunked.mat');
sixgr.util.writeTimeChunkedMATPayload(chunked,payload,"PathGains_000001");
a=dir(native); b=dir(chunked);
assert(b.bytes<a.bytes && isequaln(load(native),load(chunked)), ...
    'Time-contiguous compression must reduce this smooth fixture with exactly identical MATLAB values.');
localReject(@()sixgr.util.writeTimeChunkedMATPayload(chunked,payload,"PathGains_000001"), ...
    'sixgr:util:InvalidTimeChunkedMATRequest');
localReject(@()sixgr.util.writeTimeChunkedMATPayload(fullfile(folder,'missing.mat'),payload,"Absent"), ...
    'sixgr:util:InvalidTimeChunkedMATRequest');
fprintf('TIME_CHUNKED_MAT_STORAGE_PASS original_bytes=%d lossless_bytes=%d\n',a.bytes,b.bytes);
ok=true;
end

function localReject(callback,id)
try, callback(); catch failure
    assert(strcmp(failure.identifier,id),'Expected %s, got %s.',id,failure.identifier);
    return;
end
error('test:MissingRejection','Expected %s.',id);
end
