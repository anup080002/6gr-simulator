function ok = testFixedLinkCampaignBLERLUTIngestion()
%TESTFIXEDLINKCAMPAIGNBLERLUTINGESTION Consume fixed-link BLER curves in AMC.

setup6GRSimToolkit("Verbose", false);

cfg = sixgr.config.defaultConfig();
cfg = sixgr.util.structSet(cfg, "phy.csi.sinrToCQIMode", "effective_sinr_bler_lut");
cfg = sixgr.util.structSet(cfg, "phy.csi.targetBLER", 0.1);
cfg = sixgr.util.structSet(cfg, "phy.csi.cqiTable", "table1");
cfg = sixgr.util.structSet(cfg, "phy.pdsch.mcsTable", "qam64_table1");
cfg = sixgr.util.structSet(cfg, "phy.pdsch.mcsIndex", 11);
cfg = sixgr.util.structSet(cfg, "phy.pdsch.cqiBLERLUT", localCampaignSummary("DL"));

low = sixgr.link.resolveWidebandCQI(localSINRInput(1), cfg, "DL");
high = sixgr.link.resolveWidebandCQI(localSINRInput(12), cfg, "DL");

assert(strcmpi(string(high.Mode), "effective_sinr_bler_target_lut"), ...
    "Fixed-link campaign curves must drive the effective-SINR BLER-LUT selector.");
assert(contains(string(high.BLERLUTSource), "fixed_link_monte_carlo_campaign") && ...
    strcmpi(string(high.BLERLUTValueRole), "fixed_link_waveform_bler_calibration"), ...
    "Fixed-link BLER LUTs must retain waveform-campaign provenance.");
assert(contains(string(high.BLERLUTCalibrationID), "fixed_link_monte_carlo:DL"), ...
    "Fixed-link BLER LUTs must expose a deterministic calibration identity.");
assert(double(low.WidebandCQI) < double(high.WidebandCQI) && double(high.WidebandCQI) == 7, ...
    "The configured-MCS fixed-link curve must bind to the matching CQI operating point.");

cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.mode", "amc");
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.dlPolicy", "baseline");
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.domain", "effective_sinr");
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.outerLoopFlag", false);
[decision, ~] = sixgr.link.computeLinkAdaptationDecision(cfg, "DL", localMetrics(12));
expected = sixgr.link.resolveMCSFromCQI(7, "qam64_table1", "table1");
assert(logical(decision.Valid) && double(decision.MCSIndex) == double(expected.MCSIndex), ...
    "Closed-loop AMC must consume the fixed-link BLER calibration before selecting MCS.");
assert(contains(string(decision.CQIBLERLUTSource), "fixed_link_monte_carlo_campaign") && ...
    strcmpi(string(decision.CQIBLERLUTValueRole), "fixed_link_waveform_bler_calibration"), ...
    "AMC decision metadata must disclose the fixed-link calibration source.");
assert(contains(string(decision.CalibrationVersion), "fixed_link_monte_carlo:DL"), ...
    "AMC calibration version must be updated from the consumed fixed-link curve.");

cfgUL = sixgr.config.defaultConfig();
cfgUL = sixgr.util.structSet(cfgUL, "phy.csi.sinrToCQIMode", "effective_sinr_bler_lut");
cfgUL = sixgr.util.structSet(cfgUL, "phy.csi.targetBLER", 0.1);
cfgUL = sixgr.util.structSet(cfgUL, "phy.csi.cqiTable", "table1");
cfgUL = sixgr.util.structSet(cfgUL, "phy.pusch.mcsTable", "qam64_table1");
cfgUL = sixgr.util.structSet(cfgUL, "phy.pusch.mcsIndex", 11);
cfgUL = sixgr.util.structSet(cfgUL, "phy.pusch.cqiBLERLUT", localCampaignSummary("UL"));
ul = sixgr.link.resolveWidebandCQI(localSINRInput(12), cfgUL, "UL");
assert(double(ul.WidebandCQI) == 7 && contains(string(ul.BLERLUTCalibrationID), "fixed_link_monte_carlo:UL"), ...
    "UL fixed-link campaign summary columns must be parsed directionally.");

ok = true;
end

function T = localCampaignSummary(direction)
direction = upper(string(direction));
snr = [-2; 2; 6; 10];
bler = [0.90; 0.40; 0.08; 0.01];
trials = [100; 100; 100; 100];
failures = round(bler .* trials);
if direction == "UL"
    T = table(snr, repmat("fixed_link_monte_carlo", 4, 1), true(4, 1), ...
        trials, failures, bler, [2001; 2002; 2003; 2004], ...
        'VariableNames', {'SNR_dB','CampaignKind','FixedReferenceMode', ...
        'UL_TrialCount','UL_FailureCount','UL_BLER','PointSeed'});
else
    T = table(snr, repmat("fixed_link_monte_carlo", 4, 1), true(4, 1), ...
        trials, failures, bler, [1001; 1002; 1003; 1004], ...
        'VariableNames', {'SNR_dB','CampaignKind','FixedReferenceMode', ...
        'DL_TrialCount','DL_FailureCount','DL_BLER','PointSeed'});
end
end

function x = localSINRInput(sinr_dB)
x = struct( ...
    "WidebandSINR_dB", double(sinr_dB), ...
    "SINRSource", "post_equalization_sinr_from_equalizer", ...
    "SINRValueRole", "measured_post_equalization_scheduling_input", ...
    "SINRValueStatus", "OK");
end

function m = localMetrics(sinr_dB)
m = localSINRInput(sinr_dB);
m.SINR_dB = double(sinr_dB);
m.RI = 1;
m.CombinedDecodeOK = true;
end
