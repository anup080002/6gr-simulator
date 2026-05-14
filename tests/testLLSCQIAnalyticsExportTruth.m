function ok = testLLSCQIAnalyticsExportTruth()
%TESTLLSCQIANALYTICSEXPORTTRUTH Scheduler-derived CQI exports must not show CQI 0.

setup6GRSimToolkit("Verbose", false);
sixgr.db.deactivateArtifactStore();

tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>

runFolder = fullfile(tmp, "run");
layout = sixgr.report.resultLayout(runFolder);
localEnsureDirs({layout.ReportCSVDir, layout.PacketFlowCSVDir, layout.RFCSVDir, ...
    layout.SystemCSVDir, layout.ControlCSVDir, layout.AirInterfaceCSVDir, layout.BeamformingCSVDir});

scfg = struct("ScenarioID", "CQI_EXPORT_TRUTH", "ConfigHash", "unit_hash");
cfg = sixgr.config.defaultConfig();

localWrite(fullfile(layout.ReportCSVDir, "scenario_summary.csv"), table( ...
    "CQI_EXPORT_TRUTH", true, 0, ...
    'VariableNames', {'ScenarioID','ResultOk','RequiredFailureCount'}));

grantT = table( ...
    [1; 1], ...
    [7; 7], ...
    [0.5; 1.0], ...
    [101; 202], ...
    [1; 1], ...
    [0; 8], ...
    [12; 24], ...
    [0; 2], ...
    [12; 12], ...
    [0; 7], ...
    [0; 10], ...
    [0.1171875; 0.6015625], ...
    [3368; 14088], ...
    [false; false], ...
    ["new_data_pf"; "new_data_pf"], ...
    'VariableNames', {'Frame','Slot','Time_s','UE','CellID','PRBStart','PRBCount','SymbolStart','NumSymbols', ...
    'CQIUsed','MCSIndex','TargetCodeRate','TBSBits','IsRetransmission','GrantReason'});

localWrite(fullfile(layout.PacketFlowCSVDir, "live_dl_scheduler_grants.csv"), grantT);
localWrite(fullfile(layout.PacketFlowCSVDir, "live_ul_scheduler_grants.csv"), grantT);

sixgr.truth.exportLLSOutputCoverageArtifacts(runFolder, scfg, cfg);

cqiTablePath = fullfile(layout.ReportCSVDir, "table_cqi_pmi_ri.csv");
mcsTablePath = fullfile(layout.ReportCSVDir, "table_mcs_tbs_evolution.csv");

assert(exist(cqiTablePath, "file") == 2, ...
    "CQI export truth regression must materialize table_cqi_pmi_ri.csv.");
assert(exist(mcsTablePath, "file") == 2, ...
    "CQI export truth regression must materialize table_mcs_tbs_evolution.csv.");

cqiT = readtable(cqiTablePath, "VariableNamingRule", "preserve");
mcsT = readtable(mcsTablePath, "VariableNamingRule", "preserve");

localAssertCQIColumnTruth(cqiT, "wideband_cqi", 101, 202, "table_cqi_pmi_ri");
localAssertCQIColumnTruth(mcsT, "cqi_input", 101, 202, "table_mcs_tbs_evolution");

ok = true;
end

function localAssertCQIColumnTruth(T, colName, zeroUE, validUE, label)
assert(istable(T) && ismember(colName, string(T.Properties.VariableNames)), ...
    "%s must expose %s.", label, colName);
vals = double(T.(colName));
finiteVals = vals(isfinite(vals));
assert(~any(finiteVals == 0), ...
    "%s must not export CQI index 0 as a valid reported CQI.", label);
assert(all(finiteVals >= 1 & finiteVals <= 15), ...
    "%s must keep finite CQI values inside the NR-reported 1..15 range.", label);

ueVals = double(T.ue_id);
zeroMask = ueVals == double(zeroUE);
validMask = ueVals == double(validUE);
assert(any(zeroMask), "%s must include the zero-placeholder scheduler observation.", label);
assert(any(validMask), "%s must include the valid scheduler observation.", label);
assert(all(~isfinite(vals(zeroMask))), ...
    "%s must turn placeholder CQIUsed=0 into NaN/unavailable.", label);
assert(all(vals(validMask) == 7), ...
    "%s must preserve valid CQIUsed=7 exactly.", label);
end

function localEnsureDirs(paths)
for i = 1:numel(paths)
    if exist(paths{i}, "dir") ~= 7
        mkdir(paths{i});
    end
end
end

function localWrite(pathStr, T)
[folder, ~, ~] = fileparts(pathStr);
if exist(folder, "dir") ~= 7
    mkdir(folder);
end
writetable(T, pathStr);
end
