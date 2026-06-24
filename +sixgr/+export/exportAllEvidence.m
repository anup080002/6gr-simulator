function report = exportAllEvidence(ctx, cfg, runDir, varargin)
%EXPORTALLEVIDENCE Build post-run Prompt 9 evidence and audit artifacts.
%
% This function composes existing exporters. It does not create primary
% placeholder rows when runtime evidence is absent.

p = inputParser;
p.addParameter("RunAnalysis", false, @(x)islogical(x) || isnumeric(x));
p.addParameter("ErrorOnOracleViolation", false, @(x)islogical(x) || isnumeric(x));
p.parse(varargin{:});
opt = p.Results;

if nargin < 1 || isempty(ctx)
    ctx = struct();
end
if nargin < 2 || isempty(cfg)
    cfg = struct();
end
runDir = char(string(runDir));
if exist(runDir, "dir") ~= 7
    error("sixgr:export:exportAllEvidence:RunDirMissing", "Run directory does not exist: %s", runDir);
end

layout = sixgr.report.resultLayout(runDir);
rows = repmat(struct("StageName", "", "Status", "", "Ok", false, "Message", ""), 0, 1);
report = struct("Ok", true, "Stages", table(), "RunDir", string(runDir));

[report, rows] = localRunStage(report, rows, "provenance_manifest", ...
    @() sixgr.truth.buildProvenanceManifest(cfg, runDir), runDir);
[report, rows] = localRunStage(report, rows, "phase7_readiness", ...
    @() sixgr.analytics.buildPhase7ReadinessArtifacts(cfg, runDir), runDir);
[report, rows] = localRunStage(report, rows, "measurement_only_audit", ...
    @() sixgr.audit.verifyMeasurementOnly(runDir, "ErrorOnViolation", logical(opt.ErrorOnOracleViolation)), runDir);

if logical(opt.RunAnalysis)
    [report, rows] = localRunStage(report, rows, "run_analysis", ...
        @() run_analysis(runDir, cfg), runDir);
else
    rows(end+1, 1) = struct("StageName", "run_analysis", "Status", "skipped_by_option", ...
        "Ok", true, "Message", "RunAnalysis option is false"); %#ok<AGROW>
end

report.Stages = struct2table(rows, "AsArray", true);
report.Ok = all(logical(report.Stages.Ok));
sixgr.analytics.writeAnalysisTable(fullfile(layout.ReportCSVDir, "export_all_evidence_status.csv"), report.Stages);
end

function [report, rows] = localRunStage(report, rows, stageName, fn, runDir)
try
    value = sixgr.utils.exportWithTimeout(fn, stageName, 120, runDir);
    report.(char(stageName)) = value;
    stageOk = localStageOk(value);
    rows(end+1, 1) = struct("StageName", string(stageName), "Status", "ok", ...
        "Ok", stageOk, "Message", localStageMessage(value)); %#ok<AGROW>
catch ME
    report.(char(stageName)) = struct("Ok", false, "Identifier", string(ME.identifier), "Message", string(ME.message));
    rows(end+1, 1) = struct("StageName", string(stageName), "Status", "failed", ...
        "Ok", false, "Message", string(ME.identifier) + ": " + string(ME.message)); %#ok<AGROW>
end
end

function tf = localStageOk(value)
tf = true;
if isstruct(value) && isfield(value, "Ok")
    tf = logical(value.Ok);
end
end

function msg = localStageMessage(value)
msg = "";
if isstruct(value) && isfield(value, "Ok") && ~logical(value.Ok)
    msg = "stage returned Ok=false";
    if isfield(value, "ViolationCount")
        msg = msg + "; ViolationCount=" + string(value.ViolationCount);
    end
end
end
