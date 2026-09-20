function ok = testPhyBLERReferencePoints()
%TESTPHYBLERREFERENCEPOINTS Smoke-test NR MCS BLER reference points.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
rng(42, "twister");

cfg = sixgr.config.defaultConfig();
cfg.channel.model = "AWGN";
cfg.channel.awgnOnly = true;
cfg.phy.pdsch.executionProfile = "phy_calibration";
cfg.run.noiseOperatingMode = "standalone_awgn_snr_argument";
% Isolated SISO data calibration: SS/PBCH and CSI-RS are not transmitted on
% this reduced carrier. Their reservation behavior is qualified separately.
cfg.phy.ssb.enable = false;
cfg.phy.csirs.enable = false;
cfg.phy.carrier.NSizeGrid = 12;
cfg.phy.pdsch.prbSet = 0:5;
cfg.phy.pdsch.symbolAllocation = [0 14];
cfg.phy.pdsch.nLayers = 1;
cfg.phy.pdsch.numLayers = 1;
cfg.phy.pdsch.numPorts = 1;
cfg.phy.pdsch.dmrs.nPorts = 1;
cfg.phy.pdsch.dmrs.portSet = 0;
cfg.phy.pdsch.enablePTRS = false;
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
    profile = sixgr.link.resolveMCSProfile(cfgM.phy.pdsch.mcsTable, mcsIdx);
    assert(profile.Valid, "Reference MCS %d must exist in %s.", ...
        mcsIdx, string(cfgM.phy.pdsch.mcsTable));
    cfgM = sixgr.util.structSet(cfgM, "phy.pdsch.mcsIndex", mcsIdx);
    cfgM = sixgr.util.structSet(cfgM, "phy.pdsch.modulation", profile.Modulation);
    cfgM = sixgr.util.structSet(cfgM, "phy.pdsch.codeRate", profile.TargetCodeRate);
    cfgM = sixgr.util.structSet(cfgM, "phy.linkAdaptation.mode", "fixed_mcs");
    out = sixgr.link.runDLPDSCHThroughput(cfgM, "NumFrames", 4, "SNR_dB", snr);
    if isfield(out, "Skipped") && out.Skipped
        continue;
    end
    assert(isfinite(out.BLER), "BLER must be finite for MCS %d.", mcsIdx);
    assert(all(~logical(out.TrialTable.Crash)), ...
        "MCS %d reference point must execute without crashed trial rows.", mcsIdx);
    assert(out.BLER <= 0.55, ...
        "MCS %d at %.1f dB has BLER %.3f > 0.55.", mcsIdx, snr, out.BLER);
end

ok = true;
end
