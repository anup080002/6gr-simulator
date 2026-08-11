function ok = testLLS_ReferencePoints()
%TESTLLS_REFERENCEPOINTS Golden-style PHY reference points (AWGN baseline).
% Reference envelopes were recalibrated on 2026-08-10 after strict
% codeword-specific MCS ownership replaced the former free modulation/rate
% pair. These are deterministic regression anchors, not 3GPP conformance
% claims; the independent FRC gate owns standards comparisons.

setup6GRSimToolkit("Verbose", false);
cfg = sixgr.config.defaultConfig();
cfg.run.shortRun = true;
cfg.outputs.saveCSV = false;
cfg.outputs.saveMAT = false;
cfg.outputs.saveFigures = false;
cfg.run.noiseOperatingMode = "standalone_awgn_snr_argument";
% Golden data-channel points exclude CSI-RS; CSI-RS physical codebooks are
% qualified separately and must never be synthesized by this test.
cfg.phy.csirs.enable = false;
cfg.phy.csirs.enabled = false;
% Pin DL to TS 38.214 table-2 MCS 22 (256QAM, R=754/1024). This exact
% table/index tuple is now required by the calibration transmitter.
dlReferenceMCS = sixgr.link.resolveMCSProfile("qam256_table2", 22);
cfg.phy.pdsch.mcsTable = "qam256_table2";
cfg.phy.pdsch.mcsIndex = 22;
cfg.phy.pdsch.modulation = char(string(dlReferenceMCS.Modulation));
cfg.phy.pdsch.codeRate = double(dlReferenceMCS.TargetCodeRate);
% Golden points must not inherit a moving operator default. Pin the UL
% reference to TS 38.214 table-1 MCS 19 (64QAM, R=517/1024) so the 0/20 dB
% envelopes describe one stable waveform operating point.
ulReferenceMCS = sixgr.link.resolveMCSProfile("qam64_table1", 19);
cfg.phy.linkAdaptation.mode = "fixed";
cfg.phy.linkAdaptation.ulPolicy = "fixed";
cfg.phy.pusch.mcsTable = "qam64_table1";
cfg.phy.pusch.mcsIndex = 19;
cfg.phy.pusch.configuredMCSIndex = 19;
cfg.phy.pusch.modulation = char(string(ulReferenceMCS.Modulation));
cfg.phy.pusch.codeRate = double(ulReferenceMCS.TargetCodeRate);

rng(2026, "twister");
dl0 = sixgr.link.runDLPDSCHThroughput(cfg, "NumFrames", 8, ...
    "SNR_dB", 0, "ExecutionProfile", "phy_calibration");
dl30 = sixgr.link.runDLPDSCHThroughput(cfg, "NumFrames", 8, ...
    "SNR_dB", 30, "ExecutionProfile", "phy_calibration");
ul0 = sixgr.link.runULPUSCHThroughput(cfg, "NumFrames", 8, "SNR_dB", 0);
ul20 = sixgr.link.runULPUSCHThroughput(cfg, "NumFrames", 8, "SNR_dB", 20);

if logical(dl0.Skipped) || logical(dl30.Skipped)
    assert(logical(dl0.Skipped) && logical(dl30.Skipped), ...
        "DL reference runs must both skip or both execute.");
else
    localAssertRange(double(dl0.BER), 0.32, 0.39, "DL BER @0dB out of reference envelope.");
    localAssertRange(double(dl30.BER), 0.0, 0.005, "DL BER @30dB out of reference envelope.");
    localAssertRange(double(dl30.BLER), 0.0, 0.25, "DL BLER @30dB out of reference envelope.");
    assert(double(dl30.BER) <= double(dl0.BER), "DL BER must improve with SNR.");
    assert(double(dl30.BER) <= 0.15 * max(double(dl0.BER), eps), "DL BER improvement is below reference expectation.");
    if istable(dl0.TrialTable) && istable(dl30.TrialTable) && ...
            all(ismember(["WidebandCQI","MCS"], string(dl0.TrialTable.Properties.VariableNames))) && ...
            all(ismember(["WidebandCQI","MCS"], string(dl30.TrialTable.Properties.VariableNames)))
        assert(mean(double(dl30.TrialTable.WidebandCQI), "omitnan") >= mean(double(dl0.TrialTable.WidebandCQI), "omitnan"), ...
            "DL reference CQI should improve with SNR.");
    end
end

if logical(ul0.Skipped) || logical(ul20.Skipped)
    assert(logical(ul0.Skipped) && logical(ul20.Skipped), ...
        "UL reference runs must both skip or both execute.");
else
    localAssertRange(double(ul0.BER), 0.22, 0.40, "UL BER @0dB out of reference envelope.");
    localAssertRange(double(ul20.BER), 0.0, 0.005, "UL BER @20dB out of reference envelope.");
    localAssertRange(double(ul20.BLER), 0.0, 0.25, "UL BLER @20dB out of reference envelope.");
    assert(double(ul20.BER) <= double(ul0.BER), "UL BER must improve with SNR.");
    assert(double(ul20.BER) <= 0.45 * max(double(ul0.BER), eps), "UL BER improvement is below reference expectation.");
    if istable(ul0.TrialTable) && istable(ul20.TrialTable) && ...
            all(ismember(["WidebandCQI","MCS"], string(ul0.TrialTable.Properties.VariableNames))) && ...
            all(ismember(["WidebandCQI","MCS"], string(ul20.TrialTable.Properties.VariableNames)))
        assert(mean(double(ul20.TrialTable.WidebandCQI), "omitnan") >= mean(double(ul0.TrialTable.WidebandCQI), "omitnan"), ...
            "UL reference CQI should improve with SNR.");
    end
end

ok = true;
end

function localAssertRange(x, lo, hi, msg)
assert(isfinite(x), "Reference metric must be finite.");
assert(x >= lo && x <= hi, msg);
end
