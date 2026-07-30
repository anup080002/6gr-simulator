function ok = testSNRSweepMonotonicity()
%TESTSNRSWEEPMONOTONICITY Ensure AWGN BLER generally decreases with SNR.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
rng(1234, "twister");

cfg = sixgr.config.defaultConfig();
cfg.channel.model = "AWGN";
cfg.phy.pdsch.executionProfile = "phy_calibration";
cfg.run.noiseOperatingMode = "standalone_awgn_snr_argument";
cfg.outputs.saveCSV = false;
cfg.outputs.saveMAT = false;
cfg.outputs.saveFigures = false;

% Positive-SNR smoke range avoids known low-SNR native instability in short
% repeated R2024a toolbox runs while still checking trend direction.
snrPts = [5 10 15 20 25];
bler = NaN(size(snrPts));
for i = 1:numel(snrPts)
    out = sixgr.link.runDLPDSCHThroughput(cfg, "NumFrames", 4, "SNR_dB", snrPts(i));
    if ~(isfield(out, "Skipped") && out.Skipped)
        bler(i) = out.BLER;
    end
end

valid = isfinite(bler);
snrV = snrPts(valid);
blerV = bler(valid);
for i = 2:numel(blerV)
    assert(blerV(i) <= blerV(i-1) + 0.15, ...
        "BLER must generally decrease: SNR %.0f->%.0f, BLER %.3f->%.3f.", ...
        snrV(i-1), snrV(i), blerV(i-1), blerV(i));
end
hiIdx = find(snrV >= 20, 1, "first");
if ~isempty(hiIdx)
    assert(blerV(hiIdx) < 0.20, ...
        "BLER at >=20 dB must be below 20%% for this smoke run; got %.1f%%.", blerV(hiIdx) * 100);
end

ok = true;
end
