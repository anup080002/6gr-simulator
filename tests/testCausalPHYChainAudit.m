function ok = testCausalPHYChainAudit()
%TESTCAUSALPHYCHAINAUDIT Focused fail-closed causal wiring audit tests.

setup6GRSimToolkit("Verbose", false);
root = fileparts(fileparts(mfilename("fullpath")));
runFolder = tempname;
mkdir(runFolder);
cleanup = onCleanup(@() localCleanup(runFolder)); %#ok<NASGU>
layout = sixgr.report.resultLayout(runFolder);
sixgr.util.ensureFolder(layout.ReportCSVDir);
sixgr.util.ensureFolder(fullfile(runFolder, "measured"));

sourceFile = "+sixgr/+truth/exportCausalPHYChainAudit.m";
profileT = table(1, string(fullfile(root, char(sourceFile))), 3, 0.125, ...
    'VariableNames', {'ProfileRank','FileName','NumCalls','TotalTime_s'});
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, ...
    "runtime_function_profile.csv"), profileT);
measuredT = table((1:3).', [true; false; true], ...
    'VariableNames', {'Sample','DecodeOK'});
sixgr.util.csvWriteTable(fullfile(runFolder, "measured", "stage.csv"), measuredT);

stage = struct( ...
    "stage_id", "truth_stage", "order", 10, "subsystem", "unit", ...
    "required", true, "always_required", true, ...
    "consumer_source_files", sourceFile, ...
    "measurement_artifact", "measured/stage.csv", ...
    "measured_fields", {{"Sample","DecodeOK"}}, ...
    "measurement_min_rows", 2, "success_field", "DecodeOK", ...
    "success_mode", "any_true");
binding = struct( ...
    "parameter_id", "timing_k", "subsystem", "timing", ...
    "scenario_path", "timing.k", "runtime_path", "phy.timing.k", ...
    "required", true, "consumer_source_files", sourceFile);
auditCfg = struct("enabled", true, "required", true, ...
    "fail_on_enabled_bypass", true, ...
    "require_config_mapping_match", true, ...
    "require_runtime_consumer", true, ...
    "require_measurement_evidence", true, ...
    "stages", stage, "parameter_bindings", binding);
scfg = struct("validation", struct("causal_phy_chain_audit", auditCfg), ...
    "timing", struct("k", 4));
cfg = struct("validation", struct("causal_phy_chain_audit", auditCfg), ...
    "phy", struct("timing", struct("k", 4)), ...
    "meta", struct("configHash", "unit_hash"));

out = sixgr.truth.exportCausalPHYChainAudit(runFolder, scfg, cfg, ...
    "RunId", "causal_unit");
assert(out.Ok && out.FailureCount == 0);
assert(out.DetailTable.StageOutcome(1) == "PASS");
assert(out.ParameterBindingTable.Status(1) == "PASS");
assert(all(isfile([out.DetailPath; out.ParameterBindingPath; out.GatePath])));

% The Top-50 inventory consumes the persisted causal audit as the exact
% source for its end-to-end chain-status visual.  This guards both the
% explicit semantic schema and the production ordering requirement that
% exportCausalPHYChainAudit runs before output-coverage finalization.
top50 = sixgr.truth.exportTop50VisualizationEvidenceInventory(runFolder, cfg);
chainRow = top50.InventoryTable(top50.InventoryTable.VisualID == 2, :);
assert(height(chainRow) == 1);
assert(chainRow.AvailabilityStatus == "validated_reconstructible");
assert(chainRow.ResolvedSourceArtifact == "reports/csv/causal_phy_chain_audit.csv");
assert(chainRow.SourceRowCount == 1);

% Enabled stage, exact consumer call, but no measured artifact must fail as
% CALLED_NO_MEASUREMENT rather than being inferred from configuration.
scfg.validation.causal_phy_chain_audit.stages.measurement_artifact = ...
    "measured/absent.csv";
cfg.validation.causal_phy_chain_audit = ...
    scfg.validation.causal_phy_chain_audit;
out = sixgr.truth.exportCausalPHYChainAudit(runFolder, scfg, cfg, ...
    "RunId", "missing_measurement", "WriteArtifacts", false);
assert(~out.Ok);
assert(out.DetailTable.StageOutcome(1) == "CALLED_NO_MEASUREMENT");

% The converse must also fail: configuration and a persisted measurement
% file cannot stand in for an exact runtime consumer call.
notCalledStage = stage;
notCalledStage.stage_id = "enabled_not_called_stage";
notCalledStage.consumer_source_files = ...
    "+sixgr/+phy/+ul/PUSCH_Rx.m";
scfg.validation.causal_phy_chain_audit.stages = notCalledStage;
cfg.validation.causal_phy_chain_audit = ...
    scfg.validation.causal_phy_chain_audit;
out = sixgr.truth.exportCausalPHYChainAudit(runFolder, scfg, cfg, ...
    "RunId", "enabled_not_called", "WriteArtifacts", false);
assert(~out.Ok);
assert(out.DetailTable.StageOutcome(1) == "ENABLED_NOT_CALLED");

% A YAML-disabled feature whose exact consumer appears in the profiler is
% an explicit bypass and must fail even though the stage is not applicable.
disabledStage = rmfield(stage, "always_required");
disabledStage.stage_id = "disabled_stage";
disabledStage.feature_authority = "unit_feature";
scfg.feature_enabled = false;
scfg.validation.causal_phy_chain_audit.stages = disabledStage;
cfg.runtime.features.unit_feature = struct( ...
    "Enabled", false, "SourceYAMLPath", "feature_enabled", ...
    "RuntimeConsumerPaths", "phy.unitFeatureEnabled");
cfg.phy.unitFeatureEnabled = false;
cfg.validation.causal_phy_chain_audit = ...
    scfg.validation.causal_phy_chain_audit;
out = sixgr.truth.exportCausalPHYChainAudit(runFolder, scfg, cfg, ...
    "RunId", "disabled_bypass", "WriteArtifacts", false);
assert(~out.Ok);
assert(out.DetailTable.StageOutcome(1) == "DISABLED_BUT_CALLED");

fprintf('%s\n', char("Causal PHY-chain audit: pass, called-without-measurement, " + ...
    "enabled-not-called, and disabled-bypass gates verified."));
ok = true;
end

function localCleanup(pathValue)
if isfolder(pathValue)
    rmdir(pathValue, "s");
end
end
