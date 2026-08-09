function seed = deterministicSeed(masterSeed, randomnessKey, snrIndex, trialIndex, streamType)
%DETERMINISTICSEED Derive a stable uint32 stream seed from simulation keys.

payload = sprintf('sixgr.lls.seed/v1|%.0f|%s|%d|%d|%s', ...
    double(masterSeed), char(string(randomnessKey)), round(double(snrIndex)), ...
    round(double(trialIndex)), char(string(streamType)));
digest = char(sixgr.util.sha256Hex(uint8(unicode2native(payload, "UTF-8"))));
seed = double(hex2dec(digest(1:8)));
end
