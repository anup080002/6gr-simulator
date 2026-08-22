function ok = testLLSCQIRangeTruth()
%TESTLLSCQIRANGETRUTH Exported CQI must be NaN or a valid NR CQI index.

setup6GRSimToolkit("Verbose", false);

cfg = sixgr.config.defaultConfig();
cfg.run.shortRun = true;
cfg.outputs.saveCSV = false;
cfg.outputs.saveMAT = false;
cfg.outputs.saveFigures = false;
% This test exercises the isolated waveform receiver, not a connected
% scheduler-owned PDSCH grant.  Declare that trust boundary explicitly so
% the production chain remains fail-closed for an omitted execution
% profile.
cfg.phy.pdsch.executionProfile = "phy_calibration";
cfg = sixgr.util.structSet(cfg, "phy.csi.reportCQI", true);
cfg = sixgr.util.structSet(cfg, "phy.pdsch.enable", true);
cfg = sixgr.util.structSet(cfg, "phy.pusch.enable", true);

dlLow = sixgr.link.runDLPDSCHThroughput(cfg, "NumFrames", 3, "SNR_dB", -10);
dlHigh = sixgr.link.runDLPDSCHThroughput(cfg, "NumFrames", 3, "SNR_dB", 20);
ulLow = sixgr.link.runULPUSCHThroughput(cfg, "NumFrames", 3, "SNR_dB", -10);
ulHigh = sixgr.link.runULPUSCHThroughput(cfg, "NumFrames", 3, "SNR_dB", 20);

localAssertCQIRange(dlLow.TrialTable, "DL low-SNR");
localAssertCQIRange(dlHigh.TrialTable, "DL high-SNR");
localAssertCQIRange(ulLow.TrialTable, "UL low-SNR");
localAssertCQIRange(ulHigh.TrialTable, "UL high-SNR");

ok = true;
end

function localAssertCQIRange(T, label)
assert(istable(T) && ismember("WidebandCQI", string(T.Properties.VariableNames)), ...
    "%s trial table must expose WidebandCQI.", label);
cqi = double(T.WidebandCQI);
assert(~any(cqi == 0), ...
    "%s exported WidebandCQI must not show CQI index 0 as a valid measurement.", label);
assert(all(~isfinite(cqi) | (cqi >= 1 & cqi <= 15)), ...
    "%s exported WidebandCQI must be NaN or a valid NR CQI index in 1..15.", label);
end
