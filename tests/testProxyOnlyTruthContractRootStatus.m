function ok = testProxyOnlyTruthContractRootStatus()
%TESTPROXYONLYTRUTHCONTRACTROOTSTATUS Proxy studies still publish root state.

root = tempname;
layout = sixgr.report.resultLayout(root);
sixgr.util.ensureDir(fullfile(layout.ReportCSVDir, ".keep"));
sixgr.util.ensureDir(fullfile(layout.ReportDir, "json", ".keep"));
cleanup = onCleanup(@() localRemove(root)); %#ok<NASGU>

summary = table("proxy_root_unit", "proxy_ai_study", "completed", true, ...
    'VariableNames', {'RunTag','ScenarioID','RunCompletion','ResultOk'});
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, ...
    "scenario_summary.csv"), summary);

scfg = struct();
scfg = sixgr.util.structSet(scfg, "meta.scenario_id", "proxy_ai_study");
scfg = sixgr.util.structSet(scfg, "meta.research_class", ...
    "optional_research_experiment");
scfg = sixgr.util.structSet(scfg, "scenario.name", ...
    "AI component benchmark; not a PHY truth or conformance claim");
scfg = sixgr.util.structSet(scfg, "scenario.runner_profile", "ai_benchmark");
scfg = sixgr.util.structSet(scfg, "scenario.target_cases", "srs");
scfg = sixgr.util.structSet(scfg, "simulation.link_direction", "both");
scfg = sixgr.util.structSet(scfg, "validation.run_class", ...
    "adaptive_system_diagnostic");
cfg = struct("run", struct("runTag", "proxy_root_unit", ...
    "runnerProfile", "ai_benchmark"));

verdict = sixgr.truth.evaluateLLSRuntimeTruthContract( ...
    root, scfg, cfg, "Result", struct("Ok", true));
assert(verdict.ContractApplicability == ...
    "not_applicable_proxy_only_study");
assert(~verdict.RequiredDL && ~verdict.RequiredUL, ...
    "Proxy-only AI studies must not claim DL/UL waveform truth.");
assert(isfield(verdict, "ResultStatus") && isstruct(verdict.ResultStatus), ...
    "Proxy-only studies must still return canonical root status.");
assert(isfile(fullfile(layout.ReportCSVDir, ...
    "result_status_summary.csv")) && ...
    isfile(fullfile(layout.ReportDir, "json", ...
    "result_status_summary.json")), ...
    "Proxy-only finalization requires the canonical root CSV/JSON pair.");
% Post-finalization reduction must be able to consume the pair.  The tiny
% fixture intentionally omits full KPI/issue-registry evidence, so its
% overall functional verdict may remain fail closed.
sixgr.artifact.updateRootStatusArtifacts(root, verdict.ResultStatus);
assert(~logical(verdict.ResultStatus.PublicationQualified), ...
    "A proxy-only AI study must never be publication-qualified as PHY truth.");

ok = true;
fprintf("PASS testProxyOnlyTruthContractRootStatus: root lifecycle retained without truth relabeling.\n");
end

function localRemove(pathValue)
if isfolder(pathValue)
    rmdir(pathValue, "s");
end
end
