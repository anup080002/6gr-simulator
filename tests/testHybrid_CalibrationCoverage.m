function ok = testHybrid_CalibrationCoverage()
%TESTHYBRID_CALIBRATIONCOVERAGE Verify calibration DB coverage and trends.

setup6GRSimToolkit("Verbose", false);
cfg = sixgr.config.defaultConfig();
cfg.run.shortRun = true;
ctx = sixgr.core.SimContext(cfg);

cal = sixgr.hybrid.CalibrateBLER(ctx, struct( ...
    "SNRGrid_dB", [-4 0 4 8 12], ...
    "CalibFrames", 3, ...
    "CalibMCS", [6 14], ...
    "CalibPRB", [10 25], ...
    "CalibLayers", [1], ...
    "CalibDopplerHz", [0], ...
    "CalibChannelModels", ["AWGN"]));

assert(isfield(cal, "DB"), "Calibration DB missing");
db = cal.DB;
assert(all(isfinite(db.BLER(:))), "Calibration DB contains non-finite values");

% Check one BLER curve is non-increasing with SNR.
b = squeeze(db.BLER(1,1,1,1,1,1,1,:));
dbDiff = diff(double(b(:)));
assert(all(dbDiff <= 1e-9), "BLER trend must be non-increasing with SNR");

% Check directions exist.
dirs = upper(string(db.Axes.Direction(:)));
assert(any(dirs == "DL") && any(dirs == "UL"), "DB must include both DL and UL.");
ok = true;
end
