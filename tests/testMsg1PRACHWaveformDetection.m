function ok = testMsg1PRACHWaveformDetection()
cfg = raStrictAnchorConfig();
ra = sixgr.mac.ra.RAConfig(cfg, "RunId", "test_msg1");
[tx, occasion] = sixgr.phy.ra.generateMsg1PRACHWaveform(cfg, ra);
det = sixgr.phy.ra.detectMsg1PRACH(tx.Waveform, cfg, ra, occasion);
ta = sixgr.phy.ra.estimateTimingAdvanceFromPRACH(det);
assert(logical(det.Detected), "MSG1 PRACH must be detected from waveform.");
assert(double(det.DetectedPreambleIndex) == double(ra.PreambleIndex), "Detected RAPID must match transmitted preamble.");
assert(isfinite(double(ta.TimingAdvanceCommand)), "Timing advance command must be derived from PRACH timing evidence.");
assert(double(ra.RARNTI) == double(sixgr.phy.ra.computeRARNTI("SymbolIndex", 0, "SlotIndex", 0, "FrequencyIndex", 0)), ...
    "RA-RNTI must be derived from PRACH occasion parameters.");
ok = true;
end
