function hash=waveformSHA256(x)
% Canonical RF sample digest; class, dimensions, real and imaginary doubles.
% This is a waveform-content hash, not a configuration or segment-list hash.
assert(isnumeric(x) || islogical(x),'sixgr:rf:WaveformHashSamplesRequired', ...
    'A waveform hash requires sample data, not configuration metadata.');
if isempty(x)
    hash=sixgr.util.sha256Hex(uint8(char("empty:"+string(class(x)))));
    return;
end
header=uint8(char("waveform:"+string(class(x))+":"));
dims=reshape(typecast(uint64(size(x)),"uint8"),[],1);
realBytes=reshape(typecast(double(real(x(:))),"uint8"),[],1);
imagBytes=reshape(typecast(double(imag(x(:))),"uint8"),[],1);
hash=sixgr.util.sha256Hex([header(:);dims;realBytes;imagBytes]);
end
