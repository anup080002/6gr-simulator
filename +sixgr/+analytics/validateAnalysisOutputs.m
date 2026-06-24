function report = validateAnalysisOutputs(runDir)
%VALIDATEANALYSISOUTPUTS Validate post-run analysis artifact presence/schema.

arguments
    runDir {mustBeTextScalar}
end

layout = sixgr.report.resultLayout(runDir);
expected = [
    "reports/csv/physics_audit_table.csv"
    "reports/csv/per_slot_kpi_table.csv"
    "reports/csv/per_ue_slot_kpi_table.csv"
    "reports/csv/full_physics_timeline.csv"
    "reports/csv/control_plane_timeline.csv"
    "air_interface/csv/lls_snr_sweep.csv"
    "reports/csv/nmse_vs_snr.csv"
    "reports/csv/energy_vs_throughput.csv"
    "reports/csv/tbs_reference_comparison.csv"
    "reports/csv/shannon_capacity_gap.csv"
    "reports/csv/trs_doppler_error_trace.csv"
    "reports/csv/mobility_adequacy_report.csv"
    "air_interface/csv/harq_combining_gain.csv"
    "reports/csv/runtime_call_graph.csv"
    "reports/json/scenario_manifest.json"
    "reports/html/access_delay_cdf.html"
    "reports/html/harq_combining_gain.html"
    "reports/html/master_dashboard.html"
    ];
rows = repmat(struct("Artifact", "", "Exists", false, "RowCount", NaN, "ColumnCount", NaN, "Status", ""), numel(expected), 1);
for i = 1:numel(expected)
    logicalPath = expected(i);
    fullPath = fullfile(runDir, strrep(logicalPath, "/", filesep));
    rows(i).Artifact = logicalPath;
    rows(i).Exists = exist(fullPath, "file") == 2;
    rows(i).Status = "missing";
    if rows(i).Exists
        if endsWith(logicalPath, ".csv")
            try
                T = readtable(fullPath, "VariableNamingRule", "preserve");
                rows(i).RowCount = height(T);
                rows(i).ColumnCount = width(T);
                rows(i).Status = "present";
            catch ME
                rows(i).Status = "unreadable:" + string(ME.identifier);
            end
        else
            rows(i).RowCount = NaN;
            rows(i).ColumnCount = NaN;
            rows(i).Status = "present";
        end
    end
end
T = struct2table(rows, "AsArray", true);
sixgr.analytics.writeAnalysisTable(fullfile(layout.ReportCSVDir, "analysis_output_validation.csv"), T);
report = struct("Table", T, "Ok", all(T.Exists));
end

function mustBeTextScalar(x)
if ~(ischar(x) || (isstring(x) && isscalar(x)))
    error("sixgr:analytics:validateAnalysisOutputs:BadRunDir", "runDir must be a char vector or string scalar.");
end
end
