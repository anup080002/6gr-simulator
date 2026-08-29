function out = refinalizePersistedLLSRuntimeEvidence(cfg, runFolder, varargin)
%REFINALIZEPERSISTEDLLSRUNTIMEEVIDENCE Rebuild derived truth from raw rows.
%
% This function is the persisted-evidence counterpart of the normal
% runWaveformLinkBundle finalization path. It reloads only primary runtime
% trial tables already present on disk and feeds those exact rows through
% the shared derived-table, energy, measured-SINR and fixed-sweep exporters.
% Missing evidence remains missing; no placeholder, fallback or proxy rows
% are introduced.

p = inputParser;
p.addRequired("cfg", @(x)isstruct(x) && isscalar(x));
p.addRequired("runFolder", @(x)ischar(x) || (isstring(x) && isscalar(x)));
p.addParameter("RunTag", "", @(x)ischar(x) || (isstring(x) && isscalar(x)));
p.addParameter("RefreshBrowserContract", "auto", ...
    @(x)(islogical(x) && isscalar(x)) || ...
    (isnumeric(x) && isscalar(x) && isfinite(x) && ismember(double(x), [0 1])) || ...
    ischar(x) || (isstring(x) && isscalar(x)));
p.parse(cfg, runFolder, varargin{:});

runFolder = char(java.io.File(char(string(p.Results.runFolder))).getCanonicalPath());
layout = sixgr.report.resultLayout(runFolder);
requestedRunTag = string(p.Results.RunTag);
if strlength(strtrim(requestedRunTag)) == 0
    requestedRunTag = string(sixgr.util.structGet(cfg, "run.runTag", ""));
end

trialData = sixgr.analytics.loadAllTrialData(runFolder);
rawTrials = localRawTrialBundle(trialData);
runTag = localResolvePersistedRunTag(rawTrials, requestedRunTag);
dlRows = localHeight(rawTrials.DL);
ulRows = localHeight(rawTrials.UL);
rawEvidencePresent = dlRows > 0 || ulRows > 0;
fixedLinkOnly = localResolveFixedLinkCampaignOnly(cfg, rawTrials);
% Runtime rows are the authority for what actually executed.  Propagate the
% resolved campaign class into every downstream reducer; keeping it only in
% this local variable caused fixed-link reanalysis to invoke connected-run
% access/scheduler KPI requirements.
cfg = sixgr.util.structSet(cfg, "run.fixedLinkCampaignOnly", ...
    logical(fixedLinkOnly));
refreshBrowserContract = localResolveBrowserContractRefresh( ...
    p.Results.RefreshBrowserContract, layout);

out = struct( ...
    "Ok", false, ...
    "Status", "no_persisted_dl_or_ul_runtime_trials", ...
    "RunFolder", string(runFolder), ...
    "RunTag", runTag, ...
    "RawEvidencePresent", logical(rawEvidencePresent), ...
    "DLTrialRows", double(dlRows), ...
    "ULTrialRows", double(ulRows), ...
    "FixedLinkCampaignOnly", logical(fixedLinkOnly), ...
    "DerivedTablesGenerated", false, ...
    "EnergyEvidenceGenerated", false, ...
    "MeasuredSINREvidenceGenerated", false, ...
    "Phase7RefreshCompleted", false, ...
    "Phase7RefreshStatus", "not_evaluated", ...
    "FixedSweepEvidenceGenerated", false, ...
    "FixedSweepStatus", "not_applicable", ...
    "FixedSweepFailureIdentifier", "", ...
    "FixedSweepFailureMessage", "", ...
    "SourceCSVFinalizationCompleted", false, ...
    "SourceCSVFinalization", struct(), ...
    "LinkKPIReconstructionCompleted", false, ...
    "LinkKPIReconstructionStatus", "not_evaluated", ...
    "BrowserContractRefreshRequested", string(refreshBrowserContract.Requested), ...
    "BrowserContractRefreshAttempted", false, ...
    "BrowserContractRefreshOk", false, ...
    "BrowserContractRefreshStatus", string(refreshBrowserContract.Status), ...
    "BrowserContractMaterialization", struct(), ...
    "DerivedArtifacts", struct(), ...
    "EnergyArtifacts", struct(), ...
    "MeasuredSINRArtifacts", struct(), ...
    "FixedSweepArtifacts", struct(), ...
    "LinkKPIArtifacts", struct(), ...
    "ProvenanceJSON", "");

if ~rawEvidencePresent
    out.ProvenanceJSON = localWriteProvenance(layout, out);
    return;
end

mobilityArtifacts = localMobilityArtifacts(layout);
slotTrace = localSlotTrace(trialData);
out.DerivedArtifacts = sixgr.truth.exportLLSLiveDerivedTables( ...
    cfg, runFolder, rawTrials, struct(), mobilityArtifacts, slotTrace);
out.DerivedTablesGenerated = true;

out.EnergyArtifacts = sixgr.truth.exportLLSEnergyDiagnostics( ...
    cfg, fullfile(runFolder, "air_interface"), rawTrials);
out.EnergyEvidenceGenerated = true;

% KPI manifests and plot lineage are byte-level evidence contracts.  The
% live derived exporter above can create scheduler, packet and application
% ledgers whose canonical schema is completed by the artifact sanitizer.
% Finalize those source bytes before any KPI reconstruction records their
% width or SHA-256.  The later terminal sanitizer must therefore be a
% byte-idempotent verification pass rather than a post-manifest mutation.
out.SourceCSVFinalization = sixgr.truth.sanitizeLLSArtifactCSVs(runFolder);
out.SourceCSVFinalizationCompleted = true;

% Reload the primary tables after canonicalization so every downstream
% in-memory projection observes the same schema that is persisted and
% hashed.  Row identity and counts are immutable across this operation.
finalizedTrialData = sixgr.analytics.loadAllTrialData(runFolder);
finalizedRawTrials = localRawTrialBundle(finalizedTrialData);
if localHeight(finalizedRawTrials.DL) ~= dlRows || ...
        localHeight(finalizedRawTrials.UL) ~= ulRows
    error("sixgr:truth:refinalize:SourceFinalizationRowCountChanged", ...
        ["Canonical source finalization changed primary DL/UL row counts " ...
        "from %d/%d to %d/%d."], ...
        dlRows, ulRows, localHeight(finalizedRawTrials.DL), ...
        localHeight(finalizedRawTrials.UL));
end
rawTrials = finalizedRawTrials;

persistedKPITable = localReadPersistedLinkKPITable(layout);
if fixedLinkOnly
    campaign = localFixedLinkCampaign(layout, rawTrials);
    if istable(campaign.Summary) && height(campaign.Summary) > 0
        persistedKPITable = campaign.Summary;
        try
            out.FixedSweepArtifacts = sixgr.analytics.exportFixedSNRSweepCurves( ...
                runFolder, campaign, cfg, struct("WriteArtifacts", true));
            out.FixedSweepEvidenceGenerated = true;
            out.FixedSweepStatus = "refinalized_from_persisted_runtime_rows";
        catch ME
            % Preserve the pre-existing artifacts and report the exact
            % refinalization failure. This may be a legacy schema gap or a
            % present implementation error, so do not relabel every
            % exception as schema incompatibility and never manufacture
            % missing interval/design evidence.
            out.FixedSweepEvidenceGenerated = false;
            out.FixedSweepStatus = "persisted_fixed_sweep_refinalization_failed";
            out.FixedSweepFailureIdentifier = string(ME.identifier);
            out.FixedSweepFailureMessage = string(ME.message);
        end
    else
        out.FixedSweepStatus = "persisted_fixed_sweep_summary_missing";
    end
end

% Reconstruct the complete KPI sidecar bundle for every completed runtime,
% not only for fixed-link sweeps.  The online waveform path already wrote
% link_kpis.csv; replaying the KPI exporter here binds the manifest to the
% finalized packet, grant, HARQ, slot and PHY source bytes above.  If the
% persisted KPI authority is absent, remain fail closed instead of creating
% a substitute summary from unrelated aggregates.
if istable(persistedKPITable) && width(persistedKPITable) > 0 && ...
        height(persistedKPITable) > 0
    kpiDetails = struct( ...
        "Config", cfg, ...
        "RunId", runTag, ...
        "ScenarioName", string(sixgr.util.structGet(cfg, "run.scenarioID", "")));
    % Deliberately omit RawTrials here. exportLinkKPIs will reload every KPI
    % source from runFolder, so its semantic hashes describe the exact
    % finalized CSV representation rather than an earlier in-memory table.
    out.LinkKPIArtifacts = sixgr.link.exportLinkKPIs( ...
        fullfile(runFolder, "air_interface"), persistedKPITable, kpiDetails, ...
        "SaveCSV", true, "SaveMAT", false, "SaveFigures", false, ...
        "SavePNG", false, "FigurePrefix", "persisted_runtime_truth_validation", ...
        "PlotVisible", false);
    out.LinkKPIReconstructionCompleted = true;
    out.LinkKPIReconstructionStatus = "reconstructed_from_finalized_source_csv_bytes";
else
    out.LinkKPIReconstructionStatus = "persisted_link_kpi_authority_missing";
end

% Match the production fixed-link finalization order: the aggregate KPI
% reconstruction is written first and the directional, raw-row-reconciled
% KPI table is the final lls_kpi_summary authority. Reversing this order
% silently replaced the directional schema with a one-row aggregate table.
out.MeasuredSINRArtifacts = sixgr.analytics.generateMeasuredSINRCurves( ...
    runFolder, runTag, ...
    "TrialData", rawTrials, ...
    "ScenarioConfig", cfg, ...
    "WriteKPISummary", true, ...
    "UpdateAnchorKPIs", true);
out.MeasuredSINREvidenceGenerated = true;

% Every reducer above can change persisted inputs consumed by Phase 7
% (mobility/KPI reconciliation, source manifests, measured-SINR evidence).
% Re-finalization previously left phase7_truth_gates.csv at its pre-refresh
% value, so the browser/exhaustive audit could observe a true reconciliation
% row alongside a stale false Phase-7 flag.  Recompute the terminal reducer
% from the same immutable configuration and finalized filesystem before any
% browser contract is materialized.  This does not promote a missing gate;
% buildPhase7ReadinessArtifacts remains fail-closed for absent evidence.
phase7 = sixgr.analytics.buildPhase7ReadinessArtifacts(cfg, runFolder);
out.Phase7RefreshCompleted = true;
out.Phase7RefreshStatus = "refreshed_from_finalized_persisted_runtime_evidence";
out.DerivedArtifacts.Phase7 = phase7;

if logical(refreshBrowserContract.Enabled)
    out.BrowserContractRefreshAttempted = true;
    out.BrowserContractMaterialization = ...
        sixgr.artifact.materializeBrowserContractArtifacts(runFolder);
    out.BrowserContractRefreshOk = logical(sixgr.util.structGet( ...
        out.BrowserContractMaterialization, "Ok", false));
    if out.BrowserContractRefreshOk
        out.BrowserContractRefreshStatus = ...
            "existing_browser_contract_refreshed_from_current_csv_bytes";
    else
        out.BrowserContractRefreshStatus = ...
            "existing_browser_contract_refresh_failed";
    end
end

fixedSweepOk = ~fixedLinkOnly || logical(out.FixedSweepEvidenceGenerated);
kpiReconstructionOk = logical(out.LinkKPIReconstructionCompleted);
browserRefreshOk = ~logical(out.BrowserContractRefreshAttempted) || ...
    logical(out.BrowserContractRefreshOk);
out.Ok = fixedSweepOk && kpiReconstructionOk && browserRefreshOk;
if ~browserRefreshOk
    out.Status = "persisted_runtime_truth_refinalized_with_browser_contract_failure";
elseif ~kpiReconstructionOk
    out.Status = "persisted_runtime_truth_refinalized_with_kpi_reconstruction_failure";
elseif out.Ok
    out.Status = "persisted_runtime_truth_refinalized";
else
    out.Status = "persisted_runtime_truth_refinalized_with_fixed_sweep_failure";
end

out.ProvenanceJSON = localWriteProvenance(layout, out);
end

function T = localReadPersistedLinkKPITable(layout)
T = table();
pathValue = fullfile(layout.AirInterfaceCSVDir, "link_kpis.csv");
if exist(pathValue, "file") ~= 2
    return;
end
try
    T = readtable(pathValue, "FileType", "text", "Delimiter", ",", ...
        "ReadVariableNames", true, "VariableNamingRule", "preserve", ...
        "TextType", "string");
catch
    T = table();
end
end

function policy = localResolveBrowserContractRefresh(value, layout)
requested = lower(strtrim(string(value)));
if islogical(value) || isnumeric(value)
    enabled = logical(value);
    if enabled
        requested = "true";
    else
        requested = "false";
    end
elseif ~ismember(requested, ["auto", "true", "false"])
    error("sixgr:truth:refinalize:InvalidBrowserContractRefresh", ...
        "RefreshBrowserContract must be auto, true or false.");
end

hasExistingContract = exist(fullfile(layout.ReportCSVDir, ...
    "contract_plot_lineage.csv"), "file") == 2 || ...
    exist(fullfile(layout.ReportCSVDir, ...
    "contract_materialization_manifest.csv"), "file") == 2;
if requested == "auto"
    enabled = hasExistingContract;
    if enabled
        status = "auto_refresh_existing_browser_contract";
    else
        status = "auto_skipped_no_existing_browser_contract";
    end
elseif requested == "true"
    enabled = true;
    status = "explicit_browser_contract_refresh";
else
    enabled = false;
    status = "explicit_browser_contract_refresh_disabled";
end
policy = struct( ...
    "Requested", requested, ...
    "Enabled", logical(enabled), ...
    "ExistingContract", logical(hasExistingContract), ...
    "Status", string(status));
end

function runTag = localResolvePersistedRunTag(rawTrials, requestedRunTag)
persisted = strings(0, 1);
for direction = ["DL", "UL"]
    T = rawTrials.(char(direction));
    if ~(istable(T) && height(T) > 0)
        continue;
    end
    vars = string(T.Properties.VariableNames);
    for fieldName = ["RunID", "RunId", "RunTag"]
        if ~ismember(fieldName, vars)
            continue;
        end
        values = strtrim(string(T.(char(fieldName))));
        values = values(~ismissing(values) & strlength(values) > 0);
        persisted = [persisted; values(:)]; %#ok<AGROW>
    end
end
persisted = unique(persisted, "stable");
if numel(persisted) > 1
    error("sixgr:truth:refinalize:InconsistentPersistedRunIdentity", ...
        "Primary persisted DL/UL rows contain multiple run identities: %s.", ...
        char(strjoin(persisted, ", ")));
end

requestedRunTag = strtrim(string(requestedRunTag));
if isempty(persisted)
    runTag = requestedRunTag;
    return;
end
runTag = persisted(1);
if strlength(requestedRunTag) > 0 && requestedRunTag ~= runTag
    error("sixgr:truth:refinalize:PersistedRunIdentityMismatch", ...
        "Requested RunTag '%s' does not match immutable primary runtime identity '%s'.", ...
        char(requestedRunTag), char(runTag));
end
end

function raw = localRawTrialBundle(trialData)
raw = struct( ...
    "DL", localTableField(trialData, "dl"), ...
    "UL", localTableField(trialData, "ul"), ...
    "SRS", localTableField(trialData, "srs"), ...
    "TRS", localTableField(trialData, "trs"), ...
    "PDCCH", localTableField(trialData, "pdcch"), ...
    "PUCCH", localTableField(trialData, "pucch"), ...
    "PRACH", localTableField(trialData, "prach"), ...
    "PBCH", localTableField(trialData, "pbch"));
end

function T = localTableField(s, name)
T = table();
if isstruct(s) && isfield(s, char(name)) && istable(s.(char(name)))
    T = s.(char(name));
end
end

function n = localHeight(T)
if istable(T)
    n = height(T);
else
    n = 0;
end
end

function fixedLinkOnly = localResolveFixedLinkCampaignOnly(cfg, rawTrials)
% Accept both the internal camelCase config and the immutable resolved-YAML
% snake_case form used by persisted WebGUI runs. Runtime row classification
% is the final authority for what actually executed.
configured = logical(sixgr.util.structGet(cfg, ...
    "run.fixedLinkCampaignOnly", sixgr.util.structGet(cfg, ...
    "run.fixed_link_campaign_only", sixgr.util.structGet(cfg, ...
    "simulation.fixed_link_campaign_enabled", false))));
observed = false(0, 1);
for direction = ["DL", "UL"]
    T = sixgr.util.structGet(rawTrials, direction, table());
    if ~(istable(T) && height(T) > 0) || ...
            ~ismember("FixedLinkCampaign", string(T.Properties.VariableNames))
        continue;
    end
    raw = T.FixedLinkCampaign;
    if islogical(raw) || isnumeric(raw)
        values = isfinite(double(raw(:))) & double(raw(:)) ~= 0;
    else
        token = lower(strtrim(string(raw(:))));
        values = token == "1" | token == "true" | token == "yes";
    end
    observed = [observed; values(:)]; %#ok<AGROW>
end
if isempty(observed)
    fixedLinkOnly = configured;
else
    % Mixed fixed/system rows are not a fixed-link-only campaign even when
    % an obsolete config flag says otherwise.
    fixedLinkOnly = all(observed);
end
end

function mobility = localMobilityArtifacts(layout)
mobility = struct();
pathValue = fullfile(layout.Root, "mobility", "csv", "trajectory_resolution.csv");
T = localReadOptionalTable(pathValue);
if istable(T) && height(T) > 0
    mobility.Resolution = T;
end
end

function slotTrace = localSlotTrace(trialData)
slotTrace = struct();
T = localTableField(trialData, "harq");
if height(T) > 0
    slotTrace.HARQTimelineTable = T;
end
end

function campaign = localFixedLinkCampaign(layout, rawTrials)
campaign = struct( ...
    "Enabled", true, ...
    "Summary", localReadFirstAvailableTable( ...
        fullfile(layout.AirInterfaceCSVDir, "lls_fixed_link_campaign.csv"), ...
        fullfile(layout.AirInterfaceCSVDir, "lls_snr_sweep.csv"), ...
        fullfile(layout.ReportCSVDir, "fixed_link_campaign_summary.csv")), ...
    "ReferenceSummary", localReadOptionalTable(fullfile( ...
        layout.AirInterfaceCSVDir, "lls_reference_snr_sweep.csv")), ...
    "TaskPlan", localReadFirstAvailableTable( ...
        fullfile(layout.AirInterfaceCSVDir, "fixed_link_campaign_task_plan.csv"), ...
        fullfile(layout.ReportCSVDir, "fixed_link_campaign_task_plan.csv")), ...
    "DLTrials", rawTrials.DL, ...
    "ULTrials", rawTrials.UL, ...
    "TargetCrossings", localTargetCrossings(layout));
end

function T = localTargetCrossings(layout)
T = localReadOptionalTable(fullfile(layout.ReportCSVDir, ...
    "fixed_snr_sweep_curve_crossing.csv"));
if ~(istable(T) && height(T) > 0)
    return;
end
T = localAliasColumn(T, "MCSIndex", "MCS");
T = localAliasColumn(T, "CrossingSNR_dB", "TargetCrossingSNR_dB");
T = localAliasColumn(T, "CrossingStatus", "TargetCrossingStatus");
end

function T = localAliasColumn(T, targetName, sourceName)
vars = string(T.Properties.VariableNames);
if ~ismember(targetName, vars) && ismember(sourceName, vars)
    T.(char(targetName)) = T.(char(sourceName));
end
end

function pathValue = localWriteProvenance(layout, out)
reportJSONDir = fullfile(layout.ReportDir, "json");
sixgr.util.ensureFolder(reportJSONDir);
pathValue = fullfile(reportJSONDir, "runtime_evidence_refinalization.json");
payload = struct( ...
    "Producer", "sixgr.truth.refinalizePersistedLLSRuntimeEvidence", ...
    "GeneratedUTC", char(datetime("now", "TimeZone", "UTC", ...
        "Format", "yyyy-MM-dd'T'HH:mm:ss'Z'")), ...
    "Status", char(string(out.Status)), ...
    "RawEvidencePresent", logical(out.RawEvidencePresent), ...
    "DLTrialRows", double(out.DLTrialRows), ...
    "ULTrialRows", double(out.ULTrialRows), ...
    "FixedLinkCampaignOnly", logical(out.FixedLinkCampaignOnly), ...
    "DerivedTablesGenerated", logical(out.DerivedTablesGenerated), ...
    "EnergyEvidenceGenerated", logical(out.EnergyEvidenceGenerated), ...
    "MeasuredSINREvidenceGenerated", logical(out.MeasuredSINREvidenceGenerated), ...
    "Phase7RefreshCompleted", logical(out.Phase7RefreshCompleted), ...
    "Phase7RefreshStatus", char(string(out.Phase7RefreshStatus)), ...
    "FixedSweepEvidenceGenerated", logical(out.FixedSweepEvidenceGenerated), ...
    "FixedSweepStatus", char(string(out.FixedSweepStatus)), ...
    "FixedSweepFailureIdentifier", char(string(out.FixedSweepFailureIdentifier)), ...
    "FixedSweepFailureMessage", char(string(out.FixedSweepFailureMessage)), ...
    "SourceCSVFinalizationCompleted", logical(out.SourceCSVFinalizationCompleted), ...
    "LinkKPIReconstructionCompleted", logical(out.LinkKPIReconstructionCompleted), ...
    "LinkKPIReconstructionStatus", char(string(out.LinkKPIReconstructionStatus)), ...
    "BrowserContractRefreshRequested", char(string(out.BrowserContractRefreshRequested)), ...
    "BrowserContractRefreshAttempted", logical(out.BrowserContractRefreshAttempted), ...
    "BrowserContractRefreshOk", logical(out.BrowserContractRefreshOk), ...
    "BrowserContractRefreshStatus", char(string(out.BrowserContractRefreshStatus)), ...
    "EvidencePolicy", "persisted_primary_runtime_rows_only_no_proxy_no_fallback_no_placeholder");
sixgr.util.jsonWrite(pathValue, payload);
pathValue = string(pathValue);
end

function T = localReadFirstAvailableTable(varargin)
T = table();
for i = 1:nargin
    T = localReadOptionalTable(varargin{i});
    if height(T) > 0 || exist(char(string(varargin{i})), "file") == 2
        return;
    end
end
end

function T = localReadOptionalTable(pathValue)
T = table();
if exist(char(string(pathValue)), "file") ~= 2
    return;
end
try
    T = sixgr.util.csvReadTable(pathValue, "TextType", "string");
catch
    T = table();
end
end
