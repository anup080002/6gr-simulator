function summary = runTwoModeLLS(mode, varargin)
%RUNTWOMODELLS Run or prepare the two WebGUI LLS validation scenarios.
%
%   summary = sixgr.tools.runTwoModeLLS("smoke")
%   summary = sixgr.tools.runTwoModeLLS("full")
%
% Supported name-value pairs:
%   "ResultsRoot"  - Root folder for run outputs and summary CSVs.
%   "PrepareOnly"  - When true, return the execution plan without running.
%   "WriteSummary" - When true, write results/two_mode_*_summary.csv.
%   "Verbose"      - Print console progress and summary lines.

p = inputParser;
p.addRequired("mode", @(x)isstring(x) || ischar(x));
p.addParameter("ResultsRoot", "", @(x)isstring(x) || ischar(x));
p.addParameter("PrepareOnly", false, @(x)islogical(x) || (isnumeric(x) && isscalar(x)));
p.addParameter("WriteSummary", true, @(x)islogical(x) || (isnumeric(x) && isscalar(x)));
p.addParameter("Verbose", true, @(x)islogical(x) || (isnumeric(x) && isscalar(x)));
p.addParameter("RunTagPrefix", "", @(x)isstring(x) || ischar(x));
p.parse(mode, varargin{:});
opt = p.Results;

mode = lower(strtrim(string(mode)));
if ~ismember(mode, ["smoke","full"])
    error("sixgr:tools:runTwoModeLLS:UnsupportedMode", ...
        "Mode must be 'smoke' or 'full', not '%s'.", char(mode));
end

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);

repoRoot = localRepoRoot();
resultsRoot = char(string(opt.ResultsRoot));
if strlength(string(resultsRoot)) == 0
    resultsRoot = fullfile(repoRoot, "results");
end
summaryPath = fullfile(resultsRoot, sprintf("two_mode_%s_summary.csv", char(mode)));

plan = localBuildPlan(mode, repoRoot, resultsRoot, char(string(opt.RunTagPrefix)));
summary = struct();
summary.Mode = string(mode);
summary.RepoRoot = string(repoRoot);
summary.ResultsRoot = string(resultsRoot);
summary.SummaryCSV = string(summaryPath);
summary.Prepared = logical(opt.PrepareOnly);
summary.Executed = false;
summary.Ok = false;
summary.Runs = plan;
summary.Table = table();
summary.FailureCodes = strings(0, 1);

if logical(opt.PrepareOnly)
    summary.Ok = true;
    summary.Status = "prepared";
    return;
end

sixgr.util.ensureFolder(resultsRoot);
rows = repmat(localEmptySummaryRow(), numel(plan), 1);
if logical(opt.Verbose)
    fprintf("[two-mode-%s] Results root: %s\n", char(mode), resultsRoot);
end

for i = 1:numel(plan)
    row = localEmptySummaryRow();
    item = plan(i);
    row.Mode = string(mode);
    row.ScenarioLabel = string(item.ScenarioLabel);
    row.BaseScenarioYAML = string(item.BaseScenarioYAML);
    row.RuntimeScenarioYAML = string(item.RuntimeScenarioYAML);
    row.RunTag = string(item.RunTag);
    row.ExpectedRunClass = string(item.ExpectedRunClass);
    row.ScenarioAuditKind = string(item.ScenarioAuditKind);
    row.OverrideApplied = logical(item.OverrideApplied);
    row.OverridePathsJSON = localJSONString(string(item.OverridePaths));
    row.AuditCSV = string(item.AuditCSV);

    if logical(opt.Verbose)
        fprintf("[two-mode-%s] Running %s using %s\n", ...
            char(mode), char(item.ScenarioLabel), char(item.RuntimeScenarioYAML));
    end

    try
        out = run_6g_phy_lls_single(item.RuntimeScenarioYAML, resultsRoot, item.RunTag);
        row.RunnerOk = logical(sixgr.util.structGet(out, "Ok", false));
        row.RunFolder = string(sixgr.util.structGet(out, "RunFolder", ""));
    catch ME
        row.RunnerOk = false;
        row.Status = "FAIL";
        row.FailureCodes = string(ME.identifier);
        row.ExceptionIdentifier = string(ME.identifier);
        row.ExceptionMessage = string(ME.message);
        rows(i) = row;
        continue;
    end

    runFolder = char(string(row.RunFolder));
    if strlength(string(runFolder)) == 0 || exist(runFolder, "dir") ~= 7
        row.Status = "FAIL";
        row.FailureCodes = "run_folder_missing";
        rows(i) = row;
        continue;
    end

    try
        switch lower(char(item.ScenarioAuditKind))
            case "fixed_snr"
                scenarioAudit = sixgr.validation.auditFixedSNRSweepRun(runFolder, "Strict", false, "WriteOutputs", true);
            case "geometry"
                scenarioAudit = sixgr.validation.auditGeometryScenarioRun(runFolder, "Strict", false, "WriteOutputs", true);
            otherwise
                error("sixgr:tools:runTwoModeLLS:UnknownAuditKind", ...
                    "Unknown scenario audit kind '%s'.", char(item.ScenarioAuditKind));
        end
        artifactAudit = sixgr.validation.auditRunArtifacts(runFolder, "Strict", false, "WriteOutputs", true);
    catch ME
        row.Status = "FAIL";
        row.FailureCodes = string(ME.identifier);
        row.ExceptionIdentifier = string(ME.identifier);
        row.ExceptionMessage = string(ME.message);
        rows(i) = row;
        continue;
    end

    row.RunClass = string(localStructGetText(scenarioAudit, "RunClass", ""));
    row.ScenarioAuditOk = logical(sixgr.util.structGet(scenarioAudit, "Ok", false));
    row.ScenarioAuditFailures = double(sixgr.util.structGet(scenarioAudit, "FailureCount", 0));
    row.ScenarioAuditWarnings = double(sixgr.util.structGet(scenarioAudit, "WarningCount", 0));
    row.ArtifactAuditOk = logical(sixgr.util.structGet(artifactAudit, "Ok", false));
    row.ArtifactAuditFailures = double(sixgr.util.structGet(artifactAudit, "FailureCount", 0));
    row.ArtifactAuditWarnings = double(sixgr.util.structGet(artifactAudit, "WarningCount", 0));
    row.OverallOk = logical(row.RunnerOk) && logical(row.ScenarioAuditOk) && logical(row.ArtifactAuditOk);
    row.Status = localTernary(row.OverallOk, "PASS", "FAIL");
    row.FailureCodes = strjoin(unique([ ...
        localStringVector(sixgr.util.structGet(scenarioAudit, "FailureCodes", strings(0, 1))); ...
        localStringVector(sixgr.util.structGet(artifactAudit, "FailureCodes", strings(0, 1)))], "stable"), ";");
    row.WarningCodes = strjoin(unique([ ...
        localStringVector(sixgr.util.structGet(scenarioAudit, "WarningCodes", strings(0, 1))); ...
        localStringVector(sixgr.util.structGet(artifactAudit, "WarningCodes", strings(0, 1)))], "stable"), ";");
    rows(i) = row;

    if logical(opt.Verbose)
        fprintf("[two-mode-%s] %s -> %s (scenario audit ok=%d, artifact audit ok=%d)\n", ...
            char(mode), char(item.ScenarioLabel), char(row.Status), ...
            double(row.ScenarioAuditOk), double(row.ArtifactAuditOk));
    end
end

summaryTable = struct2table(rows, "AsArray", true);
summary.Table = summaryTable;
summary.Executed = true;
summary.Ok = all(summaryTable.OverallOk);
summary.Status = localTernary(summary.Ok, "pass", "fail");
failCodes = strings(0, 1);
if height(summaryTable) > 0 && ismember("FailureCodes", summaryTable.Properties.VariableNames)
    for i = 1:height(summaryTable)
        parts = split(string(summaryTable.FailureCodes(i)), ";");
        parts = strtrim(parts(parts ~= ""));
        failCodes = [failCodes; parts(:)]; %#ok<AGROW>
    end
end
summary.FailureCodes = unique(failCodes, "stable");

if logical(opt.WriteSummary)
    sixgr.util.ensureFolder(fileparts(summaryPath));
    sixgr.analytics.writeAnalysisTable(summaryPath, summaryTable);
end

if logical(opt.Verbose)
    localPrintConsoleSummary(summary);
end

if ~summary.Ok
    error("sixgr:tools:runTwoModeLLS:AuditFailed", ...
        "Two-mode %s run failed. See %s for per-scenario audit results.", ...
        char(mode), summaryPath);
end
end

function plan = localBuildPlan(mode, repoRoot, resultsRoot, runTagPrefix)
resultsRoot = char(string(resultsRoot)); %#ok<NASGU>
switch mode
    case "smoke"
        snrBase = "simulator/configs/scenarios/lls_true_snr_sweep_awgn_1ue.yaml";
        snrRuntime = fullfile(repoRoot, "simulator", "configs", "scenarios", ...
            "lls_true_snr_sweep_awgn_1ue_smoke.yaml");
        geometryBase = "simulator/configs/scenarios/lls_true_geometry_2cell_2ue_200kmh.yaml";
        geometryRuntime = fullfile(repoRoot, "simulator", "configs", "scenarios", ...
            "lls_true_geometry_2cell_2ue_200kmh_smoke.yaml");
        tagPrefix = string(localDefaultTagPrefix(runTagPrefix, "two_mode_smoke"));
        plan = [
            localPlanRow("fixed_snr_sweep", repoRoot, snrBase, snrRuntime, ...
                tagPrefix + "_snr", "fixed_snr_sweep_lls", "fixed_snr", true, localSmokeSNROverridePaths(), ...
                "reports/csv/fixed_snr_sweep_audit.csv")
            localPlanRow("geometry_placement", repoRoot, geometryBase, geometryRuntime, ...
                tagPrefix + "_geometry", "ue_placement_geometry_lls", "geometry", true, localSmokeGeometryOverridePaths(), ...
                "reports/csv/geometry_runtime_audit.csv")
            ];
    case "full"
        tagPrefix = string(localDefaultTagPrefix(runTagPrefix, "two_mode_full"));
        plan = [
            localPlanRow("fixed_snr_sweep", repoRoot, "simulator/configs/scenarios/lls_true_snr_sweep_awgn_1ue.yaml", ...
                fullfile(repoRoot, "simulator", "configs", "scenarios", "lls_true_snr_sweep_awgn_1ue.yaml"), ...
                tagPrefix + "_snr", "fixed_snr_sweep_lls", "fixed_snr", false, strings(0, 1), ...
                "reports/csv/fixed_snr_sweep_audit.csv")
            localPlanRow("geometry_placement", repoRoot, "simulator/configs/scenarios/lls_true_geometry_2cell_2ue_200kmh.yaml", ...
                fullfile(repoRoot, "simulator", "configs", "scenarios", "lls_true_geometry_2cell_2ue_200kmh.yaml"), ...
                tagPrefix + "_geometry", "ue_placement_geometry_lls", "geometry", false, strings(0, 1), ...
                "reports/csv/geometry_runtime_audit.csv")
            ];
    otherwise
        error("sixgr:tools:runTwoModeLLS:UnsupportedMode", "Unsupported mode '%s'.", char(mode));
end
end

function paths = localSmokeSNROverridePaths()
paths = [ ...
        "canonical_control.run.fixed_link_snr_grid_db"
        "canonical_control.run.snr_db"
        "canonical_control.run.noise_operating_mode"
        "canonical_control.run.min_trials_per_sinr_bin"
        "canonical_control.run.max_trials_per_sinr_bin"
        "canonical_control.run.num_workers"
        "canonical_control.run.batch_size_links"
        "canonical_control.run.auto_start_parallel_pool"
        "run_control.num_workers"
        "run_control.batch_size_links"
        "run_control.auto_start_parallel_pool"
        "simulation.snr_db"
        "simulation.noise_operating_mode"
        "validation.fixed_link_campaign.snr_db"
        "validation.fixed_link_campaign.min_tb_per_point"
        "validation.fixed_link_campaign.max_tb_per_point"
        "sweeps_and_matrix.snr_sweep.values_db"
        "sweeps_and_matrix.fixed_link_calibration.snr_db"
        "sweeps_and_matrix.fixed_link_calibration.min_trials"
        "sweeps_and_matrix.fixed_link_calibration.max_trials"
        "sweeps_and_matrix.fixed_link_calibration.trials_per_drop"
        ];
end

function paths = localSmokeGeometryOverridePaths()
paths = [ ...
        "canonical_control.run.total_slots"
        "canonical_control.run.measurement_slots"
        "canonical_control.run.num_workers"
        "canonical_control.run.batch_size_links"
        "canonical_control.run.auto_start_parallel_pool"
        "run_control.total_slots"
        "run_control.measurement_slots"
        "run_control.num_workers"
        "run_control.batch_size_links"
        "run_control.auto_start_parallel_pool"
        ];
end

function row = localPlanRow(label, repoRoot, baseRel, runtimePath, runTag, expectedRunClass, auditKind, overrideApplied, overridePaths, auditCsv)
row = struct();
row.ScenarioLabel = string(label);
row.BaseScenarioYAML = string(baseRel);
row.BaseScenarioPath = string(fullfile(repoRoot, strrep(char(baseRel), "/", filesep)));
row.RuntimeScenarioYAML = string(runtimePath);
row.RunTag = string(runTag);
row.ExpectedRunClass = string(expectedRunClass);
row.ScenarioAuditKind = string(auditKind);
row.OverrideApplied = logical(overrideApplied);
row.OverridePaths = string(overridePaths(:));
row.AuditCSV = string(auditCsv);
end

function row = localEmptySummaryRow()
row = struct( ...
    "Mode", "", ...
    "ScenarioLabel", "", ...
    "BaseScenarioYAML", "", ...
    "RuntimeScenarioYAML", "", ...
    "RunTag", "", ...
    "RunFolder", "", ...
    "ExpectedRunClass", "", ...
    "RunClass", "", ...
    "ScenarioAuditKind", "", ...
    "AuditCSV", "", ...
    "OverrideApplied", false, ...
    "OverridePathsJSON", "[]", ...
    "RunnerOk", false, ...
    "ScenarioAuditOk", false, ...
    "ScenarioAuditFailures", 0, ...
    "ScenarioAuditWarnings", 0, ...
    "ArtifactAuditOk", false, ...
    "ArtifactAuditFailures", 0, ...
    "ArtifactAuditWarnings", 0, ...
    "OverallOk", false, ...
    "Status", "", ...
    "FailureCodes", "", ...
    "WarningCodes", "", ...
    "ExceptionIdentifier", "", ...
    "ExceptionMessage", "");
end

function localPrintConsoleSummary(summary)
fprintf("[two-mode-%s] Summary CSV: %s\n", char(summary.Mode), char(summary.SummaryCSV));
if ~istable(summary.Table) || height(summary.Table) == 0
    fprintf("[two-mode-%s] No scenario rows were recorded.\n", char(summary.Mode));
    return;
end
for i = 1:height(summary.Table)
    fprintf("[two-mode-%s] %-20s status=%s run_class=%s run_folder=%s\n", ...
        char(summary.Mode), char(summary.Table.ScenarioLabel(i)), char(summary.Table.Status(i)), ...
        char(summary.Table.RunClass(i)), char(summary.Table.RunFolder(i)));
end
fprintf("[two-mode-%s] Overall status: %s\n", char(summary.Mode), char(summary.Status));
end

function out = localDefaultTagPrefix(value, fallback)
value = strtrim(string(value));
if strlength(value) == 0
    out = string(fallback);
else
    out = value;
end
end

function txt = localStructGetText(s, fieldName, fallback)
txt = string(sixgr.util.structGet(s, fieldName, fallback));
end

function vals = localStringVector(v)
if isstring(v)
    vals = v(:);
elseif ischar(v)
    vals = string(v);
elseif iscell(v)
    vals = string(v(:));
else
    vals = string(v);
end
vals = vals(strlength(strtrim(vals)) > 0);
end

function txt = localJSONString(values)
values = string(values(:));
values = values(:).';
quoted = strings(size(values));
for i = 1:numel(values)
    value = char(values(i));
    value = strrep(value, "\", "\\");
    value = strrep(value, '"', '\"');
    quoted(i) = """" + string(value) + """";
end
txt = "[" + strjoin(quoted, ", ") + "]";
end

function out = localTernary(tf, ifTrue, ifFalse)
if tf
    out = string(ifTrue);
else
    out = string(ifFalse);
end
end

function root = localRepoRoot()
here = fileparts(mfilename("fullpath"));
root = fileparts(fileparts(here));
end
