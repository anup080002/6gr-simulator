function ok = testPhyBLERReferencePoints()
%TESTPHYBLERREFERENCEPOINTS Smoke-test NR MCS BLER reference points.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
rng(42, "twister");

cfg = sixgr.config.defaultConfig();
cfg.channel.model = "AWGN";
cfg.run.noiseOperatingMode = "standalone_awgn_snr_argument";
cfg.outputs.saveCSV = false;
cfg.outputs.saveMAT = false;
cfg.outputs.saveFigures = false;

% Keep this as a short CI smoke test. Very-low-SNR repeated toolbox runs can
% destabilize some R2024a sessions, so these points sit slightly above the
% approximate 10%-BLER operating region while still exercising all MCS ranges.
refPts = [1 15; 7 18; 14 21; 21 24; 27 27];
for r = 1:size(refPts, 1)
    cfgM = cfg;
    mcsIdx = refPts(r, 1);
    snr = refPts(r, 2);
    cfgM = sixgr.util.structSet(cfgM, "phy.pdsch.mcsIndex", mcsIdx);
    cfgM = sixgr.util.structSet(cfgM, "phy.linkAdaptation.mode", "fixed_mcs");
    out = sixgr.link.runDLPDSCHThroughput(cfgM, "NumFrames", 4, "SNR_dB", snr);
    if isfield(out, "Skipped") && out.Skipped
        continue;
    end
    assert(isfinite(out.BLER), "BLER must be finite for MCS %d.", mcsIdx);
    assert(out.BLER <= 0.55, ...
        "MCS %d at %.1f dB has BLER %.3f > 0.55.", mcsIdx, snr, out.BLER);
end

ok = true;
end
