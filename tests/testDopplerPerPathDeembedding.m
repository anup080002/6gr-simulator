function ok = testDopplerPerPathDeembedding()
%TESTDOPPLERPERPATHDEEMBEDDING Validate per-path fading phase de-embedding.

setup6GRSimToolkit("Verbose", false);

fs = 1000;
t = (0:15).' ./ fs;
fd = [25 -40 0];
base = complex(ones(numel(t), numel(fd), 2, 1));
rot = exp(1j .* 2 .* pi .* t .* fd);
pathGains = base .* reshape(rot, [numel(t), numel(fd), 1, 1]);

[deembedded, info] = sixgr.phy.sync.deembedDopplerFromPathGains(pathGains, t, fd);
assert(logical(info.Applied), "Per-path Doppler de-embedding must mark the operation as applied.");
assert(string(info.Status) == "applied_per_path_path_gain_phase_deembedding", ...
    "Per-path Doppler de-embedding must disclose the sample-domain status.");
assert(max(abs(deembedded(:) - base(:))) < 1e-12, ...
    "Known per-path Doppler phase must be removed exactly from the path-gain tensor.");

sync = sixgr.phy.sync.resolveSynchronizationState( ...
    "SampleRate_Hz", fs, ...
    "InjectedCFO_Hz", 10, ...
    "AppliedCFOCorrection_Hz", 8, ...
    "PhysicalDoppler_Hz", 25, ...
    "PerPathDoppler_Hz", fd, ...
    "PerPathDopplerDeembeddingApplied", true, ...
    "PerPathDopplerDeembeddingStatus", info.Status);
assert(sync.ResidualCFO_PostCorrection_Hz == 2, ...
    "CFO residual must remain oscillator-CFO-only when path Doppler evidence is present.");
assert(sync.PerPathDopplerPathCount == numel(fd) && logical(sync.PerPathDopplerDeembeddingApplied), ...
    "Synchronization metadata must preserve per-path Doppler de-embedding evidence.");

threw = false;
try
    sixgr.phy.sync.deembedDopplerFromPathGains(pathGains, t, fd(1:2));
catch ME
    threw = strcmp(string(ME.identifier), "sixgr:phy:sync:DopplerPathCountMismatch");
end
assert(threw, "A mismatched per-path Doppler vector must fail before producing samples.");

ok = true;
end
