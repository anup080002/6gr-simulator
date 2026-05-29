function ok = testSchedulerAMCNoFixedMCSFallback()
%TESTSCHEDULERAMCNOFIXEDMCSFALLBACK AMC must not promote configured MCS.

setup6GRSimToolkit("Verbose", false);

tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>

scenarioPath = fullfile(pwd, "simulator", "configs", "scenarios", ...
    "lls_3gpp_rel20_anchor_4ghz_100mhz_waveform_honest_200ue_1frame.yaml");
scfg = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
cfg = sixgr.lls6g.buildInternalConfig(scfg, fullfile(tmp, "run"));
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.mode", "amc");
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.dlPolicy", "baseline");
cfg = sixgr.util.structSet(cfg, "phy.pdsch.mcsIndex", 26);

scheduler = sixgr.l2.mac.SchedulerPF(cfg, "Direction", "DL");
ue = struct("CQI", NaN, "RI", 1);
[~, layers, ~, amc] = scheduler.selectAMC(ue);

assert(strcmpi(char(string(amc.Mode)), "cqi_table"), ...
    "AMC mode must stay on the CQI table path when CQI is missing.");
assert(double(amc.MCSIndex) == 0, ...
    "Missing CQI in AMC mode must fall closed to MCS 0, not configured MCS 26.");
assert(double(layers) == 1, ...
    "Scheduler layers must respect the runtime RI when no measured multi-layer RI exists.");

ue.CQI = 3;
[~, ~, ~, amcCQI] = scheduler.selectAMC(ue);
assert(double(amcCQI.MCSIndex) < 26, ...
    "CQI-driven AMC must not reuse the configured fixed MCS override.");

ok = true;
end
