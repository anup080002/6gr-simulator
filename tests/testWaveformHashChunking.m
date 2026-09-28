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

ok = true;
disp("WAVEFORM_HASH_CHUNKING_PASS");
end
