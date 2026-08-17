function ok = testFadingLinkDelayAlignment()
%TESTFADINGLINKDELAYALIGNMENT Preserve fading-waveform delay handling in link helpers.

setup6GRSimToolkit("Verbose", false);

cfg = sixgr.config.defaultConfig();
cfg = sixgr.truth.prepareValidationConfig(cfg, struct("SaveFigures", false, "LinkSNR_dB", 30));
cfg.outputs.saveCSV = false;
cfg.outputs.saveMAT = false;
cfg.outputs.saveFigures = false;
cfg.outputs.savePNG = false;
cfg.run.noiseOperatingMode = "standalone_awgn_snr_argument";
cfg.phy.pdcch.enable = false;
cfg.phy.pdcch.Enable = false;
cfg.phy.dl.pdcch.Enable = false;
cfg.control_gating.pdcch_required = false;
cfg.run.controlGating.pdcchRequired = false;
cfg.phy.pdsch.nLayers = 1;
cfg.phy.pdsch.numLayers = 1;
cfg.phy.pdsch.numPorts = 1;
cfg.phy.pdsch.dmrs.portSet = 0;
cfg.phy.pdsch.mcsTable = "calibration_explicit";
cfg.phy.pdsch.mcsIndex = 0;
cfg.phy.pusch.nLayers = 1;
cfg.phy.pusch.numLayers = 1;
cfg.phy.pusch.numPorts = 1;
cfg.phy.pusch.dmrs.portSet = 0;
cfg.phy.pusch.mcsTable = "calibration_explicit";
cfg.phy.pusch.mcsIndex = 0;

dl = sixgr.link.runDLPDSCHThroughput(cfg, "NumFrames", 2, ...
    "SNR_dB", 30, "ExecutionProfile", "phy_calibration");
ul = sixgr.link.runULPUSCHThroughput(cfg, "NumFrames", 2, ...
    "SNR_dB", 30, "ExecutionProfile", "phy_calibration");

assert(~logical(dl.Skipped), "Strict fading DL helper must execute, not skip.");
assert(~logical(ul.Skipped), "Strict fading UL helper must execute, not skip.");
assert(logical(dl.Ok), ...
    "Strict fading DL helper must decode cleanly after delay alignment; BLER=%g, notes=%s.", ...
    double(dl.BLER), char(string(dl.Notes)));
assert(logical(ul.Ok), ...
    "Strict fading UL helper must decode cleanly after delay alignment; BLER=%g, notes=%s.", ...
    double(ul.BLER), char(string(ul.Notes)));
assert(double(dl.BLER) == 0, "Strict fading DL helper should not report block errors at the validation point.");
assert(double(ul.BLER) == 0, "Strict fading UL helper should not report block errors at the validation point.");
assert(double(dl.Throughput_Mbps) > 0, "Strict fading DL helper should report positive throughput.");
assert(double(ul.Throughput_Mbps) > 0, "Strict fading UL helper should report positive throughput.");

ok = true;
end
