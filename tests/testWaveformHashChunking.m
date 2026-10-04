function ok = testWaveformHashChunking()
%TESTWAVEFORMHASHCHUNKING Preserve hashes while bounding Java updates.

setup6GRSimToolkit("Verbose",false);
rng(20260928,"twister");

% Cross the private 8 MiB byte-update boundary so this exercises more than
% one MessageDigest.update call without allocating a scenario-size array.
bytes = randi([0 255],9*1024*1024+17,1,"uint8");
expectedBytes = sixgr.util.sha256Hex(bytes);
actualBytes = sixgr.phy.waveform.WaveformHash.bytes(bytes);
assert(actualBytes == string(expectedBytes), ...
    "Chunked byte hashing must preserve the canonical SHA-256 digest.");

samples = complex(randn(310000,2),randn(310000,2));
flat = samples(:);
countBytes = typecast(uint64(numel(flat)),"uint8");
realBytes = typecast(real(double(flat)),"uint8");
imaginaryBytes = typecast(imag(double(flat)),"uint8");
legacyPayload = [countBytes(:);realBytes(:);imaginaryBytes(:)];
expectedNumeric = sixgr.util.sha256Hex(legacyPayload);
actualNumeric = sixgr.phy.waveform.WaveformHash.numeric(samples);
assert(actualNumeric == string(expectedNumeric), ...
    "Chunked numeric hashing must preserve the historical byte order.");

% ChannelFactory uses a different class/shape-prefixed serialization. Check
% both real and imaginary chunk boundaries, shape, empty arrays and types.
inputs = {samples,reshape(single(1:24),[2 3 4]),int16([-128 0 255]), ...
    logical([1 0]),zeros(0,3),complex(single([1 2]),single([-3 4]))};
for index=1:numel(inputs)
    value=inputs{index};
    header=uint8(char("runtime_array:"+string(class(value))+":"));
    dims=reshape(typecast(uint64(size(value)),"uint8"),[],1);
    re=reshape(typecast(double(real(value(:))),"uint8"),[],1);
    im=reshape(typecast(double(imag(value(:))),"uint8"),[],1);
    payload=[header(:);dims;re;im];
    independent=javaMethod("getInstance","java.security.MessageDigest","SHA-256");
    independent.update(typecast(payload,'int8'));
    reference=lower(string(reshape(dec2hex(typecast(independent.digest(),'uint8'),2).',1,[])));
    assert(string(sixgr.channel.ChannelFactory.runtimeNumericArraySHA256(value))==reference);
end
assert(sixgr.util.sha256Hex('abc')== ...
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
assert(sixgr.util.sha256Hex(uint8([]))== ...
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");

ok = true;
disp("WAVEFORM_HASH_CHUNKING_PASS");
end
