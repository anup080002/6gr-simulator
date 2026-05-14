function ok = testLLSValueSourceAuditObservedSelection()
%TESTLLSVALUESOURCEAUDITOBSERVEDSELECTION Prefer actual observed values over the first empty eligible row.

setup6GRSimToolkit("Verbose", false);

tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>

scenarioPath = fullfile(pwd, "simulator", "configs", "scenarios", "lls_700mhz_20mhz_3bs_30ue_tdlc_browser_coupled.yaml");
scfg = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
cfg = sixgr.lls6g.buildInternalConfig(scfg, fullfile(tmp, "run"));
layout = sixgr.report.resultLayout(fullfile(tmp, "run"));

sixgr.util.ensureDir(layout.ReportCSVDir);
sixgr.util.ensureDir(layout.AirInterfaceCSVDir);

trialT = table( ...
    [0; 0], ...
    [false; false], ...
    [NaN; 7], ...
    [-1.5; 8.2], ...
    [-1.5; 8.2], ...
    'VariableNames', {'Slot','IsWarmupFrame','WidebandCQI','ReceiverHestSINR_dB','MeasuredTrialSINR_dB'});
sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir, "dl_pdsch_trials.csv"), trialT);

artifacts = sixgr.truth.exportLLSConfigOwnershipArtifacts(fullfile(tmp, "run"), scfg, cfg);
valueAuditT = readtable(char(artifacts.ValueSourceAudit), "VariableNamingRule", "preserve");

mask = strcmp(string(valueAuditT.Direction), "DL") & strcmp(string(valueAuditT.FieldName), "WidebandCQI");
assert(any(mask), "value_source_audit.csv must contain a DL WidebandCQI row.");
row = valueAuditT(find(mask, 1, "first"), :);
assert(strcmp(string(row.ObservedValue), "7"), ...
    "Value-source audit must pick the first observed DL WidebandCQI value, not the first empty eligible row.");
assert(strcmp(string(row.ConsistencyStatus), "observed"), ...
    "Value-source audit must mark the DL WidebandCQI row observed when a later eligible trial carries evidence.");

ok = true;
end
