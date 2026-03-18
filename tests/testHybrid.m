function ok = testHybrid()
%TESTHYBRID Regression checks for calibrated hybrid BLER artifacts.

setup6GRSimToolkit("Verbose", false);
cfg = sixgr.config.defaultConfig();
cfg.run.shortRun = true;
ctx = sixgr.core.SimContext(cfg);

cal = sixgr.hybrid.CalibrateBLER(ctx, struct( ...
    "SNRGrid_dB", [-6 -2 2 6 10], ...
    "CalibFrames", 2, ...
    "CalibDirection", ["DL","UL"], ...
    "CalibMCS", [6 14], ...
    "CalibPRB", [10], ...
    "CalibLayers", [1], ...
    "CalibSCS_kHz", [30], ...
    "CalibDopplerHz", [0], ...
    "CalibChannelModels", ["AWGN"]));

assert(isfield(cal, "LUT"), "Hybrid LUT missing");
assert(isfield(cal, "DB"), "Hybrid BLER DB missing");
db = cal.DB;
assert(isfield(db, "Axes") && isfield(db.Axes, "Direction"), "Hybrid DB axes missing");
dirs = upper(string(db.Axes.Direction(:)));
assert(any(dirs == "DL") && any(dirs == "UL"), "Hybrid DB must contain both DL and UL directions");
assert(all(isfinite(db.BLER(:))), "Hybrid DB contains NaN/Inf BLER values");
assert(isfield(cal.LUT, "Source"), "Hybrid LUT source missing");

lutSource = lower(string(cal.LUT.Source));
assert(contains(lutSource, "calibrated"), "Hybrid LUT source must be calibrated.");
assert(~contains(lutSource, "fallback"), "Hybrid LUT source must not be fallback.");

b = squeeze(db.BLER(1,1,1,1,1,1,1,:));
dbDiff = diff(double(b(:)));
assert(all(dbDiff <= 1e-9), "BLER trend must be non-increasing with SNR.");

B = double(db.BLER);
nSnr = size(B, 8);
flat = reshape(B, [], nSnr);
dropPerCurve = flat(:,1) - flat(:,end);
trendExists = any(dropPerCurve > 1e-3);
assert(any(isfinite(dropPerCurve)), "Invalid BLER curves in hybrid calibration.");

hasNR = (exist("nrPDSCH", "file") == 2) && (exist("nrPUSCH", "file") == 2);
if hasNR
    cfgStrict = cfg;
    cfgStrict.run.strictMode = true;
    ctxStrict = sixgr.core.SimContext(cfgStrict);
    calStrict = sixgr.hybrid.CalibrateBLER(ctxStrict, struct( ...
        "SNRGrid_dB", [-4 0 4], ...
        "CalibFrames", 1, ...
        "CalibDirection", ["DL","UL"], ...
        "CalibMCS", [8], ...
        "CalibPRB", [10], ...
        "CalibLayers", [1], ...
        "CalibSCS_kHz", [30], ...
        "CalibDopplerHz", [0], ...
        "CalibChannelModels", ["AWGN"]));
    assert(all(isfinite(calStrict.DB.BLER(:))), "Strict calibration DB must not contain NaN/Inf.");
end
ok = true;
end
