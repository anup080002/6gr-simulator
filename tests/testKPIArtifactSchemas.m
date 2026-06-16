function ok = testKPIArtifactSchemas()
%TESTKPIARTIFACTSCHEMAS Exported KPI audit artifacts must have required schemas.

setup6GRSimToolkit("Verbose", false);

tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>

raw = struct();
raw.UL = localDirectionTable("UL", 7.952);
raw.DL = localDirectionTable("DL", 40.137091);
kpiTable = table(["DL_PDSCH_Throughput"; "UL_PUSCH_Throughput"], [true; true], [false; false], ...
    'VariableNames', {'Case','Ok','Skipped'});
details = struct("RawTrials", raw, "Config", struct("run", struct("strictMode", true)));

sixgr.link.exportLinkKPIs(tmp, kpiTable, details, "SaveCSV", true, "SaveMAT", false, "SaveFigures", false);

reportDir = fullfile(tmp, "reports", "csv");
files = ["kpi_formula_registry.csv","kpi_source_table_manifest.csv", ...
    "kpi_raw_table_schema_audit.csv","kpi_reconstruction_summary.csv", ...
    "kpi_row_contributions_ul.csv","kpi_row_contributions_dl.csv", ...
    "kpi_harq_delivery_trace_ul.csv","kpi_harq_delivery_trace_dl.csv", ...
    "kpi_direction_isolation_audit.csv","kpi_legacy_alias_map.csv", ...
    "kpi_known_bug_regression.csv","kpi_unit_conversion_audit.csv", ...
    "kpi_duration_source_audit.csv","kpi_objective_binding.csv"];
for i = 1:numel(files)
    path = fullfile(reportDir, files(i));
    assert(exist(path, "file") == 2, "Missing KPI artifact: %s", files(i));
    T = readtable(path, "VariableNamingRule", "preserve");
    assert(istable(T) && width(T) > 0, "KPI artifact has no schema columns: %s", files(i));
end

recon = readtable(fullfile(reportDir, "kpi_reconstruction_summary.csv"), "VariableNamingRule", "preserve");
requiredRecon = ["KPIName","Direction","FormulaId","SourceRowsHash","ReconciliationPass","StrictOk"];
assert(all(ismember(requiredRecon, string(recon.Properties.VariableNames))), ...
    "KPI reconstruction summary is missing required contract columns.");

ok = true;
end

function T = localDirectionTable(direction, goodput)
T = table( ...
    repmat(string(direction), 2, 1), [goodput; 0], [true; false], [0; 1], [1000; 1000], ...
    [1000; 1000], [1000; 0], [1; 1], [1; 2], string([direction + "_tb_1"; direction + "_tb_2"]), ...
    [0; 0], [0; 0], [0; 1], [1; 1], [1; 2], ...
    'VariableNames', {'Direction','Goodput_Mbps','CRCPass','BitErrors','BitsCompared', ...
    'TBSize_bits','GoodBits','Frame','Slot','TransportBlockId','HARQProcessId','RV','NDI', ...
    'AirInterfaceObservation_ms','TrialId'});
end
