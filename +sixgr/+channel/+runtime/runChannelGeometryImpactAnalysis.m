function result = runChannelGeometryImpactAnalysis(varargin)
%RUNCHANNELGEOMETRYIMPACTANALYSIS Fail-closed Phase-10 impact entry point.
%
% The paired 768-experiment campaign is not allowed to start until every
% base contracted artifact is qualified. This prevents component anchors
% from being promoted to waveform/statistical impact truth.

parser = inputParser;
parser.addParameter("BaseDir", fullfile(pwd,"artifacts","channel_geometry_phase"));
parser.addParameter("OutputDir", fullfile(pwd,"artifacts","channel_geometry_impact"));
parser.addParameter("ExperimentMatrix", fullfile(pwd,"tests","vectors", ...
    "channel","channel_impact_experiment_matrix.csv"));
parser.addParameter("SeedList", [11 23 47 89 131 197], ...
    @(x) isnumeric(x) && isvector(x) && all(isfinite(x)));
parser.addParameter("ConfidenceLevel", 0.95, ...
    @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x > 0 && x < 1);
parser.addParameter("Strict", true, ...
    @(x) (islogical(x) || isnumeric(x)) && isscalar(x));
parser.parse(varargin{:});
baseDir = char(string(parser.Results.BaseDir));
outputDir = char(string(parser.Results.OutputDir));
if ~logical(parser.Results.Strict)
    error("CHANNEL:StrictFallbackForbidden", ...
        "Phase-10 impact evidence can only run in strict mode.");
end
sixgr.util.ensureFolder(outputDir);
gatePath = fullfile(baseDir,"channel_phase10_gate_report.csv");
if exist(gatePath,"file") ~= 2
    reason = "base_gate_report_missing";
    localWriteGate(outputDir,reason);
    error("CHANNEL:BasePhaseIncomplete", ...
        "Phase-10 impact analysis requires a completed base gate.");
end
gate = readtable(gatePath,"TextType","string");
if ~all(gate.Status=="PASS")
    missing = string(gate.Artifact(gate.Status~="PASS"));
    reason = "base_artifacts_incomplete:" + strjoin(missing,"|");
    localWriteGate(outputDir,reason);
    error("CHANNEL:BasePhaseIncomplete", ...
        "Phase-10 impact analysis is blocked by base artifacts: %s.", ...
        strjoin(cellstr(missing),", "));
end
error("CHANNEL:ImpactRunnerNotQualified", ...
    "The base gate passed, but no qualified 768-experiment impact runner is installed.");
end

function localWriteGate(outputDir,reason)
gate = table("channel_geometry_impact",false,string(reason),"FAIL", ...
    'VariableNames',{'Campaign','Started','Reason','Status'});
sixgr.util.csvWriteTable(fullfile(outputDir,"channel_impact_gate_report.csv"),gate);
end
