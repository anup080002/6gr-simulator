function out = recoverLLSRunArtifacts(runFolder, scenarioCfg, varargin)
%RECOVERLLSRUNARTIFACTS Rebuild truthful report artifacts from persisted raw evidence.
%
% This recovery path is for failed or aborted runs that still produced raw
% PHY/control/grant artifacts but never reached the normal post-run export
% bundle. It does not fabricate success; it republishes summary, reporting,
% truth-contract, and coverage artifacts from the evidence already on disk.

p = inputParser;
p.addRequired("runFolder", @(x)ischar(x) || isstring(x));
p.addRequired("scenarioCfg", @(x)isa(x, "sixgr.lls6g.config.ScenarioConfig") || isstruct(x) || ischar(x) || isstring(x));
p.addParameter("RunTag", "", @(x)ischar(x) || isstring(x));
p.addParameter("PublicRunFolder", "", @(x)ischar(x) || isstring(x));
p.addParameter("StatusText", "failed", @(x)ischar(x) || isstring(x));
p.addParameter("ErrorIdentifier", "", @(x)ischar(x) || isstring(x));
p.addParameter("ErrorMessage", "", @(x)ischar(x) || isstring(x));
p.addParameter("SourceFiles", strings(0,1), @(x)isstring(x) || iscellstr(x) || ischar(x));
p.addParameter("ConfigPath", "", @(x)ischar(x) || isstring(x));
p.addParameter("ConfigHash", "", @(x)ischar(x) || isstring(x));
p.addParameter("RunID", NaN, @(x) isempty(x) || (isnumeric(x) && isscalar(x)));
p.addParameter("FinalizationMode", "failed_recovery", @(x)ischar(x) || isstring(x));
p.parse(runFolder, scenarioCfg, varargin{:});

runFolder = char(string(p.Results.runFolder));
publicRunFolder = string(p.Results.PublicRunFolder);
if strlength(publicRunFolder) == 0
    publicRunFolder = string(runFolder);
end
layout = sixgr.report.resultLayout(runFolder);
localEnsureDirs(layout);
storedMeta = localReadStoredRunMetadata(runFolder);
[persistedRunTag, persistedRunTagEvidence] = ...
    sixgr.truth.resolvePersistedLLSRunTag(string(runFolder));
finalizationMode = lower(strtrim(string(p.Results.FinalizationMode)));
if ~ismember(finalizationMode, ["failed_recovery", ...
        "completed_run_refinalization", "persisted_trial_refinalization"])
    error("sixgr:truth:recover:InvalidFinalizationMode", ...
        ["FinalizationMode must be failed_recovery, " ...
        "completed_run_refinalization, or persisted_trial_refinalization."]);
end

inputCfg = p.Results.scenarioCfg;
[scfg, recoveryConfigAuthority] = sixgr.truth.resolveRecoveryScenarioConfig( ...
    runFolder, inputCfg, ...
    "SourceFiles", string(p.Results.SourceFiles), ...
    "ConfigPath", string(p.Results.ConfigPath), ...
    "ConfigHash", string(p.Results.ConfigHash));
% Rebuild the internal runtime structure from the verified immutable
% resolved scenario. A caller-provided internal structure may have been
% built from a later YAML revision and is therefore not recovery authority.
cfg = sixgr.lls6g.buildInternalConfig(scfg, runFolder);
requestedRunTag = strtrim(string(p.Results.RunTag));
storedRunTag = strtrim(string(persistedRunTag));
if finalizationMode == "completed_run_refinalization" && ...
        strlength(storedRunTag) > 0 && strlength(requestedRunTag) > 0 && ...
        requestedRunTag ~= storedRunTag
    error("sixgr:truth:recover:RunTagIdentityMismatch", ...
        ['Completed-run re-finalization cannot replace immutable run ' ...
        'identity ''%s'' with ''%s''. Use PublicRunFolder to select a new ' ...
        'recovery output location while retaining the source RunTag.'], ...
        char(storedRunTag), char(requestedRunTag));
end
if finalizationMode == "completed_run_refinalization"
    recoveryRunTag = localFirstNonEmptyString( ...
        storedRunTag, requestedRunTag, ...
        string(sixgr.util.structGet(cfg, "run.runTag", "")), ...
        localResolveRunTagFromStoredFolder(string(runFolder)));
else
    recoveryRunTag = localFirstNonEmptyString( ...
        requestedRunTag, string(sixgr.util.structGet(cfg, "run.runTag", "")), ...
        storedRunTag, localResolveRunTagFromStoredFolder(string(runFolder)));
end
cfg.run.runTag = char(recoveryRunTag);
cfg.run.runnerProfile = char(string(scfg.get("scenario.runner_profile", "")));
cfg.run.scenarioID = char(string(scfg.ScenarioID));
cfg.meta.scenarioID = char(string(scfg.ScenarioID));
cfg.meta.configHash = char(localFirstNonEmptyString( ...
    string(scfg.ConfigHash), ...
    string(p.Results.ConfigHash), ...
    string(sixgr.util.structGet(storedMeta, "config_hash", ""))));
recoveryStore = localActivateRecoveryArtifactStore(runFolder, publicRunFolder, cfg, scfg, recoveryRunTag, double(p.Results.RunID));
cleanupStore = onCleanup(@() sixgr.db.deactivateArtifactStore()); %#ok<NASGU>

localRepairOptionalRAEvidenceSchemas(layout);
localEnsureResolvedSnapshots(layout, scfg);
sixgr.truth.exportLiveGeometryArtifacts(layout, scfg, cfg);
localRepairRuntimeOperatingMode(layout, cfg);
fixedLinkCampaignOnly = logical(scfg.get( ...
    "sweeps_and_matrix.fixed_link_calibration.only", ...
    scfg.get("canonical_control.run.fixed_link_campaign_only", false)));
cfg.run.fixedLinkCampaignOnly = fixedLinkCampaignOnly;
% Rebuild all runtime-derived evidence before any truth/status reduction.
% This invokes the same exporters as normal waveform completion and uses
% only persisted primary trial rows. If no DL/UL rows survived, it writes a
% provenance record and leaves every downstream gate fail-closed.
runtimeEvidenceRefinalization = ...
    sixgr.truth.refinalizePersistedLLSRuntimeEvidence(cfg, runFolder, ...
    "RunTag", recoveryRunTag, ...
    "RefreshBrowserContract", false);
% Normal completion audits geometry after runtime-derived measurements.
% Aborted execution must do the same: incomplete geometry stays FAIL, but
% its required audit must not disappear merely because PHY execution threw.
geometryScenarioAudit = sixgr.validation.runGeometryScenarioAuditIfNeeded( ...
    runFolder, scfg, cfg);

profile = lower(string(scfg.get("scenario.runner_profile", "")));
if finalizationMode == "completed_run_refinalization"
    persistedResultPath = fullfile(layout.ReportMATDir, "scenario_result.mat");
    if exist(persistedResultPath, "file") ~= 2
        error("sixgr:truth:recover:MissingCompletedRunResult", ...
            "Completed-run re-finalization requires %s.", persistedResultPath);
    end
    persisted = load(persistedResultPath, "Result");
    if ~isfield(persisted, "Result") || ~isstruct(persisted.Result)
        error("sixgr:truth:recover:InvalidCompletedRunResult", ...
            "The persisted scenario result does not contain a canonical Result structure.");
    end
    result = persisted.Result;
    result.RefinalizedFromPersistedCompletedRun = true;
    restoredTruthArtifacts = sixgr.truth.restoreCompletedRunTruthArtifacts( ...
        runFolder, result);
elseif finalizationMode == "persisted_trial_refinalization"
    if ~logical(runtimeEvidenceRefinalization.RawEvidencePresent)
        error("sixgr:truth:recover:MissingPersistedTrialEvidence", ...
            "Persisted-trial re-finalization requires at least one " + ...
            "primary DL or UL runtime trial row.");
    end
    result = struct( ...
        "Ok", false, ...
        "RefinalizedFromPersistedTrialRun", true, ...
        "ProfileReportedOk", false, ...
        "RunCompletion", "completed_with_failures", ...
        "DLTrialRows", double(runtimeEvidenceRefinalization.DLTrialRows), ...
        "ULTrialRows", double(runtimeEvidenceRefinalization.ULTrialRows));
    restoredTruthArtifacts = table();
else
    result = struct( ...
        "Ok", false, ...
        "RecoveredFromIncompleteRun", true, ...
        "ProfileReportedOk", false, ...
        "RunCompletion", string(p.Results.StatusText));
    restoredTruthArtifacts = table();
end
runtimeSummary = localBuildRuntimeSummary(profile, publicRunFolder, cfg);
environmentSummary = localBuildEnvironmentSummary(cfg);
scenarioStatus = localBuildScenarioStatus(string(p.Results.StatusText), ...
    string(p.Results.ErrorIdentifier), string(p.Results.ErrorMessage), finalizationMode);

summaryT = localBuildScenarioSummaryTable(scfg, cfg, profile, result, scenarioStatus, runFolder);
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "scenario_summary.csv"), summaryT);
sixgr.util.jsonWrite(fullfile(layout.MetaDir, "runtime_summary.json"), runtimeSummary);
sixgr.util.jsonWrite(fullfile(layout.MetaDir, "environment.json"), environmentSummary);

manifest = localBuildManifest(scfg, publicRunFolder, profile, runtimeSummary, environmentSummary, scenarioStatus);
localWriteScenarioManifest(layout, manifest);

configOwnership = sixgr.truth.exportLLSConfigOwnershipArtifacts(runFolder, scfg, cfg);
scenarioStatus = localApplyTruthVerdict(scenarioStatus, ...
    sixgr.truth.evaluateLLSRuntimeTruthContract(runFolder, scfg, cfg, "Result", result), ...
    runFolder, cfg, finalizationMode);
result.Ok = logical(scenarioStatus.ResultOk);
summaryT = localBuildScenarioSummaryTable(scfg, cfg, profile, result, scenarioStatus, runFolder);
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "scenario_summary.csv"), summaryT);
manifest = localBuildManifest(scfg, publicRunFolder, profile, runtimeSummary, environmentSummary, scenarioStatus);
localWriteScenarioManifest(layout, manifest);

reportBundle = sixgr.truth.exportLLSReportingBundle(runFolder, scfg, cfg, result, manifest, runtimeSummary, scenarioStatus);
reportBundle.GeometryScenarioAudit = geometryScenarioAudit;
truthArtifactScan = sixgr.truth.scanTruthArtifacts(runFolder, struct());
artifactEvidenceCoverage = table();
artifactContractResult = struct( ...
    "Ok", false, "Executed", false, "Status", "NOT_EVALUATED", ...
    "EvidenceOrigin", "not_available");
runtimeArtifactIdentity = struct();
if finalizationMode == "completed_run_refinalization"
    % Rebuild the runtime contract components from the canonical persisted
    % Result.  Never carry a copied component CSV through recovery: doing so
    % would preserve stale qualification labels even when the current
    % exporter or YAML policy has changed.  The registration adapter checks
    % all raw lifecycle identities before admitting any table.
    artifactEvidence = sixgr.artifact.EvidenceRegistry();
    [artifactEvidenceCoverage, runtimeArtifactIdentity] = ...
        sixgr.artifact.registerPersistedCompletedRunEvidence( ...
        artifactEvidence, result, scfg, cfg, recoveryRunTag);
    cfg.run.executionID = char(runtimeArtifactIdentity.ExecutionID);
    cfg.meta.executionID = char(runtimeArtifactIdentity.ExecutionID);
    reportBundle.ArtifactEvidenceCoverage = artifactEvidenceCoverage;
    artifactContractResult = sixgr.artifact.finalizeRunFailClosed( ...
        runFolder, artifactEvidence, scfg, runtimeArtifactIdentity);
    artifactContractResult.EvidenceOrigin = ...
        "persisted_completed_run_truth";
    reportBundle.ArtifactContract = artifactContractResult;
end
% The ISAC source tables have already passed through the global provenance
% annotator in the original run.  Rebind plot lineage to those stable bytes
% before output coverage performs its strict visual-integrity audit.
sixgr.lls.refreshISACPlotLineage(runFolder, cfg);
outputCoverage = sixgr.truth.exportLLSOutputCoverageArtifacts(runFolder, scfg, cfg);
componentViewsRequiredComponents = string(scfg.get( ...
    "output.component_artifact_views.required_components", strings(0, 1)));
configOwnership = sixgr.truth.exportLLSConfigOwnershipArtifacts(runFolder, scfg, cfg);
reportBundle.ConfigOwnershipArtifacts = configOwnership;
scenarioStatus = localApplyTruthVerdict(scenarioStatus, ...
    sixgr.truth.evaluateLLSRuntimeTruthContract(runFolder, scfg, cfg, "Result", result), ...
    runFolder, cfg, finalizationMode);
result.Ok = logical(scenarioStatus.ResultOk);
summaryT = localBuildScenarioSummaryTable(scfg, cfg, profile, result, scenarioStatus, runFolder);
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "scenario_summary.csv"), summaryT);
manifest = localBuildManifest(scfg, publicRunFolder, profile, runtimeSummary, environmentSummary, scenarioStatus);
localWriteScenarioManifest(layout, manifest);
sanitizedCSVs = sixgr.truth.sanitizeLLSArtifactCSVs(runFolder);
% Browser publication is part of terminal evidence finalization, not a UI
% convenience. Run it only after CSV sanitization so every raster and
% lineage hash binds to the exact stable source bytes.
contractMaterialization = ...
    sixgr.artifact.materializeBrowserContractArtifacts(runFolder);
contractMaterialization.RunID = recoveryRunTag;
contractMaterialization.GeneratedAtUTC = string(sixgr.util.utcNowISO8601());
browserReceipt = sixgr.artifact.writeBrowserPublicationReceipt( ...
    runFolder, contractMaterialization);
reportBundle.BrowserContractMaterialization = contractMaterialization;
reportBundle.BrowserPublicationReceipt = browserReceipt;
componentViews = sixgr.truth.publishComponentArtifactViews(runFolder, ...
    "Enabled", logical(scfg.get( ...
        "output.component_artifact_views.enabled", false)), ...
    "Required", logical(scfg.get( ...
        "output.component_artifact_views.required", false)), ...
    "RequiredComponents", componentViewsRequiredComponents(:));
% Keep the final verdict tied to the exact post-sanitization source bytes.
% This is idempotent and never regenerates or substitutes a plot.
sixgr.lls.refreshISACPlotLineage(runFolder, cfg);
finalVisualAudit = sixgr.visual.finalizeRunVisualAudit(runFolder);
outputCoverage.VisualArtifactIntegrity = finalVisualAudit.Integrity;
outputCoverage.VisualArtifactAudit = finalVisualAudit.Audit;
reportBundle.OutputCoverageArtifacts = outputCoverage;
% The recursive CSV/image audit written during output-coverage export is a
% pre-materialization snapshot.  Refresh it against the exact final raster
% tree before Phase 7 consumes all_image_artifact_audit.csv; otherwise a
% successful browser/visual publication can be reported alongside stale
% "required image missing" rows.  This audit verifies persisted bytes and
% lineage only and never creates substitute evidence.
postMaterializationArtifactAudit = sixgr.validation.auditRunArtifacts( ...
    runFolder, "Strict", false, "WriteOutputs", true);
reportBundle.PostMaterializationArtifactAudit = ...
    postMaterializationArtifactAudit;
postMaterializationPhase7 = ...
    sixgr.analytics.buildPhase7ReadinessArtifacts(scfg, runFolder);
postMaterializationPublication = ...
    sixgr.analytics.evaluatePublicationReadinessGates(cfg, runFolder);
reportBundle.PostMaterializationPhase7 = postMaterializationPhase7;
reportBundle.PostMaterializationPublicationReadiness = ...
    postMaterializationPublication;
% Status reduction changes source CSV bytes that themselves drive browser
% charts.  Close that dependency as a bounded fixed point: publish exact
% current sources, audit them, reduce status, and repeat until both status
% and every recorded source hash are stable.  This is deliberately
% fail-closed; a non-convergent publication tree is not a completed run.
terminalGeneratedAt = string(sixgr.util.utcNowISO8601());
terminalPreviousSignature = "";
terminalConverged = false;
terminalClosure = struct();
browserPublicationRequired = logical(sixgr.util.structGet( ...
    scenarioStatus, "BrowserPublicationRequired", false));
visualClosureRequired = logical(sixgr.util.structGet( ...
    scenarioStatus, "VisualArtifactGateRequired", false));
for terminalPass = 1:3
    componentViews = sixgr.truth.publishComponentArtifactViews(runFolder, ...
        "Enabled", logical(scfg.get( ...
            "output.component_artifact_views.enabled", false)), ...
        "Required", logical(scfg.get( ...
            "output.component_artifact_views.required", false)), ...
        "RequiredComponents", componentViewsRequiredComponents(:));
    terminalClosure = sixgr.artifact.sealBrowserArtifactClosure( ...
        string(runFolder), "RunID", recoveryRunTag, ...
        "GeneratedAtUTC", terminalGeneratedAt, ...
        "MaxPasses", 1 + 2*double(browserPublicationRequired || ...
            visualClosureRequired), ...
        "Required", browserPublicationRequired || visualClosureRequired);
    contractMaterialization = terminalClosure.Materialization;
    browserReceipt = terminalClosure.Receipt;
    finalVisualAudit = terminalClosure.VisualAudit;
    outputCoverage.VisualArtifactIntegrity = finalVisualAudit.Integrity;
    outputCoverage.VisualArtifactAudit = finalVisualAudit.Audit;
    reportBundle.BrowserContractMaterialization = contractMaterialization;
    reportBundle.BrowserPublicationReceipt = browserReceipt;
    reportBundle.OutputCoverageArtifacts = outputCoverage;

    postMaterializationArtifactAudit = sixgr.validation.auditRunArtifacts( ...
        runFolder, "Strict", false, "WriteOutputs", true);
    postMaterializationPhase7 = ...
        sixgr.analytics.buildPhase7ReadinessArtifacts(scfg, runFolder);
    postMaterializationPublication = ...
        sixgr.analytics.evaluatePublicationReadinessGates(cfg, runFolder);
    reportBundle.PostMaterializationArtifactAudit = ...
        postMaterializationArtifactAudit;
    reportBundle.PostMaterializationPhase7 = postMaterializationPhase7;
    reportBundle.PostMaterializationPublicationReadiness = ...
        postMaterializationPublication;

    scenarioStatus = localApplyTruthVerdict(scenarioStatus, ...
        sixgr.truth.evaluateLLSRuntimeTruthContract( ...
            runFolder, scfg, cfg, "Result", result), ...
        runFolder, cfg, finalizationMode);
    % Production qualification reads the just-persisted canonical root
    % status.  Reduce it inside the same terminal fixed point so its gate
    % table can never describe an earlier failed-recovery state while the
    % final root status describes a completed functional run.
    scenarioStatus = sixgr.truth.applyProductionQualificationGate( ...
        scenarioStatus, runFolder);
    sixgr.artifact.updateRootStatusArtifacts(runFolder, scenarioStatus);
    result.Ok = logical(scenarioStatus.ResultOk);
    summaryT = localBuildScenarioSummaryTable( ...
        scfg, cfg, profile, result, scenarioStatus, runFolder);
    sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, ...
        "scenario_summary.csv"), summaryT);
    manifest = localBuildManifest(scfg, publicRunFolder, profile, ...
        runtimeSummary, environmentSummary, scenarioStatus);
    localWriteScenarioManifest(layout, manifest);

    terminalSignature = localTerminalStatusSignature(scenarioStatus);
    lineageClosure = sixgr.artifact.verifyContractPlotLineageSources( ...
        string(runFolder));
    if terminalPass >= 2 && terminalSignature == terminalPreviousSignature && ...
            logical(lineageClosure.Ok) && ...
            logical(sixgr.util.structGet(scenarioStatus, ...
                "VisualArtifactGateOk", false))
        terminalConverged = true;
        break;
    end
    terminalPreviousSignature = terminalSignature;
end
if ~terminalConverged
    error("sixgr:truth:recover:TerminalArtifactFixedPointFailed", ...
        "Terminal status and exact plot-source hashes did not converge " + ...
        "within three publication passes.");
end
if logical(sixgr.util.structGet(recoveryStore, "Active", false))
    sixgr.db.markRunStatus(char(string(scenarioStatus.RunCompletion)), struct( ...
        "status_authority", char(string(scenarioStatus.StatusAuthority)), ...
        "reason", "recover_lls_run_artifacts_persisted_existing_run", ...
        "runtime_truth_contract_ok", logical(sixgr.util.structGet(scenarioStatus, "RuntimeTruthContractOk", false)), ...
        "required_failure_count", double(sixgr.util.structGet(scenarioStatus, "RequiredFailureCount", 0)), ...
        "roundtrip_mismatch_count", double(sixgr.util.structGet(scenarioStatus, "RoundtripMismatchCount", 0))));
end

out = struct();
out.Ok = true;
out.ScenarioID = string(scfg.ScenarioID);
out.RunFolder = string(runFolder);
out.RunnerProfile = profile;
out.RuntimeSummary = runtimeSummary;
out.EnvironmentSummary = environmentSummary;
out.Manifest = manifest;
out.PersistedRunTagEvidence = persistedRunTagEvidence;
out.ScenarioStatus = scenarioStatus;
out.ConfigOwnershipArtifacts = configOwnership;
out.ReportBundle = reportBundle;
out.TruthArtifactScan = truthArtifactScan;
out.ArtifactEvidenceCoverage = artifactEvidenceCoverage;
out.ArtifactContract = artifactContractResult;
out.RuntimeArtifactIdentity = runtimeArtifactIdentity;
out.OutputCoverageArtifacts = outputCoverage;
out.ComponentArtifactViews = componentViews;
out.SanitizedCSVs = sanitizedCSVs;
out.RestoredTruthArtifacts = restoredTruthArtifacts;
out.RecoveryArtifactStore = recoveryStore;
out.RuntimeEvidenceRefinalization = runtimeEvidenceRefinalization;
out.GeometryScenarioAudit = geometryScenarioAudit;
out.BrowserContractMaterialization = contractMaterialization;
out.BrowserPublicationReceipt = browserReceipt;
out.FinalVisualAudit = finalVisualAudit;
out.TerminalArtifactClosure = terminalClosure;
out.PostMaterializationArtifactAudit = postMaterializationArtifactAudit;
out.PostMaterializationPhase7 = postMaterializationPhase7;
out.PostMaterializationPublicationReadiness = ...
    postMaterializationPublication;
out.FinalizationMode = finalizationMode;
out.RecoveryConfigAuthority = recoveryConfigAuthority;
end

function signature = localTerminalStatusSignature(status)
payload = struct( ...
    "RunCompletion", string(sixgr.util.structGet(status, "RunCompletion", "")), ...
    "ResultOk", logical(sixgr.util.structGet(status, "ResultOk", false)), ...
    "RuntimeTruthContractOk", logical(sixgr.util.structGet(status, "RuntimeTruthContractOk", false)), ...
    "RequiredFailureCount", double(sixgr.util.structGet(status, "RequiredFailureCount", 0)), ...
    "VisualArtifactGateOk", logical(sixgr.util.structGet(status, "VisualArtifactGateOk", false)), ...
    "VisualArtifactFailureCount", double(sixgr.util.structGet(status, "VisualArtifactFailureCount", 0)), ...
    "VisualArtifactFailureReason", string(sixgr.util.structGet(status, "VisualArtifactFailureReason", "")), ...
    "RuntimeTruthContractFailures", string(sixgr.util.structGet(status, "RuntimeTruthContractFailures", strings(0, 1))));
encoded = unicode2native(jsonencode(payload), "UTF-8");
signature = lower(string(sixgr.util.sha256Hex(uint8(encoded))));
end

function localEnsureDirs(layout)
sixgr.util.ensureFolder(layout.ReportDir);
sixgr.util.ensureFolder(layout.ReportCSVDir);
sixgr.util.ensureFolder(layout.ReportImageDir);
sixgr.util.ensureFolder(layout.MetaDir);
end

function localEnsureResolvedSnapshots(layout, scfg)
resolvedStruct = scfg.toStruct();
jsonPath = fullfile(layout.MetaDir, "scenario_config_resolved.json");
if exist(jsonPath, "file") ~= 2
    sixgr.util.jsonWrite(jsonPath, resolvedStruct);
end

yamlPath = fullfile(layout.MetaDir, "scenario_config_resolved.yaml");
if exist(yamlPath, "file") ~= 2
    try
        sixgr.lls6g.config.writeYAML(yamlPath, resolvedStruct);
    catch
    end
end
srcFiles = localPortablePath(string(scfg.SourceFiles(:)));
sourcePath = fullfile(layout.MetaDir, "scenario_source_chain.csv");
if exist(sourcePath, "file") ~= 2
    srcT = table(srcFiles, 'VariableNames', {'SourceConfigFile'});
    sixgr.util.csvWriteTable(sourcePath, srcT);
end
identityPath = fullfile(layout.MetaDir, "scenario_config_identity.json");
if exist(jsonPath, "file") == 2 && exist(identityPath, "file") ~= 2
    fid = fopen(jsonPath, "r");
    if fid < 0
        error("sixgr:truth:recover:ResolvedConfigSnapshotUnreadable", ...
            "Cannot read resolved configuration snapshot %s.", jsonPath);
    end
    cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
    digest = string(sixgr.util.sha256Hex(fread(fid, Inf, "*uint8")));
    clear cleanup;
    identity = struct( ...
        "SchemaVersion", "sixgr_resolved_config_identity/v1", ...
        "ScenarioID", string(scfg.ScenarioID), ...
        "ConfigHash", string(scfg.ConfigHash), ...
        "ResolvedJSONSHA256", digest, ...
        "ResolvedYAMLSHA256", "", ...
        "GeneratedUTC", string(sixgr.util.utcNowISO8601()));
    sixgr.util.jsonWrite(identityPath, identity);
end
end

function localRepairOptionalRAEvidenceSchemas(layout)
% Repair schema-only legacy files without inventing an RA observation.
names = ["ra_negative_trials", "ra_collision_trials"];
for index = 1:numel(names)
    pathValue = fullfile(layout.ControlCSVDir, names(index) + ".csv");
    needsSchema = exist(pathValue, "file") ~= 2;
    if ~needsSchema
        info = dir(pathValue);
        needsSchema = isempty(info) || double(info(1).bytes) == 0;
        if ~needsSchema
            try
                existing = sixgr.util.csvReadTable(pathValue);
                needsSchema = width(existing) == 0;
            catch
                needsSchema = true;
            end
        end
    end
    if needsSchema
        schema = sixgr.phy.ra.emptyOptionalEvidenceTable(names(index));
        sixgr.util.csvWriteTable(pathValue, schema, "PreserveSchema", true);
    end
end
end

function storeInfo = localActivateRecoveryArtifactStore(runFolder, publicRunFolder, cfg, scfg, runTag, runID)
storeInfo = struct("Active", false);
backend = lower(string(sixgr.util.structGet(cfg, "outputs.storageBackend", "filesystem")));
if backend ~= "mysql_web"
    return;
end
storeInfo = sixgr.db.activateArtifactStore(runFolder, cfg, struct( ...
    "ScenarioID", scfg.ScenarioID, ...
    "RunTag", runTag, ...
    "Bucket", scfg.get("output.bucket"), ...
    "Profile", "recovery_artifact_refresh", ...
    "LogicalRunFolder", publicRunFolder, ...
    "ScenarioConfigStruct", scfg.toStruct(), ...
    "ScenarioSourceFiles", string(scfg.SourceFiles(:)), ...
    "ExistingRunID", runID));
end

function runtime = localBuildRuntimeSummary(profile, runFolder, cfg)
runtime = struct();
runtime.StartedUTC = "";
runtime.CompletedUTC = char(localUTCStamp());
runtime.ElapsedSeconds = NaN;
runtime.Profile = char(string(profile));
runtime.RunFolder = char(string(runFolder));
runtime.RunTag = char(string(sixgr.util.structGet(cfg, "run.runTag", "")));
runtime.UseMex = logical(sixgr.util.structGet(cfg, "acceleration.useMex", false));
runtime.UseMexAutoEnabled = logical(sixgr.util.structGet(cfg, "acceleration.useMexAutoEnabled", false));
runtime.UseParallel = logical(sixgr.util.structGet(cfg, "run.useParallel", false));
runtime.RequestedWorkers = double(sixgr.util.structGet(cfg, "run.numWorkers", 0));
runtime.EffectiveWorkers = double(sixgr.util.structGet(cfg, "run.numWorkers", 0));
runtime.ParallelDisabledReason = char(string(sixgr.util.structGet(cfg, "run.parallelDisabledReason", "")));
runtime.MaxNumCompThreads = double(maxNumCompThreads);
runtime.WarningCount = 0;
end

function env = localBuildEnvironmentSummary(cfg)
env = struct();
env.Platform = char(string(computer));
env.MATLABRelease = char(string(version("-release")));
env.MATLABVersion = char(string(version));
env.UseMex = logical(sixgr.util.structGet(cfg, "acceleration.useMex", false));
env.UseParallel = logical(sixgr.util.structGet(cfg, "run.useParallel", false));
end

function status = localBuildScenarioStatus(statusText, errorIdentifier, errorMessage, finalizationMode)
status = struct();
status.RunCompletion = string(statusText);
status.ResultOk = false;
status.PartialOk = true;
status.ArtifactsGenerated = true;
status.RequiredCaseCount = 1;
status.RequiredFailureCount = 1;
status.OptionalPrunedCount = 0;
status.RequiredFailedCases = "runtime_incomplete_recovered_from_persisted_raw_evidence";
status.OptionalPrunedCases = strings(0, 1);
status.StatusAuthority = "recovered_failed_run_artifacts_v1";
status.StatusNotes = "Recovered summary/report/coverage artifacts from persisted raw evidence after a failed or aborted run.";
status.RuntimeTruthContractOk = false;
status.TruthContractOk = false;
status.StandardsConformanceOk = false;
status.ScenarioObjectiveOk = false;
status.ConfiguredEffectiveOk = false;
status.ConfiguredEffectivePolicyOk = false;
status.MandatorySubsystemsOk = false;
status.ActiveIssueGateOk = false;
status.KpiConsistencyOk = false;
status.VisualArtifactGateOk = false;
status.VisualArtifactGateStatus = "NOT_EVALUATED";
status.VisualArtifactFailureCount = 0;
status.VisualArtifactFailureReason = "not_evaluated";
status.VisualArtifactIntegrityOk = false;
status.VisualArtifactIntegrityFailureCount = 0;
status.VisualArtifactIntegrityFailures = "not_evaluated";
status.DuplicateArtifactGateOk = false;
status.DuplicateArtifactGateStatus = "NOT_EVALUATED";
status.StrictAnchorEligible = false;
status.StrictAnchorPass = false;
status.ResultStatusReason = "recovered_run_not_yet_truth_gated";
status.ActiveMandatoryIssueCount = 0;
status.ActiveCriticalIssueCount = 0;
status.ActiveHighIssueCount = 0;
status.ActiveMediumIssueCount = 0;
status.RoundtripMismatchCount = 0;
status.RequiredRuntimeEvidenceMissingCount = 0;
status.StrictTruthFailureCount = 0;
status.StrictProxyGuardFailureCount = 0;
status.CanonicalArtifactGapCount = 0;
status.RuntimeTruthContractFailures = strings(0, 1);
status.WarningCount = 0;
status.FailingCaseCount = 1;
status.CaseOk = false;
status.ErrorSource = "recovered_failed_run_artifacts";
status.ErrorIdentifier = string(errorIdentifier);
status.ErrorMessage = string(errorMessage);
status.AuthoritativeStatusSource = "recovered_failed_run_artifacts";
if ismember(lower(strtrim(string(finalizationMode))), ...
        ["completed_run_refinalization", "persisted_trial_refinalization"])
    status.RunCompletion = "completed_with_failures";
    status.RequiredFailedCases = ...
        "persisted_trial_refinalization_pending_truth_contract";
    status.StatusAuthority = ...
        "persisted_trial_refinalization_pending_truth_contract";
    status.StatusNotes = [ ...
        "Persisted waveform evidence is being re-finalized; no success " ...
        "is claimed before every canonical root gate passes."];
    status.ErrorSource = "";
    status.ErrorIdentifier = "";
    status.ErrorMessage = "";
    status.AuthoritativeStatusSource = ...
        "persisted_trial_refinalization_pending_truth_contract";
end
end

function status = localApplyTruthVerdict(status, verdict, runFolder, cfg, finalizationMode)
status.RuntimeTruthContractOk = logical(sixgr.util.structGet(verdict, "RuntimeTruthContractOk", false));
status.TruthContractOk = logical(status.RuntimeTruthContractOk);
rootStatus = sixgr.util.structGet(verdict, "ResultStatus", struct());
status.ArtifactsWritten = logical(sixgr.util.structGet(rootStatus, ...
    "ArtifactsWritten", sixgr.util.structGet(status, "ArtifactsGenerated", false)));
status.ArtifactCompletenessOk = logical(sixgr.util.structGet(rootStatus, ...
    "ArtifactCompletenessOk", false));
status.StandardsConformanceOk = logical(sixgr.util.structGet(rootStatus, "StandardsConformanceOk", status.RuntimeTruthContractOk));
status.ScenarioObjectiveOk = logical(sixgr.util.structGet(rootStatus, "ScenarioObjectiveOk", status.RuntimeTruthContractOk));
status.ConfiguredEffectiveOk = logical(sixgr.util.structGet(rootStatus, "ConfiguredEffectiveOk", false));
status.ConfiguredEffectivePolicyOk = logical(sixgr.util.structGet(rootStatus, ...
    "ConfiguredEffectivePolicyOk", false));
status = sixgr.truth.applyPersistedMIMOConfiguredEffectiveStatus( ...
    status, runFolder, cfg);
status.MandatorySubsystemsOk = logical(sixgr.util.structGet(rootStatus, "MandatorySubsystemsOk", status.RuntimeTruthContractOk));
status.ActiveIssueGateOk = logical(sixgr.util.structGet(rootStatus, "ActiveIssueGateOk", status.RuntimeTruthContractOk));
status.KpiConsistencyOk = logical(sixgr.util.structGet(rootStatus, "KpiConsistencyOk", false));
status.VisualArtifactGateOk = logical(sixgr.util.structGet(rootStatus, ...
    "VisualArtifactGateOk", false));
status.VisualArtifactGateStatus = string(sixgr.util.structGet(rootStatus, ...
    "VisualArtifactGateStatus", "NOT_EVALUATED"));
status.VisualArtifactFailureCount = double(sixgr.util.structGet(rootStatus, ...
    "VisualArtifactFailureCount", 0));
status.VisualArtifactFailureReason = string(sixgr.util.structGet(rootStatus, ...
    "VisualArtifactFailureReason", ""));
status.VisualArtifactIntegrityOk = logical(sixgr.util.structGet(rootStatus, ...
    "VisualArtifactIntegrityOk", status.VisualArtifactGateOk));
status.VisualArtifactIntegrityFailureCount = double(sixgr.util.structGet(rootStatus, ...
    "VisualArtifactIntegrityFailureCount", status.VisualArtifactFailureCount));
status.VisualArtifactIntegrityFailures = string(sixgr.util.structGet(rootStatus, ...
    "VisualArtifactIntegrityFailures", status.VisualArtifactFailureReason));
status.DuplicateArtifactGateOk = logical(sixgr.util.structGet(rootStatus, ...
    "DuplicateArtifactGateOk", false));
status.DuplicateArtifactGateStatus = string(sixgr.util.structGet(rootStatus, ...
    "DuplicateArtifactGateStatus", "NOT_EVALUATED"));
status.StrictAnchorEligible = logical(sixgr.util.structGet(rootStatus, "StrictAnchorEligible", false));
status.StrictAnchorPass = logical(sixgr.util.structGet(rootStatus, "StrictAnchorPass", status.RuntimeTruthContractOk));
status.ResultStatusReason = string(sixgr.util.structGet(rootStatus, "ResultStatusReason", ""));
status.ActiveMandatoryIssueCount = double(sixgr.util.structGet(rootStatus, "ActiveMandatoryIssueCount", 0));
status.ActiveCriticalIssueCount = double(sixgr.util.structGet(rootStatus, "ActiveCriticalIssueCount", 0));
status.ActiveHighIssueCount = double(sixgr.util.structGet(rootStatus, "ActiveHighIssueCount", 0));
status.ActiveMediumIssueCount = double(sixgr.util.structGet(rootStatus, "ActiveMediumIssueCount", 0));
status.RoundtripMismatchCount = double(sixgr.util.structGet(verdict, "RoundtripMismatchCount", 0));
status.RequiredRuntimeEvidenceMissingCount = double(sixgr.util.structGet(verdict, "RequiredRuntimeEvidenceMissingCount", 0));
status.StrictTruthFailureCount = double(sixgr.util.structGet(verdict, "StrictTruthFailureCount", 0));
status.StrictProxyGuardFailureCount = double(sixgr.util.structGet(verdict, "StrictProxyGuardFailureCount", 0));
status.CanonicalArtifactGapCount = double(sixgr.util.structGet(verdict, "CanonicalArtifactGapCount", 0));
status.RuntimeTruthContractFailures = string(sixgr.util.structGet(verdict, "Failures", strings(0, 1)));
if logical(status.RuntimeTruthContractOk)
    status.StatusNotes = localJoinStatusNotes(status.StatusNotes, "Recovered artifacts passed the runtime truth contract.");
else
    status.StatusNotes = localJoinStatusNotes(status.StatusNotes, "Recovered artifacts still reflect a failed/incomplete run and preserve the truth-contract failures explicitly.");
end
status = sixgr.truth.applyCompletedRefinalizationVerdict( ...
    status, verdict, finalizationMode);
end

function manifest = localBuildManifest(scfg, runFolder, profile, runtimeSummary, environmentSummary, scenarioStatus)
manifest = struct();
manifest.GeneratedUTC = char(localUTCStamp());
manifest.ScenarioID = char(string(scfg.ScenarioID));
manifest.ConfigHash = char(string(scfg.ConfigHash));
manifest.ConfigPath = char(string(scfg.ConfigPath));
manifest.RunFolder = char(string(runFolder));
manifest.RunTag = char(string(sixgr.util.structGet(runtimeSummary, "RunTag", "")));
manifest.SourceFiles = cellstr(localPortablePath(scfg.SourceFiles));
manifest.SourceFileCount = numel(scfg.SourceFiles);
manifest.RunnerProfile = char(string(profile));
manifest.RandomSeed = double(scfg.get("simulation.random_seed", NaN));
manifest.DeterministicMode = logical(scfg.get("simulation.deterministic_mode", false));
manifest.StrictValidation = logical(scfg.get("logging.strict_validation", false));
manifest.ExecutionStartedUTC = char(string(sixgr.util.structGet(runtimeSummary, "StartedUTC", "")));
manifest.ExecutionCompletedUTC = char(string(sixgr.util.structGet(runtimeSummary, "CompletedUTC", "")));
manifest.ElapsedSeconds = double(sixgr.util.structGet(runtimeSummary, "ElapsedSeconds", NaN));
manifest.WarningCount = double(scenarioStatus.WarningCount);
manifest.EnvironmentSummaryPath = "meta/environment.json";
manifest.RuntimeSummaryPath = "meta/runtime_summary.json";
manifest.HostPlatform = char(string(sixgr.util.structGet(environmentSummary, "Platform", "")));
manifest.RunScope = "6G_PHY_LLS_SINGLE_SCENARIO";
manifest.RunCompletion = char(string(scenarioStatus.RunCompletion));
manifest.ResultOk = logical(scenarioStatus.ResultOk);
manifest.PartialOk = logical(scenarioStatus.PartialOk);
manifest.ArtifactsGenerated = logical(scenarioStatus.ArtifactsGenerated);
manifest.RequiredCaseCount = double(scenarioStatus.RequiredCaseCount);
manifest.RequiredFailureCount = double(scenarioStatus.RequiredFailureCount);
manifest.OptionalPrunedCount = double(scenarioStatus.OptionalPrunedCount);
manifest.RequiredFailedCases = cellstr(string(scenarioStatus.RequiredFailedCases(:)));
manifest.OptionalPrunedCases = cellstr(string(scenarioStatus.OptionalPrunedCases(:)));
manifest.StatusAuthority = char(string(scenarioStatus.StatusAuthority));
manifest.StatusNotes = char(string(scenarioStatus.StatusNotes));
manifest.ErrorSource = char(string(sixgr.util.structGet(scenarioStatus, "ErrorSource", "")));
manifest.ErrorIdentifier = char(string(sixgr.util.structGet(scenarioStatus, "ErrorIdentifier", "")));
manifest.ErrorMessage = char(string(sixgr.util.structGet(scenarioStatus, "ErrorMessage", "")));
manifest.AuthoritativeStatusSource = char(string(sixgr.util.structGet(scenarioStatus, "AuthoritativeStatusSource", "")));
manifest.RuntimeTruthContractOk = logical(scenarioStatus.RuntimeTruthContractOk);
manifest.TruthContractOk = logical(sixgr.util.structGet(scenarioStatus, "TruthContractOk", scenarioStatus.RuntimeTruthContractOk));
manifest.StandardsConformanceOk = logical(sixgr.util.structGet(scenarioStatus, "StandardsConformanceOk", scenarioStatus.RuntimeTruthContractOk));
manifest.ScenarioObjectiveOk = logical(sixgr.util.structGet(scenarioStatus, "ScenarioObjectiveOk", scenarioStatus.ResultOk));
manifest.ConfiguredEffectiveOk = logical(sixgr.util.structGet(scenarioStatus, "ConfiguredEffectiveOk", false));
manifest.ConfiguredEffectivePolicyOk = logical(sixgr.util.structGet(scenarioStatus, ...
    "ConfiguredEffectivePolicyOk", false));
manifest.MandatorySubsystemsOk = logical(sixgr.util.structGet(scenarioStatus, "MandatorySubsystemsOk", false));
manifest.ActiveIssueGateOk = logical(sixgr.util.structGet(scenarioStatus, "ActiveIssueGateOk", false));
manifest.KpiConsistencyOk = logical(sixgr.util.structGet(scenarioStatus, "KpiConsistencyOk", false));
manifest.VisualArtifactGateOk = logical(sixgr.util.structGet(scenarioStatus, ...
    "VisualArtifactGateOk", false));
manifest.VisualArtifactGateStatus = char(string(sixgr.util.structGet(scenarioStatus, ...
    "VisualArtifactGateStatus", "NOT_EVALUATED")));
manifest.VisualArtifactFailureCount = double(sixgr.util.structGet(scenarioStatus, ...
    "VisualArtifactFailureCount", 0));
manifest.VisualArtifactFailureReason = char(string(sixgr.util.structGet(scenarioStatus, ...
    "VisualArtifactFailureReason", "")));
manifest.VisualArtifactIntegrityOk = logical(sixgr.util.structGet(scenarioStatus, ...
    "VisualArtifactIntegrityOk", manifest.VisualArtifactGateOk));
manifest.VisualArtifactIntegrityFailureCount = double(sixgr.util.structGet(scenarioStatus, ...
    "VisualArtifactIntegrityFailureCount", manifest.VisualArtifactFailureCount));
manifest.VisualArtifactIntegrityFailures = char(strjoin(string(sixgr.util.structGet( ...
    scenarioStatus, "VisualArtifactIntegrityFailures", "")), "; "));
manifest.DuplicateArtifactGateOk = logical(sixgr.util.structGet(scenarioStatus, ...
    "DuplicateArtifactGateOk", false));
manifest.DuplicateArtifactGateStatus = char(string(sixgr.util.structGet(scenarioStatus, ...
    "DuplicateArtifactGateStatus", "NOT_EVALUATED")));
manifest.StrictAnchorEligible = logical(sixgr.util.structGet(scenarioStatus, "StrictAnchorEligible", false));
manifest.StrictAnchorPass = logical(sixgr.util.structGet(scenarioStatus, "StrictAnchorPass", false));
manifest.ResultStatusReason = char(string(sixgr.util.structGet(scenarioStatus, "ResultStatusReason", "")));
manifest.ActiveMandatoryIssueCount = double(sixgr.util.structGet(scenarioStatus, "ActiveMandatoryIssueCount", 0));
manifest.ActiveCriticalIssueCount = double(sixgr.util.structGet(scenarioStatus, "ActiveCriticalIssueCount", 0));
manifest.ActiveHighIssueCount = double(sixgr.util.structGet(scenarioStatus, "ActiveHighIssueCount", 0));
manifest.ActiveMediumIssueCount = double(sixgr.util.structGet(scenarioStatus, "ActiveMediumIssueCount", 0));
manifest.RoundtripMismatchCount = double(scenarioStatus.RoundtripMismatchCount);
manifest.RequiredRuntimeEvidenceMissingCount = double(scenarioStatus.RequiredRuntimeEvidenceMissingCount);
manifest.StrictTruthFailureCount = double(scenarioStatus.StrictTruthFailureCount);
manifest.StrictProxyGuardFailureCount = double(scenarioStatus.StrictProxyGuardFailureCount);
manifest.CanonicalArtifactGapCount = double(scenarioStatus.CanonicalArtifactGapCount);
manifest.RuntimeTruthContractFailures = cellstr(string(scenarioStatus.RuntimeTruthContractFailures(:)));
manifest.CodeVersion = char(string(version("-release")));
manifest.CodeDetail = "recovered_failed_run_artifacts";
end

function T = localBuildScenarioSummaryTable(scfg, cfg, profile, result, scenarioStatus, runFolder)
layout = sixgr.report.resultLayout(runFolder);
dlTrials = localReadFirstAvailableTable( ...
    fullfile(layout.AirInterfaceCSVDir, "dl_pdsch_trials.csv"), ...
    fullfile(layout.AirInterfaceCSVDir, "dl_fixed_link_campaign_trials.csv"), ...
    fullfile(layout.ReportCSVDir, "dl_fixed_link_campaign_trials.csv"));
ulTrials = localReadFirstAvailableTable( ...
    fullfile(layout.AirInterfaceCSVDir, "ul_pusch_trials.csv"), ...
    fullfile(layout.AirInterfaceCSVDir, "ul_fixed_link_campaign_trials.csv"), ...
    fullfile(layout.ReportCSVDir, "ul_fixed_link_campaign_trials.csv"));
opSummary = sixgr.truth.summarizeEffectiveOperatingPoint(scfg, dlTrials, ulTrials, cfg);
opSummary.Radio.SCS_kHz = double(scfg.get("frame.scs_khz", NaN));
cp = string(scfg.get("frame.cp_type", ...
    sixgr.util.structGet(cfg, "phy.carrier.CyclicPrefix", "normal")));
numerology = sixgr.phy.frame.NumerologyCatalog.resolve( ...
    opSummary.Radio.SCS_kHz, cp, "generic_waveform_test", "");
opSummary.Radio.Numerology_mu = double(numerology.Mu);
opSummary.Radio.SlotDuration_ms = ...
    double(numerology.SlotDurationMilliseconds);
opSummary.Radio.SlotsPerFrame = double(numerology.SlotsPerFrame);
opSummary.Radio.SymbolsPerSlot = double(numerology.SymbolsPerSlot);
opSummary.Radio.NumerologySource = "frame.scs_khz_runtime_authority";
opSummary.Radio.TimingInterpretationSource = "nr_mu_from_scs";
numerologyMu = double(sixgr.util.structGet(opSummary, "Radio.Numerology_mu", NaN));
scsKHz = double(sixgr.util.structGet(opSummary, "Radio.SCS_kHz", NaN));
slotDuration_ms = double(sixgr.util.structGet(opSummary, "Radio.SlotDuration_ms", NaN));
slotsPerFrame = double(sixgr.util.structGet(opSummary, "Radio.SlotsPerFrame", NaN));
symbolsPerSlot = double(sixgr.util.structGet(opSummary, "Radio.SymbolsPerSlot", NaN));
okVal = logical(scenarioStatus.ResultOk);
T = table( ...
    string(scfg.ScenarioID), ...
    string(profile), ...
    localResolveRecoveredConfigHash(scfg, cfg, runFolder), ...
    double(scfg.get("simulation.random_seed", NaN)), ...
    logical(scfg.get("simulation.deterministic_mode", false)), ...
    logical(scfg.get("logging.strict_validation", false)), ...
    double(scfg.get("users.n_users", 1)), ...
    double(scfg.get("mimo.n_layers", NaN)), ...
    string(scfg.get("users.beam_selection_strategy", "")), ...
    "6G_PHY_LLS_SINGLE_SCENARIO", ...
    string(scenarioStatus.RunCompletion), ...
    logical(sixgr.util.structGet(scenarioStatus, "RunCompleted", ...
        any(string(scenarioStatus.RunCompletion) == ["completed","completed_with_failures"]))), ...
    okVal, ...
    okVal, ...
    logical(scenarioStatus.PartialOk), ...
    logical(scenarioStatus.ArtifactsGenerated), ...
    logical(sixgr.util.structGet(scenarioStatus, "ArtifactsWritten", ...
        scenarioStatus.ArtifactsGenerated)), ...
    double(scenarioStatus.RequiredCaseCount), ...
    double(scenarioStatus.RequiredFailureCount), ...
    double(scenarioStatus.OptionalPrunedCount), ...
    string(scenarioStatus.StatusAuthority), ...
    logical(scenarioStatus.RuntimeTruthContractOk), ...
    logical(sixgr.util.structGet(scenarioStatus, "TruthContractOk", scenarioStatus.RuntimeTruthContractOk)), ...
    logical(sixgr.util.structGet(scenarioStatus, "StandardsConformanceOk", scenarioStatus.RuntimeTruthContractOk)), ...
    logical(sixgr.util.structGet(scenarioStatus, "ScenarioObjectiveOk", scenarioStatus.ResultOk)), ...
    logical(sixgr.util.structGet(scenarioStatus, "ConfiguredEffectiveOk", false)), ...
    logical(sixgr.util.structGet(scenarioStatus, "ConfiguredEffectivePolicyOk", false)), ...
    logical(sixgr.util.structGet(scenarioStatus, "MandatorySubsystemsOk", false)), ...
    logical(sixgr.util.structGet(scenarioStatus, "ActiveIssueGateOk", false)), ...
    logical(sixgr.util.structGet(scenarioStatus, "KpiConsistencyOk", false)), ...
    logical(sixgr.util.structGet(scenarioStatus, "StrictAnchorEligible", false)), ...
    logical(sixgr.util.structGet(scenarioStatus, "StrictAnchorPass", false)), ...
    string(sixgr.util.structGet(scenarioStatus, "ResultStatusReason", "")), ...
    double(sixgr.util.structGet(scenarioStatus, "ActiveMandatoryIssueCount", 0)), ...
    double(sixgr.util.structGet(scenarioStatus, "ActiveCriticalIssueCount", 0)), ...
    double(sixgr.util.structGet(scenarioStatus, "ActiveHighIssueCount", 0)), ...
    double(sixgr.util.structGet(scenarioStatus, "ActiveMediumIssueCount", 0)), ...
    double(scenarioStatus.RoundtripMismatchCount), ...
    double(scenarioStatus.RequiredRuntimeEvidenceMissingCount), ...
    double(scenarioStatus.StrictTruthFailureCount), ...
    double(scenarioStatus.StrictProxyGuardFailureCount), ...
    double(scenarioStatus.CanonicalArtifactGapCount), ...
    logical(sixgr.util.structGet(scenarioStatus, "VisualArtifactIntegrityOk", ...
        sixgr.util.structGet(scenarioStatus, "VisualArtifactGateOk", false))), ...
    double(sixgr.util.structGet(scenarioStatus, "VisualArtifactIntegrityFailureCount", ...
        sixgr.util.structGet(scenarioStatus, "VisualArtifactFailureCount", 0))), ...
    string(strjoin(string(sixgr.util.structGet(scenarioStatus, ...
        "VisualArtifactIntegrityFailures", strings(0, 1))), "; ")), ...
    logical(sixgr.util.structGet(scenarioStatus, "VisualArtifactGateOk", false)), ...
    double(sixgr.util.structGet(scenarioStatus, "VisualArtifactFailureCount", 0)), ...
    string(strjoin(string(scenarioStatus.RuntimeTruthContractFailures(:)), "; ")), ...
    string(scfg.get("meta.description", "")), ...
    string(opSummary.RuntimeQualifiedDescription), ...
    "nominal", ...
    string(opSummary.Configured.MIMOText), ...
    string(opSummary.Configured.DL.OperatingPointText), ...
    string(opSummary.Configured.UL.OperatingPointText), ...
    double(opSummary.Radio.ActiveGridNumRBs), ...
    double(opSummary.Radio.ConfiguredGridNumRBs), ...
    string(opSummary.Radio.ActiveGridSource), ...
    numerologyMu, ...
    scsKHz, ...
    slotDuration_ms, ...
    slotsPerFrame, ...
    symbolsPerSlot, ...
    string(sixgr.util.structGet(opSummary, "Radio.NumerologySource", "")), ...
    string(sixgr.util.structGet(opSummary, "Radio.TimingInterpretationSource", "")), ...
    string(opSummary.Radio.ActiveDuplexMode), ...
    string(opSummary.Radio.ConfiguredTDDPattern), ...
    string(opSummary.Radio.ActiveTDDPattern), ...
    logical(opSummary.Radio.TDDPatternApplicable), ...
    double(opSummary.DL.SampleCount), ...
    string(opSummary.DL.DominantOperatingPointText), ...
    string(opSummary.DL.LayerHistogram), ...
    string(opSummary.DL.RankHistogram), ...
    string(opSummary.DL.ModulationHistogram), ...
    string(opSummary.DL.MCSHistogram), ...
    double(opSummary.DL.ConfiguredMatchRate), ...
    double(opSummary.UL.SampleCount), ...
    string(opSummary.UL.DominantOperatingPointText), ...
    string(opSummary.UL.LayerHistogram), ...
    string(opSummary.UL.RankHistogram), ...
    string(opSummary.UL.ModulationHistogram), ...
    string(opSummary.UL.MCSHistogram), ...
    double(opSummary.UL.ConfiguredMatchRate), ...
    double(scenarioStatus.FailingCaseCount), ...
    double(scenarioStatus.WarningCount), ...
    string(scenarioStatus.ErrorSource), ...
    string(scenarioStatus.ErrorIdentifier), ...
    string(scenarioStatus.ErrorMessage), ...
    string(scenarioStatus.AuthoritativeStatusSource), ...
    string(opSummary.RuntimeNarrative), ...
    'VariableNames', {'ScenarioID','RunnerProfile','ConfigHash','RandomSeed', ...
    'DeterministicMode','StrictValidation','NumUsers','ConfiguredLayers','BeamSelectionStrategy', ...
    'RunScope','RunCompletion','RunCompleted','Ok','ResultOk','PartialOk','ArtifactsGenerated','ArtifactsWritten', ...
    'RequiredCaseCount','RequiredFailureCount','OptionalPrunedCount','StatusAuthority', ...
    'RuntimeTruthContractOk','TruthContractOk','StandardsConformanceOk','ScenarioObjectiveOk', ...
    'ConfiguredEffectiveOk','ConfiguredEffectivePolicyOk','MandatorySubsystemsOk','ActiveIssueGateOk','KpiConsistencyOk','StrictAnchorEligible','StrictAnchorPass','ResultStatusReason', ...
    'ActiveMandatoryIssueCount','ActiveCriticalIssueCount','ActiveHighIssueCount','ActiveMediumIssueCount', ...
    'RoundtripMismatchCount','RequiredRuntimeEvidenceMissingCount', ...
    'StrictTruthFailureCount','StrictProxyGuardFailureCount','CanonicalArtifactGapCount', ...
    'VisualArtifactIntegrityOk','VisualArtifactIntegrityFailureCount','VisualArtifactIntegrityFailures', ...
    'VisualArtifactGateOk','VisualArtifactFailureCount','RuntimeTruthContractFailures','Description', ...
    'RuntimeQualifiedDescription', ...
    'ConfiguredParameterSemantics','ConfiguredMIMO','ConfiguredDLNominalOperatingPoint','ConfiguredULNominalOperatingPoint', ...
    'ActiveGridNumRBs','ConfiguredGridNumRBs','ActiveGridSource','Numerology_mu','SCS_kHz','SlotDuration_ms','SlotsPerFrame','SymbolsPerSlot','NumerologySource','TimingInterpretationSource','ActiveDuplexMode','ConfiguredTDDPattern','ActiveTDDPattern','TDDPatternApplicable', ...
    'EffectiveDLTrialCount','EffectiveDLDominantOperatingPoint','EffectiveDLLayerHistogram','EffectiveDLRankHistogram','EffectiveDLModulationHistogram','EffectiveDLMCSHistogram','EffectiveDLConfiguredMatchRate', ...
    'EffectiveULTrialCount','EffectiveULDominantOperatingPoint','EffectiveULLayerHistogram','EffectiveULRankHistogram','EffectiveULModulationHistogram','EffectiveULMCSHistogram','EffectiveULConfiguredMatchRate', ...
    'FailingCaseCount','WarningCount','ErrorSource','ErrorIdentifier','ErrorMessage','AuthoritativeStatusSource', ...
    'EffectiveRuntimeNote'});
end

function localRepairRuntimeOperatingMode(layout, cfg)
pathOut = fullfile(layout.ReportCSVDir, "runtime_operating_mode.csv");
if exist(pathOut, "file") ~= 2
    return;
end
T = localReadOptionalTable(pathOut);
if ~(istable(T) && ~isempty(T) && ismember("Direction", string(T.Properties.VariableNames)))
    return;
end
dlTrials = localReadOptionalTable(fullfile(layout.AirInterfaceCSVDir, "dl_pdsch_trials.csv"));
ulTrials = localReadOptionalTable(fullfile(layout.AirInterfaceCSVDir, "ul_pusch_trials.csv"));
if ~ismember("ActualMCSSelectionMode", string(T.Properties.VariableNames))
    T.ActualMCSSelectionMode = repmat("", height(T), 1);
end
if ~ismember("AppliedOperatingPointSource", string(T.Properties.VariableNames))
    T.AppliedOperatingPointSource = repmat("", height(T), 1);
end
if ~ismember("ActualMCSSelectionModeAuthority", string(T.Properties.VariableNames))
    T.ActualMCSSelectionModeAuthority = repmat("", height(T), 1);
end
if ~ismember("SchedulerGrantMCSSelectionMode", string(T.Properties.VariableNames))
    T.SchedulerGrantMCSSelectionMode = repmat("", height(T), 1);
end
textVars = ["Direction", "ActualMCSSelectionMode", "AppliedOperatingPointSource", ...
    "ActualMCSSelectionModeAuthority", "SchedulerGrantMCSSelectionMode"];
for j = 1:numel(textVars)
    varName = textVars(j);
    if ismember(varName, string(T.Properties.VariableNames))
        T.(varName) = string(T.(varName));
    end
end
for i = 1:height(T)
    direction = upper(strtrim(string(T.Direction(i))));
    evidenceT = table();
    if direction == "DL"
        evidenceT = dlTrials;
    elseif direction == "UL"
        evidenceT = ulTrials;
    end
    actualMode = localDominantStringValue(evidenceT, "ActualMCSSelectionMode", "");
    appliedSource = localDominantStringValue(evidenceT, "AppliedOperatingPointSource", "");
    schedulerMode = localDominantStringValue(evidenceT, "SchedulerGrantMCSSelectionMode", "");
    if strlength(strtrim(actualMode)) > 0
        T.ActualMCSSelectionMode(i) = actualMode;
        T.ActualMCSSelectionModeAuthority(i) = "raw_trial_runtime_evidence";
    end
    if strlength(strtrim(appliedSource)) > 0
        T.AppliedOperatingPointSource(i) = appliedSource;
        if strlength(strtrim(string(T.ActualMCSSelectionModeAuthority(i)))) == 0
            T.ActualMCSSelectionModeAuthority(i) = "raw_trial_runtime_evidence";
        end
    end
    if strlength(strtrim(schedulerMode)) > 0
        T.SchedulerGrantMCSSelectionMode(i) = schedulerMode;
    end
    if strlength(strtrim(string(T.ActualMCSSelectionMode(i)))) == 0
        T.ActualMCSSelectionMode(i) = localConfiguredMCSSelectionModeFallback(cfg, direction);
    end
    if strlength(strtrim(string(T.AppliedOperatingPointSource(i)))) == 0
        T.AppliedOperatingPointSource(i) = localConfiguredOperatingPointSourceFallback(cfg, direction);
    end
end
sixgr.util.csvWriteTable(pathOut, T);
end

function value = localConfiguredMCSSelectionModeFallback(cfg, direction)
value = "fixed_mcs";
direction = upper(strtrim(string(direction)));
if direction == "UL"
    if logical(sixgr.util.structGet(cfg, "phy.pusch.enableOLLA", false))
        value = "cqi_driven";
    end
else
    if logical(sixgr.util.structGet(cfg, "phy.pdsch.enableOLLA", false)) || ...
            logical(sixgr.util.structGet(cfg, "phy.linkAdaptation.enable", false))
        value = "cqi_driven";
    end
end
end

function value = localConfiguredOperatingPointSourceFallback(cfg, direction)
selectionMode = localConfiguredMCSSelectionModeFallback(cfg, direction);
if selectionMode == "cqi_driven"
    value = "cqi_link_adaptation";
else
    value = "fixed_mcs";
end
end

function value = localDominantStringValue(T, varName, defaultValue)
value = string(defaultValue);
if ~(istable(T) && ~isempty(T) && ismember(varName, string(T.Properties.VariableNames)))
    return;
end
raw = string(T.(varName));
raw = raw(~ismissing(raw));
raw = strtrim(raw);
raw = raw(strlength(raw) > 0);
if isempty(raw)
    return;
end
[uniqueVals, ~, idx] = unique(raw, 'stable');
counts = accumarray(idx, 1);
[~, best] = max(counts);
value = uniqueVals(best);
end

function value = localResolveRecoveredConfigHash(scfg, cfg, runFolder)
computedHash = "";
try
    computedHash = localComputeScenarioConfigHash(scfg.toStruct());
catch
end
value = localFirstNonEmptyString( ...
    string(scfg.ConfigHash), ...
    string(sixgr.util.structGet(cfg, "meta.configHash", "")), ...
    string(sixgr.util.structGet(localReadStoredRunMetadata(runFolder), "config_hash", "")), ...
    string(computedHash));
end

function meta = localReadStoredRunMetadata(runFolder)
meta = struct("run_tag", "", "config_hash", "");
manifestPath = fullfile(runFolder, "meta", "scenario_manifest.json");
if exist(manifestPath, "file") == 2
    try
        manifest = jsondecode(fileread(manifestPath));
        if isstruct(manifest)
            meta.config_hash = string(sixgr.util.structGet(manifest, "ConfigHash", ""));
            meta.run_tag = localResolveRunTagFromStoredFolder(string(sixgr.util.structGet(manifest, "RunFolder", "")));
        end
    catch
    end
end
runtimeSummaryPath = fullfile(runFolder, "meta", "runtime_summary.json");
if exist(runtimeSummaryPath, "file") == 2
    try
        runtimeSummary = jsondecode(fileread(runtimeSummaryPath));
        if isstruct(runtimeSummary)
            meta.run_tag = localFirstNonEmptyString(meta.run_tag, ...
                localResolveRunTagFromStoredFolder(string(sixgr.util.structGet(runtimeSummary, "RunFolder", ""))));
        end
    catch
    end
end
end

function runTag = localResolveRunTagFromStoredFolder(pathValue)
runTag = "";
pathValue = string(pathValue);
if strlength(strtrim(pathValue)) == 0
    return;
end
[~, name, ext] = fileparts(char(pathValue));
runTag = string(name) + string(ext);
end

function value = localFirstNonEmptyString(varargin)
value = "";
for i = 1:nargin
    candidate = string(varargin{i});
    candidate = candidate(~ismissing(candidate));
    candidate = strtrim(candidate);
    candidate = candidate(strlength(candidate) > 0);
    if ~isempty(candidate)
        value = candidate(1);
        return;
    end
end
end

function cfgHash = localComputeScenarioConfigHash(cfg)
txt = jsonencode(cfg);
try
    md = java.security.MessageDigest.getInstance("SHA-256");
    md.update(uint8(txt));
    d = typecast(md.digest(), "uint8");
    cfgHash = lower(reshape(dec2hex(d, 2).', 1, []));
catch
    cfgHash = "fallback_" + string(sum(double(uint8(txt))));
end
cfgHash = char(string(cfgHash));
end

function T = localReadOptionalTable(pathStr)
T = table();
if exist(pathStr, "file") ~= 2
    return;
end
try
    T = sixgr.util.csvReadTable(pathStr);
catch
    T = table();
end
end

function T = localReadFirstAvailableTable(varargin)
T = table();
for i = 1:nargin
    T = localReadOptionalTable(varargin{i});
    if height(T) > 0 || exist(varargin{i}, "file") == 2
        return;
    end
end
end

function txt = localUTCStamp()
dt = datetime("now", "TimeZone", "UTC", "Format", "yyyy-MM-dd HH:mm:ss");
txt = char(replace(string(dt), " ", "T") + "Z");
end

function out = localPortablePath(in)
vals = string(in(:));
vals = replace(vals, "\", "/");
if isscalar(vals)
    out = char(vals);
else
    out = vals;
end
end

function notes = localJoinStatusNotes(existing, addition)
notes=sixgr.util.joinStatusNotes(existing,addition);
end

function mu = localDeriveNumerologyMu(scsKHz)
mu = NaN;
scsKHz = double(scsKHz);
if ~(isfinite(scsKHz) && scsKHz > 0)
    return;
end
numerology = sixgr.phy.frame.NumerologyCatalog.resolve( ...
    scsKHz, "normal", "generic_waveform_test", "");
mu = double(numerology.Mu);
end

function slotDuration_ms = localDeriveSlotDurationMs(mu)
slotDuration_ms = NaN;
mu = double(mu);
if isfinite(mu)
    numerology = sixgr.phy.frame.AbsoluteTime.resolveNumerology(mu);
    slotDuration_ms = 1e3 * double(numerology.TicksPerSlot) / ...
        double(sixgr.phy.frame.AbsoluteTime.TicksPerSecond);
end
end

function localWriteScenarioManifest(layout, manifest)
sixgr.util.jsonWrite(fullfile(layout.MetaDir, "scenario_manifest.json"), manifest);
sixgr.util.ensureDir(fullfile(layout.ReportDir, "json", ".keep"));
sixgr.util.jsonWrite(fullfile(layout.ReportDir, "json", "scenario_manifest.json"), manifest);
end

function slotsPerFrame = localDeriveSlotsPerFrame(mu)
slotsPerFrame = NaN;
mu = double(mu);
if isfinite(mu)
    numerology = sixgr.phy.frame.AbsoluteTime.resolveNumerology(mu);
    slotsPerFrame = double(numerology.SlotsPerFrame);
end
end
