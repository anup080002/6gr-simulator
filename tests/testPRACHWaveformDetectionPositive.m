function ok = testPRACHWaveformDetectionPositive()
%TESTPRACHWAVEFORMDETECTIONPOSITIVE Positive waveform PRACH detection guard.

setup6GRSimToolkit("Verbose", false);

b = prachStrictAnchorResult();
T = b.Result.ArtifactTables.prach_trials;
pos = T(string(T.TrialType) == "positive_high_snr", :);
assert(height(pos) >= 1, "Strict PRACH result must contain a positive high-SNR trial.");
assert(any(logical(pos.StrictOk)), "At least one positive high-SNR PRACH trial must pass strict detection.");
assert(all(logical(pos.PreambleIndexMatch)), "Positive PRACH trials must detect the transmitted preamble index.");
assert(all(~logical(pos.FalseAlarm) & ~logical(pos.MissedDetection)), ...
    "Positive PRACH trials must not be false alarms or missed detections.");
assert(all(abs(double(pos.TimingErrorSamples)) <= 1.5), ...
    "Positive PRACH trials must estimate timing within the strict sample tolerance.");
assert(all(strlength(strtrim(string(pos.ConfigHash))) > 0 & strlength(strtrim(string(pos.WaveformHash))) == 64), ...
    "Positive PRACH rows must carry config and waveform hashes.");
assert(all(strlength(strtrim(string(pos.UsedOracleFields))) == 0), ...
    "Positive PRACH detection must not consume transmitter oracle fields.");

ok = true;
end
