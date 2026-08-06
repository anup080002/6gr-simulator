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
finalizationMode = lower(strtrim(string(p.Results.FinalizationMode)));
if ~ismember(finalizationMode, ["failed_recovery", "completed_run_refinalization"])
    error("sixgr:truth:recover:InvalidFinalizationMode", ...
        "FinalizationMode must be failed_recovery or completed_run_refinalization.");
end

inputCfg = p.Results.scenarioCfg;
scfg = localResolveScenarioConfig(inputCfg, ...
    string(p.Results.SourceFiles), string(p.Results.ConfigPath), string(p.Results.ConfigHash), layout);
cfg = localResolveInternalConfig(inputCfg, scfg, runFolder);
recoveryRunTag = localFirstNonEmptyString( ...
    string(p.Results.RunTag), ...
    string(sixgr.util.structGet(cfg, "run.runTag", "")), ...
    string(sixgr.util.structGet(storedMeta, "run_tag", "")), ...
    localResolveRunTagFromStoredFolder(string(runFolder)));
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

localWriteResolvedSnapshots(layout, scfg);
localExportLiveGeometryArtifacts(layout, scfg, cfg);
localRepairRuntimeOperatingMode(layout, cfg);

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
truthArtifactScan = sixgr.truth.scanTruthArtifacts(runFolder, struct());
outputCoverage = sixgr.truth.exportLLSOutputCoverageArtifacts(runFolder, scfg, cfg);
componentViewsRequiredComponents = string(scfg.get( ...
    "output.component_artifact_views.required_components", scfg.get( ...
    "canonical_control.output.component_artifact_views.required_components", ...
    strings(0, 1))));
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
componentViews = sixgr.truth.publishComponentArtifactViews(runFolder, ...
    "Enabled", logical(scfg.get( ...
        "output.component_artifact_views.enabled", scfg.get( ...
        "canonical_control.output.component_artifact_views.enabled", false))), ...
    "Required", logical(scfg.get( ...
        "output.component_artifact_views.required", scfg.get( ...
        "canonical_control.output.component_artifact_views.required", false))), ...
    "RequiredComponents", componentViewsRequiredComponents(:));
% Sanitization and component publication are mutating finalization stages.
% Re-evaluate the exact persisted tree after both so the root verdict never
% describes an earlier intermediate filesystem state.
scenarioStatus = localApplyTruthVerdict(scenarioStatus, ...
    sixgr.truth.evaluateLLSRuntimeTruthContract(runFolder, scfg, cfg, "Result", result), ...
    runFolder, cfg, finalizationMode);
result.Ok = logical(scenarioStatus.ResultOk);
summaryT = localBuildScenarioSummaryTable(scfg, cfg, profile, result, scenarioStatus, runFolder);
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "scenario_summary.csv"), summaryT);
manifest = localBuildManifest(scfg, publicRunFolder, profile, runtimeSummary, environmentSummary, scenarioStatus);
localWriteScenarioManifest(layout, manifest);
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
out.ScenarioStatus = scenarioStatus;
out.ConfigOwnershipArtifacts = configOwnership;
out.ReportBundle = reportBundle;
out.TruthArtifactScan = truthArtifactScan;
out.OutputCoverageArtifacts = outputCoverage;
out.ComponentArtifactViews = componentViews;
out.SanitizedCSVs = sanitizedCSVs;
out.RestoredTruthArtifacts = restoredTruthArtifacts;
out.RecoveryArtifactStore = recoveryStore;
out.FinalizationMode = finalizationMode;
end

function scfg = localResolveScenarioConfig(inputCfg, sourceFiles, configPath, configHash, layout)
if isa(inputCfg, "sixgr.lls6g.config.ScenarioConfig")
    if strlength(strtrim(string(inputCfg.ConfigHash))) == 0
        data = inputCfg.toStruct();
        configHash = localComputeScenarioConfigHash(data);
        scfg = sixgr.lls6g.config.ScenarioConfig(data, ...
            "SourceFiles", inputCfg.SourceFiles, ...
            "ConfigPath", inputCfg.ConfigPath, ...
            "ConfigHash", configHash, ...
            "Kind", inputCfg.Kind);
        return;
    end
    scfg = inputCfg;
    return;
end
if ischar(inputCfg) || isstring(inputCfg)
    candidate = string(inputCfg);
    if exist(char(candidate), "file") == 2
        scfg = sixgr.lls6g.config.loadScenarioConfig(char(candidate));
        return;
    end
    error("sixgr:truth:recover:ScenarioConfigNotFound", ...
        "Scenario configuration '%s' could not be resolved for artifact recovery.", char(candidate));
end
data = inputCfg;
if isstruct(data) && isfield(data, "lls6g") && isstruct(data.lls6g) && isfield(data.lls6g, "resolvedConfig")
    data = data.lls6g.resolvedConfig;
    if strlength(configPath) == 0
        configPath = string(sixgr.util.structGet(inputCfg, ...
            "lls6g.resolvedConfig.config_inheritance.provenance.config_path", ""));
    end
    if isempty(sourceFiles) || all(strlength(strtrim(sourceFiles(:))) == 0)
        sourceFiles = string(sixgr.util.structGet(inputCfg, ...
            "lls6g.resolvedConfig.config_inheritance.provenance.source_files", strings(0,1)));
    end
    if strlength(configHash) == 0
        configHash = string(sixgr.util.structGet(inputCfg, "meta.configHash", ""));
    end
end
sixgr.lls6g.config.validateScenarioConfig(data, ...
    "Kind", "scenario", "AllowPartial", false, "Context", "recoverLLSRunArtifacts");
if (isempty(sourceFiles) || all(strlength(strtrim(sourceFiles(:))) == 0)) && exist(fullfile(layout.MetaDir, "scenario_source_chain.csv"), "file") == 2
    try
        chainT = readtable(fullfile(layout.MetaDir, "scenario_source_chain.csv"), "VariableNamingRule", "preserve");
        if istable(chainT) && ismember("SourceConfigFile", string(chainT.Properties.VariableNames))
            sourceFiles = string(chainT.SourceConfigFile(:));
        end
    catch
    end
end
if strlength(configPath) == 0
    configPath = string(sixgr.util.structGet(data, "meta.loadedFrom", ""));
end
if strlength(configHash) == 0
    configHash = string(sixgr.util.structGet(data, "meta.configHash", ""));
end
if strlength(strtrim(configHash)) == 0
    configHash = localComputeScenarioConfigHash(data);
end
scfg = sixgr.lls6g.config.ScenarioConfig(data, ...
    "SourceFiles", sourceFiles(:), ...
    "ConfigPath", configPath, ...
    "ConfigHash", configHash, ...
    "Kind", "scenario");
end

function cfg = localResolveInternalConfig(inputCfg, scfg, runFolder)
if isstruct(inputCfg) && isfield(inputCfg, "lls6g") && isstruct(inputCfg.lls6g) && isfield(inputCfg.lls6g, "resolvedConfig")
    cfg = inputCfg;
    return;
end
cfg = sixgr.lls6g.buildInternalConfig(scfg, runFolder);
end

function localEnsureDirs(layout)
sixgr.util.ensureFolder(layout.ReportDir);
sixgr.util.ensureFolder(layout.ReportCSVDir);
sixgr.util.ensureFolder(layout.ReportImageDir);
sixgr.util.ensureFolder(layout.MetaDir);
end

function localWriteResolvedSnapshots(layout, scfg)
resolvedStruct = scfg.toStruct();
sixgr.util.jsonWrite(fullfile(layout.MetaDir, "scenario_config_resolved.json"), resolvedStruct);
try
    sixgr.lls6g.config.writeYAML(fullfile(layout.MetaDir, "scenario_config_resolved.yaml"), resolvedStruct);
catch
end
srcFiles = localPortablePath(string(scfg.SourceFiles(:)));
srcT = table(srcFiles, 'VariableNames', {'SourceConfigFile'});
sixgr.util.csvWriteTable(fullfile(layout.MetaDir, "scenario_source_chain.csv"), srcT);
end

function localExportLiveGeometryArtifacts(layout, scfg, cfg)
backend = lower(string(scfg.get("output.backend", "filesystem")));
if backend ~= "mysql_web"
    return;
end
try
    seed = double(sixgr.util.structGet(cfg, "run.seed", sixgr.util.structGet(cfg, "run.randomSeed", 1)));
    rngState = rng; %#ok<RNGR>
    cleanupRng = onCleanup(@() rng(rngState)); %#ok<NASGU>
    rng(seed, "twister");
    scenarioName = string(sixgr.util.structGet(cfg, "scenario.name", scfg.ScenarioID));
    scenarioLayout = sixgr.scenario.generateLayout(cfg, scenarioName);
    ue = sixgr.scenario.dropUEs(cfg, scenarioLayout, scenarioName);
    [siteT, sectorT, trpT, ueT] = localBuildProjectedGeometryTables(scenarioLayout, ue);
    sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "sites.csv"), siteT);
    sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "sectors.csv"), sectorT);
    sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "trps.csv"), trpT);
    sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "ues.csv"), ueT);
catch
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

function [siteT, sectorT, trpT, ueT] = localBuildProjectedGeometryTables(layoutStruct, ue)
anchorLat = 19.122164;
anchorLon = 72.999217;
anchorLabel = "Reliance Corporate Park, Ghansoli, Navi Mumbai";
coordMode = "projected_default_anchor";

sitePos = double(sixgr.util.structGet(layoutStruct, "sites.pos_m", zeros(0,3)));
siteId = double(sixgr.util.structGet(layoutStruct, "sites.id", (1:size(sitePos,1)).'));
[siteLat, siteLon] = sixgr.util.projectLocalXYToGeo(sitePos(:,1), sitePos(:,2), anchorLat, anchorLon);
siteT = table(siteId(:), sitePos(:,1), sitePos(:,2), sitePos(:,3), siteLat(:), siteLon(:), ...
    repmat(string(coordMode), numel(siteId), 1), repmat(string(anchorLabel), numel(siteId), 1), ...
    'VariableNames', {'SiteID','X_m','Y_m','Z_m','Lat','Lon','CoordinateMode','MapAnchorLabel'});

bsPos = double(sixgr.util.structGet(layoutStruct, "bs.pos_m", zeros(0,3)));
siteRef = double(sixgr.util.structGet(layoutStruct, "bs.siteId", nan(size(bsPos,1),1)));
sectorId = double(sixgr.util.structGet(layoutStruct, "bs.sectorId", (1:size(bsPos,1)).'));
az = double(sixgr.util.structGet(layoutStruct, "bs.azim_deg", nan(size(bsPos,1),1)));
txP = double(sixgr.util.structGet(layoutStruct, "bs.txPower_dBm", nan(size(bsPos,1),1)));
[bsLat, bsLon] = sixgr.util.projectLocalXYToGeo(bsPos(:,1), bsPos(:,2), anchorLat, anchorLon);
sectorT = table(siteRef(:), sectorId(:), az(:), bsPos(:,1), bsPos(:,2), bsPos(:,3), bsLat(:), bsLon(:), ...
    repmat(string(coordMode), numel(sectorId), 1), repmat(string(anchorLabel), numel(sectorId), 1), ...
    'VariableNames', {'SiteID','SectorID','Azimuth_deg','X_m','Y_m','Z_m','Lat','Lon','CoordinateMode','MapAnchorLabel'});

trpId = (1:size(bsPos,1)).';
trpT = table(trpId(:), siteRef(:), sectorId(:), az(:), txP(:), bsPos(:,1), bsPos(:,2), bsPos(:,3), bsLat(:), bsLon(:), ...
    repmat(string(coordMode), numel(trpId), 1), repmat(string(anchorLabel), numel(trpId), 1), ...
    'VariableNames', {'TRPID','SiteID','SectorID','Azimuth_deg','TxPower_dBm','X_m','Y_m','Z_m','Lat','Lon','CoordinateMode','MapAnchorLabel'});

ueId = double(sixgr.util.structGet(ue, "id", (1:size(ue.pos_m,1)).'));
uePos = double(sixgr.util.structGet(ue, "pos_m", zeros(0,3)));
ueIndoor = logical(sixgr.util.structGet(ue, "indoor", false(size(uePos,1),1)));
ueSpeed = double(sixgr.util.structGet(ue, "speed_kmh", nan(size(uePos,1),1)));
ueHeading = double(sixgr.util.structGet(ue, "heading_deg", nan(size(uePos,1),1)));
[ueLat, ueLon] = sixgr.util.projectLocalXYToGeo(uePos(:,1), uePos(:,2), anchorLat, anchorLon);
ueT = table(ueId(:), uePos(:,1), uePos(:,2), uePos(:,3), ueLat(:), ueLon(:), ueIndoor(:), ueSpeed(:), ueHeading(:), ...
    repmat(string(coordMode), numel(ueId), 1), repmat(string(anchorLabel), numel(ueId), 1), ...
    'VariableNames', {'UEID','X_m','Y_m','Z_m','Lat','Lon','Indoor','Speed_kmh','Heading_deg','CoordinateMode','MapAnchorLabel'});
end

function runtime = localBuildRuntimeSummary(profile, runFolder, cfg)
runtime = struct();
runtime.StartedUTC = "";
runtime.CompletedUTC = char(localUTCStamp());
runtime.ElapsedSeconds = NaN;
runtime.Profile = char(string(profile));
runtime.RunFolder = char(string(runFolder));
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
if lower(strtrim(string(finalizationMode))) == "completed_run_refinalization"
    status.RunCompletion = "completed_with_failures";
    status.RequiredFailedCases = "completed_run_refinalization_pending_truth_contract";
    status.StatusAuthority = "completed_run_refinalization_pending_truth_contract";
    status.StatusNotes = "Completed waveform evidence is being re-finalized; no success is claimed before every canonical root gate passes.";
    status.ErrorSource = "";
    status.ErrorIdentifier = "";
    status.ErrorMessage = "";
    status.AuthoritativeStatusSource = "completed_run_refinalization_pending_truth_contract";
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
dlTrials = localReadOptionalTable(fullfile(layout.AirInterfaceCSVDir, "dl_pdsch_trials.csv"));
ulTrials = localReadOptionalTable(fullfile(layout.AirInterfaceCSVDir, "ul_pusch_trials.csv"));
opSummary = sixgr.truth.summarizeEffectiveOperatingPoint(scfg, dlTrials, ulTrials);
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
    okVal, ...
    okVal, ...
    logical(scenarioStatus.PartialOk), ...
    logical(scenarioStatus.ArtifactsGenerated), ...
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
    'RunScope','RunCompletion','Ok','ResultOk','PartialOk','ArtifactsGenerated', ...
    'RequiredCaseCount','RequiredFailureCount','OptionalPrunedCount','StatusAuthority', ...
    'RuntimeTruthContractOk','TruthContractOk','StandardsConformanceOk','ScenarioObjectiveOk', ...
    'ConfiguredEffectiveOk','ConfiguredEffectivePolicyOk','MandatorySubsystemsOk','ActiveIssueGateOk','KpiConsistencyOk','StrictAnchorEligible','StrictAnchorPass','ResultStatusReason', ...
    'ActiveMandatoryIssueCount','ActiveCriticalIssueCount','ActiveHighIssueCount','ActiveMediumIssueCount', ...
    'RoundtripMismatchCount','RequiredRuntimeEvidenceMissingCount', ...
    'StrictTruthFailureCount','StrictProxyGuardFailureCount','CanonicalArtifactGapCount','RuntimeTruthContractFailures','Description', ...
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
    T = readtable(pathStr, "VariableNamingRule", "preserve");
catch
    T = table();
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
parts = [string(existing); string(addition)];
parts = strtrim(parts(:));
parts = parts(strlength(parts) > 0);
parts = unique(parts, "stable");
notes = strjoin(parts, " | ");
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
