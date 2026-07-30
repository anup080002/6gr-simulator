function ok = testLLSClosedLoopLinkAdaptation()
%TESTLLSCLOSEDLOOPLINKADAPTATION Verify runtime LLS closed-loop AMC uses measured CSI.

setup6GRSimToolkit("Verbose", false);

cfg = sixgr.config.defaultConfig();
cfg.run.shortRun = true;
cfg.outputs.saveCSV = false;
cfg.outputs.saveMAT = false;
cfg.outputs.saveFigures = false;
cfg.phy.pdsch.executionProfile = "phy_calibration";
cfg.channel.model = "AWGN";
cfg.channel.awgnOnly = true;
cfg.phy.nTxAnt = 2;
cfg.phy.nRxAnt = 2;
cfg = sixgr.util.structSet(cfg, "phy.csi.reportCQI", true);
cfg = sixgr.util.structSet(cfg, "phy.csi.reportPMI", true);
cfg = sixgr.util.structSet(cfg, "phy.csi.reportRI", true);
cfg = sixgr.util.structSet(cfg, "phy.csi.reportCRI", true);
cfg = sixgr.util.structSet(cfg, "phy.csirs.enable", false);
cfg = sixgr.util.structSet(cfg, "phy.csirs.numResources", 0);
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.mode", "amc");
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.dlPolicy", "baseline");
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.ulPolicy", "baseline");
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.rankPolicy", "fixed");
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.beamPolicy", "fixed");
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.periodicity", "slot");
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.delayModel", "zero");

cfg = sixgr.util.structSet(cfg, "phy.pdsch.enable", true);
cfg = sixgr.util.structSet(cfg, "phy.pdsch.modulation", "QPSK");
cfg = sixgr.util.structSet(cfg, "phy.pdsch.codeRate", 0.12);
cfg = sixgr.util.structSet(cfg, "phy.pdsch.mcsIndex", 0);
cfg = sixgr.util.structSet(cfg, "phy.pdsch.nLayers", 1);
cfg = sixgr.util.structSet(cfg, "phy.pdsch.numLayers", 1);

dl = sixgr.link.runDLPDSCHThroughput(cfg, "NumFrames", 3, "SNR_dB", 24);
assert(istable(dl.TrialTable) && height(dl.TrialTable) == 3, "DL closed-loop run must produce trial rows.");
assert(all(ismember(["Modulation","TargetCodeRate","LinkAdaptationApplied","LinkAdaptationScheduled","LinkAdaptationDomain","CQISource","MCSSelectionSource"], ...
    string(dl.TrialTable.Properties.VariableNames))), ...
    "DL closed-loop run must export adaptation state.");
assert(all(string(dl.TrialTable.LinkAdaptationDomain) == "cqi"), ...
    "Default closed-loop DL adaptation must label CQI-space domain explicitly.");
assert(any(dl.TrialTable.LinkAdaptationScheduled), "DL closed-loop run must schedule at least one adaptation update.");
assert(any(dl.TrialTable.MCS(2:end) > dl.TrialTable.MCS(1)), ...
    "DL closed-loop AMC must increase MCS after observing good CSI.");
assert(any(string(dl.TrialTable.Modulation(2:end)) ~= string(dl.TrialTable.Modulation(1))), ...
    "DL closed-loop AMC must update modulation across frames.");

cfg = sixgr.util.structSet(cfg, "phy.pusch.enable", true);
cfg = sixgr.util.structSet(cfg, "phy.pusch.modulation", "QPSK");
cfg = sixgr.util.structSet(cfg, "phy.pusch.codeRate", 0.12);
cfg = sixgr.util.structSet(cfg, "phy.pusch.mcsIndex", 0);
cfg = sixgr.util.structSet(cfg, "phy.pusch.nLayers", 1);
cfg = sixgr.util.structSet(cfg, "phy.pusch.numLayers", 1);

ul = sixgr.link.runULPUSCHThroughput(cfg, "NumFrames", 3, "SNR_dB", 24);
assert(istable(ul.TrialTable) && height(ul.TrialTable) == 3, "UL closed-loop run must produce trial rows.");
assert(all(string(ul.TrialTable.LinkAdaptationDomain) == "cqi"), ...
    "Default closed-loop UL adaptation must label CQI-space domain explicitly.");
assert(any(ul.TrialTable.LinkAdaptationScheduled), "UL closed-loop run must schedule at least one adaptation update.");
assert(any(ul.TrialTable.MCS(2:end) > ul.TrialTable.MCS(1)), ...
    "UL closed-loop AMC must increase MCS after observing good CSI.");
assert(any(string(ul.TrialTable.Modulation(2:end)) ~= string(ul.TrialTable.Modulation(1))), ...
    "UL closed-loop AMC must update modulation across frames.");

cfgNoCQI = sixgr.util.structSet(cfg, "phy.csi.reportCQI", false);

dlNoCQI = sixgr.link.runDLPDSCHThroughput(cfgNoCQI, "NumFrames", 3, "SNR_dB", 24);
assert(all(~isfinite(double(dlNoCQI.TrialTable.WidebandCQI))), ...
    "DL closed-loop AMC must leave CQI unavailable when no measured CQI was reported.");
assert(~any(dlNoCQI.TrialTable.LinkAdaptationScheduled), ...
    "DL closed-loop AMC must not schedule updates from synthesized CQI when measurement-backed CQI is unavailable.");
assert(all(double(dlNoCQI.TrialTable.MCS) == double(dlNoCQI.TrialTable.MCS(1))), ...
    "DL closed-loop AMC must keep MCS fixed when measured CQI is unavailable.");

ulNoCQI = sixgr.link.runULPUSCHThroughput(cfgNoCQI, "NumFrames", 3, "SNR_dB", 24);
assert(all(~isfinite(double(ulNoCQI.TrialTable.WidebandCQI))), ...
    "UL closed-loop AMC must leave CQI unavailable when no measured CQI was reported.");
assert(~any(ulNoCQI.TrialTable.LinkAdaptationScheduled), ...
    "UL closed-loop AMC must not schedule updates from synthesized CQI when measurement-backed CQI is unavailable.");
assert(all(double(ulNoCQI.TrialTable.MCS) == double(ulNoCQI.TrialTable.MCS(1))), ...
    "UL closed-loop AMC must keep MCS fixed when measured CQI is unavailable.");

ok = true;
end
