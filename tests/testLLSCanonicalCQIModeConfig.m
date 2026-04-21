function ok = testLLSCanonicalCQIModeConfig()
%TESTLLSCANONICALCQIMODECONFIG Canonical browser LLS scenario keeps the honest default CQI mode.

setup6GRSimToolkit("Verbose", false);

tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>

scenarioPath = fullfile(pwd, "simulator", "configs", "scenarios", ...
    "lls_3gpp_rel20_anchor_4ghz_100mhz_waveform_honest_200ue_1frame.yaml");
scfg = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
cfg = sixgr.lls6g.buildInternalConfig(scfg, fullfile(tmp, "run"));

modeToken = lower(string(sixgr.util.structGet(cfg, "phy.csi.sinrToCQIMode", "")));
assert(strlength(strtrim(modeToken)) == 0 || modeToken == "threshold_table", ...
    "Canonical browser-owned Rel-20 LLS scenario must keep the honest threshold-table CQI default until an effective-SINR calibration is explicitly configured.");
assert(strcmpi(char(string(sixgr.util.structGet(cfg, "phy.csi.cqiTable", ""))), "table1"), ...
    "Canonical browser-owned Rel-20 LLS scenario must keep the resolved NR CQI table wiring.");
assert(abs(double(sixgr.util.structGet(cfg, "phy.csi.targetBLER", 0.1)) - 0.1) < 1e-12, ...
    "Canonical browser-owned Rel-20 LLS scenario must preserve the 10 percent BLER target metadata even when the threshold-table path is active.");

ok = true;
end
