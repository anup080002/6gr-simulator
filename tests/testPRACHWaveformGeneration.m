function ok = testPRACHWaveformGeneration()
%TESTPRACHWAVEFORMGENERATION Real strict PRACH waveform generation smoke.

setup6GRSimToolkit("Verbose", false);

b = prachStrictAnchorResult();
occ = sixgr.rach.mapPRACHToOccasion(b.Config, "OccasionIndex", 1);
tx = sixgr.phy.prach.generatePRACHWaveform(b.Config, "Occasion", occ, "PreambleIndex", 7);

assert(~isempty(tx.Waveform) && any(abs(tx.Waveform(:)) > 0), ...
    "Strict PRACH waveform generation must emit non-empty baseband samples.");
assert(isfinite(double(tx.SampleRate_Hz)) && double(tx.SampleRate_Hz) > 0, ...
    "Strict PRACH waveform must report a finite sample rate.");
assert(~isempty(tx.Indices), "Strict PRACH waveform must expose PRACH resource indices.");
assert(strlength(string(tx.WaveformHash)) == 64, "Strict PRACH waveform must include a SHA-256 sample hash.");
assert(~logical(tx.ProxyUsed) && ~logical(tx.Skipped) && ~logical(tx.ToolboxMissing), ...
    "Strict PRACH waveform generation must not use proxy, skipped, or toolbox-missing paths.");
assert(string(tx.TruthStatus) == "real_lls_evidence", ...
    "Strict PRACH waveform generation must declare real LLS evidence.");

ok = true;
end
