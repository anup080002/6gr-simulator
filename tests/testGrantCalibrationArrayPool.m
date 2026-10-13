function ok=testGrantCalibrationArrayPool()
% Exercise the collector/reader/key and underpopulation guards, not just
% an isolated codec round trip. Physical DL/UL episodes remain unqualified.
ok=testGrantCalibrationReference("lossless_path_gains_xor_dedup_v1");
end
