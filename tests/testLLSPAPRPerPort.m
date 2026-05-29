function ok = testLLSPAPRPerPort()
%TESTLLSPAPRPERPORT Guard against flattening multi-port waveforms for PAPR.

setup6GRSimToolkit("Verbose", false);

tx = struct();
tx.Waveform = [ones(128, 1), 10 * ones(128, 1)];
rx = struct();
cfg = struct();

[metrics, ~] = sixgr.link.deriveModulationTrackingMetrics(tx, rx, cfg, "DL");
assert(isfinite(double(metrics.PAPR_dB)), "PAPR must be finite for a non-empty waveform.");
assert(abs(double(metrics.PAPR_dB)) < 1e-9, ...
    "PAPR must be computed per RF port; inter-port power offsets must not look like time-domain peaks.");

cfg.waveform = struct("cfr_enabled", true, "cfr_target_papr_db", 1);
[metricsCFR, ~] = sixgr.link.deriveModulationTrackingMetrics(tx, rx, cfg, "DL");
assert(double(metricsCFR.PeakClippingEvents) == 0, ...
    "CFR clipping-event accounting must use per-port average power thresholds.");

ok = true;
end
