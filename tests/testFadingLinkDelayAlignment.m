function ok = testFadingLinkDelayAlignment()
%TESTFADINGLINKDELAYALIGNMENT Preserve fading-waveform delay handling in link helpers.

setup6GRSimToolkit("Verbose", false);

cfg = sixgr.config.defaultConfig();
cfg = sixgr.truth.prepareValidationConfig(cfg, struct("SaveFigures", false, "LinkSNR_dB", 30));
cfg.outputs.saveCSV = false;
cfg.outputs.saveMAT = false;
cfg.outputs.saveFigures = false;
cfg.outputs.savePNG = false;

dl = sixgr.link.runDLPDSCHThroughput(cfg, "NumFrames", 2, "SNR_dB", 30);
ul = sixgr.link.runULPUSCHThroughput(cfg, "NumFrames", 2, "SNR_dB", 30);

assert(~logical(dl.Skipped), "Strict fading DL helper must execute, not skip.");
assert(~logical(ul.Skipped), "Strict fading UL helper must execute, not skip.");
assert(logical(dl.Ok), "Strict fading DL helper must decode cleanly after delay alignment.");
assert(logical(ul.Ok), "Strict fading UL helper must decode cleanly after delay alignment.");
assert(double(dl.BLER) == 0, "Strict fading DL helper should not report block errors at the validation point.");
assert(double(ul.BLER) == 0, "Strict fading UL helper should not report block errors at the validation point.");
assert(double(dl.Throughput_Mbps) > 0, "Strict fading DL helper should report positive throughput.");
assert(double(ul.Throughput_Mbps) > 0, "Strict fading UL helper should report positive throughput.");

ok = true;
end
