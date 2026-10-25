function out = runWaveformLinkBundle(cfg, runFolder, opt)
%RUNWAVEFORMLINKBUNDLE Run strict waveform link/control validation exports.

if nargin < 3 || ~isstruct(opt)
    opt = struct();
end
sixgr.config.assertRuntimeFeatureAuthority(cfg);
persistenceEnabled = localResolvePersistenceEnabled(opt);
persistenceCleanup = sixgr.util.persistenceScope(persistenceEnabled); %#ok<NASGU>

cfgL = cfg;
% Preserve publication authority before disabling per-trial legacy figures.
cfgL.outputs.liveCSVPNGEnabled = logical(sixgr.util.structGet(cfg, "outputs.liveCSVPNGEnabled", false)) && ...
    logical(sixgr.util.structGet(opt, "LiveCSVPNGEnabled", ...
        sixgr.util.structGet(opt, "SaveFigures", sixgr.util.structGet(cfg, "outputs.saveFigures", false)))) && ...
    logical(sixgr.util.structGet(cfg, "outputs.savePNG", false)) && logical(persistenceEnabled);
cfgL.run.mode = "link";
cfgL.run.shortRun = false;
cfgL.outputs.saveCSV = false;
cfgL.outputs.saveMAT = false;
cfgL.outputs.saveFigures = false;
cfgL.outputs.saveFIG = false;
cfgL.outputs.savePNG = true;
cfgL.channel.snr_dB = double(sixgr.util.structGet(opt, "LinkSNR_dB", 30));
multiUser = localResolveMultiUserSpec(cfgL);
isCoupledTruth = logical(multiUser.Enabled) && string(multiUser.ExecutionModel) == "slot_coupled_truth";
isacEnabled = logical(sixgr.util.structGet(cfgL,"isac.enabled",false));
if isacEnabled
    sixgr.isac.validateConfig(cfgL);
    if ~isCoupledTruth
        error("sixgr:isac:RequiresCoupledTruthRuntime", ...
            "Enabled full-stack ISAC requires slot_coupled_truth so the exact committed PDSCH waveform, topology, and runtime antenna objects share one state.");
    end
end
cfgExec = localPrepareUserCfg(cfgL, multiUser, 1);
rootRunFolder = fileparts(char(string(runFolder)));
stageProfileCleanup=sixgr.runtime.ExecutionStageProfiler.start(rootRunFolder, ...
    logical(sixgr.util.structGet(cfg,'outputs.executionStageProfileEnabled',false))); %#ok<NASGU>
cfgL = sixgr.util.structSet(cfgL, "run.rootRunFolder", rootRunFolder);
cfgExec = sixgr.util.structSet(cfgExec, "run.rootRunFolder", rootRunFolder);
cfgL = sixgr.util.structSet(cfgL, "run.fixedLinkCampaignWriteArtifacts", logical(persistenceEnabled));
cfgExec = sixgr.util.structSet(cfgExec, "run.fixedLinkCampaignWriteArtifacts", logical(persistenceEnabled));
fixedLinkCampaignOnly = logical(sixgr.util.structGet(opt, "FixedLinkCampaignOnly", false));
cfgL = sixgr.util.structSet(cfgL, "run.fixedLinkCampaignOnly", fixedLinkCampaignOnly);
cfgExec = sixgr.util.structSet(cfgExec, "run.fixedLinkCampaignOnly", fixedLinkCampaignOnly);

sixgr.util.ensureFolder(runFolder);
sixgr.util.ensureFolder(fullfile(runFolder, "csv"));
sixgr.util.ensureFolder(fullfile(runFolder, "mat"));
sixgr.util.ensureFolder(fullfile(runFolder, "image"));

ctx = sixgr.core.SimContext(cfgExec, "RunFolder", runFolder);
ctx.Logger.EchoToConsole = false;
localRuntimeLogPath("set", fullfile(runFolder, "logs", "run.log"));

slotDur_s = localSlotDuration(cfgExec);
reqFrames = ceil(double(sixgr.util.structGet(opt, "LinkDuration_s", 0.02)) / max(slotDur_s, eps));
requestedMaxFrames = round(double(sixgr.util.structGet(opt, "LinkMaxSimFrames", reqFrames)));
numFrames = max(1, min(requestedMaxFrames, reqFrames));
sweepPlan = localResolveSweepPlan(opt, numFrames);

if fixedLinkCampaignOnly
    fixedGridFallback = sixgr.util.structGet(opt, "LinkSNRGrid_dB", ...
        sixgr.util.structGet(opt, "LinkSNR_dB", cfgExec.channel.snr_dB));
    fixedLinkGrid = localResolveFixedLinkCampaignGrid(double(fixedGridFallback), sweepPlan);
    campaign = localRunFixedLinkCampaign(cfgExec, fixedLinkGrid(:), sweepPlan, multiUser);
    fixedSummary = sixgr.util.structGet(campaign, "Summary", table());
    if istable(fixedSummary) && ~isempty(fixedSummary)
        sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "lls_snr_sweep.csv"), fixedSummary, "PreserveSchema", true);
        sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "lls_fixed_link_campaign.csv"), fixedSummary, "PreserveSchema", true);
    end
    if logical(persistenceEnabled)
        localWriteFixedLinkCampaignEvidence(runFolder, campaign);
    end
    rawTrials = struct( ...
        "DL", sixgr.util.structGet(campaign, "DLTrials", table()), ...
        "UL", sixgr.util.structGet(campaign, "ULTrials", table()));
    energyArtifacts = struct();
    measuredSINRArtifacts = struct();
    liveDerivedArtifacts = struct();
    if logical(persistenceEnabled)
        rawTrials = localPublishFixedLinkCanonicalTruthEvidence( ...
            runFolder, cfgExec, multiUser, campaign);
        % Fixed-link-only execution is still a production waveform run.
        % Feed its exact canonical trial rows through the same derived-table
        % and reconciliation pipeline as the ordinary waveform bundle.  Do
        % not leave Phase-7 to infer RF/noise/MIMO evidence from configured
        % values, and do not synthesize scheduler/control rows that this
        % mode did not execute.
        liveDerivedArtifacts = sixgr.truth.exportLLSLiveDerivedTables( ...
            cfgExec, rootRunFolder, rawTrials, multiUser, struct(), struct());
        % Fixed-link-only execution still consumes real PDSCH/PUSCH trial
        % rows.  Feed those exact rows through the same runtime-conditioned
        % engineering energy model used by the connected runtime.  This is
        % model-backed evidence (and is labelled as such by the exporter),
        % never measured circuit power and never a synthetic primary PHY
        % row.
        energyArtifacts = sixgr.truth.exportLLSEnergyDiagnostics( ...
            cfgExec, runFolder, rawTrials);
        kpiDetails = struct( ...
            "RawTrials", rawTrials, ...
            "Config", cfgExec, ...
            "RunId", string(sixgr.util.structGet(cfgExec, "run.runTag", "")), ...
            "ScenarioName", string(sixgr.util.structGet(cfgExec, ...
            "run.scenarioID", sixgr.util.structGet(cfgExec, "meta.lls6gScenarioID", ""))));
        measuredSINRArtifacts.KPIReconstruction = sixgr.link.exportLinkKPIs( ...
            runFolder, fixedSummary, kpiDetails, ...
            "SaveCSV", true, ...
            "SaveMAT", false, ...
            "SaveFigures", false, ...
            "SavePNG", false, ...
            "FigurePrefix", "fixed_link_truth_validation", ...
            "PlotVisible", false);
        try
            measuredSINRArtifacts.Curves = ...
                sixgr.analytics.generateMeasuredSINRCurves( ...
                rootRunFolder, ...
                string(sixgr.util.structGet(cfgExec, "run.runTag", "")), ...
                "TrialData", rawTrials, ...
                "ScenarioConfig", cfgExec, ...
                "WriteKPISummary", true, ...
                "UpdateAnchorKPIs", true);
            if logical(sixgr.util.structGet(opt, "SaveFigures", true))
                measuredSINRArtifacts.Plots = ...
                    sixgr.analytics.generateMeasuredSINRPlots( ...
                    rootRunFolder, ...
                    string(sixgr.util.structGet( ...
                    cfgExec, "run.runTag", "")));
            end
        catch ME
            measuredSINRArtifacts = struct( ...
                "Ok", false, ...
                "Identifier", string(ME.identifier), ...
                "Message", string(ME.message));
        end
    end
    if logical(sixgr.util.structGet(campaign, "Enabled", false))
        sixgr.analytics.exportFixedSNRSweepCurves(rootRunFolder, campaign, cfgExec, ...
            struct("WriteArtifacts", logical(persistenceEnabled)));
        % Production rasters are generated once, after final CSV bytes are
        % stable, by scripts/materialize_lls_contract_artifacts.py.  Do not
        % create an earlier MATLAB PNG/lineage authority here.
    end
    out = struct();
    out.Ok = localFixedLinkCampaignEvidenceOk(campaign);
    out.RunFolder = runFolder;
    out.Result = struct("SNRSweep", fixedSummary, ...
        "ReferenceSweep", table(), "FixedLinkCampaign", campaign);
    out.KPITable = table();
    out.SNRSweep = fixedSummary;
    out.ReferenceSweep = fixedSummary;
    out.FixedLinkCampaign = campaign;
    out.RawTrials = rawTrials;
    out.Artifacts = struct("MeasuredSINR", measuredSINRArtifacts, ...
        "Energy", energyArtifacts, "LiveDerived", liveDerivedArtifacts);
    out.EnergyArtifacts = energyArtifacts;
    out.LiveDerivedArtifacts = liveDerivedArtifacts;
    out.Errors = strings(0,1);
    out.MultiUser = multiUser;
    out.PersistenceEnabled = logical(persistenceEnabled);
    out.CoreOnly = ~logical(persistenceEnabled);
    return;
end

params = struct();
params.NumFrames = numFrames;
params.ForceLong = true;
bundleStart = tic;
stageRows = repmat(localEmptyRuntimeStageRow(), 0, 1);
stageOrder = 0;
liveSweepPath = "";
saveFigures = logical(sixgr.util.structGet(opt, "SaveFigures", true));
% Same-trial TX/RX/Hest capture is evidence, not a legacy MATLAB figure.
% SaveFigures=false suppresses rendering only; it must not suppress the
% exact source rows later consumed by the contract materializer.
diagnosticEnabled = logical(sixgr.util.structGet(cfgExec, ...
    "outputs.phySignalDiagnosticEnabled", false));
cfgL = sixgr.util.structSet(cfgL, "outputs.phySignalDiagnosticEnabled", diagnosticEnabled);
cfgExec = sixgr.util.structSet(cfgExec, "outputs.phySignalDiagnosticEnabled", diagnosticEnabled);
anchorCaseNames = localResolveBundleAnchorCases(opt);
receiverNoiseMode = localUsesReceiverNoiseMeasurement(cfgExec, opt);
if logical(sixgr.util.structGet(opt, "ResumeCompletedRuntimeFinalization", false))
    out = localResumeCompletedRuntimeFinalization(cfgExec, runFolder, opt, ...
        multiUser, sweepPlan, saveFigures, diagnosticEnabled, ctx, ...
        bundleStart, stageRows, stageOrder);
    return;
end

if receiverNoiseMode
    localLogStage(ctx, "Starting strict waveform LLS bundle: slot_steps=" + string(numFrames) + ...
        ", quality_mode=" + localResolveNoiseOperatingMode(cfgExec) + ...
        ", operating_point_label_db=" + string(double(sixgr.util.structGet(opt, "LinkSNR_dB", 30))));
else
    localLogStage(ctx, "Starting strict waveform LLS bundle: slot_steps=" + string(numFrames) + ...
        ", configured_snr_db=" + string(double(sixgr.util.structGet(opt, "LinkSNR_dB", 30))));
end
stageStart = tic;
if isCoupledTruth
    localLogStage(ctx, "Coupled truth mode defers legacy preflight cases to the canonical slot runtime.");
    res = localRunConfiguredBundleAnchorCases(cfgExec, ctx, numFrames, ...
        double(sixgr.util.structGet(opt, "LinkSNR_dB", 30)), strings(0, 1));
elseif isempty(anchorCaseNames)
    res = sixgr.link.LinkLevelRunner.run(ctx, params);
else
    localLogStage(ctx, "Bundle preflight cases constrained by config: " + strjoin(anchorCaseNames, ", "));
    res = localRunConfiguredBundleAnchorCases(cfgExec, ctx, numFrames, ...
        double(sixgr.util.structGet(opt, "LinkSNR_dB", 30)), anchorCaseNames);
end
[stageRows, stageOrder] = localAppendRuntimeStageProfile(rootRunFolder, stageRows, stageOrder, ...
    "anchor_link_run", toc(stageStart), toc(bundleStart), "Initial waveform preflight run completed.");
unsupportedCases = table();
[res, unsupportedCases] = localPruneUnsupportedTruthCases(res);
localPublishAnchorKPIArtifacts(runFolder, res);
localPublishWaveformBundleStageStatus(runFolder, struct( ...
    "Stage", "link_anchor_complete", ...
    "AnchorKPIsReady", istable(sixgr.util.structGet(res, "KPITable", table())) && ~isempty(res.KPITable), ...
    "DLTrialsReady", false, ...
    "ULTrialsReady", false, ...
    "ControlReady", false, ...
    "HARQReady", false, ...
    "BeamReady", false, ...
    "RFReady", false, ...
    "SweepReady", false, ...
    "FinalBundleReady", false, ...
    "Notes", "Initial waveform preflight completed; configured SNR is metadata only in receiver-noise mode."));
stageStart = tic;
localPublishRuntimeReferenceArtifacts(runFolder, cfgL, multiUser);
[stageRows, stageOrder] = localAppendRuntimeStageProfile(rootRunFolder, stageRows, stageOrder, ...
    "runtime_reference_artifacts", toc(stageStart), toc(bundleStart), "Reference runtime, CQI, MCS, and deployment tables published.");
localLogStage(ctx, "Publishing live mobility, serving-cell, and coverage sidecar tables.");
stageStart = tic;
if isCoupledTruth
    liveMobilityArtifacts = struct();
    [stageRows, stageOrder] = localAppendRuntimeStageProfile(rootRunFolder, stageRows, stageOrder, ...
        "live_mobility_deferred_to_coupled_runtime", toc(stageStart), toc(bundleStart), ...
        "Coupled truth mode defers live mobility/map telemetry to the canonical slot runtime.");
else
    liveMobilityArtifacts = sixgr.truth.exportLLSLiveMobilityTables(cfgL, rootRunFolder, multiUser);
    [stageRows, stageOrder] = localAppendRuntimeStageProfile(rootRunFolder, stageRows, stageOrder, ...
        "live_mobility_sidecar", toc(stageStart), toc(bundleStart), "Per-slot RSRP, movement, coverage, and reselection sidecar tables published.");
end
localLogStage(ctx, "Deferring HARQ diagnostics until DL/UL raw trials are available.");
harqArtifacts = struct("PacketTable", table(), "SummaryTable", table(), "TimelineTable", table(), "PreviewOnly", false);
[stageRows, stageOrder] = localAppendRuntimeStageProfile(rootRunFolder, stageRows, stageOrder, ...
    "harq_export_deferred", 0, toc(bundleStart), "HARQ diagnostics deferred until DL/UL raw trials are available.");
localPublishWaveformBundleStageStatus(runFolder, struct( ...
    "Stage", "pre_raw_sweep", ...
    "AnchorKPIsReady", istable(sixgr.util.structGet(res, "KPITable", table())), ...
    "DLTrialsReady", false, ...
    "ULTrialsReady", false, ...
    "ControlReady", false, ...
    "HARQReady", false, ...
    "BeamReady", false, ...
    "RFReady", false, ...
    "SweepReady", false, ...
    "FinalBundleReady", false, ...
    "Notes", "HARQ diagnostics are deferred until DL/UL raw trials are available."));
if istable(unsupportedCases) && ~isempty(unsupportedCases)
    localLogStage(ctx, "Pruned unsupported truth-only cases from KPI table: " + string(height(unsupportedCases)));
end
if receiverNoiseMode
    sweepPlan.MaxSweepPoints = 1;
    sweepPlan.ReferenceTrialsPerSNR = 0;
    snrGrid = localResolvePhysicalOperatingPointGrid(cfgExec, opt);
    localLogStage(ctx, "Exporting raw truth trial tables across SNR grid [" + ...
        strjoin(string(round(snrGrid(:).', 6)), ", ") + "] dB (receiver-noise operating-point label, not measured SINR).");
else
    snrGrid = localReduceSweepGrid( ...
        double(sixgr.util.structGet(opt, "LinkSNRGrid_dB", [-30 -20 -10 0 10 20 30 40])), ...
        double(sweepPlan.MaxSweepPoints), ...
        double(sixgr.util.structGet(opt, "LinkSNR_dB", 30)));
    localLogStage(ctx, "Exporting raw truth trial tables across SNR grid [" + ...
        strjoin(string(round(snrGrid(:).', 6)), ", ") + "].");
end
stageStart = tic;
trialExecutionCfg = sixgr.truth.selectWaveformBundleTrialConfig( ...
    cfgL, cfgExec, isCoupledTruth);
rawTrials = localExportLinkRawTrialTables(trialExecutionCfg, runFolder, res, sweepPlan.PrimaryTrialsPerSNR, snrGrid(:), multiUser, saveFigures, liveMobilityArtifacts, ...
    sixgr.util.structGet(opt,'SlotCheckpointLease',[]));
slotTrace = struct();
if isCoupledTruth
    slotTrace = sixgr.util.structGet(rawTrials, "CoupledRuntime", struct());
    if isstruct(slotTrace) && ~isempty(fieldnames(slotTrace))
        liveMobilityArtifacts = localBuildMobilityArtifactsFromCoupledRuntime(slotTrace);
    end
end
isacArtifacts = struct("Enabled",isacEnabled,"Executed",false, ...
    "EvidenceValid",~isacEnabled,"CSV",strings(0,1),"Images",strings(0,1), ...
    "Result",struct());
if isacEnabled
    sensing = sixgr.util.structGet(slotTrace,"ISAC",struct());
    if ~(isstruct(sensing) && logical(sixgr.util.structGet(sensing,"Executed",false)))
        error("sixgr:isac:MissingRuntimeEvidence", ...
            "ISAC was enabled, but no committed DL grant produced exact-waveform sensing evidence.");
    end
    if ~logical(sixgr.util.structGet(sensing,"EvidenceValid",false))
        error("sixgr:isac:AcceptanceFailed", ...
            "The measured ISAC result did not satisfy the YAML-owned target matching tolerances.");
    end
    imagePaths = sixgr.lls.exportISACArtifacts(rootRunFolder,cfgExec, ...
        struct("ISAC",sensing),logical(cfgExec.isac.output.savePNG), ...
        struct("StructuredComponentFolders",true));
    componentFolder = char(string(cfgExec.isac.output.componentFolder));
    csvListing = dir(fullfile(rootRunFolder,componentFolder,"csv","*.csv"));
    csvPaths = string(fullfile({csvListing.folder},{csvListing.name})).';
    isacArtifacts = struct("Enabled",true,"Executed",true, ...
        "EvidenceValid",true,"CSV",csvPaths,"Images",string(imagePaths(:)), ...
        "Result",sensing);
end
localPublishRuntimeReferenceArtifacts(runFolder, cfgL, multiUser, rawTrials);
% Live callbacks are cadence-controlled and may legitimately finish before
% the final directional tables are complete (for example, short coupled
% runs with different DL/UL completion counts).  Materialize the canonical
% signal-chain tables once more from the finalized primary trial evidence so
% a completed run cannot lose its channel-estimation/state exports merely
% because no later live-refresh milestone occurred.
finalSignalTrials = localAppendCompatTable( ...
    sixgr.util.structGet(rawTrials, "DL", table()), ...
    sixgr.util.structGet(rawTrials, "UL", table()));
finalConstellation = localAppendCompatTable( ...
    sixgr.util.structGet(rawTrials, "DLConstellation", table()), ...
    sixgr.util.structGet(rawTrials, "ULConstellation", table()));
finalWaveformPreview = sixgr.util.structGet(rawTrials, "WaveformPreviewTable", table());
if isCoupledTruth
    % Publish the samples retained by the execution path that actually ran.
    % Immediate per-grant PHY execution is not a shared continuous stream.
    % Both paths must retain their real preview; neither may rescue the other.
    finalWaveformPreview = sixgr.truth.finalCoupledWaveformPreview(slotTrace,finalSignalTrials);
end
sixgr.truth.exportLLSLiveSignalChainTables( ...
    rootRunFolder, finalSignalTrials, finalConstellation, struct( ...
        "WaveformPreviewTable", finalWaveformPreview, "FinalSnapshot", true));
[stageRows, stageOrder] = localAppendRuntimeStageProfile(rootRunFolder, stageRows, stageOrder, ...
    "raw_trials_export", toc(stageStart), toc(bundleStart), "Primary raw trial tables published.");
localPublishWaveformBundleStageStatus(runFolder, struct( ...
    "Stage", "raw_trials_exported", ...
    "AnchorKPIsReady", true, ...
    "DLTrialsReady", istable(sixgr.util.structGet(rawTrials, "DL", table())) && ~isempty(sixgr.util.structGet(rawTrials, "DL", table())), ...
    "ULTrialsReady", istable(sixgr.util.structGet(rawTrials, "UL", table())) && ~isempty(sixgr.util.structGet(rawTrials, "UL", table())), ...
    "ControlReady", localRawControlTablesReady(rawTrials), ...
    "HARQReady", false, ...
    "BeamReady", false, ...
    "RFReady", false, ...
    "SweepReady", false, ...
    "FinalBundleReady", false, ...
    "Notes", "Primary raw trial tables were written to the active artifact sink."));
profileStopReason = string(sixgr.util.structGet(slotTrace, "ProfileStopReason", ""));
if strlength(strtrim(profileStopReason)) > 0
    [stageRows, stageOrder] = localAppendRuntimeStageProfile(rootRunFolder, stageRows, stageOrder, ...
        "profile_debug_stop", 0, toc(bundleStart), ...
        "Profile debug stop requested before publication-grade derived exports: " + profileStopReason);
    localPublishWaveformBundleStageStatus(runFolder, struct( ...
        "Stage", "profile_debug_stopped", ...
        "AnchorKPIsReady", true, ...
        "DLTrialsReady", istable(sixgr.util.structGet(rawTrials, "DL", table())), ...
        "ULTrialsReady", istable(sixgr.util.structGet(rawTrials, "UL", table())), ...
        "ControlReady", localRawControlTablesReady(rawTrials), ...
        "HARQReady", false, ...
        "BeamReady", false, ...
        "RFReady", false, ...
        "SweepReady", false, ...
        "FinalBundleReady", false, ...
        "Notes", "Profile debug run stopped early before heavy derived/report exports: " + profileStopReason));
    out = struct();
    out.Ok = false;
    out.RunFolder = runFolder;
    out.Result = res;
    out.KPITable = sixgr.util.structGet(res, "KPITable", table());
    out.SNRSweep = table();
    out.MeasuredSINR = struct();
    out.ReferenceSweep = table();
    out.FixedLinkCampaign = localEmptyFixedLinkCampaignResult(false);
    out.RawTrials = rawTrials;
    out.Artifacts = struct();
    out.BeamformingArtifacts = struct();
    out.HARQArtifacts = struct();
    out.EnergyArtifacts = struct();
    out.TrialDiagnosticPlots = strings(0, 1);
    out.LiveMobilityArtifacts = liveMobilityArtifacts;
    out.LiveDerivedArtifacts = struct();
    out.RuntimeStageProfile = struct2table(stageRows);
    out.Integrity = struct("Ok", false, "ProfileStoppedEarly", true, "Reason", profileStopReason);
    out.Errors = "profile_debug_stop:" + profileStopReason;
    out.UnsupportedCases = unsupportedCases;
    out.MultiUser = multiUser;
    out.PersistenceEnabled = logical(persistenceEnabled);
    out.CoreOnly = ~logical(persistenceEnabled);
    out.ProfileStoppedEarly = true;
    out.ProfileStopReason = profileStopReason;
    localLogStage(ctx, "Profile debug run stopped early before heavy derived exports: " + profileStopReason);
    return;
end
localLogStage(ctx, "Publishing live derived channel, beam, CSI, and coverage tables from raw trials.");
stageStart = tic;
liveDerivedArtifacts = sixgr.truth.exportLLSLiveDerivedTables(cfgL, rootRunFolder, rawTrials, multiUser, liveMobilityArtifacts, slotTrace);
runtimeHARQArtifacts = sixgr.util.structGet(liveDerivedArtifacts, "RuntimeHARQ", struct());
if localArtifactStructReady(runtimeHARQArtifacts, "TimelineTable")
    harqArtifacts = runtimeHARQArtifacts;
end
[stageRows, stageOrder] = localAppendRuntimeStageProfile(rootRunFolder, stageRows, stageOrder, ...
    "live_derived_tables_initial", toc(stageStart), toc(bundleStart), "Initial live derived channel, beam, CSI, and coverage tables published.");
if receiverNoiseMode
    localLogStage(ctx, "Building primary receiver-noise operating-point summary from raw truth trials.");
else
    localLogStage(ctx, "Building primary SNR sweep from raw truth trials.");
end
stageStart = tic;
if receiverNoiseMode
    res.SNRSweep = table();
else
    res.SNRSweep = localBuildSNRSweepFromRawTrials(rawTrials, cfgExec, snrGrid(:));
end
[stageRows, stageOrder] = localAppendRuntimeStageProfile(rootRunFolder, stageRows, stageOrder, ...
    "primary_sweep_from_raw_trials", toc(stageStart), toc(bundleStart), "Primary operating-point summary constructed from raw trials.");
if receiverNoiseMode
    refinedGrid = [];
else
    refinedGrid = localBuildAdaptiveRefinedGrid(res.SNRSweep, snrGrid(:), cfgExec, opt);
end
if receiverNoiseMode
    [stageRows, stageOrder] = localAppendRuntimeStageProfile(rootRunFolder, stageRows, stageOrder, ...
        "refined_sweep_skipped_for_receiver_noise", 0, toc(bundleStart), ...
        "Receiver-noise mode uses measured runtime evidence at the configured operating point and skips adaptive configured-SNR sweeps.");
elseif isCoupledTruth
    [stageRows, stageOrder] = localAppendRuntimeStageProfile(rootRunFolder, stageRows, stageOrder, ...
        "refined_sweep_skipped_for_coupled_truth", 0, toc(bundleStart), ...
        "Coupled truth uses the canonical slot runtime as the authoritative source and skips legacy refined sweeps.");
elseif ~isempty(refinedGrid)
    localLogStage(ctx, "Refining truth SNR sweep near the observed waterfall at [" + ...
        strjoin(string(round(refinedGrid(:).', 6)), ", ") + "].");
    stageStart = tic;
    rawTrials = localAugmentRawTrialsWithRefinedSweep(cfgExec, runFolder, rawTrials, sweepPlan.PrimaryTrialsPerSNR, refinedGrid(:), multiUser);
    sixgr.truth.exportLLSLiveSignalChainTables(rootRunFolder, ...
        localAppendCompatTable(rawTrials.DL, rawTrials.UL), ...
        localAppendCompatTable(rawTrials.DLConstellation, rawTrials.ULConstellation), ...
        struct("WaveformPreviewTable", rawTrials.WaveformPreviewTable, "FinalSnapshot", true));
    [stageRows, stageOrder] = localAppendRuntimeStageProfile(rootRunFolder, stageRows, stageOrder, ...
        "refined_sweep", toc(stageStart), toc(bundleStart), "Adaptive refined raw trials were added near the waterfall.");
    snrGrid = unique(sort([double(snrGrid(:)); double(refinedGrid(:))]));
    res.SNRSweep = localBuildSNRSweepFromRawTrials(rawTrials, cfgExec, snrGrid(:));
end
res.FixedLinkCampaign = localEmptyFixedLinkCampaignResult(false);
if logical(sweepPlan.FixedLinkCampaignEnabled)
    fixedLinkGrid = localResolveFixedLinkCampaignGrid(snrGrid(:), sweepPlan);
    localLogStage(ctx, "Running fixed-reference SNR sweep with fixed-link Monte Carlo engine.");
    stageStart = tic;
    res.FixedLinkCampaign = localRunFixedLinkCampaign(cfgExec, fixedLinkGrid(:), sweepPlan, multiUser);
    res.ReferenceSweep = sixgr.util.structGet(res.FixedLinkCampaign, "Summary", table());
    if istable(res.ReferenceSweep) && ~isempty(res.ReferenceSweep)
        res.SNRSweep = res.ReferenceSweep;
    end
    [stageRows, stageOrder] = localAppendRuntimeStageProfile(rootRunFolder, stageRows, stageOrder, ...
        "fixed_link_monte_carlo_campaign", toc(stageStart), toc(bundleStart), ...
        "Fixed-reference multi-point Monte Carlo SNR campaign completed.");
elseif receiverNoiseMode
    res.ReferenceSweep = table();
    [stageRows, stageOrder] = localAppendRuntimeStageProfile(rootRunFolder, stageRows, stageOrder, ...
        "reference_sweep_skipped_for_receiver_noise", 0, toc(bundleStart), ...
        "Receiver-noise mode skipped the optional fixed-link calibration campaign; runtime receiver evidence remains authoritative.");
    if isCoupledTruth
        [stageRows, stageOrder] = localAppendRuntimeStageProfile(rootRunFolder, stageRows, stageOrder, ...
            "reference_sweep_skipped_for_coupled_truth", 0, toc(bundleStart), ...
            "Coupled truth also skipped the optional fixed-link campaign and uses canonical slot-trace summaries only.");
    end
elseif isCoupledTruth
    res.ReferenceSweep = table();
    [stageRows, stageOrder] = localAppendRuntimeStageProfile(rootRunFolder, stageRows, stageOrder, ...
        "reference_sweep_skipped_for_coupled_truth", 0, toc(bundleStart), ...
        "Coupled truth skipped the optional fixed-link campaign and uses canonical slot-trace summaries only.");
else
    res.ReferenceSweep = table();
    [stageRows, stageOrder] = localAppendRuntimeStageProfile(rootRunFolder, stageRows, stageOrder, ...
        "reference_sweep_disabled", 0, toc(bundleStart), ...
        "Fixed-link campaign disabled by configuration.");
end
localLogStage(ctx, "Applying primary sweep results to the authoritative KPI table.");
stageStart = tic;
res = localApplyPrimarySweepResults(res, rawTrials, cfgExec, snrGrid(:), isCoupledTruth);
res.PAPRCCDF = localBuildPAPRCCDFTable(rawTrials);
[stageRows, stageOrder] = localAppendRuntimeStageProfile(rootRunFolder, stageRows, stageOrder, ...
    "primary_sweep_apply", toc(stageStart), toc(bundleStart), "Primary sweep results were applied to the authoritative KPI table.");
localPublishWaveformBundleStageStatus(runFolder, struct( ...
    "Stage", "primary_sweep_ready", ...
    "AnchorKPIsReady", true, ...
    "DLTrialsReady", true, ...
    "ULTrialsReady", true, ...
    "ControlReady", localRawControlTablesReady(rawTrials), ...
    "HARQReady", false, ...
    "BeamReady", false, ...
    "RFReady", false, ...
    "SweepReady", true, ...
    "FinalBundleReady", false, ...
    "Notes", "Primary operating-point summary is available for live charts."));
localLogStage(ctx, "Refreshing live derived tables after primary sweep consolidation.");
stageStart = tic;
liveDerivedArtifacts = sixgr.truth.exportLLSLiveDerivedTables(cfgL, rootRunFolder, rawTrials, multiUser, liveMobilityArtifacts, slotTrace);
runtimeHARQArtifacts = sixgr.util.structGet(liveDerivedArtifacts, "RuntimeHARQ", struct());
if localArtifactStructReady(runtimeHARQArtifacts, "TimelineTable")
    harqArtifacts = runtimeHARQArtifacts;
end
[stageRows, stageOrder] = localAppendRuntimeStageProfile(rootRunFolder, stageRows, stageOrder, ...
    "live_derived_tables_refresh", toc(stageStart), toc(bundleStart), "Live derived tables refreshed after sweep consolidation.");
if logical(multiUser.Enabled)
    res.MultiUserMode = string(multiUser.ExecutionModel);
    res.MultiUserEnabled = logical(multiUser.Enabled);
    res.MultiUserCount = double(multiUser.NumUsers);
end
localLogStage(ctx, "Writing optional legacy sweep CSV artifacts when enabled.");
stageStart = tic;
if istable(res.SNRSweep) && ~isempty(res.SNRSweep)
    % Undefined measurements at a zero-trial operating point are NaN, not
    % unwired fields. Keep the same declared schema across the whole sweep.
    sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "lls_snr_sweep.csv"), res.SNRSweep, "PreserveSchema", true);
end
if istable(res.ReferenceSweep) && ~isempty(res.ReferenceSweep)
    sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "lls_reference_snr_sweep.csv"), res.ReferenceSweep, "PreserveSchema", true);
end
fixedLinkSummary = sixgr.util.structGet(sixgr.util.structGet(res, "FixedLinkCampaign", struct()), "Summary", table());
if istable(fixedLinkSummary) && ~isempty(fixedLinkSummary)
    sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "lls_fixed_link_campaign.csv"), fixedLinkSummary, "PreserveSchema", true);
end
if logical(persistenceEnabled)
    localWriteFixedLinkCampaignEvidence(runFolder, sixgr.util.structGet(res, "FixedLinkCampaign", struct()));
end
if logical(sixgr.util.structGet(sixgr.util.structGet(res, "FixedLinkCampaign", struct()), "Enabled", false))
    sixgr.analytics.exportFixedSNRSweepCurves(rootRunFolder, ...
        sixgr.util.structGet(res, "FixedLinkCampaign", struct()), cfgExec, ...
        struct("WriteArtifacts", logical(persistenceEnabled)));
    % Production rasters are generated once, after final CSV bytes are
    % stable, by scripts/materialize_lls_contract_artifacts.py.  Do not
    % create an earlier MATLAB PNG/lineage authority here.
end
[stageRows, stageOrder] = localAppendRuntimeStageProfile(rootRunFolder, stageRows, stageOrder, ...
    "sweep_csv_export", toc(stageStart), toc(bundleStart), "Controlled sweep CSV artifact export completed when fixed-link or raw sweep evidence was available.");
legacyHARQReady = localLegacyHARQArtifactsReady(rootRunFolder);
runtimeHARQReady = localArtifactStructReady(harqArtifacts, "TimelineTable");
harqDiagnosticsEnabled = logical(sixgr.util.structGet(opt, "HARQDiagnosticsEnabled", false));
harqExportMode = sixgr.truth.resolveWaveformBundleHARQExportMode( ...
    isCoupledTruth, runtimeHARQReady, harqDiagnosticsEnabled, ...
    localArtifactStructReady(harqArtifacts, "SummaryTable"), ...
    logical(sixgr.util.structGet(harqArtifacts, "PreviewOnly", false)), ...
    legacyHARQReady);
if harqExportMode == "runtime_observation_reuse"
    localLogStage(ctx, "Publishing HARQ diagnostics from the canonical slot-runtime timeline.");
    stageStart = tic;
    harqArtifacts = sixgr.truth.publishRuntimeHARQDiagnostics(cfgExec, runFolder, harqArtifacts);
    [stageRows, stageOrder] = localAppendRuntimeStageProfile(rootRunFolder, stageRows, stageOrder, ...
        "harq_export_runtime_observation_reuse", toc(stageStart), toc(bundleStart), ...
        "Canonical slot-runtime HARQ observations were adapted to the legacy diagnostic schemas without replaying the PHY.");
elseif harqExportMode == "unavailable_no_canonical_observation"
    localLogStage(ctx, ["Canonical coupled runtime produced no HARQ observations; " ...
        "standalone HARQ replay is forbidden for this run scope."]);
    [stageRows, stageOrder] = localAppendRuntimeStageProfile(rootRunFolder, stageRows, stageOrder, ...
        "harq_export_unavailable_no_canonical_observation", 0, toc(bundleStart), ...
        "No canonical slot-runtime HARQ observations were available. A standalone PHY campaign was not substituted for coupled-run evidence.");
elseif harqExportMode == "disabled_no_runtime_observation"
    [stageRows, stageOrder] = localAppendRuntimeStageProfile(rootRunFolder, stageRows, stageOrder, ...
        "harq_export_disabled_no_runtime_observation", 0, toc(bundleStart), ...
        "Optional standalone HARQ probe disabled by runtime tuning and no runtime HARQ observation table was available.");
elseif harqExportMode == "standalone_export"
    localLogStage(ctx, "Exporting HARQ diagnostics.");
    stageStart = tic;
    harqArtifacts = sixgr.truth.exportLLSHARQDiagnostics(cfgExec, runFolder, opt);
    [stageRows, stageOrder] = localAppendRuntimeStageProfile(rootRunFolder, stageRows, stageOrder, ...
        "harq_export", toc(stageStart), toc(bundleStart), "HARQ diagnostics exported.");
else
    [stageRows, stageOrder] = localAppendRuntimeStageProfile(rootRunFolder, stageRows, stageOrder, ...
        "harq_export_reuse", 0, toc(bundleStart), "HARQ diagnostics were already available.");
end
harqReady = localArtifactStructReady(harqArtifacts, "SummaryTable");
if harqReady
    harqStageNotes = "Canonical-scope HARQ diagnostics were exported.";
elseif isCoupledTruth
    harqStageNotes = "Canonical coupled runtime produced no HARQ observations; no standalone evidence was substituted.";
else
    harqStageNotes = "HARQ diagnostics were unavailable for this run.";
end
localPublishWaveformBundleStageStatus(runFolder, struct( ...
    "Stage", "harq_ready", ...
    "AnchorKPIsReady", true, ...
    "DLTrialsReady", true, ...
    "ULTrialsReady", true, ...
    "ControlReady", localRawControlTablesReady(rawTrials), ...
    "HARQReady", harqReady, ...
    "BeamReady", false, ...
    "RFReady", false, ...
    "SweepReady", true, ...
    "FinalBundleReady", false, ...
    "Notes", harqStageNotes));
localLogStage(ctx, "Exporting beamforming diagnostics.");
stageStart = tic;
beamArtifacts = localExportBeamformingDiagnostics(cfgExec, runFolder, rawTrials, saveFigures);
[stageRows, stageOrder] = localAppendRuntimeStageProfile(rootRunFolder, stageRows, stageOrder, ...
    "beam_export", toc(stageStart), toc(bundleStart), "Beamforming diagnostics exported.");
localPublishWaveformBundleStageStatus(runFolder, struct( ...
    "Stage", "beam_ready", ...
    "AnchorKPIsReady", true, ...
    "DLTrialsReady", true, ...
    "ULTrialsReady", true, ...
    "ControlReady", localRawControlTablesReady(rawTrials), ...
    "HARQReady", localArtifactStructReady(harqArtifacts, "SummaryTable"), ...
    "BeamReady", localArtifactStructReady(beamArtifacts, "SummaryTable"), ...
    "RFReady", false, ...
    "SweepReady", true, ...
    "FinalBundleReady", false, ...
    "Notes", "Beam diagnostics were exported."));
localLogStage(ctx, "Exporting RF and energy diagnostics.");
stageStart = tic;
energyArtifacts = sixgr.truth.exportLLSEnergyDiagnostics(cfgExec, runFolder, rawTrials);
iqImbalanceArtifacts = sixgr.truth.exportLLSRFImpairmentDiagnostics(cfgExec, runFolder, rawTrials);
[stageRows, stageOrder] = localAppendRuntimeStageProfile(rootRunFolder, stageRows, stageOrder, ...
    "rf_energy_export", toc(stageStart), toc(bundleStart), "RF, IQ-imbalance, and energy diagnostics exported.");
localPublishWaveformBundleStageStatus(runFolder, struct( ...
    "Stage", "rf_ready", ...
    "AnchorKPIsReady", true, ...
    "DLTrialsReady", true, ...
    "ULTrialsReady", true, ...
    "ControlReady", localRawControlTablesReady(rawTrials), ...
    "HARQReady", localArtifactStructReady(harqArtifacts, "SummaryTable"), ...
    "BeamReady", localArtifactStructReady(beamArtifacts, "SummaryTable"), ...
    "RFReady", localRFArtifactsReady(struct("Energy", energyArtifacts, "IQImpairment", iqImbalanceArtifacts)), ...
    "SweepReady", true, ...
    "FinalBundleReady", false, ...
    "Notes", "RF, IQ-imbalance, and energy diagnostics were exported."));
localLogStage(ctx, "Exporting trial diagnostic plots.");
stageStart = tic;
trialPlots = localExportTrialDiagnosticPlots(runFolder, rawTrials, saveFigures);
phySignalArtifacts = struct( ...
    "SourceCSV", "", ...
    "SourceTable", table(), ...
    "DLImage", "", ...
    "ULImage", "", ...
    "DLAvailable", false, ...
    "ULAvailable", false, ...
    "DLReason", string(sixgr.util.structGet(cfgExec, ...
    "outputs.phySignalDiagnosticUnavailableReason", "capture_disabled_by_config")), ...
    "ULReason", string(sixgr.util.structGet(cfgExec, ...
    "outputs.phySignalDiagnosticUnavailableReason", "capture_disabled_by_config")));
diagnosticExportError = "";
if diagnosticEnabled
    try
        phySignalArtifacts = sixgr.truth.exportPHYSignalDiagnostic( ...
            rootRunFolder, cfgExec, rawTrials, saveFigures);
    catch ME
        phySignalArtifacts.DLReason = "export_failed:" + string(ME.identifier);
        phySignalArtifacts.ULReason = "export_failed:" + string(ME.identifier);
        diagnosticExportError = "phy_signal_diagnostic_export_failed:" + ...
            string(ME.identifier) + ":" + string(ME.message);
        localLogStage(ctx, "PHY signal diagnostic export failed: " + ...
            string(ME.identifier) + " " + string(ME.message));
    end
end
[stageRows, stageOrder] = localAppendRuntimeStageProfile(rootRunFolder, stageRows, stageOrder, ...
    "trial_plot_export", toc(stageStart), toc(bundleStart), ...
    "Trial plots and same-trial PHY signal diagnostics exported when real evidence was available.");

localLogStage(ctx, "Checking primary-link export integrity.");
stageStart = tic;
[kpi, integrity] = sixgr.link.enforcePrimaryLinkExportIntegrity(cfgExec, sixgr.util.structGet(res, "KPITable", table()), rawTrials);
res.KPITable = kpi;
res.RawTrials = rawTrials;
res.Config = cfgExec;
[stageRows, stageOrder] = localAppendRuntimeStageProfile(rootRunFolder, stageRows, stageOrder, ...
    "integrity_check", toc(stageStart), toc(bundleStart), "Primary-link export integrity check completed.");
localLogStage(ctx, "Exporting structured link KPI bundle and report inputs.");
stageStart = tic;
arts = sixgr.link.exportLinkKPIs(runFolder, kpi, res, ...
    "SaveCSV", true, ...
    "SaveMAT", true, ...
    "SaveFigures", logical(sixgr.util.structGet(opt, "SaveFigures", true)), ...
    "SavePNG", true, ...
    "FigurePrefix", "link_truth_validation", ...
    "PlotVisible", false, ...
    "FigureResolution", 140);
arts.PHYSignalDiagnostic = phySignalArtifacts;
measuredSINRArtifacts = struct();
try
    measuredSINRArtifacts.Curves = sixgr.analytics.generateMeasuredSINRCurves(rootRunFolder, ...
        string(sixgr.util.structGet(cfgExec, "run.runTag", "")), ...
        "TrialData", rawTrials, ...
        "ScenarioConfig", cfgExec, ...
        "WriteKPISummary", true, ...
        "UpdateAnchorKPIs", true);
    if saveFigures
        measuredSINRArtifacts.Plots = sixgr.analytics.generateMeasuredSINRPlots(rootRunFolder, ...
            string(sixgr.util.structGet(cfgExec, "run.runTag", "")));
    else
        measuredSINRArtifacts.Plots = localSuppressedLegacyRasterResult(rootRunFolder);
    end
    if isstruct(arts) && isfield(arts, "csv")
        curvePaths = struct2cell(measuredSINRArtifacts.Curves.Paths);
        for ai = 1:numel(curvePaths)
            arts.csv{end+1} = char(string(curvePaths{ai})); %#ok<AGROW>
        end
    end
    if isstruct(arts) && isfield(arts, "fig")
        plotPaths = string(measuredSINRArtifacts.Plots.Plots(:));
        for ai = 1:numel(plotPaths)
            arts.fig{end+1} = char(plotPaths(ai)); %#ok<AGROW>
        end
    end
catch ME
    measuredSINRArtifacts = struct("Ok", false, "Identifier", string(ME.identifier), "Message", string(ME.message));
end
[stageRows, stageOrder] = localAppendRuntimeStageProfile(rootRunFolder, stageRows, stageOrder, ...
    "final_kpi_bundle_export", toc(stageStart), toc(bundleStart), "Final structured KPI bundle exported.");
localPublishWaveformBundleStageStatus(runFolder, struct( ...
    "Stage", "final_bundle_ready", ...
    "AnchorKPIsReady", true, ...
    "DLTrialsReady", true, ...
    "ULTrialsReady", true, ...
    "ControlReady", localRawControlTablesReady(rawTrials), ...
    "HARQReady", localArtifactStructReady(harqArtifacts, "SummaryTable"), ...
    "BeamReady", localArtifactStructReady(beamArtifacts, "SummaryTable"), ...
    "RFReady", localRFArtifactsReady(struct("Energy", energyArtifacts, "IQImpairment", iqImbalanceArtifacts)), ...
    "SweepReady", true, ...
    "FinalBundleReady", true, ...
    "PBCHAttemptCount", localControlTrialHeight(rawTrials, "PBCH"), ...
    "PRACHAttemptCount", localControlTrialHeight(rawTrials, "PRACH"), ...
    "SRSAttemptCount", localControlTrialHeight(rawTrials, "SRS"), ...
    "TRSAttemptCount", localControlTrialHeight(rawTrials, "TRS"), ...
    "Notes", "Final structured KPI bundle export completed."));
[stageRows, stageOrder] = localAppendRuntimeStageProfile(rootRunFolder, stageRows, stageOrder, ...
    "bundle_complete", 0, toc(bundleStart), "Strict waveform LLS bundle completed.");

campaignEvidenceOk = true;
if logical(sweepPlan.FixedLinkCampaignEnabled)
    campaignEvidenceOk = localFixedLinkCampaignEvidenceOk(sixgr.util.structGet(res, "FixedLinkCampaign", struct()));
end

out = struct();
out.Ok = logical(localLinkKPITableHealthy(kpi)) && logical(campaignEvidenceOk);
out.RunFolder = runFolder;
out.Result = res;
out.KPITable = kpi;
out.SNRSweep = res.SNRSweep;
out.MeasuredSINR = measuredSINRArtifacts;
out.ReferenceSweep = sixgr.util.structGet(res, "ReferenceSweep", table());
out.FixedLinkCampaign = sixgr.util.structGet(res, "FixedLinkCampaign", localEmptyFixedLinkCampaignResult(false));
out.RawTrials = rawTrials;
out.Artifacts = arts;
out.BeamformingArtifacts = beamArtifacts;
out.HARQArtifacts = harqArtifacts;
out.EnergyArtifacts = energyArtifacts;
out.TrialDiagnosticPlots = trialPlots;
out.PHYSignalDiagnosticArtifacts = phySignalArtifacts;
out.LiveMobilityArtifacts = liveMobilityArtifacts;
out.LiveDerivedArtifacts = liveDerivedArtifacts;
out.RuntimeStageProfile = struct2table(stageRows);
out.Integrity = integrity;
out.Errors = sixgr.util.structGet(res, "Errors", strings(0,1));
if strlength(strtrim(diagnosticExportError)) > 0
    out.Errors = [string(out.Errors(:)); diagnosticExportError];
    out.Ok = false;
end
if logical(sweepPlan.FixedLinkCampaignEnabled) && ~logical(campaignEvidenceOk)
    out.Errors = [string(out.Errors(:)); "fixed_link_campaign_missing_nonempty_curve_with_confidence_intervals"];
end
out.UnsupportedCases = unsupportedCases;
out.MultiUser = multiUser;
out.PersistenceEnabled = logical(persistenceEnabled);
out.CoreOnly = ~logical(persistenceEnabled);
localLogStage(ctx, "Strict waveform LLS bundle completed.");
end

function out = localResumeCompletedRuntimeFinalization(cfg, runFolder, opt, ...
        multiUser, sweepPlan, saveFigures, diagnosticEnabled, ctx, ...
        bundleStart, stageRows, stageOrder)
% Resume only derived exports after an independently verified terminal PHY.

rootRunFolder = fileparts(char(string(runFolder)));
snrGrid = unique(sort(double(sixgr.util.structGet(opt, ...
    "LinkSNRGrid_dB", sixgr.util.structGet(opt, "LinkSNR_dB", NaN)))));
snrGrid = snrGrid(isfinite(snrGrid));
direction = lower(strtrim(string(sixgr.util.structGet(cfg, ...
    "run.linkDirection", sixgr.util.structGet(cfg, ...
    "simulation.link_direction", "both")))));
requireDL = any(direction == ["", "all", "both", "dl", "downlink"]);
requireUL = any(direction == ["", "all", "both", "ul", "uplink"]);
expectedSlots = round(double(sixgr.util.structGet(opt, "LinkMaxSimFrames", NaN)));
if logical(multiUser.Enabled) && ...
        string(multiUser.ExecutionModel) == "slot_coupled_truth"
    % LinkMaxSimFrames is the per-operating-point slot budget.  The
    % coupled runtime persists one terminal counter across the full sweep.
    expectedSlots = expectedSlots * max(1, numel(snrGrid));
end
checkpoint = sixgr.truth.assertCompletedWaveformRuntimeCheckpoint( ...
    rootRunFolder, "ExpectedTotalSlots", expectedSlots, ...
    "ExpectedSweepPointCount", numel(snrGrid), ...
    "RequireDL", requireDL, "RequireUL", requireUL, ...
    "ReconcileFinalizedControlCounters", true);
localLogStage(ctx, "Resuming derived finalization from verified terminal waveform runtime checkpoint.");

layout = sixgr.report.resultLayout(rootRunFolder);
rawTrials = struct();
rawTrials.DL = localReadPersistedCSV(fullfile(layout.AirInterfaceCSVDir, "dl_pdsch_trials.csv"));
rawTrials.UL = localReadPersistedCSV(fullfile(layout.AirInterfaceCSVDir, "ul_pusch_trials.csv"));
rawTrials.DL = sixgr.truth.canonicalizeConfiguredPhysicalAntennaMetadata( ...
    rawTrials.DL, cfg, "DL");
rawTrials.UL = sixgr.truth.canonicalizeConfiguredPhysicalAntennaMetadata( ...
    rawTrials.UL, cfg, "UL");
rawTrials.UL = sixgr.truth.canonicalizeRecoveredPUSCHUCIEvidence(rawTrials.UL);
% These fields are exact aliases of values already persisted by the
% completed waveform runtime.  Older checkpoints predate the explicit
% configured/effective and air-observation columns, so bind them here
% before any derived report is rebuilt.  Conflicting populated values fail
% closed; recovery never substitutes configured values for runtime values.
rawTrials.DL = localCanonicalizeRecoveredPrimaryLinkEvidence(rawTrials.DL, "DL");
rawTrials.UL = localCanonicalizeRecoveredPrimaryLinkEvidence(rawTrials.UL, "UL");
rawTrials.DL = sixgr.link.applyMeasuredDLMUMIMOReceiverEvidence(rawTrials.DL);
[dlConstellationPath,ulConstellationPath] = ...
    sixgr.truth.constellationArtifactPaths(cfg,layout.AirInterfaceCSVDir);
rawTrials.DLConstellation = localReadPersistedCSV(dlConstellationPath);
rawTrials.ULConstellation = localReadPersistedCSV(ulConstellationPath);
rawTrials.DLConstellationPath = "";
rawTrials.ULConstellationPath = "";
if isfile(dlConstellationPath), rawTrials.DLConstellationPath=string(dlConstellationPath); end
if isfile(ulConstellationPath), rawTrials.ULConstellationPath=string(ulConstellationPath); end
rawTrials.PBCH = localReadPersistedCSV(fullfile(layout.AirInterfaceCSVDir, "pbch_trials.csv"));
rawTrials.PRACH = localReadPersistedCSV(fullfile(layout.AirInterfaceCSVDir, "prach_trials.csv"));
rawTrials.PDCCH = localReadPersistedCSV(fullfile(layout.AirInterfaceCSVDir, "pdcch_trials.csv"));
rawTrials.PUCCH = localReadPersistedCSV(fullfile(layout.AirInterfaceCSVDir, "pucch_trials.csv"));
rawTrials.SRS = localReadPersistedCSV(fullfile(layout.AirInterfaceCSVDir, "srs_trials.csv"));
rawTrials.CSIRS = localReadPersistedCSV(fullfile(layout.AirInterfaceCSVDir, "csi_rs_trials.csv"));
rawTrials.TRS = localReadPersistedCSV(fullfile(layout.AirInterfaceCSVDir, "trs_trials.csv"));
rawTrials.InitialAccessLifecycleTraceTable = localReadPersistedCSV( ...
    fullfile(layout.ReportCSVDir, "initial_access_lifecycle_trace.csv"));
rawTrials.ControlGatingSummaryTable = localReadPersistedCSV( ...
    fullfile(layout.ReportCSVDir, "live_control_gating_summary.csv"));
rawTrials.ControlGatingStateTable = localReadPersistedCSV( ...
    fullfile(layout.ReportCSVDir, "live_control_gating_state.csv"));

% A resumable finalization consumes persisted canonical projections. Bind
% any legacy blank identity columns from the already verified checkpoint
% and exact current configuration before strict reduction. Contradictory
% populated identities still fail closed in localBindIdentityColumn.
identityFields = ["DL","UL","DLConstellation","ULConstellation", ...
    "PBCH","PRACH","PDCCH","PUCCH","SRS","CSIRS","TRS"];
for identityField = identityFields
    rawTrials.(char(identityField)) = localBindCoupledRuntimeIdentity( ...
        rawTrials.(char(identityField)), cfg, identityField);
end
sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir, ...
    "dl_pdsch_trials.csv"), rawTrials.DL, "PreserveSchema", true);
sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir, ...
    "ul_pusch_trials.csv"), rawTrials.UL, "PreserveSchema", true);
resumeControlFiles = struct( ...
    "PBCH", "pbch_trials.csv", ...
    "PRACH", "prach_trials.csv", ...
    "PDCCH", "pdcch_trials.csv", ...
    "PUCCH", "pucch_trials.csv", ...
    "SRS", "srs_trials.csv", ...
    "CSIRS", "csi_rs_trials.csv", ...
    "TRS", "trs_trials.csv");
for identityField = identityFields(5:end)
    fieldName = char(identityField);
    controlT = rawTrials.(fieldName);
    if ~(istable(controlT) && ~isempty(controlT))
        continue;
    end
    sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir, ...
        char(resumeControlFiles.(fieldName))), controlT, ...
        "PreserveSchema", true,"RoundTripNumericText",identityField=="SRS");
end

res = struct();
res.KPITable = table();
res.SNRSweep = localReadPersistedCSV(fullfile(layout.AirInterfaceCSVDir, "lls_snr_sweep.csv"));
res.ReferenceSweep = localReadPersistedCSV(fullfile(layout.AirInterfaceCSVDir, "lls_reference_snr_sweep.csv"));
res.FixedLinkCampaign = localEmptyFixedLinkCampaignResult(false);
res = localApplyPrimarySweepResults(res, rawTrials, cfg, snrGrid(:), true);
res.PAPRCCDF = localBuildPAPRCCDFTable(rawTrials);
res.RawTrials = rawTrials;
res.Config = cfg;
res.CompletedRuntimeCheckpoint = checkpoint;
res.MultiUserMode = string(multiUser.ExecutionModel);
res.MultiUserEnabled = logical(multiUser.Enabled);
res.MultiUserCount = double(multiUser.NumUsers);
res.Errors = strings(0, 1);

isacEnabled = logical(sixgr.util.structGet(cfg,"isac.enabled",false));
isacArtifacts = struct("Enabled",isacEnabled,"Executed",false, ...
    "EvidenceValid",~isacEnabled,"CSV",strings(0,1), ...
    "Images",strings(0,1),"Result",struct());
if isacEnabled
    % Exact sensing state contains arrays that are not reconstructible from
    % communication trial CSVs.  Never invent or relabel it on recovery.
    error("sixgr:isac:ResumeRequiresPersistedRuntimeState", ...
        ["An ISAC-enabled completed-runtime recovery requires a persisted " ...
         "exact sensing-state checkpoint; communication CSVs alone are insufficient."]);
end

[stageRows, stageOrder] = localAppendRuntimeStageProfile(rootRunFolder, ...
    stageRows, stageOrder, "completed_runtime_checkpoint_verified", ...
    0, toc(bundleStart), ...
    "Terminal slot/sweep counters and canonical persisted row counts matched exactly.");

harqArtifacts = struct( ...
    "PacketTable", localReadPersistedCSV(fullfile(layout.HARQCSVDir, "probe_harq_packets.csv")), ...
    "SummaryTable", localReadPersistedCSV(fullfile(layout.HARQCSVDir, "probe_harq_summary.csv")), ...
    "TimelineTable", localReadPersistedCSV(fullfile(layout.HARQCSVDir, "harq_process_timeline.csv")), ...
    "PreviewOnly", false, ...
    "EvidenceSource", "persisted_canonical_slot_runtime");

stageStart = tic;
beamArtifacts = localExportBeamformingDiagnostics(cfg, runFolder, rawTrials, saveFigures);
[stageRows, stageOrder] = localAppendRuntimeStageProfile(rootRunFolder, ...
    stageRows, stageOrder, "beam_export_resumed", toc(stageStart), ...
    toc(bundleStart), "Beam diagnostics resumed from canonical raw DL/UL trial rows.");
localPublishWaveformBundleStageStatus(runFolder, struct( ...
    "Stage", "beam_ready", "AnchorKPIsReady", true, ...
    "DLTrialsReady", requireDL, "ULTrialsReady", requireUL, ...
    "ControlReady", localRawControlTablesReady(rawTrials), ...
    "HARQReady", localArtifactStructReady(harqArtifacts, "SummaryTable"), ...
    "BeamReady", localArtifactStructReady(beamArtifacts, "SummaryTable"), ...
    "RFReady", false, "SweepReady", true, "FinalBundleReady", false, ...
    "Notes", "Resumed beam diagnostics completed from persisted terminal runtime evidence."));

stageStart = tic;
energyArtifacts = sixgr.truth.exportLLSEnergyDiagnostics(cfg, runFolder, rawTrials);
iqImbalanceArtifacts = sixgr.truth.exportLLSRFImpairmentDiagnostics(cfg, runFolder, rawTrials);
[stageRows, stageOrder] = localAppendRuntimeStageProfile(rootRunFolder, ...
    stageRows, stageOrder, "rf_energy_export_resumed", toc(stageStart), ...
    toc(bundleStart), "RF, IQ-imbalance, and energy diagnostics resumed from canonical trials.");

stageStart = tic;
trialPlots = localExportTrialDiagnosticPlots(runFolder, rawTrials, saveFigures);
phySignalArtifacts = struct( ...
    "SourceCSV", "", "SourceTable", table(), "DLImage", "", "ULImage", "", ...
    "DLAvailable", false, "ULAvailable", false, ...
    "DLReason", "runtime_capture_not_persisted_for_resumable_finalization", ...
    "ULReason", "runtime_capture_not_persisted_for_resumable_finalization");
diagnosticExportError = "";
if diagnosticEnabled
    try
        phySignalArtifacts = sixgr.truth.exportPHYSignalDiagnostic( ...
            rootRunFolder, cfg, rawTrials, saveFigures);
    catch ME
        diagnosticExportError = "phy_signal_diagnostic_export_failed:" + ...
            string(ME.identifier) + ":" + string(ME.message);
    end
end
[stageRows, stageOrder] = localAppendRuntimeStageProfile(rootRunFolder, ...
    stageRows, stageOrder, "trial_plot_export_resumed", toc(stageStart), ...
    toc(bundleStart), "Trial plots resumed from persisted canonical runtime rows.");

[kpi, integrity] = sixgr.link.enforcePrimaryLinkExportIntegrity(cfg, ...
    sixgr.util.structGet(res, "KPITable", table()), rawTrials);
res.KPITable = kpi;
arts = sixgr.link.exportLinkKPIs(runFolder, kpi, res, ...
    "SaveCSV", true, "SaveMAT", true, "SaveFigures", saveFigures, ...
    "SavePNG", true, "FigurePrefix", "link_truth_validation", ...
    "PlotVisible", false, "FigureResolution", 140);
arts.PHYSignalDiagnostic = phySignalArtifacts;
arts.ISAC = isacArtifacts;

measuredSINRArtifacts = struct();
try
    measuredSINRArtifacts.Curves = sixgr.analytics.generateMeasuredSINRCurves( ...
        rootRunFolder, string(sixgr.util.structGet(cfg, "run.runTag", "")), ...
        "TrialData", rawTrials, "ScenarioConfig", cfg, ...
        "WriteKPISummary", true, "UpdateAnchorKPIs", true);
    if saveFigures
        measuredSINRArtifacts.Plots = sixgr.analytics.generateMeasuredSINRPlots( ...
            rootRunFolder, string(sixgr.util.structGet(cfg, "run.runTag", "")));
    else
        measuredSINRArtifacts.Plots = localSuppressedLegacyRasterResult(rootRunFolder);
    end
catch ME
    measuredSINRArtifacts = struct("Ok", false, ...
        "Identifier", string(ME.identifier), "Message", string(ME.message));
end

localPublishWaveformBundleStageStatus(runFolder, struct( ...
    "Stage", "final_bundle_ready", "AnchorKPIsReady", true, ...
    "DLTrialsReady", requireDL, "ULTrialsReady", requireUL, ...
    "ControlReady", localRawControlTablesReady(rawTrials), ...
    "HARQReady", localArtifactStructReady(harqArtifacts, "SummaryTable"), ...
    "BeamReady", localArtifactStructReady(beamArtifacts, "SummaryTable"), ...
    "RFReady", localRFArtifactsReady(struct("Energy", energyArtifacts, ...
        "IQImpairment", iqImbalanceArtifacts)), ...
    "SweepReady", true, "FinalBundleReady", true, ...
    "PBCHAttemptCount", height(rawTrials.PBCH), ...
    "PRACHAttemptCount", height(rawTrials.PRACH), ...
    "SRSAttemptCount", height(rawTrials.SRS), ...
    "TRSAttemptCount", height(rawTrials.TRS), ...
    "Notes", "Resumable finalization completed from a verified terminal waveform runtime checkpoint."));
[stageRows, stageOrder] = localAppendRuntimeStageProfile(rootRunFolder, ...
    stageRows, stageOrder, "bundle_complete_resumed", 0, toc(bundleStart), ...
    "Strict waveform LLS derived bundle completed without replaying the PHY runtime.");

out = struct();
out.Ok = logical(localLinkKPITableHealthy(kpi));
out.RunFolder = runFolder;
out.Result = res;
out.KPITable = kpi;
out.SNRSweep = res.SNRSweep;
out.MeasuredSINR = measuredSINRArtifacts;
out.ReferenceSweep = res.ReferenceSweep;
out.FixedLinkCampaign = res.FixedLinkCampaign;
out.RawTrials = rawTrials;
out.Artifacts = arts;
out.BeamformingArtifacts = beamArtifacts;
out.HARQArtifacts = harqArtifacts;
out.EnergyArtifacts = energyArtifacts;
out.TrialDiagnosticPlots = trialPlots;
out.PHYSignalDiagnosticArtifacts = phySignalArtifacts;
out.ISACArtifacts = isacArtifacts;
out.LiveMobilityArtifacts = struct();
out.LiveDerivedArtifacts = struct();
out.RuntimeStageProfile = struct2table(stageRows);
out.Integrity = integrity;
out.Errors = strings(0, 1);
if strlength(diagnosticExportError) > 0
    out.Errors = diagnosticExportError;
    out.Ok = false;
end
out.UnsupportedCases = table();
out.MultiUser = multiUser;
out.PersistenceEnabled = true;
out.CoreOnly = false;
out.ResumedCompletedRuntimeFinalization = true;
out.CompletedRuntimeCheckpoint = checkpoint;
end

function T = localReadPersistedCSV(path)
T = table();
if exist(char(path), "file") ~= 2
    return;
end
T = sixgr.util.csvReadTable(path,"TextType","string");
end

function tf = localResolvePersistenceEnabled(opt)
tf = logical(sixgr.util.structGet(opt, "PersistenceEnabled", true));
if logical(sixgr.util.structGet(opt, "CoreOnly", false))
    tf = false;
end
tf = tf && sixgr.util.persistenceEnabled();
end

function localLogStage(ctx, msg)
if ~(isa(ctx, "sixgr.core.SimContext") && isprop(ctx, "Logger") && ~isempty(ctx.Logger))
    return;
end
try
    ctx.Logger.info(string(msg));
catch
end
end

function [res, unsupported] = localPruneUnsupportedTruthCases(res)
unsupported = table();
if ~(isstruct(res) && isfield(res, "KPITable") && istable(res.KPITable) && ~isempty(res.KPITable))
    return;
end
caseCol = string(res.KPITable.Case);
noteCol = strings(height(res.KPITable), 1);
if ismember("Notes", string(res.KPITable.Properties.VariableNames))
    noteCol = lower(string(res.KPITable.Notes));
end
mask = strcmpi(caseCol, "PRACH_Detection") & ( ...
    contains(noteCol, "cfg.phy.prach.enable=false") | ...
    contains(noteCol, "nrprach/nrprachdetect unavailable") | ...
    contains(noteCol, "prach waveform is empty"));
if any(mask)
    unsupported = res.KPITable(mask, :);
    if ismember("Notes", string(unsupported.Properties.VariableNames))
        unsupported.Notes = string(unsupported.Notes) + "|unsupported_in_truth_validation_profile";
    end
    res.KPITable = res.KPITable(~mask, :);
end
end

function caseNames = localResolveBundleAnchorCases(opt)
rawCases = sixgr.util.structGet(opt, "LinkAnchorCases", {});
if isempty(rawCases)
    caseNames = strings(0, 1);
    return;
end
tokens = string(rawCases(:));
tokens = lower(strtrim(tokens));
tokens = tokens(strlength(tokens) > 0);
caseNames = strings(0, 1);
for i = 1:numel(tokens)
    caseNames(end+1, 1) = localNormalizeBundleAnchorCaseName(tokens(i)); %#ok<AGROW>
end
caseNames = unique(caseNames, "stable");
end

function caseName = localNormalizeBundleAnchorCaseName(token)
switch lower(strtrim(string(token)))
    case {"cell_search_mib_sib1", "cellsearch_mib_sib1", "cellsearch"}
        caseName = "CellSearch_MIB_SIB1";
    case {"prach_detection", "prach"}
        caseName = "PRACH_Detection";
    case {"dl_pdsch_throughput", "dl_pdsch", "pdsch", "dl"}
        caseName = "DL_PDSCH_Throughput";
    case {"ul_pusch_throughput", "ul_pusch", "pusch", "ul"}
        caseName = "UL_PUSCH_Throughput";
    case {"ul_srs_channelest", "ul_srs_channel_est", "srs", "ul_srs"}
        caseName = "UL_SRS_ChannelEst";
    case {"ul_lowpapr", "ul_low_papr", "lowpapr", "papr"}
        caseName = "UL_LowPAPR";
    otherwise
        error("sixgr:truth:UnknownBundleAnchorCase", ...
            "Unsupported scenario.bundle_anchor_cases token '%s'.", string(token));
end
end

function caseDefs = localBundleAnchorCaseDefs()
caseDefs = { ...
    struct('name',"CellSearch_MIB_SIB1"); ...
    struct('name',"PRACH_Detection"); ...
    struct('name',"DL_PDSCH_Throughput"); ...
    struct('name',"UL_PUSCH_Throughput"); ...
    struct('name',"UL_SRS_ChannelEst"); ...
    struct('name',"UL_LowPAPR") ...
    };
end

function res = localRunConfiguredBundleAnchorCases(cfg, ctx, numFrames, baseSNR_dB, anchorCaseNames)
res = struct();
res.Ok = false;
res.Skipped = false;
res.Errors = strings(0, 1);
res.Cases = struct();
res.KPITable = table();
res.Artifacts = struct('csv', {{}}, 'mat', {{}}, 'fig', {{}});

rows = repmat(localMakeBundleAnchorKpiRow("", struct()), 0, 1);
for k = 1:numel(anchorCaseNames)
    cName = string(anchorCaseNames(k));
    deferred = struct( ...
        "Ok", false, ...
        "Skipped", false, ...
        "BER", NaN, ...
        "BLER", NaN, ...
        "Throughput_Mbps", NaN, ...
        "EVM_rms", NaN, ...
        "PAPR_CP_dB", NaN, ...
        "PAPR_DFTs_dB", NaN, ...
        "PAPR_Gain_dB", NaN, ...
        "NMSE_dB", NaN, ...
        "Notes", "deferred_to_primary_raw_trials");
    res.Cases.(matlab.lang.makeValidName(char(cName))) = deferred;
    rows(end+1, 1) = localMakeBundleAnchorKpiRow(cName, deferred); %#ok<AGROW>
end
res.KPITable = struct2table(rows);

for k = 1:numel(anchorCaseNames)
    cName = string(anchorCaseNames(k));
    try
        cres = localRunBundleAnchorCase(cfg, ctx, cName, numFrames, baseSNR_dB);
    catch ME
        cres = struct( ...
            "Ok", false, ...
            "Skipped", false, ...
            "BER", NaN, ...
            "BLER", NaN, ...
            "Throughput_Mbps", NaN, ...
            "EVM_rms", NaN, ...
            "PAPR_CP_dB", NaN, ...
            "PAPR_DFTs_dB", NaN, ...
            "PAPR_Gain_dB", NaN, ...
            "NMSE_dB", NaN, ...
            "Notes", "Crash: " + string(ME.message));
        res.Errors(end+1, 1) = "Anchor case " + cName + " failed: " + string(ME.message); %#ok<AGROW>
    end
    res = localReplaceCaseResult(res, cName, cres);
    if ~logical(sixgr.util.structGet(cres, "Ok", false)) && ...
            ~logical(sixgr.util.structGet(cres, "Skipped", false))
        res.Errors(end+1, 1) = "Anchor case " + cName + " failed: " + string(sixgr.util.structGet(cres, "Notes", "")); %#ok<AGROW>
    end
end
res.Ok = localLinkKPITableHealthy(res.KPITable);
if isempty(anchorCaseNames)
    % Coupled mode deliberately executes no standalone preflight cases.
    % An empty table is neither measured success nor a failing case row.
    % Keep Ok=false until canonical runtime evidence has been collected.
    localLogStage(ctx, "No standalone bundle anchor cases executed; canonical slot-runtime measurements are pending.");
elseif ~res.Ok
    localLogStage(ctx, "Configured bundle anchor cases completed with deferred or failing case rows.");
end
end

function cres = localRunBundleAnchorCase(cfg, ctx, caseName, numFrames, baseSNR_dB)
log = [];
if isa(ctx, "sixgr.core.SimContext") && isprop(ctx, "Logger")
    log = ctx.Logger;
end
switch string(caseName)
    case "CellSearch_MIB_SIB1"
        rootRunFolder = string(sixgr.util.structGet(cfg, "run.rootRunFolder", ""));
        cellSearchArgs = {"Logger", log};
        if strlength(rootRunFolder) > 0 && logical(sixgr.util.structGet(cfg, "phy.sib1.enable", false))
            cellSearchArgs = [cellSearchArgs, {"RunFolder", rootRunFolder, ...
                "RunId", "sib1_anchor_waveform", "WriteArtifacts", true}]; %#ok<AGROW>
        end
        cres = sixgr.link.runCellSearch_MIB_SIB1(cfg, cellSearchArgs{:});
    case "PRACH_Detection"
        cres = sixgr.link.runPRACHDetection(cfg, "Logger", log, "SNR_dB", baseSNR_dB);
    case "DL_PDSCH_Throughput"
        cres = sixgr.link.runDLPDSCHThroughput(cfg, "Logger", log, "NumFrames", numFrames);
    case "UL_PUSCH_Throughput"
        cres = sixgr.link.runULPUSCHThroughput(cfg, "Logger", log, "NumFrames", numFrames, "SNR_dB", baseSNR_dB);
    case "UL_SRS_ChannelEst"
        cres = sixgr.link.runSRSChannelEstimation(cfg, "Logger", log, "SNR_dB", baseSNR_dB);
    case "UL_LowPAPR"
        cres = sixgr.link.runULLowPAPR(cfg, "Logger", log, "NumFrames", numFrames);
    otherwise
        error("sixgr:truth:UnknownBundleAnchorCaseName", ...
            "Unknown normalized bundle anchor case '%s'.", string(caseName));
end
end

function row = localMakeBundleAnchorKpiRow(caseName, s)
row = struct();
row.Case = string(caseName);
row.Ok = logical(sixgr.util.structGet(s, "Ok", false));
row.Skipped = logical(sixgr.util.structGet(s, "Skipped", false));
row.BER = double(sixgr.util.structGet(s, "BER", NaN));
row.BLER = double(sixgr.util.structGet(s, "BLER", NaN));
row.BLERScope = string(sixgr.util.structGet(s, "BLERScope", ""));
row.BLEREligibleTrialCount = double(sixgr.util.structGet(s, "BLEREligibleTrialCount", NaN));
row.BLERErrorCount = double(sixgr.util.structGet(s, "BLERErrorCount", NaN));
row.BLERSource = string(sixgr.util.structGet(s, "BLERSource", ""));
row.BLERStatus = string(sixgr.util.structGet(s, "BLERStatus", ""));
row.Throughput_Mbps = double(sixgr.util.structGet(s, "Throughput_Mbps", NaN));
row.EVM_rms = double(sixgr.util.structGet(s, "EVM_rms", NaN));
row.PAPR_CP_dB = double(sixgr.util.structGet(s, "PAPR_CP_dB", NaN));
row.PAPR_DFTs_dB = double(sixgr.util.structGet(s, "PAPR_DFTs_dB", NaN));
row.PAPR_Gain_dB = double(sixgr.util.structGet(s, "PAPR_Gain_dB", NaN));
row.NMSE_dB = double(sixgr.util.structGet(s, "NMSE_dB", NaN));
row.Notes = string(sixgr.util.structGet(s, "Notes", ""));
end

function T = localRunLinkSNRSweep(cfg, snrGrid, nFrames, multiUser)
if nargin < 4 || ~isstruct(multiUser)
    multiUser = localResolveMultiUserSpec(cfg);
end
if logical(sixgr.util.structGet(multiUser, "Enabled", false))
    rows = repmat(struct("UEIndex", NaN, "RNTI", NaN, "SNR_dB", NaN, ...
        "DL_BER", NaN, "DL_BLER", NaN, "DL_Throughput_Mbps", NaN, ...
        "DL_OfferedThroughput_Mbps", NaN, "DL_Goodput_Mbps", NaN, ...
        "DL_CodeBlockBLER", NaN, "DL_CBG_BLER", NaN, ...
        "UL_BER", NaN, "UL_BLER", NaN, "UL_Throughput_Mbps", NaN, ...
        "UL_OfferedThroughput_Mbps", NaN, "UL_Goodput_Mbps", NaN, ...
        "UL_CodeBlockBLER", NaN, "UL_CBG_BLER", NaN, ...
        "SRS_NMSE_dB", NaN, "BeamSelectionStrategy", "", ...
        "ExecutionModel", ""), 0, 1);
    for ueIdx = 1:max(1, round(double(multiUser.NumUsers)))
        cfgU = localPrepareUserCfg(cfg, multiUser, ueIdx);
        Tu = localRunLinkSNRSweep(cfgU, snrGrid, nFrames, localSingleUserSpec(multiUser));
        if isempty(Tu)
            continue;
        end
        for r = 1:height(Tu)
            rows(end+1,1) = struct( ... %#ok<AGROW>
                "UEIndex", double(ueIdx), ...
                "RNTI", double(localUserRNTI(multiUser, ueIdx)), ...
                "SNR_dB", double(Tu.SNR_dB(r)), ...
                "DL_BER", double(Tu.DL_BER(r)), ...
                "DL_BLER", double(Tu.DL_BLER(r)), ...
                "DL_Throughput_Mbps", double(Tu.DL_Throughput_Mbps(r)), ...
                "DL_OfferedThroughput_Mbps", double(Tu.DL_OfferedThroughput_Mbps(r)), ...
                "DL_Goodput_Mbps", double(Tu.DL_Goodput_Mbps(r)), ...
                "DL_CodeBlockBLER", double(Tu.DL_CodeBlockBLER(r)), ...
                "DL_CBG_BLER", double(Tu.DL_CBG_BLER(r)), ...
                "UL_BER", double(Tu.UL_BER(r)), ...
                "UL_BLER", double(Tu.UL_BLER(r)), ...
                "UL_Throughput_Mbps", double(Tu.UL_Throughput_Mbps(r)), ...
                "UL_OfferedThroughput_Mbps", double(Tu.UL_OfferedThroughput_Mbps(r)), ...
                "UL_Goodput_Mbps", double(Tu.UL_Goodput_Mbps(r)), ...
                "UL_CodeBlockBLER", double(Tu.UL_CodeBlockBLER(r)), ...
                "UL_CBG_BLER", double(Tu.UL_CBG_BLER(r)), ...
                "SRS_NMSE_dB", double(Tu.SRS_NMSE_dB(r)), ...
                "BeamSelectionStrategy", string(multiUser.BeamSelectionStrategy), ...
                "ExecutionModel", string(multiUser.ExecutionModel));
        end
    end
    if isempty(rows)
        T = table();
    else
        T = struct2table(rows);
    end
    return;
end

n = numel(snrGrid);
rows = repmat(localEmptySweepSummaryRow(0), n, 1);
nFrames = max(1, round(double(nFrames)));
useParallelSweep = localCanParallelizeSweep(cfg, n);
seedBase = double(sixgr.util.structGet(cfg, "run.seed", 1));
if useParallelSweep
    rows = cell(n,1);
    parfor i = 1:n
        rows{i} = localRunSweepPointDeterministic(cfg, double(snrGrid(i)), nFrames, seedBase + 1000 + i);
    end
    rows = vertcat(rows{:});
else
    for i = 1:n
        rows(i,1) = localRunSweepPointDeterministic(cfg, double(snrGrid(i)), nFrames, seedBase + 1000 + i);
    end
end
T = struct2table(rows);
end

function tf = localCanParallelizeSweep(cfg, nPoints)
workerCount = max(1, round(double(sixgr.util.structGet(cfg, "run.numWorkers", 1))));
minPoints = double(sixgr.util.structGet(cfg, "run.parallelMinSweepPointCount", NaN));
if ~(isscalar(minPoints) && isfinite(minPoints) && minPoints >= 2)
    minPoints = max(2, min(workerCount, 8));
end
tf = logical(sixgr.util.structGet(cfg, "run.useParallel", false)) && ...
    workerCount > 1 && nPoints >= minPoints && ...
    localEnsureCoupledParallelPool(cfg, "fixed_link_sweep");
end

function row = localRunSweepPointDeterministic(cfg, snr, nFrames, seed)
row = localEmptySweepSummaryRow(snr);

if logical(sixgr.util.structGet(cfg, "phy.pdsch.enable", false))
    rng(double(seed), "twister");
    dl = sixgr.link.runDLPDSCHThroughput(cfg, "NumFrames", nFrames, "SNR_dB", snr);
    if logical(sixgr.util.structGet(dl, "Skipped", false))
        error("sixgr:truth:FixedSweepSkippedDL", ...
            "DL fixed-link sweep point at %.6g dB was skipped: %s", snr, string(sixgr.util.structGet(dl, "Notes", "")));
    end
    dlTrials = localEnsureLinkTrialTable(sixgr.util.structGet(dl, "TrialTable", table()), "DL", snr, cfg);
    dlStats = localSummarizeLinkTrialTable(dlTrials, cfg);
    row = localApplyLinkSweepStats(row, "DL", dlStats);
end

if logical(sixgr.util.structGet(cfg, "phy.pusch.enable", false))
    rng(double(seed) + 10000, "twister");
    ul = sixgr.link.runULPUSCHThroughput(cfg, "NumFrames", nFrames, "SNR_dB", snr);
    if logical(sixgr.util.structGet(ul, "Skipped", false))
        error("sixgr:truth:FixedSweepSkippedUL", ...
            "UL fixed-link sweep point at %.6g dB was skipped: %s", snr, string(sixgr.util.structGet(ul, "Notes", "")));
    end
    ulTrials = localEnsureLinkTrialTable(sixgr.util.structGet(ul, "TrialTable", table()), "UL", snr, cfg);
    ulStats = localSummarizeLinkTrialTable(ulTrials, cfg);
    row = localApplyLinkSweepStats(row, "UL", ulStats);
end

if logical(sixgr.util.structGet(cfg, "phy.srs.enable", false))
    rng(double(seed) + 20000, "twister");
    srs = sixgr.link.runSRSChannelEstimation(cfg, "SNR_dB", snr);
    if logical(sixgr.util.structGet(srs, "Skipped", false))
        error("sixgr:truth:FixedSweepSkippedSRS", ...
            "SRS fixed-link sweep point at %.6g dB was skipped: %s", snr, string(sixgr.util.structGet(srs, "Notes", "")));
    end
    row = sixgr.truth.applySRSSweepStatistics(row,srs);
end
end

function out = localExportLinkRawTrialTables(cfg, runFolder, linkRes, nFrames, snrGrid_dB, multiUser, saveFigures, mobilityArtifacts, checkpointLease)
if nargin < 6 || ~isstruct(multiUser)
    multiUser = localResolveMultiUserSpec(cfg);
end
if nargin < 7
    saveFigures = false;
end
if nargin < 8 || ~isstruct(mobilityArtifacts)
    mobilityArtifacts = struct();
end
coupledTruth = logical(multiUser.Enabled) && string(multiUser.ExecutionModel) == "slot_coupled_truth";
csvDir = fullfile(runFolder, "csv");
sixgr.util.ensureFolder(csvDir);

nTrials = max(1, round(double(nFrames)));
snrGrid = unique(sort(double(snrGrid_dB(:))));
if isempty(snrGrid)
    snrGrid = double(sixgr.util.structGet(cfg, "channel.snr_dB", 30));
end

fDL = fullfile(csvDir, "dl_pdsch_trials.csv");
fUL = fullfile(csvDir, "ul_pusch_trials.csv");
fSSBBeamSweep = fullfile(csvDir, "ssb_pbch_sib1_beam_sweep.csv");
fPBCH = fullfile(csvDir, "pbch_trials.csv");
fPRACH = fullfile(csvDir, "prach_trials.csv");
fPDCCH = fullfile(csvDir, "pdcch_trials.csv");
fPUCCH = fullfile(csvDir, "pucch_trials.csv");
fSRS = fullfile(csvDir, "srs_trials.csv");
fCSIRS = fullfile(csvDir, "csi_rs_trials.csv");
fTRS = fullfile(csvDir, "trs_trials.csv");
isLiveDBMode = localIsMySQLWebMode(cfg);
dlLiveConstellationPath = "";
ulLiveConstellationPath = "";
liveSweepPath = "";
if localCoupledLiveRuntimePublicationEnabled(cfg)
    [dlLiveConstellationPath, ulLiveConstellationPath] = ...
        sixgr.truth.constellationArtifactPaths(cfg, csvDir);
end
if isLiveDBMode
    emptyTrials = localEmptyLinkTrialTable(0);
    sixgr.util.csvWriteTable(fDL, emptyTrials);
    sixgr.util.csvWriteTable(fUL, emptyTrials);
    sixgr.util.csvWriteTable(fPBCH, emptyTrials);
    sixgr.util.csvWriteTable(fPRACH, emptyTrials);
    sixgr.util.csvWriteTable(fPDCCH, emptyTrials);
    standalonePUCCHRequired = logical(sixgr.util.structGet(cfg, ...
        "control_gating.pucch_required", sixgr.util.structGet(cfg, ...
        "run.controlGating.pucchRequired", false)));
    if standalonePUCCHRequired
        sixgr.util.csvWriteTable(fPUCCH, emptyTrials);
    elseif isfile(fPUCCH)
        delete(fPUCCH);
    end
    sixgr.util.csvWriteTable(fSRS, emptyTrials);
    sixgr.util.csvWriteTable(fTRS, emptyTrials);
    localPublishWaveformBundleStageStatus(runFolder, struct( ...
        "Stage", "raw_trials_streaming", ...
        "AnchorKPIsReady", true, ...
        "DLTrialsReady", false, ...
        "ULTrialsReady", false, ...
        "ControlReady", false, ...
        "HARQReady", false, ...
        "BeamReady", false, ...
        "RFReady", false, ...
        "SweepReady", false, ...
        "FinalBundleReady", false, ...
        "Notes", "Raw truth tables are streaming into the database as each SNR sweep point completes."));
end

pbchTrials = localEmptyLinkTrialTable(0);
ssbBeamSweep = table();
prachTrials = localEmptyLinkTrialTable(0);
prachCorrelationTrace = table();
prachRAEvidence = localEmptyRAEvidenceTables();
pdcchTrials = localEmptyLinkTrialTable(0);
pucchTrials = localEmptyLinkTrialTable(0);
srsTrials = localEmptyLinkTrialTable(0);
csirsTrials = table();
trsTrials = localEmptyLinkTrialTable(0);
coupledRuntime = struct();
dlObservedRE = table();
ulObservedRE = table();
dlWaveformPreview = table();
ulWaveformPreview = table();
dlSignalDiagnostic = localUnavailablePHYSignalDiagnostic("DL");
ulSignalDiagnostic = localUnavailablePHYSignalDiagnostic("UL");
% Component-anchor diagnostics may be requested explicitly, but they must
% never backfill primary coupled-runtime tables when an in-path feature is
% disabled.  Primary rows are reserved for observations made by this run's
% canonical slot/control state machine.
exportStandaloneControlDiagnostics = logical(sixgr.util.structGet( ...
    cfg, "outputs.exportStandaloneControlDiagnostics", false));

if coupledTruth
    if exportStandaloneControlDiagnostics
        diagDir = localStandaloneControlDiagnosticDir(runFolder, csvDir);
        standalonePBCH = localCollectTrialsAcrossSweep(@(snr) localCollectPBCHTrials(cfg, snr, max(1, ceil(nTrials/4))), snrGrid, ...
            fullfile(diagDir, "pbch_standalone_trials.csv"), "PBCH standalone diagnostic", cfg);
        standalonePBCH = localCanonicalizeControlTrialTable("PBCH", localMarkStandaloneControlDiagnostic("PBCH", standalonePBCH));
        sixgr.util.csvWriteTable(fullfile(diagDir, "pbch_standalone_trials.csv"), standalonePBCH);

        standalonePRACH = localCollectTrialsAcrossSweep(@(snr) localCollectPRACHTrials(cfg, snr, max(1, ceil(nTrials/4))), snrGrid, ...
            fullfile(diagDir, "prach_standalone_trials.csv"), "PRACH standalone diagnostic", cfg);
        standalonePRACH = localCanonicalizeControlTrialTable("PRACH", localMarkStandaloneControlDiagnostic("PRACH", standalonePRACH));
        sixgr.util.csvWriteTable(fullfile(diagDir, "prach_standalone_trials.csv"), standalonePRACH);

        standalonePDCCH = localCollectTrialsAcrossSweep(@(snr) localCollectPDCCHTrials(cfg, snr, max(1, ceil(nTrials/2))), snrGrid, ...
            fullfile(diagDir, "pdcch_aggregation_sweep_trials.csv"), "PDCCH aggregation sweep diagnostic", cfg);
        standalonePDCCH = localCanonicalizeControlTrialTable("PDCCH", localMarkStandaloneControlDiagnostic("PDCCH", standalonePDCCH));
        sixgr.util.csvWriteTable(fullfile(diagDir, "pdcch_aggregation_sweep_trials.csv"), standalonePDCCH);

        standalonePUCCH = localCollectTrialsAcrossSweep(@(snr) localCollectPUCCHTrials(cfg, snr, max(1, ceil(nTrials/2))), snrGrid, ...
            fullfile(diagDir, "pucch_standalone_trials.csv"), "PUCCH standalone diagnostic", cfg);
        standalonePUCCH = localCanonicalizeControlTrialTable("PUCCH", localMarkStandaloneControlDiagnostic("PUCCH", standalonePUCCH));
        sixgr.util.csvWriteTable(fullfile(diagDir, "pucch_standalone_trials.csv"), standalonePUCCH);

        standaloneSRS = localCollectTrialsAcrossSweep(@(snr) localCollectSRSTrials(cfg, snr, max(1, ceil(nTrials/3))), snrGrid, ...
            fullfile(diagDir, "srs_standalone_trials.csv"), "SRS standalone diagnostic", cfg);
        standaloneSRS = localCanonicalizeControlTrialTable("SRS", localMarkStandaloneControlDiagnostic("SRS", standaloneSRS));
        sixgr.util.csvWriteTable(fullfile(diagDir, "srs_standalone_trials.csv"), standaloneSRS, ...
            "RoundTripNumericText",true);

        standaloneTRS = localCollectTrialsAcrossSweep(@(snr) localCollectTRSTrials(cfg, snr, max(1, ceil(nTrials/3))), snrGrid, ...
            fullfile(diagDir, "trs_standalone_trials.csv"), "TRS standalone diagnostic", cfg);
        standaloneTRS = localCanonicalizeControlTrialTable("TRS", localMarkStandaloneControlDiagnostic("TRS", standaloneTRS));
        sixgr.util.csvWriteTable(fullfile(diagDir, "trs_standalone_trials.csv"), standaloneTRS);

    end
else
    pbchTrials = localCollectTrialsAcrossSweep(@(snr) localCollectPBCHTrials(cfg, snr, max(1, ceil(nTrials/4))), snrGrid, fPBCH, "PBCH", cfg);
    pbchTrials = localCanonicalizeControlTrialTable("PBCH", pbchTrials);
    sixgr.util.csvWriteTable(fPBCH, pbchTrials);

    [prachTrials, prachCorrelationTrace, prachRAEvidence] = localCollectPRACHTrialsAcrossSweep(cfg, snrGrid, max(1, ceil(nTrials/4)), fPRACH, "PRACH");
    prachTrials = localCanonicalizeControlTrialTable("PRACH", prachTrials);
    sixgr.util.csvWriteTable(fPRACH, prachTrials, "PreserveSchema", true);

    [pdcchTrials,pdcchChannelEstimates] = localCollectPDCCHTrialsAcrossSweep( ...
        cfg,snrGrid,max(1,ceil(nTrials/2)),fPDCCH);
    pdcchTrials = localCanonicalizeControlTrialTable("PDCCH", pdcchTrials);
    sixgr.util.csvWriteTable(fPDCCH, pdcchTrials);
    if logical(sixgr.util.structGet(cfg,"outputs.phySignalDiagnosticEnabled",false))
        sixgr.report.exportPDCCHChannelEstimates(fileparts(char(string(runFolder))), ...
            pdcchChannelEstimates,saveFigures);
    end

    pucchTrials = localCollectTrialsAcrossSweep(@(snr) localCollectPUCCHTrials(cfg, snr, max(1, ceil(nTrials/2))), snrGrid, fPUCCH, "PUCCH", cfg);
    pucchTrials = localCanonicalizeControlTrialTable("PUCCH", pucchTrials);
    sixgr.util.csvWriteTable(fPUCCH, pucchTrials);

    srsTrials = localCollectTrialsAcrossSweep(@(snr) localCollectSRSTrials(cfg, snr, max(1, ceil(nTrials/3))), snrGrid, fSRS, "SRS", cfg);
    srsTrials = localCanonicalizeControlTrialTable("SRS", srsTrials);
    sixgr.util.csvWriteTable(fSRS, srsTrials,"RoundTripNumericText",true);

    trsTrials = localCollectTrialsAcrossSweep(@(snr) localCollectTRSTrials(cfg, snr, max(1, ceil(nTrials/3))), snrGrid, fTRS, "TRS", cfg);
    trsTrials = localCanonicalizeControlTrialTable("TRS", trsTrials);
    sixgr.util.csvWriteTable(fTRS, trsTrials);
end
if isLiveDBMode
    if coupledTruth && exportStandaloneControlDiagnostics
        controlReadyNotes = "Control/reference diagnostic sweeps are available separately; primary coupled control tables are populated only by runtime observations.";
    elseif coupledTruth
        controlReadyNotes = "Standalone control/reference diagnostic sweeps are disabled for coupled truth; primary control tables are populated only by runtime observations.";
    else
        controlReadyNotes = "Standalone waveform control/reference raw trial rows are available live in the database.";
    end
    localPublishWaveformBundleStageStatus(runFolder, struct( ...
        "Stage", "control_trials_ready", ...
        "AnchorKPIsReady", true, ...
        "DLTrialsReady", false, ...
        "ULTrialsReady", false, ...
        "ControlReady", true, ...
        "HARQReady", false, ...
        "BeamReady", false, ...
        "RFReady", false, ...
        "SweepReady", false, ...
        "FinalBundleReady", false, ...
        "Notes", controlReadyNotes));
end

if coupledTruth
    [dlTrials, ulTrials, dlUserSummary, ulUserSummary, dlConst, ulConst, controlTrials, coupledRuntime] = ...
        localCollectCoupledTruthMultiUserLinkTrialsAcrossSweep(cfg, runFolder, multiUser, nTrials, snrGrid, ...
        fDL, fUL, dlLiveConstellationPath, ulLiveConstellationPath, struct(), checkpointLease);
    coupledDiagnostics = sixgr.util.structGet(coupledRuntime, "PHYSignalDiagnostics", struct());
    dlSignalDiagnostic = localSelectPHYSignalDiagnostic(dlSignalDiagnostic, ...
        sixgr.util.structGet(coupledDiagnostics, "DL", struct()));
    ulSignalDiagnostic = localSelectPHYSignalDiagnostic(ulSignalDiagnostic, ...
        sixgr.util.structGet(coupledDiagnostics, "UL", struct()));
    pbchTrials = localRuntimeControlTrials(sixgr.util.structGet(controlTrials, "PBCH", table()));
    prachTrials = localRuntimeControlTrials(sixgr.util.structGet(controlTrials, "PRACH", table()));
    prachCorrelationTrace = localRuntimeControlTrials(sixgr.util.structGet(controlTrials, "PRACHCorrelationTrace", table()));
    prachRAEvidence = localAppendRAEvidenceTables(prachRAEvidence, sixgr.util.structGet(controlTrials, "RAEvidenceTables", struct()));
    pdcchTrials = localRuntimeControlTrials(sixgr.util.structGet(controlTrials, "PDCCH", table()));
    if width(pdcchTrials) == 0
        % Acquisition outage can prevent every PDCCH occasion. Preserve a
        % typed zero-row CSV, not a two-byte file with no schema.
        pdcchTrials = localEmptyLinkTrialTable(0);
    end
    if logical(sixgr.util.structGet(cfg,"outputs.phySignalDiagnosticEnabled",false))
        channelEstimates=localBindCoupledRuntimeIdentity( ...
            sixgr.util.structGet(controlTrials,"PDCCHChannelEstimate",table()),cfg,"PDCCH");
        sixgr.report.exportPDCCHChannelEstimates(fileparts(char(string(runFolder))), ...
            channelEstimates,saveFigures);
    end
    pucchTrials = localRuntimeControlTrials(sixgr.util.structGet(controlTrials, "PUCCH", table()));
    srsTrials = localRuntimeControlTrials(sixgr.util.structGet(controlTrials, "SRS", table()));
    csirsTrials = localRuntimeControlTrials(sixgr.util.structGet(controlTrials, "CSIRS", table()));
    trsTrials = localRuntimeControlTrials(sixgr.util.structGet(controlTrials, "TRS", table()));
elseif logical(multiUser.Enabled) && isLiveDBMode
    [dlTrials, ulTrials, dlUserSummary, ulUserSummary, dlConst, ulConst, csirsTrials, dlSignalDiagnostic, ulSignalDiagnostic, dlWaveformPreview, ulWaveformPreview, dlObservedRE, ulObservedRE] = ...
        localCollectInterleavedMultiUserLinkTrialsAcrossSweep(cfg, runFolder, multiUser, nTrials, snrGrid, ...
        fDL, fUL, dlLiveConstellationPath, ulLiveConstellationPath, saveFigures, mobilityArtifacts);
else
    if logical(multiUser.Enabled)
        [dlTrials, dlUserSummary, dlConst, csirsTrials, dlSignalDiagnostic, dlWaveformPreview, dlObservedRE] = localCollectMultiUserLinkTrialsAcrossSweep(cfg, multiUser, "DL", nTrials, snrGrid, fDL, dlLiveConstellationPath, "DL PDSCH");
    else
        [dlTrials, dlConst, csirsTrials, dlSignalDiagnostic, dlWaveformPreview, dlObservedRE] = localCollectSingleUserLinkTrialsAcrossSweep(cfg, "DL", nTrials, snrGrid, ...
            fDL, dlLiveConstellationPath, "DL PDSCH");
        dlUserSummary = table();
    end
    dlTrials = localCanonicalizeLinkTrialExport(dlTrials, "DL", cfg);
    sixgr.util.csvWriteTable(fDL, dlTrials, "PreserveSchema", true);
    if istable(csirsTrials) && ~isempty(csirsTrials)
        sixgr.util.csvWriteTable(fCSIRS, csirsTrials, "PreserveSchema", true);
    end
    if isLiveDBMode
        liveArtifacts = localRefreshLiveDerivedArtifacts(cfg, runFolder, struct( ...
            "DL", dlTrials, ...
            "UL", table(), ...
            "SRS", srsTrials, ...
            "CSIRS", csirsTrials, ...
            "TRS", trsTrials, ...
            "PDCCH", pdcchTrials, ...
            "PBCH", pbchTrials, ...
            "PRACH", prachTrials, ...
            "PUCCH", pucchTrials, ...
            "MultiUserDL", dlUserSummary, ...
            "MultiUserUL", table()), multiUser, mobilityArtifacts);
        localPublishWaveformBundleStageStatus(runFolder, struct( ...
            "Stage", "dl_raw_trials_ready", ...
            "AnchorKPIsReady", true, ...
            "DLTrialsReady", true, ...
            "ULTrialsReady", false, ...
            "ControlReady", true, ...
            "HARQReady", localArtifactStructReady(liveArtifacts.HARQ, "SummaryTable") || localArtifactStructReady(liveArtifacts.HARQ, "TimelineTable"), ...
            "BeamReady", localArtifactStructReady(liveArtifacts.Beam, "SummaryTable"), ...
            "RFReady", localRFArtifactsReady(liveArtifacts), ...
            "SweepReady", false, ...
            "FinalBundleReady", false, ...
            "Notes", "DL PDSCH raw trial rows are available live in the database."));
    end

    if logical(multiUser.Enabled)
        [ulTrials, ulUserSummary, ulConst, ~, ulSignalDiagnostic, ulWaveformPreview, ulObservedRE] = localCollectMultiUserLinkTrialsAcrossSweep(cfg, multiUser, "UL", nTrials, snrGrid, fUL, ulLiveConstellationPath, "UL PUSCH");
    else
        [ulTrials, ulConst, ~, ulSignalDiagnostic, ulWaveformPreview, ulObservedRE] = localCollectSingleUserLinkTrialsAcrossSweep(cfg, "UL", nTrials, snrGrid, ...
            fUL, ulLiveConstellationPath, "UL PUSCH");
        ulUserSummary = table();
    end
    ulTrials = localCanonicalizeLinkTrialExport(ulTrials, "UL", cfg);
    sixgr.util.csvWriteTable(fUL, ulTrials, "PreserveSchema", true);
    if isLiveDBMode
        liveArtifacts = localRefreshLiveDerivedArtifacts(cfg, runFolder, struct( ...
            "DL", dlTrials, ...
            "UL", ulTrials, ...
            "SRS", srsTrials, ...
            "CSIRS", csirsTrials, ...
            "TRS", trsTrials, ...
            "PDCCH", pdcchTrials, ...
            "PBCH", pbchTrials, ...
            "PRACH", prachTrials, ...
            "PUCCH", pucchTrials, ...
            "MultiUserDL", dlUserSummary, ...
            "MultiUserUL", ulUserSummary), multiUser, mobilityArtifacts);
        localPublishWaveformBundleStageStatus(runFolder, struct( ...
            "Stage", "ul_raw_trials_ready", ...
            "AnchorKPIsReady", true, ...
            "DLTrialsReady", true, ...
            "ULTrialsReady", true, ...
            "ControlReady", true, ...
            "HARQReady", localArtifactStructReady(liveArtifacts.HARQ, "SummaryTable") || localArtifactStructReady(liveArtifacts.HARQ, "TimelineTable"), ...
            "BeamReady", localArtifactStructReady(liveArtifacts.Beam, "SummaryTable"), ...
            "RFReady", localRFArtifactsReady(liveArtifacts), ...
            "SweepReady", false, ...
            "FinalBundleReady", false, ...
            "Notes", "UL PUSCH raw trial rows are available live in the database."));
    end
end

function T = localRuntimeControlTrials(runtimeT)
if nargin < 1 || ~istable(runtimeT)
    T = table();
else
    T = runtimeT;
end
end

function diagDir = localStandaloneControlDiagnosticDir(airInterfaceRunFolder, fallbackCsvDir)
diagDir = fullfile(char(string(fallbackCsvDir)), "standalone_control_diagnostics");
rootRunFolder = fileparts(char(string(airInterfaceRunFolder)));
if strlength(string(rootRunFolder)) > 0
    try
        layout = sixgr.report.resultLayout(rootRunFolder);
        diagDir = fullfile(layout.ControlCSVDir, "standalone_diagnostics");
    catch
    end
end
sixgr.util.ensureFolder(diagDir);
end

function T = localMarkStandaloneControlDiagnostic(signalName, T)
if ~(istable(T) && ~isempty(T))
    return;
end
n = height(T);
sig = string(signalName);
T.SignalFamily = repmat(sig, n, 1);
T.SourceClassification = repmat("standalone_diagnostic", n, 1);
T.RuntimeMaterializationStatus = repmat("standalone_control_sweep_not_coupled_runtime", n, 1);
T.ControlGatingEffect = repmat("diagnostic_only_no_runtime_state_update", n, 1);
T.RuntimeStateConsumer = repmat("not_consumed_by_coupled_runtime", n, 1);
T.RuntimeConsumer = repmat("not_consumed_by_coupled_runtime", n, 1);
T.ValueSource = repmat("standalone_control_waveform_diagnostic", n, 1);
T.ValueRole = repmat("diagnostic_not_primary_runtime_evidence", n, 1);
T.ValueStatus = repmat("available_diagnostic_observation", n, 1);
T.ValueDefinition = repmat("standalone control/reference waveform diagnostic; not the canonical coupled runtime table", n, 1);
T.ArtifactClass = repmat("diagnostic_control_reference_signal_sweep", n, 1);
T.SemanticState = repmat("diagnostic_not_primary_runtime", n, 1);
T.FinalizedFlag = true(n, 1);
T.PlaceholderFlag = false(n, 1);
T.FallbackFlag = false(n, 1);
end

function localWriteCoupledControlMirror(airInterfaceRunFolder, fileName, T)
if nargin < 3 || ~istable(T)
    T = table();
end
rootRunFolder = fileparts(char(string(airInterfaceRunFolder)));
if strlength(string(rootRunFolder)) == 0
    return;
end
layout = sixgr.report.resultLayout(rootRunFolder);
preserveSchema = endsWith(string(fileName), "_trials.csv");
sixgr.util.csvWriteTable(fullfile(layout.ControlCSVDir, fileName), T, ...
    "PreserveSchema", preserveSchema,"RoundTripNumericText",string(fileName)=="srs_trials.csv");
end

function localWriteOptionalCoupledControlMirror(cfg, featureName, ...
        airInterfaceRunFolder, fileName, T)
rootRunFolder = fileparts(char(string(airInterfaceRunFolder)));
if strlength(string(rootRunFolder)) == 0
    return;
end
layout = sixgr.report.resultLayout(rootRunFolder);
path = fullfile(layout.ControlCSVDir, fileName);
if localOptionalFeatureHasPrimaryEvidence(cfg, featureName, T)
    localWriteCoupledControlMirror(airInterfaceRunFolder, fileName, T);
elseif isfile(path)
    delete(path);
end
end

function localWriteOptionalFeatureTrialTable(cfg, featureName, path, T)
sixgr.truth.writeOptionalRuntimeFeatureTable(cfg, string(featureName), ...
    string(path), T);
end

function tf = localOptionalFeatureHasPrimaryEvidence(cfg, featureName, T)
feature = sixgr.util.structGet(cfg, ...
    "runtime.features." + string(featureName), struct());
authorityPresent = isstruct(feature) && isscalar(feature) && ...
    isfield(feature, "Enabled");
if ~authorityPresent
    % Manual/unit configurations preserve their historical explicit-table
    % behavior; resolved YAML runs always carry runtime.features authority.
    tf = true;
    return;
end
enabled = logical(sixgr.util.structGet(feature, "Enabled", false));
tf = enabled || (istable(T) && height(T) > 0);
end

function tf = localShouldExportSSBBeamSweep(cfg)
tf = logical(sixgr.util.structGet(cfg, "outputs.exportSSBBeamSweep", ...
    sixgr.util.structGet(cfg, "analytics.export_ssb_beam_sweep", ...
    sixgr.util.structGet(cfg, "phy.beamManagement.enabled", false)))) && ...
    logical(sixgr.util.structGet(cfg, "phy.ssb.enable", false)) && ...
    localResolveSSBBeamCount(cfg) > 1;
end

function T = localCollectSSBBeamSweepArtifact(cfg, snr_dB, outputPath)
try
    sweep = sixgr.link.runSSBBeamSweep(cfg, ...
        "SNR_dB", double(snr_dB), ...
        "NumSubframes", localResolvePBCHObservationSubframes(cfg), ...
        "OutputPath", outputPath);
    T = sixgr.util.structGet(sweep, "TrialTable", table());
catch ME
    if logical(sixgr.util.structGet(cfg, "run.strictMode", false))
        rethrow(ME);
    end
    T = table();
end
end

function localWriteSSBBeamSweepMirrors(airInterfaceRunFolder, T)
if nargin < 2 || ~istable(T) || isempty(T)
    return;
end
rootRunFolder = fileparts(char(string(airInterfaceRunFolder)));
if strlength(string(rootRunFolder)) == 0
    return;
end
layout = sixgr.report.resultLayout(rootRunFolder);
sixgr.util.csvWriteTable(fullfile(layout.ControlCSVDir, "ssb_pbch_sib1_beam_sweep.csv"), T);
sixgr.util.csvWriteTable(fullfile(layout.BeamformingCSVDir, "ssb_pbch_sib1_beam_sweep.csv"), T);
sixgr.util.csvWriteTable(fullfile(layout.BeamformingCSVDir, "ssb_beam_sweep.csv"), T);
end

if coupledTruth && isstruct(coupledRuntime)
    harqTimelineT = sixgr.util.structGet(coupledRuntime, "HARQTimelineTable", table());
    dlTrials = localHydrateHARQTrialColumnsFromTimeline(dlTrials, harqTimelineT, "DL");
    ulTrials = localHydrateHARQTrialColumnsFromTimeline(ulTrials, harqTimelineT, "UL");
    csiFeedbackReports = sixgr.util.structGet(coupledRuntime, "PendingCSITable", table());
    referenceSignalMeasurements = sixgr.util.structGet(coupledRuntime, "ReferenceSignalMeasurementTable", table());
    csirsTrials = sixgr.report.bindCSIReportMeasurementAudit(csirsTrials, csiFeedbackReports, "DL");
    mobilityArtifacts = localBuildMobilityArtifactsFromCoupledRuntime(coupledRuntime);
else
    csiFeedbackReports = table();
    referenceSignalMeasurements = table();
end
dlTrials = localCanonicalizeLinkTrialExport(dlTrials, "DL", cfg);
ulTrials = localCanonicalizeLinkTrialExport(ulTrials, "UL", cfg);
pbchTrials = localCanonicalizeControlTrialTable("PBCH", pbchTrials);
prachTrials = localCanonicalizeControlTrialTable("PRACH", prachTrials);
pdcchTrials = localCanonicalizeControlTrialTable("PDCCH", pdcchTrials);
pucchTrials = localCanonicalizeControlTrialTable("PUCCH", pucchTrials);
srsTrials = localCanonicalizeControlTrialTable("SRS", srsTrials);
trsTrials = localCanonicalizeControlTrialTable("TRS", trsTrials);
if coupledTruth
    % All rows are emitted by the same coupled runtime. Bind immutable
    % scenario identity before any CSV, strict evaluator or artifact
    % registry consumes them. Leaving data rows unbound makes their actual
    % Channel/RF replay impossible to distinguish from component probes.
    dlTrials = localBindCoupledRuntimeIdentity(dlTrials, cfg, "DL");
    ulTrials = localBindCoupledRuntimeIdentity(ulTrials, cfg, "UL");
    csirsTrials = localBindCoupledRuntimeIdentity(csirsTrials, cfg, "CSI-RS");
    pbchTrials = localBindCoupledRuntimeIdentity(pbchTrials, cfg, "PBCH");
    prachTrials = localBindCoupledRuntimeIdentity(prachTrials, cfg, "PRACH");
    pdcchTrials = localBindCoupledRuntimeIdentity(pdcchTrials, cfg, "PDCCH");
    pucchTrials = localBindCoupledRuntimeIdentity(pucchTrials, cfg, "PUCCH");
    srsTrials = localBindCoupledRuntimeIdentity(srsTrials, cfg, "SRS");
    trsTrials = localBindCoupledRuntimeIdentity(trsTrials, cfg, "TRS");
else
    % CSI-RS is collected alongside isolated data trials, unlike the other
    % standalone reference collectors which bind their producer identity.
    % Own the fresh rows here before final CSV publication, but do not make
    % an isolated measurement eligible as connected shared-runtime evidence.
    csirsTrials = sixgr.truth.bindComponentExecutionIdentity(csirsTrials, cfg, "CSI-RS");
end
% Coupled live callbacks intentionally publish partial tables while slots
% execute.  Always replace those snapshots with the final canonical,
% identity-bound data tables; otherwise the CSV can lag the in-memory
% result and silently lose fields added during finalization.
sixgr.util.csvWriteTable(fDL, dlTrials, "PreserveSchema", true);
sixgr.util.csvWriteTable(fUL, ulTrials, "PreserveSchema", true);
localWriteOptionalFeatureTrialTable(cfg, "pbch", fPBCH, pbchTrials);
if localShouldExportSSBBeamSweep(cfg)
    if coupledTruth
        % These candidates already consumed the actual shared burst. Never
        % launch another channel/noise/acquisition episode while exporting
        % a connected run, or replace its failures with standalone results.
        ssbBeamSweep = sixgr.truth.exportReceivedSSBBeamSweep( ...
            fileparts(char(string(runFolder))), pbchTrials);
    else
        ssbBeamSweep = localCollectSSBBeamSweepArtifact(cfg, snrGrid(1), fSSBBeamSweep);
        localWriteSSBBeamSweepMirrors(runFolder, ssbBeamSweep);
    end
end
localWriteOptionalFeatureTrialTable(cfg, "prach", fPRACH, prachTrials);
if istable(prachCorrelationTrace) && ~isempty(prachCorrelationTrace)
    rootRunFolderForPRACHTrace = fileparts(char(string(runFolder)));
    layoutForPRACHTrace = sixgr.report.resultLayout(rootRunFolderForPRACHTrace);
    sixgr.util.csvWriteTable(fullfile(layoutForPRACHTrace.ReportCSVDir, "prach_correlation_trace.csv"), prachCorrelationTrace);
    sixgr.util.csvWriteTable(fullfile(layoutForPRACHTrace.ReportCSVDir, "prach_correlation_traces.csv"), prachCorrelationTrace);
end
localWriteRAEvidenceTables(fileparts(char(string(runFolder))), prachRAEvidence);
sixgr.util.csvWriteTable(fPDCCH, pdcchTrials);
standalonePUCCHRequired = logical(sixgr.util.structGet(cfg, ...
    "control_gating.pucch_required", sixgr.util.structGet(cfg, ...
    "run.controlGating.pucchRequired", false)));
if standalonePUCCHRequired || (istable(pucchTrials) && ~isempty(pucchTrials))
    sixgr.util.csvWriteTable(fPUCCH, pucchTrials);
elseif isfile(fPUCCH)
    delete(fPUCCH);
end
localWriteOptionalFeatureTrialTable(cfg, "srs", fSRS, srsTrials);
localWriteOptionalFeatureTrialTable(cfg, "trs", fTRS, trsTrials);
if coupledTruth
    localWriteOptionalCoupledControlMirror(cfg, "pbch", runFolder, ...
        "pbch_trials.csv", pbchTrials);
    localWriteOptionalCoupledControlMirror(cfg, "prach", runFolder, ...
        "prach_trials.csv", prachTrials);
    localWriteCoupledControlMirror(runFolder, "pdcch_trials.csv", pdcchTrials);
    if standalonePUCCHRequired || (istable(pucchTrials) && ~isempty(pucchTrials))
        localWriteCoupledControlMirror(runFolder, "pucch_trials.csv", pucchTrials);
    end
    localWriteOptionalCoupledControlMirror(cfg, "srs", runFolder, ...
        "srs_trials.csv", srsTrials);
    localWriteOptionalCoupledControlMirror(cfg, "trs", runFolder, ...
        "trs_trials.csv", trsTrials);
    localWriteCoupledControlMirror(runFolder, "csi_rs_trials.csv", csirsTrials);
end
if istable(csirsTrials) && ~isempty(csirsTrials)
    sixgr.util.csvWriteTable(fCSIRS, csirsTrials, "PreserveSchema", true);
end
if coupledTruth
    rootRunFolderForRS = fileparts(char(string(runFolder)));
    layoutForRS = sixgr.report.resultLayout(rootRunFolderForRS);
    sixgr.util.csvWriteTable(fullfile(layoutForRS.AirInterfaceCSVDir, "csi_feedback_reports.csv"), csiFeedbackReports);
    sixgr.util.csvWriteTable(fullfile(layoutForRS.ControlCSVDir, "csi_feedback_reports.csv"), csiFeedbackReports);
    sixgr.util.csvWriteTable(fullfile(layoutForRS.ReportCSVDir, "reference_signal_measurements.csv"), referenceSignalMeasurements);
    sixgr.util.csvWriteTable(fullfile(layoutForRS.ControlCSVDir, "reference_signal_measurements.csv"), referenceSignalMeasurements);
end

[outDLConst,outULConst] = sixgr.truth.constellationArtifactPaths(cfg,csvDir);
if istable(dlConst) && ~isempty(dlConst)
    sixgr.util.csvWriteTable(outDLConst, localDownsampleConstellationTable(dlConst, 2500), "PreserveSchema", true);
else
    outDLConst = "";
end

if istable(ulConst) && ~isempty(ulConst)
    sixgr.util.csvWriteTable(outULConst, localDownsampleConstellationTable(ulConst, 2500), "PreserveSchema", true);
else
    outULConst = "";
end

out = struct();
out.DL = dlTrials;
out.UL = ulTrials;
if ~coupledTruth
    out.ObservedREAllocationTable=localAppendCompatTable(dlObservedRE,ulObservedRE);
    sixgr.truth.writeObservedREAllocationArtifacts(out.ObservedREAllocationTable,cfg, ...
        sixgr.report.resultLayout(fileparts(char(string(runFolder)))));
end
out.PBCH = pbchTrials;
out.PRACH = prachTrials;
out.RAEvidenceTables = prachRAEvidence;
out.PRACHCorrelationTrace = prachCorrelationTrace;
out.PDCCH = pdcchTrials;
out.PUCCH = pucchTrials;
out.SRS = srsTrials;
out.CSIRS = csirsTrials;
out.TRS = trsTrials;
out.CSIFeedbackReports = csiFeedbackReports;
out.ReferenceSignalMeasurements = referenceSignalMeasurements;
out.DLPath = fDL;
out.ULPath = fUL;
if ~coupledTruth && logical(sixgr.util.structGet(cfg,'outputs.antennaPatternSamplesEnabled',false))
    out.AppliedDataPrecoder=sixgr.report.exportIsolatedDataPrecoderArchives( ...
        fileparts(char(string(runFolder))),dlTrials,ulTrials);
end
out.DLConstellation = dlConst;
out.ULConstellation = ulConst;
% Keep exact retained receiver samples through final publication. These are
% independent-link previews, not shared-stream or SLS abstraction evidence.
out.WaveformPreviewTable = localAppendCompatTable(dlWaveformPreview, ulWaveformPreview);
out.DLConstellationPath = outDLConst;
out.ULConstellationPath = outULConst;
out.PBCHPath = fPBCH;
out.SSBBeamSweep = ssbBeamSweep;
out.SSBBeamSweepPath = fSSBBeamSweep;
out.PRACHPath = fPRACH;
if istable(prachCorrelationTrace) && ~isempty(prachCorrelationTrace)
    rootRunFolderForPRACHTrace = fileparts(char(string(runFolder)));
    layoutForPRACHTrace = sixgr.report.resultLayout(rootRunFolderForPRACHTrace);
    out.PRACHCorrelationTracePath = fullfile(layoutForPRACHTrace.ReportCSVDir, "prach_correlation_trace.csv");
else
    out.PRACHCorrelationTracePath = "";
end
out.PDCCHPath = fPDCCH;
out.PUCCHPath = fPUCCH;
out.SRSPath = fSRS;
out.CSIRSPath = fCSIRS;
out.TRSPath = fTRS;
out.LiveSweepPath = liveSweepPath;
out.MultiUserDL = dlUserSummary;
out.MultiUserUL = ulUserSummary;
out.CoupledRuntime = coupledRuntime;
stream=sixgr.util.structGet(coupledRuntime,'SharedWaveformStream',[]);
if isa(stream,'sixgr.truth.CoupledWaveformStream')
    out.RFEndpointExecutionEvidence=stream.Physical.readRFExecutionLedger();
end
out.PHYSignalDiagnostics = struct("DL", dlSignalDiagnostic, "UL", ulSignalDiagnostic);
out.DLSignalDiagnostic = dlSignalDiagnostic;
out.ULSignalDiagnostic = ulSignalDiagnostic;
out.InitialAccessLifecycleTraceTable = sixgr.util.structGet(coupledRuntime, "InitialAccessLifecycleTraceTable", table());
out.MobilityArtifacts = mobilityArtifacts;
if logical(multiUser.Enabled) && logical(multiUser.SaveUserTables)
    out.MultiUserSummaryPath = fullfile(csvDir, "multiuser_user_summary.csv");
    userSummary = localMergeMultiUserSummaries(dlUserSummary, ulUserSummary, multiUser);
    sixgr.util.csvWriteTable(out.MultiUserSummaryPath, userSummary);
end
try
    sixgr.truth.sanitizeLLSArtifactCSVs(runFolder);
catch
end
end

function out = localAugmentRawTrialsWithRefinedSweep(cfg, runFolder, rawTrials, nFrames, snrGrid_dB, multiUser)
out = rawTrials;
snrGrid = unique(sort(double(snrGrid_dB(:))));
if isempty(snrGrid)
    return;
end
csvDir = fullfile(runFolder, "csv");
sixgr.util.ensureFolder(csvDir);

if logical(multiUser.Enabled)
    [dlTrials, dlUserSummary, dlConst, ~, ~, dlWaveT, dlObservedRE] = localCollectMultiUserLinkTrialsAcrossSweep(cfg, multiUser, "DL", nFrames, snrGrid);
    [ulTrials, ulUserSummary, ulConst, ~, ~, ulWaveT, ulObservedRE] = localCollectMultiUserLinkTrialsAcrossSweep(cfg, multiUser, "UL", nFrames, snrGrid);
    out.MultiUserDL = localAppendCompatTable(sixgr.util.structGet(rawTrials, "MultiUserDL", table()), dlUserSummary);
    out.MultiUserUL = localAppendCompatTable(sixgr.util.structGet(rawTrials, "MultiUserUL", table()), ulUserSummary);
else
    [dlTrials, dlConst, ~, ~, dlWaveT, dlObservedRE] = localCollectSingleUserLinkTrialsAcrossSweep(cfg, "DL", nFrames, snrGrid);
    [ulTrials, ulConst, ~, ~, ulWaveT, ulObservedRE] = localCollectSingleUserLinkTrialsAcrossSweep(cfg, "UL", nFrames, snrGrid);
end

srsTrials = localCollectTrialsAcrossSweep(@(snr) localCollectSRSTrials(cfg, snr, max(6, ceil(nFrames/3))), snrGrid, "", "SRS", cfg);

out.DL = localAppendCompatTable(rawTrials.DL, dlTrials);
out.UL = localAppendCompatTable(rawTrials.UL, ulTrials);
out.ObservedREAllocationTable=localAppendCompatTable( ...
    sixgr.util.structGet(rawTrials,'ObservedREAllocationTable',table()), ...
    localAppendCompatTable(dlObservedRE,ulObservedRE));
sixgr.truth.writeObservedREAllocationArtifacts(out.ObservedREAllocationTable,cfg, ...
    sixgr.report.resultLayout(fileparts(char(string(runFolder)))));
out.WaveformPreviewTable = localAppendCompatTable( ...
    sixgr.util.structGet(rawTrials, "WaveformPreviewTable", table()), ...
    localAppendCompatTable(dlWaveT, ulWaveT));
out.DLConstellation = localAppendCompatTable( ...
    sixgr.util.structGet(rawTrials, "DLConstellation", table()), dlConst);
out.ULConstellation = localAppendCompatTable( ...
    sixgr.util.structGet(rawTrials, "ULConstellation", table()), ulConst);
out.SRS = localAppendCompatTable(sixgr.util.structGet(rawTrials, "SRS", table()), srsTrials);

out.DL = localSortTrialTableBySweep(out.DL);
out.UL = localSortTrialTableBySweep(out.UL);
out.SRS = localSortTrialTableBySweep(out.SRS);
out.DL = localForceLinkTrialSourceArtifact(out.DL, "DL");
out.UL = localForceLinkTrialSourceArtifact(out.UL, "UL");
out.DL = sixgr.truth.canonicalizeLLSLiveSignalChainTable("dl_pdsch_trials", out.DL);
out.UL = sixgr.truth.canonicalizeLLSLiveSignalChainTable("ul_pusch_trials", out.UL);
out.DL = localForceLinkTrialSourceArtifact(out.DL, "DL");
out.UL = localForceLinkTrialSourceArtifact(out.UL, "UL");
out.SRS = sixgr.truth.CoupledTruthRuntime.canonicalizePersistedControlReferenceTable("SRS", out.SRS);

sixgr.util.csvWriteTable(fullfile(csvDir, "dl_pdsch_trials.csv"), ...
    out.DL, "PreserveSchema", true);
sixgr.util.csvWriteTable(fullfile(csvDir, "ul_pusch_trials.csv"), ...
    out.UL, "PreserveSchema", true);
if istable(out.SRS) && ~isempty(out.SRS)
    sixgr.util.csvWriteTable(fullfile(csvDir, "srs_trials.csv"), out.SRS,"RoundTripNumericText",true);
end
if logical(multiUser.Enabled) && isfield(out, "MultiUserSummaryPath") && strlength(string(out.MultiUserSummaryPath)) > 0
    userSummary = localMergeMultiUserSummaries(out.MultiUserDL, out.MultiUserUL, multiUser);
    sixgr.util.csvWriteTable(char(string(out.MultiUserSummaryPath)), userSummary);
end
end

function tf = localIsMySQLWebMode(cfg)
tf = lower(string(sixgr.util.structGet(cfg, "outputs.storageBackend", "filesystem"))) == "mysql_web";
end

function T = localDownsampleConstellationTable(Tin, maxRows)
T = Tin;
if ~(istable(Tin) && ~isempty(Tin))
    return;
end
% A preview limit cannot silently downgrade an explicit full observation.
% Live callbacks and final persistence share this rule.
if ismember("CaptureScope", string(Tin.Properties.VariableNames)) && ...
        any(string(Tin.CaptureScope) == "full_allocation_paired_symbols")
    return;
end
maxRows = max(1, round(double(maxRows)));
if height(Tin) <= maxRows
    return;
end
idx = unique(round(linspace(1, height(Tin), maxRows)));
T = Tin(idx, :);
end

function localPublishAnchorKPIArtifacts(runFolder, res)
kpi = sixgr.util.structGet(res, "KPITable", table());
if ~(istable(kpi) && ~isempty(kpi))
    return;
end
sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "link_anchor_kpis.csv"), kpi);
end

function localPublishRuntimeReferenceArtifacts(runFolder, cfg, multiUser, rawTrials)
if nargin < 4
    rawTrials = struct();
end
rootRunFolder = fileparts(char(string(runFolder)));
layout = sixgr.report.resultLayout(rootRunFolder);

runtimeT = localBuildRuntimeOperatingModeTable(cfg, multiUser, rawTrials);
if ~isempty(runtimeT)
    sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "runtime_operating_mode.csv"), runtimeT);
end

layoutT = localBuildDeploymentLayoutReferenceTable(cfg, multiUser);
if ~isempty(layoutT)
    sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "deployment_layout_reference.csv"), layoutT);
end

cqiT = localBuildCQITableReferenceTable(cfg);
if ~isempty(cqiT)
    sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "cqi_table_reference.csv"), cqiT);
end

mcsT = localBuildMCSTableReferenceTable(cfg);
if ~isempty(mcsT)
    sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "mcs_table_reference.csv"), mcsT);
end
end

function localPublishWaveformBundleStageStatus(runFolder, status)
if ~sixgr.util.persistenceEnabled()
    return;
end
rootRunFolder = localNormalizeBundleRootRunFolder(runFolder);
layout = sixgr.report.resultLayout(rootRunFolder);
statusPath = fullfile(layout.ReportCSVDir, "live_stage_status.csv");
status = localNormalizeStageStatusStruct(status, localReadStageStatusStruct(statusPath));
status = localReconcileStageStatusControlAttemptCounts(status, rootRunFolder);
status = sixgr.truth.canonicalizeRuntimeStatusSnapshot(status, rootRunFolder);
T = struct2table(orderfields(status));
if height(T) ~= 1
    error("sixgr:truth:RuntimeStatusRowCountMismatch", ...
        "Runtime status serialization produced %d rows; exactly one measured snapshot is required.", ...
        height(T));
end
sixgr.util.csvWriteTable(statusPath, T);
localPublishWaveformBundleRuntimeStatus(status);
end

function status = localReconcileStageStatusControlAttemptCounts(status, rootRunFolder)
if nargin < 2 || strlength(string(rootRunFolder)) == 0
    return;
end
layout = sixgr.report.resultLayout(rootRunFolder);
pairs = {
    "PBCH", "PBCHAttemptCount";
    "PRACH", "PRACHAttemptCount";
    "SRS", "SRSAttemptCount";
    "TRS", "TRSAttemptCount"};
finalized = logical(sixgr.util.structGet(status, "FinalBundleReady", false));
for i = 1:size(pairs, 1)
    signal = lower(string(pairs{i, 1}));
    fieldName = char(pairs{i, 2});
    fileName = signal + "_trials.csv";
    % Stage status can be published with either the complete run root or
    % the air_interface domain as its local root.  The latter is the live
    % waveform-bundle layout used by the WebGUI.  Resolve both layouts
    % explicitly so finalization never resets a measured cumulative count
    % merely because it searched air_interface/air_interface/csv.
    airCount = localMaxCSVDataRowCount([ ...
        string(fullfile(layout.AirInterfaceCSVDir, fileName)); ...
        string(fullfile(rootRunFolder, "csv", fileName))]);
    controlCount = localMaxCSVDataRowCount([ ...
        string(fullfile(layout.ControlCSVDir, fileName)); ...
        string(fullfile(fileparts(rootRunFolder), "control", "csv", fileName))]);
    if finalized
        if isfinite(airCount) && isfinite(controlCount) && airCount ~= controlCount
            error("sixgr:truth:FinalControlMirrorRowCountMismatch", ...
                ["Final %s runtime table contains %d rows but its control " ...
                 "mirror contains %d rows."], upper(char(signal)), ...
                round(double(airCount)), round(double(controlCount)));
        end
        % Once the bundle is finalized, the canonical persisted runtime
        % table—not an earlier heartbeat or in-memory pre-canonical count—
        % is the row-count authority used by resumable validation.
        count = localMaxFiniteScalar(airCount, controlCount);
    else
        count = double(sixgr.util.structGet(status, fieldName, NaN));
        count = localMaxFiniteScalar(count, airCount, controlCount);
    end
    if ~isfinite(count)
        count = 0;
    end
    status.(fieldName) = double(count);
end
end

function n = localMaxCSVDataRowCount(filePaths)
n = NaN;
filePaths = unique(string(filePaths(:)), "stable");
for i = 1:numel(filePaths)
    if strlength(strtrim(filePaths(i))) == 0
        continue;
    end
    n = localMaxFiniteScalar(n, localCSVDataRowCount(filePaths(i)));
end
end

function n = localCSVDataRowCount(filePath)
n = NaN;
filePath = char(filePath);
if exist(filePath, "file") ~= 2
    return;
end
try
    opts = detectImportOptions(filePath, "FileType", "text", ...
        "Delimiter", ",", "VariableNamingRule", "preserve");
    T = readtable(filePath, opts);
    n = double(height(T));
catch
    try
        fid = fopen(filePath, "r");
        if fid < 0
            return;
        end
        c = onCleanup(@() fclose(fid));
        lines = 0;
        while ~feof(fid)
            fgetl(fid);
            lines = lines + 1;
        end
        n = max(0, double(lines - 1));
    catch
        n = NaN;
    end
end
end

function statusOut = localNormalizeStageStatusStruct(statusIn, statusBase)
statusOut = struct( ...
    "Stage", "", ...
    "CurrentDirection", "", ...
    "CurrentSNR_dB", NaN, ...
    "SweepPointIndex", NaN, ...
    "SweepPointCount", NaN, ...
    "CurrentUEIndex", NaN, ...
    "TotalUsers", NaN, ...
    "CurrentSlot", NaN, ...
    "TotalSlots", NaN, ...
    "CurrentFrame", NaN, ...
    "CompletedSlots", NaN, ...
    "DLCompletedFrames", NaN, ...
    "ULCompletedFrames", NaN, ...
    "CompletedFrames", NaN, ...
    "TotalFrames", NaN, ...
    "RunCompletion", NaN, ...
    "DLTrialRows", NaN, ...
    "ULTrialRows", NaN, ...
    "DLUniqueUsersPublished", NaN, ...
    "ULUniqueUsersPublished", NaN, ...
    "DLSummaryUsersPublished", NaN, ...
    "ULSummaryUsersPublished", NaN, ...
    "DLGrantCount", NaN, ...
    "ULGrantCount", NaN, ...
    "DLActiveUsers", NaN, ...
    "ULActiveUsers", NaN, ...
    "DLGrantedUsers", NaN, ...
    "ULGrantedUsers", NaN, ...
    "DLQueueBits", NaN, ...
    "ULQueueBits", NaN, ...
    "DLUserProgressFraction", NaN, ...
    "ULUserProgressFraction", NaN, ...
    "BidirectionalInterleavingEnabled", false, ...
    "AnchorKPIsReady", false, ...
    "DLTrialsReady", false, ...
    "ULTrialsReady", false, ...
    "ControlReady", false, ...
    "HARQReady", false, ...
    "BeamReady", false, ...
    "RFReady", false, ...
    "SweepReady", false, ...
    "FinalBundleReady", false, ...
    "Notes", "");
if nargin >= 2 && isstruct(statusBase) && ~isempty(fieldnames(statusBase))
    fBase = fieldnames(statusBase);
    for i = 1:numel(fBase)
        statusOut.(fBase{i}) = statusBase.(fBase{i});
    end
end
if ~(isstruct(statusIn) && ~isempty(fieldnames(statusIn)))
    return;
end
f = fieldnames(statusIn);
for i = 1:numel(f)
    statusOut.(f{i}) = statusIn.(f{i});
end
end

function status = localReadStageStatusStruct(statusPath)
status = struct();
if exist(statusPath, "file") ~= 2
    return;
end
try
    T = sixgr.util.csvReadTable(statusPath);
    if istable(T) && ~isempty(T)
        status = table2struct(T(1, :), "ToScalar", true);
    end
catch
    status = struct();
end
end

function rootRunFolder = localNormalizeBundleRootRunFolder(runFolder)
rootRunFolder = sixgr.truth.normalizeWaveformBundleRootRunFolder(runFolder);
end

function localPublishWaveformBundleRuntimeStatus(status)
if ~sixgr.db.isArtifactStoreActive()
    return;
end
try
    payload = struct();
    payload.stage = localStatusTextValue(sixgr.util.structGet(status, "Stage", ""));
    payload.current_slot = localStatusScalarValue(sixgr.util.structGet(status, "CurrentSlot", NaN));
    payload.total_slots = localStatusScalarValue(sixgr.util.structGet(status, "TotalSlots", NaN));
    payload.current_frame = localStatusScalarValue(sixgr.util.structGet(status, "CurrentFrame", NaN));
    payload.completed_frames = localStatusScalarValue(sixgr.util.structGet(status, "CompletedFrames", NaN));
    payload.completed_slots = localStatusScalarValue(sixgr.util.structGet(status, "CompletedSlots", NaN));
    payload.progress_source = localStatusTextValue(sixgr.util.structGet(status, "ProgressSource", ""));
    payload.progress_meaning = localStatusTextValue(sixgr.util.structGet(status, "ProgressMeaning", ""));
    payload.total_frames = localStatusScalarValue(sixgr.util.structGet(status, "TotalFrames", NaN));
    payload.completed_symbols = localStatusScalarValue(sixgr.util.structGet(status, "CompletedSymbols", NaN));
    payload.total_symbols = localStatusScalarValue(sixgr.util.structGet(status, "TotalSymbols", NaN));
    payload.current_slot_dl_symbols = localStatusScalarValue(sixgr.util.structGet(status, "CurrentSlotDLSymbols", NaN));
    payload.current_slot_ul_symbols = localStatusScalarValue(sixgr.util.structGet(status, "CurrentSlotULSymbols", NaN));
    payload.run_completion = localStatusScalarValue(sixgr.util.structGet(status, "RunCompletion", NaN));
    payload.current_direction = localStatusTextValue(sixgr.util.structGet(status, "CurrentDirection", ""));
    payload.active_ue_count = localStatusMaxValue([ ...
        sixgr.util.structGet(status, "DLActiveUsers", NaN), ...
        sixgr.util.structGet(status, "ULActiveUsers", NaN)]);
    payload.grant_count_slot = localStatusMaxValue([ ...
        sixgr.util.structGet(status, "DLGrantCount", NaN), ...
        sixgr.util.structGet(status, "ULGrantCount", NaN)]);
    payload.dl_trial_rows = localStatusScalarValue(sixgr.util.structGet(status, "DLTrialRows", NaN));
    payload.ul_trial_rows = localStatusScalarValue(sixgr.util.structGet(status, "ULTrialRows", NaN));
    payload.dl_queue_bits = localStatusScalarValue(sixgr.util.structGet(status, "DLQueueBits", NaN));
    payload.ul_queue_bits = localStatusScalarValue(sixgr.util.structGet(status, "ULQueueBits", NaN));
    payload.current_ue_index = localStatusScalarValue(sixgr.util.structGet(status, "CurrentUEIndex", NaN));
    payload.total_users = localStatusScalarValue(sixgr.util.structGet(status, "TotalUsers", NaN));
    payload.control_phase = localStatusTextValue(sixgr.util.structGet(status, "ControlPhase", ""));
    payload.pbch_attempt_count = localStatusScalarValue(sixgr.util.structGet(status, "PBCHAttemptCount", NaN));
    payload.prach_attempt_count = localStatusScalarValue(sixgr.util.structGet(status, "PRACHAttemptCount", NaN));
    payload.srs_attempt_count = localStatusScalarValue(sixgr.util.structGet(status, "SRSAttemptCount", NaN));
    payload.trs_attempt_count = localStatusScalarValue(sixgr.util.structGet(status, "TRSAttemptCount", NaN));
    payload.ssb_occasion_active = localStatusScalarValue(sixgr.util.structGet(status, "SSBOccasionActive", NaN));
    payload.active_ssb_indices_0based = localStatusTextValue(sixgr.util.structGet(status, "ActiveSSBIndices0Based", ""));
    payload.ssb_period_carrier_slots = localStatusScalarValue(sixgr.util.structGet(status, "SSBPeriodCarrierSlots", NaN));
    payload.notes = localStatusTextValue(sixgr.util.structGet(status, "Notes", ""));
    payload.run_profile = "waveform_bundle";
    payload.value_role = "measured";
    payload.value_source = "sixgr.truth.runWaveformLinkBundle";
    payload.value_status = "OK";
    payload.placeholder_flag = false;
    payload.fallback_flag = false;
    payload.config_only_flag = false;
    payload.timestamp_utc = sixgr.util.utcNowISO8601();
    sixgr.db.markRunStatus("running", payload);
catch ME
    localAppendRuntimeLog("WARN", "Waveform bundle runtime DB status heartbeat failed: %s", ME.message);
end
end

function value = localStatusTextValue(raw)
if ismissing(raw)
    value = "";
    return;
end
txt = string(raw);
if isempty(txt) || all(ismissing(txt))
    value = "";
    return;
end
value = char(txt(1));
end

function value = localStatusScalarValue(raw)
if isempty(raw) || all(ismissing(raw))
    value = NaN;
    return;
end
if ~(isnumeric(raw) || islogical(raw))
    value = NaN;
    return;
end
raw = double(raw(:));
raw = raw(isfinite(raw));
if isempty(raw)
    value = NaN;
    return;
end
value = double(raw(1));
end

function value = localStatusMaxValue(raw)
if isempty(raw)
    value = NaN;
    return;
end
if ~(isnumeric(raw) || islogical(raw))
    value = NaN;
    return;
end
raw = double(raw(:));
raw = raw(isfinite(raw));
if isempty(raw)
    value = NaN;
    return;
end
value = double(max(raw));
end

function [rows, stageOrder] = localAppendRuntimeStageProfile(rootRunFolder, rows, stageOrder, stageName, stageElapsed_s, bundleElapsed_s, notes)
stageOrder = double(stageOrder) + 1;
row = localEmptyRuntimeStageRow();
row.StageOrder = double(stageOrder);
row.StageName = string(stageName);
row.StageElapsed_s = double(stageElapsed_s);
row.BundleElapsed_s = double(bundleElapsed_s);
row.CompletedUTC = sixgr.util.utcNowISO8601();
row.Notes = string(notes);
rows(end+1,1) = row; %#ok<AGROW>
layout = sixgr.report.resultLayout(rootRunFolder);
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "runtime_stage_profile.csv"), struct2table(rows));
end

function row = localEmptyRuntimeStageRow()
row = struct( ...
    "StageOrder", NaN, ...
    "StageName", "", ...
    "StageElapsed_s", NaN, ...
    "BundleElapsed_s", NaN, ...
    "CompletedUTC", "", ...
    "Notes", "");
end

function T = localBuildRuntimeOperatingModeTable(cfg, multiUser, rawTrials)
if nargin < 3
    rawTrials = struct();
end
rows = repmat(struct( ...
    "Direction", "", ...
    "LinkAdaptationMode", "", ...
    "ConfiguredLinkAdaptationMode", "", ...
    "LinkAdaptationDomain", "", ...
    "DirectionPolicy", "", ...
    "ActualMCSSelectionMode", "", ...
    "ConfiguredMCSSelectionPolicy", "", ...
    "ConfiguredMCSSelectionMode", "", ...
    "SchedulerGrantMCSSelectionMode", "", ...
    "RequestedOperatingPointSource", "", ...
    "AppliedOperatingPointSource", "", ...
    "ActualMCSSelectionModeAuthority", "", ...
    "CQITable", "", ...
    "MCSTable", "", ...
    "MCSSelectionSource", "", ...
    "MCSValueStatus", "", ...
    "OLLADomain", "", ...
    "CalibrationProfile", "", ...
    "FixedMCSIndex", NaN, ...
    "FixedModulation", "", ...
    "FixedTargetCodeRate", NaN, ...
    "Numerology_mu", NaN, ...
    "SCS_kHz", NaN, ...
    "ConfiguredBandwidth_Hz", NaN, ...
    "CyclicPrefix", "", ...
    "SlotDuration_ms", NaN, ...
    "SlotsPerFrame", NaN, ...
    "SymbolsPerSlot", NaN, ...
    "ConfiguredGridNumRBs", NaN, ...
    "ActiveGridNumRBs", NaN, ...
    "ActiveGridSource", "", ...
    "NumerologySource", "", ...
    "TimingInterpretationSource", "", ...
    "CQISource", "", ...
    "WidebandSINRMargin_dB", NaN, ...
    "MultiUserEnabled", false, ...
    "ConfiguredUsers", NaN, ...
    "BrowserExecutionMode", "", ...
    "UserExecutionModel", "", ...
    "ConfiguredLayers", NaN, ...
    "NoiseOperatingMode", "", ...
    "ConfiguredSNRMetadataOnly", false, ...
    "DopplerSourceMode", "", ...
    "ResolvedDopplerHz", NaN, ...
    "MobilitySpeed_kmh", NaN, ...
    "InterferenceMode", "", ...
    "FullInterfererChannelTruthUsed", false, ...
    "AntennaRuntimeObjectSource", "", ...
    "ChannelArrayModel", "", ...
    "ChannelObjectSource", "", ...
    "ChannelObjectClass", "", ...
    "ChannelArrayHandlingStatus", "", ...
    "ChannelArrayHandlingBlocker", "", ...
    "ChannelGeometryCouplingLevel", "", ...
    "GeometryAdapterType", "", ...
    "GeometryAdapterSource", "", ...
    "GeometryAdapterLimitation", "", ...
    "GeometryAdapterPortMapping", "", ...
    "ChannelUsesCountOnlyAntennaModel", false, ...
    "ChannelUsesSameRuntimeAntennaAssumptions", false, ...
    "ElementPatternChannelApplicability", "", ...
    "AntennaChannelConsistencyStatus", "", ...
    "AntennaChannelConsistencyReason", "", ...
    "InterferenceChannelObjectSource", "", ...
    "InterferenceChannelObjectClass", "", ...
    "InterferenceChannelArrayHandlingStatus", "", ...
    "InterferenceChannelArrayHandlingBlocker", "", ...
    "InterferenceUsesSameRuntimeAntennaAssumptions", false, ...
    "InterferencePathUsesSameArrayAssumptions", false, ...
    "ControlIntegrationMode", "", ...
    "PBCHMode", "", ...
    "PRACHMode", "", ...
    "PDCCHMode", "", ...
    "PUCCHMode", "", ...
    "SRSMode", "", ...
    "TRSMode", "", ...
    "TRSRuntimeConsumer", "", ...
    "TRSInfluencedDecision", false, ...
    "TRSInfluenceDefinition", "", ...
    "TRSReceiverIntegrationStatus", "", ...
    "TRSReceiverIntegrationBlocker", "", ...
    "PBCHGatingActive", false, ...
    "PRACHGatingActive", false, ...
    "PDCCHGatingActive", false, ...
    "SRSGatingActive", false, ...
    "TRSGatingActive", false, ...
    "ParallelExecutionActive", false, ...
    "ConfiguredWorkers", NaN, ...
    "EffectiveWorkers", NaN, ...
    "ParallelDisabledReason", "", ...
    "ConfiguredBatchSizeLinks", NaN, ...
    "ConfiguredSchedulerType", "", ...
    "ConfiguredMeasurementPeriodSlots", NaN, ...
    "ConfiguredBeamUpdatePeriodSlots", NaN, ...
    "ConfiguredTrafficModel", "", ...
    "ConfiguredTrafficTransport", "", ...
    "ConfiguredTrafficFlowDirection", "", ...
    "ConfiguredTrafficTargetRate_Mbps", NaN, ...
    "TrafficFlowSource", "", ...
    "TrafficFlowDerivationMode", "", ...
    "TrafficFlowResolvedFlag", false, ...
    "CoupledGrantExecutionMode", "", ...
    "RunStateSource", "", ...
    "SlotTraceSource", "", ...
    "SlotTraceRows", NaN, ...
    "CanonicalSlotTraceFirst", false, ...
    "TruthModeIndependentSweepForbidden", false, ...
    "ExecutionBackend", "", ...
    "PHYMode", "", ...
    "WaveformBacked", false, ...
    "WaveformPHYActive", false, ...
    "ProxyPHYActive", true, ...
    "FallbackUsed", true), 2, 1);
noiseMode = localResolveNoiseOperatingMode(cfg);
fixedLinkCampaignOnly = logical(sixgr.util.structGet(cfg, ...
    "run.fixedLinkCampaignOnly", false));
dopplerMode = localResolveDopplerSourceMode(cfg);
dopplerHz = double(sixgr.util.structGet(cfg, "channel.doppler_Hz", ...
    sixgr.util.structGet(cfg, "channel.dopplerHz", sixgr.util.structGet(cfg, "channel.fading.maxDoppler_Hz", NaN))));
speedRange = double(sixgr.util.structGet(cfg, "scenario.mobility.speed_kmh", [NaN NaN]));
mobilitySpeedKmh = NaN;
if ~isempty(speedRange)
    mobilitySpeedKmh = speedRange(1);
end
interferenceMode = ternaryInterferenceMode(cfg);
controlMode = localResolveControlIntegrationMode(cfg, multiUser);
pbchGating = localResolveControlGatingFlag(cfg, "run.controlGating.pbchRequired", "control_gating.pbch_required");
prachGating = localResolveControlGatingFlag(cfg, "run.controlGating.prachRequired", "control_gating.prach_required");
pdcchGating = localResolveControlGatingFlag(cfg, "run.controlGating.pdcchRequired", "control_gating.pdcch_required");
srsGating = localResolveControlGatingFlag(cfg, "run.controlGating.srsRequired", "control_gating.srs_required");
trsGating = localResolveControlGatingFlag(cfg, "run.controlGating.trsRequired", "control_gating.trs_required");
browserExecutionMode = string(sixgr.util.structGet(cfg, "run.executionMode", "LLS"));
configuredWorkers = double(sixgr.util.structGet(cfg, "run.parallelRequestedWorkers", ...
    sixgr.util.structGet(cfg, "run.numWorkers", NaN)));
requestedWorkers = double(sixgr.util.structGet(cfg, "run.numWorkers", configuredWorkers));
requestedParallel = logical(sixgr.util.structGet(cfg, "run.useParallel", false)) && ...
    isfinite(requestedWorkers) && requestedWorkers > 1;
[parallelActive, effectiveWorkers, actualParallelReason] = localResolveActualCoupledParallelState(cfg, requestedParallel, requestedWorkers);
parallelDisabledReason = char(string(sixgr.util.structGet(cfg, "run.parallelDisabledReason", "")));
if requestedParallel && ~parallelActive && strlength(strtrim(string(parallelDisabledReason))) == 0
    parallelDisabledReason = char(actualParallelReason);
end
configuredBatchSizeLinks = double(sixgr.util.structGet(cfg, "run.batchSizeLinks", NaN));
configuredSchedulerType = char(string(sixgr.util.structGet(cfg, "system.scheduler.type", ...
    sixgr.util.structGet(cfg, "mac.scheduler.type", ""))));
configuredMeasurementPeriodSlots = double(sixgr.util.structGet(cfg, "system.measurement.periodSlots", NaN));
configuredBeamUpdatePeriodSlots = double(sixgr.util.structGet(cfg, "system.beam.updatePeriod_slots", NaN));
configuredTrafficModel = char(string(sixgr.util.structGet(cfg, "traffic.model", "")));
configuredTrafficTransport = char(string(sixgr.util.structGet(cfg, "traffic.transport", "")));
configuredTrafficFlowDirection = char(string(sixgr.util.structGet(cfg, "traffic.flowDirection", "")));
configuredTrafficTargetRate = double(sixgr.util.structGet(cfg, "traffic.targetRate_Mbps", NaN));
trafficFlowSource = char(string(sixgr.util.structGet(cfg, "traffic.flowSource", "")));
trafficFlowDerivationMode = char(string(sixgr.util.structGet(cfg, "traffic.flowDerivationMode", "")));
trafficFlowResolvedFlag = logical(sixgr.util.structGet(cfg, "traffic.flowResolvedFlag", false));
coupledRuntime = sixgr.util.structGet(rawTrials, "CoupledRuntime", struct());
slotTraceT = sixgr.util.structGet(coupledRuntime, "SlotTraceTable", table());
slotTraceRows = height(slotTraceT);
userExecutionModel = string(sixgr.util.structGet(multiUser, "ExecutionModel", "independent_link_sweep"));
grantExecutionMode = "serial_per_grant_execution";
if parallelActive
    grantExecutionMode = "parallel_worker_batch_serial_commit";
elseif isfinite(configuredBatchSizeLinks) && configuredBatchSizeLinks > 1
    grantExecutionMode = "serial_chunked_grant_execution";
end
executionBackend = "WAVEFORM_LINK_BUNDLE";
phyMode = "COUPLED_WAVEFORM_GRANT_EXECUTION";
for i = 1:2
    direction = "DL";
    if i == 2
        direction = "UL";
    end
    [configuredMode, policy, configuredSelectionMode] = localResolveLinkAdaptationTokens(cfg, direction);
    requestedOperatingPointSource = localResolveOperatingPointSourceToken(configuredSelectionMode, policy);
    runtimeEvidence = localSummarizeRuntimeOperatingPointEvidence(rawTrials, direction);
    channelEvidence = localSummarizeChannelArrayEvidence(rawTrials, direction);
    rows(i).Direction = char(direction);
    rows(i).LinkAdaptationMode = char(policy);
    rows(i).ConfiguredLinkAdaptationMode = char(configuredMode);
    rows(i).LinkAdaptationDomain = char(sixgr.link.resolveLinkAdaptationDomain(cfg, direction));
    rows(i).DirectionPolicy = char(policy);
    rows(i).ActualMCSSelectionMode = "";
    rows(i).ConfiguredMCSSelectionPolicy = char(configuredSelectionMode);
    rows(i).ConfiguredMCSSelectionMode = char(configuredSelectionMode);
    rows(i).SchedulerGrantMCSSelectionMode = "";
    rows(i).RequestedOperatingPointSource = char(requestedOperatingPointSource);
    rows(i).AppliedOperatingPointSource = "";
    rows(i).ActualMCSSelectionModeAuthority = "runtime_trial_evidence_pending";
    rows(i).CQITable = char(localResolveCQITable(cfg, direction));
    rows(i).MCSTable = char(localResolveMCSTable(cfg, direction));
    rows(i).MCSSelectionSource = char(localResolveOperatingPointSourceToken(configuredSelectionMode, policy));
    rows(i).MCSValueStatus = "";
    rows(i).OLLADomain = char(localResolveRuntimeOLLADomainToken(cfg, direction));
    rows(i).CalibrationProfile = char(localResolveRuntimeCalibrationProfileToken(cfg, direction));
    rows(i).Numerology_mu = double(sixgr.util.structGet(cfg, "phy.numerology.mu", NaN));
    rows(i).SCS_kHz = double(sixgr.util.structGet(cfg, "phy.numerology.scs_kHz", NaN));
    rows(i).ConfiguredBandwidth_Hz = double(sixgr.util.structGet(cfg, ...
        "channel.bandwidth_Hz", NaN));
    rows(i).CyclicPrefix = char(string(sixgr.util.structGet(cfg, ...
        "phy.carrier.CyclicPrefix", "")));
    rows(i).SlotDuration_ms = double(sixgr.util.structGet(cfg, "phy.numerology.slotDuration_ms", NaN));
    rows(i).SlotsPerFrame = double(sixgr.util.structGet(cfg, "phy.numerology.slotsPerFrame", NaN));
    rows(i).SymbolsPerSlot = double(sixgr.util.structGet(cfg, "phy.numerology.symbolsPerSlot", NaN));
    rows(i).ConfiguredGridNumRBs = double(sixgr.util.structGet(cfg, "phy.numerology.configuredGridNumRBs", ...
        sixgr.util.structGet(cfg, "phy.carrier.NSizeGrid", NaN)));
    rows(i).ActiveGridNumRBs = double(sixgr.util.structGet(cfg, "phy.numerology.activeGridNumRBs", ...
        sixgr.util.structGet(cfg, "phy.carrier.NSizeGrid", NaN)));
    rows(i).ActiveGridSource = char(string(sixgr.util.structGet(cfg, "phy.numerology.activeGridSource", "configured_n_size_grid")));
    rows(i).NumerologySource = char(string(sixgr.util.structGet(cfg, "phy.numerology.numerologySource", "carrier_subcarrier_spacing_khz")));
    rows(i).TimingInterpretationSource = char(string(sixgr.util.structGet(cfg, "phy.numerology.timingInterpretationSource", "nr_mu_from_scs")));
    rows(i).CQISource = char(string(sixgr.util.structGet(cfg, "phy.linkAdaptation.cqiSource", "csi_feedback")));
    rows(i).WidebandSINRMargin_dB = double(sixgr.util.structGet(cfg, "phy.csi.widebandSINRMargin_dB", NaN));
    rows(i).MultiUserEnabled = logical(sixgr.util.structGet(multiUser, "Enabled", false));
    rows(i).ConfiguredUsers = double(sixgr.util.structGet(multiUser, "NumUsers", 1));
    rows(i).BrowserExecutionMode = char(browserExecutionMode);
    rows(i).UserExecutionModel = char(userExecutionModel);
    rows(i).NoiseOperatingMode = char(noiseMode);
    rows(i).ConfiguredSNRMetadataOnly = noiseMode == "receiver_noise_figure_thermal_noise";
    rows(i).DopplerSourceMode = char(dopplerMode);
    rows(i).ResolvedDopplerHz = double(dopplerHz);
    rows(i).MobilitySpeed_kmh = double(mobilitySpeedKmh);
    rows(i).InterferenceMode = char(interferenceMode);
    rows(i).FullInterfererChannelTruthUsed = interferenceMode == "full_per_link_channel_waveform_sum";
    rows(i).AntennaRuntimeObjectSource = char(string(channelEvidence.AntennaRuntimeObjectSource));
    rows(i).ChannelArrayModel = char(string(channelEvidence.ChannelArrayModel));
    rows(i).ChannelObjectSource = char(string(channelEvidence.ChannelObjectSource));
    rows(i).ChannelObjectClass = char(string(channelEvidence.ChannelObjectClass));
    rows(i).ChannelArrayHandlingStatus = char(string(channelEvidence.ChannelArrayHandlingStatus));
    rows(i).ChannelArrayHandlingBlocker = char(string(channelEvidence.ChannelArrayHandlingBlocker));
    rows(i).ChannelGeometryCouplingLevel = char(string(channelEvidence.ChannelGeometryCouplingLevel));
    rows(i).GeometryAdapterType = char(string(channelEvidence.GeometryAdapterType));
    rows(i).GeometryAdapterSource = char(string(channelEvidence.GeometryAdapterSource));
    rows(i).GeometryAdapterLimitation = char(string(channelEvidence.GeometryAdapterLimitation));
    rows(i).GeometryAdapterPortMapping = char(string(channelEvidence.GeometryAdapterPortMapping));
    rows(i).ChannelUsesCountOnlyAntennaModel = logical(channelEvidence.ChannelUsesCountOnlyAntennaModel);
    rows(i).ChannelUsesSameRuntimeAntennaAssumptions = logical(channelEvidence.ChannelUsesSameRuntimeAntennaAssumptions);
    rows(i).ElementPatternChannelApplicability = char(string(channelEvidence.ElementPatternChannelApplicability));
    rows(i).AntennaChannelConsistencyStatus = char(string(channelEvidence.AntennaChannelConsistencyStatus));
    rows(i).AntennaChannelConsistencyReason = char(string(channelEvidence.AntennaChannelConsistencyReason));
    rows(i).InterferenceChannelObjectSource = char(string(channelEvidence.InterferenceChannelObjectSource));
    rows(i).InterferenceChannelObjectClass = char(string(channelEvidence.InterferenceChannelObjectClass));
    rows(i).InterferenceChannelArrayHandlingStatus = char(string(channelEvidence.InterferenceChannelArrayHandlingStatus));
    rows(i).InterferenceChannelArrayHandlingBlocker = char(string(channelEvidence.InterferenceChannelArrayHandlingBlocker));
    rows(i).InterferenceUsesSameRuntimeAntennaAssumptions = logical(channelEvidence.InterferenceUsesSameRuntimeAntennaAssumptions);
    rows(i).InterferencePathUsesSameArrayAssumptions = logical(channelEvidence.InterferencePathUsesSameArrayAssumptions);
    rows(i).ControlIntegrationMode = char(controlMode);
    rows(i).PBCHMode = char(localResolveControlSidecarMode(cfg, "PBCH", controlMode));
    rows(i).PRACHMode = char(localResolveControlSidecarMode(cfg, "PRACH", controlMode));
    rows(i).PDCCHMode = char(localResolveControlSidecarMode(cfg, "PDCCH", controlMode));
    rows(i).PUCCHMode = char(localResolveControlSidecarMode(cfg, "PUCCH", controlMode));
    rows(i).SRSMode = char(localResolveControlSidecarMode(cfg, "SRS", controlMode));
    rows(i).TRSMode = char(localResolveControlSidecarMode(cfg, "TRS", controlMode));
    trsSummary = localResolveTRSOperatingModeSummary(rawTrials, direction, trsGating, cfg);
    rows(i).TRSRuntimeConsumer = char(string(trsSummary.TRSRuntimeConsumer));
    rows(i).TRSInfluencedDecision = logical(trsSummary.TRSInfluencedDecision);
    rows(i).TRSInfluenceDefinition = char(string(trsSummary.TRSInfluenceDefinition));
    rows(i).TRSReceiverIntegrationStatus = char(string(trsSummary.TRSReceiverIntegrationStatus));
    rows(i).TRSReceiverIntegrationBlocker = char(string(trsSummary.TRSReceiverIntegrationBlocker));
    rows(i).PBCHGatingActive = pbchGating;
    rows(i).PRACHGatingActive = prachGating;
    rows(i).PDCCHGatingActive = pdcchGating;
    rows(i).SRSGatingActive = srsGating;
    rows(i).TRSGatingActive = trsGating;
    rows(i).ParallelExecutionActive = parallelActive;
    rows(i).ConfiguredWorkers = configuredWorkers;
    rows(i).EffectiveWorkers = effectiveWorkers;
    rows(i).ParallelDisabledReason = parallelDisabledReason;
    rows(i).ConfiguredBatchSizeLinks = configuredBatchSizeLinks;
    rows(i).ConfiguredSchedulerType = configuredSchedulerType;
    rows(i).ConfiguredMeasurementPeriodSlots = configuredMeasurementPeriodSlots;
    rows(i).ConfiguredBeamUpdatePeriodSlots = configuredBeamUpdatePeriodSlots;
    rows(i).ConfiguredTrafficModel = configuredTrafficModel;
    rows(i).ConfiguredTrafficTransport = configuredTrafficTransport;
    rows(i).ConfiguredTrafficFlowDirection = configuredTrafficFlowDirection;
    rows(i).ConfiguredTrafficTargetRate_Mbps = configuredTrafficTargetRate;
    rows(i).TrafficFlowSource = trafficFlowSource;
    rows(i).TrafficFlowDerivationMode = trafficFlowDerivationMode;
    rows(i).TrafficFlowResolvedFlag = trafficFlowResolvedFlag;
    rows(i).CoupledGrantExecutionMode = char(grantExecutionMode);
    rows(i).RunStateSource = "reports/csv/run_state.csv";
    rows(i).SlotTraceSource = "reports/csv/slot_trace.csv";
    rows(i).SlotTraceRows = double(slotTraceRows);
    rows(i).CanonicalSlotTraceFirst = logical(userExecutionModel == "slot_coupled_truth" && slotTraceRows > 0);
    rows(i).TruthModeIndependentSweepForbidden = logical(userExecutionModel == "slot_coupled_truth");
    rows(i).ExecutionBackend = char(executionBackend);
    rows(i).PHYMode = char(phyMode);
    rows(i).WaveformBacked = true;
    rows(i).WaveformPHYActive = true;
    rows(i).ProxyPHYActive = false;
    rows(i).FallbackUsed = false;
    if strlength(strtrim(string(runtimeEvidence.LinkAdaptationMode))) > 0
        rows(i).LinkAdaptationMode = char(string(runtimeEvidence.LinkAdaptationMode));
    end
    if strlength(strtrim(string(runtimeEvidence.ActualMCSSelectionMode))) > 0
        rows(i).ActualMCSSelectionMode = char(string(runtimeEvidence.ActualMCSSelectionMode));
        rows(i).ActualMCSSelectionModeAuthority = "raw_trial_runtime_evidence";
    end
    if strlength(strtrim(string(runtimeEvidence.LinkAdaptationDomain))) > 0
        rows(i).LinkAdaptationDomain = char(string(runtimeEvidence.LinkAdaptationDomain));
    end
    if strlength(strtrim(string(runtimeEvidence.SchedulerGrantMCSSelectionMode))) > 0
        rows(i).SchedulerGrantMCSSelectionMode = char(string(runtimeEvidence.SchedulerGrantMCSSelectionMode));
    elseif fixedLinkCampaignOnly
        rows(i).SchedulerGrantMCSSelectionMode = ...
            "not_applicable_fixed_link_calibration_no_scheduler_grant";
    end
    if strlength(strtrim(string(runtimeEvidence.AppliedOperatingPointSource))) > 0
        rows(i).AppliedOperatingPointSource = char(string(runtimeEvidence.AppliedOperatingPointSource));
        if rows(i).ActualMCSSelectionModeAuthority == ""
            rows(i).ActualMCSSelectionModeAuthority = "raw_trial_runtime_evidence";
        end
    end
    if strlength(strtrim(string(runtimeEvidence.MCSSelectionSource))) > 0
        rows(i).MCSSelectionSource = char(string(runtimeEvidence.MCSSelectionSource));
    end
    if isfield(runtimeEvidence, "MCSValueStatus") && strlength(strtrim(string(runtimeEvidence.MCSValueStatus))) > 0
        rows(i).MCSValueStatus = char(string(runtimeEvidence.MCSValueStatus));
    end
    if strlength(strtrim(string(runtimeEvidence.OLLADomain))) > 0
        rows(i).OLLADomain = char(string(runtimeEvidence.OLLADomain));
    end
    if strlength(strtrim(string(runtimeEvidence.CalibrationProfile))) > 0
        rows(i).CalibrationProfile = char(string(runtimeEvidence.CalibrationProfile));
    end
    if direction == "UL"
        rows(i).FixedMCSIndex = double(sixgr.util.structGet(cfg, "phy.pusch.mcsIndex", NaN));
        rows(i).FixedModulation = char(string(sixgr.util.structGet(cfg, "phy.pusch.modulation", "")));
        rows(i).FixedTargetCodeRate = double(sixgr.util.structGet(cfg, "phy.pusch.codeRate", NaN));
        rows(i).ConfiguredLayers = double(sixgr.util.structGet(cfg, "phy.pusch.nLayers", NaN));
    else
        rows(i).FixedMCSIndex = double(sixgr.util.structGet(cfg, "phy.pdsch.mcsIndex", NaN));
        rows(i).FixedModulation = char(string(sixgr.util.structGet(cfg, "phy.pdsch.modulation", "")));
        rows(i).FixedTargetCodeRate = double(sixgr.util.structGet(cfg, "phy.pdsch.codeRate", NaN));
        rows(i).ConfiguredLayers = double(sixgr.util.structGet(cfg, "phy.pdsch.nLayers", NaN));
    end
end
T = struct2table(rows);
end

function mode = localResolveNoiseOperatingMode(cfg)
mode = string(sixgr.util.structGet(cfg, "run.noiseOperatingMode", "receiver_noise_figure_thermal_noise"));
if strlength(strtrim(mode)) == 0
    mode = "receiver_noise_figure_thermal_noise";
end
end

function tf = localUsesReceiverNoiseMeasurement(cfg, opt)
if nargin < 2 || ~isstruct(opt)
    opt = struct();
end
mode = string(sixgr.util.structGet(opt, "LinkQualityMode", ""));
if strlength(strtrim(mode)) == 0
    mode = localResolveNoiseOperatingMode(cfg);
end
mode = lower(strtrim(mode));
switch mode
    case {"receiver_noise_figure_thermal_noise","absolute_reference_esn0"}
        tf=true;
    case "standalone_awgn_snr_argument"
        tf=false;
    otherwise
        error('sixgr:truth:UnsupportedSharedNoisePowerReference','Unsupported receiver quality mode %s.',mode);
end
end

function grid = localResolvePhysicalOperatingPointGrid(cfg, opt)
grid = double(sixgr.util.structGet(opt, "LinkSNRGrid_dB", NaN));
grid = grid(:);
grid = grid(isfinite(grid));
if isempty(grid)
    grid = double(sixgr.util.structGet(opt, "LinkSNR_dB", ...
        sixgr.util.structGet(cfg, "channel.snr_dB", NaN)));
end
grid = grid(:);
grid = grid(isfinite(grid));
if isempty(grid)
    grid = NaN;
else
    grid = grid(1);
end
end

function varargout = localResolveDopplerSourceMode(varargin)
% Compatibility delegate; completion/publication has one production owner.
[varargout{1:nargout}] = sixgr.truth.SharedDataCompletionRuntime.resolveDopplerSourceMode(varargin{:});
end

function varargout = localRowsUseFadingChannelDoppler(varargin)
% Compatibility delegate; completion/publication has one production owner.
[varargout{1:nargout}] = sixgr.truth.SharedDataCompletionRuntime.rowsUseFadingChannelDoppler(varargin{:});
end

function mode = localResolveControlIntegrationMode(cfg, multiUser)
mode = "independent_signal_bundle";
if logical(sixgr.util.structGet(multiUser, "Enabled", false)) && ...
        string(sixgr.util.structGet(multiUser, "ExecutionModel", "")) == "slot_coupled_truth"
    if localResolveControlGatingFlag(cfg, "run.controlGating.trsRequired", "control_gating.trs_required")
        mode = "runtime_control_access_tracking_state_gated";
    else
        mode = "runtime_control_access_state_gated";
    end
end
end

function mode = localResolveControlSidecarMode(cfg, signalName, controlMode)
signalName = upper(string(signalName));
enabled = false;
    switch signalName
        case "PBCH"
            enabled = logical(sixgr.util.structGet(cfg, "phy.pbch.enable", false));
        case "PRACH"
            enabled = logical(sixgr.util.structGet(cfg, "phy.prach.enable", false));
        case "PDCCH"
            enabled = logical(sixgr.util.structGet(cfg, "phy.pdcch.enable", false));
        case "PUCCH"
            enabled = logical(sixgr.util.structGet(cfg, "phy.pucch.enable", false));
        case "SRS"
            enabled = logical(sixgr.util.structGet(cfg, "phy.srs.enable", false));
        case "TRS"
            enabled = logical(sixgr.util.structGet(cfg, "phy.trs.enable", false));
    end
if ~enabled
    mode = "disabled";
elseif signalName == "PBCH" && localResolveControlGatingFlag(cfg, "run.controlGating.pbchRequired", "control_gating.pbch_required")
    mode = "runtime_cell_search_gate";
elseif signalName == "PRACH" && localResolveControlGatingFlag(cfg, "run.controlGating.prachRequired", "control_gating.prach_required")
    if localShouldRunFourStepRAForPRACH(cfg)
        mode = "runtime_four_step_ra_msg1_to_msg4_shared_channel_gated";
    else
        mode = "runtime_prach_detector_success_gate";
    end
elseif signalName == "PDCCH" && localResolveControlGatingFlag(cfg, "run.controlGating.pdcchRequired", "control_gating.pdcch_required")
    mode = "grant_coupled_pdcch_dci_gating";
elseif signalName == "PUCCH"
    mode = "runtime_coupled_pucch_grant_waveform_execution";
elseif signalName == "SRS" && localResolveControlGatingFlag(cfg, "run.controlGating.srsRequired", "control_gating.srs_required")
    mode = "srs_freshness_csi_gate";
elseif signalName == "TRS" && localResolveControlGatingFlag(cfg, "run.controlGating.trsRequired", "control_gating.trs_required")
    mode = "runtime_shared_receiver_tracking_state_gate";
elseif signalName == "TRS"
    mode = "runtime_shared_receiver_tracking_observer";
else
    mode = "enabled";
end
end

function tf = localResolveControlGatingFlag(cfg, resolvedPath, legacyPath)
value = sixgr.util.structGet(cfg, resolvedPath, []);
if isempty(value)
    value = sixgr.util.structGet(cfg, legacyPath, []);
end
if isempty(value)
    error("sixgr:truth:MissingControlGatingConfig", ...
        "Missing explicit control-gating config for '%s'.", string(legacyPath));
end
tf = logical(value);
end

function [active, workerCount, reason] = localResolveActualCoupledParallelState(cfg, requestedParallel, requestedWorkers)
active = false;
workerCount = 1;
reason = "";
if ~logical(requestedParallel)
    reason = "parallel_not_requested";
    return;
end
if ~(isfinite(double(requestedWorkers)) && double(requestedWorkers) > 1)
    reason = "requested_worker_count_not_parallel";
    return;
end
if exist("gcp", "file") ~= 2
    reason = "parallel_toolbox_gcp_unavailable";
    return;
end
pool = [];
try
    pool = gcp("nocreate");
catch
    pool = [];
end
if isempty(pool)
    if ~logical(sixgr.util.structGet(cfg, "run.autoStartParallelPool", false))
        reason = "parallel_pool_not_active_auto_start_disabled";
    else
        reason = "parallel_pool_not_active";
    end
    return;
end
try
    workerCount = double(pool.NumWorkers);
catch
    workerCount = double(requestedWorkers);
end
if ~(isfinite(workerCount) && workerCount > 1)
    workerCount = 1;
    reason = "parallel_pool_worker_count_not_parallel";
    return;
end
active = true;
reason = "parallel_pool_active";
end

function summary = localResolveTRSOperatingModeSummary(rawTrials, direction, trsGating, cfg)
summary = struct( ...
    "TRSRuntimeConsumer", "", ...
    "TRSInfluencedDecision", false, ...
    "TRSInfluenceDefinition", "", ...
    "TRSReceiverIntegrationStatus", "", ...
    "TRSReceiverIntegrationBlocker", "");
if ~logical(sixgr.util.structGet(cfg, "phy.trs.enable", false))
    summary.TRSRuntimeConsumer = "inactive";
    summary.TRSInfluenceDefinition = "trs_disabled";
    summary.TRSReceiverIntegrationStatus = "inactive";
    return;
end
summary.TRSRuntimeConsumer = "pending_shared_receiver_tracking_state";
summary.TRSInfluencedDecision = false;
summary.TRSInfluenceDefinition = "trs_runtime_observation_required_before_receiver_tracking_state_update";
summary.TRSReceiverIntegrationStatus = "pending_no_runtime_trs_observation";
summary.TRSReceiverIntegrationBlocker = "no_trs_trial_row_in_current_bounded_run";
if trsGating
    summary.TRSInfluenceDefinition = "shared_receiver_tracking_state_required_for_grant_scheduling_when_trs_gating_active";
end
sourceT = table();
dirField = char(upper(string(direction)));
if isstruct(rawTrials) && isfield(rawTrials, dirField) && istable(rawTrials.(dirField)) && ~isempty(rawTrials.(dirField))
    sourceT = rawTrials.(dirField);
end
if isempty(sourceT) && isstruct(rawTrials) && isfield(rawTrials, "TRS") && istable(rawTrials.TRS) && ~isempty(rawTrials.TRS)
    sourceT = rawTrials.TRS;
end
if ~(istable(sourceT) && ~isempty(sourceT))
    return;
end
summary.TRSRuntimeConsumer = localFirstNonEmptyString(sourceT, ["TRSRuntimeConsumer","RuntimeStateConsumer"], summary.TRSRuntimeConsumer);
summary.TRSInfluenceDefinition = localFirstNonEmptyString(sourceT, ["TRSInfluenceDefinition"], summary.TRSInfluenceDefinition);
summary.TRSReceiverIntegrationStatus = localFirstNonEmptyString(sourceT, ["TRSReceiverIntegrationStatus"], summary.TRSReceiverIntegrationStatus);
summary.TRSReceiverIntegrationBlocker = localFirstNonEmptyString(sourceT, ["TRSReceiverIntegrationBlocker"], summary.TRSReceiverIntegrationBlocker);
if all(ismember(["RuntimeStateUpdated","TRSReceiverIntegrationBlocker"],string(sourceT.Properties.VariableNames)))
    committed=find(sourceT.RuntimeStateUpdated==1,1,'last');
    if ~isempty(committed)
        summary.TRSReceiverIntegrationBlocker=string(sourceT.TRSReceiverIntegrationBlocker(committed));
    end
end
summary.TRSInfluencedDecision = localFirstLogicalValue(sourceT, ["TRSInfluencedDecision","RuntimeStateUpdated"], summary.TRSInfluencedDecision);
end

function value = localFirstNonEmptyString(T, candidates, defaultValue)
value = string(defaultValue);
for i = 1:numel(candidates)
    name = char(candidates(i));
    if ~ismember(name, string(T.Properties.VariableNames))
        continue;
    end
    tokens = string(T.(name));
    tokens = strtrim(tokens);
    tokens = tokens(strlength(tokens) > 0 & lower(tokens) ~= "missing");
    if ~isempty(tokens)
        value = tokens(1);
        return;
    end
end
end

function value = localFirstLogicalValue(T, candidates, defaultValue)
value = logical(defaultValue);
for i = 1:numel(candidates)
    name = char(candidates(i));
    if ~ismember(name, string(T.Properties.VariableNames))
        continue;
    end
    col = T.(name);
    if islogical(col)
        if ~isempty(col)
            value = logical(col(1));
            return;
        end
    else
        numCol = double(col);
        mask = isfinite(numCol);
        if any(mask)
            value = logical(numCol(find(mask, 1, "first")));
            return;
        end
    end
end
end

function T = localBuildDeploymentLayoutReferenceTable(cfg, multiUser)
speedRange = double(sixgr.util.structGet(cfg, "scenario.mobility.speed_kmh", [0 0]));
if isempty(speedRange)
    speedRange = [0 0];
end
speedRange = [speedRange(:).' zeros(1, max(0, 2 - numel(speedRange)))];
speedRange = speedRange(1:2);
numSites = localFiniteMax([ ...
    double(sixgr.util.structGet(cfg, "scenario.layout.nSites", NaN)), ...
    double(sixgr.util.structGet(cfg, "deployment_topology.num_sites", NaN))]);
numCells = localFiniteMax([ ...
    double(sixgr.util.structGet(cfg, "scenario.layout.nCells", NaN)), ...
    double(sixgr.util.structGet(cfg, "deployment_topology.num_cells", NaN))]);
sectorsPerSite = localFiniteMax([ ...
    double(sixgr.util.structGet(cfg, "scenario.layout.nSectorsPerSite", NaN)), ...
    double(sixgr.util.structGet(cfg, "deployment_topology.sectors_per_site", NaN))]);
if ~(isfinite(sectorsPerSite) && sectorsPerSite >= 1) && isfinite(numSites) && numSites >= 1 && isfinite(numCells) && numCells >= 1
    sectorsPerSite = max(1, round(numCells / numSites));
end
if ~(isfinite(numSites) && numSites >= 1) && isfinite(numCells) && isfinite(sectorsPerSite) && sectorsPerSite >= 1
    numSites = max(1, round(numCells / sectorsPerSite));
end
if ~(isfinite(numCells) && numCells >= 1) && isfinite(numSites) && numSites >= 1 && isfinite(sectorsPerSite) && sectorsPerSite >= 1
    numCells = double(numSites) * double(sectorsPerSite);
end
numUEs = max([ ...
    double(sixgr.util.structGet(cfg, "scenario.nUE", NaN)), ...
    double(sixgr.util.structGet(cfg, "scenario.ue.nUE", NaN)), ...
    double(sixgr.util.structGet(cfg, "deployment_topology.num_ues", NaN)), ...
    double(sixgr.util.structGet(multiUser, "NumUsers", NaN))], [], "omitnan");
mobilityModel = string(sixgr.util.structGet(cfg, "scenario.mobility.model", ...
    sixgr.util.structGet(cfg, "mobility.trajectory_model", "RandomWaypoint")));
layoutType = string(sixgr.util.structGet(cfg, "scenario.geometry.deployment", ...
    sixgr.util.structGet(cfg, "deployment_topology.layout_type", "")));
mobilityEnabled = logical(sixgr.util.structGet(cfg, "scenario.mobility.enable", false));
if ~mobilityEnabled
    mobilityToken = lower(strtrim(string(mobilityModel)));
    mobilityEnabled = any(speedRange > 0) || ~any(mobilityToken == ["", "none", "static"]);
end
T = table( ...
    layoutType, ...
    double(numSites), ...
    double(sectorsPerSite), ...
    double(numCells), ...
    double(sixgr.util.structGet(cfg, "scenario.layout.interSiteDistance_m", sixgr.util.structGet(cfg, "deployment_topology.inter_site_distance", NaN))), ...
    double(numUEs), ...
    double(sixgr.util.structGet(cfg, "phy.beamManagement.trpCount", sixgr.util.structGet(cfg, "deployment_topology.num_trps", 1))), ...
    logical(mobilityEnabled), ...
    mobilityModel, ...
    speedRange(1), speedRange(2), ...
    logical(sixgr.util.structGet(multiUser, "Enabled", false)), ...
    double(sixgr.util.structGet(multiUser, "NumUsers", 1)), ...
    string(sixgr.util.structGet(multiUser, "ExecutionModel", "independent_link_sweep")), ...
    'VariableNames', {'LayoutType','NumSites','SectorsPerSite','NumCells','InterSiteDistance_m','NumUEs','NumTRPs', ...
    'MobilityEnabled','MobilityModel','MobilitySpeedMin_kmh','MobilitySpeedMax_kmh', ...
    'MultiUserEnabled','ConfiguredUsers','UserExecutionModel'});
end

function value = localFiniteMax(values)
values = double(values(:));
values = values(isfinite(values));
if isempty(values)
    value = NaN;
else
    value = max(values);
end
end

function T = localBuildCQITableReferenceTable(cfg)
rows = repmat(struct( ...
    "Direction", "", ...
    "CQITable", "", ...
    "CQI", NaN, ...
    "Modulation", "", ...
    "TargetCodeRate", NaN, ...
    "SpectralEfficiency", NaN), 0, 1);
for direction = ["DL", "UL"]
    tableToken = localResolveCQITable(cfg, direction);
    for idx = 0:15
        profile = sixgr.link.resolveCQIProfile(tableToken, idx);
        rows(end+1,1) = struct( ... %#ok<AGROW>
            "Direction", char(direction), ...
            "CQITable", char(tableToken), ...
            "CQI", double(idx), ...
            "Modulation", char(string(profile.Modulation)), ...
            "TargetCodeRate", double(profile.TargetCodeRate), ...
            "SpectralEfficiency", double(profile.SpectralEfficiency));
    end
end
T = struct2table(rows);
end

function T = localBuildMCSTableReferenceTable(cfg)
rows = repmat(struct( ...
    "Direction", "", ...
    "MCSTable", "", ...
    "MCSIndex", NaN, ...
    "Modulation", "", ...
    "TargetCodeRate", NaN, ...
    "SpectralEfficiency", NaN), 0, 1);
for direction = ["DL", "UL"]
    tableToken = localResolveMCSTable(cfg, direction);
    for idx = 0:31
        profile = sixgr.link.resolveMCSProfile(tableToken, idx);
        if ~logical(profile.Valid)
            continue;
        end
        rows(end+1,1) = struct( ... %#ok<AGROW>
            "Direction", char(direction), ...
            "MCSTable", char(tableToken), ...
            "MCSIndex", double(idx), ...
            "Modulation", char(string(profile.Modulation)), ...
            "TargetCodeRate", double(profile.TargetCodeRate), ...
            "SpectralEfficiency", double(profile.SpectralEfficiency));
    end
end
T = struct2table(rows);
end

function varargout = localResolveLinkAdaptationTokens(varargin)
% Compatibility delegate; completion/publication has one production owner.
[varargout{1:nargout}] = sixgr.truth.SharedDataCompletionRuntime.resolveLinkAdaptationTokens(varargin{:});
end

function varargout = localResolveOperatingPointSourceColumn(varargin)
% Compatibility delegate; completion/publication has one production owner.
[varargout{1:nargout}] = sixgr.truth.SharedDataCompletionRuntime.resolveOperatingPointSourceColumn(varargin{:});
end

function value = localResolveOperatingPointSourceToken(actualMode, linkMode)
values = localResolveOperatingPointSourceColumn(string(actualMode), string(linkMode));
if isempty(values)
    value = "";
else
    value = string(values(1));
end
end

function token = localResolveRuntimeOLLADomainToken(cfg, direction)
if ~logical(sixgr.util.structGet(cfg, "phy.linkAdaptation.outerLoopFlag", false))
    token = "disabled";
    return;
end
domain = sixgr.link.resolveLinkAdaptationDomain(cfg, direction);
if domain == "bler_margin"
    token = "bler_margin_proxy_delta_db";
elseif domain == "legacy_mcs"
    token = "delta_mcs";
else
    token = "delta_db_required_sinr_margin";
end
end

function token = localResolveRuntimeCalibrationProfileToken(cfg, direction)
switch sixgr.link.resolveLinkAdaptationDomain(cfg, direction)
    case "effective_sinr"
        token = "effective_sinr:" + localResolveSINRToCQIModeToken(cfg, direction);
    case "bler_margin"
        token = "heuristic_bler_margin_proxy";
    case "legacy_mcs"
        token = "legacy_mcs_domain_smoothing";
    otherwise
        token = "cqi_table_amc";
end
end

function token = localResolveSINRToCQIModeToken(cfg, direction)
direction = upper(string(direction));
if direction == "UL"
    candidates = [ ...
        "phy.pusch.sinrToCQIMode"
        "phy.csi.ulSINRToCQIMode"
        "phy.csi.sinrToCQIMode"];
else
    candidates = [ ...
        "phy.pdsch.sinrToCQIMode"
        "phy.csi.dlSINRToCQIMode"
        "phy.csi.sinrToCQIMode"];
end
token = "threshold_table";
for i = 1:numel(candidates)
    raw = lower(strtrim(string(sixgr.util.structGet(cfg, candidates(i), ""))));
    if strlength(raw) > 0
        token = raw;
        return;
    end
end
end

function summary = localSummarizeRuntimeOperatingPointEvidence(rawTrials, direction)
summary = struct( ...
    "LinkAdaptationMode", "", ...
    "LinkAdaptationDomain", "", ...
    "ActualMCSSelectionMode", "", ...
    "SchedulerGrantMCSSelectionMode", "", ...
    "AppliedOperatingPointSource", "", ...
    "MCSSelectionSource", "", ...
    "MCSValueStatus", "", ...
    "OLLADomain", "", ...
    "CalibrationProfile", "");
if ~(isstruct(rawTrials) && ~isempty(fieldnames(rawTrials)))
    return;
end
trialTable = sixgr.util.structGet(rawTrials, char(string(direction)), table());
if ~(istable(trialTable) && ~isempty(trialTable))
    return;
end
if ismember("Direction", string(trialTable.Properties.VariableNames))
    mask = strcmpi(strtrim(string(trialTable.Direction)), char(string(direction)));
    if any(mask)
        trialTable = trialTable(mask, :);
    end
end
if isempty(trialTable)
    return;
end
if ismember("IsWarmupFrame", string(trialTable.Properties.VariableNames))
    warmMask = logical(trialTable.IsWarmupFrame);
    if any(~warmMask)
        trialTable = trialTable(~warmMask, :);
    end
end
summary.LinkAdaptationMode = localDominantStringValue(trialTable, "LinkAdaptationMode");
summary.LinkAdaptationDomain = localDominantStringValue(trialTable, "LinkAdaptationDomain");
summary.ActualMCSSelectionMode = localDominantStringValue(trialTable, "ActualMCSSelectionMode");
summary.SchedulerGrantMCSSelectionMode = localDominantStringValue(trialTable, "SchedulerGrantMCSSelectionMode");
summary.AppliedOperatingPointSource = localDominantStringValue(trialTable, "AppliedOperatingPointSource");
summary.MCSSelectionSource = localDominantStringValue(trialTable, "MCSSelectionSource");
summary.MCSValueStatus = localDominantStringValue(trialTable, "MCSValueStatus");
summary.OLLADomain = localDominantStringValue(trialTable, "OLLADomain");
summary.CalibrationProfile = localDominantStringValue(trialTable, "CalibrationProfile");
end

function summary = localSummarizeChannelArrayEvidence(rawTrials, direction)
summary = struct( ...
    "AntennaRuntimeObjectSource", "", ...
    "ChannelArrayModel", "", ...
    "ChannelObjectSource", "", ...
    "ChannelObjectClass", "", ...
    "ChannelArrayHandlingStatus", "", ...
    "ChannelArrayHandlingBlocker", "", ...
    "ChannelGeometryCouplingLevel", "", ...
    "GeometryAdapterType", "", ...
    "GeometryAdapterSource", "", ...
    "GeometryAdapterLimitation", "", ...
    "GeometryAdapterPortMapping", "", ...
    "ChannelUsesCountOnlyAntennaModel", false, ...
    "ChannelUsesSameRuntimeAntennaAssumptions", false, ...
    "ElementPatternChannelApplicability", "", ...
    "AntennaChannelConsistencyStatus", "", ...
    "AntennaChannelConsistencyReason", "", ...
    "InterferenceChannelObjectSource", "", ...
    "InterferenceChannelObjectClass", "", ...
    "InterferenceChannelArrayHandlingStatus", "", ...
    "InterferenceChannelArrayHandlingBlocker", "", ...
    "InterferenceUsesSameRuntimeAntennaAssumptions", false, ...
    "InterferencePathUsesSameArrayAssumptions", false);
if ~(isstruct(rawTrials) && ~isempty(fieldnames(rawTrials)))
    return;
end
trialTable = sixgr.util.structGet(rawTrials, char(string(direction)), table());
if ~(istable(trialTable) && ~isempty(trialTable))
    return;
end
if ismember("Direction", string(trialTable.Properties.VariableNames))
    mask = strcmpi(strtrim(string(trialTable.Direction)), char(string(direction)));
    if any(mask)
        trialTable = trialTable(mask, :);
    end
end
if isempty(trialTable)
    return;
end
if ismember("IsWarmupFrame", string(trialTable.Properties.VariableNames))
    warmMask = logical(trialTable.IsWarmupFrame);
    if any(~warmMask)
        trialTable = trialTable(~warmMask, :);
    end
end
summary.AntennaRuntimeObjectSource = localDominantStringValue(trialTable, "RuntimeAntennaObjectSource");
summary.ChannelArrayModel = localDominantStringValue(trialTable, "ChannelArrayModel");
summary.ChannelObjectSource = localDominantStringValue(trialTable, "ChannelObjectSource");
summary.ChannelObjectClass = localDominantStringValue(trialTable, "ChannelObjectClass");
summary.ChannelArrayHandlingStatus = localDominantStringValue(trialTable, "ChannelArrayHandlingStatus");
summary.ChannelArrayHandlingBlocker = localDominantStringValue(trialTable, "ChannelArrayHandlingBlocker");
summary.ChannelGeometryCouplingLevel = localDominantStringValue(trialTable, "ChannelGeometryCouplingLevel");
summary.GeometryAdapterType = localDominantStringValue(trialTable, "GeometryAdapterType");
summary.GeometryAdapterSource = localDominantStringValue(trialTable, "GeometryAdapterSource");
    summary.GeometryAdapterLimitation = localDominantStringValue(trialTable, "GeometryAdapterLimitation");
    summary.GeometryAdapterPortMapping = localDominantStringValue(trialTable, "GeometryAdapterPortMapping");
    summary.ChannelUsesCountOnlyAntennaModel = localDominantLogicalValue(trialTable, "ChannelUsesCountOnlyAntennaModel");
    summary.ChannelUsesSameRuntimeAntennaAssumptions = localDominantLogicalValue(trialTable, "ChannelUsesSameRuntimeAntennaAssumptions");
    summary.ElementPatternChannelApplicability = localDominantStringValue(trialTable, "ElementPatternChannelApplicability");
    summary.AntennaChannelConsistencyStatus = localDominantStringValue(trialTable, "AntennaChannelConsistencyStatus");
    summary.AntennaChannelConsistencyReason = localDominantStringValue(trialTable, "AntennaChannelConsistencyReason");
    if strcmpi(strtrim(string(summary.ChannelArrayModel)), "awgn_no_array_channel")
        % Older raw rows predate the explicit AWGN classification.  The
        % channel model itself is sufficient to classify applicability, but
        % it is not evidence that element patterns were applied.
        summary.ChannelUsesCountOnlyAntennaModel = false;
        summary.ChannelUsesSameRuntimeAntennaAssumptions = false;
        summary.ElementPatternChannelApplicability = "not_applicable_awgn_identity_channel";
        if strlength(strtrim(string(summary.AntennaChannelConsistencyStatus))) == 0
            summary.AntennaChannelConsistencyStatus = "classified_not_applicable_pending_runtime_dimension_check";
        end
        if strlength(strtrim(string(summary.AntennaChannelConsistencyReason))) == 0
            summary.AntennaChannelConsistencyReason = "awgn_has_no_spatial_propagation_kernel_or_element_pattern_application";
        end
    end
summary.InterferenceChannelObjectSource = localDominantStringValue(trialTable, "InterferenceChannelObjectSource");
summary.InterferenceChannelObjectClass = localDominantStringValue(trialTable, "InterferenceChannelObjectClass");
summary.InterferenceChannelArrayHandlingStatus = localDominantStringValue(trialTable, "InterferenceChannelArrayHandlingStatus");
summary.InterferenceChannelArrayHandlingBlocker = localDominantStringValue(trialTable, "InterferenceChannelArrayHandlingBlocker");
summary.InterferenceUsesSameRuntimeAntennaAssumptions = localDominantLogicalValue(trialTable, "InterferenceUsesSameRuntimeAntennaAssumptions");
summary.InterferencePathUsesSameArrayAssumptions = localDominantLogicalValue(trialTable, "InterferencePathUsesSameArrayAssumptions");
end

function value = localDominantStringValue(T, varName)
value = "";
if ~(istable(T) && ismember(varName, string(T.Properties.VariableNames)))
    return;
end
values = strtrim(string(T.(char(varName))));
values = values(strlength(values) > 0);
if isempty(values)
    return;
end
[uniqueValues, ~, idx] = unique(values, "stable");
counts = accumarray(idx, 1);
[~, bestIdx] = max(counts);
value = char(uniqueValues(bestIdx));
end

function value = localDominantLogicalValue(T, varName)
value = false;
if ~(istable(T) && ismember(varName, string(T.Properties.VariableNames)))
    return;
end
values = logical(T.(char(varName)));
if isempty(values)
    return;
end
value = sum(values) >= sum(~values);
end

function tableToken = localResolveCQITable(cfg, direction)
tableToken = string(sixgr.link.resolveConfiguredCQITable(cfg, direction));
end

function tableToken = localResolveMCSTable(cfg, direction)
tableToken = string(sixgr.link.resolveConfiguredMCSTable(cfg, direction));
end

function tf = localRawControlTablesReady(rawTrials)
tf = false;
for fieldName = ["PBCH", "PRACH", "PDCCH", "PUCCH", "SRS", "CSIRS", "TRS"]
    T = sixgr.util.structGet(rawTrials, fieldName, table());
    if istable(T) && ~isempty(T)
        tf = true;
        return;
    end
end
end

function tf = localArtifactStructReady(artifacts, fieldName)
T = sixgr.util.structGet(artifacts, fieldName, table());
tf = istable(T) && ~isempty(T);
end

function tf = localRFArtifactsReady(artifacts)
energyReady = localArtifactStructReady(sixgr.util.structGet(artifacts, "Energy", struct()), "SummaryTable");
iqReady = localArtifactStructReady(sixgr.util.structGet(artifacts, "IQImpairment", struct()), "SummaryTable");
tf = energyReady && iqReady;
end

function tf = localLegacyHARQArtifactsReady(rootRunFolder)
layout = sixgr.report.resultLayout(rootRunFolder);
paths = [ ...
    string(fullfile(layout.HARQCSVDir, "probe_harq_packets.csv")); ...
    string(fullfile(layout.HARQCSVDir, "probe_harq_summary.csv")); ...
    string(fullfile(layout.HARQCSVDir, "harq_process_timeline.csv"))];
tf = true;
for i = 1:numel(paths)
    tf = tf && exist(char(paths(i)), "file") == 2;
end
end

function T = localGetCaseTrialTable(linkRes, caseField)
T = table();
caseStruct = localGetCaseStruct(linkRes, caseField);
if isempty(fieldnames(caseStruct))
    return;
end
try
    T = sixgr.util.structGet(caseStruct, "TrialTable", table());
catch
    T = table();
end
if ~istable(T)
    T = table();
end
end

function caseStruct = localGetCaseStruct(linkRes, caseField)
caseStruct = struct();
if ~(builtin("isstruct", linkRes) && isscalar(linkRes))
    return;
end
cases = sixgr.util.structGet(linkRes, "Cases", struct());
if ~(builtin("isstruct", cases) && isscalar(cases) && isfield(cases, char(caseField)))
    return;
end
try
    caseStruct = cases.(char(caseField));
catch
    caseStruct = struct();
end
end

function [T, constT, csirsT, signalDiagnostic, waveT, observedRET] = localCollectSingleUserLinkTrialsAcrossSweep(cfg, direction, nTrials, snrGrid, liveTablePath, liveConstellationPath, progressLabel)
T = localEmptyLinkTrialTable(0);
observedRET = table();
constT = table();
csirsT = table();
waveT = table();
direction = upper(string(direction));
signalDiagnostic = localUnavailablePHYSignalDiagnostic(direction);
snrGrid = unique(sort(double(snrGrid(:))));
if nargin < 5
    liveTablePath = "";
end
if nargin < 6
    liveConstellationPath = "";
end
if nargin < 7
    progressLabel = string(direction);
end
for i = 1:numel(snrGrid)
    snr = double(snrGrid(i));
    liveTrialCallback = [];
    if strlength(string(liveTablePath)) > 0 || strlength(string(liveConstellationPath)) > 0
        baseTrials = T;
        baseConst = constT;
        liveTrialCallback = @(partialTrials, partialConst, meta) ...
            localPublishLiveSweepSnapshot(baseTrials, partialTrials, baseConst, partialConst, ...
            liveTablePath, liveConstellationPath, cfg, meta);
    end
    if direction == "DL"
        res = sixgr.link.runDLPDSCHThroughput(cfg, ...
            "NumFrames", nTrials, ...
            "SNR_dB", snr, ...
            "LiveTrialCallback", liveTrialCallback, ...
            "LiveCallbackInterval", localResolveLiveFramePublishInterval(cfg, nTrials));
    else
        res = sixgr.link.runULPUSCHThroughput(cfg, ...
            "NumFrames", nTrials, ...
            "SNR_dB", snr, ...
            "LiveTrialCallback", liveTrialCallback, ...
            "LiveCallbackInterval", localResolveLiveFramePublishInterval(cfg, nTrials));
    end
    Ti = localEnsureLinkTrialTable(sixgr.util.structGet(res, "TrialTable", table()), direction, snr, cfg);
    observedRET=localAppendCompatTable(observedRET,sixgr.truth.bindIndependentREObservation( ...
        sixgr.util.structGet(res,'ObservedREAllocationTable',table())));
    signalDiagnostic = localSelectPHYSignalDiagnostic(signalDiagnostic, ...
        sixgr.util.structGet(res, "SignalDiagnostic", struct()));
    T = localAppendCompatTable(T, Ti);
    constT = localAppendCompatTable(constT, sixgr.util.structGet(res, "ConstellationSamples", table()));
    waveT = localAppendCompatTable(waveT, sixgr.util.structGet(res, "WaveformPreviewTable", table()));
    if direction == "DL"
        csirsT = localAppendCompatTable(csirsT, sixgr.util.structGet(res, "CSIRSTrialTable", table()));
    end
    localMaybeWritePartialTable(liveTablePath, T);
    localMaybeAppendSweepProgressLog(progressLabel, snr, i, numel(snrGrid), T);
    if strlength(string(liveConstellationPath)) > 0 && istable(constT) && ~isempty(constT)
        if localIsMySQLWebMode(cfg)
            sixgr.util.csvWriteTable(liveConstellationPath, localDownsampleConstellationTable(constT, 2500));
        else
            sixgr.util.csvWriteTable(liveConstellationPath, constT);
        end
    end
end
end

function [dlTrials, ulTrials, dlSummaryT, ulSummaryT, dlConstT, ulConstT, csirsT, dlSignalDiagnostic, ulSignalDiagnostic, dlWaveT, ulWaveT, dlObservedRE, ulObservedRE] = localCollectInterleavedMultiUserLinkTrialsAcrossSweep(cfg, runFolder, multiUser, nTrials, snrGrid, dlTablePath, ulTablePath, dlConstellationPath, ulConstellationPath, ~, mobilityArtifacts)
dlTrials = localEmptyLinkTrialTable(0);
ulTrials = localEmptyLinkTrialTable(0);
dlObservedRE=table(); ulObservedRE=table();
dlWaveT = table();
ulWaveT = table();
dlConstT = table();
ulConstT = table();
csirsT = table();
dlSignalDiagnostic = localUnavailablePHYSignalDiagnostic("DL");
ulSignalDiagnostic = localUnavailablePHYSignalDiagnostic("UL");
dlParts = {};
ulParts = {};
if nargin < 11 || ~isstruct(mobilityArtifacts)
    mobilityArtifacts = struct();
end
snrGrid = unique(sort(double(snrGrid(:))));
numUsers = max(1, round(double(sixgr.util.structGet(multiUser, "NumUsers", 1))));
for i = 1:numel(snrGrid)
    snrVal = double(snrGrid(i));
    for ueIdx = 1:numUsers
        dlLivePublisher = @(partialTrials, partialConst, meta) localPublishLiveSweepSnapshot( ...
            dlTrials, partialTrials, dlConstT, partialConst, ...
            dlTablePath, dlConstellationPath, cfg, ...
            localMergeLiveMeta(meta, ...
            localBuildLivePublishMeta( ...
            "DL", snrVal, i, numel(snrGrid), ueIdx, numUsers, ...
            localBuildLiveRawTrialsAggregate(localAppendCompatTable(dlTrials, partialTrials), ulTrials, dlParts, ulParts, csirsT), ...
            multiUser, mobilityArtifacts, ...
            sprintf("Streaming DL user %d/%d at SNR point %d/%d (%.3f dB).", ueIdx, numUsers, i, numel(snrGrid), snrVal))));
        [dlUserT, dlUserSummary, dlUserConst, dlUserCSIRS, dlUserSignalDiagnostic, dlUserWave, dlUserRE] = localRunSingleUserDirectionTrials( ...
            cfg, multiUser, ueIdx, "DL", nTrials, snrVal, dlLivePublisher);
        dlSignalDiagnostic = localSelectPHYSignalDiagnostic(dlSignalDiagnostic, dlUserSignalDiagnostic);
        dlTrials = localAppendCompatTable(dlTrials, dlUserT);
        dlConstT = localAppendCompatTable(dlConstT, dlUserConst);
        dlWaveT = localAppendCompatTable(dlWaveT, dlUserWave);
        dlObservedRE=localAppendCompatTable(dlObservedRE,dlUserRE);
        csirsT = localAppendCompatTable(csirsT, dlUserCSIRS);
        if istable(dlUserSummary) && ~isempty(dlUserSummary)
            dlParts{end+1} = dlUserSummary; %#ok<AGROW>
        end
        localMaybeWritePartialTable(dlTablePath, dlTrials);
        if strlength(string(dlConstellationPath)) > 0 && istable(dlConstT) && ~isempty(dlConstT)
            sixgr.util.csvWriteTable(dlConstellationPath, localDownsampleConstellationTable(dlConstT, 2500));
        end
        liveRawTrials = localBuildLiveRawTrialsAggregate(dlTrials, ulTrials, dlParts, ulParts, csirsT);
        liveDerived = sixgr.truth.exportLLSLiveDerivedTables(cfg, fileparts(char(string(runFolder))), liveRawTrials, multiUser, mobilityArtifacts);
        localPublishWaveformBundleStageStatus(runFolder, localBuildLiveStageStatus( ...
            liveRawTrials, struct("LiveDerived", liveDerived, "HARQ", sixgr.util.structGet(liveDerived, "HARQ", struct()), "Energy", struct()), ...
            localBuildLivePublishMeta("DL", snrVal, i, numel(snrGrid), ueIdx, numUsers, struct(), multiUser, mobilityArtifacts, ...
            sprintf("Completed DL user %d/%d at SNR point %d/%d (%.3f dB).", ueIdx, numUsers, i, numel(snrGrid), snrVal))));

        ulLivePublisher = @(partialTrials, partialConst, meta) localPublishLiveSweepSnapshot( ...
            ulTrials, partialTrials, ulConstT, partialConst, ...
            ulTablePath, ulConstellationPath, cfg, ...
            localMergeLiveMeta(meta, ...
            localBuildLivePublishMeta( ...
            "UL", snrVal, i, numel(snrGrid), ueIdx, numUsers, ...
            localBuildLiveRawTrialsAggregate(dlTrials, localAppendCompatTable(ulTrials, partialTrials), dlParts, ulParts, csirsT), ...
            multiUser, mobilityArtifacts, ...
            sprintf("Streaming UL user %d/%d at SNR point %d/%d (%.3f dB).", ueIdx, numUsers, i, numel(snrGrid), snrVal))));
        [ulUserT, ulUserSummary, ulUserConst, ~, ulUserSignalDiagnostic, ulUserWave, ulUserRE] = localRunSingleUserDirectionTrials( ...
            cfg, multiUser, ueIdx, "UL", nTrials, snrVal, ulLivePublisher);
        ulSignalDiagnostic = localSelectPHYSignalDiagnostic(ulSignalDiagnostic, ulUserSignalDiagnostic);
        ulTrials = localAppendCompatTable(ulTrials, ulUserT);
        ulConstT = localAppendCompatTable(ulConstT, ulUserConst);
        ulWaveT = localAppendCompatTable(ulWaveT, ulUserWave);
        ulObservedRE=localAppendCompatTable(ulObservedRE,ulUserRE);
        if istable(ulUserSummary) && ~isempty(ulUserSummary)
            ulParts{end+1} = ulUserSummary; %#ok<AGROW>
        end
        localMaybeWritePartialTable(ulTablePath, ulTrials);
        if strlength(string(ulConstellationPath)) > 0 && istable(ulConstT) && ~isempty(ulConstT)
            sixgr.util.csvWriteTable(ulConstellationPath, localDownsampleConstellationTable(ulConstT, 2500));
        end
        liveRawTrials = localBuildLiveRawTrialsAggregate(dlTrials, ulTrials, dlParts, ulParts, csirsT);
        liveDerived = sixgr.truth.exportLLSLiveDerivedTables(cfg, fileparts(char(string(runFolder))), liveRawTrials, multiUser, mobilityArtifacts);
        localPublishWaveformBundleStageStatus(runFolder, localBuildLiveStageStatus( ...
            liveRawTrials, struct("LiveDerived", liveDerived, "HARQ", sixgr.util.structGet(liveDerived, "HARQ", struct()), "Energy", struct()), ...
            localBuildLivePublishMeta("UL", snrVal, i, numel(snrGrid), ueIdx, numUsers, struct(), multiUser, mobilityArtifacts, ...
            sprintf("Completed UL user %d/%d at SNR point %d/%d (%.3f dB).", ueIdx, numUsers, i, numel(snrGrid), snrVal))));
    end
    localMaybeAppendSweepProgressLog("DL", snrVal, i, numel(snrGrid), dlTrials);
    localMaybeAppendSweepProgressLog("UL", snrVal, i, numel(snrGrid), ulTrials);
end

if isempty(dlParts)
    dlSummaryT = table();
else
    dlSummaryT = vertcat(dlParts{:});
end
if isempty(ulParts)
    ulSummaryT = table();
else
    ulSummaryT = vertcat(ulParts{:});
end
end


function [dlTrials, ulTrials, dlSummaryT, ulSummaryT, dlConstT, ulConstT, controlTrials, runtimeState] = localCollectCoupledTruthMultiUserLinkTrialsAcrossSweep(cfg, runFolder, multiUser, nTrials, snrGrid, dlTablePath, ulTablePath, dlConstellationPath, ulConstellationPath, controlTrials, checkpointLease)
dlTrials = localEmptyLinkTrialTable(0);
ulTrials = localEmptyLinkTrialTable(0);
dlConstT = table();
ulConstT = table();
if nargin < 10 || ~isstruct(controlTrials)
    controlTrials = struct();
end

snrGrid = unique(sort(double(snrGrid(:))));
numUsers = max(1, round(double(sixgr.util.structGet(multiUser, "NumUsers", 1))));
nFramesPerPoint = max(1, round(double(nTrials)));
totalCanonicalSlots = nFramesPerPoint * numel(snrGrid);
userCfg = cell(numUsers, 1);
for ueIdx = 1:numUsers
    userCfg{ueIdx} = localPrepareUserCfg(cfg, multiUser, ueIdx);
end
resumeCheckpoint=string(sixgr.util.structGet(cfg,'run.runtimeCheckpointResumeFrom',''));
checkpointEnabled=logical(sixgr.util.structGet(cfg,'run.runtimeCheckpointEnabled',false));
checkpointSource=struct();
if checkpointEnabled || strlength(resumeCheckpoint)>0
    checkpointSource=sixgr.runtime.SlotCheckpoint.sourceIdentity();
end
if strlength(resumeCheckpoint)>0
    if isempty(checkpointLease)
        [restored,checkpointLineage]=sixgr.runtime.SlotCheckpoint.read(resumeCheckpoint, ...
            cfg.run.runtimeCheckpointScenario,cfg.run.runtimeCheckpointRepairReason);
    else
        assert(isa(checkpointLease,'sixgr.runtime.CheckpointResumeLease'), ...
            'sixgr:checkpoint:InvalidResumeOwner','Use the native preflight owner, not a reconstructed payload.');
        [restored,checkpointLineage]=checkpointLease.take(resumeCheckpoint, ...
            cfg.run.runtimeCheckpointScenario,cfg.run.runtimeCheckpointRepairReason);
    end
    runtimeState=restored.RuntimeState;
    % SlotCheckpoint.read has verified this completed boundary. Older saved
    % states predate the separate radio-progress counter; do not use data rows.
    runtimeState.CompletedCanonicalSlots=double(restored.CompletedSlot);
    runtimeState.CheckpointContinuation=checkpointLineage;
    runtimeState.PrimaryStudyEligible=false;
    dlTrials=restored.DLTrials; ulTrials=restored.ULTrials;
    dlConstT=restored.DLConstellations; ulConstT=restored.ULConstellations;
    sixgr.runtime.CheckpointExecutionHorizon.assertResume(restored,cfg,nFramesPerPoint,snrGrid);
    if isfield(cfg.run,'executionHorizon')
        runtimeState.ExecutionHorizon=cfg.run.executionHorizon;
        runtimeState.ConfiguredCanonicalSlotsPerSweepPoint= ...
            cfg.run.executionHorizon.OriginalConfiguredSlots;
        runtimeState.CanonicalSlotsPerSweepPoint=nFramesPerPoint;
    end
    rng(restored.RNG);
else
    runtimeState = localInitCoupledTruthRuntimeState(cfg, runFolder, multiUser, controlTrials, nFramesPerPoint * numel(snrGrid));
end
pendingULGrants = repmat(struct(), 0, 1);
firstSweep=1; firstFrame=1;
if strlength(resumeCheckpoint)>0
    pendingULGrants=restored.PendingULGrants;
    firstSweep=restored.SweepIndex; firstFrame=restored.FrameLocal+1;
end
sweepStatePolicy = lower(strtrim(string(sixgr.util.structGet( ...
    cfg, "run.snrSweepStatePolicy", ""))));
if numel(snrGrid) > 1 && strlength(sweepStatePolicy) == 0
    error("sixgr:truth:MissingCoupledSNRSweepStatePolicy", ...
        "A multi-point coupled truth run requires sweeps_and_matrix.snr_sweep.state_policy in YAML. Use independent_link_state_per_point for fixed-SNR measurement or continuous_runtime for a time-varying operating scenario.");
end

if strlength(sweepStatePolicy) == 0
    sweepStatePolicy = "continuous_runtime";
end
if ~ismember(sweepStatePolicy, ["independent_link_state_per_point", "continuous_runtime"])
    error("sixgr:truth:InvalidCoupledSNRSweepStatePolicy", ...
        "Unsupported coupled truth SNR-sweep state policy '%s'.", char(sweepStatePolicy));
end
rootRunFolder = fileparts(char(string(runFolder)));
profileCtl = localResolveCoupledProfileControl(runFolder, nFramesPerPoint);
profileCtl.StartTic = tic;
stopCoupledProfile = false;

try
for sweepIdx = firstSweep:numel(snrGrid)
    snrVal = double(snrGrid(sweepIdx));
    if sweepIdx > 1 && sweepStatePolicy == "independent_link_state_per_point" && ...
            ~(sweepIdx==firstSweep && strlength(resumeCheckpoint)>0)
        sweepStartSlot = (sweepIdx - 1) * nFramesPerPoint + 1;
        runtimeState = sixgr.truth.CoupledTruthRuntime.resetIndependentSweepPointLinkState( ...
            runtimeState, cfg, sweepIdx, sweepStartSlot);
        pendingULGrants = repmat(struct(), 0, 1);
        localAppendRuntimeLog("INFO", ...
            "Reset causal HARQ, channel, reference-measurement, scheduler, link-adaptation and traffic-queue state at independent fixed-SNR point boundary: sweep=%d/%d start_slot=%d snr_db=%.3f policy=%s.", ...
            round(double(sweepIdx)), round(double(numel(snrGrid))), ...
            round(double(sweepStartSlot)), double(snrVal), char(sweepStatePolicy));
    end
    dlStates = cell(numUsers, 1);
    ulStates = cell(numUsers, 1);
    if sweepIdx==firstSweep && strlength(resumeCheckpoint)>0
        dlStates=restored.DLStates; ulStates=restored.ULStates;
        clear restored;
    end
    startFrame=1;
    if sweepIdx==firstSweep, startFrame=firstFrame; end
    for frameLocal = startFrame:nFramesPerPoint
        absoluteFrame = (sweepIdx - 1) * nFramesPerPoint + frameLocal;
        sixgr.runtime.ExecutionStageProfiler.setSlot(absoluteFrame,sweepIdx);
        runtimeState = localAdvanceCoupledRuntimeFrame(runtimeState, cfg, multiUser, absoluteFrame, snrVal);
        [allowDL, allowUL, slotLabel] = localCoupledSlotDuplexState(cfg, absoluteFrame);
        localAppendRuntimeLog("INFO", ...
            "Coupled canonical slot prepared: sweep=%d/%d slot=%d/%d duplex=%s allow_dl=%d allow_ul=%d.", ...
            round(double(sweepIdx)), round(double(numel(snrGrid))), round(double(frameLocal)), round(double(nFramesPerPoint)), ...
            char(string(slotLabel)), double(logical(allowDL)), double(logical(allowUL)));
        if allowDL
            [runtimeState,pendingULGrants,entryBlockedUL] = sixgr.truth.CoupledTruthRuntime.startSlotWithQueuedUL( ...
                runtimeState,cfg,"DL",sweepIdx,numel(snrGrid),absoluteFrame,totalCanonicalSlots,snrVal, ...
                pendingULGrants,logical(localPUSCHUCIOnPUSCHAvailable(cfg)));
        elseif allowUL
            [runtimeState,pendingULGrants,entryBlockedUL] = sixgr.truth.CoupledTruthRuntime.startSlotWithQueuedUL( ...
                runtimeState,cfg,"UL",sweepIdx,numel(snrGrid),absoluteFrame,totalCanonicalSlots,snrVal, ...
                pendingULGrants,logical(localPUSCHUCIOnPUSCHAvailable(cfg)));
        else
            localAppendRuntimeLog("WARN", ...
                "Coupled canonical slot skipped because no duplex direction is enabled: sweep=%d/%d slot=%d/%d duplex=%s.", ...
                round(double(sweepIdx)), round(double(numel(snrGrid))), round(double(frameLocal)), round(double(nFramesPerPoint)), ...
                char(string(slotLabel)));
            continue;
        end
        if ~isempty(entryBlockedUL)
            localAppendRuntimeLog("INFO", ...
                "Suppressed queued UL before standalone feedback execution: slot=%d blocked=%d.", ...
                absoluteFrame,height(entryBlockedUL));
        end
        if ~isfield(runtimeState,'SharedWaveformStream') && ...
                sixgr.channel.ChannelFactory.requiresRuntimeChannelState(cfg)
            [runtimeState,~]=sixgr.truth.CoupledWaveformStream.initialize(runtimeState,cfg,userCfg);
        end
        [runtimeState, pendingULGrants] = localRunCoupledPreSchedulingControlGating( ...
            runtimeState, cfg, runFolder, userCfg, snrVal, pendingULGrants);
        if isfield(runtimeState,'SharedWaveformStream')
            runtimeState.SharedPendingULGrants=pendingULGrants;
            runtimeState.SharedULLinkAdaptationStates=ulStates;
        end
        liveRawTrials = localBuildCoupledTruthRawTrialsAggregate(dlTrials, ulTrials, multiUser, runtimeState.ControlTrials, cfg);
        publishDirection = "DL";
        if ~allowDL && allowUL
            publishDirection = "UL";
        end
        localPublishCoupledTruthRuntimeState(cfg, runFolder, liveRawTrials, multiUser, runtimeState, ...
            dlTablePath, ulTablePath, dlConstellationPath, ulConstellationPath, dlConstT, ulConstT, ...
            publishDirection, snrVal, sweepIdx, numel(snrGrid), 0, numel(userCfg), frameLocal, nFramesPerPoint, table(), ...
            "WriteRawTables", false, "SlotComplete", false, "PublishReason", "slot_pre_schedule_status");
        if allowDL
            [runtimeState, dlGrants, dlInfo] = sixgr.truth.CoupledTruthRuntime.scheduleDirection(runtimeState, cfg, "DL");
            dlUnavailableReason = string(sixgr.util.structGet( ...
                dlInfo, "ResourceUnavailableReason", ""));
            if strlength(strtrim(dlUnavailableReason)) > 0
                localAppendRuntimeLog("INFO", ...
                    "Coupled DL scheduling deferred: sweep=%d/%d slot=%d/%d reason=%s policy=no_valid_harq_ack_occasion_from_current_dl_slot.", ...
                    round(double(sweepIdx)), round(double(numel(snrGrid))), ...
                    round(double(frameLocal)), round(double(nFramesPerPoint)), ...
                    char(dlUnavailableReason));
            end
            localAppendRuntimeLog("INFO", ...
                "Coupled DL schedule complete: sweep=%d/%d slot=%d/%d active=%d granted=%d grants=%d.", ...
                round(double(sweepIdx)), round(double(numel(snrGrid))), round(double(frameLocal)), round(double(nFramesPerPoint)), ...
                round(double(sixgr.util.structGet(dlInfo, "ActiveUsers", NaN))), ...
                round(double(sixgr.util.structGet(dlInfo, "GrantedUsers", NaN))), numel(dlGrants));
            plannedSharedUL=repmat(struct(),0,1);
            if isfield(runtimeState,'SharedWaveformStream')
                [runtimeState,pendingULGrants,plannedSharedUL]=localScheduleCoupledFutureULGrantsFromDLControl( ...
                    runtimeState,cfg,userCfg,pendingULGrants,snrVal,sweepIdx,numel(snrGrid),frameLocal,nFramesPerPoint,true);
                if localPUSCHUCIOnPUSCHAvailable(cfg)
                    [runtimeState,dlGrants,plannedSharedUL]=sixgr.truth.planJointHARQPUSCHTiming( ...
                        runtimeState,userCfg,dlGrants,plannedSharedUL);
                end
                [dlGrants,plannedSharedUL]=sixgr.truth.resolveJointPDCCHAdmission( ...
                    runtimeState,cfg,userCfg,dlGrants,plannedSharedUL);
            end
            [runtimeState, dlGrants, queuedDL] = localQualifyCoupledGrantsWithPDCCH(runtimeState, userCfg, dlGrants, "DL", snrVal);
            if isfield(runtimeState,'SharedWaveformStream')
                % Authored DL samples are transmitted before the UE knows
                % whether its DCI decoded. Queued is not qualified RX.
                dlGrants=queuedDL;
                localAppendRuntimeLog("INFO", ...
                    "Coupled DL control preparation complete: slot=%d queued_transmissions=%d receiver_authority=pending_actual_DCI.", ...
                    absoluteFrame,numel(queuedDL));
            else
                localAppendRuntimeLog("INFO", ...
                    "Coupled DL PDCCH qualification complete: sweep=%d/%d slot=%d/%d executable_grants=%d.", ...
                    round(double(sweepIdx)), round(double(numel(snrGrid))), round(double(frameLocal)), round(double(nFramesPerPoint)), numel(dlGrants));
            end
            % The same PDCCH monitoring occasion can carry DL assignments
            % and UL grants.  Resolve and freeze the future K2 PUSCH grant
            % while the runtime still represents that control occasion.
            % Executing PDSCH first mutates per-UE feedback/PHY state and
            % incorrectly made the UL decision depend on a later data-plane
            % event instead of the decoded DCI authority.
            if isfield(runtimeState,'SharedWaveformStream')
                [runtimeState,pendingULGrants]=localTransmitCoupledFutureULGrants( ...
                    runtimeState,cfg,userCfg,pendingULGrants,plannedSharedUL,snrVal);
            else
                [runtimeState, pendingULGrants] = localScheduleCoupledFutureULGrantsFromDLControl( ...
                    runtimeState, cfg, userCfg, pendingULGrants, snrVal, sweepIdx, numel(snrGrid), frameLocal, nFramesPerPoint);
            end
            [runtimeState, dlTrials, dlConstT, dlStates] = localExecuteCoupledDirectionBatch( ...
                runtimeState, cfg, runFolder, multiUser, userCfg, dlGrants, "DL", snrVal, absoluteFrame, dlStates, ...
                dlTrials, ulTrials, dlConstT, ulConstT, dlTablePath, ulTablePath, dlConstellationPath, ulConstellationPath, ...
                sweepIdx, numel(snrGrid), frameLocal, nFramesPerPoint);
            % The K2 PUSCH grant above is frozen before this PDSCH decode,
            % while the HARQ-ACK reservation is created by the decode. Bind
            % that newly measured ACK/NACK to the already queued future
            % PUSCH now. Waiting until the due UL slot is incorrect because
            % startSlot emits standalone PUCCH before queued PUSCH lookup.
            [runtimeState, pendingULGrants, lateFeedbackBlockedPUSCH] = ...
                sixgr.truth.CoupledTruthRuntime. ...
                reconcileQueuedPUSCHAfterDLFeedbackRuntime( ...
                runtimeState, pendingULGrants, ...
                localPUSCHUCIOnPUSCHAvailable(cfg));
            if istable(lateFeedbackBlockedPUSCH) && ...
                    ~isempty(lateFeedbackBlockedPUSCH)
                localAppendRuntimeLog("INFO", ...
                    "Suppressed queued PUSCH after post-PDSCH HARQ-ACK creation: source_slot=%d blocked=%d pending=%d.", ...
                    round(double(absoluteFrame)), ...
                    height(lateFeedbackBlockedPUSCH), numel(pendingULGrants));
            end
        end
        sharedDueULGrants=repmat(struct(),0,1);
        if allowUL
            if allowDL
                runtimeState = sixgr.truth.CoupledTruthRuntime.startSlot(runtimeState, cfg, "UL", sweepIdx, numel(snrGrid), absoluteFrame, totalCanonicalSlots, snrVal);
            end
            [ulGrants, pendingULGrants, staleCount] = localPopDueCoupledULGrants(pendingULGrants, absoluteFrame);
            if staleCount > 0
                localAppendRuntimeLog("WARN", ...
                    "Dropped stale queued UL grants before slot=%d: stale_grants=%d.", ...
                    round(double(absoluteFrame)), round(double(staleCount)));
            end
            localAppendRuntimeLog("INFO", ...
                "Coupled UL queued grant lookup complete: sweep=%d/%d slot=%d/%d due_grants=%d pending_grants=%d.", ...
                round(double(sweepIdx)), round(double(numel(snrGrid))), round(double(frameLocal)), round(double(nFramesPerPoint)), ...
                numel(ulGrants), numel(pendingULGrants));
            if ~isempty(ulGrants)
                % The K2 UL grant was frozen at an earlier control
                % occasion.  A DL HARQ-ACK due in this UL slot can be
                % created only after the originating PDSCH is decoded,
                % which is later than that control decision.  Reconcile
                % the now-complete due-slot state before executing either
                % PUSCH or PUCCH.  Otherwise the same UE can incorrectly
                % emit a standalone PUCCH and a PUSCH on overlapping UL
                % resources even though TS 38.212 UCI-on-PUSCH
                % multiplexing is available.
                if localPUSCHUCIOnPUSCHAvailable(cfg)
                    [runtimeState, ulGrants] = sixgr.truth.CoupledTruthRuntime. ...
                        multiplexDueHARQACKOnPUSCHRuntime( ...
                        runtimeState, ulGrants, absoluteFrame);
                end
                [ulGrants, latePUCCHCollisionBlocked] = ...
                    sixgr.truth.CoupledTruthRuntime. ...
                    excludeULGrantsCollidingWithPUCCHRuntime( ...
                    runtimeState, ulGrants, absoluteFrame);
                if istable(latePUCCHCollisionBlocked) && ...
                        ~isempty(latePUCCHCollisionBlocked)
                    localAppendRuntimeLog("INFO", ...
                        "Suppressed queued PUSCH grants after due-slot PUCCH reconciliation: slot=%d blocked=%d remaining=%d.", ...
                        round(double(absoluteFrame)), ...
                        height(latePUCCHCollisionBlocked), numel(ulGrants));
                end
            end
            runtimeState = localRecordQueuedULScheduleForCurrentSlot(runtimeState, ulGrants);
            sharedDueULGrants=ulGrants;
            if ~isempty(ulGrants) && ~isfield(runtimeState,'SharedWaveformStream')
                [runtimeState, ulTrials, ulConstT, ulStates] = localExecuteCoupledDirectionBatch( ...
                    runtimeState, cfg, runFolder, multiUser, userCfg, ulGrants, "UL", snrVal, absoluteFrame, ulStates, ...
                    ulTrials, dlTrials, ulConstT, dlConstT, ulTablePath, dlTablePath, ulConstellationPath, dlConstellationPath, ...
                    sweepIdx, numel(snrGrid), frameLocal, nFramesPerPoint);
            end
        end
        if isfield(runtimeState,'SharedWaveformStream')
            runtimeState=sixgr.truth.advanceSharedSlotWithULGrants( ...
                runtimeState,cfg,pendingULGrants,sharedDueULGrants, ...
                @localCompleteSharedControlObservations);
            [runtimeState,dlTrials,ulTrials,dlConstT,ulConstT,dlStates,ulStates] = ...
                localDrainSharedDataPlans(runtimeState,dlTrials,ulTrials,dlConstT,ulConstT,dlStates,ulStates);
            pendingULGrants=sixgr.util.structGet(runtimeState,'SharedPendingULGrants',repmat(struct(),0,1));
            runtimeState.CompletedCanonicalSlots=double(absoluteFrame);
            liveRawTrials=localBuildCoupledTruthRawTrialsAggregate(dlTrials,ulTrials,multiUser,runtimeState.ControlTrials,cfg);
            localPublishCoupledTruthRuntimeState(cfg,runFolder,liveRawTrials,multiUser,runtimeState, ...
                dlTablePath,ulTablePath,dlConstellationPath,ulConstellationPath,dlConstT,ulConstT, ...
                publishDirection,snrVal,sweepIdx,numel(snrGrid),0,numel(userCfg),frameLocal,nFramesPerPoint, ...
                sixgr.util.structGet(runtimeState,'SharedWaveformPreviewTable',table()), ...
                'SlotComplete',true,'PublishReason','shared_physical_receive_completions');
        else
            % No-grant/control-only slots advance the radio clock too. A
            % directional chunk above is not completion of the whole slot.
            runtimeState.CompletedCanonicalSlots=double(absoluteFrame);
            radioProgress=sixgr.truth.resolveRuntimeClockProgress(runtimeState);
            localPublishWaveformBundleStageStatus(runFolder,radioProgress);
        end
        sixgr.runtime.ExecutionStageProfiler.flush();
        if checkpointEnabled && sixgr.runtime.CheckpointSchedule.due(absoluteFrame, ...
                double(cfg.run.checkpointEverySlots), ...
                double(sixgr.util.structGet(cfg,'run.checkpointFirstSlot',0)))
            if isfield(runtimeState,'SharedWaveformStream')
                runtimeState.SharedWaveformStream.archiveCompletedSampleOwners(rootRunFolder);
            end
            checkpointPayload=struct('RuntimeState',runtimeState, ...
                'ConfigHash',string(cfg.meta.configHash), ...
                'CompletedSlot',absoluteFrame,'RNG',rng,'SweepIndex',sweepIdx, ...
                'FrameLocal',frameLocal,'FramesPerPoint',nFramesPerPoint, ...
                'SNRGrid',snrGrid,'PendingULGrants',pendingULGrants, ...
                'DLTrials',dlTrials,'ULTrials',ulTrials, ...
                'DLConstellations',dlConstT,'ULConstellations',ulConstT, ...
                'DLStates',{dlStates},'ULStates',{ulStates});
            if isfield(cfg.run,'executionHorizon')
                checkpointPayload.ExecutionHorizon=cfg.run.executionHorizon;
            end
            checkpointPath=sixgr.runtime.SlotCheckpoint.write(rootRunFolder, ...
                checkpointPayload,cfg.run.runtimeCheckpointScenario,checkpointSource);
            clear checkpointPayload;
            localAppendRuntimeLog('INFO', ...
                'Exact completed-slot checkpoint saved: completed_slot=%d next_slot=%d path=%s.', ...
                absoluteFrame,absoluteFrame+1,checkpointPath);
        end
        [runtimeState, profileCtl] = localMaybeFlushCoupledProfileSnapshot(runtimeState, rootRunFolder, profileCtl, absoluteFrame);
        [stopCoupledProfile, stopReason] = localShouldStopCoupledProfile(runtimeState, profileCtl, absoluteFrame, dlTrials, ulTrials);
        if stopCoupledProfile
            runtimeState.ProfileStopReason = string(stopReason);
            runtimeState = localWriteCoupledRuntimeTables(runtimeState, rootRunFolder);
            localAppendRuntimeLog("WARN", ...
                "Coupled profiled run stopped early at slot=%d/%d: %s.", ...
                round(double(frameLocal)), round(double(nFramesPerPoint)), char(string(stopReason)));
            break;
        end
    end
    localMaybeAppendSweepProgressLog("DL", snrVal, sweepIdx, numel(snrGrid), dlTrials);
    localMaybeAppendSweepProgressLog("UL", snrVal, sweepIdx, numel(snrGrid), ulTrials);
    if stopCoupledProfile
        break;
    end
end
if isfield(runtimeState,'SharedWaveformStream')
    runtimeState=runtimeState.SharedWaveformStream.drainDataReceiveTail( ...
        runtimeState,cfg,@localCompleteSharedControlObservations);
    [runtimeState,dlTrials,ulTrials,dlConstT,ulConstT,dlStates,ulStates] = ...
        localDrainSharedDataPlans(runtimeState,dlTrials,ulTrials,dlConstT,ulConstT,dlStates,ulStates);
    if isfield(runtimeState,'SharedReceiveTailTable')
        tail=runtimeState.SharedReceiveTailTable;
        sixgr.util.csvWriteTable(fullfile(rootRunFolder,'reports','csv','shared_receive_tail.csv'),tail);
        localAppendRuntimeLog('INFO', ...
            'Drained actual shared data receive tail: samples=[%d,%d) observations=%d scheduled_slots=%d dl_rows=%d ul_rows=%d.', ...
            tail.StartSample,tail.EndSampleExclusive,tail.PendingDataObservationCount, ...
            tail.ScheduledSlotCount,height(dlTrials),height(ulTrials));
    end
end
if isfield(runtimeState,'SharedWaveformStream') && ...
        any(ismember(string({runtimeState.SharedWaveformStream.Pending.Kind}),["PDSCH","PUSCH","PUSCHReceiveOnly"]))
    error('sixgr:truth:SharedDataReceiveTailNotDrained', ...
        'The scheduling horizon ended with actual data observations pending. Drain those physical receive tails before finalizing results.');
end
if isfield(runtimeState,'SharedWaveformStream') && ...
        logical(sixgr.util.structGet(cfg,'outputs.continuousRawIQCaptureEnabled',false))
    carrier=sixgr.phy.grid.makeCarrier(cfg);
    expectedEndSample=sixgr.phy.frame.slotStartSample( ...
        carrier,totalCanonicalSlots,runtimeState.SharedWaveformStream.SampleRateHz);
    runtimeState.ContinuousTxIQCapture= ...
        runtimeState.SharedWaveformStream.finalizeContinuousTxIQCapture( ...
        expectedEndSample,totalCanonicalSlots);
    localAppendRuntimeLog('INFO', ...
        ['Sealed continuous shared-clock Tx-IQ: samples_per_port=%d ' ...
         'physical_transmitters=%d manifest=%s.'], ...
        runtimeState.ContinuousTxIQCapture.SampleCount, ...
        runtimeState.ContinuousTxIQCapture.EndpointCount, ...
        char(runtimeState.ContinuousTxIQCapture.ManifestPath));
end
catch ME
    ME = localPersistCoupledRuntimeFailureCheckpoint( ...
        ME, runtimeState, rootRunFolder, cfg, dlTrials, ulTrials, ...
        dlTablePath, ulTablePath, dlConstT, ulConstT, dlConstellationPath, ulConstellationPath);
    rethrow(ME);
end

terminalReason = "finite_runtime_horizon_reached";
if isfield(cfg.run,'executionHorizon')
    terminalReason="explicit_bounded_checkpoint_horizon_reached";
end
if logical(stopCoupledProfile)
    terminalReason = "profiled_runtime_horizon_reached:" + ...
        string(sixgr.util.structGet(runtimeState, "ProfileStopReason", "configured_profile_stop"));
end
runtimeState = sixgr.truth.CoupledTruthRuntime.finalizeFiniteHorizonRuntime( ...
    runtimeState, double(sixgr.util.structGet(runtimeState, "CurrentSlot", 0)), terminalReason);
controlTrials = runtimeState.ControlTrials;
harqTimelineT = sixgr.util.structGet(runtimeState, "HARQTimelineTable", table());
dlTrials = localHydrateHARQTrialColumnsFromTimeline(dlTrials, harqTimelineT, "DL");
ulTrials = localHydrateHARQTrialColumnsFromTimeline(ulTrials, harqTimelineT, "UL");
finalRawTrials = localBuildCoupledTruthRawTrialsAggregate(dlTrials, ulTrials, multiUser, controlTrials, cfg);
dlSummaryT = sixgr.util.structGet(finalRawTrials, "MultiUserDL", table());
ulSummaryT = sixgr.util.structGet(finalRawTrials, "MultiUserUL", table());
dlTrials = localCanonicalizeLinkTrialExport(dlTrials, "DL", cfg);
ulTrials = localCanonicalizeLinkTrialExport(ulTrials, "UL", cfg);
sixgr.util.csvWriteTable(dlTablePath, dlTrials, "PreserveSchema", true);
sixgr.util.csvWriteTable(ulTablePath, ulTrials, "PreserveSchema", true);
if strlength(string(dlConstellationPath)) > 0 && istable(dlConstT) && ~isempty(dlConstT)
    sixgr.util.csvWriteTable(dlConstellationPath, localDownsampleConstellationTable(dlConstT, 2500));
end
if strlength(string(ulConstellationPath)) > 0 && istable(ulConstT) && ~isempty(ulConstT)
    sixgr.util.csvWriteTable(ulConstellationPath, localDownsampleConstellationTable(ulConstT, 2500));
end
localWriteCoupledRuntimeTables(runtimeState, fileparts(char(string(runFolder))));
end

function [state, pendingULGrants, plannedGrants] = localScheduleCoupledFutureULGrantsFromDLControl(state, cfg, userCfg, pendingULGrants, snr_dB, sweepIdx, sweepCount, frameLocal, nFramesPerPoint, planOnly)
if nargin<10, planOnly=false; end
if nargin<4 || ~isstruct(pendingULGrants)
    pendingULGrants=repmat(struct(),0,1);
end
[state,plannedGrants,planning]=sixgr.truth.planFutureULGrants( ...
    state,cfg,userCfg,pendingULGrants,sweepIdx,nFramesPerPoint);
if planning.Status=="timing_opportunity_deferred"
    opportunity=planning.Opportunity;
    localAppendRuntimeLog("INFO", ...
        "Coupled UL K2 preschedule deferred: control_slot=%d reason=%s evaluated_candidates=%d source=packet_flow/csv/ul_scheduler_timing.csv.", ...
        planning.ControlSlot,char(opportunity.BlockReason),opportunity.EvaluatedCandidateCount);
end
if planning.ScheduleAttempted
    info=planning.SchedulingInfo;
    localAppendRuntimeLog("INFO", ...
        "Coupled UL K2 preschedule complete: control_slot=%d due_slot=%d k2=%d active=%d granted=%d grants=%d reason=%s resource_reason=%s admission_details=%s.", ...
        planning.ControlSlot,planning.DataSlot,planning.K2, ...
        round(double(sixgr.util.structGet(info,"ActiveUsers",NaN))), ...
        round(double(sixgr.util.structGet(info,"GrantedUsers",NaN))), ...
        planning.SchedulerGrantCount, ...
        char(string(sixgr.util.structGet(info,"NoGrantReason",""))), ...
        char(string(sixgr.util.structGet(info,"ResourceUnavailableReason",""))), ...
        char(string(info.NoGrantDetails)));
end
if planning.SRSDeferredCount>0
    localAppendRuntimeLog("INFO", ...
        "Deferred PUSCH candidates before UL DCI for authored first-SRS priority: control_slot=%d data_slot=%d deferred=%d.", ...
        planning.ControlSlot,planning.DataSlot,planning.SRSDeferredCount);
end
if isempty(plannedGrants) || planOnly, return; end
[state,pendingULGrants]=localTransmitCoupledFutureULGrants( ...
    state,cfg,userCfg,pendingULGrants,plannedGrants,snr_dB);
end

function [state,pendingULGrants]=localTransmitCoupledFutureULGrants(state,cfg,userCfg,pendingULGrants,grants,snr_dB)
if isempty(grants), return; end
dueSlot=sixgr.truth.runtimeULGrantSlot(grants(1));
controlSlot=double(state.CurrentSlot);
uciOnPUSCHAvailable=localPUSCHUCIOnPUSCHAvailable(cfg);
[state, qualifiedGrants] = localQualifyCoupledGrantsWithPDCCH(state, userCfg, grants, "UL", snr_dB);
if isfield(state,'SharedWaveformStream')
    % The receiver callback owns acceptance and future UE preparation.
    % No queued PDCCH may masquerade as a decoded UL grant here.
    return;
end
if uciOnPUSCHAvailable && ~isempty(qualifiedGrants)
    % Reserve the exact pending DL HARQ feedback only after the future UL
    % grant has passed its PDCCH/DCI authority boundary.  The reservation
    % prevents a standalone PUCCH from being emitted at the same occasion,
    % and binds every ACK/NACK bit (not only the first one) to the PUSCH
    % waveform and later PUSCH-UCI decoder result.
    [state, qualifiedGrants] = sixgr.truth.CoupledTruthRuntime. ...
        multiplexDueHARQACKOnPUSCHRuntime(state, qualifiedGrants, dueSlot);
end
if isempty(qualifiedGrants)
    localAppendRuntimeLog("INFO", ...
        "Coupled UL K2 preschedule produced no executable grants after PDCCH: control_slot=%d due_slot=%d.", ...
        round(double(controlSlot)), round(double(dueSlot)));
    return;
end
[qualifiedGrants, pucchCollisionBlocked] = sixgr.truth.CoupledTruthRuntime.excludeULGrantsCollidingWithPUCCHRuntime( ...
    state, qualifiedGrants, dueSlot);
if istable(pucchCollisionBlocked) && ~isempty(pucchCollisionBlocked)
    localAppendRuntimeLog("INFO", ...
        "Suppressed standalone PUSCH grants that collide with due HARQ-ACK PUCCH: control_slot=%d due_slot=%d blocked=%d remaining=%d policy=avoid_standalone_pusch_without_uci_on_pusch_multiplexing.", ...
        round(double(controlSlot)), round(double(dueSlot)), height(pucchCollisionBlocked), numel(qualifiedGrants));
end
if isempty(qualifiedGrants)
    return;
end
for gi = 1:numel(qualifiedGrants)
    ueIdx = sixgr.truth.GrantPreparation.resolveGrantUEIndex(qualifiedGrants(gi), state.MultiUser);
    feedback = sixgr.truth.CoupledTruthRuntime.latestFeedbackForDirectionRuntime(state, ueIdx, "UL");
    state = sixgr.truth.CoupledTruthRuntime.appendGrantTraceRuntime(state, qualifiedGrants(gi), "UL", feedback);
end
pendingULGrants = localAppendCoupledPendingULGrants(pendingULGrants, qualifiedGrants);
localAppendRuntimeLog("INFO", ...
    "Queued coupled UL grants after K2 PDCCH qualification: control_slot=%d due_slot=%d executable_grants=%d pending_total=%d.", ...
    round(double(controlSlot)), round(double(dueSlot)), numel(qualifiedGrants), numel(pendingULGrants));
end

function tf = localPUSCHUCIOnPUSCHAvailable(cfg)
tf=sixgr.truth.isPUSCHUCIAvailable(cfg);
end

function varargout = localAppendCoupledPendingULGrants(varargin)
% Compatibility delegate; the implementation and schema have one owner.
[varargout{1:nargout}] = sixgr.truth.PDCCHControlRuntime.appendCoupledPendingULGrants(varargin{:});
end

function [dueGrants, pendingULGrants, staleCount] = localPopDueCoupledULGrants(pendingULGrants, slotIdx)
dueGrants = repmat(struct(), 0, 1);
staleCount = 0;
if ~(isstruct(pendingULGrants) && ~isempty(pendingULGrants))
    pendingULGrants = repmat(struct(), 0, 1);
    return;
end
slots = arrayfun(@sixgr.truth.runtimeULGrantSlot,pendingULGrants(:));
dueMask = abs(slots - double(slotIdx)) < 1e-9;
staleMask = isfinite(slots) & slots < double(slotIdx) & ~dueMask;
staleCount = sum(staleMask);
if any(dueMask)
    dueGrants = pendingULGrants(dueMask);
end
pendingULGrants = pendingULGrants(~dueMask & ~staleMask);
end

function varargout = localRecordQueuedULScheduleForCurrentSlot(varargin)
% Compatibility delegate; completion/publication has one production owner.
[varargout{1:nargout}] = sixgr.truth.SharedDataCompletionRuntime.recordQueuedULSchedule(varargin{:});
end

function varargout = localCountQueuedULSchedulerDecisionRows(varargin)
% Compatibility delegate; completion/publication has one production owner.
[varargout{1:nargout}] = sixgr.truth.SharedDataCompletionRuntime.countQueuedULSchedulerDecisionRows(varargin{:});
end

function [Tu, constT, waveT, laState, res, job] = localRunSingleFrameDirectionTrial(cfg, multiUser, ueIdx, direction, snr_dB, frameIdx, laStateIn, trialContext)
if nargin < 8 || ~isstruct(trialContext)
    trialContext = struct();
end
job = sixgr.truth.GrantPreparation.buildJob(cfg, direction, snr_dB, frameIdx, laStateIn, trialContext);
jobResult = sixgr.truth.executeGrantPHYJob(job);
if job.PrepareOnly
    Tu=table(); constT=table(); waveT=table(); laState=laStateIn;
    res=jobResult.Result;
    return;
end
res = sixgr.util.structGet(jobResult, "Result", struct());
laState = sixgr.util.structGet(jobResult, "LinkAdaptationState", laStateIn);
[Tu,constT,waveT]=localFinalizeCompletedGrantTables(res,job.Cfg,multiUser,ueIdx,direction,snr_dB);
end

function varargout = localFinalizeCompletedGrantTables(varargin)
% Compatibility delegate; completion/publication has one production owner.
[varargout{1:nargout}] = sixgr.truth.SharedDataCompletionRuntime.finalizeTables(varargin{:});
end

function [runtimeState, primaryTrials, primaryConstT, laStates] = localExecuteCoupledDirectionBatch( ...
        runtimeState, cfg, runFolder, multiUser, userCfg, grants, direction, snr_dB, absoluteFrame, laStates, ...
        primaryTrials, secondaryTrials, primaryConstT, secondaryConstT, primaryTablePath, secondaryTablePath, ...
        primaryConstellationPath, secondaryConstellationPath, sweepIdx, sweepCount, frameLocal, nFramesPerPoint)
direction = upper(string(direction));
localAppendRuntimeLog("INFO", ...
    "Preparing coupled %s batches: sweep=%d/%d slot=%d/%d candidate_grants=%d batch_size=%d.", ...
    char(direction), round(double(sweepIdx)), round(double(sweepCount)), round(double(frameLocal)), round(double(nFramesPerPoint)), ...
    numel(grants), max(1, round(double(sixgr.util.structGet(cfg, 'run.batchSizeLinks', numel(grants))))));
if isfield(runtimeState,'SharedWaveformStream')
    runtimeState=sixgr.truth.queueSharedDataPlans(runtimeState,cfg,multiUser,userCfg,grants, ...
        direction,snr_dB,absoluteFrame,laStates);
    return;
end
chunkSize = max(1, round(double(sixgr.util.structGet(cfg, "run.batchSizeLinks", numel(grants)))));
    [resolvedGrantCache, runtimeState] = localBuildCoupledResolvedGrantCache(runtimeState, cfg, multiUser, userCfg, grants, direction);
interferenceCacheKey = "";
interferenceCachePayload = struct();
interferenceWorkerCache = [];
if localCanUseLightweightCoupledInterferenceCache(cfg, resolvedGrantCache)
    cacheRuntimeState = localCompactCoupledRuntimeStateForWorkerTransfer(runtimeState);
    cacheGrantEntries = localSanitizeCoupledResolvedGrantCacheForWorkerTransfer(resolvedGrantCache);
    interferenceCachePayload = struct( ...
        "ResolvedGrantCache", cacheGrantEntries, ...
        "BSAntennaRuntime", sixgr.util.structGet(cacheRuntimeState, "BSAntennaRuntime", repmat(struct(), 0, 1)), ...
        "UEAntennaRuntime", sixgr.util.structGet(cacheRuntimeState, "UEAntennaRuntime", repmat(struct(), 0, 1)), ...
        "Layout", sixgr.util.structGet(cacheRuntimeState, "Layout", struct()));
    interferenceCacheKey = localRegisterCoupledInterferenceCache(interferenceCachePayload, direction, sweepIdx, frameLocal, absoluteFrame);
    cleanupInterferenceCache = onCleanup(@() sixgr.link.interferenceReplayCache("remove", interferenceCacheKey)); %#ok<NASGU>
    interferenceWorkerCache = localCreateParallelInterferenceReplayCacheConstant(interferenceCacheKey, interferenceCachePayload, cfg);
end
for chunkStart = 1:chunkSize:numel(grants)
    chunkEnd = min(numel(grants), chunkStart + chunkSize - 1);
    grantChunk = grants(chunkStart:chunkEnd);
    chunk = sixgr.truth.GrantPreparation.prepareCoupledGrantBatch(runtimeState, cfg, multiUser, userCfg, grantChunk, direction, snr_dB, absoluteFrame, laStates, grants, chunkStart - 1, resolvedGrantCache);
    if isempty(chunk)
        localAppendRuntimeLog("INFO", ...
            "Preparing coupled %s chunk yielded zero executable plans: sweep=%d/%d slot=%d/%d chunk=%d-%d.", ...
            char(direction), round(double(sweepIdx)), round(double(sweepCount)), round(double(frameLocal)), round(double(nFramesPerPoint)), ...
            round(double(chunkStart)), round(double(chunkEnd)));
        continue;
    end
    localAppendRuntimeLog("INFO", ...
        "Prepared coupled %s chunk: sweep=%d/%d slot=%d/%d executable_plans=%d chunk=%d-%d of %d.", ...
        char(direction), round(double(sweepIdx)), round(double(sweepCount)), round(double(frameLocal)), round(double(nFramesPerPoint)), ...
        numel(chunk), round(double(chunkStart)), round(double(chunkEnd)), round(double(numel(grants))));
    localAppendRuntimeLog("INFO", ...
        "Executing coupled %s chunk: sweep=%d/%d slot=%d/%d chunk=%d-%d of %d.", ...
        char(direction), round(double(sweepIdx)), round(double(sweepCount)), round(double(frameLocal)), round(double(nFramesPerPoint)), ...
        round(double(chunkStart)), round(double(chunkEnd)), round(double(numel(grants))));
    progressContext = struct( ...
        "RunFolder", string(runFolder), ...
        "SweepIdx", double(sweepIdx), ...
        "SweepCount", double(sweepCount), ...
        "FrameLocal", double(frameLocal), ...
        "TotalFrames", double(nFramesPerPoint), ...
        "ChunkStart", double(chunkStart), ...
        "ChunkEnd", double(chunkEnd), ...
        "GrantCount", double(numel(grants)), ...
        "PrimaryTrialRows", double(height(primaryTrials)), ...
        "SecondaryTrialRows", double(height(secondaryTrials)));
    localPublishCoupledGrantExecutionHeartbeat(progressContext, struct(), direction, snr_dB, absoluteFrame, ...
        "chunk_start", 0, numel(chunk), runtimeState);
    [chunk, runtimeState] = localRunCoupledGrantBatch(chunk, runtimeState, resolvedGrantCache, multiUser, direction, snr_dB, absoluteFrame, interferenceCacheKey, interferenceWorkerCache, progressContext);
    localPublishCoupledGrantExecutionHeartbeat(progressContext, struct(), direction, snr_dB, absoluteFrame, ...
        "chunk_complete", numel(chunk), numel(chunk), runtimeState);
    chunkWaveformPreviewT = table();
    chunkLastUEIdx = NaN;
    chunkHadCommittedGrant = false;
    for bi = 1:numel(chunk)
        if ~logical(sixgr.util.structGet(chunk(bi), "Valid", false))
            continue;
        end
        ueIdx = double(chunk(bi).UEIndex);
        runtimeState = sixgr.truth.CoupledTruthRuntime.setCurrentUE(runtimeState, ueIdx, direction);
        userT = localAnnotateGrantDrivenTrials(sixgr.util.structGet(chunk(bi), "TrialTable", table()), chunk(bi).GrantRow);
        runtimeState = sixgr.truth.CoupledTruthRuntime.commitRuntimeChannelState( ...
            runtimeState, sixgr.util.structGet(chunk(bi).Result, "ChannelState", struct()));
        runtimeState = sixgr.truth.CoupledTruthRuntime.commitGrantExecution(runtimeState, ueIdx, direction, chunk(bi).GrantSnapshot);
        [runtimeState, userT] = localCompleteCoupledRuntimeSlot(runtimeState, chunk(bi).Cfg, ueIdx, direction, userT, chunk(bi).Result);
        runtimeState = localCaptureCommittedFullPHYISAC( ...
            runtimeState,cfg,chunk(bi),direction);
        runtimeState = localCaptureCommittedTxIQ( ...
            runtimeState,cfg,chunk(bi),direction);
        if isfield(chunk(bi).Result,"ISACWaveformCapture")
            chunk(bi).Result.ISACWaveformCapture = struct();
        end
        if isfield(chunk(bi).Result,"TxWaveformCapture")
            chunk(bi).Result.TxWaveformCapture = struct();
        end
        userT = sixgr.truth.annotateFrozenMUMIMOTrialEvidence(userT, chunk(bi).GrantSnapshot);
        userT = sixgr.link.applyMeasuredDLMUMIMOReceiverEvidence(userT);
        % Scheduled operating-point evidence depends on the immutable
        % frozen-grant identifier added immediately above.  The link-level
        % producer cannot materialize this relationship earlier because it
        % has not yet been joined to the coupled scheduler grant.  Finalize
        % it here, after the authoritative grant annotation and before the
        % row enters the primary runtime aggregate.
        userT = sixgr.link.applyScheduledOperatingPointEvidence(userT);
        primaryTrials = localAppendCompatTable(primaryTrials, userT);
        primaryConstT = localAppendCompatTable(primaryConstT, sixgr.util.structGet(chunk(bi), "ConstellationTable", table()));
        runtimeState.ObservedREAllocationTable = localAppendObservedREAllocation( ...
            sixgr.util.structGet(runtimeState, "ObservedREAllocationTable", table()), ...
            sixgr.util.structGet(chunk(bi).Result, "ObservedREAllocationTable", table()));
        runtimeState = localRecordPHYSignalDiagnostic(runtimeState, direction, ...
            sixgr.util.structGet(chunk(bi).Result, "SignalDiagnostic", struct()));
        % CoupledTruthRuntime.completeSlotImpl is the single authority for
        % committing the exact CSI-RS measurement row consumed by delayed
        % CSI feedback.  Appending Result.CSIRSTrialTable again here created
        % duplicate same-slot producer rows and broke one-to-one lineage.
        laStates{ueIdx} = sixgr.util.structGet(chunk(bi), "LinkAdaptationState", laStates{ueIdx});
        chunkWaveformPreviewT = localAppendCompatTable(chunkWaveformPreviewT, sixgr.util.structGet(chunk(bi), "WaveformPreviewTable", table()));
        % Live refreshes only receive this chunk. Retain every committed
        % grant's actual waveform preview for final publication as well.
        runtimeState.WaveformPreviewTable = localAppendCompatTable( ...
            sixgr.util.structGet(runtimeState, "WaveformPreviewTable", table()), ...
            sixgr.util.structGet(chunk(bi), "WaveformPreviewTable", table()));
        chunkLastUEIdx = double(ueIdx);
        chunkHadCommittedGrant = true;
    end
    if ~chunkHadCommittedGrant
        continue;
    end
    localAppendRuntimeLog("INFO", ...
        "Publishing coupled %s chunk results: sweep=%d/%d slot=%d/%d committed_rows=%d current_primary_rows=%d.", ...
        char(direction), round(double(sweepIdx)), round(double(sweepCount)), round(double(frameLocal)), round(double(nFramesPerPoint)), ...
        round(double(chunkEnd - chunkStart + 1)), height(primaryTrials));
    if direction == "DL"
        liveRawTrials = localBuildCoupledTruthRawTrialsAggregate(primaryTrials, secondaryTrials, multiUser, runtimeState.ControlTrials, cfg);
        localPublishCoupledTruthRuntimeState(cfg, runFolder, liveRawTrials, multiUser, runtimeState, ...
            primaryTablePath, secondaryTablePath, primaryConstellationPath, secondaryConstellationPath, primaryConstT, secondaryConstT, ...
            direction, snr_dB, sweepIdx, sweepCount, chunkLastUEIdx, numel(userCfg), frameLocal, nFramesPerPoint, chunkWaveformPreviewT, ...
            "SlotComplete", localIsCoupledDirectionalPublishSlotComplete(runtimeState, direction), ...
            "FinalDirectionChunk", chunkEnd >= numel(grants), "PublishReason", "post_grant_chunk");
    else
        liveRawTrials = localBuildCoupledTruthRawTrialsAggregate(secondaryTrials, primaryTrials, multiUser, runtimeState.ControlTrials, cfg);
        localPublishCoupledTruthRuntimeState(cfg, runFolder, liveRawTrials, multiUser, runtimeState, ...
            secondaryTablePath, primaryTablePath, secondaryConstellationPath, primaryConstellationPath, secondaryConstT, primaryConstT, ...
            direction, snr_dB, sweepIdx, sweepCount, chunkLastUEIdx, numel(userCfg), frameLocal, nFramesPerPoint, chunkWaveformPreviewT, ...
            "SlotComplete", localIsCoupledDirectionalPublishSlotComplete(runtimeState, direction), ...
            "FinalDirectionChunk", chunkEnd >= numel(grants), "PublishReason", "post_grant_chunk");
    end
end
end




function [batch, runtimeState] = localRunCoupledGrantBatch(batch, runtimeState, resolvedGrantCache, multiUser, direction, snr_dB, absoluteFrame, interferenceCacheKey, interferenceWorkerCache, progressContext)
if isempty(batch)
    return;
end
if nargin < 9
    interferenceWorkerCache = [];
end
if nargin < 10
    progressContext = struct();
end
useParallel = localCanParallelizeCoupledGrantBatch(batch, sixgr.util.structGet(batch(1), "Cfg", struct()));
if useParallel
    batchWorker = localSanitizeCoupledGrantBatchForWorkerTransfer(batch);
    runtimeStateWorker = localCompactCoupledRuntimeStateForWorkerTransfer(runtimeState);
    resolvedGrantCacheWorker = localSanitizeCoupledResolvedGrantCacheForWorkerTransfer(resolvedGrantCache);
    results = cell(numel(batch), 1);
    if localHasParallelInterferenceReplayCache(interferenceWorkerCache)
        localAppendRuntimeLog("INFO", ...
            "Executing coupled %s grant chunk in parfor: plans=%d interference_cache=worker_local_lightweight.", ...
            char(upper(string(direction))), numel(batch));
        workerCache = interferenceWorkerCache;
        localPublishCoupledGrantExecutionHeartbeat(progressContext, struct(), direction, snr_dB, absoluteFrame, ...
            "parfor_chunk_start", 0, numel(batch), runtimeState);
        parfor bi = 1:numel(batch)
            results{bi} = localExecuteCoupledGrantBatchPlan(batchWorker(bi), runtimeStateWorker, resolvedGrantCacheWorker, multiUser, direction, snr_dB, absoluteFrame, workerCache.Value);
        end
        localPublishCoupledGrantExecutionHeartbeat(progressContext, struct(), direction, snr_dB, absoluteFrame, ...
            "parfor_chunk_complete", numel(batch), numel(batch), runtimeState);
    else
        localAppendRuntimeLog("INFO", ...
            "Executing coupled %s grant chunk in parfor: plans=%d interference_cache=inline_bundle.", ...
            char(upper(string(direction))), numel(batch));
        localPublishCoupledGrantExecutionHeartbeat(progressContext, struct(), direction, snr_dB, absoluteFrame, ...
            "parfor_chunk_start", 0, numel(batch), runtimeState);
        parfor bi = 1:numel(batch)
            results{bi} = localExecuteCoupledGrantBatchPlan(batchWorker(bi), runtimeStateWorker, resolvedGrantCacheWorker, multiUser, direction, snr_dB, absoluteFrame, "");
        end
        localPublishCoupledGrantExecutionHeartbeat(progressContext, struct(), direction, snr_dB, absoluteFrame, ...
            "parfor_chunk_complete", numel(batch), numel(batch), runtimeState);
    end
    for bi = 1:numel(batch)
        batch(bi) = localMergeCoupledGrantBatchWorkerResult(batch(bi), results{bi});
    end
else
    if logical(sixgr.util.structGet(batch(1).Cfg, "run.useParallel", false)) && numel(batch) > 1
        localAppendRuntimeLog("INFO", ...
            "Executing coupled %s grant chunk serially: plans=%d reason=parallel_safety_or_pool_unavailable.", ...
            char(upper(string(direction))), numel(batch));
    end
    for bi = 1:numel(batch)
        localPublishCoupledGrantExecutionHeartbeat(progressContext, batch(bi), direction, snr_dB, absoluteFrame, ...
            "grant_start", bi, numel(batch), runtimeState);
        [resultPlan, runtimeState] = localExecuteCoupledGrantBatchPlan(batch(bi), runtimeState, resolvedGrantCache, multiUser, direction, snr_dB, absoluteFrame, interferenceCacheKey);
        localPublishCoupledGrantExecutionHeartbeat(progressContext, resultPlan, direction, snr_dB, absoluteFrame, ...
            "grant_complete", bi, numel(batch), runtimeState);
        batch(bi) = localMergeCoupledGrantBatchWorkerResult(batch(bi), resultPlan);
    end
end
end

function localPublishCoupledGrantExecutionHeartbeat(progressContext, plan, direction, snr_dB, absoluteFrame, phase, planIndex, planCount, runtimeState)
if ~(isstruct(progressContext) && isfield(progressContext, "RunFolder"))
    return;
end
runFolder = string(sixgr.util.structGet(progressContext, "RunFolder", ""));
if strlength(strtrim(runFolder)) == 0
    return;
end
direction = upper(string(direction));
ueIdx = double(sixgr.util.structGet(plan, "UEIndex", NaN));
grantIdx = double(sixgr.util.structGet(plan, "GrantIndex", NaN));
frameLocal = double(sixgr.util.structGet(progressContext, "FrameLocal", absoluteFrame));
totalFrames = double(sixgr.util.structGet(progressContext, "TotalFrames", NaN));
if ~(isfinite(totalFrames) && totalFrames > 0)
    totalFrames = double(sixgr.util.structGet(runtimeState, "TotalFrames", NaN));
end
grantCount = double(sixgr.util.structGet(progressContext, "GrantCount", NaN));
chunkStart = double(sixgr.util.structGet(progressContext, "ChunkStart", NaN));
chunkEnd = double(sixgr.util.structGet(progressContext, "ChunkEnd", NaN));
dlRows = NaN;
ulRows = NaN;
primaryRows = double(sixgr.util.structGet(progressContext, "PrimaryTrialRows", NaN));
secondaryRows = double(sixgr.util.structGet(progressContext, "SecondaryTrialRows", NaN));
if direction == "DL"
    dlRows = primaryRows;
    ulRows = secondaryRows;
else
    dlRows = secondaryRows;
    ulRows = primaryRows;
end
runCompletion = NaN;
if isfinite(frameLocal) && isfinite(totalFrames) && totalFrames > 0
    runCompletion = min(1, max(0, frameLocal / totalFrames));
end
dlGrantCount = NaN;
ulGrantCount = NaN;
if direction == "DL"
    dlGrantCount = double(planCount);
else
    ulGrantCount = double(planCount);
end
notes = sprintf("phase=%s grant=%s/%s ue=%s grantIndex=%s chunk=%s-%s/%s absoluteSlot=%s heartbeat_only_no_trial_rows", ...
    char(string(phase)), localDisplayProgressValue(planIndex), localDisplayProgressValue(planCount), ...
    localDisplayProgressValue(ueIdx), localDisplayProgressValue(grantIdx), ...
    localDisplayProgressValue(chunkStart), localDisplayProgressValue(chunkEnd), ...
    localDisplayProgressValue(grantCount), localDisplayProgressValue(absoluteFrame));
status = struct( ...
    "Stage", "coupled_grant_execution", ...
    "CurrentDirection", char(direction), ...
    "CurrentSNR_dB", double(snr_dB), ...
    "SweepPointIndex", double(sixgr.util.structGet(progressContext, "SweepIdx", NaN)), ...
    "SweepPointCount", double(sixgr.util.structGet(progressContext, "SweepCount", NaN)), ...
    "CurrentUEIndex", ueIdx, ...
    "TotalUsers", double(sixgr.util.structGet(runtimeState, "NumUsers", NaN)), ...
    "CurrentSlot", double(frameLocal), ...
    "TotalSlots", double(totalFrames), ...
    "CompletedFrames", double(frameLocal), ...
    "TotalFrames", double(totalFrames), ...
    "RunCompletion", runCompletion, ...
    "DLTrialRows", dlRows, ...
    "ULTrialRows", ulRows, ...
    "DLGrantCount", dlGrantCount, ...
    "ULGrantCount", ulGrantCount, ...
    "Notes", notes);
localPublishWaveformBundleStageStatus(char(runFolder), status);
end

function planOut = localMergeCoupledGrantBatchWorkerResult(planIn, workerPlan)
planOut = planIn;
if ~(isstruct(workerPlan) && ~isempty(fieldnames(workerPlan)))
    planOut.Valid = false;
    return;
end
copyFields = ["Valid", "TrialTable", "GrantSnapshot", "GrantRow", ...
    "ConstellationTable", "WaveformPreviewTable", "LinkAdaptationState", "Result"];
for i = 1:numel(copyFields)
    f = char(copyFields(i));
    if isfield(workerPlan, f)
        planOut.(f) = workerPlan.(f);
    end
end
end

function tf = localCanParallelizeCoupledGrantBatch(batch, cfg)
workerCount = double(sixgr.util.structGet(cfg, "run.numWorkers", 0));
minPlans = localCoupledParallelMinimumPlanCount(cfg, workerCount);
tf = logical(sixgr.util.structGet(cfg, "run.useParallel", false)) && ...
    workerCount > 1 && ...
    ~isempty(batch) && numel(batch) >= minPlans && ...
    localEnsureCoupledParallelPool(cfg, "grant_batch");
if ~tf
    return;
end
if any(arrayfun(@localPlanHasRuntimeChannelState, batch(:)))
    tf = false;
    return;
end
ueIdx = arrayfun(@(b) double(sixgr.util.structGet(b, "UEIndex", NaN)), batch(:));
ueIdx = ueIdx(isfinite(ueIdx));
tf = numel(unique(ueIdx)) == numel(ueIdx);
end

function tf = localPlanHasRuntimeChannelState(plan)
trialContext = sixgr.util.structGet(plan, "TrialContext", struct());
chState = sixgr.util.structGet(trialContext, "ChannelState", struct());
tf = isstruct(chState) && isfield(chState, "ContractVersion");
end

function [plan, runtimeState] = localExecuteCoupledGrantBatchPlan(plan, runtimeState, resolvedGrantCache, multiUser, direction, snr_dB, absoluteFrame, interferenceCacheKey)
if ~logical(sixgr.util.structGet(plan, "Valid", false))
    return;
end
trialContext = sixgr.util.structGet(plan, "TrialContext", struct());
if ~(isstruct(trialContext) && isfield(trialContext, "InterferenceBundle"))
    trialContext.InterferenceBundle = struct([]);
end
    [trialContext.InterferenceBundle, runtimeState] = localBuildCoupledInterferenceBundle( ...
    sixgr.util.structGet(plan, "Cfg", struct()), ...
    multiUser, ...
    runtimeState, ...
    resolvedGrantCache, ...
    round(double(sixgr.util.structGet(plan, "GrantIndex", NaN))), ...
    direction, ...
    interferenceCacheKey);
trialContext = localRefreshTrialContextRuntimeChannelState( ...
    trialContext, runtimeState);
planSNR_dB = double(sixgr.util.structGet(plan, "LinkSNR_dB", snr_dB));
planFrameIdx = double(sixgr.util.structGet(plan.GrantSnapshot, "Frame", ...
    sixgr.util.structGet(runtimeState, "CurrentFrame", absoluteFrame)));
[userT, userConst, waveT, laStateOut, res] = localRunSingleFrameDirectionTrial( ...
    plan.Cfg, multiUser, plan.UEIndex, direction, planSNR_dB, planFrameIdx, plan.LinkAdaptationStateIn, trialContext);
plan.TrialTable = userT;
plan.GrantSnapshot = localRefreshGrantSnapshotFromTrial(plan.GrantSnapshot, userT);
plan.GrantRow = sixgr.truth.GrantPreparation.refreshGrantRowFromGrant( ...
    plan.GrantRow, ...
    plan.GrantSnapshot, ...
    double(sixgr.util.structGet(plan.GrantSnapshot, "TBSBits", NaN)));
plan.ConstellationTable = userConst;
plan.WaveformPreviewTable = waveT;
plan.LinkAdaptationState = laStateOut;
plan.Result = localSlimCoupledGrantResultForCoordinator(res);
plan.Cfg = struct();
plan.TrialContext = struct();
end

function out = localSlimCoupledGrantResultForCoordinator(res)
out = struct();
if ~(isstruct(res) && ~isempty(fieldnames(res)))
    return;
end
keepFields = ["HARQ", "CSIRSTrialTable", "ObservedREAllocationTable", "LinkAdaptationState", "ChannelState", "SignalDiagnostic", "ISACWaveformCapture", "TxWaveformCapture", ...
    "Throughput_Mbps", "Goodput_Mbps", "BLER", "BER", "Ok", "Notes"];
for i = 1:numel(keepFields)
    f = char(keepFields(i));
    if isfield(res, f)
        out.(f) = res.(f);
    end
end
end




function [cache, runtimeState] = localBuildCoupledResolvedGrantCache(runtimeState, cfg, multiUser, userCfg, grants, direction)
cache = repmat(struct( ...
    "Valid", false, ...
    "GrantIndex", NaN, ...
    "UEIndex", NaN, ...
    "Cfg", struct(), ...
    "GrantSnapshot", struct(), ...
    "SignalType", "", ...
    "TransportBlockBits", int8([]), ...
    "RV", [], ...
    "ExpectedUCIBits", int8([]), ...
    "ResolvedFormat", NaN, ...
    "RNTI", NaN, ...
    "PrecomputedTxWaveform", [], ...
    "PrecomputedTxSampleRate_Hz", NaN, ...
    "ServingCell", NaN, ...
    "Frame", NaN, ...
    "Slot", NaN), 0, 1);
if ~(isstruct(grants) && ~isempty(grants))
    return;
end
tStart = tic;
localAppendRuntimeLog("INFO", ...
    "Preparing coupled %s resolved grant cache: candidate_grants=%d.", ...
    char(upper(string(direction))), numel(grants));
if localCanParallelizeCoupledGrantCache(cfg, grants)
    runtimeStateWorker = localCompactCoupledRuntimeStateForWorkerTransfer(runtimeState);
    cfgWorker = localSanitizeCoupledCfgForWorkerTransfer(cfg);
    userCfgWorker = localSanitizeCoupledUserCfgForWorkerTransfer(userCfg);
    localAppendRuntimeLog("INFO", ...
        "Preparing coupled %s resolved grant cache in parfor with worker-safe runtime antenna geometry: candidate_grants=%d.", ...
        char(upper(string(direction))), numel(grants));
    entries = cell(numel(grants), 1);
    parfor gi = 1:numel(grants)
        entries{gi} = localBuildCoupledResolvedGrantCacheEntry(runtimeStateWorker, cfgWorker, multiUser, userCfgWorker, grants(gi), direction, gi, grants);
    end
    for gi = 1:numel(entries)
        entry = entries{gi};
        if isstruct(entry) && logical(sixgr.util.structGet(entry, "Valid", false))
            cache(end + 1, 1) = entry; %#ok<AGROW>
        end
        if mod(gi, 25) == 0 || gi == numel(entries)
            localAppendRuntimeLog("INFO", ...
                "Prepared coupled %s resolved grant cache entries: %d/%d.", ...
                char(upper(string(direction))), round(double(gi)), round(double(numel(entries))));
        end
    end
else
    for gi = 1:numel(grants)
        entry = localBuildCoupledResolvedGrantCacheEntry(runtimeState, cfg, multiUser, userCfg, grants(gi), direction, gi, grants);
        if isstruct(entry) && logical(sixgr.util.structGet(entry, "Valid", false))
            cache(end + 1, 1) = entry; %#ok<AGROW>
        end
        if mod(gi, 25) == 0 || gi == numel(grants)
            localAppendRuntimeLog("INFO", ...
                "Prepared coupled %s resolved grant cache entries: %d/%d.", ...
                char(upper(string(direction))), round(double(gi)), round(double(numel(grants))));
        end
    end
end
if logical(sixgr.util.structGet(runtimeState, "ProtocolWaveformEnabled", false))
    [cache, runtimeState] = localBindProtocolPayloadsToResolvedGrantCache( ...
        cache, runtimeState, cfg, direction);
end
localAppendRuntimeLog("INFO", ...
    "Prepared coupled %s resolved grant cache complete: entries=%d elapsed_s=%.3f.", ...
    char(upper(string(direction))), numel(cache), toc(tStart));
end

function [cache, runtimeState] = localBindProtocolPayloadsToResolvedGrantCache(cache, runtimeState, cfg, direction)
direction = upper(string(direction));
bridge = sixgr.util.structGet(runtimeState, "ProtocolBridge", []);
if isempty(bridge) || ~isa(bridge, "sixgr.protocol.WaveformProtocolBridge") || ~bridge.Enabled
    error("sixgr:protocol:WaveformProtocolBridgeMissing", ...
        "Strict protocol YAML is enabled, but the coordinator protocol bridge is unavailable.");
end
packetT = sixgr.util.structGet(runtimeState, "PacketDeliveryLedgerTable", table());
if ~(istable(packetT) && ~isempty(packetT))
    error("sixgr:protocol:MissingApplicationTraffic", ...
        "Strict same-waveform protocol execution requires queued application packets before new-data grants.");
end
required = ["Direction","UEIndex","PacketId","ApplicationPacketId", ...
    "OfferedBits","RemainingBits","SegmentCount"];
if ~all(ismember(required, string(packetT.Properties.VariableNames)))
    error("sixgr:protocol:ApplicationLedgerSchemaMismatch", ...
        "Application packet ledger lacks the fields required for protocol-TB binding.");
end
plannedRemaining = double(packetT.RemainingBits);
plannedSegments = double(packetT.SegmentCount);

for i = 1:numel(cache)
    if ~logical(sixgr.util.structGet(cache(i), "Valid", false))
        continue;
    end
    signalType = upper(string(sixgr.util.structGet(cache(i), "SignalType", direction)));
    if ~any(signalType == ["DL","UL","PDSCH","PUSCH"])
        continue;
    end
    grant = sixgr.util.structGet(cache(i), "GrantSnapshot", struct());
    isRetx = sixgr.truth.GrantPreparation.grantIsRetransmission(grant);
    if isRetx
        if ~logical(sixgr.util.structGet(grant, "ProtocolPayloadSameWaveformTruth", false))
            error("sixgr:protocol:RetransmissionMissingProtocolBinding", ...
                "HARQ retransmission grant %d does not retain its original protocol payload binding.", i);
        end
        continue;
    end

    ueIdx = double(sixgr.util.structGet(cache(i), "UEIndex", NaN));
    packetMask = upper(string(packetT.Direction)) == direction & ...
        double(packetT.UEIndex) == ueIdx & plannedRemaining > 0;
    packetIdx = find(packetMask, 1, "first");
    if isempty(packetIdx)
        error("sixgr:protocol:NewDataGrantWithoutApplicationPayload", ...
            "New-data %s grant %d for UE %d has no queued application payload.", ...
            direction, i, ueIdx);
    end
    tbsBits = double(sixgr.util.structGet(grant, "TBSBits", ...
        sixgr.util.structGet(grant, "TransportBlockSize", NaN)));
    capacityBytes = bridge.maximumPayloadBytes(tbsBits);
    remainingBits = plannedRemaining(packetIdx);
    if mod(remainingBits, 8) ~= 0
        error("sixgr:protocol:NonByteAlignedApplicationPayload", ...
            "Application packet %s has %d remaining bits; strict protocol payloads are byte aligned.", ...
            string(packetT.PacketId(packetIdx)), remainingBits);
    end
    payloadBytes = min(capacityBytes, remainingBits / 8);
    if payloadBytes < 1
        error("sixgr:protocol:MACPDUCapacityExceeded", ...
            "The %d-bit transport block cannot carry one configured SDAP/PDCP/RLC/MAC payload byte.", tbsBits);
    end

    offsetBits = double(packetT.OfferedBits(packetIdx)) - plannedRemaining(packetIdx);
    segmentIndex = plannedSegments(packetIdx) + 1;
    packetId = string(packetT.PacketId(packetIdx));
    fragmentId = "runtime-" + direction + "-UE-" + compose("%03d", ueIdx) + ...
        "-" + packetId + "-fragment-" + string(segmentIndex);
    tbId = localProtocolTransportBlockId(grant, direction, ueIdx, i);
    payload = localProtocolPayloadBytes(cfg, packetId, direction, ueIdx, offsetBits / 8, payloadBytes);
    slot = double(sixgr.util.structGet(grant, "Slot", sixgr.util.structGet(runtimeState, "CurrentSlot", 1)));
    eventTime = max(0, (slot - 1) * double(sixgr.util.structGet(runtimeState, "SlotDuration_s", 0)));
    [tbBits, evidence] = bridge.encodeFragment(ueIdx, direction, tbId, ...
        fragmentId, payload, tbsBits, eventTime);

    grant.TransportBlockId = char(tbId);
    grant.ProtocolPayloadSameWaveformTruth = true;
    grant.ProtocolPacketId = char(packetId);
    grant.ProtocolApplicationPacketId = char(string(packetT.ApplicationPacketId(packetIdx)));
    grant.ProtocolFragmentId = char(fragmentId);
    grant.ProtocolSegmentIndex = double(segmentIndex);
    grant.ProtocolPayloadOffsetBits = double(offsetBits);
    grant.ProtocolPayloadBits = double(evidence.PayloadBits);
    grant.ProtocolPayloadSHA256 = char(evidence.PayloadSHA256);
    grant.ProtocolSDAPHeaderHex = char(evidence.SDAPHeaderHex);
    grant.ProtocolPDCPHeaderHex = char(evidence.PDCPHeaderHex);
    grant.ProtocolRLCHeaderHex = char(evidence.RLCHeaderHex);
    grant.ProtocolEncodedRLC_SHA256 = char(evidence.EncodedRLC_SHA256);
    grant.ProtocolMACSHA256 = char(evidence.MACSHA256);
    grant.ProtocolMACPDUBytes = double(evidence.MACPDUBytes);
    grant.ProtocolMACPaddingBytes = double(evidence.MACPaddingBytes);
    grant.ProtocolEvidenceSource = char(evidence.EvidenceSource);
    cache(i).GrantSnapshot = grant;
    cache(i).TransportBlockBits = int8(tbBits(:));

    if ~isempty(sixgr.util.structGet(cache(i), "PrecomputedTxWaveform", []))
        context = struct("GrantSnapshot", grant, "TransportBlockBits", int8(tbBits(:)), ...
            "RV", sixgr.util.structGet(cache(i), "RV", []));
        [wave, rate] = localPrecomputeCoupledInterfererTxWaveform( ...
            cache(i).Cfg, direction, signalType, grant, context);
        cache(i).PrecomputedTxWaveform = wave;
        cache(i).PrecomputedTxSampleRate_Hz = rate;
    end
    plannedRemaining(packetIdx) = plannedRemaining(packetIdx) - evidence.PayloadBits;
    plannedSegments(packetIdx) = segmentIndex;
end
runtimeState.ProtocolBridge = bridge;
end

function tbId = localProtocolTransportBlockId(grant, direction, ueIdx, grantIndex)
for name = ["TransportBlockId","TBId","GrantContextId","PHYGrantContextId"]
    value = strtrim(string(sixgr.util.structGet(grant, char(name), "")));
    if strlength(value) > 0 && lower(value) ~= "nan"
        tbId = value;
        return;
    end
end
harq = sixgr.util.structGet(grant, "HARQ", struct());
harqId = double(sixgr.util.structGet(harq, "HarqID", NaN));
ndiEpoch = double(sixgr.util.structGet(harq, "NDIEpoch", NaN));
slot = double(sixgr.util.structGet(grant, "Slot", NaN));
if ~(isfinite(harqId) && isfinite(ndiEpoch) && isfinite(slot))
    error("sixgr:protocol:MissingTransportBlockIdentity", ...
        "Protocol grant %d lacks a stable grant or HARQ transport-block identity.", grantIndex);
end
tbId = direction + "_ue" + string(ueIdx) + "_harq" + string(harqId) + ...
    "_epoch" + string(ndiEpoch) + "_slot" + string(slot);
end

function bytes = localProtocolPayloadBytes(cfg, packetId, direction, ueIdx, offsetBytes, count)
seed = double(sixgr.util.structGet(cfg, "run.seed", NaN));
if ~(isfinite(seed) && seed >= 0)
    error("sixgr:protocol:MissingPayloadSeed", ...
        "Deterministic same-waveform application payload generation requires run.seed.");
end
identityOffset = sum(double(char(packetId + "|" + direction))) + 257 * double(ueIdx);
start = double(offsetBytes) + seed + identityOffset;
bytes = uint8(mod(start + (0:(double(count)-1)), 256));
end

function tf = localCanParallelizeCoupledGrantCache(cfg, grants)
workerCount = double(sixgr.util.structGet(cfg, "run.numWorkers", 0));
minPlans = localCoupledParallelMinimumPlanCount(cfg, workerCount);
tf = logical(sixgr.util.structGet(cfg, "run.useParallel", false)) && ...
    workerCount > 1 && ...
    isstruct(grants) && ~isempty(grants) && numel(grants) >= minPlans && ...
    localEnsureCoupledParallelPool(cfg, "grant_cache");
end

function n = localCoupledParallelMinimumPlanCount(cfg, workerCount)
n = double(sixgr.util.structGet(cfg, "run.parallelMinGrantPlanCount", NaN));
if ~(isfinite(n) && n >= 1)
    workerCount = max(1, round(double(workerCount)));
    n = max(4, min(workerCount, 8));
end
n = max(1, round(double(n)));
end

function stateOut = localCompactCoupledRuntimeStateForWorkerTransfer(stateIn)
stateOut = stateIn;
if ~isstruct(stateOut)
    return;
end
if isfield(stateOut, "BSAntennaRuntime")
    stateOut.BSAntennaRuntime = localSanitizeRuntimeAntennaEntriesForWorkerTransfer(stateOut.BSAntennaRuntime);
end
if isfield(stateOut, "UEAntennaRuntime")
    stateOut.UEAntennaRuntime = localSanitizeRuntimeAntennaEntriesForWorkerTransfer(stateOut.UEAntennaRuntime);
end
% These runtime objects are not read by worker-side grant execution. Keeping
% them out of parfor payloads avoids serializing handle/System objects while
% preserving the numeric geometry and large-scale state used by the PHY path.
if isfield(stateOut, "PLModel")
    stateOut.PLModel = [];
end
if isfield(stateOut, "MobilityModel")
    stateOut.MobilityModel = [];
end
if isfield(stateOut, "RuntimeChannelStates")
    stateOut.RuntimeChannelStates = repmat(sixgr.channel.ChannelFactory.emptyRuntimeChannelState(), 0, 1);
end
if isfield(stateOut, "ProtocolBridge")
    stateOut.ProtocolBridge = [];
end
end

function entriesOut = localSanitizeRuntimeAntennaEntriesForWorkerTransfer(entriesIn)
entriesOut = entriesIn;
if ~isstruct(entriesOut)
    return;
end
for ii = 1:numel(entriesOut)
    if isfield(entriesOut, "Antenna")
        entriesOut(ii).Antenna = localSanitizeRuntimeAntennaForWorkerTransfer(entriesOut(ii).Antenna);
    end
end
end

function antennaOut = localSanitizeRuntimeAntennaForWorkerTransfer(antennaIn)
antennaOut = antennaIn;
if ~isstruct(antennaOut)
    return;
end
for ii = 1:numel(antennaOut)
    if isfield(antennaOut, "ArrayObj")
        antennaOut(ii).ArrayObj = [];
    end
    if isfield(antennaOut, "ElementObj")
        antennaOut(ii).ElementObj = [];
    end
end
end

function cfgOut = localSanitizeCoupledCfgForWorkerTransfer(cfgIn)
cfgOut = cfgIn;
if ~isstruct(cfgOut)
    return;
end
userMeta = sixgr.util.structGet(cfgOut, "lls6g.userContext", struct());
if isstruct(userMeta) && ~isempty(fieldnames(userMeta))
    if isfield(userMeta, "RuntimeServingBSAntenna")
        userMeta.RuntimeServingBSAntenna = localSanitizeRuntimeAntennaForWorkerTransfer(userMeta.RuntimeServingBSAntenna);
    end
    if isfield(userMeta, "RuntimeUEAntenna")
        userMeta.RuntimeUEAntenna = localSanitizeRuntimeAntennaForWorkerTransfer(userMeta.RuntimeUEAntenna);
    end
    cfgOut = sixgr.util.structSet(cfgOut, "lls6g.userContext", userMeta);
end
end

function userCfgOut = localSanitizeCoupledUserCfgForWorkerTransfer(userCfgIn)
userCfgOut = userCfgIn;
if ~iscell(userCfgOut)
    return;
end
for ii = 1:numel(userCfgOut)
    if isstruct(userCfgOut{ii})
        userCfgOut{ii} = localSanitizeCoupledCfgForWorkerTransfer(userCfgOut{ii});
    end
end
end

function batchOut = localSanitizeCoupledGrantBatchForWorkerTransfer(batchIn)
batchOut = batchIn;
if ~isstruct(batchOut)
    return;
end
for ii = 1:numel(batchOut)
    if isfield(batchOut, "Cfg") && isstruct(batchOut(ii).Cfg)
        batchOut(ii).Cfg = localSanitizeCoupledCfgForWorkerTransfer(batchOut(ii).Cfg);
    end
end
end

function cacheOut = localSanitizeCoupledResolvedGrantCacheForWorkerTransfer(cacheIn)
cacheOut = cacheIn;
if ~isstruct(cacheOut)
    return;
end
for ii = 1:numel(cacheOut)
    if isfield(cacheOut, "Cfg") && isstruct(cacheOut(ii).Cfg)
        cacheOut(ii).Cfg = localSanitizeCoupledCfgForWorkerTransfer(cacheOut(ii).Cfg);
    end
end
end

function tf = localCanUseLightweightCoupledInterferenceCache(cfg, resolvedGrantCache)
interCellMode = strtrim(lower(string(sixgr.util.structGet(cfg, ...
    "run.interferenceExecutionMode", ""))));
intraCellMode = strtrim(lower(string(sixgr.util.structGet(cfg, ...
    "run.intraCellInterferenceExecutionMode", "none"))));
tf = (interCellMode == "full_per_link_channel_waveform_sum" || ...
    intraCellMode == "shared_slot_waveform_superposition") && ...
    isstruct(resolvedGrantCache) && ~isempty(resolvedGrantCache);
end

function key = localRegisterCoupledInterferenceCache(payload, direction, sweepIdx, frameLocal, absoluteFrame)
key = "";
if ~(isstruct(payload) && ~isempty(fieldnames(payload)))
    return;
end
timestampUs = round(posixtime(datetime("now", "TimeZone", "UTC")) * 1e6);
key = sprintf("coupled_%s_%d_%d_%d_%d", ...
    char(upper(string(direction))), round(double(sweepIdx)), round(double(frameLocal)), round(double(absoluteFrame)), round(double(timestampUs)));
sixgr.link.interferenceReplayCache("put", key, payload);
end

function workerCache = localCreateParallelInterferenceReplayCacheConstant(interferenceCacheKey, payload, cfg)
workerCache = [];
if strlength(strtrim(string(interferenceCacheKey))) < 1 || ~(isstruct(payload) && ~isempty(fieldnames(payload)))
    return;
end
if ~(logical(sixgr.util.structGet(cfg, "run.useParallel", false)) && double(sixgr.util.structGet(cfg, "run.numWorkers", 0)) > 1)
    return;
end
resolvedCache = sixgr.util.structGet(payload, "ResolvedGrantCache", struct([]));
workerCount = max(1, round(double(sixgr.util.structGet(cfg, "run.numWorkers", 1))));
if numel(resolvedCache) < localCoupledParallelMinimumPlanCount(cfg, workerCount)
    return;
end
if ~localEnsureCoupledParallelPool(cfg, "interference_cache")
    return;
end
if exist("parallel.pool.Constant", "class") ~= 8
    localAppendRuntimeLog("INFO", ...
        "Parallel interference replay cache constant unavailable; parfor will use inline interferer bundles.");
    return;
end
try
    keyChar = char(string(interferenceCacheKey));
    workerCache = parallel.pool.Constant( ...
        @() localInstallInterferenceReplayCacheOnWorker(keyChar, payload), ...
        @(installedKey) localRemoveInterferenceReplayCacheOnWorker(installedKey));
    localAppendRuntimeLog("INFO", ...
        "Prepared parallel worker interference replay cache: key=%s entries=%d.", ...
        keyChar, numel(resolvedCache));
catch ME
    workerCache = [];
    localAppendRuntimeLog("WARN", ...
        "Parallel worker interference replay cache unavailable; parfor will use inline interferer bundles: %s %s", ...
        char(string(ME.identifier)), char(string(ME.message)));
end
end

function tf = localHasParallelInterferenceReplayCache(workerCache)
tf = false;
try
    tf = ~isempty(workerCache) && isa(workerCache, "parallel.pool.Constant");
catch
    tf = false;
end
end

function tf = localParallelPoolActive()
tf = false;
if exist("gcp", "file") ~= 2
    return;
end
try
    tf = ~isempty(gcp("nocreate"));
catch
    tf = false;
end
end

function tf = localEnsureCoupledParallelPool(cfg, context)
tf = false;
if nargin < 2 || strlength(string(context)) < 1
    context = "coupled_waveform";
end
if ~(logical(sixgr.util.structGet(cfg, "run.useParallel", false)) && ...
        double(sixgr.util.structGet(cfg, "run.numWorkers", 0)) > 1)
    return;
end
if exist("gcp", "file") ~= 2 || exist("parpool", "file") ~= 2
    return;
end
try
    pool = gcp("nocreate");
catch
    pool = [];
end
if ~isempty(pool)
    pool = localApplyCoupledParpoolIdleTimeout(pool, cfg);
    tf = double(pool.NumWorkers) > 1;
    return;
end
if ~logical(sixgr.util.structGet(cfg, "run.autoStartParallelPool", false))
    localAppendRuntimeLog("INFO", ...
        "Parallel pool is not active for coupled %s and auto-start is disabled; execution remains serial.", ...
        char(string(context)));
    return;
end

requestedWorkers = max(2, round(double(sixgr.util.structGet(cfg, "run.numWorkers", 2))));
poolKind = lower(strtrim(string(sixgr.util.structGet(cfg, ...
    "run.parallelPoolKindEffective", sixgr.util.structGet(cfg, "run.parallelPoolKind", "auto")))));
if strlength(poolKind) < 1
    poolKind = "auto";
end

localAppendRuntimeLog("WARN", ...
    "Parallel pool unavailable before coupled %s; restarting requested %s pool with %d workers.", ...
    char(string(context)), char(poolKind), requestedWorkers);
try
    pool = localStartCoupledParpoolFromCfg(poolKind, requestedWorkers);
    pool = localApplyCoupledParpoolIdleTimeout(pool, cfg);
    tf = ~isempty(pool) && double(pool.NumWorkers) > 1;
    if tf
        localAppendRuntimeLog("INFO", ...
            "Parallel pool ready for coupled %s: workers=%d kind=%s idle_timeout_min=%.3f.", ...
            char(string(context)), double(pool.NumWorkers), char(poolKind), ...
            double(sixgr.util.structGet(cfg, "run.parallelPoolIdleTimeoutMinutes", 1440)));
    end
catch ME
    tf = false;
    localAppendRuntimeLog("WARN", ...
        "Parallel pool restart failed before coupled %s; execution will remain serial: %s %s", ...
        char(string(context)), char(string(ME.identifier)), char(string(ME.message)));
end
end

function pool = localStartCoupledParpoolFromCfg(poolKind, requestedWorkers)
pool = [];
poolKind = lower(strtrim(string(poolKind)));
if poolKind == "threads"
    pool = parpool("threads", requestedWorkers);
    return;
end
if poolKind == "processes" || poolKind == "local"
    pool = localStartCoupledProcessParpool(requestedWorkers);
    return;
end
try
    pool = localStartCoupledProcessParpool(requestedWorkers);
catch
    pool = parpool("threads", requestedWorkers);
end
end

function pool = localStartCoupledProcessParpool(requestedWorkers)
try
    pool = parpool(requestedWorkers);
catch firstME
    firstFailure = sprintf("%s %s", char(string(firstME.identifier)), char(string(firstME.message)));
    try
        pool = parpool("local", requestedWorkers);
    catch secondME
        error("sixgr:truth:ParpoolRestartFailed", ...
            "Process parpool(%d) failed: %s; local profile failed: %s %s", ...
            requestedWorkers, firstFailure, char(string(secondME.identifier)), char(string(secondME.message)));
    end
end
end

function pool = localApplyCoupledParpoolIdleTimeout(pool, cfg)
if isempty(pool)
    return;
end
idleTimeoutMinutes = max(1, double(sixgr.util.structGet(cfg, ...
    "run.parallelPoolIdleTimeoutMinutes", 1440)));
try
    if isprop(pool, 'IdleTimeout')
        pool.IdleTimeout = idleTimeoutMinutes;
    end
catch
    % Some cluster profiles expose IdleTimeout as read-only; the on-demand
    % restart gate above still keeps long honest runs from falling to serial.
end
end

function key = localInstallInterferenceReplayCacheOnWorker(key, payload)
key = char(string(key));
if strlength(strtrim(string(key))) < 1 || ~(isstruct(payload) && ~isempty(fieldnames(payload)))
    return;
end
sixgr.link.interferenceReplayCache("put", key, payload);
end

function localRemoveInterferenceReplayCacheOnWorker(key)
try
    key = char(string(key));
    if strlength(strtrim(string(key))) > 0
        sixgr.link.interferenceReplayCache("remove", key);
    end
catch
end
end

function entry = localBuildCoupledResolvedGrantCacheEntry(runtimeState, cfg, multiUser, userCfg, grant, direction, grantIndex, scheduledGrants)
entry = struct( ...
    "Valid", false, ...
    "GrantIndex", NaN, ...
    "UEIndex", NaN, ...
    "Cfg", struct(), ...
    "GrantSnapshot", struct(), ...
    "SignalType", "", ...
    "TransportBlockBits", int8([]), ...
    "RV", [], ...
    "ExpectedUCIBits", int8([]), ...
    "ResolvedFormat", NaN, ...
    "RNTI", NaN, ...
    "PrecomputedTxWaveform", [], ...
    "PrecomputedTxSampleRate_Hz", NaN, ...
    "ServingCell", NaN, ...
    "Frame", NaN, ...
    "Slot", NaN);
ueIdx = NaN;
servingCell = double(sixgr.util.structGet(grant, "ServingCell", NaN));
signalType = upper(string(sixgr.util.structGet(grant, "SignalType", direction)));
try
    verboseCacheLog = strlength(strtrim(string(getenv("SIXGR_VERBOSE_STAGE_LOG")))) > 0;
    entryTimer = tic;
    stageTimer = tic;
    ueIdx = sixgr.truth.GrantPreparation.resolveGrantUEIndex(grant, multiUser);
    if ~(isfinite(ueIdx) && ueIdx >= 1 && ueIdx <= numel(userCfg))
        return;
    end
    if verboseCacheLog
        localAppendRuntimeLog("INFO", ...
            "Coupled %s grant cache entry %d resolved UE index: ue=%d elapsed_s=%.3f.", ...
            char(upper(string(direction))), round(double(grantIndex)), round(double(ueIdx)), toc(stageTimer));
    end
    stageTimer = tic;
    tempState = sixgr.truth.CoupledTruthRuntime.setCurrentUE(runtimeState, ueIdx, direction);
    [cfgI, tempState] = sixgr.truth.GrantPreparation.applyCoupledRuntimeUserContext(userCfg{ueIdx}, tempState, ueIdx, direction);
    if verboseCacheLog
        localAppendRuntimeLog("INFO", ...
            "Coupled %s grant cache entry %d applied runtime UE context: ue=%d elapsed_s=%.3f.", ...
            char(upper(string(direction))), round(double(grantIndex)), round(double(ueIdx)), toc(stageTimer));
    end
    stageTimer = tic;
    [tempState, grantContext, ~] = sixgr.truth.CoupledTruthRuntime.buildTrialContextFromGrant(tempState, cfgI, ueIdx, direction, grant); %#ok<ASGLU>
    if verboseCacheLog
        localAppendRuntimeLog("INFO", ...
            "Coupled %s grant cache entry %d built trial context: ue=%d elapsed_s=%.3f.", ...
            char(upper(string(direction))), round(double(grantIndex)), round(double(ueIdx)), toc(stageTimer));
    end
    stageTimer = tic;
    [grantContext, ~] = sixgr.truth.GrantPreparation.finalizeGrantTrialContext(cfgI, direction, grantContext);
    if verboseCacheLog
        localAppendRuntimeLog("INFO", ...
            "Coupled %s grant cache entry %d finalized grant context: ue=%d elapsed_s=%.3f.", ...
            char(upper(string(direction))), round(double(grantIndex)), round(double(ueIdx)), toc(stageTimer));
    end
    grantResolved = sixgr.util.structGet(grantContext, "GrantSnapshot", struct());
    [cfgI, grantResolved] = sixgr.rf.bindScheduledGrantPowerBudget( ...
        cfgI, direction, grantResolved, scheduledGrants);
    grantContext.GrantSnapshot = grantResolved;
    grantContext.HARQContext = sixgr.util.structGet(grantContext, "HARQContext", struct());
    grantContext.HARQContext.GrantSnapshot = grantResolved;
    resolvedBits = double(sixgr.util.structGet(grantResolved, "TBSBits", ...
        sixgr.util.structGet(grantResolved, "TransportBlockSize", NaN)));
    if ~(isfinite(resolvedBits) && resolvedBits > 0)
        return;
    end
    stageTimer = tic;
    cfgI = sixgr.truth.GrantPreparation.applyHARQGrantContext(cfgI, direction, grantResolved);
    cfgI = sixgr.truth.GrantPreparation.applyExecutionGrantSnapshot(cfgI, direction, grantResolved);
    cfgI = localCompactCoupledResolvedGrantCacheCfg(cfgI);
    if verboseCacheLog
        localAppendRuntimeLog("INFO", ...
            "Coupled %s grant cache entry %d applied HARQ/execution snapshot and compaction: ue=%d elapsed_s=%.3f.", ...
            char(upper(string(direction))), round(double(grantIndex)), round(double(ueIdx)), toc(stageTimer));
    end
    signalType = upper(string(sixgr.util.structGet(grantResolved, "SignalType", direction)));
    servingCell = double(sixgr.util.structGet(grantResolved, "ServingCell", servingCell));
    precomputedTxWaveform = [];
    precomputedTxSampleRateHz = NaN;
    if localShouldPrecomputeCoupledInterfererTxWaveform(cfgI)
        stageTimer = tic;
        if verboseCacheLog
            localAppendRuntimeLog("INFO", ...
                "Coupled %s grant cache entry %d precomputing TX waveform: ue=%d signal=%s.", ...
                char(upper(string(direction))), round(double(grantIndex)), round(double(ueIdx)), char(signalType));
        end
        [precomputedTxWaveform, precomputedTxSampleRateHz] = localPrecomputeCoupledInterfererTxWaveform( ...
            cfgI, direction, signalType, grantResolved, grantContext);
        if verboseCacheLog
            localAppendRuntimeLog("INFO", ...
                "Coupled %s grant cache entry %d precomputed TX waveform: ue=%d samples=%d ports=%d elapsed_s=%.3f.", ...
                char(upper(string(direction))), round(double(grantIndex)), round(double(ueIdx)), ...
                size(precomputedTxWaveform, 1), size(precomputedTxWaveform, 2), toc(stageTimer));
        end
    end
    entry = struct( ...
        "Valid", true, ...
        "GrantIndex", double(grantIndex), ...
        "UEIndex", double(ueIdx), ...
        "Cfg", cfgI, ...
        "GrantSnapshot", grantResolved, ...
        "SignalType", char(signalType), ...
        "TransportBlockBits", sixgr.util.structGet(grantContext, "TransportBlockBits", int8([])), ...
        "RV", sixgr.util.structGet(grantContext, "RV", []), ...
        "ExpectedUCIBits", int8(sixgr.util.structGet(grantContext, "ExpectedUCIBits", int8([]))), ...
        "ResolvedFormat", double(sixgr.util.structGet(grantContext, "ResolvedFormat", NaN)), ...
        "RNTI", double(sixgr.util.structGet(grantContext, "RNTI", sixgr.util.structGet(cfgI, "phy.rnti", NaN))), ...
        "PrecomputedTxWaveform", precomputedTxWaveform, ...
        "PrecomputedTxSampleRate_Hz", double(precomputedTxSampleRateHz), ...
        "ServingCell", double(sixgr.util.structGet(grantResolved, "ServingCell", NaN)), ...
        "Frame", double(sixgr.util.structGet(grantResolved, "Frame", sixgr.util.structGet(runtimeState, "CurrentFrame", NaN))), ...
        "Slot", double(sixgr.util.structGet(grantResolved, "Slot", sixgr.util.structGet(runtimeState, "CurrentSlot", NaN))));
    if verboseCacheLog
        localAppendRuntimeLog("INFO", ...
            "Coupled %s grant cache entry %d complete: ue=%d serving_cell=%s tbs_bits=%.0f elapsed_s=%.3f.", ...
            char(upper(string(direction))), round(double(grantIndex)), round(double(ueIdx)), ...
            localDisplayProgressValue(servingCell), resolvedBits, toc(entryTimer));
    end
catch ME
    failureReport = string(getReport(ME, "extended", "hyperlinks", "off"));
    failureReport = replace(failureReport, newline, " | ");
    localAppendRuntimeLog("ERROR", ...
        "Coupled %s resolved grant cache entry failed: grant_index=%d ue=%s serving_cell=%s signal=%s err=%s msg=%s stack=%s", ...
        char(upper(string(direction))), round(double(grantIndex)), ...
        localDisplayProgressValue(ueIdx), localDisplayProgressValue(servingCell), char(signalType), ...
        char(string(ME.identifier)), char(string(ME.message)), char(failureReport));
    rethrow(ME);
end
end

function tf = localShouldPrecomputeCoupledInterfererTxWaveform(cfg)
interCellMode = lower(strtrim(string(sixgr.util.structGet(cfg, ...
    "run.interferenceExecutionMode", ""))));
intraCellMode = lower(strtrim(string(sixgr.util.structGet(cfg, ...
    "run.intraCellInterferenceExecutionMode", "none"))));
tf = interCellMode == "full_per_link_channel_waveform_sum" || ...
    intraCellMode == "shared_slot_waveform_superposition" || ...
    logical(sixgr.util.structGet(cfg, "run.precomputeInterfererTxWaveforms", false));
end

function varargout = localCaptureCommittedFullPHYISAC(varargin)
% Compatibility delegate; completion/publication has one production owner.
[varargout{1:nargout}] = sixgr.truth.SharedDataCompletionRuntime.captureCommittedFullPHYISAC(varargin{:},@localAppendRuntimeLog);
end

function varargout = localCaptureCommittedTxIQ(varargin)
% Compatibility delegate; completion/publication has one production owner.
[varargout{1:nargout}] = sixgr.truth.SharedDataCompletionRuntime.captureCommittedTxIQ(varargin{:},@localAppendRuntimeLog);
end

function cfgOut = localCompactCoupledResolvedGrantCacheCfg(cfgIn)
cfgOut = cfgIn;
cfgOut = localRemoveNestedFieldIfPresent(cfgOut, "lls6g.resolvedConfig");
cfgOut = localRemoveNestedFieldIfPresent(cfgOut, "lls6g.parameterBindingMatrix");
cfgOut = localRemoveNestedFieldIfPresent(cfgOut, "lls6g.browserConfigSurfaceMatrix");
cfgOut = localRemoveNestedFieldIfPresent(cfgOut, "lls6g.runtimeConfigApplicationEvidence");
cfgOut = localRemoveNestedFieldIfPresent(cfgOut, "lls6g.featureParameterIndex");
cfgOut = localRemoveNestedFieldIfPresent(cfgOut, "lls6g.configOwnershipArtifacts");
topLevelDrop = ["display_outputs","logging_outputs","fidelity_registry","export"];
for i = 1:numel(topLevelDrop)
    fieldName = char(topLevelDrop(i));
    if isstruct(cfgOut) && isfield(cfgOut, fieldName)
        cfgOut = rmfield(cfgOut, fieldName);
    end
end
end

function s = localRemoveNestedFieldIfPresent(s, path)
if ~(isstruct(s) && strlength(strtrim(string(path))) > 0)
    return;
end
parts = split(string(path), ".");
parts = parts(strlength(parts) > 0);
if isempty(parts)
    return;
end
s = localRemoveNestedFieldRecursive(s, parts);
end

function s = localRemoveNestedFieldRecursive(s, parts)
if ~(isstruct(s) && ~isempty(parts))
    return;
end
fieldName = char(parts(1));
if ~isfield(s, fieldName)
    return;
end
if numel(parts) == 1
    s = rmfield(s, fieldName);
    return;
end
child = s.(fieldName);
if ~isstruct(child)
    return;
end
child = localRemoveNestedFieldRecursive(child, parts(2:end));
if isempty(fieldnames(child))
    s = rmfield(s, fieldName);
else
    s.(fieldName) = child;
end
end

function [bundle, runtimeState] = localBuildCoupledInterferenceBundle(cfg, multiUser, runtimeState, resolvedGrantCache, victimGrantIdx, direction, interferenceCacheKey)
bundle = struct([]);
direction = upper(string(direction));
interCellMode = strtrim(lower(string(sixgr.util.structGet(cfg, ...
    "run.interferenceExecutionMode", ""))));
intraCellMode = strtrim(lower(string(sixgr.util.structGet(cfg, ...
    "run.intraCellInterferenceExecutionMode", "none"))));
if interCellMode ~= "full_per_link_channel_waveform_sum" && ...
        intraCellMode ~= "shared_slot_waveform_superposition"
    return;
end
if ~(isstruct(resolvedGrantCache) && ~isempty(resolvedGrantCache))
    return;
end
useLightweightCache = nargin >= 7 && strlength(strtrim(string(interferenceCacheKey))) > 0;

victimMask = arrayfun(@(entry) logical(sixgr.util.structGet(entry, "Valid", false)) && ...
    round(double(sixgr.util.structGet(entry, "GrantIndex", NaN))) == round(double(victimGrantIdx)), resolvedGrantCache(:));
victimPos = find(victimMask, 1, "last");
if isempty(victimPos)
    return;
end

victimEntry = resolvedGrantCache(victimPos);
victimGrant = sixgr.util.structGet(victimEntry, "GrantSnapshot", struct());
victimUEIdx = double(sixgr.util.structGet(victimEntry, "UEIndex", NaN));
victimServingCell = double(sixgr.util.structGet(victimEntry, "ServingCell", NaN));
if ~(isfinite(victimUEIdx) && victimUEIdx >= 1 && victimUEIdx <= size(runtimeState.LargeScaleState.RxPower_dBm, 1))
    return;
end

count = 0;
for gi = 1:numel(resolvedGrantCache)
    entry = resolvedGrantCache(gi);
    if ~logical(sixgr.util.structGet(entry, "Valid", false))
        continue;
    end
    if round(double(sixgr.util.structGet(entry, "GrantIndex", NaN))) == round(double(victimGrantIdx))
        continue;
    end
    interfererGrant = sixgr.util.structGet(entry, "GrantSnapshot", struct());
    interfererCell = double(sixgr.util.structGet(entry, "ServingCell", NaN));
    if ~(isfinite(interfererCell) && interfererCell >= 1)
        continue;
    end
    sameServingCell = interfererCell == victimServingCell;
    sameMUGroup = localGrantsShareMUMIMOOpportunity(victimGrant, interfererGrant);
    % Same-cell signals are coupled here only when the scheduler froze an
    % explicit shared-resource MU group.  Ordinary orthogonal same-cell
    % grants remain excluded, while inter-cell overlap retains the existing
    % full per-link waveform path.
    if sameServingCell && ~sameMUGroup
        continue;
    end
    if sameServingCell && intraCellMode ~= "shared_slot_waveform_superposition"
        continue;
    end
    if ~sameServingCell && interCellMode ~= "full_per_link_channel_waveform_sum"
        continue;
    end
    if ~localGrantsOverlap(victimGrant, interfererGrant)
        continue;
    end
    interfererUEIdx = double(sixgr.util.structGet(entry, "UEIndex", NaN));
    if ~(isfinite(interfererUEIdx) && interfererUEIdx >= 1)
        continue;
    end
    if direction == "UL"
        metricCell = victimServingCell;
        metricUE = interfererUEIdx;
    else
        metricCell = interfererCell;
        metricUE = victimUEIdx;
    end
    if ~(isfinite(metricCell) && metricCell >= 1 && metricCell <= size(runtimeState.LargeScaleState.Pathloss_dB, 2))
        continue;
    end
    if ~(isfinite(metricUE) && metricUE >= 1 && metricUE <= size(runtimeState.LargeScaleState.Pathloss_dB, 1))
        continue;
    end
    [victimBsEntry, victimUeEntry] = localRuntimeAntennaEntriesForVictim(runtimeState, victimUEIdx, victimServingCell);
    sourceBsEntry = localRuntimeBSAntennaEntry(runtimeState, interfererCell);
    sourceUeEntry = localRuntimeUEAntennaEntry(runtimeState, interfererUEIdx);

    count = count + 1;
    bundle(count).SignalType = sixgr.util.structGet(entry, "SignalType", char(upper(string(direction)))); %#ok<AGROW>
    if useLightweightCache
        bundle(count).CacheKey = char(interferenceCacheKey); %#ok<AGROW>
        bundle(count).CacheIndex = double(gi); %#ok<AGROW>
    else
        bundle(count).Cfg = sixgr.util.structGet(entry, "Cfg", struct()); %#ok<AGROW>
        bundle(count).GrantSnapshot = interfererGrant; %#ok<AGROW>
        bundle(count).TransportBlockBits = sixgr.util.structGet(entry, "TransportBlockBits", []); %#ok<AGROW>
        bundle(count).RV = sixgr.util.structGet(entry, "RV", []); %#ok<AGROW>
        bundle(count).ExpectedUCIBits = sixgr.util.structGet(entry, "ExpectedUCIBits", int8([])); %#ok<AGROW>
        bundle(count).ResolvedFormat = double(sixgr.util.structGet(entry, "ResolvedFormat", NaN)); %#ok<AGROW>
        bundle(count).RNTI = double(sixgr.util.structGet(entry, "RNTI", NaN)); %#ok<AGROW>
        bundle(count).PrecomputedTxWaveform = sixgr.util.structGet(entry, "PrecomputedTxWaveform", []); %#ok<AGROW>
        bundle(count).PrecomputedTxSampleRate_Hz = double(sixgr.util.structGet(entry, "PrecomputedTxSampleRate_Hz", NaN)); %#ok<AGROW>
    end
    bundle(count).VictimUEIndex = double(victimUEIdx); %#ok<AGROW>
    bundle(count).InterfererUEIndex = double(interfererUEIdx); %#ok<AGROW>
    bundle(count).ServingCell = double(interfererCell); %#ok<AGROW>
    bundle(count).VictimServingCell = double(victimServingCell); %#ok<AGROW>
    bundle(count).VictimRxPower_dBm = double(runtimeState.LargeScaleState.RxPower_dBm(metricUE, metricCell)); %#ok<AGROW>
    bundle(count).VictimRSRP_dBm = double(runtimeState.LargeScaleState.RSRP_dBm(metricUE, metricCell)); %#ok<AGROW>
    bundle(count).BasePathloss_dB = double(runtimeState.LargeScaleState.BasePathloss_dB(metricUE, metricCell)); %#ok<AGROW>
    bundle(count).Pathloss_dB = double(runtimeState.LargeScaleState.Pathloss_dB(metricUE, metricCell)); %#ok<AGROW>
    bundle(count).ShadowFading_dB = double(runtimeState.LargeScaleState.Shadow_dB(metricUE, metricCell)); %#ok<AGROW>
    bundle(count).O2I_dB = double(runtimeState.LargeScaleState.O2I_dB(metricUE, metricCell)); %#ok<AGROW>
    bundle(count).BeamIndex = double(runtimeState.LargeScaleState.BeamIndex(metricUE, metricCell)); %#ok<AGROW>
    bundle(count).BeamGain_dB = double(runtimeState.LargeScaleState.BeamGain_dB(metricUE, metricCell)); %#ok<AGROW>
    bundle(count).VictimServingBSAntenna = sixgr.util.structGet(victimBsEntry, "Antenna", struct()); %#ok<AGROW>
    bundle(count).VictimServingBSAntennaMeta = sixgr.util.structGet(victimBsEntry, "Metadata", struct()); %#ok<AGROW>
    bundle(count).VictimUEAntenna = sixgr.util.structGet(victimUeEntry, "Antenna", struct()); %#ok<AGROW>
    bundle(count).VictimUEAntennaMeta = sixgr.util.structGet(victimUeEntry, "Metadata", struct()); %#ok<AGROW>
    bundle(count).SourceBSAntenna = sixgr.util.structGet(sourceBsEntry, "Antenna", struct()); %#ok<AGROW>
    bundle(count).SourceBSAntennaMeta = sixgr.util.structGet(sourceBsEntry, "Metadata", struct()); %#ok<AGROW>
    bundle(count).SourceUEAntenna = sixgr.util.structGet(sourceUeEntry, "Antenna", struct()); %#ok<AGROW>
    bundle(count).SourceUEAntennaMeta = sixgr.util.structGet(sourceUeEntry, "Metadata", struct()); %#ok<AGROW>
    if isfinite(victimServingCell) && victimServingCell >= 1 && victimServingCell <= size(runtimeState.Layout.bs.pos_m, 1)
        bundle(count).VictimServingBSPosition_m = reshape(double(runtimeState.Layout.bs.pos_m(victimServingCell, :)), 1, []); %#ok<AGROW>
        bundle(count).VictimServingBSAzimuth_deg = double(runtimeState.Layout.bs.azim_deg(victimServingCell)); %#ok<AGROW>
    end
    interferenceModeForEntry = interCellMode;
    interferenceClass = "inter_cell_shared_prb";
    if sameMUGroup
        interferenceModeForEntry = "shared_slot_waveform_superposition";
        interferenceClass = "intra_cell_mu_mimo_shared_prb";
    end
    bundle(count).BundleContractVersion = "sixgr_shared_slot_interference/v1"; %#ok<AGROW>
    bundle(count).InterferenceMode = char(interferenceModeForEntry); %#ok<AGROW>
    bundle(count).InterferenceClass = char(interferenceClass); %#ok<AGROW>
    bundle(count).MUMIMOGroupId = double(sixgr.util.structGet(victimGrant, ...
        "MUMIMOGroupId", NaN)); %#ok<AGROW>
    bundle(count).MUMIMOGroupSize = double(sixgr.util.structGet(victimGrant, ...
        "MUMIMOGroupSize", NaN)); %#ok<AGROW>
    bundle(count).SourceId = char(sprintf("%s_cell%d_ue%d_grant%d_to_victim%d", ...
        char(direction), round(double(interfererCell)), round(double(interfererUEIdx)), ...
        round(double(sixgr.util.structGet(entry, "GrantIndex", gi))), round(double(victimUEIdx)))); %#ok<AGROW>
    channelLinkKey = sixgr.channel.ChannelFactory.runtimeChannelKey(cfg, direction, ...
        "UEIndex", double(metricUE), "ServingCell", double(metricCell));
    bundle(count).ChannelLinkKey = char(channelLinkKey); %#ok<AGROW>
    bundle(count).ChannelSeed = double(sixgr.channel.ChannelFactory.runtimeChannelSeed(cfg, channelLinkKey)); %#ok<AGROW>
    bundle(count).Frame = double(sixgr.util.structGet(entry, "Frame", sixgr.util.structGet(runtimeState, "CurrentFrame", NaN))); %#ok<AGROW>
    bundle(count).Slot = double(sixgr.util.structGet(entry, "Slot", sixgr.util.structGet(runtimeState, "CurrentSlot", NaN))); %#ok<AGROW>
    bundle(count).Seed = double(localDeterministicInterferenceSeed(cfg, runtimeState, victimUEIdx, victimServingCell, interfererUEIdx, interfererCell, direction)); %#ok<AGROW>
    if localEnvLogical("SIXGR_VERBOSE_STAGE_LOG", false)
        localAppendRuntimeLog("INFO", ...
            "Coupled interference contribution start: direction=%s victim_grant=%d source_grant=%d victim_ue=%d interferer_ue=%d.", ...
        char(direction), round(double(victimGrantIdx)), ...
            round(double(sixgr.util.structGet(entry, "GrantIndex", gi))), ...
            round(double(victimUEIdx)), round(double(interfererUEIdx)));
    end
    contributionTic = tic;
    [contributionWaveform, contributionMeta, runtimeState] = localBuildSharedSlotReceiverContribution( ...
        bundle(count), entry, runtimeState, direction, metricUE, metricCell);
    if localEnvLogical("SIXGR_VERBOSE_STAGE_LOG", false)
        localAppendRuntimeLog("INFO", ...
            "Coupled interference contribution done: direction=%s victim_grant=%d source_grant=%d elapsed_s=%.3f samples=%d cols=%d.", ...
            char(direction), round(double(victimGrantIdx)), ...
            round(double(sixgr.util.structGet(entry, "GrantIndex", gi))), toc(contributionTic), ...
            size(contributionWaveform, 1), max(1, size(contributionWaveform, 2)));
    end
    bundle(count).SharedSlotContributionWaveform = contributionWaveform; %#ok<AGROW>
    bundle(count).ContributionSampleRate_Hz = double(contributionMeta.SampleRate_Hz); %#ok<AGROW>
    bundle(count).ContributionRxPower_dBm = double(contributionMeta.RxPower_dBm); %#ok<AGROW>
    bundle(count).ContributionPowerReferencePlane = char(contributionMeta.PowerReferencePlane); %#ok<AGROW>
    bundle(count).ContributionSource = char(contributionMeta.Source); %#ok<AGROW>
    bundle(count).ChannelObjectSource = char(contributionMeta.ChannelObjectSource); %#ok<AGROW>
    bundle(count).ChannelObjectClass = char(contributionMeta.ChannelObjectClass); %#ok<AGROW>
    bundle(count).ChannelArrayHandlingStatus = char(contributionMeta.ChannelArrayHandlingStatus); %#ok<AGROW>
    bundle(count).ChannelArrayHandlingBlocker = char(contributionMeta.ChannelArrayHandlingBlocker); %#ok<AGROW>
    bundle(count).ChannelGeometryCouplingLevel = char(contributionMeta.ChannelGeometryCouplingLevel); %#ok<AGROW>
    bundle(count).GeometryAdapterType = char(contributionMeta.GeometryAdapterType); %#ok<AGROW>
    bundle(count).GeometryAdapterSource = char(contributionMeta.GeometryAdapterSource); %#ok<AGROW>
    bundle(count).GeometryAdapterLimitation = char(contributionMeta.GeometryAdapterLimitation); %#ok<AGROW>
    bundle(count).GeometryAdapterPortMapping = char(contributionMeta.GeometryAdapterPortMapping); %#ok<AGROW>
    bundle(count).ChannelUsesSameRuntimeAntennaAssumptions = logical(contributionMeta.ChannelUsesSameRuntimeAntennaAssumptions); %#ok<AGROW>
end
end

function tf = localGrantsShareMUMIMOOpportunity(a, b)
tf = false;
if ~(isstruct(a) && isstruct(b))
    return;
end
enabledA = logical(sixgr.util.structGet(a, "MUMIMOEnabled", false));
enabledB = logical(sixgr.util.structGet(b, "MUMIMOEnabled", false));
sizeA = double(sixgr.util.structGet(a, "MUMIMOGroupSize", NaN));
sizeB = double(sixgr.util.structGet(b, "MUMIMOGroupSize", NaN));
idA = double(sixgr.util.structGet(a, "MUMIMOGroupId", NaN));
idB = double(sixgr.util.structGet(b, "MUMIMOGroupId", NaN));
statusA = lower(strtrim(string(sixgr.util.structGet(a, "MUMIMOPairingStatus", ""))));
statusB = lower(strtrim(string(sixgr.util.structGet(b, "MUMIMOPairingStatus", ""))));
tf = enabledA && enabledB && isfinite(sizeA) && isfinite(sizeB) && ...
    sizeA > 1 && sizeB > 1 && isfinite(idA) && isfinite(idB) && idA == idB && ...
    statusA == "paired_shared_prb_spatial_multiplexing" && ...
    statusB == "paired_shared_prb_spatial_multiplexing";
end

function [contribution, meta, runtimeState] = localBuildSharedSlotReceiverContribution(bundleEntry, cacheEntry, runtimeState, direction, metricUE, metricCell)
txWave = sixgr.util.structGet(cacheEntry, "PrecomputedTxWaveform", []);
sampleRateHz = double(sixgr.util.structGet(cacheEntry, "PrecomputedTxSampleRate_Hz", NaN));
sourceId = string(sixgr.util.structGet(bundleEntry, "SourceId", ...
    sprintf("grant%d", round(double(sixgr.util.structGet(cacheEntry, "GrantIndex", NaN))))));
if isempty(txWave)
    error("sixgr:truth:MissingPrecomputedSharedSlotTxWaveform", ...
        "Full-truth interference source '%s' has no precomputed Tx waveform; receiver contribution tensors cannot be produced without regenerating in the victim path.", ...
        char(sourceId));
end
if ~(isfinite(sampleRateHz) && sampleRateHz > 0)
    sampleRateHz = double(sixgr.util.structGet(bundleEntry, "PrecomputedTxSampleRate_Hz", 30.72e6));
end
cfgC = sixgr.util.structGet(cacheEntry, "Cfg", struct());
cfgC = localConfigureContributionLinkBudget(cfgC, runtimeState, direction, metricUE, metricCell, bundleEntry);
numTx = max(1, size(txWave, 2));
[txRuntimeAntenna, txRuntimeMeta, rxRuntimeAntenna, rxRuntimeMeta, numRx, runtimeNumTx] = ...
    localContributionRuntimeAntennaPair(cfgC, direction, numTx);
txInfoC = struct("OFDM", struct("SampleRate", double(sampleRateHz)));
linkKey = char(string(sixgr.util.structGet(bundleEntry, "ChannelLinkKey", "")));
if strlength(strtrim(string(linkKey))) == 0
    linkKey = char("shared_slot_" + sourceId);
end
    [runtimeState, canonicalChannelState] = localResolveSharedSlotRuntimeChannelState( ...
        runtimeState, cfgC, direction, linkKey, double(metricUE), double(metricCell));
    % Materialize the canonical state before forking it.  On a link's first
    % scheduled MU slot, forking an unmaterialized descriptor and then
    % materializing the two copies independently creates two different
    % fading/array realizations.  The scheduler precoder, peer contribution,
    % and desired waveform must all use one canonical realization at one
    % slot-start time origin.
    canonicalChannelState = sixgr.channel.ChannelFactory.materializeRuntimeChannelState( ...
        canonicalChannelState, cfgC, txWave, txInfoC, ...
    "NumTxAnt", runtimeNumTx, ...
    "NumRxAnt", numRx, ...
    "TransmitAntennaRuntime", txRuntimeAntenna, ...
    "ReceiveAntennaRuntime", rxRuntimeAntenna, ...
    "TransmitAntennaMeta", txRuntimeMeta, ...
    "ReceiveAntennaMeta", rxRuntimeMeta);
    slotStart_s = double(sixgr.util.structGet(cfgC, "lls6g.userContext.RuntimeSlotStartTime_s", NaN));
    if isfinite(slotStart_s) && slotStart_s >= 0
        canonicalChannelState = sixgr.channel.ChannelFactory.advanceRuntimeChannelStateToTime( ...
            canonicalChannelState, slotStart_s, runtimeNumTx, txWave);
    end
    runtimeState = sixgr.truth.CoupledTruthRuntime.commitRuntimeChannelState( ...
        runtimeState, canonicalChannelState);
    % Every signal in a shared MU slot must see the same materialized channel
    % state.  Execute the peer on a deep fork so the canonical state remains
    % available for the desired waveform, which advances it exactly once.
    chState = sixgr.channel.ChannelFactory.forkRuntimeChannelState( ...
        canonicalChannelState);
    [rxContribution, channelReplay, chState] = sixgr.channel.ChannelFactory.applyRuntimeChannelState(chState, txWave);
if size(rxContribution, 2) ~= numRx
    error("sixgr:truth:SharedSlotContributionRxPortMismatch", ...
        "Shared-slot source '%s' produced %d receiver column(s), but the %s source-to-victim channel was materialized for %d receive port(s).", ...
        char(sourceId), size(rxContribution, 2), char(direction), numRx);
end
[contribution, replay] = sixgr.link.applyWaveformImpairments(rxContribution, cfgC, sampleRateHz, ...
    "Endpoint", "rx", ...
    "UseLegacyGlobalConfig", true, ...
    "ApplyPA", false, ...
    "ApplyADC", false, ...
    "ApplyRFChain", false);
channelMeta = sixgr.util.structGet(chState, "Meta", struct());
meta = struct( ...
    "SampleRate_Hz", double(sampleRateHz), ...
    "RxPower_dBm", double(sixgr.util.structGet(replay, "ServingRxPower_dBm", NaN)), ...
    "PowerReferencePlane", char(string(sixgr.util.structGet(replay, ...
        "AbsolutePowerReferencePlane", ""))), ...
    "Source", "runtime_pre_adc_shared_slot_receiver_contribution", ...
    "RuntimeStatePolicy", "deep_fork_at_shared_slot_time_origin_no_canonical_advance", ...
    "ChannelObjectSource", char(string(sixgr.util.structGet(channelMeta, "ChannelObjectSource", "runtime_shared_slot_source_to_victim_channel"))), ...
    "ChannelObjectClass", char(string(sixgr.util.structGet(channelReplay, "ChannelFadingObjectClass", ""))), ...
    "ChannelArrayHandlingStatus", char(string(sixgr.util.structGet(channelMeta, "ChannelArrayHandlingStatus", ""))), ...
    "ChannelArrayHandlingBlocker", char(string(sixgr.util.structGet(channelMeta, "ChannelArrayHandlingBlocker", ""))), ...
    "ChannelGeometryCouplingLevel", char(string(sixgr.util.structGet(channelMeta, "ChannelGeometryCouplingLevel", ""))), ...
    "GeometryAdapterType", char(string(sixgr.util.structGet(channelMeta, "GeometryAdapterType", ""))), ...
    "GeometryAdapterSource", char(string(sixgr.util.structGet(channelMeta, "GeometryAdapterSource", ""))), ...
    "GeometryAdapterLimitation", char(string(sixgr.util.structGet(channelMeta, "GeometryAdapterLimitation", ""))), ...
    "GeometryAdapterPortMapping", char(string(sixgr.util.structGet(channelMeta, "GeometryAdapterPortMapping", "source_waveform_ports_to_victim_receive_ports"))), ...
    "ChannelUsesSameRuntimeAntennaAssumptions", logical(sixgr.util.structGet(channelMeta, "ChannelUsesSameRuntimeAntennaAssumptions", false)));
end

function cfgOut = localConfigureContributionLinkBudget(cfgIn, runtimeState, direction, metricUE, metricCell, bundleEntry)
cfgOut = cfgIn;
direction = upper(string(direction));
userMeta = sixgr.util.structGet(cfgOut, "lls6g.userContext", struct());
if ~(isstruct(userMeta) && ~isempty(fieldnames(userMeta)))
    userMeta = struct();
end
ls = sixgr.util.structGet(runtimeState, "LargeScaleState", struct());
userMeta.RuntimeCurrentDirection = char(direction);
userMeta.Direction = char(direction);
userMeta.RuntimeServingCell = double(metricCell);
userMeta.RuntimeServingCellIndex = double(metricCell);
userMeta.RuntimeUEIndex = double(metricUE);
userMeta.RuntimeServingBasePathloss_dB = localLargeScaleMatrixValue(ls, "BasePathloss_dB", metricUE, metricCell);
userMeta.RuntimeServingPathloss_dB = localLargeScaleMatrixValue(ls, "Pathloss_dB", metricUE, metricCell);
userMeta.RuntimePropagationPathloss_dB = localLargeScaleMatrixValue(ls, "Pathloss_dB", metricUE, metricCell);
userMeta.RuntimePropagationPathlossSource = "CoupledTruthRuntime.LargeScaleState.metric_link_Pathloss_dB";
userMeta.RuntimeServingShadowFading_dB = localLargeScaleMatrixValue(ls, "Shadow_dB", metricUE, metricCell);
userMeta.RuntimeServingO2I_dB = localLargeScaleMatrixValue(ls, "O2I_dB", metricUE, metricCell);
[userMeta.RuntimeServingRSRP_dBm, runtimeServingRSRPSource] = ...
    sixgr.truth.CoupledTruthRuntime.resolveReportableServingRSRPRuntime( ...
    runtimeState, metricUE, metricCell);
userMeta.RuntimeServingRSRPSource = char(runtimeServingRSRPSource);
    if direction == "DL"
        userMeta.RuntimeServingRxPower_dBm = localLargeScaleMatrixValue(ls, "RxPower_dBm", metricUE, metricCell);
        userMeta.RuntimeServingRxPowerDirection = "DL";
        userMeta.RuntimeServingRxPowerSource = "CoupledTruthRuntime.LargeScaleState.RxPower_dBm";
    else
        userMeta.RuntimeServingRxPower_dBm = NaN;
        userMeta.RuntimeServingRxPowerDirection = "UL";
        userMeta.RuntimeServingRxPowerSource = "unavailable_ul_requires_signal_specific_tx_power_and_pathloss";
    end
userMeta.RuntimeServingDistance2D_m = localLargeScaleMatrixValue(ls, "d2d_m", metricUE, metricCell);
userMeta.RuntimeServingDistance3D_m = localLargeScaleMatrixValue(ls, "d3d_m", metricUE, metricCell);
userMeta.RuntimeServingPropagationDelay_s = localLargeScaleMatrixValue(ls, "PropagationDelay_s", metricUE, metricCell);
userMeta.RuntimeServingRadialVelocity_mps = localLargeScaleMatrixValue(ls, "RadialVelocity_mps", metricUE, metricCell);
userMeta.RuntimeServingSignedDopplerHz = localLargeScaleMatrixValue(ls, "SignedDoppler_Hz", metricUE, metricCell);
userMeta.RuntimeServingDopplerHz = localLargeScaleMatrixValue(ls, "Doppler_Hz", metricUE, metricCell);
userMeta.RuntimeServingLOSProbability = localLargeScaleMatrixValue(ls, "LOSProbability", metricUE, metricCell);
losValue = localLargeScaleMatrixValue(ls, "LOS", metricUE, metricCell);
userMeta.RuntimeServingLOS = isfinite(losValue) && logical(losValue);
userMeta.RuntimeGeometrySource = char(string(sixgr.util.structGet(ls, "GeometrySource", "")));
userMeta.RuntimeGeometryDelaySource = char(string(sixgr.util.structGet(ls, "DelaySource", "")));
userMeta.RuntimeGeometryDopplerSource = char(string(sixgr.util.structGet(ls, "DopplerSource", "")));
userMeta.RuntimeChannelComplianceMode = "runtime_coupled_shared_slot_contribution";
userMeta.RuntimePathlossModelSource = "CoupledTruthRuntime.LargeScaleState";
userMeta.RuntimePathlossComplianceStatus = "applied";
userMeta.RuntimeFallbackUsedForPathloss = false;
if isfield(runtimeState, "UE") && isstruct(runtimeState.UE) && isfield(runtimeState.UE, "pos_m") && ...
        metricUE >= 1 && metricUE <= size(runtimeState.UE.pos_m, 1)
    userMeta.RuntimeUEPosition_m = reshape(double(runtimeState.UE.pos_m(metricUE, :)), 1, []);
end
if isfield(ls, "UEVelocity_mps") && metricUE >= 1 && metricUE <= size(ls.UEVelocity_mps, 1)
    userMeta.RuntimeUEVelocity_mps = reshape(double(ls.UEVelocity_mps(metricUE, :)), 1, []);
end
layout = sixgr.util.structGet(runtimeState, "Layout", struct());
bs = sixgr.util.structGet(layout, "bs", struct());
if isstruct(bs) && isfield(bs, "pos_m") && metricCell >= 1 && metricCell <= size(bs.pos_m, 1)
    userMeta.RuntimeServingBSPosition_m = reshape(double(bs.pos_m(metricCell, :)), 1, []);
end
if isfield(ls, "BSVelocity_mps") && metricCell >= 1 && metricCell <= size(ls.BSVelocity_mps, 1)
    userMeta.RuntimeServingBSVelocity_mps = reshape(double(ls.BSVelocity_mps(metricCell, :)), 1, []);
end
if isstruct(bs) && isfield(bs, "azim_deg") && metricCell >= 1 && metricCell <= numel(bs.azim_deg)
    userMeta.RuntimeServingBSAzimuth_deg = double(bs.azim_deg(metricCell));
end
if direction == "UL"
    if isfield(bundleEntry, "VictimServingBSAntenna")
        userMeta.RuntimeServingBSAntenna = bundleEntry.VictimServingBSAntenna;
    end
    if isfield(bundleEntry, "VictimServingBSAntennaMeta")
        userMeta.RuntimeServingBSAntennaMeta = bundleEntry.VictimServingBSAntennaMeta;
    end
    if isfield(bundleEntry, "SourceUEAntenna")
        userMeta.RuntimeUEAntenna = bundleEntry.SourceUEAntenna;
    end
    if isfield(bundleEntry, "SourceUEAntennaMeta")
        userMeta.RuntimeUEAntennaMeta = bundleEntry.SourceUEAntennaMeta;
    end
else
    if isfield(bundleEntry, "SourceBSAntenna")
        userMeta.RuntimeServingBSAntenna = bundleEntry.SourceBSAntenna;
    end
    if isfield(bundleEntry, "SourceBSAntennaMeta")
        userMeta.RuntimeServingBSAntennaMeta = bundleEntry.SourceBSAntennaMeta;
    end
    if isfield(bundleEntry, "VictimUEAntenna")
        userMeta.RuntimeUEAntenna = bundleEntry.VictimUEAntenna;
    end
    if isfield(bundleEntry, "VictimUEAntennaMeta")
        userMeta.RuntimeUEAntennaMeta = bundleEntry.VictimUEAntennaMeta;
    end
end
cfgOut = sixgr.util.structSet(cfgOut, "lls6g.userContext", userMeta);
if isfinite(userMeta.RuntimeServingDistance2D_m)
    cfgOut = sixgr.util.structSet(cfgOut, "channel.distance2D_m", userMeta.RuntimeServingDistance2D_m);
    cfgOut = sixgr.util.structSet(cfgOut, "channel.propagationDistance2D_m", userMeta.RuntimeServingDistance2D_m);
end
if isfinite(userMeta.RuntimeServingDistance3D_m)
    cfgOut = sixgr.util.structSet(cfgOut, "channel.distance3D_m", userMeta.RuntimeServingDistance3D_m);
    cfgOut = sixgr.util.structSet(cfgOut, "channel.propagationDistance_m", userMeta.RuntimeServingDistance3D_m);
end
if isfinite(userMeta.RuntimeServingPropagationDelay_s)
    cfgOut = sixgr.util.structSet(cfgOut, "channel.propagationDelay_s", userMeta.RuntimeServingPropagationDelay_s);
end
cfgOut = sixgr.channel.bindRuntimeDoppler(cfgOut,userMeta);
if isfinite(userMeta.RuntimeServingLOSProbability)
    cfgOut = sixgr.util.structSet(cfgOut, "channel.losProbability", userMeta.RuntimeServingLOSProbability);
end
cfgOut = sixgr.util.structSet(cfgOut, "channel.runtimeLOS", userMeta.RuntimeServingLOS);
% Preserve existing contribution behavior; an absolute reference must keep
% its original frozen N0 rather than acquire thermal or signal-relative noise.
switch localResolveNoiseOperatingMode(cfgOut)
    case {"receiver_noise_figure_thermal_noise","standalone_awgn_snr_argument"}
        cfgOut=sixgr.util.structSet(cfgOut,"run.noiseOperatingMode","receiver_noise_figure_thermal_noise");
    case "absolute_reference_esn0"
        % Keep the original reference policy and capsule.
    otherwise
        error('sixgr:truth:UnsupportedSharedNoisePowerReference','Unsupported contribution noise policy.');
end
end

function [txAnt, txMeta, rxAnt, rxMeta, numRx, runtimeNumTx] = localContributionRuntimeAntennaPair(cfg, direction, numTx)
userMeta = sixgr.util.structGet(cfg, "lls6g.userContext", struct());
direction = upper(string(direction));
if direction == "UL"
    txAnt = sixgr.util.structGet(userMeta, "RuntimeUEAntenna", struct());
    txMeta = sixgr.util.structGet(userMeta, "RuntimeUEAntennaMeta", struct());
    rxAnt = sixgr.util.structGet(userMeta, "RuntimeServingBSAntenna", struct());
    rxMeta = sixgr.util.structGet(userMeta, "RuntimeServingBSAntennaMeta", struct());
    sourceToken = "shared_slot_pusch_interferer_tx_waveform_port_count";
    fallbackRx = double(sixgr.phy.ul.resolveULDirectionalAntennaCount(cfg, "rx", numTx));
else
    txAnt = sixgr.util.structGet(userMeta, "RuntimeServingBSAntenna", struct());
    txMeta = sixgr.util.structGet(userMeta, "RuntimeServingBSAntennaMeta", struct());
    rxAnt = sixgr.util.structGet(userMeta, "RuntimeUEAntenna", struct());
    rxMeta = sixgr.util.structGet(userMeta, "RuntimeUEAntennaMeta", struct());
    sourceToken = "shared_slot_pdsch_interferer_tx_waveform_port_count";
    fallbackRx = localFirstFiniteScalar( ...
        sixgr.util.structGet(cfg, "phy.nRxAnt", []), ...
        sixgr.util.structGet(cfg, "channel.nRxAnt", []), ...
        numTx);
end
runtimeNumTx = localResolveContributionTxPortCapacity(cfg, direction, txAnt, txMeta, numTx);
[txAnt, txMeta] = localContributionRuntimeAntennaView(txAnt, txMeta, ...
    numTx, sourceToken, direction);
numRx = localFirstFiniteScalar( ...
    sixgr.util.structGet(rxMeta, "NumWaveformColumns", []), ...
    sixgr.util.structGet(rxAnt, "NumWaveformColumns", []), ...
    sixgr.util.structGet(rxMeta, "NumLogicalPorts", []), ...
    fallbackRx, ...
    numTx);
numRx = max(1, round(double(numRx)));
end

function numTx = localResolveContributionTxPortCapacity(cfg, direction, txAnt, txMeta, activePortCount)
activePortCount = max(1, round(double(activePortCount)));
direction = upper(string(direction));
if direction == "UL"
    numTx = localFirstFiniteScalar( ...
        sixgr.util.structGet(txMeta, "NumWaveformColumns", []), ...
        sixgr.util.structGet(txMeta, "NumLogicalPorts", []), ...
        sixgr.util.structGet(txAnt, "NumWaveformColumns", []), ...
        sixgr.util.structGet(txAnt, "NumLogicalPorts", []), ...
        sixgr.util.structGet(cfg, "phy.maxULLayers", []), ...
        sixgr.util.structGet(cfg, "phy.pusch.maxLayers", []), ...
        sixgr.util.structGet(cfg, "phy.pusch.dmrs.nPorts", []), ...
        sixgr.util.structGet(cfg, "phy.pusch.NumAntennaPorts", []), ...
        sixgr.util.structGet(cfg, "phy.pusch.numAntennaPorts", []), ...
        sixgr.util.structGet(cfg, "phy.pusch.numPorts", []), ...
        sixgr.util.structGet(cfg, "phy.pusch.nPorts", []), ...
        sixgr.util.structGet(cfg, "phy.pusch.numLayers", []), ...
        sixgr.util.structGet(cfg, "phy.pusch.nLayers", []), ...
        activePortCount);
    if isfinite(numTx) && numTx > 4
        numTx = activePortCount;
    end
else
    numTx = localFirstFiniteScalar( ...
        sixgr.util.structGet(txMeta, "NumWaveformColumns", []), ...
        sixgr.util.structGet(txMeta, "NumLogicalPorts", []), ...
        sixgr.util.structGet(txAnt, "NumWaveformColumns", []), ...
        sixgr.util.structGet(txAnt, "NumLogicalPorts", []), ...
        sixgr.util.structGet(cfg, "phy.maxDLLayers", []), ...
        sixgr.util.structGet(cfg, "phy.pdsch.maxLayers", []), ...
        sixgr.util.structGet(cfg, "phy.pdsch.dmrs.nPorts", []), ...
        sixgr.util.structGet(cfg, "phy.pdsch.numPorts", []), ...
        sixgr.util.structGet(cfg, "phy.pdsch.nPorts", []), ...
        sixgr.util.structGet(cfg, "phy.pdsch.NumAntennaPorts", []), ...
        sixgr.util.structGet(cfg, "phy.pdsch.numAntennaPorts", []), ...
        sixgr.util.structGet(cfg, "phy.pdsch.numLayers", []), ...
        sixgr.util.structGet(cfg, "phy.pdsch.nLayers", []), ...
        activePortCount);
    if isfinite(numTx) && numTx > sixgr.truth.GrantPreparation.maxNRLogicalPDSCHPorts()
        numTx = activePortCount;
    end
end
numTx = max(activePortCount, round(double(numTx)));
end

function trialContext = localRefreshTrialContextRuntimeChannelState(trialContext, runtimeState)
% Refresh a grant context after a shared-slot peer has materialized the
% canonical link.  Grant contexts are built before interference bundles, so
% their ChannelState can otherwise retain the earlier unmaterialized copy.
if ~(isstruct(trialContext) && isstruct(runtimeState))
    return;
end
linkKey = string(sixgr.util.structGet(trialContext, "RuntimeChannelLinkKey", ...
    sixgr.util.structGet(trialContext, "GrantSnapshot.RuntimeChannelLinkKey", ...
    sixgr.util.structGet(trialContext, "HARQContext.ChannelStateKey", ""))));
if strlength(strtrim(linkKey)) == 0
    return;
end
states = sixgr.util.structGet(runtimeState, "RuntimeChannelStates", repmat(struct(), 0, 1));
if ~(isstruct(states) && ~isempty(states))
    return;
end
for stateIdx = 1:numel(states)
    if string(sixgr.util.structGet(states(stateIdx), "LinkKey", "")) == linkKey
        trialContext.ChannelState = states(stateIdx);
        return;
    end
end
end

function [ant, meta] = localContributionRuntimeAntennaView(ant, meta, numColumns, sourceToken, direction)
waveformDomain = lower(strtrim(string(sixgr.util.structGet(ant, "WaveformDomain", ...
    sixgr.util.structGet(meta, "WaveformDomain", "")))));
hybridEnabled = logical(sixgr.util.structGet(ant, "HybridBeamformingEnabled", ...
    sixgr.util.structGet(meta, "HybridBeamformingEnabled", false)));
if waveformDomain == "element" || hybridEnabled
    expectedColumns = localFirstFiniteScalar( ...
        sixgr.util.structGet(ant, "NumWaveformColumns", []), ...
        sixgr.util.structGet(meta, "NumWaveformColumns", []), ...
        sixgr.util.structGet(ant, "NumElements", []), ...
        sixgr.util.structGet(meta, "NumElements", []));
    if ~(isfinite(expectedColumns) && round(double(expectedColumns)) == round(double(numColumns)))
        error("sixgr:truth:HybridInterfererWaveformColumnMismatch", ...
            ['%s shared-slot contribution has %d waveform column(s), but its ' ...
            'runtime hybrid antenna contract requires %d element-domain column(s).'], ...
            char(upper(string(direction))), round(double(numColumns)), ...
            round(double(expectedColumns)));
    end
    meta.NumWaveformColumns = double(expectedColumns);
    meta.WaveformDomain = "element";
    meta.HybridBeamformingEnabled = true;
    meta.RuntimeObjectSource = "AntennaArrayFactory.element_domain_shared_slot_view";
    return;
end
[ant, meta] = sixgr.rf.AntennaArrayFactory.logicalPortView(ant, meta, ...
    max(1, round(double(numColumns))), sourceToken);
end

function [runtimeState, chState] = localResolveSharedSlotRuntimeChannelState(runtimeState, cfg, direction, linkKey, ueIdx, servingCell)
if ~isfield(runtimeState, "RuntimeChannelStates") || ~isstruct(runtimeState.RuntimeChannelStates)
    runtimeState.RuntimeChannelStates = repmat(sixgr.channel.ChannelFactory.emptyRuntimeChannelState(), 0, 1);
end
linkKey = char(string(linkKey));
states = runtimeState.RuntimeChannelStates;
for si = 1:numel(states)
    if string(sixgr.util.structGet(states(si), "LinkKey", "")) == string(linkKey)
        chState = states(si);
        return;
    end
end
seed = sixgr.channel.ChannelFactory.runtimeChannelSeed(cfg, linkKey);
chState = sixgr.channel.ChannelFactory.createRuntimeChannelState(cfg, direction, ...
    "LinkKey", linkKey, ...
    "Seed", double(seed), ...
    "UEIndex", double(ueIdx), ...
    "ServingCell", double(servingCell));
runtimeState.RuntimeChannelStates(end + 1, 1) = chState;
end

function value = localLargeScaleMatrixValue(ls, fieldName, rowIdx, colIdx)
value = NaN;
if ~(isstruct(ls) && isfield(ls, fieldName))
    return;
end
M = double(ls.(fieldName));
rowIdx = round(double(rowIdx));
colIdx = round(double(colIdx));
if rowIdx >= 1 && colIdx >= 1 && rowIdx <= size(M, 1) && colIdx <= size(M, 2)
    value = double(M(rowIdx, colIdx));
end
end

function tf = localGrantsOverlap(grantA, grantB)
tf = false;
prbA = unique(round(double(sixgr.util.structGet(grantA, "PRBSet", []))));
prbB = unique(round(double(sixgr.util.structGet(grantB, "PRBSet", []))));
if isempty(intersect(prbA(:), prbB(:)))
    return;
end
symA = double(sixgr.util.structGet(grantA, "SymbolAllocation", []));
symB = double(sixgr.util.structGet(grantB, "SymbolAllocation", []));
if numel(symA) < 2 || numel(symB) < 2
    % Missing allocation metadata cannot prove non-overlap. Keep the
    % conservative collision decision without fabricating full-slot bounds.
    tf = true;
    return;
end
startA = double(symA(1)); stopA = startA + double(symA(2));
startB = double(symB(1)); stopB = startB + double(symB(2));
tf = max(startA, startB) < min(stopA, stopB);
end

function seed = localDeterministicInterferenceSeed(cfg, runtimeState, victimUEIdx, victimServingCell, interfererUEIdx, interfererCell, direction)
seedBase = double(sixgr.util.structGet(cfg, "run.seed", 1));
dirOffset = sum(double(char(upper(string(direction)))));
slotIdx = double(sixgr.util.structGet(runtimeState, "CurrentSlot", 1));
frameIdx = double(sixgr.util.structGet(runtimeState, "CurrentFrame", 1));
receiverKey = double(victimUEIdx);
if upper(string(direction)) == "UL" && isfinite(victimServingCell) && victimServingCell >= 1
    receiverKey = double(victimServingCell);
end
seed = mod(seedBase + 104729 * frameIdx + 1543 * slotIdx + 313 * receiverKey + 571 * interfererUEIdx + 997 * interfererCell + dirOffset, 2^31 - 1);
seed = max(1, round(double(seed)));
end

function [bsEntry, ueEntry] = localRuntimeAntennaEntriesForVictim(runtimeState, ueIdx, servingCell)
bsEntry = struct();
ueEntry = struct();
bsRuntime = sixgr.util.structGet(runtimeState, "BSAntennaRuntime", repmat(struct(), 0, 1));
ueRuntime = sixgr.util.structGet(runtimeState, "UEAntennaRuntime", repmat(struct(), 0, 1));
if isfinite(servingCell) && servingCell >= 1 && servingCell <= numel(bsRuntime)
    bsEntry = bsRuntime(servingCell);
end
if isfinite(ueIdx) && ueIdx >= 1 && ueIdx <= numel(ueRuntime)
    ueEntry = ueRuntime(ueIdx);
end
end

function entry = localRuntimeBSAntennaEntry(runtimeState, cellIdx)
entry = struct();
bsRuntime = sixgr.util.structGet(runtimeState, "BSAntennaRuntime", repmat(struct(), 0, 1));
cellIdx = round(double(cellIdx));
if isfinite(cellIdx) && cellIdx >= 1 && cellIdx <= numel(bsRuntime)
    entry = bsRuntime(cellIdx);
end
end

function entry = localRuntimeUEAntennaEntry(runtimeState, ueIdx)
entry = struct();
ueRuntime = sixgr.util.structGet(runtimeState, "UEAntennaRuntime", repmat(struct(), 0, 1));
ueIdx = round(double(ueIdx));
if isfinite(ueIdx) && ueIdx >= 1 && ueIdx <= numel(ueRuntime)
    entry = ueRuntime(ueIdx);
end
end

function value = localFirstFiniteScalar(varargin)
value = NaN;
for i = 1:nargin
    candidate = varargin{i};
    if isempty(candidate)
        continue;
    end
    if isnumeric(candidate) || islogical(candidate)
        candidate = double(candidate);
        candidate = candidate(:);
        idx = find(isfinite(candidate), 1, "first");
        if ~isempty(idx)
            value = double(candidate(idx));
            return;
        end
    end
end
end

function [txWave, sampleRateHz] = localPrecomputeCoupledInterfererTxWaveform(cfg, direction, signalType, grantResolved, grantContext)
txWave = [];
sampleRateHz = NaN;
direction = upper(string(direction));
signalType = upper(string(signalType));
% Cache exact grant-specific interferer Tx waveforms once per slot grant so
% each victim still sees its own per-link channel, but we avoid rebuilding
% the same UL/DL waveform for every overlap evaluation.

seed = double(sixgr.util.structGet(grantContext, "Seed", NaN));
restore = [];
if isfinite(seed) && seed >= 1
    priorRng = rng;
    restore = onCleanup(@() rng(priorRng)); %#ok<NASGU>
    rng(max(1, round(seed)), "twister");
end

try
    if signalType == "PUCCH"
        connected = localBuildConnectedPUCCHInterferer( ...
            cfg,grantResolved,grantContext);
        tx = sixgr.phy.pucch.PUCCHTransmitter.transmit( ...
            connected.Carrier,connected.Assignment,connected.Report);
        txInfo = struct("OFDMInfo",tx.OFDMInfo, ...
            "AssignmentDigest",tx.AssignmentDigest, ...
            "ReportDigest",tx.ReportDigest, ...
            "ConnectedModeEvidenceEligible", ...
            tx.ConnectedModeEvidenceEligible);
    elseif direction == "UL"
        txArgs = {"CompactOutput", true};
        txArgs = localAppendCoupledGrantReplayTxArgs(txArgs, grantResolved, "UL");
        transportBlockBits = sixgr.util.structGet(grantContext, "TransportBlockBits", int8([]));
        if ~isempty(transportBlockBits)
            txArgs = [txArgs {"TransportBlockBits", transportBlockBits}]; %#ok<AGROW>
        end
        rv = sixgr.util.structGet(grantContext, "RV", []);
        if ~isempty(rv)
            txArgs = [txArgs {"RV", rv}]; %#ok<AGROW>
        end
        transformPrecoding = sixgr.util.structGet(grantResolved, "TransformPrecoding", []);
        if ~isempty(transformPrecoding)
            cfg = sixgr.util.structSet(cfg, "phy.pusch.transformPrecoding", logical(transformPrecoding));
        end
        [tx, txInfo] = sixgr.phy.ul.PUSCH_Tx(cfg, txArgs{:});
        [tx.Waveform, powerCtrl, cfg, ~] = ...
            sixgr.link.bindPUSCHPowerControlContext( ...
            tx.Waveform, cfg, tx, grantResolved, struct());
    else
        cfg = localConfigureCoupledDLCalibrationOwnership( ...
            cfg, grantResolved);
        txArgs = {"CompactOutput", true, ...
            "ExecutionProfile", "phy_calibration", ...
            "CellCommonSignalOwnershipMode", "reserve_only"};
        txArgs = localAppendCoupledGrantReplayTxArgs(txArgs, grantResolved, "DL");
        transportBlockBits = sixgr.util.structGet(grantContext, "TransportBlockBits", int8([]));
        if ~isempty(transportBlockBits)
            txArgs = [txArgs {"TransportBlockBits", transportBlockBits}]; %#ok<AGROW>
        end
        rv = sixgr.util.structGet(grantContext, "RV", []);
        if ~isempty(rv)
            txArgs = [txArgs {"RV", rv}]; %#ok<AGROW>
        end
        precodingMatrix = sixgr.truth.selectGrantReplayPDSCHPrecodingMatrix(grantResolved);
        if sixgr.truth.GrantPreparation.grantCarriesActiveDLPrecoding(grantResolved, precodingMatrix)
            txArgs = [txArgs {"PrecodingMatrix", precodingMatrix}]; %#ok<AGROW>
        end
        [tx, txInfo] = sixgr.phy.dl.PDSCH_Tx(cfg, txArgs{:});
    end
    txWave = sixgr.util.structGet(tx, "Waveform", []);
    if ~isempty(txWave)
        [txWave, powerContext] = sixgr.rf.applyPowerContext(txWave, cfg, char(direction), txInfo);
        if direction == "UL" && exist("powerCtrl", "var") && logical(powerCtrl.Enabled)
            powerCtrl.AmplitudeScale = double(powerContext.AmplitudeScale);
            powerCtrl.MeasuredWaveformPower_dBm = double(powerContext.OutputTotalPower_dBm);
            powerCtrl.PowerClosureError_dB = double(powerContext.PowerClosureError_dB);
            powerContext.PowerControlAmplitudeScale = double(powerCtrl.AmplitudeScale);
            txInfo.PowerContext = powerContext;
        end
        tx.PowerContext = powerContext; %#ok<NASGU>
        if sixgr.rf.hasExplicitTransmitConfig(cfg)
            txRfOut = sixgr.rf.applyRFImpairmentChain(txWave, cfg, ...
                "SampleRateHz", localResolveCoupledTxSampleRate(tx, txInfo), ...
                "Direction", char(direction), ...
                "MeasurementPoint", "tx_output", ...
                "Endpoint", "tx", ...
                "StrictMutationRequired", false, ...
                "UseLegacyGlobalConfig", false, ...
                "ApplyPA", false, ...
                "ApplyADC", false);
            txWave = cast(txRfOut.Waveform, "like", txWave);
        end
    end
    sampleRateHz = localResolveCoupledTxSampleRate(tx, txInfo);
catch ME
    wrapped = MException("sixgr:truth:InterfererTxPrecomputeFailed", ...
        "Coupled %s interferer Tx precompute failed for signal %s: %s %s", ...
        char(direction), char(signalType), char(string(ME.identifier)), char(string(ME.message)));
    wrapped = addCause(wrapped, ME);
    throwAsCaller(wrapped);
end
end

function connected = localBuildConnectedPUCCHInterferer( ...
        cfg,grant,context)
rnti=localFirstFiniteScalar( ...
    sixgr.util.structGet(context,"RNTI",[]), ...
    sixgr.util.structGet(grant,"RNTI",[]), ...
    sixgr.util.structGet(cfg,"phy.rnti",[]));
ueID=localFirstFiniteScalar( ...
    sixgr.util.structGet(context,"UEIndex",[]), ...
    sixgr.util.structGet(grant,"UEIndex",[]),1);
servingCell=localFirstFiniteScalar( ...
    sixgr.util.structGet(context,"ServingCell",[]), ...
    sixgr.util.structGet(grant,"ServingCell",[]),0);
componentCarrier=localFirstFiniteScalar( ...
    sixgr.util.structGet(context,"ComponentCarrier",[]),0);
activeBWP=localFirstFiniteScalar( ...
    sixgr.util.structGet(context,"ActiveULBWP",[]),0);
ackBits=int8(sixgr.util.structGet(context,"HARQACKBits", ...
    sixgr.util.structGet(context,"ExpectedUCIBits",int8(1))));
if isempty(ackBits),ackBits=int8(1);end
ack=logical(ackBits(1));
sourceSlot=localFirstFiniteScalar( ...
    sixgr.util.structGet(context,"SourceSlot",[]), ...
    sixgr.util.structGet(grant,"SourceSlot",[]),0);
targetSlot=localFirstFiniteScalar( ...
    sixgr.util.structGet(context,"ScheduledAbsoluteSlot",[]), ...
    sixgr.util.structGet(grant,"ScheduledAbsoluteSlot",[]), ...
    sourceSlot+1);
k1=targetSlot-sourceSlot;
if ~(isfinite(k1)&&k1>=0&&k1==fix(k1))
    error("sixgr:phy:pucch:InvalidK1", ...
        "Coupled PUCCH interferer requires exact decoded timing state.");
end
ue=struct("UEID",ueID,"RNTI",rnti, ...
    "ServingCell",servingCell,"PUCCHCell",servingCell, ...
    "ComponentCarrier",componentCarrier,"ActiveULBWP",activeBWP);
frame=struct("K1",k1,"K1Source","decoded_dci", ...
    "PDSCHEndSlot",sourceSlot,"TargetSlot",targetSlot, ...
    "DecodedPRI",localFirstFiniteScalar( ...
    sixgr.util.structGet(context,"PRIValue",[]),0), ...
    "PRIFieldWidth",3,"PRIProvenance","decoded_dci_interferer", ...
    "FirstCCE",localFirstFiniteScalar( ...
    sixgr.util.structGet(context,"FirstCCE",[]),NaN), ...
    "NumCCE",localFirstFiniteScalar( ...
    sixgr.util.structGet(context,"NumCCE",[]),NaN), ...
    "SlotSymbolOwnership","UUUUUUUUUUUUUU", ...
    "FlexibleResolutionProvided",false, ...
    "TriggeringEventID",string(sixgr.util.structGet( ...
    context,"PUCCHGrantId","coupled_interferer")));
typed=sixgr.phy.pucch.PUCCHConfigBuilder.connectedHARQ( ...
    cfg,ue,ack,frame);
typed.Carrier=sixgr.phy.grid.makeCarrier(cfg);
connected=typed;
end

function cfgOut = localConfigureCoupledDLCalibrationOwnership(cfgOut, grant)
phyGrant = sixgr.util.structGet(grant, "PHYGrant", struct());
nLayers = localFirstFiniteScalar( ...
    sixgr.util.structGet(grant, "NumLayers", []), ...
    sixgr.util.structGet(phyGrant, "CodingLayout.NumLayers", []), ...
    sixgr.util.structGet(cfgOut, "phy.pdsch.numLayers", []), 1);
nLayers = max(1, round(double(nLayers)));
numCodewords = 1 + double(nLayers > 4);
cfgOut.run.pdschExecutionProfile = "phy_calibration";
cfgOut.phy.pdsch.executionProfile = "phy_calibration";
cfgOut.phy.pdsch.mcsTable = repmat( ...
    "calibration_explicit", 1, numCodewords);
cfgOut.phy.pdsch.mcsIndex = 0:(numCodewords - 1);

modulation = string(sixgr.util.structGet(grant, "Modulation", ...
    sixgr.util.structGet(phyGrant, "CodingLayout.Modulation", ...
    sixgr.util.structGet(cfgOut, "phy.pdsch.modulation", ""))));
pdschConfig = sixgr.util.structGet(grant, "PDSCHConfig", []);
if strlength(strtrim(join(modulation, ""))) == 0 && ...
        ~isempty(pdschConfig) && isobject(pdschConfig) && ...
        isprop(pdschConfig, "Modulation")
    modulation = string(pdschConfig.Modulation);
end
modulation = upper(strtrim(modulation(:).'));
if any(modulation == "1024QAM")
    % Do not manufacture 1024QAM eligibility for an interferer replay.
    % Explicit UE/RRC/DCI and deployment context must already be supplied.
    return;
end
cfgOut.phy.pdsch.mcsContext = struct( ...
    "UECapability1024QAM", false, ...
    "RRCEnabled1024QAM", false, ...
    "DCIEnabled1024QAM", false, ...
    "DeploymentAllows1024QAM", false, ...
    "FrequencyRangeAllows1024QAM", false, ...
    "BandAllows1024QAM", false, ...
    "FrequencyRange", "not_applicable_non1024_interferer_replay", ...
    "OperatingBand", "not_applicable_non1024_interferer_replay", ...
    "DeploymentClass", "coupled_interferer_calibration");
end

function txArgs = localAppendCoupledGrantReplayTxArgs(txArgs, grant, direction)
if ~(isstruct(grant) && ~isempty(fieldnames(grant)))
    return;
end
direction = upper(string(direction));
phyGrant = sixgr.util.structGet(grant, "PHYGrant", struct());
if isstruct(phyGrant) && ~isempty(fieldnames(phyGrant))
    txArgs = [txArgs {"PHYGrant", phyGrant}]; %#ok<AGROW>
    return;
end
carrier = sixgr.util.structGet(grant, "CarrierConfig", []);
if ~isempty(carrier)
    txArgs = [txArgs {"Carrier", carrier}]; %#ok<AGROW>
end
if direction == "UL"
    chCfg = sixgr.util.structGet(grant, "PUSCHConfig", []);
    if ~isempty(chCfg)
        txArgs = [txArgs {"PUSCH", chCfg}]; %#ok<AGROW>
    end
else
    chCfg = sixgr.util.structGet(grant, "PDSCHConfig", []);
    if ~isempty(chCfg)
        txArgs = [txArgs {"PDSCH", chCfg}]; %#ok<AGROW>
    end
end
targetCodeRate = double(sixgr.util.structGet(grant, "TargetCodeRate", NaN));
if isfinite(targetCodeRate) && targetCodeRate > 0
    txArgs = [txArgs {"TargetCodeRate", targetCodeRate}]; %#ok<AGROW>
end
storedTBSize = double(sixgr.util.structGet(grant, "TBSBits", ...
    sixgr.util.structGet(grant, "TransportBlockSize", NaN)));
if localCoupledGrantRequiresTransportBlockSizeOverride(grant) && isfinite(storedTBSize) && storedTBSize > 0
    txArgs = [txArgs {"TransportBlockSizeOverride", round(storedTBSize)}]; %#ok<AGROW>
end
xOverhead = double(sixgr.util.structGet(grant, "XOverhead", NaN));
if isfinite(xOverhead) && xOverhead >= 0
    txArgs = [txArgs {"XOverhead", xOverhead}]; %#ok<AGROW>
end
numTxAnt = double(sixgr.util.structGet(grant, "NumTxAnt", NaN));
if isfinite(numTxAnt) && numTxAnt >= 1
    txArgs = [txArgs {"NumTxAnt", numTxAnt}]; %#ok<AGROW>
end
end

function tf = localCoupledGrantRequiresTransportBlockSizeOverride(grant)
tf = false;
if ~(isstruct(grant) && ~isempty(fieldnames(grant)))
    return;
end
tf = sixgr.truth.GrantPreparation.grantIsRetransmission(grant) || ...
    sixgr.util.logicalAny(sixgr.util.structGet(grant, "HARQIsRetransmission", false)) || ...
    sixgr.util.logicalAny(sixgr.util.structGet(grant, "HARQProcessKey.IsRetransmission", false)) || ...
    contains(lower(strtrim(string(sixgr.util.structGet(grant, "GrantReason", "")))), "retrans");
end

function sampleRateHz = localResolveCoupledTxSampleRate(tx, txInfo)
sampleRateHz = [];
if nargin >= 2 && isstruct(txInfo)
    sampleRateHz = sixgr.util.structGet(txInfo, "OFDM.SampleRate", []);
end
if isempty(sampleRateHz) && isstruct(tx)
    carrier = sixgr.util.structGet(tx, "Carrier", []);
    if ~isempty(carrier)
        try
            ofdmInfo = nrOFDMInfo(carrier);
            sampleRateHz = double(sixgr.util.structGet(ofdmInfo, "SampleRate", []));
        catch
            sampleRateHz = [];
        end
    end
end
if isempty(sampleRateHz) || ~isfinite(double(sampleRateHz)) || double(sampleRateHz) <= 0
    sampleRateHz = 30.72e6;
else
    sampleRateHz = double(sampleRateHz);
end
end



function grant = localRefreshGrantSnapshotFromTrial(grant, T)
if ~(isstruct(grant) && istable(T) && ~isempty(T))
    return;
end
vars = string(T.Properties.VariableNames);
stringFields = [ ...
    "ConfiguredBeamSelectionStrategy","PrecoderSource","PrecodingMode","PrecodingApplicationStage", ...
    "AppliedBeamIndexSet","AppliedPrecoderPMIType","AppliedPrecoderCodebookMode","RequestedVsAppliedPrecoderPMIMatchStatus", ...
    "AppliedPrecoderMatrixSHA256","RequestedPrecoderSHA256","AppliedPrecoderSHA256","PrecoderDigestDomain","FrozenGrantContextId", ...
    "FrequencyHoppingMode","FrequencyHoppingToolboxMode", ...
    "UCIOnPUSCHSource","HARQACKDecodeStatus","HARQACKDecodeReason", ...
    "GrantContextId","GrantSharedStateCommitMode","TBSInputModulation","TBSInputSource"];
logicalFields = [ ...
    "PrecodingActive","ExplicitBeamWeightsApplied","TransformPrecodingApplied","FrequencyHoppingApplied","BeamformingApplied", ...
    "UCIOnPUSCHApplied","HARQACKContentMatch","GrantWorkerSafe"];
numericFields = [ ...
    "PMI","CRI","AppliedPrecoderPMI","PrecodingNumPorts","PrecodingNumLayers", ...
    "PrecodingMatrixRows","PrecodingMatrixCols","SecondHopStartPRB","TBSBits","TBSBytes","HARQACKBitCount", ...
    "TBSInputNumLayers","TBSInputNPRB","TBSInputNREPerPRB", ...
    "TBSInputTargetCodeRate","TBSInputXOverhead"];

for i = 1:numel(stringFields)
    fieldName = stringFields(i);
    if ismember(fieldName, vars)
        grant.(char(fieldName)) = char(localTrialStructStringValue(T.(char(fieldName))(1)));
    end
end
for i = 1:numel(logicalFields)
    fieldName = logicalFields(i);
    if ismember(fieldName, vars)
        grant.(char(fieldName)) = logical(T.(char(fieldName))(1));
    end
end
for i = 1:numel(numericFields)
    fieldName = numericFields(i);
    if ismember(fieldName, vars)
        grant.(char(fieldName)) = double(T.(char(fieldName))(1));
    end
end

% The executed trial, rather than the pre-execution scheduler shell, is the
% authority for the spatial rank that reached the waveform chain.  Keep all
% canonical grant aliases synchronized before the snapshot is committed to
% the grant trace and HARQ entity.  This is especially important for HARQ
% replays: a stale rank-one scheduler shell must not overwrite a rank-two
% waveform execution in the persisted evidence or in the next replay.
executedLayers = NaN;
layerFields = ["EffectiveLayers", "Layers", "PrecodingNumLayers", "ConfiguredLayers"];
for i = 1:numel(layerFields)
    fieldName = layerFields(i);
    if ~ismember(fieldName, vars)
        continue;
    end
    candidate = double(T.(char(fieldName))(1));
    if isscalar(candidate) && isfinite(candidate) && candidate >= 1
        executedLayers = max(1, round(candidate));
        break;
    end
end
if isfinite(executedLayers)
    grant.NumLayers = double(executedLayers);
    grant.Layers = double(executedLayers);
    grant.RI = double(executedLayers);
    grant.RIUsed = double(executedLayers);
    grant.Rank = double(executedLayers);
    grant.RankIndicator = double(executedLayers);
    grant.TBSInputNumLayers = double(executedLayers);
end
end

function token = localTrialStructStringValue(value)
if isempty(value)
    token = "";
    return;
end
if isstring(value)
    token = string(value(1));
elseif iscell(value)
    if isempty(value{1})
        token = "";
    else
        token = string(value{1});
    end
elseif ischar(value)
    token = string(value);
else
    token = string(value(1));
end
if any(ismissing(token))
    token = "";
else
    token = strtrim(token);
end
end



















function varargout = localFormatNumericVector(varargin)
% Compatibility delegate; the implementation and schema have one owner.
[varargout{1:nargout}] = sixgr.truth.PDCCHControlRuntime.formatNumericVector(varargin{:});
end


















function state = localInitCoupledTruthRuntimeState(cfg, runFolder, multiUser, controlTrials, totalTrafficFrames)
if nargin < 5
    totalTrafficFrames = max(1, round(double(sixgr.util.structGet(cfg, "run.numFrames", 1))));
end
state = sixgr.truth.CoupledTruthRuntime.initialize(cfg, runFolder, multiUser, controlTrials, totalTrafficFrames);
end

function state = localAdvanceCoupledRuntimeFrame(state, cfg, multiUser, absoluteFrame, snr_dB)
state = sixgr.truth.CoupledTruthRuntime.advanceFrame(state, cfg, multiUser, absoluteFrame, snr_dB);
end

function [allowDL, allowUL, slotLabel] = localCoupledSlotDuplexState(cfg, canonicalSlot)
duplexMode = sixgr.phy.frame.resolveDuplexMode(cfg);
switch duplexMode
    case "FDD"
        % Paired FDD carriers permit canonical DL scheduling and UL
        % execution in the same absolute slot. Frequency separation, not
        % a TDD slot partition, supplies direction isolation.
        allowDL = true;
        allowUL = true;
        slotLabel = "FDD";
    case "TDD"
        % The coupled runtime uses one-based physical slot numbers while
        % resolveTDDSlotPartition implements the canonical zero-based slot
        % convention used by the timing engine.
        partition = sixgr.util.resolveTDDSlotPartition( ...
            cfg, double(canonicalSlot) - 1);
        allowDL = logical(partition.AllowDL);
        allowUL = logical(partition.AllowUL);
        slotLabel = string(partition.SlotLabel);
    otherwise
        error("sixgr:truth:runWaveformLinkBundle:InvalidCoupledDuplexMode", ...
            "Coupled truth execution requires a resolved FDD or TDD duplex mode; received '%s'.", ...
            char(duplexMode));
end
end

function tf = localIsCoupledDirectionalPublishSlotComplete(runtimeState, direction)
direction = upper(string(direction));
allowDL = logical(sixgr.util.structGet(runtimeState, "CurrentSlotDLAllowed", true));
allowUL = logical(sixgr.util.structGet(runtimeState, "CurrentSlotULAllowed", true));
switch direction
    case "DL"
        tf = allowDL && ~allowUL;
    case "UL"
        tf = allowUL;
    otherwise
        tf = true;
end
end

function state = localBeginCoupledRuntimeSlot(state, cfg, userCfg, ueIdx, direction, sweepIdx, sweepCount, absoluteFrame, totalFrames, snr_dB)
state = sixgr.truth.CoupledTruthRuntime.beginSlot(state, cfg, userCfg, ueIdx, direction, sweepIdx, sweepCount, absoluteFrame, totalFrames, snr_dB);
end


function context = localResolveCoupledHARQTrialContext(state, ueIdx, direction)
context = sixgr.truth.CoupledTruthRuntime.resolveHARQTrialContext(state, ueIdx, direction);
end

function [state, trialT] = localCompleteCoupledRuntimeSlot(state, cfgU, ueIdx, direction, trialT, res)
[state, trialT] = sixgr.truth.CoupledTruthRuntime.completeSlot(state, cfgU, ueIdx, direction, trialT, res);
end

function state = localWriteCoupledRuntimeTables(state, runFolder)
state = sixgr.truth.CoupledTruthRuntime.writeTables(state, runFolder);
sixgr.truth.exportSharedSIB1Reception(state,runFolder);
end

function ME = localPersistCoupledRuntimeFailureCheckpoint( ...
        ME, state, rootRunFolder, cfg, dlTrials, ulTrials, ...
        dlTablePath, ulTablePath, dlConstT, ulConstT, dlConstellationPath, ulConstellationPath)
% Persist only observations completed before a coupled-runtime exception.
% The checkpoint is diagnostic evidence, never a successful finalization,
% and the original exception is always rethrown after persistence attempts.
slotNow = double(sixgr.util.structGet(state, "CurrentSlot", NaN));
frameNow = double(sixgr.util.structGet(state, "CurrentFrame", NaN));
state.RuntimeFailure = struct( ...
    "Identifier", string(ME.identifier), ...
    "Message", string(ME.message), ...
    "Slot", slotNow, ...
    "Frame", frameNow, ...
    "DLTrialRows", localSafeTableHeight(dlTrials), ...
    "ULTrialRows", localSafeTableHeight(ulTrials), ...
    "EvidenceScope", "completed_runtime_observations_before_failure");
state.ProfileStopReason = "runtime_failure_checkpoint";

% Preserve the original exception while it is still available, before any
% multi-gigabyte table or constellation recovery can delay/abort reporting.
% This failure receipt must never imply that the current slot completed.
localAppendRuntimeLog("ERROR", ...
    "Coupled truth runtime failed before recovery publication: " + ...
     "slot=%g frame=%g dl_rows=%d ul_rows=%d error=%s %s", ...
    slotNow, frameNow, localSafeTableHeight(dlTrials), ...
    localSafeTableHeight(ulTrials), char(string(ME.identifier)), ...
    char(string(ME.message)));
try
    sixgr.truth.persistRuntimeFailureNotice(ME,state,rootRunFolder, ...
        localSafeTableHeight(dlTrials),localSafeTableHeight(ulTrials));
catch checkpointME
    % A secondary write failure cannot replace the original throw site.
    ME = addCause(ME, checkpointME);
end

% Capture only completed receiver samples already in the coordinator. An
% exception must not lose these because final export was never reached.
for capture={ {dlConstellationPath,dlConstT}, {ulConstellationPath,ulConstT} }
    pair=capture{1};
    if strlength(string(pair{1}))>0 && istable(pair{2}) && ~isempty(pair{2})
        try
            sixgr.util.csvWriteTable(pair{1},pair{2},"PreserveSchema",true);
        catch checkpointME
            ME=addCause(ME,checkpointME);
        end
    end
end

try
    state = localWriteCoupledRuntimeTables(state, rootRunFolder);
catch checkpointME
    ME = addCause(ME, checkpointME);
end
try
    localWriteNonemptyFailureTrialTable( ...
        dlTablePath, dlTrials, "DL", cfg);
    localWriteNonemptyFailureTrialTable( ...
        ulTablePath, ulTrials, "UL", cfg);
catch checkpointME
    ME = addCause(ME, checkpointME);
end
localAppendRuntimeLog("ERROR", ...
    "Coupled truth runtime failed after measured checkpoint: " + ...
     "slot=%g frame=%g dl_rows=%d ul_rows=%d error=%s %s", ...
    slotNow, frameNow, localSafeTableHeight(dlTrials), ...
    localSafeTableHeight(ulTrials), char(string(ME.identifier)), ...
    char(string(ME.message)));
end

function localWriteNonemptyFailureTrialTable(pathText, T, direction, cfg)
if strlength(strtrim(string(pathText))) == 0 || ...
        ~(istable(T) && ~isempty(T))
    return;
end
T = localCanonicalizeLinkTrialExport(T, direction, cfg);
T = sixgr.truth.bindCoupledExecutionIdentity(T, cfg, direction, true);
sixgr.util.csvWriteTable(pathText, T, "PreserveSchema", true);
end

function n = localSafeTableHeight(T)
n = 0;
if istable(T)
    n = double(height(T));
end
end

function ctl = localResolveCoupledProfileControl(runFolder, totalSlots)
mode = strtrim(string(getenv("SIXGR_PROFILE_MODE")));
ctl = struct();
ctl.Enabled = strlength(mode) > 0;
ctl.Mode = mode;
ctl.RunFolder = string(fileparts(char(string(runFolder))));
ctl.TotalSlots = double(totalSlots);
ctl.FlushEverySlots = localEnvDouble("SIXGR_FLUSH_EVERY_SLOTS", Inf);
ctl.FlushEverySeconds = localEnvDouble("SIXGR_FLUSH_EVERY_SECONDS", Inf);
ctl.InternalWallClockGuardSeconds = localEnvDouble("SIXGR_INTERNAL_WALL_GUARD_SECONDS", Inf);
ctl.StopAfterAccessComplete = localEnvLogical("SIXGR_STOP_AFTER_ACCESS_COMPLETE", false);
ctl.StopAfterFirstExecutableDataGrant = localEnvLogical("SIXGR_STOP_AFTER_FIRST_EXECUTABLE_DATA_GRANT", false);
ctl.StopAfterFirstNPDSCHGrants = localEnvDouble("SIXGR_STOP_AFTER_FIRST_N_PDSCH_GRANTS", Inf);
ctl.StopAfterFirstNPUSCHGrants = localEnvDouble("SIXGR_STOP_AFTER_FIRST_N_PUSCH_GRANTS", Inf);
ctl.LastFlushSlot = 0;
ctl.LastFlushElapsed_s = 0;
ctl.StartTic = [];
if ctl.Enabled
    if ~(isfinite(ctl.FlushEverySlots) && ctl.FlushEverySlots >= 1)
        ctl.FlushEverySlots = 25;
    end
    if ~(isfinite(ctl.FlushEverySeconds) && ctl.FlushEverySeconds >= 1)
        ctl.FlushEverySeconds = 30;
    end
end
end

function value = localEnvDouble(name, defaultValue)
raw = strtrim(string(getenv(char(string(name)))));
value = double(defaultValue);
if strlength(raw) == 0
    return;
end
tmp = str2double(raw);
if isfinite(tmp) || isinf(tmp)
    value = double(tmp);
end
end

function tf = localEnvLogical(name, defaultValue)
raw = lower(strtrim(string(getenv(char(string(name))))));
if strlength(raw) == 0
    tf = logical(defaultValue);
    return;
end
tf = any(raw == ["1","true","yes","on"]);
end

function [state, ctl] = localMaybeFlushCoupledProfileSnapshot(state, rootRunFolder, ctl, absoluteSlot)
if ~(isstruct(ctl) && logical(sixgr.util.structGet(ctl, "Enabled", false)))
    return;
end
if isempty(sixgr.util.structGet(ctl, "StartTic", []))
    ctl.StartTic = tic;
end
elapsed = toc(ctl.StartTic);
slotDelta = double(absoluteSlot) - double(sixgr.util.structGet(ctl, "LastFlushSlot", 0));
timeDelta = elapsed - double(sixgr.util.structGet(ctl, "LastFlushElapsed_s", 0));
slotDue = isfinite(double(ctl.FlushEverySlots)) && slotDelta >= double(ctl.FlushEverySlots);
timeDue = isfinite(double(ctl.FlushEverySeconds)) && timeDelta >= double(ctl.FlushEverySeconds);
if ~(slotDue || timeDue)
    return;
end
try
    if localShouldMirrorProfileRuntimeTables(ctl)
        state = localWriteCoupledRuntimeTables(state, rootRunFolder);
    end
    localWriteCoupledProfileSnapshot(rootRunFolder, state, ctl, absoluteSlot, elapsed);
    ctl.LastFlushSlot = double(absoluteSlot);
    ctl.LastFlushElapsed_s = double(elapsed);
catch ME
    localAppendRuntimeLog("WARN", ...
        "Coupled profile snapshot flush failed at slot=%d: %s %s", ...
        round(double(absoluteSlot)), char(string(ME.identifier)), char(string(ME.message)));
end
end

function tf = localShouldMirrorProfileRuntimeTables(ctl)
tf = true;
if ~(isstruct(ctl) && logical(sixgr.util.structGet(ctl, "Enabled", false)))
    return;
end
override = strtrim(string(getenv("SIXGR_PROFILE_FLUSH_RUNTIME_TABLES")));
if strlength(override) > 0
    tf = any(lower(override) == ["1","true","yes","on"]);
    return;
end
mode = lower(strtrim(string(sixgr.util.structGet(ctl, "Mode", ""))));
totalSlots = double(sixgr.util.structGet(ctl, "TotalSlots", NaN));
if contains(mode, "webgui") && isfinite(totalSlots) && totalSlots >= 100
    tf = false;
end
end

function localWriteCoupledProfileSnapshot(rootRunFolder, state, ctl, absoluteSlot, elapsed_s)
if strlength(string(rootRunFolder)) == 0
    return;
end
snapDir = fullfile(char(string(rootRunFolder)), "profile_snapshots");
sixgr.util.ensureFolder(snapDir);
slotToken = sprintf("slot_%06d", round(double(absoluteSlot)));
profileInfo = struct();
try
    profileInfo = profile("info");
catch
end
save(fullfile(snapDir, "profile_snapshot_" + string(slotToken) + ".mat"), "profileInfo");
profileT = sixgr.monitor.ProfileExporter.functionTable(profileInfo);
sixgr.util.csvWriteTable(fullfile(snapDir, "profile_snapshot_" + string(slotToken) + ".csv"), profileT);
summary = struct( ...
    "mode", string(sixgr.util.structGet(ctl, "Mode", "")), ...
    "slot", double(absoluteSlot), ...
    "elapsed_s", double(elapsed_s), ...
    "access_state", strjoin(string(sixgr.util.structGet(state, "AccessState", strings(0,1))).', ","), ...
    "scheduling_eligible", strjoin(string(logical(sixgr.util.structGet(state, "SchedulingEligibility", false(0,1)))).', ","), ...
    "profile_function_rows", height(profileT));
sixgr.util.jsonWrite(fullfile(snapDir, "profile_snapshot_" + string(slotToken) + ".json"), summary);
end

function [tf, reason] = localShouldStopCoupledProfile(state, ctl, absoluteSlot, dlTrials, ulTrials)
tf = false;
reason = "";
if ~(isstruct(ctl) && logical(sixgr.util.structGet(ctl, "Enabled", false)))
    return;
end
elapsed = toc(ctl.StartTic);
guard_s = double(sixgr.util.structGet(ctl, "InternalWallClockGuardSeconds", Inf));
if isfinite(guard_s) && guard_s > 0 && elapsed >= guard_s
    tf = true;
    reason = "internal_wall_clock_guard_seconds_elapsed";
    return;
end
accessState = string(sixgr.util.structGet(state, "AccessState", strings(0,1)));
if logical(sixgr.util.structGet(ctl, "StopAfterAccessComplete", false)) && ...
        ~isempty(accessState) && all(accessState == "succeeded")
    tf = true;
    reason = "all_ues_access_succeeded";
    return;
end
dlRows = height(dlTrials);
ulRows = height(ulTrials);
if logical(sixgr.util.structGet(ctl, "StopAfterFirstExecutableDataGrant", false)) && (dlRows + ulRows) >= 1
    tf = true;
    reason = "first_executable_data_grant_observed";
    return;
end
nDL = double(sixgr.util.structGet(ctl, "StopAfterFirstNPDSCHGrants", Inf));
if isfinite(nDL) && nDL >= 1 && dlRows >= nDL
    tf = true;
    reason = "requested_pdsch_grant_count_observed";
    return;
end
nUL = double(sixgr.util.structGet(ctl, "StopAfterFirstNPUSCHGrants", Inf));
if isfinite(nUL) && nUL >= 1 && ulRows >= nUL
    tf = true;
    reason = "requested_pusch_grant_count_observed";
    return;
end
if isfinite(double(sixgr.util.structGet(ctl, "TotalSlots", NaN))) && ...
        double(absoluteSlot) >= double(sixgr.util.structGet(ctl, "TotalSlots", Inf))
    reason = "profiled_slot_budget_completed";
end
end

function artifacts = localBuildMobilityArtifactsFromCoupledRuntime(state)
artifacts = sixgr.truth.CoupledTruthRuntime.mobilityArtifacts(state);
end

function trialCache = localPrecomputePBCHControlGatingTrials(state, cfg, userCfg, pbchEligible, slotIdx, frameIdx, snr_dB, slotDLAllowed)
numUsers = numel(userCfg);
trialCache = cell(numUsers, 1);
if ~logical(slotDLAllowed) || numUsers < 1
    return;
end
% A causal fading timeline is mutable per link.  Parallel precomputation
% would fork and discard its channel state, so runtime-channel PBCH must be
% executed serially through the canonical state below.
if sixgr.channel.ChannelFactory.requiresRuntimeChannelState(cfg)
    return;
end
eligible = false(numUsers, 1);
if islogical(pbchEligible) || isnumeric(pbchEligible)
    eligible(1:min(numUsers, numel(pbchEligible))) = logical(pbchEligible(1:min(numUsers, numel(pbchEligible))));
end
if ~any(eligible)
    return;
end
eligibleCount = round(double(sum(eligible)));
minPlans = localCoupledParallelMinimumPlanCount(cfg, max(1, round(double(sixgr.util.structGet(cfg, "run.numWorkers", 1)))));
if eligibleCount < minPlans
    return;
end
if ~(logical(sixgr.util.structGet(cfg, "run.useParallel", false)) && ...
        double(sixgr.util.structGet(cfg, "run.numWorkers", 0)) > 1 && ...
        localEnsureCoupledParallelPool(cfg, "control_gating_pbch"))
    return;
end
try
    stateWorker = localCompactCoupledRuntimeStateForWorkerTransfer(state);
    userCfgWorker = localSanitizeCoupledUserCfgForWorkerTransfer(userCfg);
    localAppendRuntimeLog("INFO", ...
        "Preparing coupled PBCH control gating trials in parfor: eligible_ues=%d.", ...
        eligibleCount);
    parfor ueIdx = 1:numUsers
        if eligible(ueIdx)
            servingCells = double(sixgr.util.structGet( ...
                stateWorker, "CurrentServingIdx", nan(numUsers, 1)));
            servingCell = NaN;
            if numel(servingCells) >= ueIdx
                servingCell = double(servingCells(ueIdx));
            end
            cfgU = userCfgWorker{ueIdx};
            tempState = stateWorker;
            [cfgU, tempState] = sixgr.truth.GrantPreparation.applyCoupledRuntimeUserContext(cfgU, tempState, ueIdx, "DL"); %#ok<ASGLU>
            rnti=sixgr.truth.CoupledRadioIdentity.dataRNTI(cfgU,ueIdx,"DL");
            cfgU = localApplyPBCHSSBBeamContext(cfgU, slotIdx, ueIdx);
            [pbchTrial, ~, decodedSIB1] = localCollectPBCHTrials( ...
                cfgU, double(snr_dB), 1);
            trialCache{ueIdx} = struct( ...
                "Trial", localAnnotateCoupledControlTrial(pbchTrial, ...
                slotIdx, frameIdx, ueIdx, rnti, "DL", servingCell), ...
                "DecodedSIB1", decodedSIB1);
        end
    end
catch ME
    trialCache = cell(numUsers, 1);
    localAppendRuntimeLog("WARN", ...
        "Coupled PBCH control gating parfor precompute unavailable; falling back to serial PBCH trials: %s %s", ...
        char(string(ME.identifier)), char(string(ME.message)));
end
end

function [state, pendingULGrants] = localRunCoupledPreSchedulingControlGating( ...
        state, cfg, runFolder, userCfg, snr_dB, pendingULGrants)
if nargin < 6 || ~isstruct(pendingULGrants)
    pendingULGrants = repmat(struct(), 0, 1);
end
state = localDeliverCoupledBroadcastResults(state);
state = sixgr.truth.SIB1ResultDelivery.deliver(state);
state = localDeliverCoupledTRSResults(state);
state = localDeliverSharedSRSResults(state);
state = sixgr.truth.CoupledTruthRuntime.refreshControlState(state);
numUsers = numel(userCfg);
slotIdx = double(sixgr.util.structGet(state, "CurrentSlot", NaN));
frameIdx = double(sixgr.util.structGet(state, "CurrentFrame", NaN));
slotDLAllowed = logical(sixgr.util.structGet(state, "CurrentSlotDLAllowed", true)) && ...
    double(sixgr.util.structGet(state, "CurrentSlotDLNumSymbols", 0)) > 0;
slotULAllowed = logical(sixgr.util.structGet(state, "CurrentSlotULAllowed", true)) && ...
    double(sixgr.util.structGet(state, "CurrentSlotULNumSymbols", 0)) > 0;
srsMaxUEsPerSlot = max(1, round(double(sixgr.util.structGet(cfg, "phy.srs.maxUEsPerSlot", 1))));
trsEnabled = logical(sixgr.util.structGet(cfg, "phy.trs.enable", false));
prachRequired = logical(sixgr.util.structGet(state.ControlGating, "PRACHRequired", false));
prachEnabled = logical(sixgr.util.structGet(cfg, "phy.prach.enable", false));
shouldAttemptTRS = false;
if trsEnabled && slotDLAllowed
    trsWindow = sixgr.truth.resolveTRSObservationWindow(cfg,slotIdx);
    % The producer includes every authored resource in this multi-slot
    % observation. Do not retransmit that complete window at each member.
    shouldAttemptTRS = trsWindow.ObservationStarts;
end
    sharedWaveformRA = isfield(state,'SharedWaveformStream');
    if sharedWaveformRA
        % Enqueue the complete canonical PRACH OFDM buffer one carrier slot
        % before its nominal origin. Received SSB phase/common UL timing can
        % advance the actual UE TX origin slightly across that boundary.
        % This is a scheduling horizon only; IQ remains on its exact clock.
        prachSignalOpportunityThisSlot = prachEnabled && ...
            sixgr.truth.isPRACHWaveformPreparationSlot(cfg,slotIdx);
    else
        prachSignalOpportunityThisSlot = prachEnabled && slotULAllowed && ...
            sixgr.truth.isActivePRACHOccasion(cfg, slotIdx);
    end
prachOccasionActiveThisSlot = prachRequired && prachSignalOpportunityThisSlot;
[ssbOccasionActiveThisSlot, ssbOccasion] = ...
    sixgr.truth.isActiveSSBOccasion(cfg, slotIdx);
sharedPBCHEligible = false(numUsers, 1);
cellBroadcastBursts=struct('ServingCell',{},'ComponentID',{},'AbsoluteSlot',{}, ...
    'StartSample',{},'EndSampleExclusive',{});
if isfield(state,'SharedWaveformStream')
    % The cell transmits independently of acquisition, traffic, and UE RX
    % eligibility. SI is a separate original producer, not a copy hidden in
    % every per-UE SS/PBCH capture.
    [cellBroadcastBursts,~]=state.SharedWaveformStream.queueDueCellBroadcasts(slotIdx-1);
    sixgr.truth.armReceivedMIBSIForSlot(state);
end
pbchAcquisitionRequired = logical(sixgr.util.structGet( ...
    state.ControlGating, "PBCHRequired", false));
ssbTrackingPolicy = sixgr.truth.resolveServingSSBTrackingPolicy(cfg);
servingSSBMeasurementRequired = ssbTrackingPolicy.Required;
ssbWaveformObservationRequired = ...
    pbchAcquisitionRequired || servingSSBMeasurementRequired;
if isfield(state,'SharedWaveformStream')
    ssbObservationDue=~isempty(cellBroadcastBursts);
else
    ssbObservationDue=slotDLAllowed && ssbOccasionActiveThisSlot;
end
if ssbWaveformObservationRequired && ssbObservationDue
    pbchStateAll = string(sixgr.util.structGet(state, "CellAcquisitionState", strings(numUsers, 1)));
    % Initial acquisition and post-acquisition serving-beam/pathloss
    % tracking use the same real SS/PBCH waveform producer.  Acquisition
    % state is advanced only for unresolved UEs below; acquired UEs commit
    % the periodic SSS power measurement without replaying the RA state.
    sharedPBCHEligible = ...
        (pbchAcquisitionRequired & pbchStateAll ~= "acquired") | ...
        servingSSBMeasurementRequired;
end
if isfield(state,'SharedWaveformStream')
    % Observe a complete burst only when its cell actually queued the
    % original burst. Individual later SSB candidate slots are not new TXs.
    for ue=1:numUsers
        sharedPBCHEligible(ue)=sharedPBCHEligible(ue) && ...
            any([cellBroadcastBursts.ServingCell]==state.CurrentServingIdx(ue));
    end
end
trsObservedServingCells = [];
for pendingUE = 1:numUsers
    if sixgr.truth.BroadcastResultDelivery.hasPending(state,pendingUE) || ...
            (isfield(state,'SharedWaveformStream') && ...
            state.SharedWaveformStream.hasPending("PBCH",pendingUE))
        sharedPBCHEligible(pendingUE)=false;
    end
end
pbchAttemptCount = 0;
prachAttemptCount = 0;
srsAttemptCount = 0;
trsAttemptCount = 0;
srsScheduledThisSlot = 0;
heartbeatIntervalUEs = localResolveCoupledControlHeartbeatInterval(cfg, numUsers);
localPublishCoupledControlGatingStatus(runFolder, state, struct( ...
    "CurrentUEIndex", 0, ...
    "TotalUsers", numUsers, ...
    "PBCHAttemptCount", pbchAttemptCount, ...
    "PRACHAttemptCount", prachAttemptCount, ...
    "SRSAttemptCount", srsAttemptCount, ...
    "TRSAttemptCount", trsAttemptCount, ...
    "SSBOccasionActive", ssbOccasionActiveThisSlot, ...
    "ActiveSSBIndices0Based", localNumericVectorToken(sixgr.util.structGet(ssbOccasion, "ActiveSSBIndices0Based", [])), ...
    "SSBPeriodCarrierSlots", double(sixgr.util.structGet(ssbOccasion, "PeriodCarrierSlots", NaN)), ...
    "Phase", "starting", ...
    "Notes", sprintf("Starting coupled pre-scheduling control gating for slot %s/%s with %d UEs.", ...
        localDisplayProgressValue(slotIdx), localDisplayProgressValue(double(sixgr.util.structGet(state, "CanonicalSlotsPerSweepPoint", NaN))), round(double(numUsers)))));
pbchTrialCache = localPrecomputePBCHControlGatingTrials(state, cfg, userCfg, sharedPBCHEligible, slotIdx, frameIdx, snr_dB, slotDLAllowed);
for ueIdx = 1:numUsers
    cfgU = userCfg{ueIdx};
    tempState = state;
    [cfgU, tempState] = sixgr.truth.GrantPreparation.applyCoupledRuntimeUserContext(cfgU, tempState, ueIdx, "DL"); %#ok<ASGLU>
    rnti=sixgr.truth.CoupledRadioIdentity.dataRNTI(cfgU,ueIdx,"DL");
    servingCell = double(sixgr.util.structGet(tempState, "CurrentServingIdx", nan(numUsers, 1)));
    if numel(servingCell) >= ueIdx
        servingCell = double(servingCell(ueIdx));
    else
        servingCell = NaN;
    end

    % Resume prior RA attempts before this slot's control/data consumers.
    % Msg2/Msg4 are DL stages and must not wait for another PRACH occasion.
    hadPendingRA = localHasPendingRA(state, ueIdx);
    if hadPendingRA
        [state, raRawT, raCorrT, raEvidenceT] = localCollectCoupledPRACHTrials( ...
            state, cfgU, ueIdx, snr_dB, slotIdx);
        raT = localAnnotateCoupledControlTrial(raRawT, slotIdx, frameIdx, ...
            ueIdx, rnti, "UL", servingCell);
        state.ControlTrials.PRACH = localAppendCompatTable(state.ControlTrials.PRACH, raT);
        state.ControlTrials.PRACHCorrelationTrace = localAppendCompatTable( ...
            sixgr.util.structGet(state.ControlTrials, "PRACHCorrelationTrace", table()), raCorrT);
        state.ControlTrials.RAEvidenceTables = localAppendRAEvidenceTables( ...
            sixgr.util.structGet(state.ControlTrials, "RAEvidenceTables", struct()), raEvidenceT);
        if ~isempty(raT)
            state = sixgr.truth.CoupledTruthRuntime.applyPRACHTrial(state, ueIdx, raT);
        end
        % A completed access procedure may install a new radio identity.
        % Bind subsequent producers before freezing this slot's contexts;
        % do not mutate any already queued operation or received RA row.
        [cfgU,state]=sixgr.truth.GrantPreparation.applyCoupledRuntimeUserContext(userCfg{ueIdx},state,ueIdx,"DL");
        rnti=sixgr.truth.CoupledRadioIdentity.dataRNTI(cfgU,ueIdx,"DL");
        servingCell=double(state.CurrentServingIdx(ueIdx));
    end

    [state,~,~,~]=sixgr.truth.queueSharedPeriodicCSIRS( ...
        state,cfgU,ueIdx,slotIdx,frameIdx,rnti,servingCell,snr_dB);

    if shouldAttemptTRS && isfinite(servingCell) && servingCell >= 1 && ...
            (isfield(state,'SharedWaveformStream') || ~ismember(servingCell, trsObservedServingCells))
        trsSNR_dB = sixgr.truth.resolveWaveformOperatingPointMetadata(cfgU, snr_dB);
        if isfield(state,'SharedWaveformStream')
            prepared=sixgr.link.prepareTRSTransmission(cfgU,trsSNR_dB,'RuntimeSlot',slotIdx);
            context=struct('Config',cfgU,'Slot',slotIdx,'Frame',frameIdx, ...
                'RNTI',rnti,'ServingCell',servingCell,'SNR',trsSNR_dB);
            state.SharedWaveformStream.queueDownlink("TRS",ueIdx,prepared,context);
            trsAttemptCount=trsAttemptCount+1;
        else
        [state,trsChannelState] = ...
            sixgr.truth.CoupledTruthRuntime.acquireRuntimeChannelStateForControl( ...
            state,cfgU,ueIdx,"DL");
        [trsRawT,trsUpdatedChannelState,trsObservedRET] = localCollectTRSTrials( ...
            cfgU,trsSNR_dB,1,trsChannelState);
        state = sixgr.truth.CoupledTruthRuntime.commitRuntimeChannelState( ...
            state,trsUpdatedChannelState);
        trsT = localAnnotateCoupledControlTrial(trsRawT, ...
            slotIdx,frameIdx,ueIdx,rnti,"DL",servingCell);
        if istable(trsT) && ~isempty(trsT)
            trsAttemptCount = trsAttemptCount + 1;
            if all(isfinite(trsT.ObservationEndSampleExclusive))
                state = sixgr.truth.TRSResultDelivery.enqueue( ...
                    state,servingCell,ueIdx,trsT,cfgU,trsObservedRET);
            else
                if ~all(trsT.Crash == 1)
                    error("sixgr:truth:MissingTRSObservationClock", ...
                        "A received TRS trial cannot bypass its actual sample-window delivery boundary.");
                end
                % Preserve the real exception, not a fabricated observation.
                state = localCommitCoupledTRSTrial(state,trsT,servingCell,cfgU,ueIdx,trsObservedRET);
            end
            trsObservedServingCells(end + 1, 1) = servingCell; %#ok<AGROW>
        end
        end
    end

    if ssbWaveformObservationRequired && ssbObservationDue
        shouldAttemptPBCH = ueIdx <= numel(sharedPBCHEligible) && sharedPBCHEligible(ueIdx);
        if shouldAttemptPBCH
            priorPBCHState = string(sixgr.util.structGet( ...
                state,"CellAcquisitionState",strings(numUsers,1)));
            wasAcquired = ueIdx <= numel(priorPBCHState) && ...
                priorPBCHState(ueIdx) == "acquired";
            measurementOnly = servingSSBMeasurementRequired && ~pbchAcquisitionRequired;
            if isfield(state,'SharedWaveformStream')
                pbchSNR_dB=sixgr.truth.resolveWaveformOperatingPointMetadata(cfgU,snr_dB);
                context=struct('Config',cfgU,'Slot',slotIdx,'Frame',frameIdx, ...
                    'RNTI',rnti,'ServingCell',servingCell,'SNR',pbchSNR_dB, ...
                    'TrackingOnly',logical(wasAcquired || measurementOnly));
                context.AcquisitionMIBBinding=[];
                if wasAcquired
                    [currentMIB,~,acquisitionMIB]=sixgr.truth.ReceivedMIBDelivery.current(state,ueIdx);
                    if currentMIB, context.AcquisitionMIBBinding=acquisitionMIB; end
                end
                state.SharedWaveformStream.armCellSSBObservation(ueIdx,context);
                pbchAttemptCount=pbchAttemptCount+1;
            else
            pbchT = table();
            decodedSIB1 = struct();
            if ueIdx <= numel(pbchTrialCache) && isstruct(pbchTrialCache{ueIdx}) && ...
                    isfield(pbchTrialCache{ueIdx}, "Trial") && ...
                    istable(pbchTrialCache{ueIdx}.Trial) && ...
                    ~isempty(pbchTrialCache{ueIdx}.Trial)
                pbchT = pbchTrialCache{ueIdx}.Trial;
                decodedSIB1 = sixgr.util.structGet( ...
                    pbchTrialCache{ueIdx}, "DecodedSIB1", struct());
            end
            if isempty(pbchT)
                pbchSNR_dB = sixgr.truth.resolveWaveformOperatingPointMetadata(cfgU, snr_dB);
                cfgU = localApplyPBCHSSBBeamContext(cfgU, slotIdx, ueIdx);
                [state, pbchRawT, decodedSIB1] = localCollectCoupledPBCHTrials( ...
                    state, cfgU, ueIdx, pbchSNR_dB, slotIdx);
                pbchT = localAnnotateCoupledControlTrial( ...
                    pbchRawT, slotIdx, frameIdx, ueIdx, rnti, "DL", servingCell);
            end
            measurementOnly = servingSSBMeasurementRequired && ...
                ~pbchAcquisitionRequired;
            if wasAcquired
                pbchT.ObservationPurpose = repmat( ...
                    "periodic_serving_ssb_beam_and_pathloss_tracking", ...
                    height(pbchT),1);
            elseif measurementOnly
                pbchT.ObservationPurpose = repmat( ...
                    "connected_mode_serving_ssb_pathloss_measurement", ...
                    height(pbchT),1);
            else
                pbchT.ObservationPurpose = repmat( ...
                    "initial_cell_search_pbch_acquisition",height(pbchT),1);
            end
            pbchAttemptCount = pbchAttemptCount + 1;
            state = sixgr.truth.BroadcastResultDelivery.enqueue( ...
                state,ueIdx,pbchT,decodedSIB1,logical(wasAcquired || measurementOnly));
            end
        end
    end

    if prachSignalOpportunityThisSlot && ~hadPendingRA
        pbchState = string(sixgr.util.structGet(state, "CellAcquisitionState", strings(numUsers,1)));
        accessState = string(sixgr.util.structGet(state, "AccessState", strings(numUsers,1)));
        lastPrachAttempt = double(sixgr.util.structGet(state, "LastPRACHSlotByUE", zeros(numUsers,1)));
        lastSuccessfulPBCH = double(sixgr.util.structGet(state, "LastSuccessfulPBCHSlotByUE", nan(numUsers,1)));
        if prachRequired
            shouldAttemptPRACH = ueIdx > numel(accessState) || accessState(ueIdx) ~= "succeeded";
            pbchAcquired = ueIdx <= numel(pbchState) && pbchState(ueIdx) == "acquired";
            if shouldAttemptPRACH
                lastAttempt = 0;
                if ueIdx <= numel(lastPrachAttempt)
                    lastAttempt = double(lastPrachAttempt(ueIdx));
                end
                shouldAttemptPRACH = ~isfinite(lastAttempt) || slotIdx > lastAttempt;
            end
            lastPbchSuccess = NaN;
            if ueIdx <= numel(lastSuccessfulPBCH)
                lastPbchSuccess = double(lastSuccessfulPBCH(ueIdx));
            end
            % PBCH is delivered before this slot's scheduling boundary.
            % Its delivery slot is already usable; adding another whole
            % slot here would introduce an unconfigured processing delay.
            shouldAttemptPRACH = shouldAttemptPRACH && pbchAcquired && isfinite(lastPbchSuccess) && slotIdx >= lastPbchSuccess;
            shouldAttemptPRACH = shouldAttemptPRACH && prachOccasionActiveThisSlot;
        else
            lastAttempt = 0;
            if ueIdx <= numel(lastPrachAttempt)
                lastAttempt = double(lastPrachAttempt(ueIdx));
            end
            shouldAttemptPRACH = ~isfinite(lastAttempt) || lastAttempt <= 0;
        end
        if shouldAttemptPRACH && isfield(state,'SharedWaveformStream') && ...
                isfield(state,'RARetryByUE') && numel(state.RARetryByUE)>=ueIdx && ...
                ~isempty(state.RARetryByUE{ueIdx})
            shouldAttemptPRACH=state.RARetryByUE{ueIdx}.canStart(localSharedNowTicks(state));
        end
        if shouldAttemptPRACH
            [cfgU, tempState] = sixgr.truth.GrantPreparation.applyCoupledRuntimeUserContext(cfgU, tempState, ueIdx, "UL"); %#ok<ASGLU>
            cfgU = localApplyDeterministicPrachUserContext(cfgU, ueIdx);
            if isfield(state,'SharedWaveformStream')
                cfgU=localApplyMeasuredSSBSelectionForRA(cfgU,state,ueIdx);
                [cfgU,referenceDecision]=sixgr.truth.bindSharedRAPowerReference(cfgU,state,ueIdx,slotIdx);
                state.ControlTrials.RAEvidenceTables=localAppendRAEvidenceTables( ...
                    state.ControlTrials.RAEvidenceTables,struct('ra_power_reference_decisions',referenceDecision));
                shouldAttemptPRACH=referenceDecision.ReferenceUsable;
                if ~shouldAttemptPRACH
                    localAppendRuntimeLog("INFO", ...
                        "PRACH deferred: ue=%d slot=%d selected_ssb=%d reason=%s minimum_age_slots=%g maximum_age_slots=%g; no model pathloss substitution.", ...
                        ueIdx,slotIdx,referenceDecision.SelectedSSBIndex,referenceDecision.Blocker, ...
                        referenceDecision.MinimumAvailableAgeSlots,referenceDecision.MaximumAgeSlots);
                end
            end
        end
        if shouldAttemptPRACH
            prachSNR_dB = sixgr.truth.resolveWaveformOperatingPointMetadata(cfgU, snr_dB);
            [state, prachRawT, prachCorrT, prachRAEvidenceT] = ...
                localCollectCoupledPRACHTrials( ...
                state, cfgU, ueIdx, prachSNR_dB, slotIdx);
            prachT = localAnnotateCoupledControlTrial(prachRawT, slotIdx, frameIdx, ueIdx, rnti, "UL", servingCell);
            if istable(prachT) && ~isempty(prachT)
                prachRow = prachT(end, :);
                localAppendRuntimeLog("INFO", ...
                    "Coupled PRACH result: slot=%s ue=%d status=%s crc=%s ra_completed=%s strict_ok=%s tx_preamble=%s detected_preamble=%s failure=%s.", ...
                    localDisplayProgressValue(slotIdx), round(double(ueIdx)), ...
                    localTrialTableString(prachRow, "Status", ""), ...
                    localDisplayProgressValue(localTrialTableScalar(prachRow, "CRCPass", NaN)), ...
                    char(string(localTrialTableLogical(prachRow, "RACompleted", false))), ...
                    char(string(localTrialTableLogical(prachRow, "StrictOk", false))), ...
                    localDisplayProgressValue(localTrialTableFirstFinite(prachRow, ["PreambleIndexTx","RequestedPreambleIndex","PreambleIndex"], NaN)), ...
                    localDisplayProgressValue(localTrialTableFirstFinite(prachRow, ["PreambleIndexDetected","DetectedPreambleIndex"], NaN)), ...
                    localTrialTableString(prachRow, "FailureReason", ""));
                localAppendRuntimeLog("INFO", ...
                    "Coupled PRACH RA PDSCH evidence: slot=%s ue=%d msg2_crc=%s msg2_layers=%s msg2_cfg_ports=%s msg2_resolved_ports=%s msg2_explicit_matrix=%s msg2_precoding=%s/%s msg2_tx_power_dBm=%s msg2_amp_scale=%s msg2_timing_used=%s msg2_timing=%s msg2_posteq_sinr_dB=%s msg2_hest_sinr_dB=%s msg2_llr_finite=%s msg4_crc=%s msg4_layers=%s msg4_cfg_ports=%s msg4_resolved_ports=%s msg4_tx_power_dBm=%s msg4_amp_scale=%s.", ...
                    localDisplayProgressValue(slotIdx), round(double(ueIdx)), ...
                    localDisplayProgressValue(localTrialTableScalar(prachRow, "Msg2PDSCHCrcPass", NaN)), ...
                    localDisplayProgressValue(localTrialTableScalar(prachRow, "Msg2PDSCHNumLayers", NaN)), ...
                    localDisplayProgressValue(localTrialTableScalar(prachRow, "Msg2PDSCHConfiguredNumPorts", NaN)), ...
                    localDisplayProgressValue(localTrialTableScalar(prachRow, "Msg2PDSCHResolvedNumPorts", NaN)), ...
                    char(string(localTrialTableLogical(prachRow, "Msg2PDSCHExplicitMatrixPresent", false))), ...
                    localTrialTableString(prachRow, "Msg2PDSCHPrecodingMode", ""), ...
                    localTrialTableString(prachRow, "Msg2PDSCHPrecodingSource", ""), ...
                    localDisplayProgressValue(localTrialTableScalar(prachRow, "Msg2TxPower_dBm", NaN)), ...
                    localDisplayProgressValue(localTrialTableScalar(prachRow, "Msg2TxAmplitudeScale", NaN)), ...
                    char(string(localTrialTableLogical(prachRow, "Msg2TimingEstimateUsed", false))), ...
                    localDisplayProgressValue(localTrialTableScalar(prachRow, "Msg2AppliedTimingCorrection_samples", NaN)), ...
                    localDisplayProgressValue(localTrialTableScalar(prachRow, "Msg2PostEqSINR_dB", NaN)), ...
                    localDisplayProgressValue(localTrialTableScalar(prachRow, "Msg2ReceiverHestSINR_dB", NaN)), ...
                    char(string(localTrialTableLogical(prachRow, "Msg2LLRFinite", false))), ...
                    localDisplayProgressValue(localTrialTableScalar(prachRow, "Msg4PDSCHCrcPass", NaN)), ...
                    localDisplayProgressValue(localTrialTableScalar(prachRow, "Msg4PDSCHNumLayers", NaN)), ...
                    localDisplayProgressValue(localTrialTableScalar(prachRow, "Msg4PDSCHConfiguredNumPorts", NaN)), ...
                    localDisplayProgressValue(localTrialTableScalar(prachRow, "Msg4PDSCHResolvedNumPorts", NaN)), ...
                    localDisplayProgressValue(localTrialTableScalar(prachRow, "Msg4TxPower_dBm", NaN)), ...
                    localDisplayProgressValue(localTrialTableScalar(prachRow, "Msg4TxAmplitudeScale", NaN)));
            end
            prachCorrT = localAnnotateCoupledControlTrial(prachCorrT, slotIdx, frameIdx, ueIdx, rnti, "UL", servingCell);
            prachAttemptCount = prachAttemptCount + 1;
            state.ControlTrials.PRACH = localAppendCompatTable(state.ControlTrials.PRACH, prachT);
            state.ControlTrials.PRACHCorrelationTrace = localAppendCompatTable( ...
                sixgr.util.structGet(state.ControlTrials, "PRACHCorrelationTrace", table()), prachCorrT);
            state.ControlTrials.RAEvidenceTables = localAppendRAEvidenceTables( ...
                sixgr.util.structGet(state.ControlTrials, "RAEvidenceTables", struct()), prachRAEvidenceT);
            state = sixgr.truth.CoupledTruthRuntime.applyPRACHTrial(state, ueIdx, prachT);
            if ueIdx > numel(state.LastPRACHSlotByUE)
                state.LastPRACHSlotByUE(ueIdx, 1) = 0;
            end
            state.LastPRACHSlotByUE(ueIdx) = slotIdx;
        end
    end

    srsEnabled = logical(sixgr.util.structGet(cfgU, "phy.srs.enable", ...
        sixgr.util.structGet(cfg, "phy.srs.enable", false)));
    if srsEnabled && isfield(state,'SharedWaveformStream')
        [state, pendingULGrants, queued] = localPrepareSharedSRS( ...
            state,cfgU,ueIdx,snr_dB,pendingULGrants);
        srsAttemptCount=srsAttemptCount+double(queued);
    elseif srsEnabled && slotULAllowed
        shouldAttemptSRS = sixgr.truth.coupledSRSAttemptDue(state,cfgU,slotIdx,ueIdx) && ...
            srsScheduledThisSlot < srsMaxUEsPerSlot;
        if shouldAttemptSRS
            [cfgSRSU, tempState] = sixgr.truth.GrantPreparation.applyCoupledRuntimeUserContext(cfgU, tempState, ueIdx, "UL"); %#ok<ASGLU>
            [srsPuschCollision, srsResourceDecisionT] = ...
                localResolveCoupledSRSPUSCHResourceDecision( ...
                cfgSRSU, pendingULGrants, ...
                sixgr.util.structGet(state, ...
                "PUCCHExecutedCurrentSlotGrantSnapshot", table()), ...
                slotIdx, ueIdx);
            if srsPuschCollision
                [state, pendingULGrants, srsResourceDecisionT, ...
                    srsPuschCollision, cancelledPUSCHCount] = ...
                    sixgr.truth.resolveSRSPUSCHRuntimePriority( ...
                    state, pendingULGrants, srsResourceDecisionT, ...
                    cfgSRSU, slotIdx, ueIdx);
                if cancelledPUSCHCount > 0
                    localAppendRuntimeLog("INFO", ...
                        "Cancelled exact queued PUSCH grants for first required SRS measurement: slot=%d srs_ue=%d cancelled_grants=%d policy=%s.", ...
                        round(double(slotIdx)), round(double(ueIdx)), ...
                        round(double(cancelledPUSCHCount)), ...
                        char(string(sixgr.util.structGet(cfgSRSU, ...
                        "phy.srs.puschCollisionPolicy", ""))));
                end
            end
            if istable(srsResourceDecisionT) && ~isempty(srsResourceDecisionT)
                state.ControlTrials.SRSResourceDecisions = ...
                    localAppendCompatTable(sixgr.util.structGet( ...
                    state.ControlTrials, "SRSResourceDecisions", table()), ...
                    srsResourceDecisionT);
            end
            if srsPuschCollision
                localAppendRuntimeLog("INFO", ...
                    "Deferred colliding SRS occasion after causal policy resolution: slot=%d ue=%d overlap_re=%d action=%s duplex=%s.", ...
                    round(double(slotIdx)), round(double(ueIdx)), ...
                    round(double(srsResourceDecisionT.OverlapRECount(end))), ...
                    char(string(srsResourceDecisionT.Action(end))), ...
                    char(string(srsResourceDecisionT.DuplexMode(end))));
                continue;
            end
            srsSNR_dB = sixgr.truth.resolveWaveformOperatingPointMetadata(cfgSRSU, snr_dB);
            [state, srsRawT] = localCollectCoupledSRSTrials( ...
                state, cfgSRSU, ueIdx, srsSNR_dB, slotIdx);
            srsT = localAnnotateCoupledControlTrial(srsRawT, slotIdx, frameIdx, ueIdx, rnti, "UL", servingCell);
            srsAttemptCount = srsAttemptCount + 1;
            srsScheduledThisSlot = srsScheduledThisSlot + 1;
            state = sixgr.truth.CoupledTruthRuntime.applySRSTrial(state, ueIdx, srsT);
            srsT = localAnnotateSRSDecisionCausality(srsT, state, ueIdx);
            state.ControlTrials.SRS = localAppendCompatTable(state.ControlTrials.SRS, srsT);
            if ueIdx > numel(state.LastSRSSlotByUE)
                state.LastSRSSlotByUE(ueIdx, 1) = 0;
            end
            state.LastSRSSlotByUE(ueIdx) = slotIdx;
        end
    end
    if ueIdx == 1 || ueIdx == numUsers || mod(ueIdx, heartbeatIntervalUEs) == 0
        localPublishCoupledControlGatingStatus(runFolder, state, struct( ...
            "CurrentUEIndex", ueIdx, ...
            "TotalUsers", numUsers, ...
            "PBCHAttemptCount", pbchAttemptCount, ...
            "PRACHAttemptCount", prachAttemptCount, ...
            "SRSAttemptCount", srsAttemptCount, ...
            "TRSAttemptCount", trsAttemptCount, ...
            "SSBOccasionActive", ssbOccasionActiveThisSlot, ...
            "ActiveSSBIndices0Based", localNumericVectorToken(sixgr.util.structGet(ssbOccasion, "ActiveSSBIndices0Based", [])), ...
            "SSBPeriodCarrierSlots", double(sixgr.util.structGet(ssbOccasion, "PeriodCarrierSlots", NaN)), ...
            "Phase", "streaming", ...
            "Notes", sprintf("Coupled control gating progress for slot %s/%s: UE %d/%d, PBCH=%d PRACH=%d SRS=%d TRS=%d.", ...
                localDisplayProgressValue(slotIdx), localDisplayProgressValue(double(sixgr.util.structGet(state, "CanonicalSlotsPerSweepPoint", NaN))), ...
                round(double(ueIdx)), round(double(numUsers)), round(double(pbchAttemptCount)), round(double(prachAttemptCount)), ...
                round(double(srsAttemptCount)), round(double(trsAttemptCount)))));
    end
end
if shouldAttemptTRS && ~isempty(trsObservedServingCells)
    state.LastTRSSlot = slotIdx;
end
state = sixgr.truth.CoupledTruthRuntime.refreshControlState(state);
pbchAcquiredCount = localCountSatisfiedControlUsers( ...
    string(sixgr.util.structGet(state, "CellAcquisitionState", strings(numUsers, 1))), ...
    "acquired", logical(sixgr.util.structGet(state.ControlGating, "PBCHRequired", false)));
accessReadyCount = localCountSatisfiedControlUsers( ...
    string(sixgr.util.structGet(state, "AccessState", strings(numUsers, 1))), ...
    "succeeded", logical(sixgr.util.structGet(state.ControlGating, "PRACHRequired", false)));
srsValidCount = sum(string(sixgr.util.structGet(state, "SRSValidityState", strings(numUsers, 1))) == "valid");
% Count cells with at least one measured eligible receiver, not a shared
% cell estimate falsely applied to every UE.
trackingEligibilityByCell=false(numel(state.TRSValidityStateByCell),1);
trackedServingUserCount = 0;
servingVec = double(sixgr.util.structGet(state, "CurrentServingIdx", nan(numUsers, 1)));
for ueIdx = 1:numUsers
    if ueIdx <= numel(servingVec)
        servingCell = round(double(servingVec(ueIdx)));
        if isfinite(servingCell) && servingCell >= 1 && servingCell <= numel(trackingEligibilityByCell)
            receiver=sixgr.truth.CoupledTruthRuntime.resolveTRSRuntimeContextRuntime(state,cfg,ueIdx,servingCell);
            if receiver.TrackingEligibility
                trackedServingUserCount = trackedServingUserCount + 1;
                trackingEligibilityByCell(servingCell)=true;
            end
        end
    end
end
trsValidCellCount=sum(trackingEligibilityByCell);
localAppendRuntimeLog("INFO", ...
    "Coupled control gating complete: slot=%d frame=%d pbch_attempts=%d prach_attempts=%d srs_attempts=%d trs_attempts=%d acquired=%d/%d access=%d/%d valid_srs=%d/%d valid_trs_cells=%d/%d tracked_serving_users=%d/%d eligible=%d/%d.", ...
    round(double(slotIdx)), round(double(frameIdx)), round(double(pbchAttemptCount)), round(double(prachAttemptCount)), ...
    round(double(srsAttemptCount)), round(double(trsAttemptCount)), ...
    round(double(pbchAcquiredCount)), round(double(numUsers)), ...
    round(double(accessReadyCount)), round(double(numUsers)), ...
    round(double(srsValidCount)), round(double(numUsers)), ...
    round(double(trsValidCellCount)), round(double(numel(trackingEligibilityByCell))), ...
    round(double(trackedServingUserCount)), round(double(numUsers)), ...
    round(double(sum(logical(sixgr.util.structGet(state, 'SchedulingEligibility', false(numUsers, 1)))))), round(double(numUsers)));
localPublishCoupledControlGatingStatus(runFolder, state, struct( ...
    "CurrentUEIndex", numUsers, ...
    "TotalUsers", numUsers, ...
    "PBCHAttemptCount", pbchAttemptCount, ...
    "PRACHAttemptCount", prachAttemptCount, ...
    "SRSAttemptCount", srsAttemptCount, ...
    "TRSAttemptCount", trsAttemptCount, ...
    "SSBOccasionActive", ssbOccasionActiveThisSlot, ...
    "ActiveSSBIndices0Based", localNumericVectorToken(sixgr.util.structGet(ssbOccasion, "ActiveSSBIndices0Based", [])), ...
    "SSBPeriodCarrierSlots", double(sixgr.util.structGet(ssbOccasion, "PeriodCarrierSlots", NaN)), ...
    "Phase", "complete", ...
    "Notes", sprintf("Coupled control gating complete for slot %s/%s: acquired=%d/%d access=%d/%d valid_srs=%d/%d valid_trs_cells=%d/%d tracked_serving_users=%d/%d eligible=%d/%d.", ...
        localDisplayProgressValue(slotIdx), localDisplayProgressValue(double(sixgr.util.structGet(state, "CanonicalSlotsPerSweepPoint", NaN))), ...
        round(double(pbchAcquiredCount)), round(double(numUsers)), round(double(accessReadyCount)), round(double(numUsers)), ...
        round(double(srsValidCount)), round(double(numUsers)), round(double(trsValidCellCount)), ...
        round(double(numel(trackingEligibilityByCell))), round(double(trackedServingUserCount)), round(double(numUsers)), ...
        round(double(sum(logical(sixgr.util.structGet(state, 'SchedulingEligibility', false(numUsers, 1)))))), round(double(numUsers)))));
end

function interval = localResolveCoupledControlHeartbeatInterval(cfg, numUsers)
interval = double(sixgr.util.structGet(cfg, "outputs.liveControlHeartbeatUEInterval", NaN));
if ~(isfinite(interval) && interval >= 1)
    interval = min(10, max(1, ceil(double(numUsers) / 20)));
end
interval = max(1, round(double(interval)));
end

function localPublishCoupledControlGatingStatus(runFolder, state, meta)
if nargin < 3 || ~isstruct(meta)
    meta = struct();
end
clock = sixgr.truth.resolveRuntimeClockProgress(state);
slotIdx = clock.CurrentSlot;
totalSlots = clock.TotalSlots;
completedFrames = clock.CompletedFrames;
totalFrames = clock.TotalFrames;
symbolsPerSlot = double(sixgr.util.structGet(state, "SymbolsPerSlot", []));
if ~(isscalar(symbolsPerSlot) && isfinite(symbolsPerSlot) && ...
        symbolsPerSlot >= 1 && symbolsPerSlot == round(symbolsPerSlot))
    error("sixgr:truth:MissingRuntimeSymbolsPerSlot", ...
        ["Live control progress requires SymbolsPerSlot from the canonical " ...
         "frame runtime; a local slot-size fallback is not permitted."]);
end

completedSymbols = clock.CompletedSymbols;
totalSymbols = clock.TotalSymbols;
runCompletion = clock.RunCompletion;
currentUE = double(sixgr.util.structGet(meta, "CurrentUEIndex", NaN));
totalUsers = double(sixgr.util.structGet(meta, "TotalUsers", sixgr.util.structGet(state, "NumUsers", NaN)));
notes = string(sixgr.util.structGet(meta, "Notes", ""));
[pbchAttemptCount, prachAttemptCount, srsAttemptCount, trsAttemptCount] = ...
    localResolveLiveControlAttemptCounts(struct(), state, meta);
if strlength(notes) == 0
    notes = sprintf("Coupled control gating %s: UE %s/%s for slot %s/%s.", ...
        char(string(sixgr.util.structGet(meta, "Phase", "streaming"))), ...
        localDisplayProgressValue(currentUE), localDisplayProgressValue(totalUsers), ...
        localDisplayProgressValue(slotIdx), localDisplayProgressValue(totalSlots));
end
localAppendRuntimeLog("INFO", "%s", char(notes));
localPublishWaveformBundleStageStatus(runFolder, struct( ...
    "Stage", "control_gating_streaming", ...
    "CurrentDirection", char(string(sixgr.util.structGet(state, "CurrentDirection", ""))), ...
    "CurrentSNR_dB", double(sixgr.util.structGet(state, "CurrentSNR_dB", NaN)), ...
    "SweepPointIndex", double(sixgr.util.structGet(state, "CurrentSweepPointIndex", NaN)), ...
    "SweepPointCount", double(sixgr.util.structGet(state, "CurrentSweepPointCount", NaN)), ...
    "CurrentUEIndex", currentUE, ...
    "TotalUsers", totalUsers, ...
    "CurrentSlot", slotIdx, ...
    "TotalSlots", totalSlots, ...
    "CurrentFrame", clock.CurrentFrame, ...
    "CompletedSlots", clock.CompletedSlots, ...
    "SlotsPerFrame", clock.SlotsPerFrame, ...
    "SymbolsPerSlot", clock.SymbolsPerSlot, ...
    "ClockScope", clock.ClockScope, ...
    "ProgressSource", clock.ProgressSource, ...
    "ProgressMeaning", clock.ProgressMeaning, ...
    "CompletedSymbols", completedSymbols, ...
    "TotalSymbols", totalSymbols, ...
    "CurrentSlotDLSymbols", double(sixgr.util.structGet(state, "CurrentSlotDLNumSymbols", NaN)), ...
    "CurrentSlotULSymbols", double(sixgr.util.structGet(state, "CurrentSlotULNumSymbols", NaN)), ...
    "DLCompletedFrames", double(sixgr.util.structGet(state, "DLCompletedFrames", NaN)), ...
    "ULCompletedFrames", double(sixgr.util.structGet(state, "ULCompletedFrames", NaN)), ...
    "CompletedFrames", completedFrames, ...
    "TotalFrames", totalFrames, ...
    "RunCompletion", runCompletion, ...
    "DLGrantCount", double(sixgr.util.structGet(state, "LastDLGrantCount", NaN)), ...
    "ULGrantCount", double(sixgr.util.structGet(state, "LastULGrantCount", NaN)), ...
    "DLActiveUsers", double(sixgr.util.structGet(state, "LastDLActiveUsers", NaN)), ...
    "ULActiveUsers", double(sixgr.util.structGet(state, "LastULActiveUsers", NaN)), ...
    "DLGrantedUsers", double(sixgr.util.structGet(state, "LastDLGrantedUsers", NaN)), ...
    "ULGrantedUsers", double(sixgr.util.structGet(state, "LastULGrantedUsers", NaN)), ...
    "DLQueueBits", double(sum(double(sixgr.util.structGet(state, "DLQueueBits", 0)), "omitnan")), ...
    "ULQueueBits", double(sum(double(sixgr.util.structGet(state, "ULQueueBits", 0)), "omitnan")), ...
    "AnchorKPIsReady", true, ...
    "DLTrialsReady", false, ...
    "ULTrialsReady", false, ...
    "ControlReady", false, ...
    "HARQReady", false, ...
    "BeamReady", false, ...
    "RFReady", false, ...
    "SweepReady", false, ...
    "FinalBundleReady", false, ...
    "ControlPhase", char(string(sixgr.util.structGet(meta, "Phase", "streaming"))), ...
    "PBCHAttemptCount", pbchAttemptCount, ...
    "PRACHAttemptCount", prachAttemptCount, ...
    "SRSAttemptCount", srsAttemptCount, ...
    "TRSAttemptCount", trsAttemptCount, ...
    "SSBOccasionActive", logical(sixgr.util.structGet(meta, "SSBOccasionActive", false)), ...
    "ActiveSSBIndices0Based", char(string(sixgr.util.structGet(meta, "ActiveSSBIndices0Based", ""))), ...
    "SSBPeriodCarrierSlots", double(sixgr.util.structGet(meta, "SSBPeriodCarrierSlots", NaN)), ...
    "Notes", char(notes)));
end

function tf = localCoupledMeasuredPathlossReferenceRequired(cfg)
% Both connected UL and absolute-power PRACH consume physical reference
% observations. Keep their channel execution bound to the shared runtime,
% independently of whether PBCH acquisition has already completed.
policy = sixgr.truth.resolveServingSSBTrackingPolicy(cfg);
tf = policy.ConnectedMeasuredPathlossReferenceRequired || ...
    policy.RASSBPowerReferenceRequired;
end

function [collision, T] = localResolveCoupledSRSPUSCHResourceDecision( ...
        cfg, pendingULGrants, currentPUCCHGrants, slotIdx, ueIdx)
collision = false;
T = table();
if isstruct(pendingULGrants) && ~isempty(pendingULGrants)
    grantSlots = arrayfun(@sixgr.truth.runtimeULGrantSlot,pendingULGrants(:));
    % SRS and PUSCH are received on the same UL carrier at the gNB.
    % Ownership is global across UEs; UE identity and logical ports do not
    % make overlapping time/frequency REs orthogonal.
    indices = find(abs(grantSlots - double(slotIdx)) < 1e-9);
    for ii = reshape(indices, 1, [])
        decision = sixgr.phy.frame.resolveSRSPUSCHCollision( ...
            cfg, pendingULGrants(ii), slotIdx, ueIdx);
        decision.CollisionPair = "SRS_PUSCH";
        decision.GrantOrdinal = double(ii);
        [decision, decisionT] = localSerializeExactCollisionDecision(decision);
        T = localAppendCompatTable(T, decisionT);
        collision = collision || logical(decision.Collision);
    end
end

if istable(currentPUCCHGrants) && ~isempty(currentPUCCHGrants)
    dueMask = abs(double(currentPUCCHGrants.ScheduledAbsoluteSlot) - ...
        double(slotIdx)) < 1e-9;
    pucchRows = currentPUCCHGrants(dueMask, :);
    for ii = 1:height(pucchRows)
        decision = sixgr.phy.frame.resolveSRSPUCCHCollision( ...
            cfg, pucchRows(ii, :), slotIdx, ueIdx);
        assert(decision.Action~="drop_overlapping_srs_symbols_preserve_pucch", ...
            'sixgr:truth:PartialSRSSymbolSuppressionRequired', ...
            ['This executor currently defers a whole SRS resource. It must not ' ...
             'drop nonoverlapping symbols of a partially overlapping SRS resource.']);
        decision.GrantOrdinal = double(ii);
        [decision, decisionT] = localSerializeExactCollisionDecision(decision);
        T = localAppendCompatTable(T, decisionT);
        collision = collision || logical(decision.Collision);
    end
end
end

function [decision, T] = localSerializeExactCollisionDecision(decision)
overlapToken = string(mat2str(double(decision.OverlapCoordinates0Based)));
decision = rmfield(decision, "OverlapCoordinates0Based");
decision.OverlapCoordinates0Based = overlapToken;
T = struct2table(decision, "AsArray", true);
end

function token = localNumericVectorToken(values)
values = double(values(:).');
values = values(isfinite(values));
if isempty(values)
    token = "";
else
    token = "[" + strjoin(string(round(values)), ",") + "]";
end
end

function count = localCountSatisfiedControlUsers(states, successState, gatingRequired)
states = string(states);
successState = string(successState);
gatingRequired = logical(gatingRequired);
if gatingRequired
    count = sum(states == successState);
else
    count = sum(states == successState | states == "not_required");
end
end

function tf = localCoupledUEControlOpportunity(slotIdx, ueIdx, periodSlots, phaseOffset)
slotIdx = max(1, round(double(slotIdx)));
ueIdx = max(1, round(double(ueIdx)));
periodSlots = max(1, round(double(periodSlots)));
phaseOffset = round(double(phaseOffset));
tf = mod(slotIdx - 1, periodSlots) == mod((ueIdx - 1) + phaseOffset, periodSlots);
end

function tf = localCoupledSRSResourceOpportunity(cfg, slotIdx, ueIdx, numUsers, periodSlots, schedulingPolicy, maxUEsPerSlot)
tf = sixgr.truth.coupledSRSResourceOpportunity(cfg, slotIdx, ueIdx, numUsers, ...
    periodSlots, schedulingPolicy, maxUEsPerSlot);
end

function cfgU = localApplyDeterministicPrachUserContext(cfgU, ueIdx)
preambleCount = max(1, round(double(sixgr.util.structGet(cfgU, "phy.prach.preambleCount", 64))));
preambleIndex = mod(max(1, round(double(ueIdx))) - 1, preambleCount);
cfgU = sixgr.util.structSet(cfgU, "phy.prach.preambleIndex", double(preambleIndex));
cfgU = sixgr.util.structSet(cfgU, "random_access.preamble_index", double(preambleIndex));
cfgU = sixgr.util.structSet(cfgU, "prach_lls.PreambleIndex", double(preambleIndex));
end

function [state, qualifiedGrants, queuedGrants] = localQualifyCoupledGrantsWithPDCCH(state, userCfg, grants, direction, snr_dB)
% Dispatch before any grant, DAI or reservation mutation. The shared owner
% performs the entire queued-control transition; the remainder is sequential.
if isfield(state,'SharedWaveformStream')
    [state,qualifiedGrants,queuedGrants]=sixgr.truth.PDCCHControlRuntime.queueShared( ...
        state,userCfg,grants,direction,snr_dB,@localAppendRuntimeLog);
    return;
end
qualifiedGrants = repmat(struct(), 0, 1);
queuedGrants = repmat(struct(), 0, 1);
direction = upper(string(direction));
if ~(isstruct(grants) && ~isempty(grants))
    return;
end
% Every grant in this path is executed with the scheduler_truth profile.
% Consequently its DCI decode is intrinsic execution authority, not an
% optional access-gating policy.  A disabled PDCCH must yield no qualified
% scheduler_truth grant rather than a control-free data waveform.
slotDLControlAllowed = logical(sixgr.util.structGet(state, "CurrentSlotDLAllowed", true)) && ...
    double(sixgr.util.structGet(state, "CurrentSlotDLNumSymbols", 0)) > 0;
for gi = 1:numel(grants)
    grant = grants(gi);
    ueIdx = sixgr.truth.GrantPreparation.resolveGrantUEIndex(grant, state.MultiUser);
    if ~(isfinite(ueIdx) && ueIdx==fix(ueIdx) && ueIdx >= 1 && ueIdx <= numel(userCfg))
        error('sixgr:truth:InvalidPDCCHGrantUEIdentity', ...
            'A scheduled DCI must bind to an existing UE; silently skipping the grant is forbidden.');
    end
    cfgU = userCfg{ueIdx};
    tempState = state;
    [cfgU, tempState] = sixgr.truth.GrantPreparation.applyCoupledRuntimeUserContext(cfgU, tempState, ueIdx, direction); %#ok<ASGLU>
    slotIdx = double(sixgr.util.structGet(grant, "Slot", sixgr.util.structGet(state, "CurrentSlot", NaN)));
    frameIdx = double(sixgr.util.structGet(grant, "Frame", sixgr.util.structGet(state, "CurrentFrame", NaN)));
    controlSlotIdx = sixgr.truth.resolvePDCCHControlSlot(grant, ...
        sixgr.util.structGet(state, "CurrentSlot", NaN));
    grant.ControlSlot = controlSlotIdx;
    controlFrameIdx = double(state.CurrentFrame);
    validateattributes(controlFrameIdx,{'numeric'},{'scalar','real','finite','integer','positive'});
    declaredControlFrame = double(sixgr.util.structGet(grant,"ControlFrame",NaN));
    assert(isscalar(declaredControlFrame) && (isnan(declaredControlFrame) || ...
        declaredControlFrame==controlFrameIdx), ...
        'sixgr:truth:PDCCHControlFrameMismatch', ...
        'A current PDCCH must not retain a different control frame from the original HARQ attempt.');
    grant.ControlFrame = controlFrameIdx;
    rnti = double(grant.RNTI);
    assert(rnti==sixgr.truth.CoupledRadioIdentity.dataRNTI(cfgU,ueIdx,direction), ...
        'sixgr:truth:PDCCHGrantRadioIdentityMismatch', ...
        'A scheduled control grant must use its installed received radio identity.');
    servingCell = double(sixgr.util.structGet(grant, "ServingCell", NaN));
    preTransmissionBlockReason="";
    if ~slotDLControlAllowed
        preTransmissionBlockReason="control_blocked_no_dl_control_symbols_in_tdd_slot";
    elseif isfield(grant,'PDCCHAdmissionSelected') && ~grant.PDCCHAdmissionSelected
        preTransmissionBlockReason="control_blocked_no_nonoverlapping_pdcch_candidate";
    end
    if strlength(preTransmissionBlockReason)>0
        [state, grant] = sixgr.truth.CoupledTruthRuntime.blockPDCCHGrantTrial( ...
            state, grant, direction, preTransmissionBlockReason);
        state = sixgr.truth.CoupledTruthRuntime.cancelUnexecutedHARQGrantRuntime( ...
            state, grant, direction, 'DCINotIssued', true);
        pdcchT = localBuildMissingPDCCHGrantBindingTrial(cfgU, NaN, ...
            preTransmissionBlockReason);
        pdcchT = localAnnotateCoupledControlTrial(pdcchT, controlSlotIdx, controlFrameIdx, ueIdx, rnti, direction, servingCell);
        [pdcchT, grant] = localAnnotateGrantControlTrial(pdcchT, grant, cfgU, direction);
        state.ControlTrials.PDCCH = localAppendCompatTable(state.ControlTrials.PDCCH, pdcchT);
        continue;
    end
    pdcchSNR_dB = sixgr.truth.resolveWaveformOperatingPointMetadata(cfgU, snr_dB);
    % An initialized attachment state is not a received DCI. Pre-attachment
    % may initialize access state, but never authorizes this DL/UL grant.
    % Reserve exact payload + DM-RS coordinates across both scheduling
    % passes. A search-space/CORESET ID or the scheduled data direction does
    % not create a separate physical resource pool.
    % Counter DAI is finalized after grant/control eligibility, never in a
    % tentative scheduler candidate or as a function of successful UE RX.
    [grant,candidateDAILedger]=sixgr.truth.prepareScheduledDLDAI( ...
        sixgr.util.structGet(state,'ScheduledDLDAILedger',struct()),cfgU,grant);
    grant=sixgr.truth.prepareScheduledULDAI(candidateDAILedger,cfgU,grant);
    cfgControl = localResolvePDCCHTrialConfig(cfgU, pdcchSNR_dB, 1, 1, grant);
    [controlCarrier, ~] = sixgr.phy.grid.makeCarrier(cfgControl);
    [state.PDCCHResourceLedger, occupiedControlREs] = ...
        sixgr.truth.PDCCHSlotResourceLedger.lookup( ...
        sixgr.util.structGet(state, "PDCCHResourceLedger", struct()), ...
        controlSlotIdx, servingCell, controlCarrier);
    occupiedControlREs=unique([occupiedControlREs;sixgr.truth.commonPDCCHReservations( ...
        state,cfgControl,controlSlotIdx-1,servingCell,controlCarrier)],'rows');
    if isfield(grant,'PDCCHAdmissionSelected')
        assert(grant.PDCCHAdmissionSelected && grant.PDCCHAdmissionControlSlot==controlSlotIdx && ...
            grant.PDCCHAdmissionCell==servingCell, ...
            'sixgr:truth:PDCCHAdmissionContextMismatch','A planned candidate belongs to one cell/control occasion.');
        occupiedControlREs=unique([occupiedControlREs;grant.PDCCHAdmissionOtherReservations],'rows');
    end
    [state,pdcchChannelState] = ...
        sixgr.truth.CoupledTruthRuntime.acquireRuntimeChannelStateForControl( ...
        state,cfgU,ueIdx,"DL");
    [pdcchRaw,pdcchUpdatedChannelState,pdcchObservedRET,allocatedControlREs] = localCollectPDCCHTrials( ...
        cfgU,pdcchSNR_dB,1,grant,pdcchChannelState,occupiedControlREs);
    if height(pdcchRaw)==1 && string(pdcchRaw.Status)=="BLOCKED" && ...
            string(pdcchRaw.FailureReason)=="control_blocked_no_nonoverlapping_pdcch_candidate"
        % The sequential (non-shared-stream) allocator can also exhaust a
        % CORESET. This is a pre-transmission decision, not a missed DCI.
        assert(isempty(allocatedControlREs) && isempty(pdcchObservedRET) && ...
            ~pdcchRaw.PDCCHReceiverTrialExecuted, ...
            'sixgr:truth:PDCCHAdmissionExecutionMismatch', ...
            'A capacity-deferred candidate cannot retain physical execution evidence.');
        reason=string(pdcchRaw.FailureReason);
        [state,grant]=sixgr.truth.CoupledTruthRuntime.blockPDCCHGrantTrial(state,grant,direction,reason);
        state=sixgr.truth.CoupledTruthRuntime.cancelUnexecutedHARQGrantRuntime( ...
            state,grant,direction,'DCINotIssued',true);
        pdcchT=localBuildMissingPDCCHGrantBindingTrial(cfgU,NaN,reason);
        pdcchT.ValueSource="pdcch_candidate_allocator_runtime";
        pdcchT=localAnnotateCoupledControlTrial(pdcchT,controlSlotIdx,controlFrameIdx,ueIdx,rnti,direction,servingCell);
        [pdcchT,grant]=localAnnotateGrantControlTrial(pdcchT,grant,cfgU,direction);
        state.ControlTrials.PDCCH=localAppendCompatTable(state.ControlTrials.PDCCH,pdcchT);
        continue;
    end
    if ~isempty(allocatedControlREs)
        % A transmitted/allocated candidate stays occupied even if its DCI
        % subsequently fails decoding; CRC failure does not release RF REs.
        state.PDCCHResourceLedger = sixgr.truth.PDCCHSlotResourceLedger.reserve( ...
            state.PDCCHResourceLedger, controlSlotIdx, servingCell, ...
            controlCarrier, allocatedControlREs);
        state.ScheduledDLDAILedger=candidateDAILedger;
    end
    state = sixgr.truth.CoupledTruthRuntime.commitRuntimeChannelState( ...
        state,pdcchUpdatedChannelState);
    state.ObservedREAllocationTable = localAppendObservedREAllocation( ...
        sixgr.util.structGet(state, "ObservedREAllocationTable", table()), ...
        pdcchObservedRET);
    pdcchT = localAnnotateCoupledControlTrial(pdcchRaw, ...
        controlSlotIdx,controlFrameIdx,ueIdx,rnti,direction,servingCell);
    % Exact DCI/grant binding is part of execution authority.  Resolve it
    % before applyPDCCHGrantTrial so a CRC-valid DCI with mismatched TDRA,
    % PRB, MCS, HARQ or identity fields can never authorize a waveform.
    [pdcchT, grant] = localAnnotateGrantControlTrial(pdcchT, grant, cfgU, direction);
    [state, grant, allowExecution] = sixgr.truth.CoupledTruthRuntime.applyPDCCHGrantTrial(state, grant, direction, pdcchT);
    % Refresh the table's control-state columns after the causal gate has
    % accepted or rejected the already-bound grant.
    [pdcchT, grant] = localAnnotateGrantControlTrial(pdcchT, grant, cfgU, direction);
    localAppendRuntimeLog("INFO", ...
        "Coupled %s PDCCH grant binding: ue=%d required=%d ok=%d status=%s failure=%s dci=%s grant_ss=%.17g observed_ss=%.17g bound_ss=%.17g grant_coreset=%.17g observed_coreset=%.17g bound_coreset=%.17g.", ...
        char(direction), round(double(ueIdx)), ...
        logical(sixgr.util.structGet(grant, "PDCCHGrantBindingRequired", false)), ...
        logical(sixgr.util.structGet(grant, "PDCCHGrantBindingOk", false)), ...
        char(string(sixgr.util.structGet(grant, "PDCCHGrantBindingStatus", ""))), ...
        char(string(sixgr.util.structGet(grant, "PDCCHGrantBindingFailureCode", ""))), ...
        char(string(sixgr.util.structGet(grant, "PDCCHGrantDCIId", ""))), ...
        double(sixgr.util.structGet(grant, "SearchSpaceID", NaN)), ...
        localTrialTableScalar(pdcchT, "SearchSpaceId", NaN), ...
        double(sixgr.util.structGet(grant, "PDCCHGrantSearchSpaceId", NaN)), ...
        double(sixgr.util.structGet(grant, "CORESETID", NaN)), ...
        localTrialTableScalar(pdcchT, "CORESETId", NaN), ...
        double(sixgr.util.structGet(grant, "PDCCHGrantCORESETId", NaN)));
    state.ControlTrials.PDCCH = localAppendCompatTable(state.ControlTrials.PDCCH, pdcchT);
    if ~allowExecution
        state = sixgr.truth.CoupledTruthRuntime.cancelUnexecutedHARQGrantRuntime(state, grant, direction);
    end
    if allowExecution
        if isempty(qualifiedGrants)
            qualifiedGrants = grant;
        else
            [qualifiedGrants, grant] = sixgr.truth.GrantPreparation.harmonizeStructArrays(qualifiedGrants, grant);
            qualifiedGrants(end + 1, 1) = grant; %#ok<AGROW>
        end
    end
end
end

function state = localCollectCanonicalCoupledControlTrials(state, cfgU, ueIdx, direction, snr_dB, trialT)
direction = upper(string(direction));
if ~(istable(trialT) && ~isempty(trialT))
    return;
end
rnti = sixgr.truth.CoupledRadioIdentity.dataRNTI(cfgU,ueIdx,direction);
slotIdx = localTrialTableScalar(trialT, "Slot", double(sixgr.util.structGet(state, "CurrentSlot", NaN)));
frameIdx = localTrialTableScalar(trialT, "Frame", double(sixgr.util.structGet(state, "CurrentFrame", NaN)));
servingCells = double(sixgr.util.structGet(state, "CurrentServingIdx", nan(max(1, ueIdx), 1)));
servingCell = NaN;
if numel(servingCells) >= ueIdx
    servingCell = double(servingCells(ueIdx));
end
slotDLAllowed = logical(sixgr.util.structGet(state, "CurrentSlotDLAllowed", true)) && ...
    double(sixgr.util.structGet(state, "CurrentSlotDLNumSymbols", 0)) > 0;
slotULAllowed = logical(sixgr.util.structGet(state, "CurrentSlotULAllowed", true)) && ...
    double(sixgr.util.structGet(state, "CurrentSlotULNumSymbols", 0)) > 0;
if direction == "DL"
    if ~slotDLAllowed
        return;
    end
    [pdcchRawT,~,pdcchObservedRET] = localCollectPDCCHTrials(cfgU, snr_dB, 1);
    state.ControlTrials.PDCCH = localAppendCompatTable(state.ControlTrials.PDCCH, ...
        localAnnotateCoupledControlTrial(pdcchRawT, slotIdx, frameIdx, ueIdx, rnti, direction, servingCell));
    state.ObservedREAllocationTable = localAppendObservedREAllocation( ...
        sixgr.util.structGet(state, "ObservedREAllocationTable", table()), ...
        pdcchObservedRET);
    [ssbOccasionActive, ~] = sixgr.truth.isActiveSSBOccasion(cfgU, slotIdx);
    if ssbOccasionActive
        cfgU = localApplyPBCHSSBBeamContext(cfgU, slotIdx, ueIdx);
        [state, pbchRawT, decodedSIB1] = localCollectCoupledPBCHTrials( ...
            state, cfgU, ueIdx, snr_dB, slotIdx);
        pbchT = localAnnotateCoupledControlTrial( ...
            pbchRawT, slotIdx, frameIdx, ueIdx, rnti, direction, servingCell);
        state.ControlTrials.PBCH = localAppendCompatTable( ...
            state.ControlTrials.PBCH, pbchT);
        state = sixgr.truth.CoupledTruthRuntime.applyPBCHTrial(state, ueIdx, pbchT);
        state = localStoreDecodedSIB1Recovery( ...
            state, ueIdx, decodedSIB1, slotIdx);
        state.LastPBCHSlot = slotIdx;
    end
    if sixgr.truth.isActiveTRSOccasion(cfgU, slotIdx)
        [trsRawT,~,trsObservedRET] = localCollectTRSTrials(cfgU, snr_dB, 1);
        state.ControlTrials.TRS = localAppendCompatTable(state.ControlTrials.TRS, ...
            localAnnotateCoupledControlTrial(trsRawT, slotIdx, frameIdx, ueIdx, rnti, direction, servingCell));
        state.ObservedREAllocationTable = localAppendObservedREAllocation( ...
            sixgr.util.structGet(state, "ObservedREAllocationTable", table()), ...
            trsObservedRET);
        state.LastTRSSlot = slotIdx;
    end
else
    if ~slotULAllowed
        return;
    end
    lastPRACH = double(sixgr.util.structGet(state, "LastPRACHSlotByUE", zeros(max(1, ueIdx), 1)));
    if ueIdx > numel(lastPRACH) || lastPRACH(ueIdx) == 0
        cfgU = localApplyDeterministicPrachUserContext(cfgU, ueIdx);
        prachSNR_dB = sixgr.truth.resolveWaveformOperatingPointMetadata(cfgU, snr_dB);
        [state, prachRawT, prachCorrT, prachRAEvidenceT] = ...
            localCollectCoupledPRACHTrials( ...
            state, cfgU, ueIdx, prachSNR_dB, slotIdx);
        state.ControlTrials.PRACH = localAppendCompatTable(state.ControlTrials.PRACH, ...
            localAnnotateCoupledControlTrial(prachRawT, slotIdx, frameIdx, ueIdx, rnti, direction, servingCell));
        state.ControlTrials.PRACHCorrelationTrace = localAppendCompatTable( ...
            sixgr.util.structGet(state.ControlTrials, "PRACHCorrelationTrace", table()), ...
            localAnnotateCoupledControlTrial(prachCorrT, slotIdx, frameIdx, ueIdx, rnti, direction, servingCell));
        state.ControlTrials.RAEvidenceTables = localAppendRAEvidenceTables( ...
            sixgr.util.structGet(state.ControlTrials, "RAEvidenceTables", struct()), prachRAEvidenceT);
        if ueIdx > numel(state.LastPRACHSlotByUE)
            state.LastPRACHSlotByUE(ueIdx, 1) = 0;
        end
        state.LastPRACHSlotByUE(ueIdx) = slotIdx;
    end
    lastSRS = double(sixgr.util.structGet(state, "LastSRSSlotByUE", zeros(max(1, ueIdx), 1)));
    srsDue=false;
    if logical(sixgr.util.structGet(cfgU,'phy.srs.enable',false))
        srsPeriod=sixgr.phy.srs.validateSRSPeriodOffset( ...
            sixgr.util.structGet(cfgU,'phy.srs.period_slots',NaN), ...
            sixgr.util.structGet(cfgU,'phy.srs.period_offset',NaN));
        srsDue=sixgr.truth.coupledSRSResourceOpportunity(cfgU,slotIdx,ueIdx,state.NumUsers, ...
            srsPeriod,cfgU.phy.srs.schedulingPolicy,cfgU.phy.srs.maxUEsPerSlot) && ...
            (ueIdx > numel(lastSRS) || lastSRS(ueIdx) == 0 || ...
            (isfinite(slotIdx) && (slotIdx - lastSRS(ueIdx)) >= srsPeriod));
    end
    if srsDue
        [cfgSRSU, state] = sixgr.truth.GrantPreparation.applyCoupledRuntimeUserContext(cfgU, state, ueIdx, "UL");
        srsSNR_dB = sixgr.truth.resolveWaveformOperatingPointMetadata(cfgSRSU, snr_dB);
        [state, srsRawT] = localCollectCoupledSRSTrials( ...
            state, cfgSRSU, ueIdx, srsSNR_dB, slotIdx);
        srsT = localAnnotateCoupledControlTrial(srsRawT, slotIdx, frameIdx, ueIdx, rnti, direction, servingCell);
        state = sixgr.truth.CoupledTruthRuntime.applySRSTrial(state, ueIdx, srsT);
        srsT = localAnnotateSRSDecisionCausality(srsT, state, ueIdx);
        state.ControlTrials.SRS = localAppendCompatTable(state.ControlTrials.SRS, srsT);
        if ueIdx > numel(state.LastSRSSlotByUE)
            state.LastSRSSlotByUE(ueIdx, 1) = 0;
        end
        state.LastSRSSlotByUE(ueIdx) = slotIdx;
    end
end
end

function T = localAnnotateSRSDecisionCausality(T, state, ueIdx)
if ~(istable(T) && ~isempty(T))
    return;
end
n = height(T);
feedbackRows = sixgr.util.structGet(state, "LatestULFeedback", repmat(struct(), 0, 1));
if ~(isstruct(feedbackRows) && ueIdx >= 1 && ueIdx <= numel(feedbackRows))
    T.RuntimeStateUpdated = false(n, 1);
    T.CSIDecisionAvailable = false(n, 1);
    T.PrecoderDecisionAvailable = false(n, 1);
    T.CausalDecisionStatus = repmat("missing_runtime_feedback_state", n, 1);
    return;
end
feedback = feedbackRows(ueIdx);
valid = logical(sixgr.util.structGet(feedback, "Valid", false));
sourceSlot = double(sixgr.util.structGet(feedback, "Slot", NaN));
trialSlot = double(T.Slot);
causal = valid && isfinite(sourceSlot) && all(sourceSlot <= trialSlot);
spatialSource = string(sixgr.util.structGet(feedback, "SpatialSignatureSource", ""));
spatialDigest = string(sixgr.util.structGet(feedback, "SpatialSignatureSHA256", ""));
spatialSourceSlot = double(sixgr.util.structGet(feedback, "SpatialSignatureSourceSlot", NaN));
precoderAvailable = causal && startsWith(lower(spatialSource), "measured_srs_receiver_channel_estimate") && ...
    strlength(strtrim(spatialDigest)) == 64 && isfinite(spatialSourceSlot) && spatialSourceSlot <= min(trialSlot);
T.RuntimeStateUpdated = repmat(logical(causal), n, 1);
T.RuntimeStateConsumer = repmat("coupled_csi_and_precoder_state", n, 1);
T.CSIDecisionAvailable = repmat(logical(causal), n, 1);
T.CSIDecisionSource = repmat(string(sixgr.util.structGet(feedback, "FeedbackSourceSignal", "")), n, 1);
T.CSIDecisionSourceSlot = repmat(sourceSlot, n, 1);
T.CSIDecisionCQI = repmat(double(sixgr.util.structGet(feedback, "CQI", NaN)), n, 1);
T.CSIDecisionRI = repmat(double(sixgr.util.structGet(feedback, "RI", NaN)), n, 1);
T.CSIDecisionPMI = repmat(double(sixgr.util.structGet(feedback, "PMI", NaN)), n, 1);
T.CSIDecisionMCS = repmat(double(sixgr.util.structGet(feedback, "MCSIndex", NaN)), n, 1);
T.CSIDecisionModulation = repmat(string(sixgr.util.structGet(feedback, "Modulation", "")), n, 1);
T.PrecoderDecisionAvailable = repmat(logical(precoderAvailable), n, 1);
T.PrecoderDecisionSource = repmat(spatialSource, n, 1);
T.PrecoderDecisionSourceSlot = repmat(spatialSourceSlot, n, 1);
T.PrecoderDecisionMatrixSHA256 = repmat(spatialDigest, n, 1);
status = "measured_srs_consumed_by_runtime_csi";
if precoderAvailable
    status = "measured_srs_consumed_by_runtime_csi_and_precoder";
elseif ~causal
    status = "srs_measurement_not_accepted_by_runtime_state";
end
T.CausalDecisionStatus = repmat(status, n, 1);
end

function value = localTrialTableScalar(T, varName, defaultValue)
value = double(defaultValue);
if ~(istable(T) && ~isempty(T) && ismember(string(varName), string(T.Properties.VariableNames)))
    return;
end
vals = double(T.(varName));
vals = vals(isfinite(vals));
if ~isempty(vals)
    value = double(vals(end));
end
end

function value = localTrialTableFirstFinite(T, varNames, defaultValue)
value = double(defaultValue);
for name = string(varNames)
    candidate = localTrialTableScalar(T, char(name), NaN);
    if isfinite(candidate)
        value = candidate;
        return;
    end
end
end

function value = localTrialTableString(T, varName, defaultValue)
value = char(string(defaultValue));
if ~(istable(T) && ~isempty(T) && ismember(string(varName), string(T.Properties.VariableNames)))
    return;
end
raw = localTrialTableLastRawValue(T, varName, defaultValue);
try
    value = char(string(raw));
catch
    value = char(string(defaultValue));
end
end

function tf = localTrialTableLogical(T, varName, defaultValue)
tf = logical(defaultValue);
if ~(istable(T) && ~isempty(T) && ismember(string(varName), string(T.Properties.VariableNames)))
    return;
end
raw = localTrialTableLastRawValue(T, varName, defaultValue);
if islogical(raw)
    tf = logical(raw);
elseif isnumeric(raw)
    raw = double(raw);
    tf = isfinite(raw) && raw ~= 0;
else
    token = lower(strtrim(string(raw)));
    tf = any(token == ["true", "1", "yes", "y", "pass", "passed", "ok"]);
end
end

function raw = localTrialTableLastRawValue(T, varName, defaultValue)
raw = defaultValue;
if ~(istable(T) && ~isempty(T) && ismember(string(varName), string(T.Properties.VariableNames)))
    return;
end
col = T.(char(string(varName)));
if isempty(col)
    return;
end
if iscell(col)
    raw = col{end};
else
    raw = col(end);
end
end


function varargout = localAnnotateCoupledControlTrial(varargin)
% Compatibility delegate; the implementation and schema have one owner.
[varargout{1:nargout}] = sixgr.truth.PDCCHControlRuntime.annotateCoupledControlTrial(varargin{:});
end

function rawTrials = localBuildCoupledTruthRawTrialsAggregate(dlTrials, ulTrials, multiUser, controlTrials, cfg)
if nargin < 4 || ~isstruct(controlTrials)
    controlTrials = struct();
end
if nargin < 5 || ~isstruct(cfg)
    error("sixgr:truth:MissingCoupledSummaryConfig", ...
        "Coupled live/final summaries require the resolved runtime configuration.");
end
rawTrials = struct( ...
    "DL", dlTrials, ...
    "UL", ulTrials, ...
    "SRS", sixgr.util.structGet(controlTrials, "SRS", table()), ...
    "CSIRS", sixgr.util.structGet(controlTrials, "CSIRS", table()), ...
    "TRS", sixgr.util.structGet(controlTrials, "TRS", table()), ...
    "PDCCH", sixgr.util.structGet(controlTrials, "PDCCH", table()), ...
    "PBCH", sixgr.util.structGet(controlTrials, "PBCH", table()), ...
    "PRACH", sixgr.util.structGet(controlTrials, "PRACH", table()), ...
    "PUCCH", sixgr.util.structGet(controlTrials, "PUCCH", table()), ...
    "RAEvidenceTables", sixgr.util.structGet(controlTrials, "RAEvidenceTables", struct()), ...
    "MultiUserDL", localBuildDirectionUserSummaryFromRaw(dlTrials, "DL", multiUser, cfg), ...
    "MultiUserUL", localBuildDirectionUserSummaryFromRaw(ulTrials, "UL", multiUser, cfg));
% Bind ALL completed producer tables before both in-memory derived exports
% and CSV publication. Binding only DL/UL left control/reference rows without
% ConfigHash in the energy path even though their separately written CSVs
% had the correct identity (first heavy refresh after checkpoint resume).
rawTrials = sixgr.truth.bindCoupledRawTrialIdentity(rawTrials, cfg);
end

function T = localHydrateHARQTrialColumnsFromTimeline(T, harqTimelineT, direction)
if ~(istable(T) && ~isempty(T) && istable(harqTimelineT) && ~isempty(harqTimelineT))
    return;
end
direction = upper(strtrim(string(direction)));
maps = localHARQTrialTimelineColumnMap();
T = localEnsureHARQTrialColumns(T, maps);

tVars = string(harqTimelineT.Properties.VariableNames);
if ismember("Direction", tVars)
    timelineDir = upper(strtrim(string(harqTimelineT.Direction)));
else
    timelineDir = repmat(direction, height(harqTimelineT), 1);
end
directionMask = timelineDir == direction;
if ~any(directionMask)
    return;
end

tSlot = localNumericColumnOrDefault(harqTimelineT, "Slot", NaN);
tFrame = localNumericColumnOrDefault(harqTimelineT, "Frame", NaN);
tUE = localNumericColumnOrDefault(harqTimelineT, ["UEIndex","UEID","UEId"], NaN);
tRNTI = localNumericColumnOrDefault(harqTimelineT, "RNTI", NaN);

rowSlot = localNumericColumnOrDefault(T, "Slot", NaN);
rowFrame = localNumericColumnOrDefault(T, "Frame", NaN);
rowUE = localNumericColumnOrDefault(T, ["UEIndex","UEID","UEId"], NaN);
rowRNTI = localNumericColumnOrDefault(T, "RNTI", NaN);

for ri = 1:height(T)
    mask = directionMask;
    if isfinite(rowSlot(ri))
        mask = mask & abs(tSlot - rowSlot(ri)) < 1e-9;
    end
    if isfinite(rowFrame(ri))
        frameMask = ~isfinite(tFrame) | abs(tFrame - rowFrame(ri)) < 1e-9;
        if any(mask & frameMask)
            mask = mask & frameMask;
        end
    end
    hasIdentity = false;
    if isfinite(rowUE(ri))
        mask = mask & abs(tUE - rowUE(ri)) < 1e-9;
        hasIdentity = true;
    elseif isfinite(rowRNTI(ri))
        mask = mask & abs(tRNTI - rowRNTI(ri)) < 1e-9;
        hasIdentity = true;
    end
    idx = find(mask);
    if isempty(idx)
        continue;
    end
    if ~hasIdentity && numel(idx) > 1
        continue;
    end
    idx = idx(end);
    for mi = 1:numel(maps)
        trialName = maps(mi).TrialName;
        timelineName = maps(mi).TimelineName;
        if ~ismember(timelineName, tVars)
            continue;
        end
        if maps(mi).IsLogical
            T.(trialName)(ri) = logical(localTimelineLogicalValue(harqTimelineT, timelineName, idx));
        else
            value = localTimelineNumericValue(harqTimelineT, timelineName, idx);
            if isfinite(value)
                T.(trialName)(ri) = value;
            end
        end
    end
end
end

function maps = localHARQTrialTimelineColumnMap()
maps = struct( ...
    "TrialName", { ...
        "HARQProcess", "HARQNDI", "HARQRV", "HARQIsRetransmission", "HARQFeedbackDueSlot", ...
        "NDIEpoch", "OriginalTBSBits", "CurrentTBSBits", "OriginalRateMatchedBits", "CurrentRateMatchedBits", ...
        "EffectiveInitialCodeRate", "EffectiveCurrentTxCodeRate", ...
        "HARQCurrentDecodeOK", "HARQCombinedDecodeOK", "HARQCombiningApplied", "HARQLLRCombiningGain_dB", ...
        "HARQPreviousLLRCount", "HARQCurrentLLRCount", "HARQCombinedLLRCount"}, ...
    "TimelineName", { ...
        "HarqID", "NDI", "RV", "IsRetransmission", "FeedbackDueSlot", ...
        "NDIEpoch", "OriginalTBSBits", "CurrentTBSBits", "OriginalRateMatchedBits", "CurrentRateMatchedBits", ...
        "EffectiveInitialCodeRate", "EffectiveCurrentTxCodeRate", ...
        "CurrentDecodeOK", "CombinedDecodeOK", "HARQCombiningApplied", "LLRCombiningGain_dB", ...
        "PreviousLLRCount", "CurrentLLRCount", "CombinedLLRCount"}, ...
    "IsLogical", { ...
        false, false, false, true, false, ...
        false, false, false, false, false, ...
        false, false, ...
        true, true, true, false, ...
        false, false, false});
end

function T = localEnsureHARQTrialColumns(T, maps)
for mi = 1:numel(maps)
    name = maps(mi).TrialName;
    if ~ismember(name, string(T.Properties.VariableNames))
        if maps(mi).IsLogical
            T.(name) = false(height(T), 1);
        else
            T.(name) = NaN(height(T), 1);
        end
    elseif maps(mi).IsLogical && ~islogical(T.(name))
        numericValues = localNumericColumn(T, name);
        T.(name) = isfinite(numericValues) & numericValues ~= 0;
    elseif ~maps(mi).IsLogical && ~isnumeric(T.(name))
        T.(name) = localNumericColumn(T, name);
    end
end
end

function value = localTimelineNumericValue(T, varName, rowIdx)
value = NaN;
try
    raw = T.(varName)(rowIdx);
    value = double(raw(1));
catch
    try
        value = str2double(string(T.(varName)(rowIdx)));
    catch
        value = NaN;
    end
end
end

function value = localTimelineLogicalValue(T, varName, rowIdx)
numVal = localTimelineNumericValue(T, varName, rowIdx);
if isfinite(numVal)
    value = numVal ~= 0;
    return;
end
try
    token = lower(strtrim(string(T.(varName)(rowIdx))));
    value = any(token == ["true","1","yes","ok","pass"]);
catch
    value = false;
end
end

function summaryT = localBuildDirectionUserSummaryFromRaw(sourceT, direction, multiUser, cfg)
if nargin < 4 || ~isstruct(cfg)
    cfg = struct();
end
template = struct( ...
        "UEIndex", NaN, ...
        "RNTI", NaN, ...
        "Direction", string(direction), ...
        "ConfiguredLayers", NaN, ...
        "ConfiguredTxAntennas", NaN, ...
        "ConfiguredRxAntennas", NaN, ...
        "BeamformingApplied", false, ...
        "BeamSelectionStrategy", "", ...
        "BeamIndexSet", "", ...
        "ExecutionModel", string(sixgr.util.structGet(multiUser, "ExecutionModel", "independent_link_sweep")), ...
        "Throughput_Mbps", NaN, ...
        "OfferedThroughput_Mbps", NaN, ...
        "Goodput_Mbps", NaN, ...
        "ObservedRowCount", NaN, ...
        "BLER", NaN, ...
        "BER", NaN, ...
        "PassRate", NaN, ...
        "MeanMeasuredSINR_dB", NaN, ...
        "MeanChannelGain_dB", NaN, ...
        "SummaryRowValid", false, ...
        "RuntimeDataPresent", false, ...
        "UserHadAnySuccessfulTx", false, ...
        "UserHadAnySuccessfulRx", false, ...
        "PartialSuccess", false, ...
        "AllObservedRowsSuccessful", false, ...
        "SummaryStatus", "", ...
        "Ok", false, ...
        "OkDefinition", "compatibility_alias_of_summary_row_valid");
if ~(istable(sourceT) && ~isempty(sourceT) && ismember("UEIndex", string(sourceT.Properties.VariableNames)))
    summaryT = struct2table(repmat(template, 0, 1), "AsArray", true);
    return;
end
    observedDuration_s = localObservedTrialWindowSeconds(sourceT, cfg);
    rows = repmat(template, 0, 1);
    ueList = unique(double(sourceT.UEIndex), "stable");
    ueList = ueList(isfinite(ueList));
    for i = 1:numel(ueList)
        mask = abs(double(sourceT.UEIndex) - ueList(i)) < 1e-9;
        slice = sourceT(mask, :);
        sem = sixgr.truth.deriveUserSummarySemantics(slice);
        row = template;
        row.UEIndex = double(ueList(i));
        row.RNTI = localLastNumericValue(slice, "RNTI");
        row.ConfiguredLayers = localLastNumericValue(slice, "ConfiguredLayers");
        row.ConfiguredTxAntennas = localLastNumericValue(slice, "ConfiguredTxAntennas");
        row.ConfiguredRxAntennas = localLastNumericValue(slice, "ConfiguredRxAntennas");
        row.BeamformingApplied = localLastLogicalValue(slice, "BeamformingApplied");
        row.BeamSelectionStrategy = localLastStringValue(slice, "BeamSelectionStrategy");
        row.BeamIndexSet = localLastStringValue(slice, "BeamIndexSet");
        row.ExecutionModel = localLastStringValue(slice, "ExecutionModel");
        row.Throughput_Mbps = localAggregateBitRateFromTrials(slice, cfg, "TBSize_bits", observedDuration_s);
        row.OfferedThroughput_Mbps = localAggregateBitRateFromTrials(slice, cfg, "OfferedBits", observedDuration_s);
        row.Goodput_Mbps = localAggregateBitRateFromTrials(slice, cfg, "GoodBits", observedDuration_s);
        row.ObservedRowCount = double(sem.ObservedRowCount);
        if ismember("CRCPass", string(slice.Properties.VariableNames))
            row.BLER = mean(1 - double(slice.CRCPass), "omitnan");
        end
        row.PassRate = double(sem.PassRate);
        row.BER = localRatioFromSlices(slice, "BitErrors", "BitsCompared");
        row.MeanMeasuredSINR_dB = localTableMean(slice, "MeasuredSINR_dB");
        row.MeanChannelGain_dB = localTableMean(slice, "ChannelGain_dB");
        row.SummaryRowValid = logical(sem.SummaryRowValid);
        row.RuntimeDataPresent = logical(sem.RuntimeDataPresent);
        row.UserHadAnySuccessfulTx = logical(sem.UserHadAnySuccessfulTx);
        row.UserHadAnySuccessfulRx = logical(sem.UserHadAnySuccessfulRx);
        row.PartialSuccess = logical(sem.PartialSuccess);
        row.AllObservedRowsSuccessful = logical(sem.AllObservedRowsSuccessful);
        row.SummaryStatus = string(sem.SummaryStatus);
        row.Ok = logical(sem.Ok);
        row.OkDefinition = string(sem.OkDefinition);
        rows(end+1, 1) = row; %#ok<AGROW>
    end
    summaryT = struct2table(rows);
end

function ratio = localRatioFromSlices(T, numVar, denVar)
ratio = NaN;
if ~(istable(T) && ~isempty(T) && ismember(numVar, string(T.Properties.VariableNames)) && ismember(denVar, string(T.Properties.VariableNames)))
    return;
end
num = sum(double(T.(numVar)), "omitnan");
den = sum(double(T.(denVar)), "omitnan");
if isfinite(den) && den > 0
    ratio = double(num) / double(den);
end
end

function value = localLastNumericValue(T, varName)
value = NaN;
if ~(istable(T) && ~isempty(T) && ismember(varName, string(T.Properties.VariableNames)))
    return;
end
vals = double(T.(varName));
vals = vals(isfinite(vals));
if ~isempty(vals)
    value = vals(end);
end
end

function value = localLastLogicalValue(T, varName)
value = false;
if ~(istable(T) && ~isempty(T) && ismember(varName, string(T.Properties.VariableNames)))
    return;
end
vals = logical(T.(varName));
if ~isempty(vals)
    value = vals(end);
end
end

function value = localLastStringValue(T, varName)
value = "";
if ~(istable(T) && ~isempty(T) && ismember(varName, string(T.Properties.VariableNames)))
    return;
end
vals = string(T.(varName));
vals = vals(strlength(vals) > 0);
if ~isempty(vals)
    value = vals(end);
end
end

function liveArtifacts = localPublishCoupledTruthRuntimeState(cfg, runFolder, rawTrials, multiUser, runtimeState, dlTablePath, ulTablePath, dlConstellationPath, ulConstellationPath, dlConstT, ulConstT, direction, snr_dB, sweepIdx, sweepCount, ueIdx, totalUsers, frameIdx, totalFrames, waveformPreviewT, varargin)
publicationScope=sixgr.runtime.ExecutionStageProfiler.scope("publication","live_runtime_tables"); %#ok<NASGU>
liveWriteScope=sixgr.util.CSVWriteReuse.scope(fileparts(char(string(runFolder)))); %#ok<NASGU>
opt = localResolveLivePublishOptions(varargin{:});
liveArtifacts = struct("Beam", struct(), "Energy", struct(), "IQImpairment", struct(), "LiveDerived", struct(), "HARQ", struct());
signalDirection = upper(string(direction));
executedNoiseMode = string(sixgr.util.structGet(runtimeState, ...
    "NoiseOperatingMode",localResolveNoiseOperatingMode(cfg)));
noiseDescription = sixgr.truth.describeNoiseOperatingPoint(executedNoiseMode);
meta = struct( ...
    "Direction", char(signalDirection), ...
    "NoiseOperatingMode", char(executedNoiseMode), ...
    "SNR_dB", double(snr_dB), ...
    "SweepPointIndex", double(sweepIdx), ...
    "SweepPointCount", double(sweepCount), ...
    "CurrentUEIndex", double(ueIdx), ...
    "TotalUsers", double(totalUsers), ...
    "CompletedFrames", double(frameIdx), ...
    "TotalFrames", double(totalFrames), ...
    "RuntimeState", runtimeState, ...
    "SlotComplete", logical(opt.SlotComplete), ...
    "FinalDirectionChunk", logical(opt.FinalDirectionChunk), ...
    "PublishReason", char(string(opt.PublishReason)), ...
    "Notes", sprintf("Coupled truth streaming %s slot %d/%d for UE %d/%d at %s %d/%d (%.3f dB, not a measured SINR). MeasuredTrialSINR_dB and ReceiverHestSINR_dB carry the live waveform/receiver SINR evidence when available.", ...
        char(signalDirection), round(double(frameIdx)), round(double(totalFrames)), round(double(ueIdx)), round(double(totalUsers)), ...
        char(noiseDescription),round(double(sweepIdx)), round(double(sweepCount)), double(snr_dB)));

refreshHeavyArtifacts = localShouldRefreshHeavyLiveArtifacts(cfg, meta);
writeRawTablesNow = logical(opt.WriteRawTables) && localShouldWriteLiveRawTables(cfg, meta, refreshHeavyArtifacts);
if writeRawTablesNow
    rawTrials = localForceDirectionalRawTrialArtifacts(rawTrials, cfg);
    sixgr.util.csvWriteTable(dlTablePath, ...
        sixgr.util.structGet(rawTrials, "DL", table()), ...
        "PreserveSchema", true);
    sixgr.util.csvWriteTable(ulTablePath, ...
        sixgr.util.structGet(rawTrials, "UL", table()), ...
        "PreserveSchema", true);
    if strlength(string(dlConstellationPath)) > 0 && istable(dlConstT) && ~isempty(dlConstT)
        sixgr.util.csvWriteTable(dlConstellationPath, localDownsampleConstellationTable(dlConstT, 2500));
    end
    if strlength(string(ulConstellationPath)) > 0 && istable(ulConstT) && ~isempty(ulConstT)
        sixgr.util.csvWriteTable(ulConstellationPath, localDownsampleConstellationTable(ulConstT, 2500));
    end
end

rootRunFolder = fileparts(char(string(runFolder)));
% Always publish the compact control/access/tracking snapshot.  Heavy live
% tables remain cadence-gated below; making them the only runtime mirror
% left WebGUI UE/TRS/SRS state one slot behind completed PHY evidence.
runtimeState = sixgr.truth.CoupledTruthRuntime.writeLiveStateTables( ...
    runtimeState, rootRunFolder);
if ~refreshHeavyArtifacts
    % Feedback can complete without a new data grant. For long runs the raw
    % writer is cadence-gated, so bind receiver attempts to the already
    % persisted primary CSVs and refresh feedback populations independently.
    committedTrials=rawTrials;
    if ~writeRawTablesNow
        committedTrials=struct('DL',table(),'UL',table());
        if isfile(dlTablePath), committedTrials.DL=sixgr.util.csvReadTable(dlTablePath); end
        if isfile(ulTablePath), committedTrials.UL=sixgr.util.csvReadTable(ulTablePath); end
    end
    compactHARQ=sixgr.truth.exportLLSLiveDerivedTables( ...
        cfg,rootRunFolder,committedTrials,multiUser,struct(),runtimeState,"harq_observations");
    liveArtifacts.HARQ=compactHARQ.HARQ;
    liveArtifacts.HARQPopulations=compactHARQ.HARQPopulations;
end
if localShouldMirrorCoupledRuntimeTables(cfg, opt, meta, refreshHeavyArtifacts, writeRawTablesNow)
    runtimeState = localWriteCoupledRuntimeTables(runtimeState, rootRunFolder);
end
% Do not leave compact channel/receiver tables at their empty startup
% snapshot until a heavy plot milestone (58 slots in the H4 run). Publish
% them whenever the corresponding primary trials are persisted.
if refreshHeavyArtifacts || writeRawTablesNow
    rawTrials = localForceDirectionalRawTrialArtifacts(rawTrials, cfg);
    mergedSignalTrials = localAppendCompatTable( ...
        sixgr.util.structGet(rawTrials, "DL", table()), ...
        sixgr.util.structGet(rawTrials, "UL", table()));
    mergedSignalConst = localAppendCompatTable(dlConstT, ulConstT);
    sixgr.truth.exportLLSLiveSignalChainTables(rootRunFolder, mergedSignalTrials, mergedSignalConst, struct( ...
        "WaveformPreviewTable", waveformPreviewT, "WriteWaveformPreview",refreshHeavyArtifacts));
    % This compact summary is live evidence, not a startup-only reference.
    % Keep it synchronized with the published receiver tables without
    % rebuilding static deployment/MCS/CQI catalogs on every slot.
    liveRawTrials=rawTrials;
    liveRawTrials.CoupledRuntime=runtimeState;
    runtimeT = localBuildRuntimeOperatingModeTable(cfg, multiUser, liveRawTrials);
    if ~isempty(runtimeT)
        sixgr.util.csvWriteTable(fullfile(rootRunFolder,"reports","csv", ...
            "runtime_operating_mode.csv"),runtimeT);
    end
end
if refreshHeavyArtifacts
    liveArtifacts = localRefreshLiveDerivedArtifacts(cfg, runFolder, rawTrials, multiUser, ...
        localBuildMobilityArtifactsFromCoupledRuntime(runtimeState), runtimeState);
    localAppendRuntimeLog("INFO", ...
        "%s heavy live artifact refresh: reason=%s slot=%d/%d interval=%d.", ...
        char(signalDirection), char(string(opt.PublishReason)), round(double(frameIdx)), round(double(totalFrames)), ...
        round(double(localResolveLiveHeavyRefreshInterval(cfg, totalFrames))));
    localPublishWaveformBundleStageStatus(runFolder, localBuildLiveStageStatus(rawTrials, liveArtifacts, meta));
else
    if logical(opt.WriteRawTables)
        notes = string(sixgr.util.structGet(meta, "Notes", ""));
        notes = notes + " Compact receiver tables follow primary-trial publication; waveform previews and heavy derived plots await the configured refresh milestone.";
        meta = localMergeLiveMeta(meta, struct("Notes", notes));
    else
        notes = string(sixgr.util.structGet(meta, "Notes", ""));
        notes = notes + " Pre-schedule progress update only; raw trial and heavy derived artifacts remain unchanged until executable grants commit.";
        meta = localMergeLiveMeta(meta, struct("Notes", notes));
    end
    localPublishWaveformBundleStageStatus(runFolder, localBuildLightweightLiveStageStatus(rawTrials, meta));
end
% Publish completed access/RS evidence before the heavy-report milestone.
% The publisher verifies source hashes and reuses an immutable snapshot
% when no measurement bytes changed. Never run it during a partial slot.
if logical(opt.SlotComplete) && logical(opt.FinalDirectionChunk) && ...
        sixgr.artifact.liveCSVPlotDue(cfg,frameIdx,totalFrames, ...
            string(opt.PublishReason)=="final_runtime_export")
    liveArtifacts.LivePNGSnapshots = sixgr.artifact.publishLiveCSVPlots(cfg, rootRunFolder);
end

dlCompletedFrames = double(sixgr.util.structGet(runtimeState, "DLCompletedFrames", NaN));
ulCompletedFrames = double(sixgr.util.structGet(runtimeState, "ULCompletedFrames", NaN));
localAppendRuntimeLog("INFO", ...
    "%s coupled publish: operating_point %d/%d configured_label_snr_dB=%.3f ue=%d/%d dlDirectionalFrames=%s/%d ulDirectionalFrames=%s/%d dlRows=%d ulRows=%d.", ...
    char(signalDirection), round(double(sweepIdx)), round(double(sweepCount)), double(snr_dB), ...
    round(double(ueIdx)), round(double(totalUsers)), ...
    localDisplayProgressValue(dlCompletedFrames), round(double(totalFrames)), ...
    localDisplayProgressValue(ulCompletedFrames), round(double(totalFrames)), ...
    height(sixgr.util.structGet(rawTrials, "DL", table())), height(sixgr.util.structGet(rawTrials, "UL", table())));
end

function [T, summaryT, constT, csirsT, signalDiagnostic, waveT, observedRET] = localCollectMultiUserLinkTrialsAcrossSweep(cfg, multiUser, direction, nTrials, snrGrid, liveTablePath, liveConstellationPath, progressLabel)
T = localEmptyLinkTrialTable(0);
observedRET=table();
constT = table();
csirsT = table();
waveT = table();
signalDiagnostic = localUnavailablePHYSignalDiagnostic(direction);
parts = {};
snrGrid = unique(sort(double(snrGrid(:))));
if nargin < 6
    liveTablePath = "";
end
if nargin < 7
    liveConstellationPath = "";
end
if nargin < 8
    progressLabel = string(direction);
end
for i = 1:numel(snrGrid)
    baseTrials = T;
    baseConst = constT;
    livePublisher = [];
    if strlength(string(liveTablePath)) > 0 || strlength(string(liveConstellationPath)) > 0
        livePublisher = @(partialTrials, partialConst, meta) localPublishLiveSweepSnapshot( ...
            baseTrials, partialTrials, baseConst, partialConst, ...
            liveTablePath, liveConstellationPath, cfg, ...
            localMergeLiveMeta(meta, struct("Direction", string(direction), "SNR_dB", double(snrGrid(i)))));
    end
    [Ti, Si, Ci, Csi, pointSignalDiagnostic, pointWaveT, pointRE] = localCollectMultiUserLinkTrials(cfg, multiUser, direction, nTrials, double(snrGrid(i)), livePublisher);
    observedRET=localAppendCompatTable(observedRET,pointRE);
    signalDiagnostic = localSelectPHYSignalDiagnostic(signalDiagnostic, pointSignalDiagnostic);
    T = localAppendCompatTable(T, Ti);
    constT = localAppendCompatTable(constT, Ci);
    csirsT = localAppendCompatTable(csirsT, Csi);
    waveT = localAppendCompatTable(waveT, pointWaveT);
    localMaybeWritePartialTable(liveTablePath, T);
    if strlength(string(liveConstellationPath)) > 0 && istable(constT) && ~isempty(constT)
        if localIsMySQLWebMode(cfg)
            sixgr.util.csvWriteTable(liveConstellationPath, localDownsampleConstellationTable(constT, 2500));
        else
            sixgr.util.csvWriteTable(liveConstellationPath, constT);
        end
    end
    localMaybeAppendSweepProgressLog(progressLabel, double(snrGrid(i)), i, numel(snrGrid), T);
    if istable(Si) && ~isempty(Si)
        parts{end+1} = Si; %#ok<AGROW>
    end
end
if isempty(parts)
    summaryT = table();
else
    summaryT = table();
    for pi = 1:numel(parts)
        summaryT = localAppendCompatTable(summaryT, parts{pi});
    end
end
end

function T = localCollectTrialsAcrossSweep(collectorFcn, snrGrid, liveTablePath, progressLabel, cfg)
T = table();
snrGrid = unique(sort(double(snrGrid(:))));
if nargin < 3
    liveTablePath = "";
end
if nargin < 4
    progressLabel = "raw_trials";
end
for i = 1:numel(snrGrid)
    Ti = collectorFcn(double(snrGrid(i)));
    Ti = sixgr.truth.bindComponentExecutionIdentity(Ti,cfg,progressLabel);
    T = localAppendCompatTable(T, Ti);
    localMaybeWritePartialTable(liveTablePath, T);
    localMaybeAppendSweepProgressLog(progressLabel, double(snrGrid(i)), i, numel(snrGrid), T);
end
end

function [T,H] = localCollectPDCCHTrialsAcrossSweep(cfg,snrGrid,nTrials,liveTablePath)
% Keep actual receiver estimates from the SAME executions as the primary
% component trials. Re-running PDCCH to repair a missing capture would change
% its noise/channel realization and cannot supply this evidence.
T=table(); H=table();
snrGrid=unique(sort(double(snrGrid(:))));
for i=1:numel(snrGrid)
    [Ti,~,~,~,Hi]=localCollectPDCCHTrials(cfg,snrGrid(i),nTrials);
    Ti=sixgr.truth.bindComponentExecutionIdentity(Ti,cfg,"PDCCH");
    Hi=sixgr.truth.bindComponentExecutionIdentity(Hi,cfg,"PDCCH");
    T=localAppendCompatTable(T,Ti);
    H=localAppendCompatTable(H,Hi);
    localMaybeWritePartialTable(liveTablePath,T);
    localMaybeAppendSweepProgressLog("PDCCH",snrGrid(i),i,numel(snrGrid),T);
end
end

function [T, correlationTraceT, raEvidenceTables] = localCollectPRACHTrialsAcrossSweep(cfg, snrGrid, nTrials, liveTablePath, progressLabel)
T = table();
correlationTraceT = table();
raEvidenceTables = localEmptyRAEvidenceTables();
snrGrid = unique(sort(double(snrGrid(:))));
if nargin < 4
    liveTablePath = "";
end
if nargin < 5
    progressLabel = "PRACH";
end
for i = 1:numel(snrGrid)
    [Ti, Ci, Ri] = localCollectPRACHTrials(cfg, double(snrGrid(i)), nTrials);
    Ti = sixgr.truth.bindComponentExecutionIdentity(Ti,cfg,"PRACH");
    T = localAppendCompatTable(T, Ti);
    correlationTraceT = localAppendCompatTable(correlationTraceT, Ci);
    raEvidenceTables = localAppendRAEvidenceTables(raEvidenceTables, Ri);
    localMaybeWritePartialTable(liveTablePath, T);
    localMaybeAppendSweepProgressLog(progressLabel, double(snrGrid(i)), i, numel(snrGrid), T);
end
end

function localMaybeWritePartialTable(pathOut, T)
if strlength(string(pathOut)) == 0 || ~istable(T)
    return;
end
[~,stem]=fileparts(string(pathOut));
sixgr.util.csvWriteTable(pathOut, T, "PreserveSchema", true, ...
    "RoundTripNumericText",any(stem==["srs_trials","srs_standalone_trials"]));
end

function interval = localResolveLiveFramePublishInterval(cfg, nTrials)
interval = double(sixgr.util.structGet(cfg, "outputs.livePublishFrameInterval", NaN));
if ~(isfinite(interval) && interval >= 1)
    if localIsMySQLWebMode(cfg)
        interval = 1;
    else
        interval = max(1, min(4, round(double(nTrials) / 4)));
    end
end
interval = max(1, round(interval));
end

function interval = localResolveLiveHeavyRefreshInterval(cfg, totalFrames)
interval = double(sixgr.util.structGet(cfg, "outputs.liveHeavyRefreshFrameInterval", NaN));
if ~(isfinite(interval) && interval >= 1)
    interval = 4;
    if isfinite(totalFrames) && totalFrames >= 1
        interval = min(interval, max(1, round(double(totalFrames))));
    end
end
interval = max(1, round(interval));
if isfinite(totalFrames) && totalFrames >= 100
    % Keep browser status live while avoiding per-slot rewrites of bulky
    % derived/report artifacts during long truth runs.
    interval = max(interval, min(25, max(10, ceil(double(totalFrames) / 5))));
end
end

function tf = localShouldWriteLiveRawTables(cfg, meta, refreshHeavyArtifacts)
tf = true;
if ~localIsMySQLWebMode(cfg)
    return;
end
if nargin < 2 || ~isstruct(meta)
    meta = struct();
end
if nargin < 3
    refreshHeavyArtifacts = localShouldRefreshHeavyLiveArtifacts(cfg, meta);
end
totalFrames = double(sixgr.util.structGet(meta, "TotalFrames", NaN));
if isfinite(totalFrames) && totalFrames >= 100
    tf = logical(refreshHeavyArtifacts);
end
end

function tf = localShouldMirrorCoupledRuntimeTables(cfg, opt, meta, refreshHeavyArtifacts, writeRawTablesNow)
tf = false;
if ~(isstruct(opt) && localCoupledLiveRuntimePublicationEnabled(cfg))
    return;
end
if nargin < 3 || ~isstruct(meta)
    meta = struct();
end
if nargin < 4
    refreshHeavyArtifacts = localShouldRefreshHeavyLiveArtifacts(cfg, meta);
end
if nargin < 5
    writeRawTablesNow = logical(sixgr.util.structGet(opt, "WriteRawTables", false));
end
totalFrames = double(sixgr.util.structGet(meta, "TotalFrames", NaN));
reason = lower(strtrim(string(sixgr.util.structGet(opt, "PublishReason", ""))));
if isfinite(totalFrames) && totalFrames >= 100
    tf = logical(writeRawTablesNow) || logical(refreshHeavyArtifacts) || any(reason == ["final_runtime_export"]);
    return;
end
tf = logical(writeRawTablesNow) || ...
    logical(sixgr.util.structGet(opt, "SlotComplete", false)) || ...
    logical(sixgr.util.structGet(opt, "FinalDirectionChunk", false)) || ...
    any(reason == ["post_grant_chunk", "slot_pre_schedule_status"]);
end

function tf = localCoupledLiveRuntimePublicationEnabled(cfg)
% Runtime control/PHY evidence is part of the canonical results folder,
% not a MySQL-only side effect.  The browser reads these tables directly
% for filesystem-backed runs, so withholding them until finalization makes
% a live truth run indistinguishable from an idle run and loses evidence if
% execution is interrupted.  Honour either supported persistence backend,
% while retaining the global persistence guard used by CoreOnly tests.
tf = logical(sixgr.util.persistenceEnabled()) && ( ...
    localIsMySQLWebMode(cfg) || ...
    logical(sixgr.util.structGet(cfg, "outputs.persistToResultsFolder", true)));
end

function artifacts = localRefreshLiveDerivedArtifacts(cfg, runFolder, rawTrials, multiUser, mobilityArtifacts, runtimeState)
if nargin < 4 || ~isstruct(multiUser)
    multiUser = struct();
end
if nargin < 5 || ~isstruct(mobilityArtifacts)
    mobilityArtifacts = struct();
end
if nargin < 6 || ~isstruct(runtimeState)
    runtimeState = struct();
end
rawTrials = localForceDirectionalRawTrialArtifacts(rawTrials, cfg);
artifacts = struct("Beam", struct(), "Energy", struct(), "LiveDerived", struct(), "HARQ", struct());
artifacts.Beam = localExportBeamformingDiagnostics(cfg, runFolder, rawTrials, false);
if isfield(runtimeState,'CompletedCanonicalSlots') && runtimeState.CompletedCanonicalSlots>0
    rawTrials.CoupledRuntime=runtimeState;
end
artifacts.Energy = sixgr.truth.exportLLSEnergyDiagnostics(cfg, runFolder, rawTrials);
artifacts.IQImpairment = sixgr.truth.exportLLSRFImpairmentDiagnostics(cfg, runFolder, rawTrials);
artifacts.LiveDerived = sixgr.truth.exportLLSLiveDerivedTables(cfg, fileparts(char(string(runFolder))), rawTrials, multiUser, mobilityArtifacts, runtimeState);
artifacts.HARQ = sixgr.util.structGet(artifacts.LiveDerived, "RuntimeHARQ", struct());
if ~localArtifactStructReady(artifacts.HARQ, "TimelineTable")
    artifacts.HARQ = sixgr.util.structGet(artifacts.LiveDerived, "HARQ", struct());
end
end

function localPublishLiveSweepSnapshot(baseTrials, partialTrials, baseConst, partialConst, liveTablePath, liveConstellationPath, cfg, meta)
if nargin < 8 || ~isstruct(meta)
    meta = struct();
end
mergedTrials = localAppendCompatTable(baseTrials, partialTrials);
direction = upper(strtrim(string(sixgr.util.structGet(meta, "Direction", ""))));
if any(direction == ["DL", "UL"])
    mergedTrials = localForceLinkTrialSourceArtifact(mergedTrials, direction);
    mergedTrials = sixgr.truth.bindCoupledExecutionIdentity(mergedTrials, cfg, direction);
end
mergedConst = table();
localMaybeWritePartialTable(liveTablePath, mergedTrials);

if strlength(string(liveConstellationPath)) > 0
    mergedConst = localAppendCompatTable(baseConst, partialConst);
    if istable(mergedConst) && ~isempty(mergedConst)
        if localIsMySQLWebMode(cfg)
            sixgr.util.csvWriteTable(liveConstellationPath, localDownsampleConstellationTable(mergedConst, 2500));
        else
            sixgr.util.csvWriteTable(liveConstellationPath, mergedConst);
        end
    end
end

if localIsMySQLWebMode(cfg)
    runFolder = localResolveRootRunFolderFromLivePath(liveTablePath);
    if strlength(string(runFolder)) > 0
        rawTrials = sixgr.util.structGet(meta, "RawTrialsAggregate", struct());
        if isempty(fieldnames(rawTrials))
            rawTrials = struct( ...
                "DL", table(), ...
                "UL", table(), ...
                "SRS", table(), ...
                "TRS", table(), ...
                "PDCCH", table(), ...
                "PBCH", table(), ...
                "PRACH", table(), ...
                "PUCCH", table(), ...
                "MultiUserDL", table(), ...
                "MultiUserUL", table());
            switch direction
                case "UL"
                    rawTrials.UL = mergedTrials;
                otherwise
                    rawTrials.DL = mergedTrials;
            end
        end
        rawTrials = localForceDirectionalRawTrialArtifacts(rawTrials, cfg);
        if localShouldRefreshHeavyLiveArtifacts(cfg, meta)
            try
                sixgr.truth.exportLLSLiveSignalChainTables(runFolder, mergedTrials, mergedConst, meta);
            catch
            end
            try
                multiUser = sixgr.util.structGet(meta, "MultiUserSpec", struct());
                mobilityArtifacts = sixgr.util.structGet(meta, "MobilityArtifacts", struct());
                liveDerived = sixgr.truth.exportLLSLiveDerivedTables(cfg, runFolder, rawTrials, multiUser, mobilityArtifacts);
                localAppendRuntimeLog("INFO", ...
                    "%s heavy live artifact refresh: reason=%s frame=%s/%s interval=%d.", ...
                    char(string(sixgr.util.structGet(meta, "Direction", ""))), ...
                    char(string(sixgr.util.structGet(meta, "PublishReason", "live_callback"))), ...
                    localDisplayProgressValue(double(sixgr.util.structGet(meta, "CompletedFrames", NaN))), ...
                    localDisplayProgressValue(double(sixgr.util.structGet(meta, "TotalFrames", NaN))), ...
                    round(double(localResolveLiveHeavyRefreshInterval(cfg, double(sixgr.util.structGet(meta, "TotalFrames", NaN))))));
                localPublishWaveformBundleStageStatus(runFolder, localBuildLiveStageStatus( ...
                    rawTrials, struct("LiveDerived", liveDerived, "HARQ", sixgr.util.structGet(liveDerived, "HARQ", struct()), "Energy", struct()), meta));
            catch
            end
        else
            meta = localMergeLiveMeta(meta, struct("Notes", ...
                string(sixgr.util.structGet(meta, "Notes", "")) + ...
                " Heavy live signal-chain and derived artifact refresh deferred until the next configured frame milestone."));
            localPublishWaveformBundleStageStatus(runFolder, localBuildLightweightLiveStageStatus(rawTrials, meta));
        end
    end
end

if sixgr.db.isArtifactStoreActive()
    completedFrames = double(sixgr.util.structGet(meta, "CompletedFrames", NaN));
    totalFrames = double(sixgr.util.structGet(meta, "TotalFrames", NaN));
    snr_dB = double(sixgr.util.structGet(meta, "SNR_dB", NaN));
    direction = string(sixgr.util.structGet(meta, "Direction", ""));
    sinrSummary = localFormatOperatingPointSINRObservabilitySummary(mergedTrials, snr_dB);
    if isfinite(completedFrames) && isfinite(totalFrames)
        message = sprintf("%s live frame publish: %d/%d directional frames complete, %s, rows=%d.", ...
            char(direction), round(completedFrames), round(totalFrames), char(sinrSummary), height(mergedTrials));
    else
        message = sprintf("%s live frame publish: partial directional update, %s, rows=%d.", ...
            char(direction), char(sinrSummary), height(mergedTrials));
    end
    sixgr.db.appendLogLine("INFO", sixgr.util.utcNowISO8601(), string(message));
end
end

function localMaybeAppendSweepProgressLog(progressLabel, snr_dB, pointIndex, pointCount, trialRowsOrTable)
[rowCount, sinrSummary] = localResolveSINRObservabilitySummary(trialRowsOrTable, snr_dB);
message = sprintf("%s raw trial sweep progress: point %d/%d, %s, rows=%d.", ...
    char(string(progressLabel)), double(pointIndex), double(pointCount), char(sinrSummary), double(rowCount));
localAppendRuntimeLog("INFO", "%s", message);
end

function runFolder = localResolveRootRunFolderFromLivePath(pathIn)
runFolder = "";
if strlength(string(pathIn)) == 0
    return;
end
try
    csvDir = fileparts(char(string(pathIn)));
    domainDir = fileparts(csvDir);
    runFolder = string(fileparts(domainDir));
catch
    runFolder = "";
end
end

function localAppendRuntimeLog(levelStr, messageText, varargin)
if nargin >= 3
    try
        messageText = sprintf(messageText, varargin{:});
    catch
    end
end
timeStamp = sixgr.util.utcNowISO8601();
try
    fprintf(1, "[%s] %s %s\n", char(timeStamp), upper(char(string(levelStr))), char(string(messageText)));
catch
end
runtimeLogPath = localRuntimeLogPath("get", "");
if strlength(runtimeLogPath) > 0
    fid = -1;
    try
        fid = fopen(char(runtimeLogPath), "a");
        if fid >= 0
            fprintf(fid, "[%s] %s %s\n", char(timeStamp), ...
                upper(char(string(levelStr))), char(string(messageText)));
            fclose(fid);
            fid = -1;
        end
    catch
        if fid >= 0
            try
                fclose(fid);
            catch
            end
        end
    end
end
if ~sixgr.db.isArtifactStoreActive()
    return;
end
try
    sixgr.db.appendLogLine(string(levelStr), timeStamp, string(messageText));
catch
end
end

function pathOut = localRuntimeLogPath(action, value)
persistent runtimePath
if isempty(runtimePath)
    runtimePath = "";
end
switch lower(string(action))
    case "set"
        runtimePath = string(value);
        parent = string(fileparts(char(runtimePath)));
        if strlength(parent) > 0
            sixgr.util.ensureFolder(char(parent));
        end
    case "clear"
        runtimePath = "";
    case "get"
        % Read-only operation.
    otherwise
        error("sixgr:truth:runWaveformLinkBundle:UnknownRuntimeLogAction", ...
            "Unknown runtime log action '%s'.", char(string(action)));
end
pathOut = runtimePath;
end

function opt = localResolveLivePublishOptions(varargin)
opt = struct( ...
    "SlotComplete", true, ...
    "WriteRawTables", true, ...
    "FinalDirectionChunk", true, ...
    "PublishReason", "streaming");
if isempty(varargin)
    return;
end
if mod(numel(varargin), 2) ~= 0
    error("sixgr:truth:runWaveformLinkBundle:LivePublishOptionsBadNV", ...
        "Live publish options must be provided as name-value pairs.");
end
for nvIdx = 1:2:numel(varargin)
    key = lower(string(varargin{nvIdx}));
    value = varargin{nvIdx + 1};
    switch key
        case "slotcomplete"
            opt.SlotComplete = logical(value);
        case "writerawtables"
            opt.WriteRawTables = logical(value);
        case "finaldirectionchunk"
            opt.FinalDirectionChunk = logical(value);
        case "publishreason"
            opt.PublishReason = string(value);
        otherwise
            error("sixgr:truth:runWaveformLinkBundle:LivePublishOptionsUnknownNV", ...
                "Unknown live publish option '%s'.", char(key));
    end
end
end

function meta = localMergeLiveMeta(meta, extra)
if nargin < 1 || ~isstruct(meta)
    meta = struct();
end
if nargin < 2 || ~isstruct(extra)
    return;
end
names = fieldnames(extra);
for i = 1:numel(names)
    meta.(names{i}) = extra.(names{i});
end
end

function tf = localShouldRefreshHeavyLiveArtifacts(cfg, meta)
if nargin < 2 || ~isstruct(meta)
    meta = struct();
end
if logical(sixgr.util.structGet(meta, "ForceHeavyRefresh", false))
    tf = true;
    return;
end
if ~logical(sixgr.util.structGet(meta, "SlotComplete", true))
    tf = false;
    return;
end
if ~logical(sixgr.util.structGet(meta, "FinalDirectionChunk", true))
    tf = false;
    return;
end
completedFrames = double(sixgr.util.structGet(meta, "CompletedFrames", NaN));
totalFrames = double(sixgr.util.structGet(meta, "TotalFrames", NaN));
interval = localResolveLiveHeavyRefreshInterval(cfg, totalFrames);
if ~(isfinite(completedFrames) && completedFrames >= 1)
    tf = true;
    return;
end
roundedFrame = max(1, round(double(completedFrames)));
refreshEachSweepPoint = logical(sixgr.util.structGet(cfg, ...
    "outputs.liveHeavyRefreshEachSweepPoint", true));
sweepPointIndex = double(sixgr.util.structGet(meta, "SweepPointIndex", 1));
sweepPointCount = double(sixgr.util.structGet(meta, "SweepPointCount", 1));
multiPointCampaign = isfinite(sweepPointIndex) && isfinite(sweepPointCount) && ...
    sweepPointCount > 1;
if roundedFrame <= 1
    tf = refreshEachSweepPoint || ~multiPointCampaign || sweepPointIndex <= 1;
    return;
end
if isfinite(totalFrames) && roundedFrame >= round(double(totalFrames))
    tf = refreshEachSweepPoint || ~multiPointCampaign || ...
        sweepPointIndex >= sweepPointCount;
    return;
end
tf = mod(roundedFrame, interval) == 0;
end

function status = localBuildLightweightLiveStageStatus(rawTrials, meta)
status = localBuildLiveStageStatus(rawTrials, struct(), meta);
dropFields = intersect(["HARQReady","BeamReady","RFReady"], string(fieldnames(status)));
if ~isempty(dropFields)
    status = rmfield(status, cellstr(dropFields));
end
end

function T = localConcatTableParts(parts)
if isempty(parts)
    T = table();
else
    T = vertcat(parts{:});
end
end

function varargout = localAppendCompatTable(varargin)
% Compatibility delegate; the implementation and schema have one owner.
[varargout{1:nargout}] = sixgr.truth.PDCCHControlRuntime.appendCompatTable(varargin{:});
end

function varargout = localAppendObservedREAllocation(varargin)
% Compatibility delegate; the implementation and schema have one owner.
[varargout{1:nargout}] = sixgr.truth.PDCCHControlRuntime.appendObservedREAllocation(varargin{:});
end

function T = localCanonicalizeLinkTrialExport(T, direction, cfg)
if ~(istable(T) && ~isempty(T))
    return;
end
scope = "ul_pusch_trials";
if strcmpi(string(direction), "DL")
    scope = "dl_pdsch_trials";
end
T = localPopulateSINRTruthColumns(T);
T = sixgr.truth.canonicalizeLLSLiveSignalChainTable(scope, T);
T = localEnsureLinkTrialTable(T, direction, double(sixgr.util.structGet(cfg, "channel.snr_dB", NaN)), cfg);
T = localForceLinkTrialSourceArtifact(T, direction);
T = sixgr.truth.canonicalizeLLSLiveSignalChainTable(scope, T);
T = sixgr.truth.bindCoupledExecutionIdentity(T, cfg, direction);
end

function T = localForceLinkTrialSourceArtifact(T, direction)
if ~(istable(T) && ~isempty(T))
    return;
end
direction = upper(strtrim(string(direction)));
if direction == "DL"
    artifact = "air_interface/csv/dl_pdsch_trials.csv";
elseif direction == "UL"
    artifact = "air_interface/csv/ul_pusch_trials.csv";
else
    return;
end
T.SourceArtifact = repmat(artifact, height(T), 1);
T.SourceTable = repmat(artifact, height(T), 1);
end

function rawTrials = localForceDirectionalRawTrialArtifacts(rawTrials, cfg)
if ~isstruct(rawTrials)
    return;
end
if isfield(rawTrials, "DL")
    rawTrials.DL = localForceLinkTrialSourceArtifact(rawTrials.DL, "DL");
    rawTrials.DL = sixgr.truth.bindCoupledExecutionIdentity(rawTrials.DL, cfg, "DL");
end
if isfield(rawTrials, "UL")
    rawTrials.UL = localForceLinkTrialSourceArtifact(rawTrials.UL, "UL");
    rawTrials.UL = sixgr.truth.bindCoupledExecutionIdentity(rawTrials.UL, cfg, "UL");
end
end

function T = localCanonicalizeControlTrialTable(signalName, T)
if ~(istable(T) && ~isempty(T))
    return;
end
T = sixgr.truth.CoupledTruthRuntime.canonicalizePersistedControlReferenceTable(signalName, T);
end

function T = localBindCoupledRuntimeIdentity(T, cfg, signalName)
T = sixgr.truth.bindCoupledExecutionIdentity(T, cfg, signalName, true);
end

function T = localCanonicalizeRecoveredPrimaryLinkEvidence(T, direction)
if ~(istable(T) && ~isempty(T))
    return;
end
direction = upper(strtrim(string(direction)));
T = localBindRecoveredNumericAlias(T, "EffectiveMCSIndex", "MCS", direction);
T = localBindRecoveredStringAlias(T, "EffectiveModulation", "Modulation", direction);
T = localBindRecoveredNumericAlias(T, "EffectiveLayers", "Layers", direction);
if ismember("Rank", string(T.Properties.VariableNames))
    T = localBindRecoveredNumericAlias(T, "EffectiveRank", "Rank", direction);
else
    T = localBindRecoveredNumericAlias(T, "EffectiveRank", "Layers", direction);
end
T = localBindRecoveredNumericAlias(T, "AirInterfaceObservation_ms", ...
    "AirInterfaceTTI_ms", direction);
end

function T = localBindRecoveredNumericAlias(T, targetName, sourceName, direction)
vars = string(T.Properties.VariableNames);
if ~ismember(sourceName, vars)
    error("sixgr:truth:RecoveredPrimaryEvidenceSourceMissing", ...
        "Recovered %s table cannot bind %s because exact runtime source %s is absent.", ...
        direction, targetName, sourceName);
end
source = double(T.(char(sourceName)));
if ~ismember(targetName, vars)
    target = NaN(height(T), 1);
else
    target = double(T.(char(targetName)));
end
missingTarget = ~isfinite(target);
if any(missingTarget & ~isfinite(source))
    error("sixgr:truth:RecoveredPrimaryEvidenceSourceInvalid", ...
        "Recovered %s table has no finite exact runtime source for %s.", ...
        direction, targetName);
end
tolerance = 1e-12 .* max(1, abs(source));
if any(~missingTarget & isfinite(source) & abs(target - source) > tolerance)
    error("sixgr:truth:RecoveredPrimaryEvidenceConflict", ...
        "Recovered %s %s conflicts with exact runtime source %s.", ...
        direction, targetName, sourceName);
end
target(missingTarget) = source(missingTarget);
T.(char(targetName)) = target;
end

function T = localBindRecoveredStringAlias(T, targetName, sourceName, direction)
vars = string(T.Properties.VariableNames);
if ~ismember(sourceName, vars)
    error("sixgr:truth:RecoveredPrimaryEvidenceSourceMissing", ...
        "Recovered %s table cannot bind %s because exact runtime source %s is absent.", ...
        direction, targetName, sourceName);
end
source = strtrim(string(T.(char(sourceName))));
if ~ismember(targetName, vars)
    target = strings(height(T), 1);
else
    target = strtrim(string(T.(char(targetName))));
end
sourceMissing = ismissing(source) | strlength(source) == 0 | lower(source) == "nan";
targetMissing = ismissing(target) | strlength(target) == 0 | lower(target) == "nan";
if any(targetMissing & sourceMissing)
    error("sixgr:truth:RecoveredPrimaryEvidenceSourceInvalid", ...
        "Recovered %s table has no exact runtime source for %s.", ...
        direction, targetName);
end
if any(~targetMissing & ~sourceMissing & ~strcmpi(target, source))
    error("sixgr:truth:RecoveredPrimaryEvidenceConflict", ...
        "Recovered %s %s conflicts with exact runtime source %s.", ...
        direction, targetName, sourceName);
end
target(targetMissing) = source(targetMissing);
T.(char(targetName)) = target;
end


function varargout = localEnsureTableVars(varargin)
% Compatibility delegate; the implementation and schema have one owner.
[varargout{1:nargout}] = sixgr.truth.PDCCHControlRuntime.ensureTableVars(varargin{:});
end

function varargout = localDefaultColumnLike(varargin)
% Compatibility delegate; the implementation and schema have one owner.
[varargout{1:nargout}] = sixgr.truth.PDCCHControlRuntime.defaultColumnLike(varargin{:});
end

function varargout = localEnsureLinkTrialTable(varargin)
% Compatibility delegate; completion/publication has one production owner.
[varargout{1:nargout}] = sixgr.truth.SharedDataCompletionRuntime.ensureLinkTrialTable(varargin{:});
end

function varargout = localPopulateSINRTruthColumns(varargin)
% Compatibility delegate; completion/publication has one production owner.
[varargout{1:nargout}] = sixgr.truth.SharedDataCompletionRuntime.populateSINRTruthColumns(varargin{:});
end

function varargout = localPostEqSINRProvenanceEligible(varargin)
% Compatibility delegate; completion/publication has one production owner.
[varargout{1:nargout}] = sixgr.truth.SharedDataCompletionRuntime.postEqSINRProvenanceEligible(varargin{:});
end

function varargout = localRepairLinkTrialEvidenceColumns(varargin)
% Compatibility delegate; completion/publication has one production owner.
[varargout{1:nargout}] = sixgr.truth.SharedDataCompletionRuntime.repairLinkTrialEvidenceColumns(varargin{:});
end

function varargout = localApplyTrialTruthAnnotations(varargin)
% Compatibility delegate; completion/publication has one production owner.
[varargout{1:nargout}] = sixgr.truth.SharedDataCompletionRuntime.applyTrialTruthAnnotations(varargin{:});
end

function varargout = localDecorateBeamAndPrecoderTruthFieldsBundle(varargin)
% Compatibility delegate; completion/publication has one production owner.
[varargout{1:nargout}] = sixgr.truth.SharedDataCompletionRuntime.decorateBeamAndPrecoderTruthFieldsBundle(varargin{:});
end

function varargout = localRequestedVsAppliedPMIStatusBundle(varargin)
% Compatibility delegate; completion/publication has one production owner.
[varargout{1:nargout}] = sixgr.truth.SharedDataCompletionRuntime.requestedVsAppliedPMIStatusBundle(varargin{:});
end

function varargout = localColumnOrDefault(varargin)
% Compatibility delegate; the implementation and schema have one owner.
[varargout{1:nargout}] = sixgr.truth.PDCCHControlRuntime.columnOrDefault(varargin{:});
end

function varargout = localNormalizeULAppliedPrecoderSourceBundle(varargin)
% Compatibility delegate; completion/publication has one production owner.
[varargout{1:nargout}] = sixgr.truth.SharedDataCompletionRuntime.normalizeULAppliedPrecoderSourceBundle(varargin{:});
end

function varargout = localResolveDirectionalTrialArtifact(varargin)
% Compatibility delegate; completion/publication has one production owner.
[varargout{1:nargout}] = sixgr.truth.SharedDataCompletionRuntime.resolveDirectionalTrialArtifact(varargin{:});
end

function varargout = localResolveArtifactStoreState(varargin)
% Compatibility delegate; completion/publication has one production owner.
[varargout{1:nargout}] = sixgr.truth.SharedDataCompletionRuntime.resolveArtifactStoreState(varargin{:});
end

function model = localResolveRequestedLinkChannelModel(cfg)
model = sixgr.channel.resolveConcreteProfile(cfg);
end

function [state, T, decodedSIB1] = localCollectCoupledPBCHTrials( ...
        state, cfg, ueIdx, snr_dB, slotIdx)
decodedSIB1 = struct();
if sixgr.channel.ChannelFactory.requiresRuntimeChannelState(cfg)
    [state, chState] = ...
        sixgr.truth.CoupledTruthRuntime.acquireRuntimeChannelStateForControl( ...
        state, cfg, ueIdx, "DL");
    [T, chState, decodedSIB1] = localCollectCoupledPBCHBeamSweep( ...
        cfg, snr_dB, chState, slotIdx);
    state = sixgr.truth.CoupledTruthRuntime.commitRuntimeChannelState( ...
        state, chState);
else
    [T, ~, decodedSIB1] = localCollectCoupledPBCHBeamSweep( ...
        cfg, snr_dB, struct(), slotIdx);
end
end

function [T, selectedAdvancedState, selectedDecodedSIB1] = ...
        localCollectCoupledPBCHBeamSweep(cfg, snr_dB, initialDLState, slotIdx, receivedBurst)
sixgr.runtime.RuntimeCallLedger.record( ...
    "sixgr.truth.runWaveformLinkBundle.localCollectCoupledPBCHBeamSweep", ...
    "SSB","DL",struct("Stage","received_beam_selection","Slot",slotIdx));
if nargin<5, receivedBurst=struct(); end
% Execute every candidate in the configured active SS burst set during the
% cell-search observation window.  A burst set can span multiple carrier
% slots (for example, four Case-A candidates occupy two slots).  Restricting
% the receiver sweep to the candidates in the first runtime slot causes the
% first successful PBCH to advance the state machine to PRACH before the
% remaining beams are measured.
%
% All candidates consume one physically received burst. Replaying the
% channel separately for each candidate can change noise and fading and
% cannot represent measurements of one SS burst set. The candidate's true
% carrier-slot and OFDM-symbol coordinates are persisted below; the coupled
% slot is the start of the acquisition window (multi-slot dispatch remains
% a separate chronological-composition responsibility).
if ~isempty(fieldnames(receivedBurst))
    % Original shared capture begins at the burst origin, even when every
    % configured candidate occurs in a later carrier slot. Validate its
    % complete received population/clock instead of re-gating emission.
    indices=sixgr.truth.validateReceivedSSBBurst(cfg,slotIdx,receivedBurst);
else
    [isOccasion, occasion] = sixgr.truth.isActiveSSBOccasion(cfg, slotIdx);
    indices = localResolveActiveSSBurstSetIndices(cfg, occasion);
    if ~isOccasion || isempty(indices)
        error("sixgr:truth:MissingActiveSSBIndex", ...
            "A coupled PBCH beam sweep requires active SSB candidates at slot %g.", ...
            double(slotIdx));
    end
end

candidateTables = cell(numel(indices), 1);
candidateStates = cell(numel(indices), 1);
candidateSIB1 = cell(numel(indices), 1);
burstOut = struct();
sharedCapture = logical(sixgr.util.structGet(cfg, "phy.sib1.enable", false));
for beamOrdinal = 1:numel(indices)
    ssbIndex = double(indices(beamOrdinal));
    cfgBeam = sixgr.util.structSet(cfg, ...
        "phy.ssb.runtimeSSBIndex", ssbIndex);
    cfgBeam = sixgr.util.structSet(cfgBeam, ...
        "phy.ssb.SSBIndex", ssbIndex);
    if ~isempty(fieldnames(receivedBurst))
        if ~isfield(receivedBurst,'CandidateResults') || numel(receivedBurst.CandidateResults)~=numel(indices)
            error('sixgr:truth:IncompleteSharedSSBBurstReception','Every configured candidate needs its actual receiver result.');
        end
        [candidateTables{beamOrdinal},candidateStates{beamOrdinal},candidateSIB1{beamOrdinal}] = ...
            localCollectPBCHTrials(cfgBeam,snr_dB,1,initialDLState,slotIdx,[],receivedBurst.CandidateResults{beamOrdinal});
    elseif ~sharedCapture
        % Preserve the existing PBCH-only path. It does not yet implement
        % the SIB1 receiver's shared-capture API and must not claim it does.
        [candidateTables{beamOrdinal}, candidateStates{beamOrdinal}, ...
            candidateSIB1{beamOrdinal}] = localCollectPBCHTrials( ...
            cfgBeam, snr_dB, 1, initialDLState, slotIdx);
    elseif beamOrdinal == 1
        [candidateTables{beamOrdinal}, candidateStates{beamOrdinal}, ...
            candidateSIB1{beamOrdinal}, burstOut] = localCollectPBCHTrials( ...
            cfgBeam, snr_dB, 1, initialDLState, slotIdx, indices);
        if ~isfield(burstOut, "CandidateResults") || ...
                numel(burstOut.CandidateResults) ~= numel(indices)
            error("sixgr:truth:IncompleteSharedSSBBurstReception", ...
                "The shared burst receiver did not return every requested candidate: %s", ...
                string(sixgr.util.structGet(burstOut, "FailureReason", "missing candidate results")));
        end
    else
        [candidateTables{beamOrdinal}, candidateStates{beamOrdinal}, ...
            candidateSIB1{beamOrdinal}] = localCollectPBCHTrials( ...
            cfgBeam, snr_dB, 1, initialDLState, slotIdx, [], ...
            burstOut.CandidateResults{beamOrdinal});
    end
end

T = table();
for beamOrdinal = 1:numel(candidateTables)
    T = localAppendCompatTable(T, candidateTables{beamOrdinal});
end
n = height(T);
candidateCoordinates=sixgr.truth.ssbCandidateCoordinateEvidence(cfg, ...
    double(T.SSBIndex),double(T.ObservationStartSample),double(T.ObservationSampleRateHz));
observedIndices = unique(round(double(T.SSBIndex(isfinite(T.SSBIndex)))), ...
    "stable");
coverageComplete = numel(observedIndices) == numel(indices) && ...
    all(ismember(indices, observedIndices));
for name=string(candidateCoordinates.Properties.VariableNames)
    T.(name)=candidateCoordinates.(name);
end
T.SSBBurstSweepExpectedCandidateCount = repmat(double(numel(indices)), n, 1);
T.SSBBurstSweepObservedCandidateCount = repmat(double(numel(observedIndices)), n, 1);
T.SSBBurstSweepObservedIndices0Based = repmat( ...
    string(localNumericVectorToken(observedIndices)), n, 1);
T.SSBBurstSweepCoverageComplete = repmat(logical(coverageComplete), n, 1);
T.SSBBurstSweepScope = repmat("configured_active_ss_burst_set", n, 1);
if isfield(receivedBurst,'AcquisitionWindowContract')
    % Receiver search and transmitter emission are different populations.
    % A quiet legal candidate has a real search outcome but is not another
    % transmitted beam. Observed identities require receiver detection.
    contract=receivedBurst.AcquisitionWindowContract;
    active=localResolveActiveSSBurstSetIndices(cfg,struct());
    T.SSBBurstSweepExpectedCandidateCount(:)=numel(active);
    T.SSBBurstSweepCoverageComplete(:)=all(ismember(active,observedIndices));
    T.SSBBurstSweepScope(:)="configured_TX_active_beams_with_complete_receiver_domain_search";
    T.SSBReceiverSearchCandidateCount=repmat(numel(indices),n,1);
    T.SSBReceiverSearchIndices0Based=repmat(string(jsonencode(indices)),n,1);
    T.SSBReceiverSearchComplete=repmat(true,n,1);
    T.SSBReceiverSearchScope=repmat(contract.Scope,n,1);
    T.SSBAcquisitionWindowContractJSON=repmat(string(jsonencode(contract)),n,1);
    T.SSBAcquisitionWindowSHA256=repmat(string(contract.SHA256),n,1);
    T.SSBRequestedCandidateTransmitted=ismember(double(T.RequestedSSBOccasionIndex),active);
    quiet=~T.SSBRequestedCandidateTransmitted;
    T.MissedDetection(quiet)=false;
    T.FalseAlarm(quiet)=sixgr.truth.pbchAcquisitionAccepted(T(quiet,:));
    T.TrackingFailureProbability(quiet)=NaN;
    T.DetectionOutcome(quiet)="quiet_candidate_no_accepted_PBCH";
    T.DetectionOutcome(quiet & T.FalseAlarm)="quiet_candidate_false_PBCH_acceptance";
    T.BCHDecodeAttempted=T.DecodeAttempted;
    T.BCHTransmittedBlockPopulationEligible=T.SSBRequestedCandidateTransmitted & ...
        T.DecodeAttempted & isfinite(T.CRCPass);
end
T.SelectedBeamFlag = false(n, 1);
T.SelectedSSBIndex = nan(n, 1);
T.SelectedBeamIndex = nan(n, 1);
% A configured-SNR run can still execute on an absolute calibrated sample
% plane. Select the beam on the measurement plane actually produced by the
% receiver, not merely on the fact that configured SNR owns the noise
% variance. This must match runSSBBeamSweep and the power-contract helpers.
fixedNormalizedEsN0 = sixgr.rf.isNormalizedFixedSNRPowerReference(cfg);
selectionMetric = sixgr.link.resolveSSBSelectionMetric(cfg);
T.SelectionMetric = repmat(selectionMetric, n, 1);
T.SelectionMetricValue_dB = nan(n, 1);
selectionSource = "coupled_receiver_measured_same_channel_origin_ssb_pbch_sweep";
if sharedCapture
    selectionSource = "coupled_receiver_measured_single_received_ssb_pbch_burst";
end
T.SelectionSource = repmat(selectionSource, n, 1);
T.SelectionStatus = repmat( ...
    "unavailable_no_successful_finite_measurement", n, 1);

power_dB = double(T.(selectionMetric));
eligible = sixgr.truth.pbchAcquisitionAccepted(T) & isfinite(power_dB) & ...
    logical(T.ChannelEstimateAvailable) & logical(T.EqualizationAvailable) & ...
    (T.PBCHStrictReceiverEvidenceOk==1);
if any(eligible)
    eligibleRows = find(eligible);
    [bestPower_dB, relativeOrdinal] = max(power_dB(eligibleRows));
    selectedRow = eligibleRows(relativeOrdinal);
    selectedSSBIndex = double(T.SSBIndex(selectedRow));
    T.SelectedBeamFlag(selectedRow) = true;
    T.SelectedSSBIndex(:) = selectedSSBIndex;
    T.SelectedBeamIndex(:) = double(T.BeamIndex(selectedRow));
    T.SelectionMetricValue_dB(:) = double(bestPower_dB);
    T.SelectionStatus(:) = "selected_from_successful_receiver_measurements";
else
    % No candidate is promoted to a selected beam.  The final failed row is
    % retained as the state-machine input, while all receiver failures stay
    % visible in the primary PBCH trial table.
    selectedRow = n;
end

selectedAdvancedState = candidateStates{selectedRow};
selectedDecodedSIB1 = candidateSIB1{selectedRow};
% CoupledTruthRuntime consumes the last row as the state transition.  Move
% the measured winner to that position without deleting any candidate row.
if selectedRow ~= n
    order = [setdiff(1:n, selectedRow, "stable"), selectedRow];
    T = T(order, :);
end
end

function indices = localResolveActiveSSBurstSetIndices(cfg, occasion)
indices = double(sixgr.util.structGet(cfg, ...
    "phy.ssb.activeCandidateIndices0Based", []));
if isempty(indices)
    timing = sixgr.util.structGet(cfg, "phy.ssb.timing", struct());
    indices = double(sixgr.util.structGet(timing, ...
        "ActiveIndices0Based", []));
end
if isempty(indices)
    indices = double(sixgr.util.structGet(occasion, ...
        "ActiveSSBIndices0Based", []));
end
indices = unique(round(indices(isfinite(indices))), "stable");
lmax = double(sixgr.util.structGet(cfg, "phy.ssb.Lmax", NaN));
if isfinite(lmax) && lmax >= 1
    indices = indices(indices >= 0 & indices < round(lmax));
else
    indices = indices(indices >= 0);
end
end

function [T, advancedDLState, decodedSIB1, cellSearchOutput] = localCollectPBCHTrials( ...
        cfg, snr_dB, nTrials, initialDLState, runtimeSlot, candidateIndices, receivedResult)
if nargin < 4 || isempty(initialDLState)
    initialDLState = struct();
end
if nargin < 5
    runtimeSlot = NaN;
end
if nargin < 6
    candidateIndices = [];
end
if nargin < 7
    receivedResult = struct();
end
cellSearchOutput = struct();
advancedDLState = initialDLState;
decodedSIB1 = struct();
nTrials = max(1, round(double(nTrials)));
standaloneTrials = isnan(runtimeSlot) && isempty(fieldnames(initialDLState)) && ...
    isempty(fieldnames(receivedResult));
assert(standaloneTrials || nTrials == 1, ...
    'sixgr:truth:PBCHRuntimeTrialMultiplicity', ...
    'A retained runtime channel or received observation belongs to one physical PBCH occasion.');
rows = repmat(localMakeLinkTrialRow(cfg, "DL", snr_dB, 1), nTrials, 1);
cfgPoint = sixgr.truth.bindStandaloneSNRPoint(cfg, double(snr_dB));
pbchObservationSubframes = localResolvePBCHObservationSubframes(cfg);
for k = 1:nTrials
    r = localMakeLinkTrialRow(cfg, "DL", snr_dB, k);
    r.Status = "FAIL";
    try
        ssbIndex = localResolvePBCHSSBIndex(cfg, k);
        cfgTrial = sixgr.truth.bindStandalonePBCHTrial( ...
            cfgPoint, double(snr_dB), k, ssbIndex);
        if standaloneTrials
            % These are separately seeded component realizations, not a
            % continuous connected capture. Initialize from this trial's
            % configured seed authority; reusing a failed initializer's
            % empty state also masks the root failure on every later trial.
            % Runtime callers retain their actual channel state unchanged.
            advancedDLState = struct();
            r.SourceClassification = "isolated_component_waveform";
        end
        % Coupled PBCH trials can execute concurrently for multiple UEs.
        % They must remain in-memory producers: writing the shared SIB1
        % filenames here creates a cross-worker overwrite race and breaks
        % the one-row/one-execution evidence identity.  The normalized
        % bundle anchor below is deliberately serial and is the sole owner
        % of component SIB1 figure/table publication.
        useRuntimeChannel = sixgr.channel.ChannelFactory. ...
            requiresRuntimeChannelState(cfgTrial) || ...
            localCoupledMeasuredPathlossReferenceRequired(cfgTrial) || ...
            (isstruct(advancedDLState) && ...
            isfield(advancedDLState, "ContractVersion") && ...
            logical(sixgr.util.structGet(advancedDLState, "Initialized", false)));
        cellSearchArgs = {"NumSubframes", pbchObservationSubframes, ...
            "SSBIndex", ssbIndex, "WriteArtifacts", false, ...
            "UseRuntimeChannel", useRuntimeChannel, ...
            "InitialDLChannelState", advancedDLState, ...
            "RuntimeSlot", runtimeSlot - 1}; % Coupled slot is one based; cell-search origin is zero based.
        if isempty(fieldnames(receivedResult))
            out = sixgr.link.runCellSearch_MIB_SIB1(cfgTrial, cellSearchArgs{:}, ...
                "CandidateSSBIndices", candidateIndices);
        else
            % Receiver result produced above from the same physical capture;
            % this branch only normalizes its row, never executes a waveform.
            out = receivedResult;
        end
        cellSearchOutput = out;
        gainComp=sixgr.util.structGet(out,'ReceiverGainCompensation',struct());
        r.ReceiverGainCompensationApplied=logical(sixgr.util.structGet(gainComp,'Applied',false));
        r.ReceiverGainCompensationSource=string(sixgr.util.structGet(gainComp,'Source',""));
        if useRuntimeChannel
            advancedDLState = sixgr.util.structGet( ...
                out, "RuntimeDLChannelState", advancedDLState);
        end
        skipped = logical(sixgr.util.structGet(out, "Skipped", false));
        pbch = sixgr.util.structGet(out, "PBCH", struct());
        sib1 = sixgr.util.structGet(out, "SIB1", struct());
        bchCrcPass = localStructLogical(sib1, "BCHCRCValid", ...
            localStructLogical(sib1,"BCHCrcPass",localStructLogical(pbch,"BCHCRCValid",false)));
        mibDecoded = localStructLogical(sib1, "MIBDecoded", false);
        sib1StrictOk = localStructLogical(sib1, "StrictOk", logical(sixgr.util.structGet(out, "Ok", false)));
        sib1TreeEqual = localStructLogical(sib1, "SIB1TreeEqual", false);
        sib1DciCrcPass = localStructLogical(sib1, "DCICrcPass", false);
        sib1DlschCrcPass = localStructLogical(sib1, "DLSCHCrcPass", false);
        sib1Asn1DecodeOk = localStructLogical(sib1, "SIB1ASN1DecodeOk", false);
        pbchAcquired = bchCrcPass && mibDecoded && ~skipped;
        % BCH CRC and overall acquisition (MIB/SIB1) are different outcomes.
        % A skipped decode has no CRC decision, not a fabricated failure.
        r.CRCPass = double(bchCrcPass);
        r.CRCApplicable = true;
        r.CRCOutcome = "fail";
        if bchCrcPass, r.CRCOutcome="pass"; end
        if skipped
            r.CRCPass=NaN;
            r.CRCOutcome="not_evaluated_decode_skipped";
        end
        r.BCHCrcPass = double(bchCrcPass);
        r.MIBDecoded = double(mibDecoded);
        r.BCHTransportBlockNumBits = double(sixgr.util.structGet(sib1, "BCHTransportBlockNumBits", ...
            sixgr.util.structGet(pbch, "BCHTransportBlockNumBits", NaN)));
        r.BCHTransportBlockHex = string(sixgr.util.structGet(sib1, "BCHTransportBlockHex", ...
            sixgr.util.structGet(pbch, "BCHTransportBlockHex", "")));
        r.BCHTransportBlockHash = string(sixgr.util.structGet(sib1, "BCHTransportBlockHash", ...
            sixgr.util.structGet(pbch, "BCHTransportBlockHash", "")));
        r.BCHScrambledBlockNumBits = double(sixgr.util.structGet(sib1, "BCHScrambledBlockNumBits", ...
            sixgr.util.structGet(pbch, "BCHScrambledBlockNumBits", NaN)));
        r.BCHScrambledBlockHex = string(sixgr.util.structGet(sib1, "BCHScrambledBlockHex", ...
            sixgr.util.structGet(pbch, "BCHScrambledBlockHex", "")));
        r.BCHScrambledBlockHash = string(sixgr.util.structGet(sib1, "BCHScrambledBlockHash", ...
            sixgr.util.structGet(pbch, "BCHScrambledBlockHash", "")));
        r.MIBDecodedBitSource = string(sixgr.util.structGet(sib1, "MIBDecodedBitSource", ...
            sixgr.util.structGet(pbch, "MIBDecodedBitSource", "")));
        r.MIBSFN4LSBValue = double(sixgr.util.structGet(sib1, "MIBSFN4LSBValue", ...
            sixgr.util.structGet(pbch, "MIBSFN4LSBValue", NaN)));
        r.MIBSFN4LSBBitString = string(sixgr.util.structGet(sib1, "MIBSFN4LSBBitString", ...
            sixgr.util.structGet(pbch, "MIBSFN4LSBBitString", "")));
        r.MIBHalfFrameBit = double(sixgr.util.structGet(sib1, "MIBHalfFrameBit", ...
            sixgr.util.structGet(pbch, "MIBHalfFrameBit", NaN)));
        r.MIBKSSBSubcarrierOffset = double(sixgr.util.structGet(sib1, "MIBKSSBSubcarrierOffset", ...
            sixgr.util.structGet(pbch, "MIBKSSBSubcarrierOffset", NaN)));
        % Original producer contract only; do not upgrade historical kSSB
        % values or use current YAML to reconstruct missing decoded operands.
        r.KSSBContractVersion=sixgr.util.structGet(sib1,"KSSBContractVersion", ...
            sixgr.util.structGet(pbch,"KSSBContractVersion",""));
        for kssbField=["Lmax","MIBKSSBLow4","PBCHKSSBMSB", ...
                "PBCHKSSBHighContribution","KSSBHighBitApplicable", ...
                "DecodedKSSB","k_SSB","BCHCRCValid","CandidateIdentityConsistent"]
            r.(kssbField)=sixgr.util.structGet(sib1,kssbField, ...
                sixgr.util.structGet(pbch,kssbField,NaN));
        end
        r.MIBSSBIndex = double(sixgr.util.structGet(sib1, "MIBSSBIndex", ...
            sixgr.util.structGet(pbch, "MIBSSBIndex", NaN)));
        r.PBCHiBarSSB = double(sixgr.util.structGet(sib1, "PBCHiBarSSB", ...
            sixgr.util.structGet(pbch, "iBar_SSB", NaN)));
        r.PBCHv = double(sixgr.util.structGet(sib1, "PBCHv", ...
            sixgr.util.structGet(pbch, "v", NaN)));
        r.SIB1StrictOk = double(sib1StrictOk);
        r.SIB1ReceptionAttempted=sixgr.util.structGet(sib1,"SIB1ReceptionAttempted",NaN);
        r.SIB1ObservationComplete=sixgr.util.structGet(sib1,"SIB1ObservationComplete",NaN);
        r.SIB1ObservationStatus=string(sixgr.util.structGet(sib1,"SIB1ObservationStatus",""));
        r.BroadcastRecoveryScope=string(sixgr.util.structGet(sib1,"RecoveryScope",""));
        r.SIB1TreeEqual = double(sib1TreeEqual);
        r.SIB1DCICrcPass = double(sib1DciCrcPass);
        r.SIB1DLSCHCrcPass = double(sib1DlschCrcPass);
        r.SIB1ASN1DecodeOk = double(sib1Asn1DecodeOk);
        if ~isequal(r.SIB1ReceptionAttempted,true)
            % No SI receive trial exists for an SSB-only observation or an
            % uncompleted legacy capture. Do not count it as failed SIB1.
            r.SIB1StrictOk=NaN;
            r.SIB1TreeEqual=NaN;
            r.SIB1DCICrcPass=NaN;
            r.SIB1DLSCHCrcPass=NaN;
            r.SIB1ASN1DecodeOk=NaN;
        end
        r.SIB1FailureReason = string(sixgr.util.structGet(sib1, "FailureReason", ""));
        r.SSBIndex = double(sixgr.util.structGet(out, "SSBIndex", ssbIndex));
        r.RequestedSSBOccasionIndex = double(sixgr.util.structGet(out, "RequestedSSBOccasionIndex", NaN));
        r.PBCHHypothesisSSBIndex = double(sixgr.util.structGet(out, "PBCHHypothesisSSBIndex", NaN));
        r.SSBIdentityVerified = logical(sixgr.util.structGet(out, "SSBIdentityVerified", false));
        r.SSBIndexSource = string(sixgr.util.structGet(out, "SSBIndexSource", ""));
        r.BeamIndex = double(sixgr.util.structGet(out, "SSBBeamIndex", r.SSBIndex + 1));
        ssbTx = sixgr.util.structGet(out, "SSBTxEvidence", struct());
        r.SSBBurstConfiguredBeamCount = double(sixgr.util.structGet(ssbTx, "ConfiguredBeamCount", NaN));
        r.SSBBurstExecutedBeamCount = double(sixgr.util.structGet(ssbTx, "ExecutedBeamCount", NaN));
        r.SSBBurstActiveIndices0Based = localNumericVectorToken( ...
            sixgr.util.structGet(ssbTx, "ActiveSSBIndices0Based", []));
        r.SSBBurstPrecoderIDs = char(strjoin(string(sixgr.util.structGet( ...
            ssbTx, "PrecoderIDs", strings(0, 1))), "|"));
        r.SSBBurstPrecoderMatrixSHA256 = char(strjoin(string(sixgr.util.structGet( ...
            ssbTx, "PrecoderMatrixSHA256", strings(0, 1))), "|"));
        r.SSBBurstPlanSHA256 = string(sixgr.util.structGet(ssbTx, "BurstPlanSHA256", ""));
        r.SSBWaveformDomain = string(sixgr.util.structGet(ssbTx, "WaveformDomain", ""));
        r.SSBWaveformPorts = double(sixgr.util.structGet(ssbTx, "WaveformPorts", NaN));
        r.SSBPhysicalTransmitAntennaElements = double(sixgr.util.structGet( ...
            ssbTx, "PhysicalTransmitAntennaElements", NaN));
        r.SSBTxEvidenceSource = string(sixgr.util.structGet(ssbTx, "Source", ""));
        r.PrecoderSource = r.SSBTxEvidenceSource;
        r.PrecodingMode = r.SSBWaveformDomain;
        r.PrecodingApplicationStage = "SSB_Tx_component_precoding_before_composite";
        r.PrecodingActive = logical(sixgr.util.structGet(ssbTx, "BeamformingApplied", false));
        r.ExplicitBeamWeightsApplied = logical(sixgr.util.structGet( ...
            ssbTx, "ExplicitBeamWeightsApplied", false));
        r.BeamformingApplied = logical(sixgr.util.structGet(ssbTx, "BeamformingApplied", false));
        % Failed acquisition has no observed beam identity. In MATLAB a
        % string converted from NaN is missing, and char(missing) throws
        % before the completed observation clock below can be retained.
        % Keep the existing empty identity; never substitute a configured beam.
        if isfinite(r.BeamIndex)
            r.AppliedBeamIndexSet = string(r.BeamIndex);
        end
        r.PrecodingNumPorts = r.SSBWaveformPorts;
        r.PrecodingNumLayers = 1;
        r.PrecodingMatrixRows = 1;
        r.PrecodingMatrixCols = r.SSBPhysicalTransmitAntennaElements;
        ssbPrecoderHash = sixgr.truth.resolveSSBPrecoderHash(ssbTx, r.SSBIndex);
        if strlength(ssbPrecoderHash) > 0
            r.AppliedPrecoderMatrixSHA256 = ssbPrecoderHash;
            r.RequestedPrecoderSHA256 = r.AppliedPrecoderMatrixSHA256;
            r.AppliedPrecoderSHA256 = r.AppliedPrecoderMatrixSHA256;
            r.PrecoderDigestDomain = "SSB_Tx_physical_beam_weight_matrix";
        end
        r.InjectedCFO_Hz = double(sixgr.util.structGet(out, "InjectedCFO_Hz", NaN));
        r.EstimatedCFO_PreCorrection_Hz = double(sixgr.util.structGet(out, "EstimatedCFO_PreCorrection_Hz", NaN));
        r.ResidualCFO_PostCorrection_Hz = double(sixgr.util.structGet(out, "ResidualCFO_PostCorrection_Hz", NaN));
        r.EstimatedCFO_Hz = double(sixgr.util.structGet(out, "EstimatedCFO_Hz", ...
            sixgr.util.structGet(out, "FreqOffsetEstimate_Hz", NaN)));
        r.TrueCFO_Hz = double(sixgr.util.structGet(out, "TrueCFO_Hz", NaN));
        r.CFOError_Hz = double(sixgr.util.structGet(out, "CFOError_Hz", NaN));
        r.CFOEstimateSource = string(sixgr.util.structGet(out, "CFOEstimateSource", ""));
        r.CFOErrorSource = string(sixgr.util.structGet(out, "CFOErrorSource", ""));
        for name = ["CFOCorrectionEnabled","CFOCorrectionApplied","CFOCorrectionApplied_Hz", ...
                "CFOCorrectionSampleOrigin","CFOCorrectionSource"]
            r.(name) = sixgr.util.structGet(out,name,r.(name));
        end
        r.CFOEstimateAvailability = string(sixgr.util.structGet( ...
            out, "CFOEstimateAvailability", "missing"));
        r.CFOErrorDefinition = string(sixgr.util.structGet( ...
            out, "CFOErrorDefinition", "not_available_without_cfo_estimate"));
        r.CFOValueStatus = string(sixgr.util.structGet( ...
            out, "CFOValueStatus", "NOT_AVAILABLE"));
        r.SIB1CFOCorrectionApplied_Hz = double(sixgr.util.structGet(out, "SIB1CFOCorrectionApplied_Hz", NaN));
        r.SIB1CFOCorrectionSource = string(sixgr.util.structGet(out, "SIB1CFOCorrectionSource", ""));
        r.ResidualCFOMeasurementStatus = string(sixgr.util.structGet(out, "ResidualCFOMeasurementStatus", ""));
        frequencyFields=sixgr.phy.broadcast.measurePBCHResidualFrequency();
        for name=string(fieldnames(frequencyFields)).'
            r.(name)=sixgr.util.structGet(out,name,frequencyFields.(name));
        end
        r.InjectedTimingOffset_samples = double(sixgr.util.structGet(out, "InjectedTimingOffset_samples", NaN));
        r.AppliedTimingCorrection_samples = double(sixgr.util.structGet(out, "AppliedTimingCorrection_samples", NaN));
        r.EstimatedTimingOffset_PreCorrection_samples = double(sixgr.util.structGet(out, "EstimatedTimingOffset_PreCorrection_samples", NaN));
        r.ResidualTimingError_PostCorrection_samples = double(sixgr.util.structGet(out, "ResidualTimingError_PostCorrection_samples", NaN));
        r.TimingOffset_samples = double(sixgr.util.structGet(out, "TimingOffset_samples", NaN));
        r.SSBTimingSearchGuardSamples = double(sixgr.util.structGet(out, "SSBTimingSearchGuardSamples", NaN));
        r.SSBTimingSearchGuardSource = string(sixgr.util.structGet(out, "SSBTimingSearchGuardSource", ""));
        r.TimingEstimateUsed = logical(sixgr.util.structGet(out, "TimingEstimateUsed", false));
        r.TrueTimingOffset_samples = double(sixgr.util.structGet(out, "TrueTimingOffset_samples", NaN));
        r.TimingError_samples = double(sixgr.util.structGet(out, "TimingError_samples", NaN));
        r.TimingEstimateApplicationPolicy = string(sixgr.util.structGet(out, "TimingEstimateApplicationPolicy", ""));
        r.TimingEstimateStatus = string(sixgr.util.structGet(out, "TimingEstimateStatus", ""));
        r.TimingEstimateWasClipped = logical(sixgr.util.structGet(out, "TimingEstimateWasClipped", false));
        r.ComputeLatency_ms = double(sixgr.util.structGet(out, "ComputeLatency_ms", NaN));
        r.ProcedureDelay_ms = double(sixgr.util.structGet(out, "ProcedureDelay_ms", NaN));
        r.AirInterfaceObservation_ms = double(sixgr.util.structGet(out, "AirInterfaceObservation_ms", NaN));
        r.AcquisitionTime_ms = double(sixgr.util.structGet(out, "AcquisitionTime_ms", NaN));
        r.ObservationStartSample = double(sixgr.util.structGet(out, "ObservationStartSample", NaN));
        r.ObservationEndSampleExclusive = double(sixgr.util.structGet(out, "ObservationEndSampleExclusive", NaN));
        r.ObservationSampleRateHz = double(sixgr.util.structGet(out, "ObservationSampleRateHz", NaN));
        r.ObservationCompletionTime_s = double(sixgr.util.structGet(out, "ObservationCompletionTime_s", NaN));
        r.ObservationCoverageSource = string(sixgr.util.structGet(out, "ObservationCoverageSource", ""));
        for name=string(fieldnames(sixgr.link.receivedWaveformEvidence())).'
            if isfield(out,name), r.(name)=out.(name); end
        end
        r.NoiseVariance = double(sixgr.util.structGet(out, "PBCHNoiseVar", ...
            sixgr.util.structGet(pbch, "NoiseVar", NaN)));
        r.EVM_rms = double(sixgr.util.structGet(out, "EVM_rms", ...
            sixgr.util.structGet(pbch, "EVM_rms", NaN)));
        r.ControlEVMSamplesJSON=string(sixgr.util.structGet(out,'ControlEVMSamplesJSON',""));
        r.EVMReferenceSource = string(sixgr.util.structGet(out, ...
            "EVMReferenceSource", sixgr.util.structGet( ...
            pbch, "EVMReferenceSource", "")));
        r.EVMValueStatus = string(sixgr.util.structGet(out, ...
            "EVMValueStatus", sixgr.util.structGet( ...
            pbch, "EVMValueStatus", "NOT_AVAILABLE")));
        r.SSBReceivedPower_dB = double(sixgr.util.structGet(out, "SSBReceivedPower_dB", NaN));
        r.SS_RSRP_dBm = double(sixgr.util.structGet(out, "SS_RSRP_dBm", NaN));
        r.SS_RSRP_dB_re_UnitOccupiedRE_Es = double(sixgr.util.structGet( ...
            out, "SS_RSRP_dB_re_UnitOccupiedRE_Es", NaN));
        r.SS_RSRPRawObserved_dB_re_UnitOccupiedRE_Es = double( ...
            sixgr.util.structGet(out, ...
            "SS_RSRPRawObserved_dB_re_UnitOccupiedRE_Es", NaN));
        for field=["SSBWindowRSSIPerReceiveAntenna_dBm","SSBWindowPowerMeasurementJSON"]
            r.(field)=string(sixgr.util.structGet(out,field,""));
        end
        for field=["SS_RSRPPerReceiveAntenna_dB_re_UnitOccupiedRE_Es", ...
                "SS_RSRPRawObservedPerReceiveAntenna_dB_re_UnitOccupiedRE_Es", ...
                "SSBWindowRSSIPerReceiveAntenna_dB_re_UnitOccupiedRE_Es", ...
                "ReferenceSignalTxEPREPerAntenna_dB_re_UnitOccupiedRE_Es"]
            r.(field)=string(sixgr.util.structGet(out,field,""));
        end
        r.SS_RSRPPerReceiveAntenna_dBm = string(sixgr.util.structGet( ...
            out, "SS_RSRPPerReceiveAntenna_dBm", ""));
        r.SS_RSRPRawObserved_dBm = double(sixgr.util.structGet( ...
            out, "SS_RSRPRawObserved_dBm", NaN));
        r.SS_RSRPRawObservedPerReceiveAntenna_dBm = string(sixgr.util.structGet( ...
            out, "SS_RSRPRawObservedPerReceiveAntenna_dBm", ""));
        r.SS_SINR_dB = double(sixgr.util.structGet(out, "SS_SINR_dB", NaN));
        r.SS_SINRPerReceiveAntenna_dB = string(sixgr.util.structGet( ...
            out, "SS_SINRPerReceiveAntenna_dB", ""));
        r.SSMeasurementSource = string(sixgr.util.structGet( ...
            out, "SSMeasurementSource", ""));
        r.SSSINRMeasurementMethod = string(sixgr.util.structGet( ...
            out, "SSSINRMeasurementMethod", ""));
        r.SSSINRReferencePlane = string(sixgr.util.structGet( ...
            out, "SSSINRReferencePlane", ""));
        r.SSSINRNoiseInterferencePowerPerReceiveAntenna_W = string( ...
            sixgr.util.structGet(out, ...
            "SSSINRNoiseInterferencePowerPerReceiveAntenna_W", ""));
        r.SSSINRDesiredPowerPerReceiveAntenna_W = string(sixgr.util.structGet( ...
            out, "SSSINRDesiredPowerPerReceiveAntenna_W", ""));
        r.SSSINRNoiseInterferenceRECount = double(sixgr.util.structGet( ...
            out, "SSSINRNoiseInterferenceRECount", NaN));
        r.SSPhysicalMeasurementStatus = string(sixgr.util.structGet( ...
            out, "SSPhysicalMeasurementStatus", "unavailable"));
        powerEvidence=sixgr.link.ssbPowerReferenceEvidence(out);
        for field=string(fieldnames(powerEvidence)).'
            r.(field)=powerEvidence.(field);
        end
        r.SSSINRFailureReason = string(sixgr.util.structGet( ...
            out, "SSSINRFailureReason", ""));
        r.ReferenceSignalId = double(sixgr.util.structGet( ...
            out, "ReferenceSignalId", r.SSBIndex));
        r.ReferenceSignalTxEPRE_dBm = double(sixgr.util.structGet( ...
            out, "ReferenceSignalTxEPRE_dBm", NaN));
        r.ReferenceSignalTxEPRE_dB_re_UnitOccupiedRE_Es = double( ...
            sixgr.util.structGet(out, ...
            "ReferenceSignalTxEPRE_dB_re_UnitOccupiedRE_Es", NaN));
        r.MeasuredReferenceSignalChannelGain_dB = double( ...
            sixgr.util.structGet(out, ...
            "MeasuredReferenceSignalChannelGain_dB", NaN));
        r.SignalledSSPBCHBlockPower_dBm = double(sixgr.util.structGet(out,"SignalledSSPBCHBlockPower_dBm",NaN));
        r.SSPBCHBlockPowerSource = string(sixgr.util.structGet(out,"SSPBCHBlockPowerSource",""));
        r.SSSTxPowerDeltaFromSignalled_dB = double(sixgr.util.structGet(out,"SSSTxPowerDeltaFromSignalled_dB",NaN));
        r.ReferenceSignalTxEPREPerAntenna_dBm = string(sixgr.util.structGet( ...
            out, "ReferenceSignalTxEPREPerAntenna_dBm", ""));
        r.ReferenceSignalTxMeasurementSource = string(sixgr.util.structGet( ...
            out, "ReferenceSignalTxMeasurementSource", ""));
        r.MeasuredReferenceSignalPathloss_dB = double(sixgr.util.structGet( ...
            out, "MeasuredReferenceSignalPathloss_dB", NaN));
        r.MeasuredReferenceSignalPathlossSource = string(sixgr.util.structGet( ...
            out, "MeasuredReferenceSignalPathlossSource", ""));
        r.PathlossReferenceRS = string(sixgr.util.structGet( ...
            out, "PathlossReferenceRS", ""));
        r.PowerReferencePlane = string(sixgr.util.structGet( ...
            out, "PowerReferencePlane", ""));
        r.PBCHDMRSMetric = double(sixgr.util.structGet(out, "PBCHDMRSMetric", NaN));
        r.PSSMetric = double(sixgr.util.structGet(out, "PSSMetric", NaN));
        detectorEvidence = sixgr.phy.sync.ssbDetectionEvidence(out);
        for name = string(fieldnames(detectorEvidence)).'
            r.(name) = detectorEvidence.(name);
        end
        r.SSSMetric = double(sixgr.util.structGet(out, "SSSMetric", NaN));
        r.SSSMetricMargin = double(sixgr.util.structGet(out, "SSSMetricMargin", NaN));
        r.PSSDetected = logical(sixgr.util.structGet(out, "PSSDetected", false));
        r.SSSDetected = logical(sixgr.util.structGet(out, "SSSDetected", false));
        r.NCellIDRecovered = logical(sixgr.util.structGet(out, "NCellIDRecovered", false));
        r.PSSDetectionSource = string(sixgr.util.structGet(out, "PSSDetectionSource", ""));
        r.SSSDetectionSource = string(sixgr.util.structGet(out, "SSSDetectionSource", ""));
        r.PSSSearchSamples = double(sixgr.util.structGet(out, "PSSSearchSamples", NaN));
        r.PSSTimingLagsEvaluated = double(sixgr.util.structGet(out, "PSSTimingLagsEvaluated", NaN));
        r.PSSSequences = double(sixgr.util.structGet(out, "PSSSequences", NaN));
        r.PSSCorrelationVectors = double(sixgr.util.structGet(out, "PSSCorrelationVectors", NaN));
        r.SSSSequenceHypotheses = double(sixgr.util.structGet(out, "SSSSequenceHypotheses", NaN));
        r.PBCHDMRSHypothesesTested = double(sixgr.util.structGet(out, "PBCHDMRSHypothesesTested", NaN));
        if isfinite(r.NoiseVariance)
            r.NoiseVarStatus = "OK";
            r.NoiseVarSource = "nrChannelEstimate_pbch_dmrs_sss";
            r.NoiseVarReason = "";
        else
            r.NoiseVarStatus = "unavailable";
            r.NoiseVarSource = "";
            r.NoiseVarReason = "pbch_noise_variance_not_reported_by_receiver";
        end
        r.ChannelEstimateAttempted = logical(sixgr.util.structGet(out, "ChannelEstimateAttempted", false));
        r.ChannelEstimateAvailable = logical(sixgr.util.structGet(out, "ChannelEstimateAvailable", ...
            sixgr.util.structGet(pbch, "ChannelEstimateAvailable", false)));
        r.ChannelEstimateSource = string(sixgr.util.structGet(out, "ChannelEstimateSource", ...
            sixgr.util.structGet(pbch, "ChannelEstimateSource", "")));
        channelScore=sixgr.truth.scoreSharedPBCHReception();
        for field=string(fieldnames(channelScore)).'
            r.(field)=sixgr.util.structGet(out,field,channelScore.(field));
        end
        r.ResourceExtractionAttempted = logical(sixgr.util.structGet(out, "ResourceExtractionAttempted", false));
        r.ResourceExtractionAvailable = r.ChannelEstimateAvailable;
        r.EqualizationAttempted = logical(sixgr.util.structGet(out, "EqualizationAttempted", false));
        r.EqualizationAvailable = logical(sixgr.util.structGet(out, "EqualizationAvailable", ...
            sixgr.util.structGet(pbch, "EqualizationAvailable", false)));
        r.EqualizerType = string(sixgr.util.structGet(out, "EqualizerType", ...
            sixgr.util.structGet(pbch, "EqualizerType", "")));
        r = sixgr.truth.bindPBCHReceiverSINREvidence(r,out,pbch);
        r.LLRAvailable = logical(sixgr.util.structGet(out, "LLRAvailable", false));
        r.LLRFinite = logical(sixgr.util.structGet(out, "LLRFinite", false));
        r.LLRNoiseVariance = r.NoiseVariance;
        % Original BCH receiver evidence, independent of later SI decoding.
        r.PBCHStrictReceiverEvidenceOk = isequal( ...
            sixgr.util.structGet(out,"PBCHStrictReceiverEvidenceOk",false),true);
        r.StrictReceiverEvidenceOk = logical(sixgr.util.structGet(out, "StrictReceiverEvidenceOk", ...
            sixgr.util.structGet(pbch, "StrictReceiverEvidenceOk", false))) && ...
            r.ChannelEstimateAvailable && r.EqualizationAvailable && ...
            r.ReceiverHestSINRApplicable && r.PostEqSINRReceiverDerived;
        r.StrictOk = logical(sib1StrictOk) && logical(r.StrictReceiverEvidenceOk);
        if r.BroadcastRecoveryScope=="SSB_MIB"
            % This original capture attempted BCH/MIB only. A later SI
            % result cannot qualify or fail its completed BCH receiver.
            r.StrictReceiverEvidenceOk=r.PBCHStrictReceiverEvidenceOk && ...
                r.ChannelEstimateAvailable && r.EqualizationAvailable && ...
                r.ReceiverHestSINRApplicable && r.PostEqSINRReceiverDerived;
            r.StrictOk=logical(pbchAcquired) && r.StrictReceiverEvidenceOk;
        end
        r.ReceiverUsable = logical(r.StrictReceiverEvidenceOk);
        r.MeasurementAttempted = logical(sixgr.util.structGet(out, "MeasurementAttempted", false));
        r.MeasurementUsable = r.ReceiverHestSINRApplicable || r.PostEqSINRReceiverDerived;
        % Received control/CRC/ASN.1 semantics own common configuration.
        % TX-tree equality remains independent validation, never UE input.
        if sib1DciCrcPass && sib1DlschCrcPass && sib1Asn1DecodeOk && ...
                localStructLogical(sib1,"SIB1SemanticValid",false)
            decodedSIB1 = localCompactDecodedSIB1Recovery(sib1);
        end
        r.TrackingFailureProbability = double(~pbchAcquired);
        r.DetectionAttempted = logical(sixgr.util.structGet(out, "DetectionAttempted", false));
        r.DecodeAttempted = logical(sixgr.util.structGet(out, "DecodeAttempted", false));
        if ~r.DecodeAttempted
            r.CRCPass=NaN;
            r.BCHCrcPass=NaN;
            r.CRCApplicable=false;
            r.CRCOutcome="not_evaluated_no_BCH_decode";
        end
        if pbchAcquired
            % Keep the receiver's measured correlation metric copied above.
            % CRC/acquisition success is a decision, not a unit correlation.
            r.DetectionSuccess = true;
            r.DetectionUsable = true;
            r.MissedDetection = false;
            r.FalseAlarm = false;
            r.DetectionOutcome = "ssb_pbch_mib_acquired";
            r.DecodeUsable = true;
            if r.StrictOk
                r.Status = "PASS";
            else
                r.Status = "FAIL";
                if ~logical(r.StrictReceiverEvidenceOk)
                    r.FailureReason = "pbch_receiver_evidence_missing_after_pbch_mib_acquisition";
                else
                    r.FailureReason = "sib1_strict_recovery_failed_after_pbch_mib_acquisition";
                end
            end
        else
            r.DetectionSuccess = false;
            r.DetectionUsable = r.DetectionAttempted;
            r.MissedDetection = r.DetectionAttempted;
            r.FalseAlarm = false;
            r.DetectionOutcome = "ssb_pbch_mib_not_acquired";
            r.DecodeUsable = false;
            if skipped
                r.Status = "NA";
            elseif logical(sixgr.util.structGet(out, "Crash", false))
                r.Status = "CRASH";
                r.Crash = true;
            else
                r.Status = "FAIL";
            end
            r.FailureReason = localPBCHFailureReason(out, sib1, pbch);
        end
        detectorNotes = string(sixgr.util.structGet(out, "Notes", ""));
        if strlength(strtrim(string(r.Notes))) == 0
            r.Notes = detectorNotes;
        elseif strlength(strtrim(detectorNotes)) > 0
            r.Notes = string(r.Notes) + "; ssb_receiver_notes=" + detectorNotes;
        end
    catch ME
        r.Crash = true;
        % A reporting/SI exception is not a negative BCH decoder decision.
        % Preserve an already copied CRC; otherwise the canonical NaN stays.
        r.Status = "CRASH";
        failure = string(ME.identifier) + ":" + string(ME.message);
        r.FailureReason = failure;
        r.Notes = failure;
    end
    rows(k) = r;
end
T = struct2table(rows);
end

function reason = localPBCHFailureReason(out, sib1, pbch)
reason = string(sixgr.util.structGet(out, "FailureReason", ""));
if strlength(strtrim(reason)) == 0
    reason = string(sixgr.util.structGet(sib1, "FailureReason", ""));
end
if strlength(strtrim(reason)) == 0
    reason = string(sixgr.util.structGet(pbch, "FailureReason", ""));
end
if strlength(strtrim(reason)) == 0
    reason = string(sixgr.util.structGet(out, "FailureIdentifier", ""));
end
if strlength(strtrim(reason)) == 0
    reason = string(sixgr.util.structGet(out, "Notes", "pbch_receiver_failed_without_reason"));
end
reason = strtrim(reason);
end

function tf = localStructLogical(s, fieldName, defaultValue)
raw = defaultValue;
if isstruct(s) && isfield(s, fieldName)
    raw = s.(fieldName);
end
if islogical(raw)
    tf = any(raw(:));
elseif isnumeric(raw)
    vals = double(raw(:));
    vals = vals(isfinite(vals));
    tf = ~isempty(vals) && vals(1) ~= 0;
elseif ischar(raw) || isstring(raw)
    token = lower(strtrim(string(raw)));
    tf = any(token == ["1", "true", "yes", "pass", "ok"]);
else
    tf = logical(defaultValue);
end
end

function recovery = localCompactDecodedSIB1Recovery(sib1)
% Preserve only receiver-owned fields needed by the subsequent RA stage.
% Every value below is copied from recoverSIB1FromWaveform output; no YAML
% value or configured tree is substituted into this causal capsule.
recovery = struct();
if ~(isstruct(sib1) && ~isempty(fieldnames(sib1)))
    return;
end
fields = ["StrictOk","SIB1TreeEqual","DCICrcPass","DLSCHCrcPass", ...
    "SIB1ASN1DecodeOk","SIB1SemanticValid","SIB1PayloadHashRx", ...
    "SIB1RxTreeHash","SIB1TxTreeHash","SIB1RxTree", ...
    "MIBDecoded","BCHCrcPass","MIBDMRSTypeAPosition", ...
    "CORESET0Present","CORESET0NumRB","CORESET0RBStart","ReceivedDLTimingReference"];
for i = 1:numel(fields)
    name = char(fields(i));
    if isfield(sib1, name)
        recovery.(name) = sib1.(name);
    end
end
end



function state=localCompleteSharedScheduledPDCCH(state,item)
% One owner performs actual reception, binding, publication and UL handoff.
state=sixgr.truth.PDCCHControlRuntime.completeShared(state,item,@localAppendRuntimeLog);
end


function state=localCompleteSharedDataPlan(state,item)
% Single production owner; preserve the coordinator's logger.
state=sixgr.truth.SharedDataCompletionRuntime.complete(state,item,@localAppendRuntimeLog);
end

function [state,dl,ul,dc,uc,ds,us]=localDrainSharedDataPlans(state,dl,ul,dc,uc,ds,us)
% Drain the exact completed plans and per-UE link-adaptation states.
[state,dl,ul,dc,uc,ds,us]=sixgr.truth.SharedDataCompletionRuntime.drain(state,dl,ul,dc,uc,ds,us);
end

function state=localCompleteSharedControlObservations(state,received)
% The owner has already physically committed every DataTX in this callback
% batch. Publish all of those grant/expectation records before any receiver
% reads the scheduling snapshot, including at a coincident event deadline.
% Preserve relative order inside each class; no future samples are consumed.
state=sixgr.truth.completeSharedReceiverBatch( ...
    state,received,@localCompleteSharedControlObservation);
end

function state=localCompleteSharedControlObservation(state,received)
for item=received
    context=item.Context;
    if any(item.Kind==["CellSIB1TX","CellSSBTX"])
        assert(numel(item.Planes)==1 && string(item.Planes.ReceiverID)==context.TransmitterPlane, ...
            'sixgr:truth:SIB1TransmitObservationIdentity','Publish only the original completed gNB SI observation.');
        observed=sixgr.truth.buildObservedBroadcastREAllocation( ...
            context.Prepared,item.Planes.Observation,context.ServingCell);
        state.ObservedREAllocationTable=localAppendObservedREAllocation( ...
            sixgr.util.structGet(state,'ObservedREAllocationTable',table()),observed);
        continue;
    end
    if item.Kind=="BindSRSPower"
        state=sixgr.truth.bindSharedSRSPower(state,item);
        continue;
    end
    if item.Kind=="PUCCHTX"
        state=sixgr.truth.commitSharedPUCCHTransmission(state,item);
        continue;
    end
    if item.Kind=="DataTX"
        state=sixgr.truth.commitSharedDataTransmission(state,item);
        if item.Context.Prepared.Direction=="DL"
            transmitted=state.SharedDataTXLedger{end};
            if transmitted.Grant.TimingDecision.HARQACKRequired
                state=sixgr.truth.CoupledTruthRuntime.armSharedDLHARQOccasionFromGrantRuntime( ...
                    state,transmitted.Grant,item.UE);
            end
        end
        continue;
    end
    if item.Kind=="PDCCH"
        state=localCompleteSharedScheduledPDCCH(state,item);
        continue;
    end
    if item.Kind=="CSIRS"
        [state,~,~,~]=sixgr.truth.completeSharedCSIRSReception(state,item);
        p=item.Context.Prepared;
        observed=sixgr.truth.buildObservedREAllocation(p.Tx, ...
            'Direction','DL','Channel','CSI-RS', ...
            'AbsoluteSlot',item.Context.Slot-1, ...
            'CellID',item.Context.ServingCell,'UEID',NaN, ...
            'AllocationID',"csirs_cell_"+string(item.Context.ServingCell)+ ...
                "_slot_"+string(item.Context.Slot-1));
        state.ObservedREAllocationTable=localAppendObservedREAllocation( ...
            sixgr.util.structGet(state,'ObservedREAllocationTable',table()),observed);
        continue;
    end
    if item.Kind=="PrepareULData"
        state=sixgr.truth.prepareSharedScheduledULData(state,item);
        continue;
    end
    if item.Kind=="PreparePUCCH"
        state=sixgr.truth.CoupledTruthRuntime.prepareSharedPUCCHFeedbackRuntime(state,item);
        continue;
    end
    if item.Kind=="PUCCH"
        state=sixgr.truth.CoupledTruthRuntime.completeSharedPUCCHFeedbackRuntime(state,item);
        continue;
    end
    if item.Kind=="PUCCHReceiveOnly"
        state=sixgr.truth.CoupledTruthRuntime.completeSharedPUCCHReceiveOnlyRuntime(state,item);
        continue;
    end
    if item.Kind=="PUCCHNotSelected"
        state=sixgr.truth.completeUnselectedPUCCHObservation(state,item);
        continue;
    end
    if item.Kind=="PUSCHReceiveOnly"
        state=sixgr.truth.completeSharedPUSCHAfterRejectedControl(state,item.Context.ObservationID);
        continue;
    end
    if any(item.Kind==["PDSCH","PUSCH"])
        state=localCompleteSharedDataPlan(state,item);
        continue;
    end
    if item.Kind=="Msg1TX"
        state=sixgr.truth.completeSharedMsg1Transmission(state,item);
        continue;
    end
    if any(item.Kind==["RA","RAR","RARExpiry","Contention","ContentionStart","ContentionExpiry"])
        state=localCompleteSharedRAObservation(state,item);
        continue;
    end
    if item.Kind=="SuppressedSRSObservation"
        proof=item.Context.SuppressionProof;
        p=item.Context.Prepared;
        decision=table(item.UE,p.ReceiveStartSample, ...
            proof.Cancellation.CancelledAtSample, ...
            string(jsonencode(proof.Decision.DroppedSymbols0Based)), ...
            "srs_suppressed_for_actual_same_UE_PUCCH", ...
            string(jsonencode(proof)),false, ...
            'VariableNames',{'UEIndex','ReceiveStartSample','DecisionSample', ...
            'DroppedSRSSymbols0Based','Action','PhysicalSuppressionProofJSON','SRSReceiverExecuted'});
        state.ControlTrials.SRSResourceDecisions=localAppendCompatTable( ...
            sixgr.util.structGet(state.ControlTrials,'SRSResourceDecisions',table()),decision);
        localAppendRuntimeLog("INFO", ...
            "SRS suppressed before emission for actual UE PUCCH: ue=%d SRS=%s PUCCH=%s.", ...
            item.UE,char(proof.SRSObservationID),char(proof.PUCCHObservationID));
        continue;
    end
    if item.Kind=="SRS"
        state=localCompleteSharedSRS(state,item);
        continue;
    end
    if item.Kind=="SSBOccasion"
        state=sixgr.truth.SSBOccasionResultDelivery.complete(state,item);
        continue;
    end
    if item.Kind=="SIB1"
        state=sixgr.truth.SIB1ResultDelivery.complete(state,item);
        continue;
    end
    if item.Kind=="SSBArchive"
        % The full configured archive remains original evidence; it is not
        % another acquisition, beam selection, reference-filter or MIB event.
        [~,~,tx,~,post]=sixgr.truth.sharedObservationEvidence(item.Planes);
        p=context.Prepared;
        assert(post.StartSample==p.BroadcastStartSample && ...
            post.EndSampleExclusive==p.BroadcastStartSample+p.NumSamples, ...
            'sixgr:truth:SSBArchiveExtent','Preserve the entire original configured broadcast archive.');
        preview=sixgr.link.buildBroadcastWaveformPreview(tx,post,context.SNR, ...
            context.Frame,context.Slot,item.UE,context.ServingCell);
        preview=localAppendCompatTable(sixgr.util.structGet( ...
            state,'SharedBroadcastWaveformPreviewTable',table()),preview);
        state.SharedBroadcastWaveformPreviewTable=preview(max(1,height(preview)-4095):end,:);
        root=string(sixgr.util.structGet(context.Config,'run.rootRunFolder',''));
        assert(strlength(strtrim(root))>0,'sixgr:truth:SSBArchiveRootRequired', ...
            'Completed full broadcast evidence needs the original run output root.');
        receipt=struct('ObservationID',string(item.ID), ...
            'AcquisitionObservationID',context.AcquisitionObservationID, ...
            'AcquisitionWindowContract',context.AcquisitionWindowContract, ...
            'StartSample',post.StartSample,'EndSampleExclusive',post.EndSampleExclusive, ...
            'SampleRateHz',post.SampleRateHz,'CompletedAtSample',state.SharedWaveformStream.Events.NextSampleIndex, ...
            'ReceiverExecuted',false,'Planes',{{}});
        for plane=item.Planes
            archive=plane.Observation.archiveCompleted(root);
            receipt.Planes{end+1}=struct('ReceiverID',string(plane.ReceiverID),'Archive',archive);
        end
        receipts=sixgr.util.structGet(state,'SharedSSBArchiveReceipts',{});
        assert(~any(cellfun(@(r)r.ObservationID==receipt.ObservationID,receipts)), ...
            'sixgr:truth:DuplicateSSBArchive','A full capture is archived exactly once.');
        receipts{end+1,1}=receipt; state.SharedSSBArchiveReceipts=receipts;
        continue;
    end
    p=context.Prepared;
    [~,pre,tx,replay,post]=sixgr.truth.sharedObservationEvidence(item.Planes);
    ch=state.SharedWaveformStream.channelState(item.UE,"DL");
    if item.Kind=="PBCH"
        if ~logical(sixgr.util.structGet(context,'CellOwnedBroadcast',false))
            observed=sixgr.truth.buildObservedBroadcastREAllocation(p,tx,context.ServingCell);
            state.ObservedREAllocationTable=localAppendObservedREAllocation( ...
                sixgr.util.structGet(state,'ObservedREAllocationTable',table()),observed);
        end
        prototype=context.Prototype;
        prototype.RuntimeChannelReplay=replay;
        prototype.RuntimeDLChannelState=ch;
        prototype.RuntimeChannelStateUsed=true;
        prototype.PowerContext=p.PowerContext;
        options=struct('UseRuntimeChannel',true,'RuntimeSlot',context.Slot-1, ...
            'CandidateSSBIndices',localResolveActiveSSBurstSetIndices(context.Config,struct()), ...
            'SSBIndex',[],'WriteArtifacts',false,'RunFolder','','RunId','shared_runtime', ...
            'PhysicalMeasurementObservation',pre,'TransmitObservation',tx);
        if isfield(context,'AcquisitionWindowContract')
            options.AcquisitionWindowContract=context.AcquisitionWindowContract;
            options.CandidateSSBIndices=context.AcquisitionWindowContract.CandidateIndices;
        end
        [options.DesiredReferenceObservation,options.DesiredReferenceEvidence]= ...
            sixgr.truth.sharedLinkScoringObservation(item.Planes,p,context.DesiredReferencePlane);
        options.ReceiveElementBinding=state.SharedWaveformStream.Physical.receiveElementLayout( ...
            string(options.DesiredReferenceEvidence.ReceiverID));
        options.OriginalSSBPowerObservationBinding=struct('Planes',{item.Planes}, ...
            'DesiredReferencePlaneID',context.DesiredReferencePlane, ...
            'ReceiveBranchBinding',state.SharedWaveformStream.Physical.receiveBranchLayout( ...
                string(options.DesiredReferenceEvidence.ReceiverID)));
        [output,mibContexts]=sixgr.link.completeCellSearchBroadcast(p,post,prototype,options,tic);
        % Retain the actually completed broadcast observation even when no
        % cell is acquired. Do not put it into the data-grant preview table.
        preview=sixgr.link.buildBroadcastWaveformPreview(tx,post,context.SNR, ...
            context.Frame,context.Slot,item.UE,context.ServingCell);
        preview=localAppendCompatTable(sixgr.util.structGet( ...
            state,'SharedBroadcastWaveformPreviewTable',table()),preview);
        state.SharedBroadcastWaveformPreviewTable=preview(max(1,height(preview)-4095):end,:);
        % The common receiver completion retains each candidate's DL clock.
        [raw,~,recovery]=localCollectCoupledPBCHBeamSweep(context.Config,context.SNR,ch,context.Slot,output);
        trial=localAnnotateCoupledControlTrial(raw,context.Slot,context.Frame,item.UE,context.RNTI,"DL",context.ServingCell);
        trial.ObservationPurpose=repmat("initial_cell_search_pbch_acquisition",height(trial),1);
        trial=sixgr.truth.bindSharedRFExecutionEvidence(trial,item.Planes,true);
        trial.MeasurementClockEpoch=repmat(state.SharedWaveformStream.Physical.ConfigurationEpoch,height(trial),1);
        trial.ResultCompletedAtSample=repmat(state.SharedWaveformStream.Events.NextSampleIndex,height(trial),1);
        % Bind reference ownership to the frozen receiver configuration, not
        % whatever configuration is current when this capture is delivered.
        captureFilter=sixgr.rrc.resolvePreconnectionRSRPFilter(context.Config);
        trial.ReferenceConfigurationEpoch=repmat( ...
            sixgr.util.structGet(context.Config,'initial_access.configuration_epoch',NaN),height(trial),1);
        if ~isempty(fieldnames(captureFilter))
            trial.SSBPowerReferenceCaptureFilterConfigHash=repmat(string(captureFilter.ConfigHash),height(trial),1);
        end
        if ~isempty(fieldnames(recovery))
            recovery.ReferenceConfigurationEpoch=sixgr.util.structGet( ...
                context.Config,'initial_access.configuration_epoch',NaN);
            recovery.MeasurementClockEpoch=state.SharedWaveformStream.Physical.ConfigurationEpoch;
            recovery.OriginalServingCell=context.ServingCell;
        end
        if context.TrackingOnly
            trial.ObservationPurpose(:)="periodic_serving_ssb_beam_and_pathloss_tracking";
            trial.SSBMeasurementDeliveryMode=repmat("per_occasion",height(trial),1);
        end
        mibBinding=[]; timingBindings={};
        acquisitionMIB=sixgr.util.structGet(context,'AcquisitionMIBBinding',[]);
        timingRows=find(sixgr.truth.pbchAcquisitionAccepted(trial) & ...
            trial.PBCHStrictReceiverEvidenceOk==1);
        if ~context.TrackingOnly || ~isempty(acquisitionMIB)
            for timingRow=reshape(timingRows,1,[])
                candidate=find(double(output.CandidateSSBIndices)==trial.SSBIndex(timingRow));
                assert(isscalar(candidate) && numel(mibContexts)>=candidate && ...
                    isa(mibContexts{candidate},'sixgr.phy.broadcast.ReceivedMIBContext'), ...
                    'sixgr:truth:MissingSelectedReceivedMIB', ...
                    'Each accepted timing candidate must retain its own original received BCH context.');
                original=output.CandidateResults{candidate};
                timingBindings{end+1,1}=sixgr.truth.ReceivedSSBTimingDelivery.bindCompleted( ...
                    state,item,mibContexts{candidate},original.SIB1.ReceivedDLTimingReference,post,acquisitionMIB); %#ok<AGROW>
            end
        end
        selected=find(trial.SelectedBeamFlag & sixgr.truth.pbchAcquisitionAccepted(trial));
        if ~isempty(selected) && ~context.TrackingOnly
            assert(isscalar(selected),'sixgr:truth:AmbiguousReceivedMIBSelection', ...
                'One acquisition installs exactly one selected original received MIB.');
            candidate=find(cellfun(@(r)r.SSBIndex==trial.SSBIndex(selected),timingBindings));
            assert(isscalar(candidate), ...
                'sixgr:truth:MissingSelectedReceivedMIB', ...
                'Do not replace the selected candidate with the first candidate or a reconstructed MIB.');
            mibBinding=timingBindings{candidate}.OriginalBCHBinding;
        end
        state=sixgr.truth.BroadcastResultDelivery.enqueue( ...
            state,item.UE,trial,recovery,context.TrackingOnly,mibBinding,timingBindings);
    elseif item.Kind=="TRS"
        [desiredReference]=sixgr.truth.sharedLinkScoringObservation(item.Planes,p,context.DesiredReferencePlane);
        output=sixgr.link.completeTRSReception(p,post,replay,ch, ...
            'DesiredReferenceObservation',desiredReference);
        if output.Crash
            % A receiver exception has no measured result to publish. Keep
            % its cause visible instead of failing later on absent clocks.
            identifier=char(output.FailureIdentifier);
            if isempty(identifier), identifier='sixgr:truth:SharedTRSReceiverFailure'; end
            error(identifier,'%s',char(output.FailureReason));
        end
        state=sixgr.truth.recordSharedQCLTimingReference(state,p,post,output,item.UE,context.ServingCell);
        [raw,~,observed]=localCollectTRSTrials(context.Config,context.SNR,1,ch,output);
        trial=localAnnotateCoupledControlTrial(raw,context.Slot,context.Frame,item.UE,context.RNTI,"DL",context.ServingCell);
        trial=sixgr.truth.bindSharedRFExecutionEvidence(trial,item.Planes,true);
        trial.MeasurementClockEpoch=repmat(state.SharedWaveformStream.Physical.ConfigurationEpoch,height(trial),1);
        trial=sixgr.truth.DLMeasurementInstallation.stamp(state,trial,p.ReceiverConfig,item.UE,"TRS");
        state=sixgr.truth.TRSResultDelivery.enqueue(state,context.ServingCell,item.UE,trial,context.Config,observed);
    else
        error('sixgr:truth:MissingSharedReceiverReducer','No canonical row reducer for completed %s.',item.Kind);
    end
end
end

function [state,queuedUL,queued]=localPrepareSharedSRS(state,cfg,ue,snr,queuedUL)
queued=false; owner=state.SharedWaveformStream;
if owner.hasPending("SRS",ue) || ...
        ~isfield(state,'ConnectedULTimingByUE') || numel(state.ConnectedULTimingByUE)<ue || ...
        isempty(state.ConnectedULTimingByUE{ue})
    return;
end
if isfield(state,'SharedSRSResults') && any(cellfun(@(x)x.UE==ue,state.SharedSRSResults)), return; end
authority=state.ConnectedULTimingByUE{ue};
% This initial TAG has only received common BWPs. A later BWP/NTN timing
% reconfiguration needs its own received authority, not a scenario override.
common=state.UECommonCellConfigurationByUE{ue};
carrier=sixgr.phy.grid.makeCarrier(cfg);
assert(carrier.SubcarrierSpacing==common.InitialULBWP.SubcarrierSpacing_kHz, ...
    'sixgr:truth:ConnectedULTimingBWPChanged','Install received dedicated-BWP timing before changing UL numerology.');
for slot=state.CurrentSlot:state.CanonicalSlotsPerSweepPoint
    [~,allowed]=sixgr.truth.CoupledTruthRuntime.resolveSlotPartition(cfg,slot);
    if ~allowed, continue; end
    plan=sixgr.truth.CoupledTruthRuntime.futureULPlanningView(state,slot);
    if ~sixgr.truth.coupledSRSAttemptDue(plan,cfg,slot,ue), continue; end
    occupied=owner.Pending(string({owner.Pending.Kind})=="SRS");
    count=sum(arrayfun(@(x)x.Context.Slot==slot,occupied));
    if count>=cfg.phy.srs.maxUEsPerSlot, continue; end
    [cfgSRS,~]=sixgr.truth.GrantPreparation.applyCoupledRuntimeUserContext(cfg,plan,ue,"UL");
    [powerAdmitted,powerDecision]=sixgr.truth.resolveSharedSRSPowerAdmission(plan,cfgSRS,ue,slot);
    state.ControlTrials.SRSResourceDecisions=localAppendCompatTable( ...
        sixgr.util.structGet(state.ControlTrials,'SRSResourceDecisions',table()),powerDecision);
    if ~powerAdmitted
        localAppendRuntimeLog("INFO", ...
            "SRS preparation deferred: ue=%d decision_slot=%d source_slot=%d reference=%s reason=%s; no waveform or power state prepared.", ...
            ue,state.CurrentSlot,slot,powerDecision.PowerReferenceRS,powerDecision.PowerReferenceStatus);
        % Later target slots cannot gain new receiver knowledge in this
        % planning call. Retry after the live owner publishes a fresh RS.
        return;
    end
    cfgSRS.SharedULTimingContext=authority;
    if string(sixgr.util.structGet(cfgSRS, ...
            'rf.frontend.ul_power_control.srs.adjustment_state',''))=="same_as_pusch"
        states=sixgr.util.structGet(state,'SharedUEULPowerControlStates',{});
        if numel(states)<ue || isempty(states{ue})
            states{ue}=sixgr.link.ReceivedULPowerControlState(cfgSRS);
        end
        state.SharedUEULPowerControlStates=states;
        cfgSRS.phy.srs.receivedPowerControlState=states{ue};
    end
    nominal=sixgr.phy.frame.slotStartSample(carrier,slot-1,owner.SampleRateHz);
    timing=sixgr.phy.ra.sharedULStageTiming(cfgSRS,nominal/owner.SampleRateHz,owner.SampleRateHz,1, ...
        authority.ReceivedRARTiming.NTA_Tc);
    if min(timing.TransmitStartSample,timing.ReceiveStartSample)<owner.Events.NextSampleIndex || ...
            timing.TransmitStartSample<authority.TimingAdvanceEffectiveAtSample
        continue; % The complete TX origin cannot precede available knowledge.
    end
    [collision,decisions]=localResolveCoupledSRSPUSCHResourceDecision(cfgSRS,queuedUL,table(),slot,ue);
    if collision
        [state,queuedUL,decisions,collision]=sixgr.truth.resolveSRSPUSCHRuntimePriority( ...
            state,queuedUL,decisions,cfgSRS,slot,ue);
    end
    state.ControlTrials.SRSResourceDecisions=localAppendCompatTable( ...
        sixgr.util.structGet(state.ControlTrials,'SRSResourceDecisions',table()),decisions);
    if collision, continue; end
    % This parameter is metadata only on the shared physical path. The
    % receiver's thermal-noise owner, not a large-scale SINR prediction,
    % determines the actual noise samples.
    args={'SNR_dB',snr,'TrialIndex',slot+1,'SlotIndex',slot, ...
        'TimingAdvanceSamples',authority.ReceivedRARTiming.Samples};
    output=sixgr.link.runSRSChannelEstimation(cfgSRS,args{:},'PrepareOnly',true);
    assert(isfield(output,'PreparedTransmission'), ...
        'sixgr:truth:SharedSRSPreparationFailed','SRS preparation failed: %s',output.Notes);
    if isfield(cfgSRS.phy.pusch,'priorityIndex')
        pendingPUSCH=owner.Pending( ...
            string({owner.Pending.Kind})=="PUSCH" & ...
            [owner.Pending.UE]==ue);
        for pendingIndex=1:numel(pendingPUSCH)
            sixgr.phy.frame.validatePreparedPriorityZeroPUSCHSRS( ...
                output.PreparedTransmission, ...
                pendingPUSCH(pendingIndex).Context.Prepared);
        end
    end
    context=struct('Config',cfgSRS,'Slot',slot,'Frame',1+floor((slot-1)*state.SlotDuration_s/.01), ...
        'RNTI',sixgr.truth.CoupledRadioIdentity.dataRNTI(cfgSRS,ue,"UL"),'ServingCell',state.CurrentServingIdx(ue), ...
        'SNR',snr,'Arguments',{args},'DecisionSlot',state.CurrentSlot);
    owner.queueUplinkControl(ue,output.PreparedTransmission,context);
    queued=true;
    localAppendRuntimeLog("INFO","Queued full SRS waveform: ue=%d decision_slot=%d source_slot=%d tx_start=%d rx_start=%d.", ...
        ue,state.CurrentSlot,slot,output.PreparedTransmission.StartSample,output.PreparedTransmission.ReceiveStartSample);
    return;
end
end

function state=localCompleteSharedSRS(state,item)
c=item.Context; p=c.Prepared;
[post,pre,tx,replay,receiver]=sixgr.truth.sharedObservationEvidence(item.Planes,p);
ch=state.SharedWaveformStream.directionalChannelState(item.UE,"UL");
if isfield(ch,'Obj') && isobject(ch.Obj) && isprop(ch.Obj,'DelayProfile') && replay.ChannelFadingApplied
    replay.ChannelModelApplied=char(ch.Obj.DelayProfile);
end
input=struct('Prepared',p,'Observation',receiver,'PhysicalMeasurementObservation',pre, ...
    'TransmitterObservation',tx,'Replay',replay,'ChannelState',ch);
[desiredReference,referenceEvidence]=sixgr.truth.sharedLinkScoringObservation( ...
    item.Planes,p,c.DesiredReferencePlane);
input.DesiredReferenceObservation=desiredReference;
input.DesiredReferenceEvidence=referenceEvidence;
% This is the actual composite link waveform, not a per-port channel
% matrix. Do not feed it into the legacy branch-averaged pilot-ratio NMSE
% helper and misrepresent that number as full channel-estimator accuracy.
[state,output]=sixgr.truth.receiveSharedSRSMeasurement(state,item,input);
receivedClock=sixgr.truth.retainReceivedSRSTimingReference(p,receiver,output);
if ~isempty(receivedClock)
    state=sixgr.truth.storeReceivedULTimingReference(state,item.UE,receivedClock);
end
[raw,~,observed]=localCollectSRSTrials(c.Config,c.SNR,1,ch,c.Slot,output);
trial=localAnnotateCoupledControlTrial(raw,c.Slot,c.Frame,item.UE,c.RNTI,"UL",c.ServingCell);
trial=sixgr.truth.bindSharedRFExecutionEvidence(trial,item.Planes,true);
trial.RuntimeTransportMode(:)="shared_physical_stream_SRS_received_completion";
trial.ObservationStartSample=post.StartSample;
trial.ObservationEndSampleExclusive=post.EndSampleExclusive;
trial.ObservationSampleRateHz=post.SampleRateHz;
trial.MeasurementClockEpoch=state.SharedWaveformStream.Physical.ConfigurationEpoch;
trial.ObservationCompletionTime_s=post.EndSampleExclusive/post.SampleRateHz;
trial.ObservationCoverageSource="complete_contiguous_received_sample_buffer";
trial.TransmitStartSample=p.StartSample;
trial.TransmitEndSampleExclusive=p.EndSampleExclusive;
trial.TransmitPreparationDecisionSlot=c.DecisionSlot;
trial=sixgr.truth.bindReceivedSRSTimingEvidence( ...
    trial,output.ReceiveTiming,p.PhysicalTiming);
% Independent same-execution arrival scoring is attached after acquisition;
% it is never an input to the practical SRS timing/rank/TPMI receiver.
trial=sixgr.truth.bindSRSArrivalTimingReference(trial,item.Planes,p.PhysicalTiming);
trial.ReceiverGainCompensationApplied=replay.ReceiverGainCompensation.Applied;
trial.DesiredLinkScoringAvailable=true;
trial.DesiredLinkScoringSource=referenceEvidence.Source;
trial.DesiredLinkScoringScope=referenceEvidence.Scope;
trial.DesiredLinkScoringLinkID=referenceEvidence.LinkID;
trial.DesiredLinkScoringAdditionalChannelExecutions=referenceEvidence.AdditionalChannelExecutions;
trial.DesiredLinkScoringChannelMatrixReference=referenceEvidence.ChannelMatrixReference;
trial.AppliedChannelReferenceSegmentCount=0;
trial.AppliedChannelReferenceSource="same_executed_desired_link_waveform_post_decode_SRS_pilot_reference";
trial.AppliedChannelReferenceUsedByReceiver=false;
trial=sixgr.truth.bindSharedSRSNMSEEvidence(trial,output);
% Keep lossless pairs outside repeated raw-table JSON/checkpoint state.
% These samples are scoring-only and never consumed by SRS rank/TPMI/CQI.
trial=sixgr.report.retainControlEVMPairs( ...
    c.Config.run.rootRunFolder,trial,output.PilotEVMPairs);
trial.ReceivedRARTimingAdvanceCommand=c.Config.SharedULTimingContext.ReceivedRARTiming.Command;
trial.TimingAdvanceEffectiveAtSample=c.Config.SharedULTimingContext.TimingAdvanceEffectiveAtSample;
trial.TimeAlignmentTimerCommon=c.Config.SharedULTimingContext.TimeAlignmentTimerCommon;
trial.RuntimeStateUpdated=false;
trial.ObservationDeliverySlot=NaN;
trial.ObservationDeliveryTime_s=NaN;
trial.ObservationDeliverySource="not_yet_delivered_to_scheduler";
% Publish the already executed uplink coefficients only after the practical
% SRS receiver has completed. Scoring captures are not receiver estimates.
if logical(sixgr.util.structGet(c.Config,'outputs.phySignalDiagnosticEnabled',false)) && ...
        (logical(ch.UseFading) || sixgr.channel.IdentityAWGNRuntime.isState(ch))
    trial=sixgr.truth.exportSharedScoringWaveformObservation( ...
        c.Config.run.rootRunFolder,trial,item.Planes,p,c.DesiredReferencePlane);
end
state.ControlTrials.SRS=localAppendCompatTable(state.ControlTrials.SRS,trial);
state.ObservedREAllocationTable=localAppendObservedREAllocation( ...
    sixgr.util.structGet(state,'ObservedREAllocationTable',table()),observed);
state.LastSRSSlotByUE(item.UE)=c.Slot;
if ~isfield(state,'SharedSRSResults'), state.SharedSRSResults=cell(0,1); end
state.SharedSRSResults{end+1,1}=struct('UE',item.UE,'Row',height(state.ControlTrials.SRS), ...
    'Trial',trial,'ServingCell',c.ServingCell);
sixgr.truth.exportSharedULControlObservation(c.Config.run.rootRunFolder,c.Config,p,item.Planes,output);
localAppendRuntimeLog("INFO","Received shared SRS: ue=%d slot=%d samples=[%d,%d) status=%s timing=%g NMSE=%g reason=%s.", ...
    item.UE,c.Slot,post.StartSample,post.EndSampleExclusive,trial.Status, ...
    trial.SRSReceiveTimingOffset_samples,trial.NMSE_dB,trial.FailureReason);
end

function state=localDeliverSharedSRSResults(state)
if ~isfield(state,'SharedSRSResults') || isempty(state.SharedSRSResults), return; end
now=(state.CurrentSlot-1)*state.SlotDuration_s;
keep=true(numel(state.SharedSRSResults),1);
for k=1:numel(keep)
    item=state.SharedSRSResults{k}; trial=item.Trial;
    if trial.ObservationCompletionTime_s>now, continue; end
    assert(state.CurrentServingIdx(item.UE)==item.ServingCell, ...
        'sixgr:truth:SharedSRSOwnerChanged','Censor old-cell SRS explicitly before consuming it in a new cell.');
    trial.ObservationDeliverySlot=state.CurrentSlot;
    trial.ObservationDeliveryTime_s=now;
    trial.ObservationDeliverySource="canonical_slot_start_after_complete_received_window";
    trial=sixgr.truth.bindDeliveredReferenceClock(state,trial);
    state=sixgr.truth.CoupledTruthRuntime.applySRSTrial(state,item.UE,trial);
    trial.RuntimeStateUpdated=true;
    % Update the measured row once. Final-slot evidence is published even
    % when no subsequent scheduler decision consumes it.
    for name=string(trial.Properties.VariableNames)
        if ~ismember(name,string(state.ControlTrials.SRS.Properties.VariableNames))
            state.ControlTrials.SRS.(name)=localDefaultColumnLike(trial,name,height(state.ControlTrials.SRS));
        end
        state.ControlTrials.SRS(item.Row,name)=trial(:,name);
    end
    keep(k)=false;
end
state.SharedSRSResults=state.SharedSRSResults(keep);
end

function state = localDeliverCoupledTRSResults(state)
[state,ready] = sixgr.truth.TRSResultDelivery.takeAvailable(state);
for k = 1:numel(ready)
    item = ready(k);
    serving = double(sixgr.util.structGet(state,"CurrentServingIdx",[]));
    if item.UEIndex>numel(serving) || serving(item.UEIndex)~=item.ServingCell
        state = sixgr.truth.TRSResultDelivery.censor(state,item, ...
            "serving_cell_changed_before_trs_delivery");
        continue;
    end
    state = localCommitCoupledTRSTrial(state,item.Trial,item.ServingCell, ...
        item.Config,item.UEIndex,item.ObservedRE);
end
end

function state = localCommitCoupledTRSTrial(state,trsT,servingCell,cfgU,ueIdx,observedRET)
if isfield(state,'SharedWaveformStream') && ...
        isa(state.SharedWaveformStream,'sixgr.truth.CoupledWaveformStream')
    trsT=sixgr.truth.bindDeliveredReferenceClock(state,trsT);
end
state = sixgr.truth.CoupledTruthRuntime.applyTRSTrial(state, servingCell, trsT);
[operational,authorityStatus]=sixgr.truth.DLMeasurementInstallation.eligible(state,ueIdx,trsT,"TRS");
if ~operational
    % Keep the original measured values, not previous tracking-state values.
    % This diagnostic completion neither warms nor invalidates the receiver.
    trsT.TraceRole="received_TRS_diagnostic_without_operational_authority";
    trsT.RuntimeStateUpdated=false;
    trsT.DLMeasurementAuthorityEligible=false;
    trsT.DLMeasurementAuthorityStatus=authorityStatus;
    state.ControlTrials.TRS=localAppendCompatTable(state.ControlTrials.TRS,trsT);
    state.ObservedREAllocationTable=localAppendObservedREAllocation( ...
        sixgr.util.structGet(state,'ObservedREAllocationTable',table()),observedRET);
    return;
end
trsContext = sixgr.truth.CoupledTruthRuntime.resolveTRSRuntimeContextRuntime(state, cfgU, ueIdx, servingCell);
trsT.ServingCell = repmat(servingCell, height(trsT), 1);
trsT.TraceRole = repmat("runtime_shared_receiver_tracking_state_update", height(trsT), 1);
trsT.TRSGatingActive = repmat(logical(sixgr.util.structGet(state.ControlGating, "TRSRequired", false)), height(trsT), 1);
trsT.TRSValidityState = repmat(trsContext.TRSValidityState, height(trsT), 1);
trsT.TrackingEligibility = repmat(trsContext.TrackingEligibility, height(trsT), 1);
trsT.LastSuccessfulTRSSlot = repmat(trsContext.LastSuccessfulTRSSlot, height(trsT), 1);
trsT.LastEstimatedTRSDopplerHz = repmat(trsContext.LastEstimatedTRSDopplerHz, height(trsT), 1);
trsT.TRSAgeSlots = repmat(double(trsContext.TRSAgeSlots), height(trsT), 1);
trsT.RuntimeStateUpdated = true(height(trsT), 1);
trsT.RuntimeStateConsumer = repmat(string(trsContext.TRSReceiverConsumerType), height(trsT), 1);
trsT.TrackingStateSource = repmat(string(trsContext.TRSStateSource), height(trsT), 1);
trsT.TRSStateSource = repmat(string(trsContext.TRSStateSource), height(trsT), 1);
trsT.TRSRuntimeConsumer = repmat(string(trsContext.TRSRuntimeConsumer), height(trsT), 1);
trsT.TRSInfluencedDecision = repmat(logical(trsContext.TRSInfluencedDecision), height(trsT), 1);
trsT.TRSInfluenceDefinition = repmat(string(trsContext.TRSInfluenceDefinition), height(trsT), 1);
trsT.TRSReceiverIntegrationStatus = repmat(string(trsContext.TRSReceiverIntegrationStatus), height(trsT), 1);
trsT.TRSReceiverIntegrationBlocker = repmat(string(trsContext.TRSReceiverIntegrationBlocker), height(trsT), 1);
trsT.TRSProcessed = repmat(logical(trsContext.TRSProcessed), height(trsT), 1);
trsT.TRSReceiverConsumerType = repmat(string(trsContext.TRSReceiverConsumerType), height(trsT), 1);
trsT.TRSTrackingStateBefore = repmat(string(trsContext.TRSTrackingStateBefore), height(trsT), 1);
trsT.TRSTrackingStateAfter = repmat(string(trsContext.TRSTrackingStateAfter), height(trsT), 1);
trsT.TRSTrackingUpdateTime_s = repmat(double(trsContext.TRSTrackingUpdateTime_s), height(trsT), 1);
trsT.TRSAssociatedCell = repmat(double(trsContext.TRSAssociatedCell), height(trsT), 1);
trsT.TRSUpdateOutcome = repmat(string(trsContext.TRSUpdateOutcome), height(trsT), 1);
trsT.TRSChannelTrackingFreshnessState = repmat(string(trsContext.TRSChannelTrackingFreshnessState), height(trsT), 1);
trsT.TRSFrequencyTrackingState = repmat(string(trsContext.TRSFrequencyTrackingState), height(trsT), 1);
trsT.TRSTimingTrackingState = repmat(string(trsContext.TRSTimingTrackingState), height(trsT), 1);
trsT.TRSTimingEstimateAvailable = repmat(logical(trsContext.TRSTimingEstimateAvailable), height(trsT), 1);
trsT.TRSTimingEstimate_samples = repmat(double(trsContext.TRSTimingEstimate_samples), height(trsT), 1);
trsT.TRSCFOEstimateAvailable = repmat(logical(trsContext.TRSCFOEstimateAvailable), height(trsT), 1);
trsT.TRSEstimatedCFO_Hz = repmat(double(trsContext.TRSEstimatedCFO_Hz), height(trsT), 1);
trsT.TRSRuntimeEvidenceSource = repmat(string(trsContext.TRSRuntimeEvidenceSource), height(trsT), 1);
state.ControlTrials.TRS = localAppendCompatTable(state.ControlTrials.TRS, trsT);
state.ObservedREAllocationTable = localAppendObservedREAllocation( ...
    sixgr.util.structGet(state,"ObservedREAllocationTable",table()),observedRET);
end


function state = localDeliverCoupledBroadcastResults(state)
% No primary PBCH row, beam measurement or SIB1 authority is published at
% the start of a multi-slot capture. Preserve the source slot in each row;
% the separate delivery fields describe when consumers can use its result.
state=sixgr.truth.SSBOccasionResultDelivery.deliver(state);
[state,ready] = sixgr.truth.BroadcastResultDelivery.takeAvailable(state);
for k=1:numel(ready)
    item=ready(k);
    if ~ismember("ServingCell",string(item.Trial.Properties.VariableNames)) || ...
            any(~isfinite(item.Trial.ServingCell)) || ...
            any(item.Trial.ServingCell~=state.CurrentServingIdx(item.UEIndex))
        error("sixgr:truth:BroadcastServingContextChangedBeforeDelivery", ...
            "UE %d broadcast reception must not acquire or update a different serving cell at delivery.", ...
            item.UEIndex);
    end
    state.ControlTrials.PBCH=localAppendCompatTable( ...
        state.ControlTrials.PBCH,item.Trial);
    if item.TrackingOnly
        state=sixgr.truth.CoupledTruthRuntime.applyServingSSBTrackingTrial( ...
            state,item.UEIndex,item.Trial);
    else
        state=sixgr.truth.CoupledTruthRuntime.applyPBCHTrial( ...
            state,item.UEIndex,item.Trial);
        if isfield(item,'MIBBinding') && ~isempty(item.MIBBinding)
            state=sixgr.truth.ReceivedMIBDelivery.deliver(state,item.MIBBinding);
            [current,~,binding]=sixgr.truth.ReceivedMIBDelivery.current(state,item.UEIndex);
            if current && binding.BindingSHA256==item.MIBBinding.BindingSHA256
                state=sixgr.truth.installReceivedSIB1Recovery( ...
                    state,item.UEIndex,item.Recovery,state.CurrentSlot,binding);
            end
        else
            state=localStoreDecodedSIB1Recovery( ...
                state,item.UEIndex,item.Recovery,state.CurrentSlot);
        end
    end
    for timingIndex=1:numel(item.TimingBindings)
        state=sixgr.truth.ReceivedSSBTimingDelivery.deliver( ...
            state,item.TimingBindings{timingIndex},item.Trial);
    end
end
end

function state = localStoreDecodedSIB1Recovery(state, ueIdx, recovery, slotIdx)
state=sixgr.truth.installReceivedSIB1Recovery(state,ueIdx,recovery,slotIdx);
end

function recovery = localDecodedSIB1RecoveryForUE(state, ueIdx)
recovery = struct();
ueIdx = round(double(ueIdx));
items = sixgr.util.structGet(state, "DecodedSIB1RecoveryByUE", {});
if iscell(items) && isfinite(ueIdx) && ueIdx >= 1 && ueIdx <= numel(items) && ...
        isstruct(items{ueIdx})
    recovery = items{ueIdx};
end
end

function tf = localRequireDecodedSIB1ForRA(cfg)
sib1WaveformRequired = localConfigBool(cfg, ...
    ["validation.sib1_and_initial_access.sib1_decode_from_waveform_required", ...
     "lls6g.sib1_and_initial_access.sib1_decode_from_waveform_required", ...
     "initial_access.sib1.decode_from_waveform_required"], false);
tf = localShouldRunFourStepRAForPRACH(cfg) && sib1WaveformRequired;
end

function tf = localConfigBool(cfg, paths, defaultValue)
tf = logical(defaultValue);
paths = string(paths(:));
for i = 1:numel(paths)
    raw = sixgr.util.structGet(cfg, paths(i), []);
    if isempty(raw)
        continue;
    end
    if islogical(raw) || isnumeric(raw)
        tf = logical(raw(1));
    else
        token = lower(strtrim(string(raw(1))));
        tf = any(token == ["1","true","yes","on","enabled"]);
    end
    return;
end
end

function numSubframes = localResolvePBCHObservationSubframes(cfg)
numSubframes = double(sixgr.util.structGet(cfg, ...
    "phy.ssb.pbchObservationSubframes", ...
    sixgr.util.structGet(cfg, "lls6g.control.pbchObservationSubframes", NaN)));
if ~(isfinite(numSubframes) && numSubframes >= 1)
    % FR1 NR cell-search acquisition only needs one valid SS burst-set
    % observation window; keep this as an explicit lab default rather than
    % stretching every UE PBCH attempt to a full 10-subframe capture.
    numSubframes = 5;
end
numSubframes = max(1, round(double(numSubframes)));
end

function cfgOut = localApplyPBCHSSBBeamContext(cfgIn, slotIdx, ueIdx)
cfgOut = cfgIn;
ssbIndex = localResolveRuntimePBCHSSBIndex(cfgIn, slotIdx, ueIdx);
if isfinite(ssbIndex)
    cfgOut = sixgr.util.structSet(cfgOut, "phy.ssb.runtimeSSBIndex", double(ssbIndex));
end
end

function ssbIndex = localResolveRuntimePBCHSSBIndex(cfg, slotIdx, ueIdx)
[isOccasion, occasion] = sixgr.truth.isActiveSSBOccasion(cfg, slotIdx);
if ~isOccasion
    ssbIndex = NaN;
    return;
end
indices = double(sixgr.util.structGet(occasion, "ActiveSSBIndices0Based", []));
indices = indices(isfinite(indices));
if isempty(indices)
    error("sixgr:truth:MissingActiveSSBIndex", ...
        "An active SSB carrier slot must expose at least one active SSB candidate index.");
end
% A receiving UE index is not a cell-transmitter beam schedule. Preserve
% the configured cell reference; the broadcast producer separately emits
% the configured SI beam set and each UE independently searches the burst.
ssbIndex=double(sixgr.util.structGet(cfg,'phy.ssb.runtimeSSBIndex',indices(1)));
assert(isscalar(ssbIndex) && ismember(ssbIndex,indices), ...
    'sixgr:truth:InactiveCellBroadcastSSB','The configured cell reference SSB must be active.');
end

function ssbIndex = localResolvePBCHSSBIndex(cfg, trialIdx)
explicit = double(sixgr.util.structGet(cfg, "phy.ssb.runtimeSSBIndex", ...
    sixgr.util.structGet(cfg, "phy.ssb.SSBIndex", NaN)));
beamCount = localResolveSSBBeamCount(cfg);
if isfinite(explicit)
    ssbIndex = round(explicit);
else
    ssbIndex = mod(max(0, round(double(trialIdx)) - 1), beamCount);
end
lmax = double(sixgr.util.structGet(cfg, "phy.ssb.Lmax", beamCount));
if ~(isfinite(lmax) && lmax >= 1)
    lmax = beamCount;
end
ssbIndex = max(0, min(round(lmax) - 1, ssbIndex));
end

function beamCount = localResolveSSBBeamCount(cfg)
beamCount = double(sixgr.util.structGet(cfg, "phy.ssb.beamCount", ...
    sixgr.util.structGet(cfg, "phy.ssb.nBeams", ...
    sixgr.util.structGet(cfg, "random_access.ssb_beam_count", ...
    sixgr.util.structGet(cfg, "signals_and_channels_common.ssb.beam_count", ...
    sixgr.util.structGet(cfg, "mimo_and_beam_management.ssb_beam_count", ...
    sixgr.util.structGet(cfg, "phy.ssb.Lmax", 1)))))));
if ~(isfinite(beamCount) && beamCount >= 1)
    beamCount = 1;
end
lmax = double(sixgr.util.structGet(cfg, "phy.ssb.Lmax", beamCount));
if isfinite(lmax) && lmax >= 1
    beamCount = min(beamCount, round(lmax));
end
beamCount = max(1, round(double(beamCount)));
end

function [state, T, correlationTraceT, raEvidenceTables] = ...
        localCollectCoupledPRACHTrials( ...
        state, cfg, ueIdx, snr_dB, slotIdx)
if localShouldRunFourStepRAForPRACH(cfg) || localHasPendingRA(state, ueIdx)
    [state, T, correlationTraceT, raEvidenceTables] = ...
        localAdvanceCoupledRAAttempt(state, cfg, ueIdx, snr_dB, slotIdx);
    return;
end
cfg = localApplyMeasuredSSBSelectionForRA(cfg, state, ueIdx);
[state, dlState] = ...
    sixgr.truth.CoupledTruthRuntime.acquireRuntimeChannelStateForControl( ...
    state, cfg, ueIdx, "DL");
[state, ulState] = ...
    sixgr.truth.CoupledTruthRuntime.acquireRuntimeChannelStateForControl( ...
    state, cfg, ueIdx, "UL");
decodedSIB1 = localDecodedSIB1RecoveryForUE(state, ueIdx);
[T, correlationTraceT, raEvidenceTables, dlState, ulState, observedRET] = ...
    localCollectPRACHTrials( ...
    cfg, snr_dB, 1, slotIdx, dlState, ulState, decodedSIB1);
state.ObservedREAllocationTable = localAppendObservedREAllocation( ...
    sixgr.util.structGet(state, "ObservedREAllocationTable", table()), ...
    observedRET);
state = sixgr.truth.CoupledTruthRuntime.commitRuntimeChannelState( ...
    state, dlState);
state = sixgr.truth.CoupledTruthRuntime.commitRuntimeChannelState( ...
    state, ulState);
end

function tf = localHasPendingRA(state, ueIdx)
queue = sixgr.util.structGet(state, "PendingRAAttempts", {});
tf = iscell(queue) && ueIdx <= numel(queue) && ~isempty(queue{ueIdx});
end

function [state, T, correlationTraceT, evidence] = ...
        localAdvanceCoupledRAAttempt(state, cfg, ueIdx, snr_dB, slotIdx)
T = table();
correlationTraceT = table();
evidence = localEmptyRAEvidenceTables();
if ~(isscalar(slotIdx) && isfinite(slotIdx) && slotIdx >= 1 && slotIdx == fix(slotIdx))
    error("sixgr:truth:InvalidRARuntimeSlot", "Coupled RA requires a positive one-based runtime slot.");
end
pending = localHasPendingRA(state, ueIdx);
if pending
    attempt = state.PendingRAAttempts{ueIdx};
    cfg = attempt.Config;
else
    cfg = localApplyMeasuredSSBSelectionForRA(cfg, state, ueIdx);
    attempt = struct("Config", cfg, "StartSlot", slotIdx, "SNR_dB", snr_dB, ...
        "PublishedStageRows", 0, "PublishedRARObservations",0,"PublishedRARCandidates",0, ...
        "PublishedRARFields",0,"Continuation", struct());
end
% Pre-scheduling observes completed samples strictly before the current
% slot, not samples from the slot whose grants are about to be decided.
receiveThrough = (slotIdx - 1) * sixgr.time.slotDurationSec(cfg);
shared=isfield(state,'SharedWaveformStream');
if shared
    receiveThrough=double(localSharedNowTicks(state))/double(sixgr.phy.frame.AbsoluteTime.TicksPerSecond);
    if pending
        if isempty(sixgr.util.structGet(attempt,'Received',[])), return; end
        ra=attempt.Received; checkpoint=attempt.Continuation;
        attempt.Received=[];
    else
        cfg=sixgr.util.structSet(cfg,'random_access.use_runtime_channel',true);
        common=state.UECommonCellConfigurationByUE{ueIdx};
        % The caller admitted the selected received beam BEFORE mutating
        % retry/attempt/LastPRACH state. Revalidate that exact frozen operand;
        % do not substitute the common SI's initial acquisition-beam clock.
        [timingAvailable,~,timing]=sixgr.truth.ReceivedSSBTimingDelivery.current( ...
            state,ueIdx,cfg,cfg.random_access.associated_ssb_index);
        assert(timingAvailable && isfield(cfg,'SharedRATimingBinding') && ...
            isfield(cfg,'SharedULTimingContext') && ...
            isequaln(cfg.SharedRATimingBinding,timing) && ...
            common.ServingCell==state.CurrentServingIdx(ueIdx) && ...
            isequaln(cfg.SharedULTimingContext.DLReference,timing.ReceivedDLTimingReference) && ...
            isequaln(cfg.SharedULTimingContext.Offset,common.ULTimingAdvanceOffset), ...
            'sixgr:truth:ULTimingReferenceIdentity', ...
            'RA must retain the selected-beam timing and received common offset admitted by its caller.');
        attempt.Config=cfg;
        if ~isfield(state,'RARetryByUE'), state.RARetryByUE=cell(numel(state.AccessState),1); end
        if isempty(state.RARetryByUE{ueIdx})
            validateattributes(cfg.run.seed,{'numeric'},{'scalar','integer','nonnegative','finite'});
            key="cell_"+state.CurrentServingIdx(ueIdx)+"_ue_"+ueIdx;
            seed=sixgr.lls.deterministicSeed(cfg.run.seed,key,1,1,"RA_BACKOFF");
            state.RARetryByUE{ueIdx}=sixgr.mac.ra.RARetryState(seed);
        end
        selected=cfg.random_access.associated_ssb_index;
        validateattributes(selected,{'numeric'},{'scalar','integer','nonnegative','finite'});
        reference="cell_"+state.CurrentServingIdx(ueIdx)+"/SSB_"+selected;
        % Current licensed CBRA path has no lower-layer LBT failure or
        % ramp-suspension indication. Such indications must be explicit inputs
        % when channel-access/preamble cancellation is integrated.
        retry=state.RARetryByUE{ueIdx}.prepare(reference,localSharedNowTicks(state),false,false);
        dlState=state.SharedWaveformStream.directionalChannelState(ueIdx,"DL");
        ulState=state.SharedWaveformStream.directionalChannelState(ueIdx,"UL");
        [prepared,checkpoint]=sixgr.phy.ra.runFourStepRA(cfg, ...
            'RunFolder',cfg.run.rootRunFolder,'RunId',"shared_ra_ue"+ueIdx+"_slot"+slotIdx, ...
            'UEId',ueIdx,'RuntimeSlot',slotIdx,'WriteArtifacts',false, ...
            'AttemptId',retry.TransmissionCounter,'PreamblePowerRampingCounter',retry.PowerRampingCounter, ...
            'RuntimeIntegrationMode','shared_physical_waveform_stream', ...
            'UseRuntimeChannel',true,'RequireRuntimeStageWaveforms',true, ...
            'AllowRuntimeStageWaveformComposition',false, ...
            'SIB1Recovery',localDecodedSIB1RecoveryForUE(state,ueIdx), ...
            'RequireDecodedSIB1',localRequireDecodedSIB1ForRA(cfg), ...
            'InitialDLChannelState',dlState,'InitialULChannelState',ulState, ...
            'StageAction','prepare_next_stage','ReceiveThroughTime_s',receiveThrough);
        state.RARetryByUE{ueIdx}=retry.arm(checkpoint.RAConfig);
        attempt.Continuation=checkpoint; attempt.Received=[];
        if ~isfield(state,'PendingRAAttempts'), state.PendingRAAttempts=cell(numel(state.AccessState),1); end
        state.PendingRAAttempts{ueIdx}=attempt; state.AccessState(ueIdx)="pending";
        state.SharedWaveformStream.armRARWindow(ueIdx,checkpoint.RAConfig);
        state.SharedWaveformStream.queueRA(ueIdx,prepared.PreparedTransmission,struct('Config',cfg));
        return;
    end
else
[state, dlState] = sixgr.truth.CoupledTruthRuntime.acquireRuntimeChannelStateForControl(state, cfg, ueIdx, "DL");
[state, ulState] = sixgr.truth.CoupledTruthRuntime.acquireRuntimeChannelStateForControl(state, cfg, ueIdx, "UL");
if pending
    [ra, checkpoint] = sixgr.truth.CoupledTruthRuntime.runFourStepRARuntime(cfg, ...
        "Continuation", attempt.Continuation, "RuntimeSlot", slotIdx, ...
        "ReceiveThroughTime_s", receiveThrough, ...
        "InitialDLChannelState", dlState, "InitialULChannelState", ulState);
else
    decodedSIB1 = localDecodedSIB1RecoveryForUE(state, ueIdx);
    [ra, ok, failure, checkpoint] = localRunFourStepRAForPRACHTrial(cfg, 1, ...
        slotIdx, snr_dB, dlState, ulState, decodedSIB1, receiveThrough);
    if ~ok
        error("sixgr:truth:RAAttemptInitializationFailed", "%s", failure);
    end
end
dlState = sixgr.util.structGet(ra, "RuntimeDLChannelState", dlState);
ulState = sixgr.util.structGet(ra, "RuntimeULChannelState", ulState);
state = sixgr.truth.CoupledTruthRuntime.commitRuntimeChannelState(state, dlState);
state = sixgr.truth.CoupledTruthRuntime.commitRuntimeChannelState(state, ulState);
end
stages = sixgr.util.structGet(ra, "RuntimeStageRows", table());
previousCount = attempt.PublishedStageRows;
if height(stages) < previousCount
    error("sixgr:truth:RAStageEvidenceRegressed", "An RA continuation lost previously received stage rows.");
end
terminal = isempty(fieldnames(checkpoint));
% Receiver completion, not final attachment, publishes Msg2/3/4 evidence.
% Exclude already published physical trials during finalization as well.
completedTables=sixgr.truth.takeUnpublishedRAStageEvidence(ra,previousCount,terminal);
evidence=localAppendRAEvidenceTables(evidence,completedTables);
% Only append newly executed stages; finalization must not duplicate the
% earlier live waveform rows already committed for this attempt.
evidence.ra_runtime_stage_waveforms = stages(previousCount+1:end, :);
for mapping={ ...
        {'RARMonitoringObservations','rar_monitoring_observations','PublishedRARObservations'}, ...
        {'RARMonitoringCandidates','rar_monitoring_candidates','PublishedRARCandidates'}, ...
        {'RARMonitoringDecodedFields','rar_monitoring_decoded_fields','PublishedRARFields'}, ...
        {'ContentionMonitoringObservations','contention_monitoring_observations','PublishedContentionObservations'}, ...
        {'UEContentionEvents','ue_contention_events','PublishedUEContentionEvents'}}
    keys=mapping{1}; values=sixgr.util.structGet(ra,keys{1},table());
    count=sixgr.util.structGet(attempt,keys{3},0);
    if height(values)<count, error('sixgr:truth:RARMonitoringEvidenceRegressed','Receiver rows were lost.'); end
    evidence.(keys{2})=values(count+1:end,:);
    attempt.(keys{3})=height(values);
end
% A continuation can add observed allocations after Msg1. Merge each
% executed publication using physical RE identity, not first-stage gating.
% Never derive occupancy from planned grants or receive-row rectangles.
if ~isempty(stages)
    state.ObservedREAllocationTable = localAppendObservedREAllocation( ...
        sixgr.util.structGet(state, "ObservedREAllocationTable", table()), ...
        sixgr.util.structGet(ra, "ObservedREAllocationTable", table()));
end
if previousCount == 0 && ~isempty(stages)
    measured = localApplyFourStepRAEvidenceToPRACHRow( ...
        localMakeLinkTrialRow(cfg, "UL", attempt.SNR_dB, 1), ra, 1, attempt.StartSlot);
    correlationTraceT = localBuildFourStepRACorrelationTraceTable(ra, measured, cfg, attempt.SNR_dB, 1);
end
if ~isfield(state, "PendingRAAttempts")
    state.PendingRAAttempts = cell(numel(state.AccessState), 1);
end
if terminal
    state.PendingRAAttempts{ueIdx} = [];
    row = localApplyFourStepRAEvidenceToPRACHRow( ...
        localMakeLinkTrialRow(cfg, "UL", attempt.SNR_dB, 1), ra, 1, attempt.StartSlot);
    sourceSlot = double(ra.Msg1ScheduledSlot);
    if string(ra.RASlotTimeBase) ~= "absolute_zero_based" || ...
            ~isscalar(sourceSlot) || ~isfinite(sourceSlot) || sourceSlot < 0 || sourceSlot ~= fix(sourceSlot)
        error("sixgr:truth:InvalidDeferredRASourceSlot", "Deferred RA must retain the producer's absolute Msg1 coordinate.");
    end
    row.SourceObservationSlot = sourceSlot + 1;
    row.SourceObservationFrame = 1 + floor(sourceSlot / round(0.01 / sixgr.time.slotDurationSec(cfg)));
    row.RuntimeEvidenceAvailableSlot = slotIdx;
    if isfield(state,'SharedWaveformStream')
        assert(isfield(attempt,'Msg1RFMetadata') && height(attempt.Msg1RFMetadata)==1, ...
            'sixgr:truth:MissingMsg1RFExecution','Shared PRACH needs its actual Msg1 endpoint metadata.');
        for name=string(attempt.Msg1RFMetadata.Properties.VariableNames)
            row.(name)=attempt.Msg1RFMetadata.(name);
        end
        row.RFMeasurementScope="Msg1_only_other_RA_stages_have_separate_receiver_RF_rows";
        row.RFStageEvidenceArtifact="control/csv/ra_receiver_rf_observations.csv";
    end
    T = struct2table(row);
else
    attempt.Continuation = checkpoint;
    attempt.PublishedStageRows = height(stages);
    state.PendingRAAttempts{ueIdx} = attempt;
    state.AccessState(ueIdx) = "pending";
end
end

function state=localCompleteSharedRAObservation(state,item)
ue=item.UE;
if item.Kind~="RA"
    % Stopping a matched window is allowed; its already armed observations
    % must not be decoded as a new attempt or delivered after access ends.
    if ~localHasPendingRA(state,ue), return; end
    cp=state.PendingRAAttempts{ue}.Continuation;
    if cp.RAConfig.RunId~=item.Context.RunId, return; end
    if any(item.Kind==["RAR","RARExpiry"])
        if cp.NextStage~=2, return; end
    else
        receiver=sixgr.util.structGet(cp,'ContentionReceiver',[]);
        if isempty(receiver), return; end
        required="waiting";
        if item.Kind=="ContentionStart", required="armed"; end
        if receiver.MAC.Status~=required, return; end
    end
end
attempt=state.PendingRAAttempts{ue};
streams=struct(); action="execute"; stage="Msg2"; extra={};
if any(item.Kind==["ContentionStart","ContentionExpiry"])
    action="start_contention_timer";
    if item.Kind=="ContentionExpiry", action="expire_contention_timer"; end
    stage="Msg4"; extra={'EventTicks',item.Context.EventTicks};
    through=double(item.Context.EventTicks)/double(sixgr.phy.frame.AbsoluteTime.TicksPerSecond);
elseif item.Kind=="RARExpiry"
    action="expire_rar_window"; extra={'EventTicks',item.Context.ExpiryTicks};
    through=double(item.Context.ExpiryTicks)/double(sixgr.phy.frame.AbsoluteTime.TicksPerSecond);
else
    ids=string({item.Planes.ReceiverID});
    post=item.Planes(find(endsWith(ids,':post_rf'),1)).Observation;
    through=post.EndSampleExclusive/post.SampleRateHz;
    if item.Kind=="Contention"
        stage="Msg4"; action="receive_contention_observation";
        streams.ContentionPhysicalExecution=struct('Planes',item.Planes);
        extra={'ContentionObservationSlot',item.Context.AbsoluteSlot};
    elseif item.Kind=="RAR"
        action="receive_rar_observation";
        streams.RARPhysicalExecution=struct('Planes',item.Planes);
        extra={'RARObservationSlot',item.Context.AbsoluteSlot};
    else
        p=item.Context.Prepared; stage=p.StageName;
        streams.(p.StageName+"RxWaveform")=post;
        streams.(p.StageName+"PhysicalExecution")=struct('Planes',item.Planes,'Prepared',p);
    end
end
dl=state.SharedWaveformStream.directionalChannelState(ue,"DL");
ul=state.SharedWaveformStream.directionalChannelState(ue,"UL");
if ~isempty(attempt.Received)
    error('sixgr:truth:UndeliveredRAStage','Prior completed RA evidence must be consumed before replacing it.');
end
[ra,checkpoint]=sixgr.phy.ra.runFourStepRA(attempt.Config, ...
    'Continuation',attempt.Continuation,'RuntimeStageWaveforms',streams, ...
    'InitialDLChannelState',dl,'InitialULChannelState',ul, ...
    'StopAfterStage',stage,'StageAction',action,'ReceiveThroughTime_s',through,extra{:});
if any(item.Kind==["RA","RAR","Contention"])
    [rfRow,rfMetadata]=sixgr.truth.buildRAReceiverRFObservation(item, ...
        attempt.Continuation.RAConfig,state.CurrentServingIdx(ue), ...
        attempt.SNR_dB,state.SharedWaveformStream.Events.NextSampleIndex);
    priorRF=sixgr.util.structGet(state.ControlTrials, ...
        'RAEvidenceTables.ra_receiver_rf_observations',table());
    assert(isempty(priorRF) || ~any(priorRF.ObservationID==rfRow.ObservationID), ...
        'sixgr:truth:DuplicateRARFObservation','Publish each completed physical window once.');
    state.ControlTrials.RAEvidenceTables=localAppendRAEvidenceTables( ...
        state.ControlTrials.RAEvidenceTables,struct('ra_receiver_rf_observations',rfRow));
    if item.Kind=="RA" && stage=="Msg1"
        % PRACH RF belongs to Msg1, not every endpoint in the procedure.
        attempt.Msg1RFMetadata=rfMetadata;
    end
end
retry=state.RARetryByUE{ue};
% Preserve failed physical reception before classifying a MAC transition.
if item.Kind=="RA"
    sixgr.truth.exportSharedRAObservation(attempt.Config.run.rootRunFolder,attempt.Config, ...
        attempt.Continuation,p,item.Planes,ra);
elseif item.Kind=="RAR"
    sixgr.truth.exportSharedRARObservation(attempt.Config.run.rootRunFolder,attempt.Config,item.Context,item.Planes,ra);
elseif item.Kind=="Contention"
    sixgr.truth.exportSharedRARObservation(attempt.Config.run.rootRunFolder,attempt.Config,item.Context,item.Planes,ra,"Contention");
end
if item.Kind=="RA" && stage=="Msg1"
    retry=retry.transmitted(attempt.Continuation.RAConfig.PRACHActiveEndTicksExclusive);
elseif item.Kind=="RARExpiry"
    [retry,retryRow]=retry.responseExpired(ra.ExpiredRARReceiver,localSharedNowTicks(state));
    retryEvidence=struct('ra_retry_events',retryRow);
    state.ControlTrials.RAEvidenceTables=localAppendRAEvidenceTables( ...
        sixgr.util.structGet(state.ControlTrials,'RAEvidenceTables',struct()),retryEvidence);
    localAppendRuntimeLog("INFO", ...
        "UE RA timeout: ue=%d attempt=%d next_counter=%d ramp_counter=%d backoff_ms=%g retry_tick=%g exhausted=%d.", ...
        ue,retryRow.CompletedAttempt,retryRow.NextTransmissionCounter,retryRow.PowerRampingCounter, ...
        retryRow.PreambleBackoff_ms,retryRow.EarliestRetryTicks,retryRow.PreambleTransMaxExhausted);
elseif item.Kind=="RAR" && ~isempty(fieldnames(checkpoint)) && checkpoint.NextStage==3
    retry=retry.rarAccepted();
    common=state.UECommonCellConfigurationByUE{ue};
    if isfield(state,'ConnectedULTimingByUE') && numel(state.ConnectedULTimingByUE)>=ue && ...
            ~isempty(state.ConnectedULTimingByUE{ue})
        error('sixgr:truth:ConnectedTAGReacquisitionNotIntegrated', ...
            'A received initial RAR cannot silently overwrite a running TAG timer.');
    end
    state.ConnectedULTimingByUE{ue,1}=sixgr.mac.ra.connectedTimingFromRAR( ...
        attempt.Config,common,checkpoint.RARRx,item.Context.AbsoluteSlot, ...
        post.EndSampleExclusive,post.SampleRateHz);
elseif isfield(ra,'ContentionReceiver') && ...
        any(ra.ContentionReceiver.MAC.Status==["expired","identity_mismatch"])
    [retry,retryRow]=retry.contentionFailed(ra.ContentionReceiver, ...
        attempt.Continuation.RARReceiver,localSharedNowTicks(state));
    state.ControlTrials.RAEvidenceTables=localAppendRAEvidenceTables( ...
        sixgr.util.structGet(state.ControlTrials,'RAEvidenceTables',struct()),struct('ra_retry_events',retryRow));
    % The initial TAG was installed by this attempt's RAR. Failed contention
    % stops that provisional timing authority; a retry must receive a new TA.
    state.ConnectedULTimingByUE{ue}=[];
elseif isfield(ra,'ContentionReceiver') && ra.ContentionReceiver.MAC.Status=="succeeded"
    if retry.Status~="completed", retry=retry.completed(); end
elseif isempty(fieldnames(checkpoint)) && ra.RACompleted && retry.Status~="completed"
    retry=retry.completed();
elseif isempty(fieldnames(checkpoint))
    error('sixgr:truth:MissingUEContentionFailureBoundary', ...
        'A post-RAR gNB decode failure cannot become an immediate UE retry; execute the UE contention timer first.');
end
state.RARetryByUE{ue}=retry;
attempt.Received=ra;
% Publish the received stage even at the final configured slot. Eligibility
% is consumed by the next scheduler decision; retaining receiver evidence
% must not depend on that future slot actually being simulated.
attempt.Continuation=checkpoint;
state.PendingRAAttempts{ue}=attempt;
deliverySlot=state.CurrentSlot+1;
[state,raw,correlation,evidence]=localAdvanceCoupledRAAttempt( ...
    state,attempt.Config,ue,attempt.SNR_dB,deliverySlot);
frame=1+floor((deliverySlot-1)*state.SlotDuration_s/0.01);
cellID=state.CurrentServingIdx(ue);
rnti=sixgr.truth.CoupledRadioIdentity.dataRNTI(attempt.Config,ue,"UL");
trial=localAnnotateCoupledControlTrial(raw,deliverySlot,frame,ue,rnti,"UL",cellID);
state.ControlTrials.PRACH=localAppendCompatTable(state.ControlTrials.PRACH,trial);
state.ControlTrials.PRACHCorrelationTrace=localAppendCompatTable( ...
    sixgr.util.structGet(state.ControlTrials,'PRACHCorrelationTrace',table()),correlation);
state.ControlTrials.RAEvidenceTables=localAppendRAEvidenceTables( ...
    sixgr.util.structGet(state.ControlTrials,'RAEvidenceTables',struct()),evidence);
if ~isempty(trial), state=sixgr.truth.CoupledTruthRuntime.applyPRACHTrial(state,ue,trial); end
if ~isempty(fieldnames(checkpoint))
    if any(item.Kind==["ContentionStart","ContentionExpiry"]) || ...
            (item.Kind=="Contention" && checkpoint.ContentionReceiver.MAC.Status=="waiting")
        return;
    end
    attempt=state.PendingRAAttempts{ue};
    if item.Kind=="RA" && stage=="Msg1" && checkpoint.NextStage==2
        [state,next,checkpoint]=sixgr.truth.prepareCellRARResponse(state,attempt.Config,checkpoint);
    elseif item.Kind=="RA" && stage=="Msg3" && checkpoint.NextStage==4
        [state,next,checkpoint]=sixgr.truth.prepareCellContentionResponse(state,attempt.Config,checkpoint);
    else
        [next,checkpoint]=sixgr.phy.ra.runFourStepRA(attempt.Config, ...
            'Continuation',checkpoint,'StageAction','prepare_next_stage');
    end
    attempt.Continuation=checkpoint;
    state.PendingRAAttempts{ue}=attempt;
    if ~isempty(fieldnames(next.PreparedTransmission))
        state.SharedWaveformStream.queueRA(ue,next.PreparedTransmission, ...
            struct('Config',attempt.Config),any(next.PreparedTransmission.StageName==["Msg2","Msg4"]));
        if next.PreparedTransmission.StageName=="Msg3"
            state.SharedWaveformStream.armContentionWindow(ue,checkpoint.ContentionReceiver);
        end
    end
end
end

function ticks=localSharedNowTicks(state)
fs=state.SharedWaveformStream.SampleRateHz;
tc=double(sixgr.phy.frame.AbsoluteTime.TicksPerSecond)/fs;
if tc~=fix(tc)
    error('sixgr:truth:SharedRetryClock','The UE retry clock must preserve exact physical Tc.');
end
ticks=int64(state.SharedWaveformStream.Events.NextSampleIndex)*int64(tc);
end

function cfg = localApplyMeasuredSSBSelectionForRA(cfg, state, ueIdx)
policy = lower(strtrim(string(sixgr.util.structGet(cfg, ...
    "random_access.msg1_beam_policy", ""))));
commonDLBeamSource = lower(strtrim(string(sixgr.util.structGet(cfg, ...
    "random_access.common_downlink_beam_source", ""))));
requiresMeasuredSelection = policy == "ssb_beam" || ...
    commonDLBeamSource == "selected_ssb_beam";
selected = localStateNumericAt(state, "SelectedSSBIndexByUE", ueIdx, NaN);
source = localStateStringAt(state, "SelectedSSBSelectionSourceByUE", ...
    ueIdx, "");
metric_dB = localStateNumericAt(state, ...
    "SelectedSSBMeasurement_dBByUE", ueIdx, NaN);
if requiresMeasuredSelection && (~isfinite(selected) || ...
        strlength(strtrim(source)) == 0)
    error("sixgr:truth:MeasuredSSBSelectionRequiredForPRACH", ...
        ["PRACH/RA policy requires a receiver-measured SSB beam, but UE %d " ...
         "has no successful coupled SSB/PBCH sweep selection."], ...
        round(double(ueIdx)));
end
if isfinite(selected)
    cfg = sixgr.util.structSet(cfg, ...
        "phy.ssb.runtimeSSBIndex", double(selected));
    cfg = sixgr.util.structSet(cfg, ...
        "random_access.associated_ssb_index", double(selected));
    cfg = sixgr.util.structSet(cfg, ...
        "random_access.associated_ssb_selection_source", char(source));
    cfg = sixgr.util.structSet(cfg, ...
        "random_access.associated_ssb_measurement_db", double(metric_dB));
end
end

function value = localStateNumericAt(state, fieldName, index, defaultValue)
value = double(defaultValue);
raw = sixgr.util.structGet(state, string(fieldName), []);
index = round(double(index));
if isnumeric(raw) && isfinite(index) && index >= 1 && index <= numel(raw)
    candidate = double(raw(index));
    if isfinite(candidate)
        value = candidate;
    end
end
end

function value = localStateStringAt(state, fieldName, index, defaultValue)
value = string(defaultValue);
raw = string(sixgr.util.structGet(state, string(fieldName), strings(0, 1)));
index = round(double(index));
if isfinite(index) && index >= 1 && index <= numel(raw)
    candidate = string(raw(index));
    if strlength(strtrim(candidate)) > 0
        value = candidate;
    end
end
end

function [T, correlationTraceT, raEvidenceTables, ...
        advancedDLState, advancedULState, observedRET] = localCollectPRACHTrials( ...
        cfg, snr_dB, nTrials, slotIdx, initialDLState, initialULState, decodedSIB1)
nTrials = max(1, round(double(nTrials)));
if nargin < 4
    slotIdx = NaN;
end
if nargin < 5
    initialDLState = struct();
end
if nargin < 6
    initialULState = struct();
end
if nargin < 7
    decodedSIB1 = struct();
end
advancedDLState = initialDLState;
advancedULState = initialULState;
rows = repmat(localMakeLinkTrialRow(cfg, "UL", snr_dB, 1), nTrials, 1);
correlationTraceT = table();
raEvidenceTables = localEmptyRAEvidenceTables();
observedRET = table();
fourStepRequired = localShouldRunFourStepRAForPRACH(cfg);
for k = 1:nTrials
    r = localMakeLinkTrialRow(cfg, "UL", snr_dB, k);
    r.CRCPass = NaN;
    r.CRCApplicable = false;
    r.CRCOutcome = "not_applicable";
    r.Status = "FAIL";
    try
        if fourStepRequired
            [ra, raRunOk, raRunFailure] = ...
                localRunFourStepRAForPRACHTrial( ...
                cfg, k, slotIdx, snr_dB, ...
                advancedDLState, advancedULState, decodedSIB1);
            if raRunOk
                advancedDLState = sixgr.util.structGet( ...
                    ra, "RuntimeDLChannelState", advancedDLState);
                advancedULState = sixgr.util.structGet( ...
                    ra, "RuntimeULChannelState", advancedULState);
                r = localApplyFourStepRAEvidenceToPRACHRow(r, ra, k, slotIdx);
                corrT = localBuildFourStepRACorrelationTraceTable( ...
                    ra, r, cfg, snr_dB, k);
                correlationTraceT = localAppendCompatTable( ...
                    correlationTraceT, corrT);
                raEvidenceTables = localAppendRAEvidenceTables(raEvidenceTables, sixgr.util.structGet(ra, "ArtifactTables", struct()));
                observedRET = localAppendCompatTable(observedRET, ...
                    sixgr.util.structGet(ra, "ObservedREAllocationTable", table()));
            else
                r.StrictOk = false;
                r.StrictReceiverEvidenceOk = false;
                r.DecodeAttempted = true;
                r.DecodeUsable = false;
                r.ReceiverUsable = false;
                r.Status = "CRASH";
                r.FailureReason = string(raRunFailure);
                r.Crash = true;
                r.RAFailureReason = string(raRunFailure);
                r.Notes = "strict_four_step_ra_failed_before_complete_runtime_evidence:" + string(raRunFailure);
                r.RuntimeMaterializationStatus = "four_step_ra_runtime_failed";
                r.RuntimeEvidenceSource = "sixgr.phy.ra.runFourStepRA";
            end
            rows(k) = r;
            continue;
        end
        out = sixgr.link.runPRACHDetection(cfg, "SNR_dB", snr_dB, "CanonicalSlot", slotIdx);
        observedRET = localAppendCompatTable(observedRET, ...
            sixgr.util.structGet(out, "ObservedREAllocationTable", table()));
        corrT = sixgr.util.structGet(out, "CorrelationTraceTable", table());
        if istable(corrT) && ~isempty(corrT)
            if ismember("trial_id", string(corrT.Properties.VariableNames))
                corrT.trial_id(:) = double(k);
            end
            correlationTraceT = localAppendCompatTable(correlationTraceT, corrT);
        end
        completed = logical(sixgr.util.structGet(out, "Ok", false)) && ~logical(sixgr.util.structGet(out, "Skipped", false));
        detected = logical(sixgr.util.structGet(out, "Detected", false));
        r.DetectionSuccess = detected;
        r.DetectionMetric = double(sixgr.util.structGet(out, "DetectionMetric", NaN));
        r.CorrelationPeak = double(sixgr.util.structGet(out, "CorrelationPeak", r.DetectionMetric));
        r.DetectionThreshold = double(sixgr.util.structGet(out, "DetectionThreshold", NaN));
        r.DetectionThresholdMode = string(sixgr.util.structGet(out, "DetectionThresholdMode", ""));
        r.NoiseOnlyDetectionMetric = double(sixgr.util.structGet(out, "NoiseOnlyDetectionMetric", NaN));
        r.DetectorNoiseFloor = double(sixgr.util.structGet(out, "DetectorNoiseFloor", NaN));
        r.RxAntennaCount = double(sixgr.util.structGet(out, "RxAntennaCount", NaN));
        r.PDPAverageNoiseFloor = double(sixgr.util.structGet(out, "PDPAverageNoiseFloor", NaN));
        r.PeakToThresholdRatio = double(sixgr.util.structGet(out, "PeakToThresholdRatio", NaN));
        r.PeakToNoiseRatio = double(sixgr.util.structGet(out, "PeakToNoiseRatio", NaN));
        r.PeakToNoiseRatio_dB = double(sixgr.util.structGet(out, "PeakToNoiseRatio_dB", NaN));
        r.CandidateCount = double(sixgr.util.structGet(out, "CandidateCount", NaN));
        r.CandidatesAboveThreshold = double(sixgr.util.structGet(out, "CandidatesAboveThreshold", NaN));
        r.TargetFalseAlarmProbability = double(sixgr.util.structGet(out, "TargetFalseAlarmProbability", NaN));
        r.ThresholdBackgroundComponent = double(sixgr.util.structGet(out, "ThresholdBackgroundComponent", NaN));
        r.ThresholdGlobalPeakComponent = double(sixgr.util.structGet(out, "ThresholdGlobalPeakComponent", NaN));
        r.PeakGuardFactor = double(sixgr.util.structGet(out, "PeakGuardFactor", NaN));
        r.DetectorPeakLagSamples = double(sixgr.util.structGet(out, "DetectorPeakLagSamples", NaN));
        r.NoiseVariance = double(sixgr.util.structGet(out, "NoiseVariance", NaN));
        r.NoiseVarStatus = string(sixgr.util.structGet(out, "NoiseVarStatus", ""));
        r.NoiseVarSource = string(sixgr.util.structGet(out, "NoiseVarSource", ""));
        r.NoiseVarReason = string(sixgr.util.structGet(out, "NoiseVarReason", ""));
        r.MissedDetection = logical(sixgr.util.structGet(out, "MissedDetection", ~detected));
        r.FalseAlarm = logical(sixgr.util.structGet(out, "FalseAlarm", false));
        r.FalseAlarmFlag = double(sixgr.util.structGet(out, "FalseAlarmFlag", NaN));
        r.NoiseFalseAlarmFlag = double(sixgr.util.structGet(out, "NoiseFalseAlarmFlag", NaN));
        r.CollisionFalseAlarmFlag = double(sixgr.util.structGet(out, "CollisionFalseAlarmFlag", NaN));
        r.FalseAlarmClassification = string(sixgr.util.structGet(out, "FalseAlarmClassification", ""));
        r.FalseAlarmCandidateScope = string(sixgr.util.structGet(out, "FalseAlarmCandidateScope", ""));
        r.FalseAlarmCandidateCount = double(sixgr.util.structGet(out, "FalseAlarmCandidateCount", NaN));
        r.PreambleIndex = localFirstFinite(sixgr.util.structGet(out, "PreambleIndex", NaN), NaN);
        r.RequestedPreambleIndex = localFirstFinite(sixgr.util.structGet(out, "RequestedPreambleIndex", NaN), NaN);
        r.DetectedPreambleIndex = localFirstFinite(sixgr.util.structGet(out, "DetectedPreambleIndex", NaN), NaN);
        r.PreambleIndexFromPeak = localFirstFinite(sixgr.util.structGet(out, "PreambleIndexFromPeak", NaN), NaN);
        r.PRACHRootSequenceIndex = double(sixgr.util.structGet(out, "PRACHRootSequenceIndex", NaN));
        r.PRACHZeroCorrelationZone = double(sixgr.util.structGet(out, "PRACHZeroCorrelationZone", NaN));
        r.PRACHConfigurationIndex = double(sixgr.util.structGet(out, "PRACHConfigurationIndex", NaN));
        r.PRACHOccasionIndex = double(sixgr.util.structGet(out, "PRACHOccasionIndex", NaN));
        r.PRACHCarrierSlot = double(sixgr.util.structGet(out, "PRACHCarrierSlot", NaN));
        r.TimingError_samples = double(sixgr.util.structGet(out, "TimingOffset_samples", NaN));
        r.TimingOffset_samples = r.TimingError_samples;
        r.TimingAdvance_samples = double(sixgr.util.structGet(out, "TimingAdvance_samples", NaN));
        r.TimingAdvance_us = double(sixgr.util.structGet(out, "TimingAdvance_us", NaN));
        r.TAOutOfRangeFlag = logical(sixgr.util.structGet(out, "TAOutOfRangeFlag", false));
        r.TAOutOfRangeReason = string(sixgr.util.structGet(out, "TAOutOfRangeReason", ""));
        r.TAMaxValid_samples = double(sixgr.util.structGet(out, "TAMaxValid_samples", NaN));
        r.TAMaxValid_us = double(sixgr.util.structGet(out, "TAMaxValid_us", NaN));
        r.ConfiguredSNR_dB = double(sixgr.util.structGet(out, "ConfiguredSNR_dB", snr_dB));
        r.SNRValueRole = string(sixgr.util.structGet(out, "SNRValueRole", r.SNRValueRole));
        r.AppliedAWGNSNR_dB = double(sixgr.util.structGet(out, "AppliedAWGNSNR_dB", NaN));
        r.AppliedAWGNSNRSource = string(sixgr.util.structGet(out, "AppliedAWGNSNRSource", ""));
        r.DesiredSignalPowerBeforeNoise = double(sixgr.util.structGet(out, "DesiredSignalPowerBeforeNoise", NaN));
        r.CompositeSignalPowerBeforeNoise = double(sixgr.util.structGet(out, "CompositeSignalPowerBeforeNoise", NaN));
        r.AppliedNoiseSNR_dB = double(sixgr.util.structGet(out, "AppliedNoiseSNR_dB", NaN));
        r.PRACHSNRCalibrationStatus = string(sixgr.util.structGet(out, "PRACHSNRCalibrationStatus", ""));
        r.PRACHSNRCalibrationSource = string(sixgr.util.structGet(out, "PRACHSNRCalibrationSource", ""));
        r.PRACHSNRCalibrationError_dB = double(sixgr.util.structGet(out, "PRACHSNRCalibrationError_dB", NaN));
        r.PRACHNoiseReferencePower = double(sixgr.util.structGet(out, "PRACHNoiseReferencePower", NaN));
        r.NoiseVarianceSource = string(sixgr.util.structGet(out, "NoiseVarianceSource", ""));
        r.ChannelModelApplied = string(sixgr.util.structGet(out, "ChannelModelApplied", ""));
        r.ChannelFadingApplied = logical(sixgr.util.structGet(out, "ChannelFadingApplied", false));
        r.AppliedLargeScaleGain_dB = double(sixgr.util.structGet(out, "AppliedLargeScaleGain_dB", NaN));
        r.AppliedLargeScaleLoss_dB = double(sixgr.util.structGet(out, "AppliedLargeScaleLoss_dB", NaN));
        r.AppliedBasePathloss_dB = double(sixgr.util.structGet(out, "AppliedBasePathloss_dB", NaN));
        r.AppliedPathloss_dB = double(sixgr.util.structGet(out, "AppliedPathloss_dB", NaN));
        r.AppliedShadowFading_dB = double(sixgr.util.structGet(out, "AppliedShadowFading_dB", NaN));
        r.AppliedO2I_dB = double(sixgr.util.structGet(out, "AppliedO2I_dB", NaN));
        r.AppliedLargeScaleGainSource = string(sixgr.util.structGet(out, "AppliedLargeScaleGainSource", ""));
        r.ServingRSRP_dBm = double(sixgr.util.structGet(out, "ServingRSRP_dBm", NaN));
        r.ServingRSRPSource = string(sixgr.util.structGet(out, "ServingRSRPSource", ""));
        r.LargeScaleSINR_dB = double(sixgr.util.structGet(out, "LargeScaleSINR_dB", NaN));
        r.LargeScaleSINRSource = string(sixgr.util.structGet(out, "LargeScaleSINRSource", ""));
        r.InjectedCFO_Hz = double(sixgr.util.structGet(out, "InjectedCFO_Hz", NaN));
        r.InjectedTimingOffset_samples = double(sixgr.util.structGet(out, "InjectedTimingOffset_samples", NaN));
        r.ComputeLatency_ms = double(sixgr.util.structGet(out, "ComputeLatency_ms", NaN));
        r.ProcedureDelay_ms = double(sixgr.util.structGet(out, "ProcedureDelay_ms", NaN));
        r.AirInterfaceObservation_ms = double(sixgr.util.structGet(out, "AirInterfaceObservation_ms", NaN));
        r.AcquisitionTime_ms = double(sixgr.util.structGet(out, "AcquisitionTime_ms", NaN));
        r.DetectionAttempted = completed || isfinite(r.DetectionMetric);
        r.DetectionUsable = logical(r.DetectionAttempted) && logical(r.DetectionSuccess) && isfinite(r.DetectionMetric);
        r.MeasurementAttempted = logical(r.DetectionAttempted);
        r.MeasurementUsable = logical(r.DetectionUsable) && isfinite(r.NoiseVariance);
        r.ReceiverUsable = logical(r.MeasurementUsable);
        if completed && detected
            r.Status = "PASS";
        elseif logical(sixgr.util.structGet(out, "Skipped", false))
            r.CRCPass = NaN;
            r.DetectionMetric = NaN;
            r.Status = "NA";
        end
        r.Notes = string(sixgr.util.structGet(out, "Notes", ""));
    catch ME
        r.Crash = true;
        r.Status = "CRASH";
        failure = string(ME.identifier) + ":" + string(ME.message);
        r.FailureReason = failure;
        r.RAFailureReason = failure;
        r.Notes = failure;
    end
    rows(k) = r;
end
T = struct2table(rows);
end

function tf = localShouldRunFourStepRAForPRACH(cfg)
prachEnabled = logical(sixgr.util.structGet(cfg, "phy.prach.enable", ...
    sixgr.util.structGet(cfg, "random_access.enabled", false)));
tf = prachEnabled && ( ...
    logical(sixgr.util.structGet(cfg, "random_access.four_step_ra_required", false)) || ...
    logical(sixgr.util.structGet(cfg, "validation.random_access_evidence.four_step_ra_required", false)) || ...
    logical(sixgr.util.structGet(cfg, "random_access.msg4_contention_resolution_required", false)) || ...
    logical(sixgr.util.structGet(cfg, "validation.random_access_evidence.msg4_contention_resolution_required", false)) || ...
    logical(sixgr.util.structGet(cfg, "validation.random_access_evidence.contention_resolution_identity_required", false)) || ...
    logical(sixgr.util.structGet(cfg, "validation.random_access_evidence.msg3_pusch_required", false)));
end

function [ra, ok, failure, continuation] = localRunFourStepRAForPRACHTrial( ...
        cfg, trialIdx, slotIdx, snr_dB, initialDLState, initialULState, decodedSIB1, receiveThrough)
if nargin < 8, receiveThrough = Inf; end
continuation = struct();
ra = struct();
ok = false;
failure = "";
try
    scenarioName = string(sixgr.util.structGet(cfg, "run.scenarioID", ...
        sixgr.util.structGet(cfg, "meta.lls6gScenarioID", ...
        sixgr.util.structGet(cfg, "scenario.name", "waveform_bundle"))));
    ueId = localFirstFinite([ ...
        sixgr.util.structGet(cfg, "lls6g.userContext.UEIndex", NaN), ...
        sixgr.util.structGet(cfg, "ue.id", NaN), ...
        sixgr.util.structGet(cfg, "scenario.ue.id", NaN)], 1);
    cellId = localFirstFinite([ ...
        sixgr.util.structGet(cfg, "phy.carrier.NCellID", NaN), ...
        sixgr.util.structGet(cfg, "scenario.NCellID", NaN)], 1);
    slotToken = "slot_unknown";
    if isfinite(double(slotIdx))
        slotToken = "slot_" + string(round(double(slotIdx)));
    end
    snrToken = "snr_" + string(round(double(snr_dB) * 1000));
    runId = "ra_" + matlab.lang.makeValidName(char(scenarioName)) + "_ue" + string(round(double(ueId))) + ...
        "_trial" + string(round(double(trialIdx))) + "_" + slotToken + "_" + snrToken;
    raRunFolder = string(sixgr.util.structGet(cfg, "ctrl6gr.OutputDir", ...
        sixgr.util.structGet(cfg, "run.outputDir", "")));
    requireDecodedSIB1 = localRequireDecodedSIB1ForRA(cfg);
    requireRuntimeStages = localConfigBool(cfg, ...
        ["validation.random_access_evidence.require_runtime_stage_waveforms", ...
         "lls6g.random_access_evidence.require_runtime_stage_waveforms", ...
         "random_access.require_runtime_stage_waveforms"], false);
    allowRuntimeComposition = localConfigBool(cfg, ...
        ["validation.random_access_evidence.allow_runtime_stage_waveform_composition", ...
         "lls6g.random_access_evidence.allow_runtime_stage_waveform_composition", ...
         "random_access.allow_runtime_stage_waveform_composition"], false);
    runNegativeSuite = localConfigBool(cfg, ...
        ["validation.random_access_evidence.four_step_negative_test_enabled", ...
         "lls6g.random_access_evidence.four_step_negative_test_enabled", ...
         "random_access.run_negative_suite"], false);
    [ra, continuation] = sixgr.truth.CoupledTruthRuntime.runFourStepRARuntime(cfg, ...
        "RunFolder", char(raRunFolder), ...
        "RunId", runId, ...
        "ScenarioName", scenarioName, ...
        "UEId", double(ueId), ...
        "CellId", double(cellId), ...
        "AttemptId", double(trialIdx), ...
        "RuntimeSlot", double(slotIdx), ...
        "ReceiveThroughTime_s", receiveThrough, ...
        "RuntimeNoiseSNR_dB", double(snr_dB), ...
        "SIB1Recovery", decodedSIB1, ...
        "RequireDecodedSIB1", requireDecodedSIB1, ...
        "RequireRuntimeStageWaveforms", requireRuntimeStages, ...
        "AllowRuntimeStageWaveformComposition", allowRuntimeComposition, ...
        "RunNegativeSuite", runNegativeSuite, ...
        "InitialDLChannelState", initialDLState, ...
        "InitialULChannelState", initialULState, ...
        "WriteArtifacts", false);
    ok = true;
catch ME
    failure = string(ME.identifier) + ":" + string(ME.message);
end
end

function r = localApplyFourStepRAEvidenceToPRACHRow(r, ra, trialIdx, slotIdx)
r.RARunId = string(sixgr.util.structGet(ra, "RunId", ""));
r.RAScenarioName = string(sixgr.util.structGet(ra, "ScenarioName", ""));
r.RACellId = double(sixgr.util.structGet(ra, "CellId", NaN));
r.RAUEId = double(sixgr.util.structGet(ra, "UEId", NaN));
r.RAAttemptId = double(sixgr.util.structGet(ra, "AttemptId", trialIdx));
    fields = ["RAProcedureType","RABindingSource","RASlotTimeBase","Msg1ScheduledSlot", ...
    "SIB1RACHBindingApplied","SIB1RACHBindingSource", ...
    "SIB1RACHPayloadHash","SIB1RACHTreeHash","RACHConfigHash", ...
    "AssociatedSSBIndex","AssociatedSSBSelectionSource", ...
    "AssociatedSSBMeasurement_dB","Msg1BeamPolicy", ...
    "SSBToPRACHAssociationApplied", ...
    "PRACHOccasionFrame","PRACHOccasionSlot","PRACHOccasionSymbol", ...
    "PRACHFrequencyIndex","PRACHOccasionID", ...
    "PreambleIndexTx","PreambleIndexDetected","PreambleDetectionMetric", ...
    "PreambleDetectionThreshold","PreambleDetectionThresholdMode","PreambleDetectionThresholdSource", ...
    "PreambleDetectionThresholdCalibrationStatus","Msg1ConfiguredTargetFalseAlarmProbability", ...
    "PreambleDetected","CollisionDetected", ...
    "PreambleAmbiguityDetected","PRACHRawTimingEstimate_samples", ...
    "PRACHPropagationTimingEstimate_samples","PRACHTrueTimingOffset_samples", ...
    "PRACHTimingError_samples","PRACHTimingEstimateValid","PRACHTimingEstimateSource", ...
    "PRACHFrequencyEstimationEnabled","PRACHFrequencyEstimate_Hz", ...
    "PRACHFrequencyEstimateValid","PRACHFrequencyEstimator", ...
    "TimingAdvanceCommand","PreambleReceivedTargetPower_dBm", ...
    "EstimatedTimingAdvanceCommand","TimingAdvanceNTA_Tc","TimingAdvanceSampleRate_Hz", ...
    "TimingAdvanceSource","PRACHTimingSampleRate_Hz","TAQuantizationResidual_samples", ...
    "PowerRampingStep_dB","PreambleTransMax","PreambleAttemptNumber", ...
    "PowerPathloss_dB","PowerBasePathloss_dB","PowerPathlossSource","ReferenceTxPower_dBm", ...
    "PreambleDelta_dB","PreambleTargetReceivedPower_dBm","PreambleRequestedTxPower_dBm", ...
    "PreambleTxPower_dBm","PreamblePowerHeadroom_dB","PreambleTxAmplitudeScale","PowerControlStatus", ...
    "P0PUSCH_dBm","AlphaPUSCH","Pcmax_dBm", ...
    "Msg3Pathloss_dB","Msg3P0PUSCH_dBm","Msg3Alpha","Msg3NumPRBForPower", ...
    "Msg3DeltaTF_dB","Msg3ClosedLoopCorrection_dB","Msg3RequestedTxPower_dBm", ...
    "Msg3TxPower_dBm","Msg3PowerHeadroom_dB","Msg3TxAmplitudeScale", ...
    "DownlinkTxPower_dBm","DownlinkTxPowerSource", ...
    "Msg2TxPower_dBm","Msg2TxAmplitudeScale","Msg4TxPower_dBm","Msg4TxAmplitudeScale", ...
    "RARNTI","RAResponseWindowStartSlot","RAResponseWindowEndSlot","RARWindowExpired", ...
    "Msg2PDCCHCandidatesAttempted","Msg2RARNTIDetected","Msg2DCICrcPass","Msg2DCIFormat", ...
    "Msg2PDSCHCrcPass","Msg2PDSCHNumLayers","Msg2PDSCHConfiguredNumPorts", ...
    "Msg2PDSCHResolvedNumPorts","Msg2PDSCHExplicitMatrixPresent", ...
    "Msg2PDSCHPrecodingActive","Msg2PDSCHPrecodingMode","Msg2PDSCHPrecodingSource", ...
    "Msg2TimingEstimateUsed","Msg2RawTimingEstimate_samples","Msg2AppliedTimingCorrection_samples", ...
    "Msg2TimingEstimateSource","Msg2PostEqSINR_dB","Msg2ReceiverHestSINR_dB", ...
    "Msg2PreEqualizationNoiseVar","Msg2DecoderNoiseVar","Msg2ChannelEstimateAvailable", ...
    "Msg2ChannelEstimateMethod","Msg2ChannelEstimatePilotResidualNMSE_dB", ...
    "Msg2EqualizationAvailable","Msg2LLRFinite","Msg2DemapperLLRCount","Msg2DecoderIterations", ...
    "RARBytesHex","RAPIDDecoded","RAPIDMatches","TemporaryCRNTI","Msg2ScheduledSlot", ...
    "RARULGrantHex","RARULGrantValid","Msg3ScheduledSlot","Msg3PUSCHPRBStart", ...
    "Msg3PUSCHNumPRB","Msg3PUSCHSymbolStart","Msg3PUSCHNumSymbols","Msg3MCS", ...
    "Msg3Modulation","Msg3TBS","Msg3TimingAdvanceApplied","Msg3PUSCHCrcPass", ...
    "Msg3TimingEstimateUsed","Msg3RawTimingEstimate_samples", ...
    "Msg3AppliedTimingCorrection_samples","Msg3TimingEstimateSource", ...
    "Msg3PostEqSINR_dB","Msg3ReceiverHestSINR_dB", ...
    "Msg3PreEqualizationNoiseVar","Msg3DecoderNoiseVar", ...
    "Msg3ChannelEstimateAvailable","Msg3ChannelEstimateMethod", ...
    "Msg3ChannelEstimatePilotResidualNMSE_dB","Msg3EqualizationAvailable", ...
    "Msg3LLRFinite","Msg3DemapperLLRCount","Msg3DecoderIterations", ...
    "Msg3PayloadHex","Msg3TransmittedPayloadHex","Msg3ContentionIdentity","Msg4ScheduledSlot","Msg4PDCCHCrcPass", ...
    "Msg4PDSCHCrcPass","Msg4PDSCHNumLayers","Msg4PDSCHConfiguredNumPorts", ...
    "Msg4PDSCHResolvedNumPorts","Msg4PDSCHExplicitMatrixPresent", ...
    "Msg4PDSCHPrecodingActive","Msg4PDSCHPrecodingMode","Msg4PDSCHPrecodingSource", ...
    "Msg4TimingEstimateUsed","Msg4RawTimingEstimate_samples","Msg4AppliedTimingCorrection_samples", ...
    "Msg4TimingEstimateSource","Msg4PostEqSINR_dB","Msg4ReceiverHestSINR_dB", ...
    "Msg4PreEqualizationNoiseVar","Msg4DecoderNoiseVar","Msg4ChannelEstimateAvailable", ...
    "Msg4ChannelEstimateMethod","Msg4ChannelEstimatePilotResidualNMSE_dB", ...
    "Msg4EqualizationAvailable","Msg4LLRFinite","Msg4DemapperLLRCount","Msg4DecoderIterations", ...
    "Msg4PayloadHex","Msg4TransmittedPayloadHex","Msg4ContentionIdentity","ContentionIdentityMatches", ...
    "FinalCRNTI","FinalCRNTISource","FinalCRNTIEncodingProfile", ...
    "RequireRRCSetupComplete","RRCTransactionID","SRB1LCID", ...
    "SetupCompleteScheduledSlot","RRCSetupRequestDecoded","RRCSetupRequestSHA256", ...
    "RRCSetupDecoded","RRCSetupSHA256","SRB1Installed","RRCSetupCompleteCRC", ...
    "RRCSetupCompleteDecoded","RRCSetupCompletePayloadSHA256", ...
    "RRCSetupCompleteTransmittedPayloadSHA256", ...
    "RRCSetupCompleteDecodedTransactionID","RRCSetupCompleteDecodedSRB1LCID", ...
    "RRCSetupCompleteDecodedUEIdentity","SetupCompleteTxAmplitudeScale", ...
    "SetupCompleteTransportBlockSize","SetupCompleteReceiverOk", ...
    "SetupCompletePostEqSINR_dB","SetupCompleteReceiverHestSINR_dB", ...
    "SetupCompleteChannelEstimateAvailable","SetupCompleteChannelEstimateMethod", ...
    "SetupCompleteEqualizationAvailable","SetupCompleteLLRFinite", ...
    "SetupCompleteDemapperLLRCount","SetupCompleteDecoderIterations", ...
    "RRCConnected","RACompleted","FailureReason","ProxyUsed","Skipped","ToolboxMissing", ...
    "UsedOracleFields","StrictOk", ...
    "RuntimeIntegrationMode","RuntimeTransportMode","RuntimeStageWaveformsRequired", ...
    "RuntimeStageWaveformsUsed","RuntimeSelfLoopWaveformsUsed","RuntimeChannelStateUsed", ...
    "RuntimeNoiseApplied","RuntimeNoiseVarianceMean","RuntimeChannelLinkKeys","RuntimeStageCount"];
for i = 1:numel(fields)
    f = char(fields(i));
    if isfield(ra, f) && isfield(r, f)
        r.(f) = ra.(f);
    end
end
strictOk = logical(sixgr.util.structGet(ra, "StrictOk", false));
preambleDetected = logical(sixgr.util.structGet(ra, "PreambleDetected", false));
r.Frame = localFirstFinite(slotIdx, trialIdx);
r.Slot = localFirstFinite(slotIdx, trialIdx);
r.PreambleIndex = double(sixgr.util.structGet(ra, "PreambleIndexTx", r.PreambleIndex));
r.ControlEVMSamplesJSON=string(sixgr.util.structGet(ra,'ControlEVMSamplesJSON',""));
nativeEvidence=sixgr.util.structGet(ra,'Msg1SampleIntervalEvidence',sixgr.truth.prachNativeSampleIntervals());
for name=string(fieldnames(nativeEvidence)).', r.(name)=nativeEvidence.(name); end
r.RequestedPreambleIndex = r.PreambleIndex;
r.DetectedPreambleIndex = double(sixgr.util.structGet(ra, "PreambleIndexDetected", r.DetectedPreambleIndex));
r.DetectionMetric = double(sixgr.util.structGet(ra, "PreambleDetectionMetric", r.DetectionMetric));
r.CorrelationPeak = r.DetectionMetric;
r.DetectionThreshold = double(sixgr.util.structGet(ra, "PreambleDetectionThreshold", r.DetectionThreshold));
r.RxAntennaCount = double(sixgr.util.structGet(ra, "Msg1RxAntennaCount", r.RxAntennaCount));
r.PDPAverageNoiseFloor = double(sixgr.util.structGet(ra, "Msg1PDPAverageNoiseFloor", r.PDPAverageNoiseFloor));
r.NoiseFloorEstimator=string(sixgr.util.structGet(ra,"Msg1NoiseFloorEstimator",""));
r.NoiseFloorDefinition=string(sixgr.util.structGet(ra,"Msg1NoiseFloorDefinition",""));
r.NoiseFloorStatus=string(sixgr.util.structGet(ra,"Msg1NoiseFloorStatus",""));
r.NoiseFloorPairCount=double(sixgr.util.structGet(ra,"Msg1NoiseFloorPairCount",NaN));
r.PeakToThresholdRatio = double(sixgr.util.structGet(ra, "Msg1PeakToThresholdRatio", r.PeakToThresholdRatio));
r.PeakToNoiseRatio = double(sixgr.util.structGet(ra, "Msg1PeakToNoiseRatio", r.PeakToNoiseRatio));
r.PeakToNoiseRatio_dB = double(sixgr.util.structGet(ra, "Msg1PeakToNoiseRatio_dB", r.PeakToNoiseRatio_dB));
r.CandidateCount = double(sixgr.util.structGet(ra, "Msg1CandidateCount", r.CandidateCount));
r.CandidatesAboveThreshold = double(sixgr.util.structGet(ra, "Msg1CandidatesAboveThreshold", r.CandidatesAboveThreshold));
r.TargetFalseAlarmProbability = double(sixgr.util.structGet(ra, "Msg1TargetFalseAlarmProbability", r.TargetFalseAlarmProbability));
r.ThresholdBackgroundComponent = double(sixgr.util.structGet(ra, "Msg1ThresholdBackgroundComponent", r.ThresholdBackgroundComponent));
r.ThresholdGlobalPeakComponent = double(sixgr.util.structGet(ra, "Msg1ThresholdGlobalPeakComponent", r.ThresholdGlobalPeakComponent));
r.PeakGuardFactor = double(sixgr.util.structGet(ra, "Msg1PeakGuardFactor", r.PeakGuardFactor));
r.DetectorPeakLagSamples = double(sixgr.util.structGet(ra, "Msg1DetectorPeakLagSamples", r.DetectorPeakLagSamples));
r.TimingAdvance_samples = double(sixgr.util.structGet(ra, "TimingAdvanceSamples", r.TimingAdvance_samples));
if isfinite(r.TimingAdvanceNTA_Tc)
    r.TimingAdvance_us = 1e6*r.TimingAdvanceNTA_Tc / ...
        double(sixgr.phy.frame.AbsoluteTime.TicksPerSecond);
end
r.TimingOffset_samples = double(sixgr.util.structGet(ra, ...
    "PRACHPropagationTimingEstimate_samples", NaN));
r.TimingEstimate_samples = r.TimingOffset_samples;
r.EstimatedTimingOffset_PreCorrection_samples = r.TimingOffset_samples;
r.EstimatedTimingOffset_samples = r.TimingOffset_samples;
r.TrueTimingOffset_samples = double(sixgr.util.structGet(ra, ...
    "PRACHTrueTimingOffset_samples", NaN));
r.TimingError_samples = double(sixgr.util.structGet(ra, ...
    "PRACHTimingError_samples", NaN));
timingEstimateValid = logical(sixgr.util.structGet(ra, ...
    "PRACHTimingEstimateValid", false));
if timingEstimateValid
    r.TimingEstimateStatus = "measured";
else
    r.TimingEstimateStatus = "not_available";
end

r.TimingEstimateApplicationPolicy = string(sixgr.util.structGet(ra, ...
    "PRACHTimingEstimateSource", ""));
r.EstimatedCFO_Hz = double(sixgr.util.structGet(ra, "PRACHFrequencyEstimate_Hz", NaN));
r.EstimatedCFO_PreCorrection_Hz = r.EstimatedCFO_Hz;
frequencyEstimateValid = logical(sixgr.util.structGet(ra, ...
    "PRACHFrequencyEstimateValid", false));
if frequencyEstimateValid
    r.CFOEstimateAvailability = "available";
    r.CFOValueStatus = "MEASURED";
else
    r.CFOEstimateAvailability = "missing";
    r.CFOValueStatus = "NOT_AVAILABLE";
end
r.CollisionFlag = double(logical(sixgr.util.structGet(ra, "CollisionDetected", false)));
detectedSet=sixgr.util.structGet(ra,'DetectedPRACHPreambles',struct([]));
receivedIndices=zeros(0,1);
if ~isempty(detectedSet), receivedIndices=reshape([detectedSet.DetectedPreambleIndex],[],1);
elseif preambleDetected, receivedIndices=r.DetectedPreambleIndex;
end
r.DetectedPreambleSetAvailable = logical(sixgr.util.structGet(ra,'DetectedPreambleSetAvailable',false));
if r.DetectedPreambleSetAvailable
    r.DetectedPreambleSet = strjoin(string(receivedIndices.'),'|');
end
r.DetectionPopulationScope = "per_target_shared_occasion_not_independent_trials";
% A different UE's real preamble is not a false alarm. The complete
% transmitted occasion population is not available to this per-UE exporter.
r.FalseAlarm = NaN;
r.FalseAlarmFlag = NaN;
r.FalseAlarmClassification="unavailable_complete_transmitted_occasion_set_not_retained";
r.MissedDetection = ~ismember(double(r.PreambleIndex),receivedIndices);
% Msg1 is preamble detection, not a CRC-protected transport block. Overall
% procedure acceptance belongs in StrictOk/RACompleted; the actual Msg2,
% Msg3, Msg4 and SetupComplete CRCs remain in their named receiver fields.
r.CRCPass = NaN;
r.CRCApplicable = false;
r.CRCOutcome = "not_applicable";
r.DetectionSuccess = preambleDetected;
r.DetectionAttempted = true;
r.DetectionUsable = preambleDetected && isfinite(double(r.DetectionMetric));
r.MeasurementAttempted = true;
r.MeasurementUsable = strictOk;
r.ReceiverUsable = strictOk;
r.DecodeAttempted = true;
r.DecodeUsable = strictOk;
r.StrictReceiverEvidenceOk = strictOk;
r.StrictOk = strictOk;
if strictOk
    r.Status = "PASS";
    r.RAStage = "RA_SUCCESS";
    if logical(sixgr.util.structGet(ra, "RequireRRCSetupComplete", false))
        r.Notes = "strict_initial_access_waveform_chain_completed_msg1_msg2_msg3_msg4_rrc_setup_complete";
    else
        r.Notes = "strict_four_step_ra_waveform_chain_completed_msg1_msg2_msg3_msg4";
    end
else
    r.Status = "FAIL";
    r.RAStage = string(sixgr.util.structGet(ra, "ObservedFailureStage", ""));
    r.Notes = "strict_four_step_ra_waveform_chain_failed:" + string(sixgr.util.structGet(ra, "FailureReason", ""));
end
r.RAFailureReason = string(sixgr.util.structGet(ra, "FailureReason", ""));
r.TruthStatus = "real_lls_evidence";
r.SourceClassification = "active_integrated";
if logical(sixgr.util.structGet(ra, "RequireRRCSetupComplete", false))
    r.RuntimeMaterializationStatus = "active_integrated_initial_access_waveform_msg1_msg2_msg3_msg4_rrc_setup_complete";
else
    r.RuntimeMaterializationStatus = "active_integrated_four_step_ra_waveform_msg1_msg2_msg3_msg4";
end
r.ControlGatingEffect = "random_access_gate_full_four_step_ra";
r.RuntimeStateConsumer = "CoupledTruthRuntime.applyPRACHTrial";
r.RuntimeConsumer = "CoupledTruthRuntime.applyPRACHTrial";
r.RuntimeEvidenceSource = "sixgr.phy.ra.runFourStepRA";
r.FullRAEvidenceSource = "sixgr.phy.ra.runFourStepRA";
r.FullRAArtifactRunFolder = "control/csv";
% The component collector has no runtime slot owner. A real four-step
% waveform can execute in isolation without attaching a runtime UE.
if ~isfinite(slotIdx)
    r.SourceClassification = "isolated_component_waveform";
    r.RuntimeMaterializationStatus = "isolated_four_step_ra_waveform_evidence";
    r.ControlGatingEffect = "none_isolated_component";
    r.RuntimeStateConsumer = "none_isolated_component";
    r.RuntimeConsumer = "none_isolated_component";
end
end

function T = localBuildFourStepRACorrelationTraceTable(ra, prachRow, cfg, snr_dB, trialIdx)
T=sixgr.truth.buildFourStepRACorrelationTraceTable(ra,prachRow,cfg,snr_dB,trialIdx);
end

function tables = localEmptyRAEvidenceTables()
names = localRAEvidenceTableNames();
tables = struct();
for i = 1:numel(names)
    name = names(i);
    if ismember(name, ["ra_negative_trials", "ra_collision_trials", "ra_retry_events"])
        tables.(char(name)) = ...
            sixgr.phy.ra.emptyOptionalEvidenceTable(name);
    else
        tables.(char(name)) = table();
    end
end
end

function out = localAppendRAEvidenceTables(out, in)
if nargin < 1 || ~isstruct(out) || isempty(fieldnames(out))
    out = localEmptyRAEvidenceTables();
end
if nargin < 2 || ~isstruct(in)
    return;
end
names = unique([localRAEvidenceTableNames(), string(fieldnames(in)).'], "stable");
for i = 1:numel(names)
    f = char(names(i));
    if ~isfield(out, f)
        out.(f) = table();
    end
    if isfield(in, f) && istable(in.(f))
        if isempty(out.(f)) && width(out.(f)) == 0 && width(in.(f)) > 0
            % Preserve the producer-owned schema even when the optional
            % campaign emitted no runtime rows.
            out.(f) = in.(f)(zeros(0, 1), :);
        end
        if ~isempty(in.(f))
            out.(f) = localAppendCompatTable(out.(f), in.(f));
        end
    end
end
end

function localWriteRAEvidenceTables(rootRunFolder, tables)
if strlength(string(rootRunFolder)) == 0 || ~isstruct(tables)
    return;
end
layout = sixgr.report.resultLayout(rootRunFolder);
names = localRAEvidenceTableNames();
for i = 1:numel(names)
    f = char(names(i));
    if isfield(tables, f) && istable(tables.(f)) && ...
            (~isempty(tables.(f)) || width(tables.(f)) > 0)
        artifactPath = fullfile(layout.ControlCSVDir, string(f) + ".csv");
        if ~isempty(tables.(f)) || exist(artifactPath, "file") ~= 2
            sixgr.util.csvWriteTable(artifactPath, tables.(f), ...
                "PreserveSchema", true);
        end
    end
end
if isfield(tables, "msg4_contention_resolution") && istable(tables.msg4_contention_resolution) && ...
        ~isempty(tables.msg4_contention_resolution)
    sixgr.util.csvWriteTable(fullfile(layout.ControlCSVDir, "msg4_trials.csv"), ...
        tables.msg4_contention_resolution);
end
end

function names = localRAEvidenceTableNames()
names = ["ra_attempts","ra_state_transitions","msg1_prach_detection", ...
    "msg1_detected_candidates", ...
    "ra_retry_events","ra_power_reference_decisions","initial_access_horizon", ...
    "rar_monitoring_observations","rar_monitoring_candidates","rar_monitoring_decoded_fields", ...
    "contention_monitoring_observations","ue_contention_events", ...
    "msg2_rar_trials","msg2_pdcch_candidates","msg2_dci_fields","msg4_dci_fields","msg3_pusch_trials", ...
    "msg4_contention_resolution","rrc_connection_events","rrc_setup_complete", ...
    "ra_timer_events","ra_negative_trials", ...
    "ra_collision_trials","ra_oracle_guard","ra_runtime_stage_waveforms", ...
    "ra_receiver_rf_observations"];
end

function [T,updatedRuntimeChannelState,observedRET,allocatedRECoordinates,channelEstimates] = localCollectPDCCHTrials( ...
        cfg,snr_dB,nTrials,grantContext,initialRuntimeChannelState,occupiedRECoordinates)
nTrials = max(1, round(double(nTrials)));
rows = repmat(localMakeLinkTrialRow(cfg, "DL", snr_dB, 1), nTrials, 1);
if nargin < 4 || ~isstruct(grantContext)
    grantContext = struct();
end
if nargin < 5 || ~isstruct(initialRuntimeChannelState)
    initialRuntimeChannelState = struct();
end
updatedRuntimeChannelState = initialRuntimeChannelState;
observedRET = table();
channelEstimates = table();
allocatedRECoordinates = zeros(0,2);
reserveControlResources = nargin >= 6;
if reserveControlResources && nTrials ~= 1
    error("sixgr:truth:PDCCHReservationTrialScope", ...
        "A shared control-slot reservation must execute one scheduled DCI at a time.");
end
dciBitsSeed = int8([]);
if isstruct(sixgr.util.structGet(grantContext, "DCI", struct()))
    dciBitsSeed = int8(sixgr.util.structGet(sixgr.util.structGet(grantContext, "DCI", struct()), "Bits", int8([])));
end
for k = 1:nTrials
    r = localMakeLinkTrialRow(cfg, "DL", snr_dB, k);
    r.Status = "FAIL";
    % A generation/propagation exception is not a measured CRC failure.
    r.CRCPass = NaN;
    r.CRCApplicable = false;
    try
        cfgTrial = localResolvePDCCHTrialConfig(cfg, snr_dB, k, nTrials, grantContext);
        grantRNTI = double(sixgr.util.structGet(grantContext, "RNTI", ...
            sixgr.util.structGet(cfgTrial, "phy.pdsch.RNTI", ...
            sixgr.util.structGet(cfgTrial, "phy.pdcch.rnti", NaN))));
        txArgs = {};
        if isfinite(grantRNTI)
            txArgs = [txArgs {"RNTI", grantRNTI}]; %#ok<AGROW>
        end
        if ~isempty(dciBitsSeed)
            txArgs = [txArgs {"DCIBits", dciBitsSeed}]; %#ok<AGROW>
        elseif ~isempty(fieldnames(grantContext))
            error('sixgr:truth:MissingScheduledPDCCHPayload', ...
                'A scheduler DCI must use the actual finalized grant payload.');
        else
            payloadBits=sixgr.util.structGet(cfgTrial,'phy.pdcch.configuredPayloadBits', ...
                sixgr.util.structGet(cfgTrial,'phy.pdcch.dciPayloadBits',[]));
            validateattributes(payloadBits,{'numeric'},{'scalar','finite','integer','positive'});
            txArgs = [txArgs {"K", payloadBits}]; %#ok<AGROW>
        end
        if reserveControlResources
            txArgs = [txArgs {"ReservedRECoordinates", occupiedRECoordinates}]; %#ok<AGROW>
        end
        preparedPDCCH = sixgr.link.preparePDCCHTransmission(cfgTrial,txArgs{:});
        tx = preparedPDCCH.Tx;
        txInfo = preparedPDCCH.TxInfo;
        allocatedRECoordinates = txInfo.AllocatedRECoordinates;
        observedSlot0 = double(sixgr.util.structGet(cfgTrial, ...
            "lls6g.runtime.AbsoluteSlotIndex0", tx.Carrier.NSlot));
        pdcchTx = struct("Carrier", tx.Carrier, "Grid", tx.Grid, ...
            "PDCCHIndices", tx.PDCCHInd, "DMRSIndices", tx.DMRSInd);
        pdcchRET = sixgr.truth.buildObservedREAllocation(pdcchTx, ...
            "Direction", "DL", "Channel", "PDCCH", ...
            "AbsoluteSlot", observedSlot0, ...
            "CellID", double(tx.Carrier.NCellID), ...
            "UEID", double(sixgr.util.structGet(grantContext, "UEIndex", NaN)), ...
            "AllocationID", "pdcch_slot_" + string(observedSlot0));
        [rxWave,nVar,replay,updatedRuntimeChannelState] = ...
            localApplyPDCCHChannelAndNoise(preparedPDCCH,snr_dB,updatedRuntimeChannelState);
        observedRET = localAppendCompatTable(observedRET,pdcchRET);
        runtimeChannelUsed = logical(sixgr.util.structGet( ...
            replay,"RuntimeChannelStateUsed",false));
        fadingChannelApplied = logical(sixgr.util.structGet( ...
            replay,"ChannelFadingApplied",false));
        if runtimeChannelUsed && fadingChannelApplied
            % A retained fading channel owns its absolute execution clock.
            % Its replay origin must therefore be present and agree with
            % the scheduled PDCCH occasion checked by receive completion.
            origin = double(sixgr.util.structGet( ...
                replay,"RuntimeChannelStartSample",NaN));
            if ~isfinite(origin)
                error('sixgr:truth:PDCCHRuntimeChannelOriginMissing', ...
                    'A retained PDCCH fading execution must expose its absolute sample origin.');
            end
        else
            % Identity/AWGN/RF replay metadata can contain a local zero
            % origin even though no fading channel clock executed.
            % The actual scheduled producer clock is authoritative here.
            origin = preparedPDCCH.RuntimeStartSample;
            if ~isfinite(origin)
                origin = 0; % Standalone capture without a scheduled absolute origin.
            end
        end
        observation = sixgr.phy.waveform.WaveformObservationBuffer( ...
            origin,origin+size(rxWave,1),preparedPDCCH.SampleRateHz,size(rxWave,2));
        observation.append(sixgr.phy.waveform.WaveformChunk(rxWave,origin),preparedPDCCH.SampleRateHz);
        if nargout>=5
            [r,~,H]=localCompletePDCCHTrial(preparedPDCCH,observation,grantContext,snr_dB,k,nVar,replay);
            if ~isempty(H)
                n=height(H);
                H.AbsoluteSlot0=repmat(observedSlot0,n,1);
                H.TrialIndex=repmat(double(k),n,1);
                H.UEIndex=repmat(double(sixgr.util.structGet(cfgTrial,"lls6g.userContext.UEIndex",NaN)),n,1);
                H.ServingCell=repmat(double(sixgr.util.structGet(cfgTrial,"lls6g.userContext.RuntimeServingCell",NaN)),n,1);
                H.SNR_dB=repmat(double(snr_dB),n,1);
                H.ObservationStartSample=repmat(double(observation.StartSample),n,1);
                H.ObservationEndSampleExclusive=repmat(double(observation.EndSampleExclusive),n,1);
                H.GrantDirection=repmat(string(sixgr.util.structGet(grantContext,"Direction","DL")),n,1);
                H.Direction=repmat("DL",n,1);
                H.SignalName=repmat("PDCCH",n,1);
                channelEstimates=localAppendCompatTable(channelEstimates,H);
            end
        else
            r = localCompletePDCCHTrial(preparedPDCCH,observation,grantContext,snr_dB,k,nVar,replay);
        end
    catch ME
        r.Crash = true;
        r.Status = "CRASH";
        r.FailureReason = string(ME.identifier);
        r.Notes = string(ME.message);
        if strcmp(ME.identifier, 'sixgr:phy:pdcch:NoFreeCandidate')
            r.Crash = false;
            r.Status = "BLOCKED";
            r.CRCPass = NaN;
            r.CRCApplicable = false;
            r.DecodeAttempted = false;
            r.DecodeUsable = false;
            r.DetectionAttempted = false;
            r.DetectionUsable = false;
            r.MeasurementAttempted = false;
            r.MeasurementUsable = false;
            r.ReceiverUsable = false;
            r.BlockingFlag = 1;
            r.UsedCCECount = 0;
            r.FailureReason = "control_blocked_no_nonoverlapping_pdcch_candidate";
        end
    end
    rows(k) = r;
end
T = struct2table(rows);
end

function varargout = localCompletePDCCHTrial(varargin)
% Compatibility delegate; the implementation and schema have one owner.
[varargout{1:nargout}] = sixgr.truth.PDCCHControlRuntime.receiveTrial(varargin{:});
end

function varargout = localThermalNoiseSINRUnavailable(varargin)
% Compatibility delegate; the implementation and schema have one owner.
[varargout{1:nargout}] = sixgr.truth.PDCCHControlRuntime.thermalNoiseSINRUnavailable(varargin{:});
end

function varargout = localMarkControlSINRUnavailable(varargin)
% Compatibility delegate; the implementation and schema have one owner.
[varargout{1:nargout}] = sixgr.truth.PDCCHControlRuntime.markControlSINRUnavailable(varargin{:});
end

function [y,nVar,replay,updatedRuntimeChannelState] = ...
        localApplyPDCCHChannelAndNoise(prepared,snr_dB,initialRuntimeChannelState)
cfg = prepared.ReceiverConfig;
tx = prepared.Tx;
txInfo = prepared.TxInfo;
x = prepared.TransmitSamples;
if nargin < 3 || ~isstruct(initialRuntimeChannelState)
    initialRuntimeChannelState = struct();
end
if ~isfield(txInfo, "OFDM")
    try
        txInfo.OFDM = nrOFDMInfo(tx.Carrier);
    catch
        txInfo.OFDM = struct();
    end
end
% Execute the same physical ordering used by data channels: configured
% transmit power/PA, transmitter RF, per-link fading, large-scale loss,
% thermal noise, then the shared receiver RF/ADC.  PDCCH must not apply a
% combined RF chain after the channel or inject noise after the ADC.
[x,powerContext] = sixgr.rf.applyPowerContext(x,cfg,"DL",txInfo);
cfg = sixgr.util.structSet(cfg,"lls6g.runtimePowerContext",powerContext);
sampleRateHz = localResolvePDCCHSampleRate(tx,txInfo);
txRfOut = sixgr.rf.applyRFImpairmentChain(x,cfg, ...
    "SampleRateHz",sampleRateHz, ...
    "Direction","DL", ...
    "MeasurementPoint","tx_output", ...
    "Endpoint","tx", ...
    "StrictMutationRequired",false, ...
    "UseLegacyGlobalConfig",false, ...
    "ApplyPA",false, ...
    "ApplyADC",false);
x = cast(txRfOut.Waveform,"like",x);
cfg = sixgr.util.structSet(cfg,"lls6g.txRFImpairmentReplay",txRfOut.Replay);
state = sixgr.link.initWaveformTruthChannelState(cfg,tx,txInfo, ...
    "InitialRuntimeChannelState",initialRuntimeChannelState);
sampleRateHz = double(sixgr.util.structGet(state, "SampleRate_Hz", localResolvePDCCHSampleRate(tx, txInfo)));
y = x;
replay = struct( ...
    "ConfiguredSNR_dB", double(snr_dB), ...
    "AppliedAWGNSNR_dB", double(snr_dB), ...
    "InjectedNoiseVariance", NaN, ...
    "NoiseVarianceSource", "", ...
    "ChannelModelApplied", string(sixgr.util.structGet(cfg, "channel.model", "AWGN")), ...
    "ChannelFadingApplied", false, ...
    "PowerContext",powerContext, ...
    "PowerContextAmplitudeUnit",string(powerContext.WaveformAmplitudeUnit), ...
    "PowerContextTotalTxPower_dBm",double(powerContext.TotalTxPower_dBm), ...
    "TxRFExecutionStatus",string(sixgr.util.structGet( ...
        txRfOut.Replay,"RFExecutionStatus","applied_or_identity")), ...
    "TxRFStageOrder",string(sixgr.util.structGet( ...
        txRfOut.Replay,"RFStageOrder","")), ...
    "TxRFAppliedStageCount",double(sixgr.util.structGet( ...
        txRfOut.Replay,"RFAppliedStageCount",0)));

[y, channelReplay, state] = sixgr.link.applyRuntimeFadingChannel(x, state); %#ok<ASGLU>
chFields = fieldnames(channelReplay);
for chIdx = 1:numel(chFields)
    replay.(chFields{chIdx}) = channelReplay.(chFields{chIdx});
end

cfgReplay = sixgr.util.structSet(cfg, "channel.snr_dB", double(snr_dB));
% Large-scale link budget belongs between channel and receiver noise.  RF
% execution is split across the already-completed TX boundary and the
% composite RX boundary below.
[y, impairmentReplay] = sixgr.link.applyWaveformImpairments(y, ...
    cfgReplay,sampleRateHz,"ApplyRFChain",false);
fields = fieldnames(impairmentReplay);
for ii = 1:numel(fields)
    replay.(fields{ii}) = impairmentReplay.(fields{ii});
end
replay.ChannelModelApplied = string(sixgr.util.structGet(cfg, "channel.model", replay.ChannelModelApplied));
replay.ChannelFadingApplied = logical(sixgr.util.structGet(channelReplay, "ChannelFadingApplied", false));
desiredWaveform = y;
[preFrontEndWaveform, preFrontEndNVar, noiseInfo] = ...
    localPDCCHAddAwgnFromReplay(y,replay,desiredWaveform,txInfo);
replay.InjectedNoiseVariance = double(preFrontEndNVar);
noiseFields = fieldnames(noiseInfo);
for ni = 1:numel(noiseFields)
    replay.(noiseFields{ni}) = noiseInfo.(noiseFields{ni});
end
if isfinite(preFrontEndNVar) && preFrontEndNVar > 0 && ...
        strlength(strtrim(string(sixgr.util.structGet( ...
        replay,"NoiseVarianceSource","")))) == 0
    replay.NoiseVarianceSource = "pdcch_replay_reference_waveform_awgn";
end
[y,replay] = sixgr.link.applyCompositeReceiverFrontEnd( ...
    preFrontEndWaveform,cfgReplay,sampleRateHz,replay,"Direction","DL");
replay = sixgr.link.applyCompositeFrontEndVarianceReplay(replay);
nVar = double(sixgr.util.structGet(replay, ...
    "InjectedNoiseVariancePostCompositeFrontEnd",preFrontEndNVar));
% A nonlinear receiver cannot be replayed independently on noise and then
% described as the disturbance in the original capture. Use its resolved
% input-to-output variance where valid, or actual received DM-RS estimation.
updatedRuntimeChannelState = sixgr.util.structGet( ...
    state,"RuntimeChannelState",struct());
end

function sampleRateHz = localResolvePDCCHSampleRate(tx, txInfo)
sampleRateHz = [];
if isstruct(txInfo)
    sampleRateHz = sixgr.util.structGet(txInfo, "OFDM.SampleRate", []);
end
if isempty(sampleRateHz) && isstruct(tx)
    try
        ofdmInfo = nrOFDMInfo(tx.Carrier);
        sampleRateHz = double(sixgr.util.structGet(ofdmInfo, "SampleRate", []));
    catch
        sampleRateHz = [];
    end
end
if isempty(sampleRateHz) || ~(isscalar(sampleRateHz) && isfinite(double(sampleRateHz)) && double(sampleRateHz) > 0)
    error('sixgr:truth:PDCCHSampleRateUnavailable', ...
        'PDCCH noise and timing require its actual OFDM sample rate.');
else
    sampleRateHz = double(sampleRateHz);
end
end

function [y, nVar, noiseInfo] = localPDCCHAddAwgnFromReplay(x, replay, referenceWaveform, txInfo)
noiseInfo = localPDCCHNoiseCalibrationInfo(x, referenceWaveform, NaN, "unavailable", replay);
noiseMode = string(sixgr.util.structGet(replay, "NoiseOperatingMode", "receiver_noise_figure_thermal_noise"));
if noiseMode == "receiver_noise_figure_thermal_noise"
    nVar = localPDCCHResolveThermalNoiseVariance(replay, referenceWaveform, txInfo);
    noiseInfo = localPDCCHNoiseCalibrationInfo(x, referenceWaveform, nVar, "thermal_noise_plus_receiver_nf", replay);
    if isfinite(nVar) && nVar > 0
        n = sqrt(nVar / 2) .* (randn(size(x), "like", real(x)) + 1i * randn(size(x), "like", real(x)));
        y = x + cast(n, "like", x);
        return;
    end
    error('sixgr:truth:PDCCHNoiseVarianceUnavailable', ...
        'The receiver thermal-noise operating mode requires a resolved physical noise PSD and sample rate.');
elseif noiseMode=="absolute_reference_esn0"
    nVar=sixgr.link.resolveAbsoluteReferenceNoiseVariance(replay);
    noiseInfo=localPDCCHNoiseCalibrationInfo(x,referenceWaveform,nVar, ...
        "absolute_nominal_reference_PSD_times_actual_sample_rate_sqrt_mW",replay);
    noiseInfo.AbsoluteReferenceNoiseInjectedSampleVariance_mW=nVar;
    noiseInfo.AbsoluteReferenceNoiseInjectionDomain='receiver_sample_waveform_pre_composite_front_end';
    n=sqrt(nVar/2).*(randn(size(x),"like",real(x))+1i*randn(size(x),"like",real(x)));
    y=x+cast(n,"like",x);
    return;
elseif noiseMode~="standalone_awgn_snr_argument"
    error('sixgr:truth:PDCCHNoiseVarianceUnavailable','Unsupported PDCCH noise mode %s.',noiseMode);
end
appliedSNR_dB = double(sixgr.util.structGet(replay, "AppliedAWGNSNR_dB", NaN));
nVar = localPDCCHResolveConfiguredSNRNoiseVariance(referenceWaveform, appliedSNR_dB, txInfo);
noiseInfo = localPDCCHNoiseCalibrationInfo(x, referenceWaveform, nVar, "standalone_awgn_snr_argument_post_channel_units", replay);
if isfinite(nVar) && nVar >= 0
    if nVar > 0
        n = sqrt(nVar / 2) .* (randn(size(x), "like", real(x)) + 1i * randn(size(x), "like", real(x)));
        y = x + cast(n, "like", x);
    else
        y = x;
    end
    return;
end
error('sixgr:truth:PDCCHNoiseVarianceUnavailable', ...
    'Configured-SNR noise requires the actual useful-symbol signal power and resolved SNR.');
end

function info = localPDCCHNoiseCalibrationInfo(compositeWaveform, desiredWaveform, nVar, source, replay)
desiredPower = NaN;
compositePower = NaN;
if ~isempty(desiredWaveform)
    desiredPower = mean(abs(double(desiredWaveform(:))).^2, "omitnan");
end
if ~isempty(compositeWaveform)
    compositePower = mean(abs(double(compositeWaveform(:))).^2, "omitnan");
end
appliedSNR = double(sixgr.util.structGet(replay, "AppliedAWGNSNR_dB", NaN));
if isfinite(desiredPower) && desiredPower > 0 && isfinite(nVar) && nVar > 0
    appliedSNR = 10 * log10(desiredPower / nVar);
end
info = struct( ...
    "DesiredSignalPowerBeforeNoise", double(desiredPower), ...
    "CompositeSignalPowerBeforeNoise", double(compositePower), ...
    "AppliedNoiseSNR_dB", double(appliedSNR), ...
    "NoiseVarianceSource", char(string(source)));
end

function nVar = localPDCCHResolveConfiguredSNRNoiseVariance(referenceWaveform, snr_dB, txInfo)
nVar = NaN;
snr_dB = double(snr_dB);
if ~(isscalar(snr_dB) && isfinite(snr_dB)) || isempty(referenceWaveform)
    return;
end
refPower = localPDCCHUsefulOFDMReferencePower(referenceWaveform, txInfo);
if ~(isfinite(refPower) && refPower >= 0)
    return;
end
nVar = refPower / max(10.^(snr_dB / 10), eps);
end

function nVar = localPDCCHResolveThermalNoiseVariance(replay, referenceWaveform, txInfo) %#ok<INUSD>
nVar = sixgr.link.resolveReceiverThermalNoiseVariance(replay);
end

function refPower = localPDCCHUsefulOFDMReferencePower(waveform, txInfo)
refPower = NaN;
if isempty(waveform)
    return;
end
ofdmInfo = sixgr.util.structGet(txInfo, "OFDM", struct());
nfft = double(sixgr.util.structGet(ofdmInfo, "Nfft", NaN));
cpLens = double(sixgr.util.structGet(ofdmInfo, "CyclicPrefixLengths", []));
if ~(isfinite(nfft) && nfft > 0 && ~isempty(cpLens))
    refPower = mean(abs(double(waveform(:))).^2, "omitnan");
    return;
end
cpLens = cpLens(:);
idx = [];
offset = 0;
nSamp = size(waveform, 1);
while offset < nSamp
    for s = 1:numel(cpLens)
        cp = max(0, round(double(cpLens(s))));
        useful = offset + cp + (1:round(nfft));
        useful = useful(useful <= nSamp);
        idx = [idx useful]; %#ok<AGROW>
        offset = offset + cp + round(nfft);
        if offset >= nSamp
            break;
        end
    end
end
if isempty(idx)
    refPower = mean(abs(double(waveform(:))).^2, "omitnan");
else
    refPower = mean(abs(double(waveform(idx, :))).^2, "all", "omitnan");
end
end

function varargout = localBuildMissingPDCCHGrantBindingTrial(varargin)
% Compatibility delegate; the implementation and schema have one owner.
[varargout{1:nargout}] = sixgr.truth.PDCCHControlRuntime.buildMissingPDCCHGrantBindingTrial(varargin{:});
end

function varargout = localPDCCHDecodeFailureReason(varargin)
% Compatibility delegate; the implementation and schema have one owner.
[varargout{1:nargout}] = sixgr.truth.PDCCHControlRuntime.pdcchDecodeFailureReason(varargin{:});
end

function varargout = localPDCCHStrictFailureReason(varargin)
% Compatibility delegate; the implementation and schema have one owner.
[varargout{1:nargout}] = sixgr.truth.PDCCHControlRuntime.pdcchStrictFailureReason(varargin{:});
end

function varargout = localResolvePDCCHTrialConfig(varargin)
% Compatibility delegate; the implementation and schema have one owner.
[varargout{1:nargout}] = sixgr.truth.PDCCHControlRuntime.resolvePDCCHTrialConfig(varargin{:});
end

function varargout = localSelectPDCCHAggregationLevel(varargin)
% Compatibility delegate; the implementation and schema have one owner.
[varargout{1:nargout}] = sixgr.truth.PDCCHControlRuntime.selectPDCCHAggregationLevel(varargin{:});
end

function varargout = localAnnotateGrantControlTrial(varargin)
% Compatibility delegate; the implementation and schema have one owner.
[varargout{1:nargout}] = sixgr.truth.PDCCHControlRuntime.annotateGrant(varargin{:});
end

function varargout = localResolvePDCCHGrantBinding(varargin)
% Compatibility delegate; the implementation and schema have one owner.
[varargout{1:nargout}] = sixgr.truth.PDCCHControlRuntime.resolvePDCCHGrantBinding(varargin{:});
end

function varargout = localGrantBindingPayloadFromGrant(varargin)
% Compatibility delegate; the implementation and schema have one owner.
[varargout{1:nargout}] = sixgr.truth.PDCCHControlRuntime.grantBindingPayloadFromGrant(varargin{:});
end

function varargout = localGrantBindingPayloadFromDecodedRow(varargin)
% Compatibility delegate; the implementation and schema have one owner.
[varargout{1:nargout}] = sixgr.truth.PDCCHControlRuntime.grantBindingPayloadFromDecodedRow(varargin{:});
end

function varargout = localGrantBindingPayloadHash(varargin)
% Compatibility delegate; the implementation and schema have one owner.
[varargout{1:nargout}] = sixgr.truth.PDCCHControlRuntime.grantBindingPayloadHash(varargin{:});
end

function varargout = localBindingNumbersMatch(varargin)
% Compatibility delegate; the implementation and schema have one owner.
[varargout{1:nargout}] = sixgr.truth.PDCCHControlRuntime.bindingNumbersMatch(varargin{:});
end

function varargout = localBindingTextsMatch(varargin)
% Compatibility delegate; the implementation and schema have one owner.
[varargout{1:nargout}] = sixgr.truth.PDCCHControlRuntime.bindingTextsMatch(varargin{:});
end

function varargout = localTableText(varargin)
% Compatibility delegate; the implementation and schema have one owner.
[varargout{1:nargout}] = sixgr.truth.PDCCHControlRuntime.tableText(varargin{:});
end

function varargout = localTableNumber(varargin)
% Compatibility delegate; the implementation and schema have one owner.
[varargout{1:nargout}] = sixgr.truth.PDCCHControlRuntime.tableNumber(varargin{:});
end

function varargout = localTableLogical(varargin)
% Compatibility delegate; the implementation and schema have one owner.
[varargout{1:nargout}] = sixgr.truth.PDCCHControlRuntime.tableLogical(varargin{:});
end

function varargout = ternaryBinding(varargin)
% Compatibility delegate; the implementation and schema have one owner.
[varargout{1:nargout}] = sixgr.truth.PDCCHControlRuntime.ternaryBinding(varargin{:});
end

function varargout = localFirstFinite(varargin)
% Compatibility delegate; the implementation and schema have one owner.
[varargout{1:nargout}] = sixgr.truth.PDCCHControlRuntime.firstFinite(varargin{:});
end


function varargout = localPDCCHAvailableCCEs(varargin)
% Compatibility delegate; the implementation and schema have one owner.
[varargout{1:nargout}] = sixgr.truth.PDCCHControlRuntime.pdcchAvailableCCEs(varargin{:});
end

function varargout = localPDCCHScalar(varargin)
% Compatibility delegate; the implementation and schema have one owner.
[varargout{1:nargout}] = sixgr.truth.PDCCHControlRuntime.pdcchScalar(varargin{:});
end

function varargout = localPDCCHScalarVector(varargin)
% Compatibility delegate; the implementation and schema have one owner.
[varargout{1:nargout}] = sixgr.truth.PDCCHControlRuntime.pdcchScalarVector(varargin{:});
end

function value = localFiniteOrNaN(value)
value = double(value);
if ~(isscalar(value) && isfinite(value))
    value = NaN;
end
end

function varargout = localHasFiniteNumericEvidence(varargin)
% Compatibility delegate; the implementation and schema have one owner.
[varargout{1:nargout}] = sixgr.truth.PDCCHControlRuntime.hasFiniteNumericEvidence(varargin{:});
end

function varargout = localComplexSHA256(varargin)
% Compatibility delegate; the implementation and schema have one owner.
[varargout{1:nargout}] = sixgr.truth.PDCCHControlRuntime.complexSHA256(varargin{:});
end

function varargout = localPDCCHResourceHash(varargin)
% Compatibility delegate; the implementation and schema have one owner.
[varargout{1:nargout}] = sixgr.truth.PDCCHControlRuntime.pdcchResourceHash(varargin{:});
end

function varargout = localResolvePDCCHGrantDCIFormat(varargin)
% Compatibility delegate; the implementation and schema have one owner.
[varargout{1:nargout}] = sixgr.truth.PDCCHControlRuntime.resolvePDCCHGrantDCIFormat(varargin{:});
end

function varargout = localDecodeObservedPDCCHGrantDCI(varargin)
% Compatibility delegate; the implementation and schema have one owner.
[varargout{1:nargout}] = sixgr.truth.PDCCHControlRuntime.decodeObservedPDCCHGrantDCI(varargin{:});
end

function varargout = localHashDecodedPDCCHGrantFields(varargin)
% Compatibility delegate; the implementation and schema have one owner.
[varargout{1:nargout}] = sixgr.truth.PDCCHControlRuntime.hashDecodedPDCCHGrantFields(varargin{:});
end

function T = localCollectPUCCHTrials(cfg, snr_dB, nTrials)
if isequal(sixgr.util.structGet(cfg, ...
        'validation.pucch_resources.component_probe.enabled',[]),false)
    % Explicitly disabled diagnostics do not create receiver attempts,
    % crash rows, or successful placeholder rows. Connected feedback is
    % collected independently by its actual scheduled runtime producer.
    T = localEmptyLinkTrialTable(0);
    return;
end
nTrials = max(1, round(double(nTrials)));
rows = repmat(localMakeLinkTrialRow(cfg, "UL", snr_dB, 1), nTrials, 1);
[rows.UEIndex] = deal(NaN);
[rows.RNTI] = deal(NaN);
for k = 1:nTrials
    r = localMakeLinkTrialRow(cfg, "UL", snr_dB, k);
    r.UEIndex = NaN;
    r.RNTI = NaN;
    r.Status = "FAIL";
    r.SourceClassification = "isolated_component_waveform";
    try
        [connected,carrier,probe] = sixgr.link.preparePUCCHComponentProbe(cfg,k);
        r.UEIndex = probe.UEID;
        r.RNTI = probe.RNTI;
        r.Slot = probe.SlotOneBased;
        r.Frame = floor(probe.AbsoluteSlotZeroBased/carrier.SlotsPerFrame)+1;
        r.Seed = probe.Seed;
        out = sixgr.link.runPUCCHWaveformTrial(connected.RuntimeConfig, ...
            "Carrier",carrier, ...
            "Assignment",connected.Assignment, ...
            "Report",connected.Report, ...
            "ReceiverContext",connected.ReceiverContext, ...
            "SNR_dB", snr_dB, ...
            "ChannelProfile",sixgr.channel.resolveConcreteProfile(cfg), ...
            "Seed",probe.Seed);
        ok = logical(sixgr.util.structGet(out, "Ok", false)) && ~logical(sixgr.util.structGet(out, "Skipped", false));
        r.TBSize_bits = double(probe.ExpectedBitCount);
        r.BitsCompared = double(sixgr.util.structGet(out, "BitsCompared", NaN));
        r.BitErrors = double(sixgr.util.structGet(out, "BitErrors", NaN));
        r.ExpectedBitCount = double(sixgr.util.structGet(out, "ExpectedBitCount", probe.ExpectedBitCount));
        r.DecodedBitCount = double(sixgr.util.structGet(out, "DecodedBitCount", NaN));
        r.UCIExpectedBitVector = string(sixgr.util.structGet(out, "UCIExpectedBitVector", ""));
        r.UCIDecodedBitVector = string(sixgr.util.structGet(out, "UCIDecodedBitVector", ""));
        r.UCIBitErrorVector = string(sixgr.util.structGet(out, "UCIBitErrorVector", ""));
        r.UCICodedBitCount = double(sixgr.util.structGet(out, "UCICodedBitCount", NaN));
        r.UCICRCBitCount = double(sixgr.util.structGet(out, "UCICRCBitCount", NaN));
        r.UCICRCApplicable = logical(sixgr.util.structGet(out, "UCICRCApplicable", false));
        r.CRCApplicable = logical(sixgr.util.structGet(out, "CRCApplicable", false));
        r.CRCOutcome = string(sixgr.util.structGet(out, "CRCOutcome", ...
            sixgr.link.pucchCRCOutcome(r.CRCApplicable, ...
            sixgr.util.structGet(out,"CRCPass",NaN))));
        r.UCIContentMatch = logical(sixgr.util.structGet(out, "UCIContentMatch", ok));
        r.DetectionOutcome = string(sixgr.util.structGet(out, "DetectionOutcome", "unavailable"));
        if logical(r.CRCApplicable)
            % Trial success also includes TX-bit comparison and detection.
            % Preserve the receiver CRC decision as its own observation.
            r.CRCPass = double(sixgr.util.structGet(out,"CRCPass",NaN));
        else
            r.CRCPass = NaN;
        end
        r.DetectionMetric = double(sixgr.util.structGet(out, "DetectionMetric", NaN));
        r.DetectionThreshold = double(sixgr.util.structGet(out, "DetectionThreshold", NaN));
        r.DetectionMetricStatus = string(sixgr.util.structGet(out, "DetectionMetricStatus", ""));
        r.DetectorPeakMetric = double(sixgr.util.structGet(out, "DetectorPeakMetric", NaN));
        r.DetectorNoiseFloor = double(sixgr.util.structGet(out, "DetectorNoiseFloor", NaN));
        r.DTXFlag = logical(sixgr.util.structGet(out, "DTXFlag", false));
        r.DTXReason = string(sixgr.util.structGet(out, "DTXReason", ""));
        r.ComputeLatency_ms = double(sixgr.util.structGet(out, "ComputeLatency_ms", NaN));
        r.DecodeLatency_ms = double(sixgr.util.structGet(out, "DecodeLatency_ms", NaN));
        r.AirInterfaceTTI_ms = double(sixgr.util.structGet(out, "AirInterfaceTTI_ms", NaN));
        r.AirInterfaceObservation_ms = double(sixgr.util.structGet(out, "AirInterfaceObservation_ms", r.AirInterfaceTTI_ms));
        % An isolated waveform has no HARQ/SR/CSI procedure timeline. A
        % missing receiver field is unavailable, not a measured zero delay.
        r.ProcedureDelay_ms = double(sixgr.util.structGet(out, "ProcedureDelay_ms", NaN));
        r.NoiseVariance = double(sixgr.util.structGet(out, "NoiseVariance", NaN));
        r.NoiseVarStatus = string(sixgr.util.structGet(out, "NoiseVarStatus", ""));
        r.NoiseVarSource = string(sixgr.util.structGet(out, "NoiseVarSource", ""));
        r.NoiseVarReason = string(sixgr.util.structGet(out, "NoiseVarReason", ""));
        r.NoiseVarStrictFailure = logical(sixgr.util.structGet(out, "NoiseVarStrictFailure", false));
        r.ReceiverUsable = logical(sixgr.util.structGet(out, "ReceiverUsable", false));
        r.DetectionAttempted = logical(sixgr.util.structGet(out, "DetectionAttempted", false));
        r.DetectionSuccess = r.DetectionAttempted && r.DetectionOutcome == "detected";
        r.DetectionUsable = logical(sixgr.util.structGet(out, "DetectionUsable", false));
        r.FailureReason = string(sixgr.util.structGet(out, "FailureReason", ""));
        r.ChannelEstimateAttempted = logical(sixgr.util.structGet(out, "ChannelEstimateAttempted", false));
        r.ChannelEstimateAvailable = logical(sixgr.util.structGet(out, "ChannelEstimateAvailable", false));
        r.ChannelEstimateSource = string(sixgr.util.structGet(out, "ChannelEstimateSource", ""));
        r.ResourceExtractionAttempted = logical(sixgr.util.structGet(out, "ResourceExtractionAttempted", false));
        r.ResourceExtractionAvailable = logical(sixgr.util.structGet(out, "ResourceExtractionAvailable", false));
        r.EqualizationAttempted = logical(sixgr.util.structGet(out, "EqualizationAttempted", false));
        r.EqualizationAvailable = logical(sixgr.util.structGet(out, "EqualizationAvailable", false));
        for name=["EVM_rms","EVMReferenceSource","EVMValueStatus", ...
                "EVMSymbolCount","EVMErrorEnergy","EVMReferenceEnergy", ...
                string(fieldnames(sixgr.link.receivedWaveformEvidence())).']
            if isfield(out,name), r.(name)=out.(name); end
        end
        r.ConfiguredSNR_dB = double(sixgr.util.structGet(out, "ConfiguredSNR_dB", snr_dB));
        r.AppliedAWGNSNR_dB = double(sixgr.util.structGet(out, "AppliedAWGNSNR_dB", NaN));
        r.DesiredSignalPowerBeforeNoise = double(sixgr.util.structGet(out, "DesiredSignalPowerBeforeNoise", NaN));
        r.CompositeSignalPowerBeforeNoise = double(sixgr.util.structGet(out, "CompositeSignalPowerBeforeNoise", NaN));
        r.AppliedNoiseSNR_dB = double(sixgr.util.structGet(out, "AppliedNoiseSNR_dB", NaN));
        r.NoiseVarianceSource = string(sixgr.util.structGet(out, "NoiseVarianceSource", ""));
        r.ReceiverHestSINR_dB = double(sixgr.util.structGet(out, "ReceiverHestSINR_dB", NaN));
        r.ReceiverHestSINRApplicable = logical(sixgr.util.structGet(out, "ReceiverHestSINRApplicable", false));
        r.ReceiverHestSINRSource = string(sixgr.util.structGet(out, "ReceiverHestSINRSource", ""));
        r.ReceiverHestSINRValueRole = string(sixgr.util.structGet(out, "ReceiverHestSINRValueRole", ""));
        r.ReceiverHestSINRValueStatus = string(sixgr.util.structGet(out, "ReceiverHestSINRValueStatus", ""));
        r.ReceiverHestSINRNAReason = string(sixgr.util.structGet(out, "ReceiverHestSINRNAReason", ""));
        r.PostEqSINR_dB = double(sixgr.util.structGet(out, "PostEqSINR_dB", NaN));
        r.PostEqSINRSource = string(sixgr.util.structGet(out, "PostEqSINRSource", ""));
        r.PostEqSINRValueRole = string(sixgr.util.structGet(out, "PostEqSINRValueRole", ""));
        r.PostEqSINRValueStatus = string(sixgr.util.structGet(out, "PostEqSINRValueStatus", ""));
        r.PostEqSINRNAReason = string(sixgr.util.structGet(out, "PostEqSINRNAReason", ""));
        r.PostEqSINRPerLayer_dB = localFormatNumericVector(sixgr.util.structGet(out, "PostEqSINRPerLayer_dB", ""));
        r.ResidualInterLayerPowerMean=double(sixgr.util.structGet(out,'ResidualInterLayerPowerMean',NaN));
        r.ResidualInterLayerPowerPerLayer=localFormatNumericVector(sixgr.util.structGet(out,'ResidualInterLayerPowerPerLayer',[]));
        r.ResidualInterLayerPowerSource=string(sixgr.util.structGet(out,'ResidualInterLayerPowerSource',''));
        r.ResidualInterLayerPowerStatus=string(sixgr.util.structGet(out,'ResidualInterLayerPowerStatus','unavailable_receiver_trial'));
        r.MeasuredTrialSINR_dB = double(sixgr.util.structGet(out, "MeasuredTrialSINR_dB", NaN));
        r.MeasuredTrialSINRSource = string(sixgr.util.structGet(out, "MeasuredTrialSINRSource", ""));
        r.MeasuredTrialSINRValueRole = string(sixgr.util.structGet(out, "MeasuredTrialSINRValueRole", ""));
        r.MeasuredTrialSINRValueStatus = string(sixgr.util.structGet(out, "MeasuredTrialSINRValueStatus", ""));
        r.MeasuredTrialSINRNAReason = string(sixgr.util.structGet(out, "MeasuredTrialSINRNAReason", ""));
        r.MeasuredSINR_dB = double(sixgr.util.structGet(out, "MeasuredTrialSINR_dB", NaN));
        r.SINRValueRole = string(sixgr.util.structGet(out, "SINRValueRole", ""));
        r.SINRSource = string(sixgr.util.structGet(out, "SINRSource", ""));
        r.SINRValueStatus = string(sixgr.util.structGet(out, "SINRValueStatus", ""));
        r.SINRValueDefinition = string(sixgr.util.structGet(out, "SINRValueDefinition", ""));
        r.WidebandCQI = double(sixgr.util.structGet(out, "WidebandCQI", NaN));
        r.RankIndicator = double(sixgr.util.structGet(out, "RankIndicator", NaN));
        r.PMI = double(sixgr.util.structGet(out, "PMI", NaN));
        r.CRI = double(sixgr.util.structGet(out, "CRI", NaN));
        r.ChannelGain_dB = double(sixgr.util.structGet(out, "ChannelGain_dB", NaN));
        r.ConditionNumber_dB = double(sixgr.util.structGet(out, "ConditionNumber_dB", NaN));
        r.NumRxAntennas = double(sixgr.util.structGet(out, "NumRxAntennas", NaN));
        r.NumTxPorts = double(sixgr.util.structGet(out, "NumTxPorts", NaN));
        r.RequestedFormat = double(sixgr.util.structGet(out, "RequestedFormat", NaN));
        r.ResolvedFormat = double(sixgr.util.structGet(out, "ResolvedFormat", NaN));
        r.FormatAdapted = logical(sixgr.util.structGet(out, "FormatAdapted", false));
        r.FormatAdaptationReason = string(sixgr.util.structGet(out, "FormatAdaptationReason", ""));
        r.ControlResourceValidity = logical(sixgr.util.structGet(out, "ControlResourceValidity", false));
        r.ControlResourceSource = "runtime_pucch_waveform_resource_mapping";
        r.PUCCHFormat = double(sixgr.util.structGet(out, "PUCCHFormat", r.ResolvedFormat));
        r.PUCCHResourceId = string(sixgr.util.structGet(out, "PUCCHResourceId", ""));
        r.PUCCHPRBSet = string(sixgr.util.structGet(out, "PUCCHPRBSet", ""));
        r.PUCCHPRBStart = double(sixgr.util.structGet(out, "PUCCHPRBStart", NaN));
        r.PUCCHPRBCount = double(sixgr.util.structGet(out, "PUCCHPRBCount", NaN));
        r.PUCCHSymbolStart = double(sixgr.util.structGet(out, "PUCCHSymbolStart", NaN));
        r.PUCCHNumSymbols = double(sixgr.util.structGet(out, "PUCCHNumSymbols", NaN));
        r.PUCCHRECount = double(sixgr.util.structGet(out, "PUCCHRECount", NaN));
        r.PUCCHDMRSRECount = double(sixgr.util.structGet(out, "PUCCHDMRSRECount", NaN));
        r.PUCCHExpectedBitCount = double(sixgr.util.structGet(out, "PUCCHExpectedBitCount", r.ExpectedBitCount));
        r.PUCCHDecodedBitCount = double(sixgr.util.structGet(out, "PUCCHDecodedBitCount", r.DecodedBitCount));
        r.PUCCHControlSINR_dB = double(sixgr.util.structGet(out, "PUCCHControlSINR_dB", NaN));
        r.PUCCHReceiverEvidenceSource = string(sixgr.util.structGet(out, "PUCCHReceiverEvidenceSource", ""));
        r.PUCCHGridHash = string(sixgr.util.structGet(out, "PUCCHGridHash", ""));
        r.PUCCHWaveformHash = string(sixgr.util.structGet(out, "PUCCHWaveformHash", ""));
        r.StrictReceiverEvidenceOk = logical(sixgr.util.structGet(out, "StrictReceiverEvidenceOk", false));
        r.StrictOk = logical(sixgr.util.structGet(out, "StrictOk", false));
        r.DecodeAttempted = isfield(out,"Receiver") && ...
            isfield(out.Receiver,"DecodedSequence1");
        r.DecodeUsable = logical(r.StrictOk);
        r.MeasurementAttempted = true;
        r.MeasurementUsable = isfinite(r.PUCCHControlSINR_dB) || ...
            (isfinite(r.ReceiverHestSINR_dB) && ...
            sixgr.util.isAcceptableSINRStatus(r.ReceiverHestSINRValueStatus));
        r.ReceiverUsable = logical(r.StrictReceiverEvidenceOk);
        r.TruthStatus = "real_pucch_waveform_uci_receiver_evidence";
        r.RuntimeMaterializationStatus = "isolated_pucch_component_waveform_receiver_evidence";
        r.RuntimeIntegrationMode = "isolated_component_waveform";
        r.RuntimeTransportMode = "pucch_tx_runtime_channel_rf_noise_pucch_rx";
        r.RuntimeEvidenceSource = "sixgr.link.runPUCCHWaveformTrial";
        r.Crash = logical(sixgr.util.structGet(out, "Crash", false));
        r.Notes = probe.EvidenceScope + "; " + string(sixgr.util.structGet(out, "Notes", ""));
        if logical(r.StrictOk)
            r.Status = "PASS";
        elseif ~logical(r.DetectionUsable)
            r.Status = "NA";
            r.CRCPass = NaN;
        elseif logical(sixgr.util.structGet(out, "Crash", false))
            r.Status = "CRASH";
        elseif logical(sixgr.util.structGet(out, "Skipped", false))
            r.Status = "NA";
        end
    catch ME
        r.Crash = true;
        r.CRCPass = 0;
        r.Status = "CRASH";
        r.Notes = string(ME.message);
    end
    rows(k) = r;
end
T = struct2table(rows);
end

function [T, chState, observedRET] = localCollectSRSTrials(cfg, snr_dB, nTrials, chState, trialOffset, receivedOutput)
if nargin < 6, receivedOutput=[]; end
assert(isempty(receivedOutput) || nTrials==1, ...
    'sixgr:truth:SharedSRSReducerMultiplicity','One actual SRS reception produces one canonical trial row.');
if nargin < 4
    chState = [];
end
if nargin < 5
    trialOffset = 0;
end
nTrials = max(1, round(double(nTrials)));
observedRET = table();
template=localMakeLinkTrialRow(cfg, "UL", snr_dB, 1);
template.SRSConfigurationContextID="";
template.SRSNumPorts=NaN;
template.SRSConfigurationContextVersion=""; template.SRSConfigurationEpoch=NaN;
template.SRSResourceID=NaN; template.SRSResourceIDsJSON="";
rows = repmat(template, nTrials, 1);
for k = 1:nTrials
    r = localMakeLinkTrialRow(cfg, "UL", snr_dB, k);
    r.SRSConfigurationContextID="";
    r.SRSNumPorts=NaN;
    r.SRSConfigurationContextVersion=""; r.SRSConfigurationEpoch=NaN;
    r.SRSResourceID=NaN; r.SRSResourceIDsJSON="";
    r.Status = "FAIL";
    try
        srsArgs = {"SNR_dB", snr_dB, ...
            "TrialIndex", double(trialOffset) + k, "ChannelState", chState};
        if isfinite(double(trialOffset)) && double(trialOffset) > 0
            srsArgs = [srsArgs, {"SlotIndex", double(trialOffset)}]; %#ok<AGROW>
        end
        if isempty(receivedOutput)
            outSRS = sixgr.link.runSRSChannelEstimation(cfg, srsArgs{:});
        else
            outSRS = receivedOutput;
        end
        r.SRSConfigurationContextID=string(sixgr.util.structGet(outSRS,'SRSConfigurationContextID',""));
        r.SRSNumPorts=double(sixgr.util.structGet(outSRS,'SRSNumPorts',NaN));
        for field=["SRSConfigurationContextVersion","SRSConfigurationEpoch","SRSResourceID","SRSResourceIDsJSON"]
            r.(field)=sixgr.util.structGet(outSRS,field,r.(field));
        end
        r.RuntimeEvidenceSource = "sixgr.link.runSRSChannelEstimation";
        pilotEVM=sixgr.phy.srs.measureReceivedPilotEVM();
        for field=string(fieldnames(pilotEVM)).'
            r.(field)=sixgr.util.structGet(outSRS,field,pilotEVM.(field));
        end
        observedRET = localAppendCompatTable(observedRET, ...
            sixgr.util.structGet(outSRS, "ObservedREAllocationTable", table()));
        chState = sixgr.util.structGet(outSRS, "ChannelState", chState);
        ok = logical(sixgr.util.structGet(outSRS, "Ok", false)) && ~logical(sixgr.util.structGet(outSRS, "Skipped", false));
        r.NMSE_dB = double(sixgr.util.structGet(outSRS, "NMSE_dB", NaN));
        r.RawChannelNMSE_dB = double(sixgr.util.structGet( ...
            outSRS, "RawChannelNMSE_dB", NaN));
        r.ChannelNMSEPhaseAligned = logical(sixgr.util.structGet( ...
            outSRS, "ChannelNMSEPhaseAligned", false));
        r.ChannelNMSECommonPhaseRotation_rad = double(sixgr.util.structGet( ...
            outSRS, "ChannelNMSECommonPhaseRotation_rad", NaN));
        r.ChannelNMSEQualificationMode = string(sixgr.util.structGet( ...
            outSRS, "ChannelNMSEQualificationMode", "raw_complex_plane_aligned"));
        r.NMSEReferenceSource = string(sixgr.util.structGet(outSRS, "NMSEReferenceSource", ""));
        r.TrueChannelOracleAvailable = logical(sixgr.util.structGet(outSRS, "TrueChannelOracleAvailable", false));
        r.TrueChannelNMSE_dB = double(sixgr.util.structGet(outSRS, "TrueChannelNMSE_dB", r.NMSE_dB));
        r.ChannelNMSEThreshold_dB = double(sixgr.util.structGet(outSRS, "ChannelNMSEThreshold_dB", NaN));
        r.PilotResidualNMSE_dB = double(sixgr.util.structGet(outSRS, "PilotResidualNMSE_dB", NaN));
        % Detection evidence is the actual received pilot correlation,
        % never the negative of an independent true-channel NMSE score.
        r.DetectionMetric = double(sixgr.util.structGet(outSRS, ...
            "ReceiveTiming.CorrelationPeakEnergy", NaN));
        r.DetectionMetricStatus = "unavailable_received_correlation_peak";
        if isfinite(r.DetectionMetric)
            r.DetectionMetricStatus = "received_reference_correlation_peak_energy";
        end
        r.InjectedDoppler_Hz = double(sixgr.util.structGet(outSRS, "InjectedDoppler_Hz", NaN));
        r.EstimatedDopplerHz = double(sixgr.util.structGet(outSRS, "EstimatedDopplerHz", NaN));
        r.DopplerError_Hz = double(sixgr.util.structGet(outSRS, "DopplerError_Hz", NaN));
        phase=sixgr.link.srsPilotPhaseEvidence(outSRS);
        for field=string(fieldnames(phase)).', r.(field)=phase.(field); end
        r.QCLAccuracy = double(sixgr.util.structGet(outSRS, "QCLAccuracy", NaN));
        r.QCLMeasurementStatus = string(sixgr.util.structGet(outSRS,"QCLMeasurementStatus","unavailable"));
        r.InterpolationLoss_dB = double(sixgr.util.structGet(outSRS, "InterpolationLoss_dB", NaN));
        r.MismatchSensitivity_dB = double(sixgr.util.structGet(outSRS, "MismatchSensitivity_dB", NaN));
        r.ComputeLatency_ms = double(sixgr.util.structGet(outSRS, "ComputeLatency_ms", NaN));
        r.ProcedureDelay_ms = double(sixgr.util.structGet(outSRS, "ProcedureDelay_ms", NaN));
        r.AirInterfaceObservation_ms = double(sixgr.util.structGet(outSRS, "AirInterfaceObservation_ms", NaN));
        r.AcquisitionTime_ms = double(sixgr.util.structGet(outSRS, "AcquisitionTime_ms", NaN));
        r.TrackingFailureProbability = double(sixgr.util.structGet(outSRS, "TrackingFailure", NaN));
        r.NoiseVariance = double(sixgr.util.structGet(outSRS, "NoiseVariance", NaN));
        r.NoiseVarianceDomain = string(sixgr.util.structGet(outSRS,"NoiseVarianceDomain",""));
        r.InjectedSampleNoiseVariance = double(sixgr.util.structGet(outSRS,"InjectedSampleNoiseVariance",NaN));
        r.InjectedSampleNoiseVarianceDomain = string(sixgr.util.structGet(outSRS,"InjectedSampleNoiseVarianceDomain",""));
        r.InjectedSampleNoiseVarianceSource = string(sixgr.util.structGet(outSRS,"InjectedSampleNoiseVarianceSource",""));
        r.NoiseVarStatus = string(sixgr.util.structGet(outSRS, "NoiseVarStatus", ""));
        r.NoiseVarSource = string(sixgr.util.structGet(outSRS, "NoiseVarSource", ""));
        r.NoiseVarReason = string(sixgr.util.structGet(outSRS, "NoiseVarReason", ""));
        r.NoiseVarStrictFailure = logical(sixgr.util.structGet(outSRS, "NoiseVarStrictFailure", false));
        r.NoiseOperatingMode = string(sixgr.util.structGet(outSRS, "NoiseOperatingMode", ""));
        absoluteNoise=sixgr.link.absoluteReferenceNoisePublication(outSRS);
        for noiseField=string(fieldnames(absoluteNoise)).'
            r.(noiseField)=absoluteNoise.(noiseField);
        end
        r.NoisePowerSource = string(sixgr.util.structGet(outSRS, "NoisePowerSource", ""));
        r.ThermalNoisePower_dBm = double(sixgr.util.structGet(outSRS, "ThermalNoisePower_dBm", NaN));
        r.ServingRxPower_dBm = double(sixgr.util.structGet(outSRS, "ServingRxPower_dBm", NaN));
        r.ServingRxPowerSource = string(sixgr.util.structGet(outSRS, "ServingRxPowerSource", ""));
        r.PowerContextDirection = string(sixgr.util.structGet(outSRS, "PowerContextDirection", ""));
        r.PowerContextTotalTxPower_dBm = double(sixgr.util.structGet(outSRS, "PowerContextTotalTxPower_dBm", NaN));
        powerFields=sixgr.link.srsPowerControlEvidence();
        for field=string(fieldnames(powerFields)).'
            r.(field)=sixgr.util.structGet(outSRS,field,powerFields.(field));
        end
        r.TxRFExecutionStatus = string(sixgr.util.structGet(outSRS, "TxRFExecutionStatus", ""));
        r.TxRFStageOrder = string(sixgr.util.structGet(outSRS, "TxRFStageOrder", ""));
        r.TxRFAppliedStageCount = double(sixgr.util.structGet(outSRS, "TxRFAppliedStageCount", NaN));
        r.CompositeReceiverFrontEndApplied = logical(sixgr.util.structGet(outSRS, "CompositeReceiverFrontEndApplied", false));
        r.CompositeReceiverFrontEndStatus = string(sixgr.util.structGet(outSRS, "CompositeReceiverFrontEndStatus", ""));
        r.ConfiguredSNR_dB = double(sixgr.util.structGet(outSRS, "ConfiguredSNR_dB", snr_dB));
        r.AppliedAWGNSNR_dB = double(sixgr.util.structGet(outSRS, "AppliedAWGNSNR_dB", NaN));
        r.DesiredSignalPowerBeforeNoise = double(sixgr.util.structGet(outSRS, "DesiredSignalPowerBeforeNoise", NaN));
        r.CompositeSignalPowerBeforeNoise = double(sixgr.util.structGet(outSRS, "CompositeSignalPowerBeforeNoise", NaN));
        r.AppliedNoiseSNR_dB = double(sixgr.util.structGet(outSRS, "AppliedNoiseSNR_dB", NaN));
        r.NoiseVarianceSource = string(sixgr.util.structGet(outSRS, "NoiseVarianceSource", ""));
        r.SignalEnergyPerOccupiedRE = double(sixgr.util.structGet( ...
            outSRS,"SignalEnergyPerOccupiedRE",NaN));
        r.ReferenceAWGNGridNoiseVariance = double(sixgr.util.structGet( ...
            outSRS,"ReferenceAWGNGridNoiseVariance",NaN));
        r.ReferenceAWGNSampleNoiseVariance = double(sixgr.util.structGet( ...
            outSRS,"ReferenceAWGNSampleNoiseVariance",NaN));
        r.SampleToGridNoiseVarianceGain = double(sixgr.util.structGet( ...
            outSRS,"SampleToGridNoiseVarianceGain",NaN));
        r.SNRReferencePlane = string(sixgr.util.structGet( ...
            outSRS,"SNRReferencePlane",""));
        r.WaveformPowerUsedForAWGN = logical(sixgr.util.structGet( ...
            outSRS,"WaveformPowerUsedForAWGN",false));
        r.ChannelModelApplied = string(sixgr.util.structGet(outSRS, "ChannelModelApplied", ""));
        r.ChannelFadingApplied = logical(sixgr.util.structGet(outSRS, "ChannelFadingApplied", false));
        r.AppliedLargeScaleGain_dB = double(sixgr.util.structGet(outSRS, "AppliedLargeScaleGain_dB", NaN));
        r.AppliedLargeScaleLoss_dB = double(sixgr.util.structGet(outSRS, "AppliedLargeScaleLoss_dB", NaN));
        r.AppliedBasePathloss_dB = double(sixgr.util.structGet(outSRS, "AppliedBasePathloss_dB", NaN));
        r.AppliedPathloss_dB = double(sixgr.util.structGet(outSRS, "AppliedPathloss_dB", NaN));
        r.AppliedShadowFading_dB = double(sixgr.util.structGet(outSRS, "AppliedShadowFading_dB", NaN));
        r.AppliedO2I_dB = double(sixgr.util.structGet(outSRS, "AppliedO2I_dB", NaN));
        r.AppliedLargeScaleGainSource = string(sixgr.util.structGet(outSRS, "AppliedLargeScaleGainSource", ""));
        r.InjectedCFO_Hz = double(sixgr.util.structGet(outSRS, "InjectedCFO_Hz", NaN));
        r.InjectedTimingOffset_samples = double(sixgr.util.structGet(outSRS, "InjectedTimingOffset_samples", NaN));
        r.DetectionAttempted = logical(sixgr.util.structGet(outSRS, "DetectionAttempted", false));
        r.DetectionSuccess = logical(sixgr.util.structGet(outSRS, "DetectionSuccess", false));
        r.DetectionUsable = logical(sixgr.util.structGet(outSRS, "DetectionUsable", false));
        r.ResourceExtractionAttempted = logical(sixgr.util.structGet(outSRS, "ResourceExtractionAttempted", false));
        r.ResourceExtractionAvailable = logical(sixgr.util.structGet(outSRS, "ResourceExtractionAvailable", false));
        r.ChannelEstimateAttempted = logical(sixgr.util.structGet(outSRS, "ChannelEstimateAttempted", false));
        r.ChannelEstimateAvailable = logical(sixgr.util.structGet(outSRS, "ChannelEstimateAvailable", ...
            sixgr.util.structGet(outSRS, "SRSChannelEstimateAvailable", false)));
        r.SRSChannelEstimateAvailable = logical(sixgr.util.structGet(outSRS, "SRSChannelEstimateAvailable", r.ChannelEstimateAvailable));
        r.ChannelEstimateSource=string(sixgr.util.structGet(outSRS,"ChannelEstimateSource",""));
        for name=string(fieldnames(sixgr.link.receivedWaveformEvidence())).'
            if isfield(outSRS,name), r.(name)=outSRS.(name); end
        end
        r.StrictReceiverEvidenceOk = logical(sixgr.util.structGet(outSRS, "StrictReceiverEvidenceOk", false));
        r.SRSRuntimeEvidenceUsable = logical(sixgr.util.structGet(outSRS, "SRSRuntimeEvidenceUsable", false));
        r.StrictOk = logical(sixgr.util.structGet(outSRS, "StrictOk", false));
        r.ReceiverUsable = logical(r.StrictReceiverEvidenceOk);
        r.DecodeUsable = logical(r.StrictOk);
        r.MeasurementAttempted = logical(sixgr.util.structGet(outSRS, "MeasurementAttempted", false));
        r.MeasurementUsable = logical(sixgr.util.structGet(outSRS, "MeasurementUsable", false));
        r.FailureReason = string(sixgr.util.structGet(outSRS, "FailureReason", ""));
        r = sixgr.truth.bindReferenceSignalSINREvidence(r,outSRS,"SRS");
        r.PUSCHSchedulingSINRAnchor_dB = double(sixgr.util.structGet( ...
            outSRS, "PUSCHSchedulingSINRAnchor_dB", NaN));
        r.PUSCHSchedulingSINRAnchorSource = string(sixgr.util.structGet( ...
            outSRS, "PUSCHSchedulingSINRAnchorSource", ""));
        r.PUSCHSchedulingSINRAnchorPowerReferencePlane = string(sixgr.util.structGet( ...
            outSRS, "PUSCHSchedulingSINRAnchorPowerReferencePlane", ""));
        r.PUSCHSchedulingSINRAnchorValueStatus = string(sixgr.util.structGet( ...
            outSRS, "PUSCHSchedulingSINRAnchorValueStatus", "NOT_AVAILABLE"));
        r.WidebandCQI = double(sixgr.util.structGet(outSRS, "CQI", NaN));
        r.CQISource = string(sixgr.util.structGet(outSRS,"CQISource",""));
        r.CQIValueStatus = string(sixgr.util.structGet(outSRS,"CQIValueStatus",""));
        r.CQISelectionSINR_dB = double(sixgr.util.structGet(outSRS,"CQISelectionSINR_dB",NaN));
        r.CQIAppliedSINRMargin_dB = double(sixgr.util.structGet(outSRS,"CQIAppliedSINRMargin_dB",NaN));
        r.CQIDerivedMCS = double(sixgr.util.structGet(outSRS, "MCSIndex", NaN));
        r.CQIDerivedModulation = string(sixgr.util.structGet(outSRS, "Modulation", ""));
        r.CQIDerivedTargetCodeRate = double(sixgr.util.structGet(outSRS, "TargetCodeRate", NaN));
        r.RankEstimate = double(sixgr.util.structGet(outSRS, "RankEstimate", NaN));
        % Retain the actual estimator's spatial decision and codebook
        % provenance, separately from any later scheduler-accepted rank.
        for name=["EstimatedRI","EstimatedTPMI","TPMICandidateCount","TPMIMutualInformation"]
            r.(name)=double(sixgr.util.structGet(outSRS,name,NaN));
        end
        for name=["RISource","TPMISource"]
            r.(name)=string(sixgr.util.structGet(outSRS,name,""));
        end
        r.PredictedPUSCHPostEqSINRPerLayer_dB = localFormatNumericVector( ...
            sixgr.util.structGet(outSRS, "PredictedPUSCHPostEqSINRPerLayer_dB", []));
        r.PredictedPUSCHMinimumLayerSINR_dB = double(sixgr.util.structGet( ...
            outSRS, "PredictedPUSCHMinimumLayerSINR_dB", NaN));
        r.PredictedPUSCHWidebandMeanSINR_dB = double(sixgr.util.structGet( ...
            outSRS, "PredictedPUSCHWidebandMeanSINR_dB", NaN));
        r.PredictedPUSCHPostEqSINRSource = string(sixgr.util.structGet( ...
            outSRS, "PredictedPUSCHPostEqSINRSource", ""));
        r.PredictedPUSCHPostEqSINRValueRole = string(sixgr.util.structGet( ...
            outSRS, "PredictedPUSCHPostEqSINRValueRole", ""));
        r.PredictedPUSCHPostEqSINRValueStatus = string(sixgr.util.structGet( ...
            outSRS, "PredictedPUSCHPostEqSINRValueStatus", "NOT_AVAILABLE"));
        r.PredictedPUSCHPostEqSINRCalibrationOffset_dB = double(sixgr.util.structGet( ...
            outSRS, "PredictedPUSCHPostEqSINRCalibrationOffset_dB", NaN));
        r.PredictedPUSCHPostEqSINRAnchor_dB = double(sixgr.util.structGet( ...
            outSRS, "PredictedPUSCHPostEqSINRAnchor_dB", NaN));
        r.PredictedPUSCHPostEqSINRAnchorSource = string(sixgr.util.structGet( ...
            outSRS, "PredictedPUSCHPostEqSINRAnchorSource", ""));
        r.PredictedPUSCHPostEqSINRPowerReferencePlane = string(sixgr.util.structGet( ...
            outSRS, "PredictedPUSCHPostEqSINRPowerReferencePlane", ""));
        r.PredictedPUSCHReferenceSignalPower = double(sixgr.util.structGet( ...
            outSRS,"PredictedPUSCHReferenceSignalPower",NaN));
        r.PredictedPUSCHDisturbancePower = double(sixgr.util.structGet( ...
            outSRS,"PredictedPUSCHDisturbancePower",NaN));
        r.PUSCHToSRSReferenceEnergyRatio = double(sixgr.util.structGet( ...
            outSRS,"PUSCHToSRSReferenceEnergyRatio",NaN));
        r.PUSCHToSRSReferenceEnergySource = string(sixgr.util.structGet( ...
            outSRS,"PUSCHToSRSReferenceEnergySource",""));
        r.SRS_RSRP_dBm = double(sixgr.util.structGet(outSRS, ...
            "SRS_RSRP_dBm",NaN));
        r.SRS_RSRP_dB_re_UnitOccupiedRE_Es = double(sixgr.util.structGet( ...
            outSRS,"SRS_RSRP_dB_re_UnitOccupiedRE_Es",NaN));
        % Retain the original post-RF engineering power operands. This is
        % not the separately measured antenna-plane diversity RSRP below.
        r.SRSRSRPPerReceiveAntenna_dB_re_UnitOccupiedRE_Es = localFormatNumericVector( ...
            sixgr.util.structGet(outSRS,"SRSRSRPPerReceiveAntenna_dB_re_UnitOccupiedRE_Es",[]));
        r.SRSRSRPSource = string(sixgr.util.structGet(outSRS,"SRSRSRPSource",""));
        r.SRSRSRPStatus = string(sixgr.util.structGet(outSRS,"SRSRSRPStatus","not_available"));
        r.SRSRSRPPerReceiveAntenna_dBm = localFormatNumericVector( ...
            sixgr.util.structGet(outSRS,"SRSRSRPPerReceiveAntenna_dBm",[]));
        r.SRSAbsolutePowerStatus = string(sixgr.util.structGet( ...
            outSRS,"SRSAbsolutePowerStatus","not_available"));
        antennaPower=sixgr.phy.srs.measureSRSAntennaPower();
        for name=setdiff(string(fieldnames(antennaPower)),"SRSRSRPPerReceiveAntenna_dBm").'
            r.(name)=sixgr.util.structGet(outSRS,name,antennaPower.(name));
        end
        referenceDefaults=sixgr.link.srsReferenceEvidence();
        for name=string(fieldnames(referenceDefaults)).'
            r.(name)=sixgr.util.structGet(outSRS,name,referenceDefaults.(name));
        end
        powerReference=sixgr.truth.scoreSharedSRSAntennaPower();
        for name=string(fieldnames(powerReference)).'
            r.(name)=sixgr.util.structGet(outSRS,name,powerReference.(name));
        end
        r.SRSInterPortLeakageMatrixJSON = string(sixgr.util.structGet( ...
            outSRS,"SRSInterPortLeakageMatrixJSON",""));
        r.SRSInterPortLeakageWorst_dB = double(sixgr.util.structGet( ...
            outSRS,"SRSInterPortLeakageWorst_dB",NaN));
        r.SRSInterPortLeakageStatus = string(sixgr.util.structGet( ...
            outSRS,"SRSInterPortLeakageStatus","not_available"));
        r.SRSInterPortLeakageSource = string(sixgr.util.structGet( ...
            outSRS,"SRSInterPortLeakageSource",""));
        r.SRSOccupiedPRBCount = double(sixgr.util.structGet(outSRS, "SRSOccupiedPRBCount", NaN));
        r.SRSCarrierPRBCount = double(sixgr.util.structGet(outSRS, "SRSCarrierPRBCount", NaN));
        r.SRSBandwidthFraction = double(sixgr.util.structGet(outSRS, "SRSBandwidthFraction", NaN));
        r.SRSFrequencyPRBStart = double(sixgr.util.structGet(outSRS, "SRSFrequencyPRBStart", NaN));
        r.SRSFrequencyPRBEnd = double(sixgr.util.structGet(outSRS, "SRSFrequencyPRBEnd", NaN));
        r.SRSBandwidthCoverageStatus = string(sixgr.util.structGet(outSRS, "SRSBandwidthCoverageStatus", ""));
        r.SRSCoverageGapRB = double(sixgr.util.structGet(outSRS,'SRSCoverageGapRB',NaN));
        r.SRSCoverageToleranceRB = double(sixgr.util.structGet(outSRS,'SRSCoverageToleranceRB',NaN));
        r.SRSLiteralFullCarrierCoverage = logical(sixgr.util.structGet(outSRS,'SRSLiteralFullCarrierCoverage',false));
        r.SpatialSignatureToken = string(sixgr.util.structGet(outSRS, "SpatialSignatureToken", ""));
        r.SpatialSignatureSHA256 = string(sixgr.util.structGet(outSRS, "SpatialSignatureSHA256", ""));
        r.SpatialSignatureRows = double(sixgr.util.structGet(outSRS, "SpatialSignatureRows", NaN));
        r.SpatialSignatureColumns = double(sixgr.util.structGet(outSRS, "SpatialSignatureColumns", NaN));
        r.SpatialSignatureSource = string(sixgr.util.structGet(outSRS, "SpatialSignatureSource", ""));
        r.SpatialSignatureRawRank = double(sixgr.util.structGet(outSRS, "SpatialSignatureRawRank", NaN));
        r.SpatialSignatureRetainedRank = double(sixgr.util.structGet(outSRS, "SpatialSignatureRetainedRank", NaN));
        r.SpatialSignatureDetectionThreshold = double(sixgr.util.structGet(outSRS, "SpatialSignatureDetectionThreshold", NaN));
        r.SpatialSignatureNoiseVariance = double(sixgr.util.structGet(outSRS, "SpatialSignatureNoiseVariance", NaN));
        r.SpatialSignatureNoiseMargin_dB = double(sixgr.util.structGet(outSRS, "SpatialSignatureNoiseMargin_dB", NaN));
        r.SpatialSignatureSnapshotCount = double(sixgr.util.structGet(outSRS, "SpatialSignatureSnapshotCount", NaN));
        r.SpatialSignatureReductionMode = string(sixgr.util.structGet(outSRS, "SpatialSignatureReductionMode", ""));
        r.RankIndicator = double(sixgr.util.structGet(outSRS, "RIEstimate", outSRS.RankEstimate));
        r.PMI = double(sixgr.util.structGet(outSRS, "TPMIEstimate", NaN));
        r.ConditionNumber_dB = double(sixgr.util.structGet(outSRS, "SRSConditionNumber_dB", r.ConditionNumber_dB));
        r.RuntimeIntegrationMode = "coupled_slot_runtime";
        r.RuntimeTransportMode = "srs_tx_power_rf_runtime_channel_noise_rx_rf_srs_rx";
        r.RuntimeStageWaveformsRequired = true;
        r.RuntimeStageWaveformsUsed = true;
        r.RuntimeSelfLoopWaveformsUsed = false;
        r.RuntimeChannelStateUsed = logical(sixgr.util.structGet(outSRS, "RuntimeChannelStateUsed", false));
        r.RuntimeChannelLinkKeys = string(sixgr.util.structGet(outSRS, "RuntimeChannelLinkKeys", ""));
        r.RuntimeNoiseApplied = logical(sixgr.util.structGet(outSRS, "RuntimeNoiseApplied", false));
        r.RuntimeNoiseVarianceMean = double(sixgr.util.structGet(outSRS, "RuntimeNoiseVarianceMean", NaN));
        r.RuntimeNoiseVarianceDomain = string(sixgr.util.structGet(outSRS, "RuntimeNoiseVarianceDomain", ""));
        r.RuntimeNoiseVarianceSource = string(sixgr.util.structGet(outSRS, "RuntimeNoiseVarianceSource", ""));
        r.RuntimeStageCount = double(sixgr.util.structGet(outSRS, "RuntimeStageCount", 5));
        r.CRCPass = NaN;
        if ok
            r.Status = "PASS";
        elseif logical(sixgr.util.structGet(outSRS, "Skipped", false))
            r.Status = "NA";
        else
            r.Status = "FAIL";
            if strlength(strtrim(string(r.FailureReason))) == 0
                r.FailureReason = "srs_runtime_evidence_incomplete";
            end
        end
        r.Notes = string(sixgr.util.structGet(outSRS, "Notes", ""));
    catch ME
        r.Crash = true;
        r.CRCPass = NaN;
        r.Status = "CRASH";
        r.Notes = string(ME.message);
    end
    rows(k) = r;
end
T = struct2table(rows);
end

function [state, T] = localCollectCoupledSRSTrials(state, cfg, ueIdx, snr_dB, slotIdx)
% Bind causal SRS to the exact UL runtime channel later used by PUSCH.
% Apply the same per-UE geometry, power-reference and physical-antenna
% context used by ordinary UL grants.  The runtime channel handle alone is
% not a link budget: TS 38.213 SRS power control also requires the measured
% serving-link pathloss and YAML-owned power-control parameters.
[cfgU, state] = sixgr.truth.CoupledTruthRuntime.applyUserContext( ...
    cfg, state, ueIdx, "UL");
if sixgr.channel.ChannelFactory.requiresRuntimeChannelState(cfgU)
    [state, chState] = ...
        sixgr.truth.CoupledTruthRuntime.acquireRuntimeChannelStateForControl( ...
        state, cfgU, ueIdx, "UL");
    [T, chState, observedRET] = localCollectSRSTrials(cfgU, snr_dB, 1, chState, slotIdx);
    state.ObservedREAllocationTable = localAppendObservedREAllocation( ...
        sixgr.util.structGet(state, "ObservedREAllocationTable", table()), ...
        observedRET);
    state = sixgr.truth.CoupledTruthRuntime.commitRuntimeChannelState(state, chState);
    if ~isfield(state, "SRSChannelStateByUE") || numel(state.SRSChannelStateByUE) < ueIdx
        state.SRSChannelStateByUE{ueIdx, 1} = [];
    end
    % Retain only an identity/evidence mirror for compatibility.  The
    % authoritative mutable channel state lives in RuntimeChannelStates.
    state.SRSChannelStateByUE{ueIdx, 1} = chState;
    return;
end
if ~isfield(state, "SRSChannelStateByUE") || numel(state.SRSChannelStateByUE) < ueIdx
    state.SRSChannelStateByUE{ueIdx, 1} = [];
end
[T, chState, observedRET] = localCollectSRSTrials( ...
    cfgU, snr_dB, 1, state.SRSChannelStateByUE{ueIdx}, slotIdx);
state.ObservedREAllocationTable = localAppendObservedREAllocation( ...
    sixgr.util.structGet(state, "ObservedREAllocationTable", table()), ...
    observedRET);
state.SRSChannelStateByUE{ueIdx, 1} = chState;
end

function [T,chState,observedRET] = localCollectTRSTrials(cfg,snr_dB,nTrials,chState,receivedOut)
if nargin < 4 || ~isstruct(chState)
    chState = struct();
end
if nargin<5, receivedOut=struct(); end
observedRET = table();
if ~logical(sixgr.util.structGet(cfg, "phy.trs.enable", false))
    T = localEmptyLinkTrialTable(0);
    return;
end
nTrials = max(1, round(double(nTrials)));
rows = repmat(localMakeLinkTrialRow(cfg, "DL", snr_dB, 1), nTrials, 1);
for k = 1:nTrials
    r = localMakeLinkTrialRow(cfg, "DL", snr_dB, k);
    r.Status = "FAIL";
    try
        if isempty(fieldnames(receivedOut))
        out = sixgr.link.runTRSTracking(cfg,"SNR_dB",snr_dB, ...
            "ChannelState",chState,"RuntimeSlot", ...
            sixgr.util.structGet(cfg,"lls6g.userContext.RuntimeCurrentSlot",[]));
        else
            if nTrials~=1, error('sixgr:truth:ReceivedTRSTrialCount','One observation produces one TRS trial.'); end
            out=receivedOut;
        end
        r.ObservationStartSample = double(sixgr.util.structGet(out,"ObservationStartSample",NaN));
        resourceEvidence=sixgr.truth.executedResourceIntervals();
        for resourceField=string(fieldnames(resourceEvidence)).'
            r.(resourceField)=sixgr.util.structGet(out, ...
                "ResourceIntervalEvidence."+resourceField,resourceEvidence.(resourceField));
        end
        r.ObservationEndSampleExclusive = double(sixgr.util.structGet(out,"ObservationEndSampleExclusive",NaN));
        r.ObservationSampleRateHz = double(sixgr.util.structGet(out,"ObservationSampleRateHz",NaN));
        r.ObservationCompletionTime_s = double(sixgr.util.structGet(out,"ObservationCompletionTime_s",NaN));
        r.ObservationCoverageSource = string(sixgr.util.structGet(out,"ObservationCoverageSource",""));
        observedRET = localAppendCompatTable(observedRET, ...
            sixgr.util.structGet(out, "ObservedREAllocationTable", table()));
        chState = sixgr.util.structGet(out,"ChannelState",chState);
        ok = logical(sixgr.util.structGet(out, "Ok", false)) && ~logical(sixgr.util.structGet(out, "Skipped", false));
        r.CRCPass = NaN;
        r.NMSE_dB = double(sixgr.util.structGet(out, "NMSE_dB", NaN));
        r.NMSEScoringAvailable = logical(sixgr.util.structGet(out,'NMSEScoringAvailable',false));
        pilotEVM=sixgr.phy.trs.summarizePilotEVM();
        for field=string(fieldnames(pilotEVM)).'
            r.(field)=sixgr.util.structGet(out,field,pilotEVM.(field));
        end
        r.NMSEReferenceSource = string(sixgr.util.structGet(out,'NMSEReferenceSource',"unavailable"));
        r.TrueChannelNMSE_dB = r.NMSE_dB;
        r.ChannelNMSEComparedComplexValues = double(sixgr.util.structGet(out,'ChannelNMSEComparedComplexValues',0));
        r.ChannelNMSEPilotResourceCount = double(sixgr.util.structGet(out,'ChannelNMSEPilotResourceCount',0));
        r.ChannelNMSEQualificationMode = string(sixgr.util.structGet(out,'ChannelNMSEQualificationMode',"unavailable"));
        r.ChannelNMSEErrorEnergy = double(sixgr.util.structGet(out,'ChannelNMSEErrorEnergy',NaN));
        r.ChannelNMSEReferenceEnergy = double(sixgr.util.structGet(out,'ChannelNMSEReferenceEnergy',NaN));
        r.ChannelNMSEReferencePlane = string(sixgr.util.structGet(out,'ChannelNMSEReferencePlane',"unavailable"));
        r.ChannelNMSEReferenceIncludesRFImpairments = double(sixgr.util.structGet(out,'ChannelNMSEReferenceIncludesRFImpairments',NaN));
        pilotScore=sixgr.phy.trs.scoreTRSPilotDisturbance();
        for field=string(fieldnames(pilotScore)).'
            r.(field)=sixgr.util.structGet(out,field,pilotScore.(field));
        end
        r.QCLMeasurementStatus = string(sixgr.util.structGet(out,'QCLMeasurementStatus',"unavailable"));
        r.DetectionMetric = double(sixgr.util.structGet(out, "DetectionMetric", NaN));
        r.DetectionThreshold = double(sixgr.util.structGet(out, "DetectionThreshold", NaN));
        r.ResourceCoverageRatio = double(sixgr.util.structGet(out, "ResourceCoverageRatio", NaN));
        r.TRSDetectionPolicy = string(sixgr.util.structGet(out,"TRSDetectionPolicy",""));
        r.TRSDetectionEvidenceJSON = string(sixgr.util.structGet(out,"TRSDetectionEvidenceJSON",""));
        r.MinCoverageRatio = double(sixgr.util.structGet(out, "MinCoverageRatio", NaN));
        r.DetectionAttempted = logical(sixgr.util.structGet(out, "DetectionAttempted", false));
        r.DetectionSuccess = logical(sixgr.util.structGet(out, "DetectionSuccess", false));
        r.DetectionUsable = logical(r.DetectionAttempted) && logical(r.DetectionSuccess) && isfinite(r.DetectionMetric);
        r.ResourceExtractionAttempted = logical(sixgr.util.structGet(out, "ResourceExtractionAttempted", false));
        r.ResourceExtractionAvailable = logical(sixgr.util.structGet(out, "ResourceExtractionAvailable", false));
        r.MeasurementAttempted = logical(sixgr.util.structGet(out, "ChannelEstimationAttempted", false));
        r.MeasurementUsable = logical(sixgr.util.structGet(out,"TRSRuntimeEvidenceUsable",false));
        r.InjectedDoppler_Hz = double(sixgr.util.structGet(out, "InjectedDoppler_Hz", NaN));
        r.PhaseTrackingError_deg = double(sixgr.util.structGet(out, "PhaseError_deg", NaN));
        r.EstimatedDopplerHz = double(sixgr.util.structGet(out, "EstimatedDoppler_Hz", NaN));
        r.DopplerError_Hz = double(sixgr.util.structGet(out, "DopplerError_Hz", NaN));
        if ~isfinite(r.DopplerError_Hz) && isfinite(r.EstimatedDopplerHz) && isfinite(r.InjectedDoppler_Hz)
            r.DopplerError_Hz = r.EstimatedDopplerHz - r.InjectedDoppler_Hz;
        end
        r.QCLAccuracy = double(sixgr.util.structGet(out, "QCLAccuracy", NaN));
        r.InterpolationLoss_dB = double(sixgr.util.structGet(out, "InterpolationLoss_dB", NaN));
        r.MismatchSensitivity_dB = double(sixgr.util.structGet(out, "MismatchSensitivity_dB", NaN));
        r.TrackingEstimateSource = string(sixgr.util.structGet(out, "TrackingEstimateSource", ""));
        r.ChannelModel = char(string(sixgr.util.structGet(out, "ChannelModel", r.ChannelModel)));
        r.ChannelModelApplied = string(sixgr.util.structGet(out, "ChannelModelApplied", r.ChannelModelApplied));
        r.ChannelFadingApplied = logical(sixgr.util.structGet(out, "ChannelFadingApplied", r.ChannelFadingApplied));
        r.AppliedAWGNSNR_dB = double(sixgr.util.structGet(out, "AppliedAWGNSNR_dB", NaN));
        r.DesiredSignalPowerBeforeNoise = double(sixgr.util.structGet(out, "DesiredSignalPowerBeforeNoise", NaN));
        r.CompositeSignalPowerBeforeNoise = double(sixgr.util.structGet(out, "CompositeSignalPowerBeforeNoise", NaN));
        r.AppliedNoiseSNR_dB = double(sixgr.util.structGet(out, "AppliedNoiseSNR_dB", NaN));
        r.NoiseVarianceSource = string(sixgr.util.structGet(out, "NoiseVarianceSource", ""));
        r = sixgr.truth.bindTRSFrequencyEvidence(r,out);
        r.InjectedTimingOffset_samples = double(sixgr.util.structGet(out, "InjectedTimingOffset_samples", r.InjectedTimingOffset_samples));
        r.TrueTimingOffset_samples = double(sixgr.util.structGet(out, "TrueTimingOffset_samples", NaN));
        r.TimingScoringReferenceSource=string(sixgr.util.structGet(out,"TimingScoringReferenceSource","unavailable"));
        r.TRSTimingEvidenceJSON=string(sixgr.util.structGet(out,"TRSTimingEvidenceJSON",""));
        appliedTiming=sixgr.phy.trs.summarizeAppliedTiming();
        for field=string(fieldnames(appliedTiming)).'
            r.(field)=sixgr.util.structGet(out,field,appliedTiming.(field));
        end
        r.EstimatedTimingOffset_PreCorrection_samples = double(sixgr.util.structGet(out, "EstimatedTimingOffset_samples", NaN));
        r.EstimatedTimingOffset_samples = double(r.EstimatedTimingOffset_PreCorrection_samples);
        r.TimingEstimate_samples = double(r.EstimatedTimingOffset_PreCorrection_samples);
        r.TRSTimingEstimate_samples = double(r.EstimatedTimingOffset_PreCorrection_samples);
        r.TimingError_samples = double(sixgr.util.structGet(out, "TimingError_samples", NaN));
        r.TimingTrackingAttempted = logical(sixgr.util.structGet(out, "TimingTrackingAttempted", false));
        r.TRSTimingEstimateAvailable = logical(sixgr.util.structGet(out, "TRSTimingEstimateAvailable", false));
        r.TRSTimingEstimateUsable = logical(sixgr.util.structGet(out, "TRSTimingEstimateUsable", false));
        r.FrequencyTrackingAttempted = logical(sixgr.util.structGet(out, "FrequencyTrackingAttempted", false));
        r.TRSCFOEstimateUsable = logical(sixgr.util.structGet(out, "TRSCFOEstimateUsable", false));
        r.ChannelEstimationAttempted = logical(sixgr.util.structGet(out, "ChannelEstimationAttempted", false));
        r.TRSChannelEstimateAvailable = logical(sixgr.util.structGet(out, "TRSChannelEstimateAvailable", false));
        r.ChannelEstimateAttempted = logical(sixgr.util.structGet(out, "ChannelEstimateAttempted", r.ChannelEstimationAttempted));
        r.ChannelEstimateAvailable = logical(sixgr.util.structGet(out, "ChannelEstimateAvailable", r.TRSChannelEstimateAvailable));
        r.ChannelEstimator = string(sixgr.util.structGet(out, "ChannelEstimator", ""));
        r.ChannelEstimateSource=r.ChannelEstimator;
        for name=string(fieldnames(sixgr.link.receivedWaveformEvidence())).'
            if isfield(out,name), r.(name)=out.(name); end
        end
        r.ChannelEstimateDimensions = string(sixgr.util.structGet(out, "HestDimensions", ""));
        r.ChannelEstimateRxPorts = double(sixgr.util.structGet(out, "HestRxPorts", NaN));
        r.ChannelEstimateTxPorts = double(sixgr.util.structGet(out, "HestTxPorts", NaN));
        r.MeasuredTrialSINR_dB = double(sixgr.util.structGet(out, "MeasuredTrialSINR_dB", NaN));
        r.MeasuredTrialSINRSource = string(sixgr.util.structGet(out, "MeasuredTrialSINRSource", ""));
        r.MeasuredTrialSINRValueRole = string(sixgr.util.structGet(out, "MeasuredTrialSINRValueRole", ""));
        r.MeasuredTrialSINRValueStatus = string(sixgr.util.structGet(out, "MeasuredTrialSINRValueStatus", ""));
        r.MeasuredTrialSINRNAReason = string(sixgr.util.structGet(out, "MeasuredTrialSINRNAReason", ""));
        r = sixgr.truth.bindReferenceSignalSINREvidence(r,out,"TRS");
        r.DesiredPilotPower = double(sixgr.util.structGet(out, "DesiredPilotPower", NaN));
        r.ResidualPilotPower = double(sixgr.util.structGet(out, "ResidualPilotPower", NaN));
        r.TRSRuntimeEvidenceUsable = logical(sixgr.util.structGet(out, "TRSRuntimeEvidenceUsable", false));
        r.StrictReceiverEvidenceOk = logical(sixgr.util.structGet(out,"StrictReceiverEvidenceOk",false));
        r.ChannelNMSEThreshold_dB = double(sixgr.util.structGet(out,"ChannelNMSEThreshold_dB",NaN));
        r.TRSQualificationCriteriaJSON = string(sixgr.util.structGet(out,"TRSQualificationCriteriaJSON",""));
        r.StrictOk = logical(sixgr.util.structGet(out, "StrictOk", false));
        r.ComputeLatency_ms = double(sixgr.util.structGet(out, "ComputeLatency_ms", NaN));
        r.ProcedureDelay_ms = double(sixgr.util.structGet(out, "ProcedureDelay_ms", NaN));
        r.AirInterfaceObservation_ms = double(sixgr.util.structGet(out, "AirInterfaceObservation_ms", NaN));
        r.AcquisitionTime_ms = double(sixgr.util.structGet(out, "AcquisitionTime_ms", NaN));
        r.TrackingFailureProbability = double(sixgr.util.structGet(out, "TrackingFailure", NaN));
        r.NoiseVariance = double(sixgr.util.structGet(out, "NoiseVariance", r.NoiseVariance));
        r.NoiseVarianceDomain = string(sixgr.util.structGet(out,"NoiseVarianceDomain",""));
        r.InjectedSampleNoiseVariance = double(sixgr.util.structGet(out,"InjectedSampleNoiseVariance",NaN));
        r.InjectedSampleNoiseVarianceDomain = string(sixgr.util.structGet(out,"InjectedSampleNoiseVarianceDomain",""));
        r.InjectedSampleNoiseVarianceSource = string(sixgr.util.structGet(out,"InjectedSampleNoiseVarianceSource",""));
        r.TxRFExecutionStatus = string(sixgr.util.structGet(out, "TxRFExecutionStatus", ""));
        r.TxRFStageOrder = string(sixgr.util.structGet(out, "TxRFStageOrder", ""));
        r.TxRFAppliedStageCount = double(sixgr.util.structGet(out, "TxRFAppliedStageCount", NaN));
        r.CompositeReceiverFrontEndApplied = logical(sixgr.util.structGet(out, "CompositeReceiverFrontEndApplied", false));
        r.CompositeReceiverFrontEndStatus = string(sixgr.util.structGet(out, "CompositeReceiverFrontEndStatus", ""));
        r.PowerNormalizationPolicy = string(sixgr.util.structGet(out, "PowerNormalizationPolicy", ""));
        r.PowerNormalizationSource = string(sixgr.util.structGet(out, "PowerNormalizationSource", ""));
        r.PowerNormalizationGridSource = string(sixgr.util.structGet(out, "PowerNormalizationGridSource", ""));
        r.PowerNormalizationGridSubcarrierCount = double(sixgr.util.structGet(out, "PowerNormalizationGridSubcarrierCount", NaN));
        r.PowerNormalizationGridActiveSymbolCount = double(sixgr.util.structGet(out, "PowerNormalizationGridActiveSymbolCount", NaN));
        r.PowerNormalizationGridMeanEnergyPerRE = double(sixgr.util.structGet(out, "PowerNormalizationGridMeanEnergyPerRE", NaN));
        r.FullBWPActivityFactor = double(sixgr.util.structGet(out, "FullBWPActivityFactor", NaN));
        r.ReferenceInputPower_dBm = double(sixgr.util.structGet(out, "ReferenceInputPower_dBm", NaN));
        r.ReferenceOutputPower_dBm = double(sixgr.util.structGet(out, "PowerReferenceOutput_dBm", NaN));
        r.ActualEmittedPower_dBm = double(sixgr.util.structGet(out, "ActualEmittedPower_dBm", NaN));
        r.ActualEmittedPowerBackoffFromBudget_dB = double(sixgr.util.structGet(out, "ActualEmittedPowerBackoffFromBudget_dB", NaN));
        r.PowerClosureError_dB = double(sixgr.util.structGet(out, "PowerClosureError_dB", NaN));
        r.PowerConversionEquation = string(sixgr.util.structGet(out, "PowerConversionEquation", ""));
        powerSchema = sixgr.report.bindTransmitPowerEvidence(struct(), struct());
        powerFields = fieldnames(powerSchema);
        for powerFieldIdx = 1:numel(powerFields)
            powerField = powerFields{powerFieldIdx};
            r.(powerField) = sixgr.util.structGet(out, powerField, powerSchema.(powerField));
        end
        r.RuntimeIntegrationMode = "coupled_slot_runtime";
        r.RuntimeTransportMode = "trs_tx_power_rf_runtime_channel_noise_rx_rf_trs_rx";
        r.RuntimeStageWaveformsRequired = true;
        r.RuntimeStageWaveformsUsed = isfinite(double(sixgr.util.structGet( ...
            out, "RuntimeStageCount", NaN)));
        r.RuntimeSelfLoopWaveformsUsed = false;
        r.RuntimeChannelStateUsed = logical(sixgr.util.structGet(out, "RuntimeChannelStateUsed", false));
        r.RuntimeChannelLinkKeys = string(sixgr.util.structGet(out, "RuntimeChannelLinkKeys", ""));
        r.RuntimeNoiseApplied = logical(sixgr.util.structGet(out, "RuntimeNoiseApplied", false));
        r.RuntimeNoiseVarianceMean = double(sixgr.util.structGet(out, "RuntimeNoiseVarianceMean", NaN));
        r.RuntimeStageCount = double(sixgr.util.structGet(out, "RuntimeStageCount", NaN));
        if ~ok && strlength(strtrim(string(sixgr.util.structGet(out, "FailureReason", "")))) > 0
            r.FailureReason = string(sixgr.util.structGet(out, "FailureReason", ""));
        end
        if ok
            r.Status = "PASS";
        end
        r.Crash = logical(sixgr.util.structGet(out, "Crash", false));
        if r.Crash
            r.Status = "CRASH";
        end
        r.Notes = string(sixgr.util.structGet(out, "Notes", ""));
    catch ME
        r.Crash = true;
        r.CRCPass = NaN;
        r.Status = "CRASH";
        r.FailureReason = string(ME.identifier) + ": " + string(ME.message);
        r.Notes = string(ME.message);
    end
    rows(k) = r;
end
T = struct2table(rows, "AsArray", true);
end

function varargout = localMakeLinkTrialRow(varargin)
% Compatibility delegate; the implementation and schema have one owner.
[varargout{1:nargout}] = sixgr.truth.makeLinkTrialRow(varargin{:});
end

function varargout = localEmptyLinkTrialTable(varargin)
% Compatibility delegate; completion/publication has one production owner.
[varargout{1:nargout}] = sixgr.truth.SharedDataCompletionRuntime.emptyLinkTrialTable(varargin{:});
end

function T = localEmptyCSIRSTrialTable()
T = sixgr.truth.emptyCSIRSTrialTable();
end

function row = localEmptyCSIRSTrialRow()
row = struct( ...
    "Direction", "", "SignalFamily", "CSI-RS", "SNR_dB", NaN, "SFN", NaN, "Frame", NaN, "Slot", NaN, "Time_s", NaN, ...
    "CellID", NaN, "BWPID", NaN, "UEIndex", NaN, "RNTI", NaN, ...
    "ResourceID", NaN, "ResourceSetID", NaN, "CSIRSType", "", "NumPorts", NaN, "RowNumber", NaN, ...
    "Density", "", "Periodicity", "", "SymbolLocations", "", "SubcarrierLocations", "", "RBOffset", NaN, "NumRB", NaN, "NRE", NaN, ...
    "Scheduled", false, "Transmitted", false, "Observed", false, "Consumed", false, "Consumer", "", ...
    "ResourceExtractionAttempted", false, "ResourceExtractionAvailable", false, ...
    "ChannelEstimationAttempted", false, "ChannelEstimateAvailable", false, ...
    "ChannelEstimateSource", "", "ChannelEstimator", "", "ChannelInterpolationMethod", "", ...
    "ChannelEstimateConvention", "", "ChannelEstimateNoiseVariance", NaN, ...
    "ChannelEstimationLatency_ms", NaN, "ReceiverPipelineLatency_ms", NaN, ...
    "ReceiverStageLatencySource", "", ...
    "PilotRECount", NaN, "PilotResidualPower", NaN, "PilotResidualNMSE_dB", NaN, ...
    "HestDimensions", "", "HestRxPorts", NaN, "HestTxPorts", NaN, ...
    "CQI", NaN, "RI", NaN, "PMI", NaN, "LI", NaN, "CRI", NaN, "CQISource", "", ...
    "PMI_I11",NaN,"PMI_I12",NaN,"PMI_I13",NaN,"PMI_I2",NaN, ...
    "CSIReportMode", "", "CSIPayloadBitLength", NaN, "CSIPayloadHex", "", ...
    "CSIComputationStatus", "not_attempted", "CSIComputationErrorIdentifier", "", ...
    "CSIMeasurementID", "", "CSIMeasurementDigest", "", ...
    "CSIMeasurementProvenance", "", ...
    "CSIMeasurementStateAvailable", false, ...
    "CSIMeasurementStatus", "not_attempted", ...
    "CSIMeasurementSlot", NaN, ...
    "CSIMeasurementNoiseVariance", NaN, ...
    "NumConfiguredResources", NaN, "NumMeasuredResources", NaN, ...
    "ResourceObjectiveValues", "", "CRISelectionSource", "", ...
    "ConfiguredResourceIDs", "", "CSIRSPhysicalPortCount", NaN, ...
    "CSIRSPrecoderSource", "", "CSIRSPrecoderDigests", "", ...
    "PMIType", "", "PMICodebookMode", "", "SINR_dB", NaN, "SINRSource", "", ...
    "CQIEffectiveSINR_dB", NaN, "CQIEffectiveSINRSource", "", ...
    "SINRValueRole", "", "SINRValueStatus", "", "SINRMeasurementDomain", "", ...
    "PowerReferencePlane", "", "CSIMeasurementAvailable", false, ...
    "ReportSourceSlot", NaN, "ReportMeasurementSourceSlot", NaN, ...
    "ReportMeasurementSourceAuthority", "", "ReportDueSlot", NaN, "ReportDeliveredSlot", NaN, ...
    "ReportProcessed", false, "ReportStatus", "not_enqueued", "ReportIdentity", "", ...
    "ReportCQIExactMatch", false, "ReportRIExactMatch", false, ...
    "ReportPMIExactMatch", false, "ReportCRIExactMatch", false, ...
    "ReportCSIExactMatch", false, "ReportBindingStatus", "missing_causal_report", ...
    "MeasurementRSRP_dB", NaN, "MeasurementSource", "", "UpdateOutcome", "", ...
    "RuntimeMaterializationStatus", "", "TxRuntimeMaterializationStatus", "", ...
    "RxRuntimeObservationStatus", "", "RuntimeBlocker", "", "RuntimeEvidenceSource", "", ...
    "RuntimeEventObserved", false, "SourceArtifact", "air_interface/csv/csi_rs_trials.csv", "SourceTable", "air_interface/csv/csi_rs_trials.csv");
end

function spec = localResolveMultiUserSpec(cfg)
spec = sixgr.truth.resolveMultiUserSpec(cfg);
end

function spec = localSingleUserSpec(specIn)
spec = specIn;
spec.Enabled = false;
spec.NumUsers = 1;
end

function cfgU = localPrepareUserCfg(cfg, multiUser, userIdx)
cfgU = cfg;
if ~logical(sixgr.util.structGet(multiUser, "Enabled", false)) && ...
        max(1, round(double(sixgr.util.structGet(multiUser, "NumUsers", 1)))) == 1 && ...
        double(userIdx) == 1
    cfgU = sixgr.util.structSet(cfgU, "lls6g.userContext", struct( ...
        "UEIndex", 1, ...
        "RNTI", double(localUserRNTI(multiUser, 1)), ...
        "ConfiguredTxAntennas", double(sixgr.util.structGet(cfg, "phy.nTxAnt", 1)), ...
        "ConfiguredRxAntennas", double(sixgr.util.structGet(cfg, "phy.nRxAnt", 1)), ...
        "ConfiguredLayers", double(localConfiguredLayerCount(cfg, "DL")), ...
        "BeamSelectionStrategy", string(multiUser.BeamSelectionStrategy), ...
        "BeamIndexSet", "", ...
        "BeamformingApplied", false, ...
        "PrecoderSource", "none"));
    if string(sixgr.util.structGet(multiUser, "ExecutionModel", "")) ~= "slot_coupled_truth"
        cfgU = sixgr.truth.attachFixedLinkRuntimeAntennaContext(cfgU, 1, 1);
    end
    return;
end

seedBase = double(sixgr.util.structGet(cfg, "run.seed", 1));
cfgU.run.seed = seedBase + (double(userIdx) - 1) * double(multiUser.SeedStride);
cfgU.scenario.nUE = 1;
cfgU.scenario.ue.nUE = 1;

rnti = localUserRNTI(multiUser, userIdx);
cfgU = sixgr.util.structSet(cfgU, "phy.pdsch.RNTI", rnti);
cfgU = sixgr.util.structSet(cfgU, "phy.pusch.RNTI", rnti);

[W, beamMeta] = localSelectUserBeamforming(cfgU, multiUser, userIdx);
cfgU = sixgr.util.structSet(cfgU, "lls6g.userContext", beamMeta);
if ~isempty(W)
    nLayers = max(1, round(double(localConfiguredLayerCount(cfgU, "DL"))));
    hybridEnabled = logical(sixgr.util.structGet(cfgU, ...
        "phy.beamManagement.hybridBeamformingEnabled", false));
    if hybridEnabled
        if size(W, 2) ~= nLayers
            error("sixgr:truth:HybridUserBeamLayerMismatch", ...
                "Selected user beam is %dx%d but configured DL rank is %d.", ...
                size(W, 1), size(W, 2), nLayers);
        end
        cfgU = sixgr.util.structSet(cfgU, ...
            "phy.pdsch.hybridElementToPortMatrix", W);
        [configuredTxRFChains, rfChainAuthorityPath] = ...
            sixgr.phy.mimo.resolveDirectionalRFChainAuthority( ...
            cfgU, "DL", "RequiredLogicalPorts", nLayers);
        cfgU = sixgr.util.structSet(cfgU, ...
            "phy.pdsch.numRFChains", configuredTxRFChains);
        cfgU = sixgr.util.structSet(cfgU, ...
            "phy.pdsch.rfChainAuthorityPath", char(rfChainAuthorityPath));
        cfgU = sixgr.util.structSet(cfgU, "phy.pdsch.precoding.matrix", eye(nLayers));
        cfgU = sixgr.util.structSet(cfgU, "phy.pdsch.selectedPrecoderSHA256", ...
            char(sixgr.phy.mimo.MatrixContract.digest(W)));
        cfgU = sixgr.util.structSet(cfgU, "phy.pdsch.NumAntennaPorts", nLayers);
        cfgU = sixgr.util.structSet(cfgU, "phy.pdsch.numAntennaPorts", nLayers);
        cfgU = sixgr.util.structSet(cfgU, "phy.pdsch.numPorts", nLayers);
        cfgU = sixgr.util.structSet(cfgU, "phy.pdsch.nPorts", nLayers);
        beamMeta.NumLogicalPorts = double(nLayers);
        beamMeta.NumWaveformColumns = double(size(W, 1));
        beamMeta.HybridElementDomainApplied = true;
        beamMeta.SelectedMatrixSHA256 = char(sixgr.phy.mimo.MatrixContract.digest(W));
        cfgU = sixgr.util.structSet(cfgU, "lls6g.userContext", beamMeta);
    else
        cfgU = sixgr.util.structSet(cfgU, "phy.pdsch.precoding.matrix", W);
        cfgU = sixgr.util.structSet(cfgU, "phy.pdsch.numPorts", size(W, 1));
        cfgU = sixgr.util.structSet(cfgU, "phy.pdsch.nPorts", size(W, 1));
    end
    cfgU.phy.nTxAnt = size(W, 1);
end
if string(sixgr.util.structGet(multiUser, "ExecutionModel", "")) ~= "slot_coupled_truth"
    cfgU = sixgr.truth.attachFixedLinkRuntimeAntennaContext( ...
        cfgU, double(userIdx), max(1, round(double(multiUser.NumUsers))));
end
end

function rnti = localUserRNTI(multiUser, userIdx)
rnti = max(1, round(double(multiUser.RNTIStart + double(userIdx) - 1)));
end

function [W, meta] = localSelectUserBeamforming(cfg, multiUser, userIdx)
W = [];
meta = struct( ...
    "UEIndex", double(userIdx), ...
    "RNTI", double(localUserRNTI(multiUser, userIdx)), ...
    "ConfiguredTxAntennas", double(sixgr.util.structGet(cfg, "phy.nTxAnt", 1)), ...
    "ConfiguredRxAntennas", double(sixgr.util.structGet(cfg, "phy.nRxAnt", 1)), ...
    "ConfiguredLayers", double(localConfiguredLayerCount(cfg, "DL")), ...
    "BeamSelectionStrategy", string(multiUser.BeamSelectionStrategy), ...
    "BeamIndexSet", "", ...
    "BeamformingApplied", false, ...
    "PrecoderSource", "none");

nTx = max(1, round(double(sixgr.util.structGet(cfg, "phy.nTxAnt", 1))));
nLayers = max(1, round(double(sixgr.util.structGet(cfg, "phy.pdsch.nLayers", 1))));
beamSweepEnabled = logical(sixgr.util.structGet(cfg, "phy.beamManagement.enabled", false));
precoderType = lower(string(sixgr.util.structGet(cfg, "lls6g.mimo.precoder_type", sixgr.util.structGet(cfg, "mimo.precoder_type", "wideband"))));
if nTx <= 1 || (nLayers <= 1 && ~beamSweepEnabled && ~logical(multiUser.Enabled))
    return;
end
if precoderType == "none"
    return;
end

beamCount = max(nLayers, round(double(sixgr.util.structGet(cfg, "phy.beamManagement.beamCount", nTx))));
arr = localInferArrayGeometry(cfg, nTx);
codebook = sixgr.rf.BeamRefinementCSIRS.makeCodebookFromArray(arr, arr.nRow, min(arr.nCol, beamCount));
if isempty(codebook)
    return;
end
numBeams = size(codebook, 2);
if numBeams < nLayers
    return;
end

switch string(multiUser.BeamSelectionStrategy)
    case "round_robin_codebook"
        startIdx = 1 + mod((double(userIdx) - 1) * max(nLayers, 1), numBeams);
        beamIdx = zeros(1, nLayers);
        for k = 1:nLayers
            beamIdx(k) = 1 + mod(startIdx + k - 2, numBeams);
        end
    otherwise
        beamIdx = 1:nLayers;
end
beamIdx = unique(max(1, min(numBeams, round(beamIdx))), "stable");
if numel(beamIdx) < nLayers
    unused = setdiff(1:numBeams, beamIdx, "stable");
    need = nLayers - numel(beamIdx);
    beamIdx = [beamIdx unused(1:min(need, numel(unused)))]; %#ok<AGROW>
end
beamIdx = beamIdx(1:nLayers);
W = codebook(:, beamIdx);
selectedPower = real(trace(W * W'));
if ~(isfinite(selectedPower) && selectedPower > 0)
    error("sixgr:truth:InvalidSelectedUserBeamPower", ...
        "Selected user beam has invalid Frobenius power.");
end
W = W ./ sqrt(selectedPower);

meta.BeamformingApplied = true;
meta.PrecoderSource = "codebook_dft";
meta.BeamIndexSet = join(string(beamIdx), "|");
end

function arr = localInferArrayGeometry(cfg, nTx)
panelCount = max(1, round(double(sixgr.util.structGet(cfg, "phy.beamManagement.panelCount", 1))));
nRow = max(1, floor(sqrt(double(nTx))));
nCol = max(1, ceil(double(nTx) / max(nRow, 1)));
if nRow * nCol ~= nTx
    if panelCount > 1 && mod(nTx, panelCount) == 0
        nRow = panelCount;
        nCol = nTx / panelCount;
    else
        nRow = 1;
        nCol = nTx;
    end
end
arr = struct("Nant", double(nTx), "nRow", double(nRow), "nCol", double(nCol));
end

function [T, summaryT, constT, csirsT, signalDiagnostic, waveT, observedRET] = localCollectMultiUserLinkTrials(cfg, multiUser, direction, nTrials, snr_dB, livePublisher)
if nargin < 6
    livePublisher = [];
end
signalDiagnostic = localUnavailablePHYSignalDiagnostic(direction);
waveT = table();
observedRET=table();
rows = cell(max(1, round(double(multiUser.NumUsers))), 1);
constRows = cell(max(1, round(double(multiUser.NumUsers))), 1);
csirsRows = cell(max(1, round(double(multiUser.NumUsers))), 1);
summaryRows = repmat(struct("UEIndex", NaN, "RNTI", NaN, "Direction", "", ...
    "ConfiguredLayers", NaN, "ConfiguredTxAntennas", NaN, "ConfiguredRxAntennas", NaN, ...
    "BeamformingApplied", false, "BeamSelectionStrategy", "", "BeamIndexSet", "", ...
    "ExecutionModel", "", "Throughput_Mbps", NaN, "ObservedRowCount", NaN, ...
    "BLER", NaN, "BER", NaN, "PassRate", NaN, "MeanMeasuredSINR_dB", NaN, ...
    "MeanChannelGain_dB", NaN, "SummaryRowValid", false, "RuntimeDataPresent", false, ...
    "UserHadAnySuccessfulTx", false, "UserHadAnySuccessfulRx", false, "PartialSuccess", false, ...
    "AllObservedRowsSuccessful", false, "SummaryStatus", "", "Ok", false, ...
    "OkDefinition", "compatibility_alias_of_summary_row_valid"), ...
    max(1, round(double(multiUser.NumUsers))), 1);

for ueIdx = 1:max(1, round(double(multiUser.NumUsers)))
    cfgU = localPrepareUserCfg(cfg, multiUser, ueIdx);
    userMeta = sixgr.util.structGet(cfgU, "lls6g.userContext", struct());
    userLiveCallback = [];
    if ~isempty(livePublisher)
        userLiveCallback = @(partialTrials, partialConst, meta) localEmitMultiUserLiveSnapshot( ...
            rows, constRows, partialTrials, partialConst, meta, ...
            cfgU, multiUser, ueIdx, userMeta, snr_dB, direction, livePublisher);
    end
    if upper(string(direction)) == "DL"
        res = sixgr.link.runDLPDSCHThroughput(cfgU, ...
            "NumFrames", nTrials, ...
            "SNR_dB", snr_dB, ...
            "LiveTrialCallback", userLiveCallback, ...
            "LiveCallbackInterval", localResolveLiveFramePublishInterval(cfgU, nTrials));
    else
        res = sixgr.link.runULPUSCHThroughput(cfgU, ...
            "NumFrames", nTrials, ...
            "SNR_dB", snr_dB, ...
            "LiveTrialCallback", userLiveCallback, ...
            "LiveCallbackInterval", localResolveLiveFramePublishInterval(cfgU, nTrials));
    end
    Tu = localEnsureLinkTrialTable(sixgr.util.structGet(res, "TrialTable", table()), upper(string(direction)), snr_dB, cfgU);
    observedRET=localAppendCompatTable(observedRET,sixgr.truth.bindIndependentREObservation( ...
        sixgr.util.structGet(res,'ObservedREAllocationTable',table())));
    signalDiagnostic = localSelectPHYSignalDiagnostic(signalDiagnostic, ...
        sixgr.util.structGet(res, "SignalDiagnostic", struct()));
    Tu = localAnnotateUserTrials(Tu, cfgU, multiUser, ueIdx, userMeta);
    waveT = localAppendCompatTable(waveT, localAnnotateWaveformPreviewTable( ...
        sixgr.util.structGet(res, "WaveformPreviewTable", table()), cfgU, ueIdx, direction));
    rows{ueIdx} = Tu;
    constRows{ueIdx} = localAnnotateConstellationSamples( ...
        sixgr.util.structGet(res, "ConstellationSamples", table()), cfgU, multiUser, ueIdx, userMeta, snr_dB, direction);
    if upper(string(direction)) == "DL"
        csirsRows{ueIdx} = sixgr.util.structGet(res, "CSIRSTrialTable", table());
    end

    sem = sixgr.truth.deriveUserSummarySemantics(Tu);
    summaryRows(ueIdx) = struct( ...
        "UEIndex", double(ueIdx), ...
        "RNTI", double(localUserRNTI(multiUser, ueIdx)), ...
        "Direction", string(direction), ...
        "ConfiguredLayers", double(localConfiguredLayerCount(cfgU, direction)), ...
        "ConfiguredTxAntennas", double(sixgr.util.structGet(cfgU, "phy.nTxAnt", 1)), ...
        "ConfiguredRxAntennas", double(sixgr.util.structGet(cfgU, "phy.nRxAnt", 1)), ...
        "BeamformingApplied", localLastLogicalValue(Tu, "BeamformingApplied"), ...
        "BeamSelectionStrategy", string(sixgr.util.structGet(userMeta, "BeamSelectionStrategy", multiUser.BeamSelectionStrategy)), ...
        "BeamIndexSet", string(sixgr.util.structGet(userMeta, "BeamIndexSet", "")), ...
        "ExecutionModel", string(multiUser.ExecutionModel), ...
        "Throughput_Mbps", double(sixgr.util.structGet(res, "Throughput_Mbps", NaN)), ...
        "ObservedRowCount", double(sem.ObservedRowCount), ...
        "BLER", double(sixgr.util.structGet(res, "BLER", NaN)), ...
        "BER", double(sixgr.util.structGet(res, "BER", NaN)), ...
        "PassRate", double(sem.PassRate), ...
        "MeanMeasuredSINR_dB", double(localTableMean(Tu, "MeasuredSINR_dB")), ...
        "MeanChannelGain_dB", double(localTableMean(Tu, "ChannelGain_dB")), ...
        "SummaryRowValid", logical(sem.SummaryRowValid), ...
        "RuntimeDataPresent", logical(sem.RuntimeDataPresent), ...
        "UserHadAnySuccessfulTx", logical(sem.UserHadAnySuccessfulTx), ...
        "UserHadAnySuccessfulRx", logical(sem.UserHadAnySuccessfulRx), ...
        "PartialSuccess", logical(sem.PartialSuccess), ...
        "AllObservedRowsSuccessful", logical(sem.AllObservedRowsSuccessful), ...
        "SummaryStatus", string(sem.SummaryStatus), ...
        "Ok", logical(sem.Ok), ...
        "OkDefinition", string(sem.OkDefinition));
    if ~isempty(livePublisher)
        partialRows = rows(~cellfun(@isempty, rows));
        if isempty(partialRows)
            partialT = localEmptyLinkTrialTable(0);
        else
            partialT = vertcat(partialRows{:});
        end
        partialConstRows = constRows(cellfun(@(x) istable(x) && ~isempty(x), constRows));
        if isempty(partialConstRows)
            partialConstT = table();
        else
            partialConstT = vertcat(partialConstRows{:});
        end
        try
            feval(livePublisher, partialT, partialConstT, struct( ...
                "Direction", string(direction), ...
                "SNR_dB", double(snr_dB), ...
                "CompletedUsers", double(ueIdx), ...
                "TotalUsers", double(max(1, round(double(multiUser.NumUsers))))));
        catch
        end
    end
end

rows = rows(~cellfun(@isempty, rows));
if isempty(rows)
    T = table();
else
    T = vertcat(rows{:});
end
constRows = constRows(cellfun(@(x) istable(x) && ~isempty(x), constRows));
if isempty(constRows)
    constT = table();
else
    constT = vertcat(constRows{:});
end
csirsRows = csirsRows(cellfun(@(x) istable(x) && ~isempty(x), csirsRows));
if isempty(csirsRows)
    csirsT = table();
else
    csirsT = vertcat(csirsRows{:});
end
summaryT = struct2table(summaryRows);
end

function [Tu, summaryT, constT, csirsT, signalDiagnostic, waveT, observedRET] = localRunSingleUserDirectionTrials(cfg, multiUser, ueIdx, direction, nTrials, snr_dB, livePublisher)
if nargin < 7
    livePublisher = [];
end
cfgU = localPrepareUserCfg(cfg, multiUser, ueIdx);
userMeta = sixgr.util.structGet(cfgU, "lls6g.userContext", struct());
userLiveCallback = [];
if ~isempty(livePublisher)
    userLiveCallback = @(partialTrials, partialConst, meta) localEmitSingleUserLiveSnapshot( ...
        partialTrials, partialConst, meta, cfgU, multiUser, ueIdx, userMeta, snr_dB, direction, livePublisher);
end
if upper(string(direction)) == "DL"
    res = sixgr.link.runDLPDSCHThroughput(cfgU, ...
        "NumFrames", nTrials, ...
        "SNR_dB", snr_dB, ...
        "LiveTrialCallback", userLiveCallback, ...
        "LiveCallbackInterval", localResolveLiveFramePublishInterval(cfgU, nTrials));
else
    res = sixgr.link.runULPUSCHThroughput(cfgU, ...
        "NumFrames", nTrials, ...
        "SNR_dB", snr_dB, ...
        "LiveTrialCallback", userLiveCallback, ...
        "LiveCallbackInterval", localResolveLiveFramePublishInterval(cfgU, nTrials));
end
Tu = localEnsureLinkTrialTable(sixgr.util.structGet(res, "TrialTable", table()), upper(string(direction)), snr_dB, cfgU);
observedRET=sixgr.truth.bindIndependentREObservation( ...
    sixgr.util.structGet(res,'ObservedREAllocationTable',table()));
signalDiagnostic = localSelectPHYSignalDiagnostic(localUnavailablePHYSignalDiagnostic(direction), ...
    sixgr.util.structGet(res, "SignalDiagnostic", struct()));
Tu = localAnnotateUserTrials(Tu, cfgU, multiUser, ueIdx, userMeta);
waveT = localAnnotateWaveformPreviewTable( ...
    sixgr.util.structGet(res, "WaveformPreviewTable", table()), cfgU, ueIdx, direction);
constT = localAnnotateConstellationSamples( ...
    sixgr.util.structGet(res, "ConstellationSamples", table()), cfgU, multiUser, ueIdx, userMeta, snr_dB, direction);
csirsT = table();
if upper(string(direction)) == "DL"
    csirsT = sixgr.util.structGet(res, "CSIRSTrialTable", table());
end
sem = sixgr.truth.deriveUserSummarySemantics(Tu);
summaryT = struct2table(struct( ...
    "UEIndex", double(ueIdx), ...
    "RNTI", double(localUserRNTI(multiUser, ueIdx)), ...
    "Direction", string(direction), ...
    "ConfiguredLayers", double(localConfiguredLayerCount(cfgU, direction)), ...
    "ConfiguredTxAntennas", double(sixgr.util.structGet(cfgU, "phy.nTxAnt", 1)), ...
    "ConfiguredRxAntennas", double(sixgr.util.structGet(cfgU, "phy.nRxAnt", 1)), ...
    "BeamformingApplied", localLastLogicalValue(Tu, "BeamformingApplied"), ...
        "BeamSelectionStrategy", string(sixgr.util.structGet(userMeta, "BeamSelectionStrategy", multiUser.BeamSelectionStrategy)), ...
        "BeamIndexSet", string(sixgr.util.structGet(userMeta, "BeamIndexSet", "")), ...
        "ExecutionModel", string(multiUser.ExecutionModel), ...
        "Throughput_Mbps", double(sixgr.util.structGet(res, "Throughput_Mbps", NaN)), ...
        "ObservedRowCount", double(sem.ObservedRowCount), ...
        "BLER", double(sixgr.util.structGet(res, "BLER", NaN)), ...
        "BER", double(sixgr.util.structGet(res, "BER", NaN)), ...
        "PassRate", double(sem.PassRate), ...
        "MeanMeasuredSINR_dB", double(localTableMean(Tu, "MeasuredSINR_dB")), ...
        "MeanChannelGain_dB", double(localTableMean(Tu, "ChannelGain_dB")), ...
        "SummaryRowValid", logical(sem.SummaryRowValid), ...
        "RuntimeDataPresent", logical(sem.RuntimeDataPresent), ...
        "UserHadAnySuccessfulTx", logical(sem.UserHadAnySuccessfulTx), ...
        "UserHadAnySuccessfulRx", logical(sem.UserHadAnySuccessfulRx), ...
        "PartialSuccess", logical(sem.PartialSuccess), ...
        "AllObservedRowsSuccessful", logical(sem.AllObservedRowsSuccessful), ...
        "SummaryStatus", string(sem.SummaryStatus), ...
        "Ok", logical(sem.Ok), ...
        "OkDefinition", string(sem.OkDefinition)));
end

function localEmitSingleUserLiveSnapshot(partialTrials, partialConst, meta, cfg, multiUser, ueIdx, userMeta, snr_dB, direction, livePublisher)
if isempty(livePublisher)
    return;
end
partialT = localAnnotateUserTrials(localEnsureLinkTrialTable(partialTrials, upper(string(direction)), snr_dB, cfg), cfg, multiUser, ueIdx, userMeta);
partialConstT = localAnnotateConstellationSamples(partialConst, cfg, multiUser, ueIdx, userMeta, snr_dB, direction);
meta = localMergeLiveMeta(meta, struct( ...
    "Direction", string(direction), ...
    "SNR_dB", double(snr_dB), ...
    "CurrentUEIndex", double(ueIdx), ...
    "TotalUsers", double(max(1, round(double(multiUser.NumUsers))))));
if isfield(meta, "WaveformPreviewTable")
    meta.WaveformPreviewTable = localAnnotateWaveformPreviewTable(meta.WaveformPreviewTable, cfg, ueIdx, direction);
end
try
    feval(livePublisher, partialT, partialConstT, meta);
catch
end
end

function rawTrials = localBuildLiveRawTrialsAggregate(dlTrials, ulTrials, dlParts, ulParts, csirsTrials)
if nargin < 5
    csirsTrials = table();
end
rawTrials = struct( ...
    "DL", dlTrials, ...
    "UL", ulTrials, ...
    "SRS", table(), ...
    "CSIRS", csirsTrials, ...
    "TRS", table(), ...
    "PDCCH", table(), ...
    "PBCH", table(), ...
    "PRACH", table(), ...
    "PUCCH", table(), ...
    "MultiUserDL", localConcatTableParts(dlParts), ...
    "MultiUserUL", localConcatTableParts(ulParts));
end

function meta = localBuildLivePublishMeta(direction, snr_dB, sweepPointIndex, sweepPointCount, currentUEIndex, totalUsers, rawTrialsAggregate, multiUser, mobilityArtifacts, notes)
if nargin < 10
    notes = "";
end
meta = struct( ...
    "Direction", string(direction), ...
    "SNR_dB", double(snr_dB), ...
    "SweepPointIndex", double(sweepPointIndex), ...
    "SweepPointCount", double(sweepPointCount), ...
    "CurrentUEIndex", double(currentUEIndex), ...
    "TotalUsers", double(totalUsers), ...
    "RawTrialsAggregate", rawTrialsAggregate, ...
    "MultiUserSpec", multiUser, ...
    "MobilityArtifacts", mobilityArtifacts, ...
    "Notes", string(notes));
end

function status = localBuildLiveStageStatus(rawTrials, liveArtifacts, meta)
dlT = sixgr.util.structGet(rawTrials, "DL", table());
ulT = sixgr.util.structGet(rawTrials, "UL", table());
dlSummaryT = sixgr.util.structGet(rawTrials, "MultiUserDL", table());
ulSummaryT = sixgr.util.structGet(rawTrials, "MultiUserUL", table());
runtimeState = sixgr.util.structGet(meta, "RuntimeState", struct());
direction = upper(string(sixgr.util.structGet(meta, "Direction", "")));
currentSNR = double(sixgr.util.structGet(meta, "SNR_dB", NaN));
completedFrames = double(sixgr.util.structGet(meta, "CompletedFrames", NaN));
totalFrames = double(sixgr.util.structGet(meta, "TotalFrames", NaN));
totalSlots = NaN;
currentUE = double(sixgr.util.structGet(meta, "CurrentUEIndex", NaN));
totalUsers = double(sixgr.util.structGet(meta, "TotalUsers", NaN));
dlCompletedFrames = NaN;
ulCompletedFrames = NaN;
dlUsers = localUniqueUserCount(dlT);
ulUsers = localUniqueUserCount(ulT);
dlSummaryUsers = localUniqueUserCount(dlSummaryT);
ulSummaryUsers = localUniqueUserCount(ulSummaryT);
beamT = sixgr.util.structGet(sixgr.util.structGet(liveArtifacts, "LiveDerived", struct()), "BeamSelectionStats", table());
energySummary = sixgr.util.structGet(sixgr.util.structGet(liveArtifacts, "Energy", struct()), "SummaryTable", table());
iqSummary = sixgr.util.structGet(sixgr.util.structGet(liveArtifacts, "IQImpairment", struct()), "SummaryTable", table());
harqInfo = sixgr.util.structGet(liveArtifacts, "HARQ", struct());
if isstruct(runtimeState) && ~isempty(fieldnames(runtimeState))
    currentSNR = double(sixgr.util.structGet(runtimeState, "CurrentSNR_dB", currentSNR));
    dlCompletedFrames = double(sixgr.util.structGet(runtimeState, "DLCompletedFrames", NaN));
    ulCompletedFrames = double(sixgr.util.structGet(runtimeState, "ULCompletedFrames", NaN));
    totalFrames = double(sixgr.util.structGet(runtimeState, "FramesPerSweepPoint", totalFrames));
    totalSlots = double(sixgr.util.structGet(runtimeState, "CanonicalSlotsPerSweepPoint", totalSlots));
    currentUE = double(sixgr.util.structGet(runtimeState, "CurrentUEIndex", currentUE));
    totalUsers = double(sixgr.util.structGet(runtimeState, "NumUsers", totalUsers));
    dlSummaryUsers = max(dlSummaryUsers, round(double(sixgr.util.structGet(runtimeState, "LastDLGrantedUsers", dlSummaryUsers))));
    ulSummaryUsers = max(ulSummaryUsers, round(double(sixgr.util.structGet(runtimeState, "LastULGrantedUsers", ulSummaryUsers))));
end
[pbchAttemptCount, prachAttemptCount, srsAttemptCount, trsAttemptCount] = ...
    localResolveLiveControlAttemptCounts(rawTrials, runtimeState, meta);
dlTrialRows = double(height(dlT));
ulTrialRows = double(height(ulT));
controlAttemptCounts = [pbchAttemptCount, prachAttemptCount, ...
    srsAttemptCount, trsAttemptCount];
resolvedLiveStage = sixgr.truth.resolveWaveformLiveStage( ...
    dlTrialRows, ulTrialRows, controlAttemptCounts);
controlReady = any(controlAttemptCounts > 0);
% Directional counters record frames containing data outcomes. Neither their
% minimum nor maximum is elapsed radio time (UL may legitimately have no row).
notes = string(sixgr.util.structGet(meta, "Notes", ""));
dlUserProgress = NaN;
ulUserProgress = NaN;
if isfinite(totalUsers) && totalUsers > 0
    dlUserProgress = min(double(dlUsers) / double(totalUsers), 1);
    ulUserProgress = min(double(ulUsers) / double(totalUsers), 1);
end
if strlength(notes) == 0
    notes = sprintf("Streaming %s at %.3f dB: UE %s/%s, published data trials DL=%d UL=%d, DL users=%d/%s, UL users=%d/%s. Trial coverage is separate from radio-clock progress.", ...
        char(direction), currentSNR, localDisplayProgressValue(currentUE), localDisplayProgressValue(totalUsers), ...
        dlTrialRows, ulTrialRows, ...
        dlUsers, localDisplayProgressValue(totalUsers), ulUsers, localDisplayProgressValue(totalUsers));
end
currentSlot = double(sixgr.util.structGet(runtimeState, "CurrentSlot", NaN));
runCompletion = NaN;
if isfinite(completedFrames) && isfinite(totalFrames) && totalFrames > 0
    runCompletion = min(max(completedFrames / totalFrames, 0), 1);
end
status = struct( ...
    "Stage", char(resolvedLiveStage), ...
    "CurrentDirection", char(direction), ...
    "CurrentSNR_dB", currentSNR, ...
    "SweepPointIndex", double(sixgr.util.structGet(meta, "SweepPointIndex", NaN)), ...
    "SweepPointCount", double(sixgr.util.structGet(meta, "SweepPointCount", NaN)), ...
    "CurrentUEIndex", currentUE, ...
    "TotalUsers", totalUsers, ...
    "CurrentSlot", currentSlot, ...
    "TotalSlots", totalSlots, ...
    "DLCompletedFrames", dlCompletedFrames, ...
    "ULCompletedFrames", ulCompletedFrames, ...
    "CompletedFrames", completedFrames, ...
    "TotalFrames", totalFrames, ...
    "RunCompletion", runCompletion, ...
    "DLTrialRows", dlTrialRows, ...
    "ULTrialRows", ulTrialRows, ...
    "DLUniqueUsersPublished", double(dlUsers), ...
    "ULUniqueUsersPublished", double(ulUsers), ...
    "DLSummaryUsersPublished", double(dlSummaryUsers), ...
    "ULSummaryUsersPublished", double(ulSummaryUsers), ...
    "DLGrantCount", double(sixgr.util.structGet(runtimeState, "LastDLGrantCount", NaN)), ...
    "ULGrantCount", double(sixgr.util.structGet(runtimeState, "LastULGrantCount", NaN)), ...
    "DLActiveUsers", double(sixgr.util.structGet(runtimeState, "LastDLActiveUsers", NaN)), ...
    "ULActiveUsers", double(sixgr.util.structGet(runtimeState, "LastULActiveUsers", NaN)), ...
    "DLGrantedUsers", double(sixgr.util.structGet(runtimeState, "LastDLGrantedUsers", NaN)), ...
    "ULGrantedUsers", double(sixgr.util.structGet(runtimeState, "LastULGrantedUsers", NaN)), ...
    "DLQueueBits", double(sum(double(sixgr.util.structGet(runtimeState, "DLQueueBits", 0)), "omitnan")), ...
    "ULQueueBits", double(sum(double(sixgr.util.structGet(runtimeState, "ULQueueBits", 0)), "omitnan")), ...
    "DLUserProgressFraction", dlUserProgress, ...
    "ULUserProgressFraction", ulUserProgress, ...
    "BidirectionalInterleavingEnabled", true, ...
    "AnchorKPIsReady", true, ...
    "DLTrialsReady", istable(dlT) && ~isempty(dlT), ...
    "ULTrialsReady", istable(ulT) && ~isempty(ulT), ...
    "ControlReady", logical(controlReady), ...
    "HARQReady", localArtifactStructReady(harqInfo, "SummaryTable") || localArtifactStructReady(harqInfo, "TimelineTable"), ...
    "BeamReady", istable(beamT) && ~isempty(beamT), ...
    "RFReady", istable(energySummary) && ~isempty(energySummary) && istable(iqSummary) && ~isempty(iqSummary), ...
    "PBCHAttemptCount", pbchAttemptCount, ...
    "PRACHAttemptCount", prachAttemptCount, ...
    "SRSAttemptCount", srsAttemptCount, ...
    "TRSAttemptCount", trsAttemptCount, ...
    "SweepReady", false, ...
    "FinalBundleReady", false, ...
    "Notes", char(notes));
if isstruct(runtimeState) && ~isempty(fieldnames(runtimeState))
    clock = sixgr.truth.resolveRuntimeClockProgress(runtimeState);
    clockFields = fieldnames(clock);
    for fieldIndex = 1:numel(clockFields)
        status.(clockFields{fieldIndex}) = clock.(clockFields{fieldIndex});
    end
end
end

function [pbchCount, prachCount, srsCount, trsCount] = localResolveLiveControlAttemptCounts(rawTrials, runtimeState, meta)
pbchCount = localResolveOneLiveControlAttemptCount(rawTrials, runtimeState, meta, "PBCH", "PBCHAttemptCount");
prachCount = localResolveOneLiveControlAttemptCount(rawTrials, runtimeState, meta, "PRACH", "PRACHAttemptCount");
srsCount = localResolveOneLiveControlAttemptCount(rawTrials, runtimeState, meta, "SRS", "SRSAttemptCount");
trsCount = localResolveOneLiveControlAttemptCount(rawTrials, runtimeState, meta, "TRS", "TRSAttemptCount");
end

function n = localControlTrialHeight(rawTrials, trialField)
n = 0;
if nargin < 1 || ~isstruct(rawTrials)
    return;
end
T = sixgr.util.structGet(rawTrials, char(string(trialField)), table());
if istable(T)
    n = double(height(T));
end
end

function count = localResolveOneLiveControlAttemptCount(rawTrials, runtimeState, meta, trialField, metaField)
count = double(sixgr.util.structGet(meta, char(metaField), NaN));
rawT = sixgr.util.structGet(rawTrials, char(trialField), table());
if istable(rawT)
    count = localMaxFiniteScalar(count, height(rawT));
end
controlTrials = sixgr.util.structGet(runtimeState, "ControlTrials", struct());
stateT = sixgr.util.structGet(controlTrials, char(trialField), table());
if istable(stateT)
    count = localMaxFiniteScalar(count, height(stateT));
end
if ~isfinite(count)
    count = 0;
end
end

function out = localMaxFiniteScalar(varargin)
vals = [];
for i = 1:nargin
    v = double(varargin{i});
    v = v(isfinite(v));
    vals = [vals; v(:)]; %#ok<AGROW>
end
if isempty(vals)
    out = NaN;
else
    out = max(vals);
end
end

function n = localUniqueUserCount(T)
n = 0;
if ~(istable(T) && ~isempty(T) && ismember("UEIndex", string(T.Properties.VariableNames)))
    return;
end
vals = unique(double(T.UEIndex), "stable");
vals = vals(isfinite(vals));
n = numel(vals);
end

function txt = localDisplayProgressValue(value)
if ~(isfinite(value) && value >= 0)
    txt = "?";
else
    txt = char(string(round(double(value))));
end
end

function [rowCount, summary] = localResolveSINRObservabilitySummary(trialRowsOrTable, configuredSNR_dB)
rowCount = 0;
trialT = table();
if istable(trialRowsOrTable)
    trialT = trialRowsOrTable;
    rowCount = height(trialT);
elseif isnumeric(trialRowsOrTable) && isscalar(trialRowsOrTable) && isfinite(trialRowsOrTable)
    rowCount = double(trialRowsOrTable);
end
pointT = trialT;
if istable(pointT) && ~isempty(pointT) && isfinite(configuredSNR_dB) && ...
        ismember("ConfiguredSNR_dB", string(pointT.Properties.VariableNames))
    configured = double(pointT.ConfiguredSNR_dB);
    pointT = pointT(isfinite(configured) & ...
        abs(configured - double(configuredSNR_dB)) <= 1e-9, :);
end
summary = localFormatOperatingPointSINRObservabilitySummary(pointT, configuredSNR_dB);
end

function summary = localFormatOperatingPointSINRObservabilitySummary(trialT, configuredSNR_dB)
if isfinite(configuredSNR_dB)
    configuredText = sprintf("configured operating-point label %.3f dB (not a measured SINR)", double(configuredSNR_dB));
else
    configuredText = "configured operating-point label unavailable";
end
postEqText = localFormatLiveSINRStatistic(trialT, "PostEqSINR_dB", "PostEqSINR_dB");
measuredText = localFormatLiveSINRStatistic(trialT, "MeasuredTrialSINR_dB", "MeasuredTrialSINR_dB");
receiverText = localFormatLiveSINRStatistic(trialT, "ReceiverHestSINR_dB", "ReceiverHestSINR_dB");
summary = string(sprintf("%s; %s; %s; %s", configuredText, postEqText, measuredText, receiverText));
end

function txt = localFormatLiveSINRStatistic(trialT, varName, label)
txt = sixgr.truth.formatLiveSINRStatistic(trialT,string(varName),string(label));
end

function localEmitMultiUserLiveSnapshot(existingRows, existingConstRows, partialTrials, partialConst, meta, cfg, multiUser, ueIdx, userMeta, snr_dB, direction, livePublisher)
if isempty(livePublisher)
    return;
end
partialT = localAnnotateUserTrials(localEnsureLinkTrialTable(partialTrials, upper(string(direction)), snr_dB, cfg), cfg, multiUser, ueIdx, userMeta);
partialConstT = localAnnotateConstellationSamples(partialConst, cfg, multiUser, ueIdx, userMeta, snr_dB, direction);

completedRows = existingRows(~cellfun(@isempty, existingRows));
if isempty(completedRows)
    combinedT = partialT;
else
    combinedT = vertcat(completedRows{:}, partialT);
end

completedConstRows = existingConstRows(cellfun(@(x) istable(x) && ~isempty(x), existingConstRows));
if isempty(completedConstRows)
    combinedConstT = partialConstT;
elseif istable(partialConstT) && ~isempty(partialConstT)
    combinedConstT = vertcat(completedConstRows{:}, partialConstT);
else
    combinedConstT = vertcat(completedConstRows{:});
end

meta = localMergeLiveMeta(meta, struct( ...
    "Direction", string(direction), ...
    "SNR_dB", double(snr_dB), ...
    "CurrentUEIndex", double(ueIdx), ...
    "TotalUsers", double(max(1, round(double(multiUser.NumUsers))))));
if isfield(meta, "WaveformPreviewTable")
    meta.WaveformPreviewTable = localAnnotateWaveformPreviewTable(meta.WaveformPreviewTable, cfg, ueIdx, direction);
end
try
    feval(livePublisher, combinedT, combinedConstT, meta);
catch
end
end

function varargout = localAnnotateWaveformPreviewTable(varargin)
% Compatibility delegate; completion/publication has one production owner.
[varargout{1:nargout}] = sixgr.truth.SharedDataCompletionRuntime.annotateWaveformPreviewTable(varargin{:});
end

function varargout = localAnnotateUserTrials(varargin)
% Compatibility delegate; completion/publication has one production owner.
[varargout{1:nargout}] = sixgr.truth.SharedDataCompletionRuntime.annotateUserTrials(varargin{:});
end

function varargout = ternaryInterferenceMode(varargin)
% Compatibility delegate; completion/publication has one production owner.
[varargout{1:nargout}] = sixgr.truth.SharedDataCompletionRuntime.ternaryInterferenceMode(varargin{:});
end


function varargout = localAnnotateGrantDrivenTrials(varargin)
% Compatibility delegate; completion/publication has one production owner.
[varargout{1:nargout}] = sixgr.truth.SharedDataCompletionRuntime.annotateGrantRows(varargin{:});
end

function varargout = localAnnotateConstellationSamples(varargin)
% Compatibility delegate; completion/publication has one production owner.
[varargout{1:nargout}] = sixgr.truth.SharedDataCompletionRuntime.annotateConstellationSamples(varargin{:});
end

function varargout = localCanonicalizeConstellationSampleTable(varargin)
% Compatibility delegate; completion/publication has one production owner.
[varargout{1:nargout}] = sixgr.truth.SharedDataCompletionRuntime.canonicalizeConstellationSampleTable(varargin{:});
end

function varargout = localDisambiguateConstellationCaseCollisionColumns(varargin)
% Compatibility delegate; completion/publication has one production owner.
[varargout{1:nargout}] = sixgr.truth.SharedDataCompletionRuntime.disambiguateConstellationCaseCollisionColumns(varargin{:});
end

function varargout = localConstellationNumericColumn(varargin)
% Compatibility delegate; completion/publication has one production owner.
[varargout{1:nargout}] = sixgr.truth.SharedDataCompletionRuntime.constellationNumericColumn(varargin{:});
end

function varargout = localConstellationStringColumn(varargin)
% Compatibility delegate; completion/publication has one production owner.
[varargout{1:nargout}] = sixgr.truth.SharedDataCompletionRuntime.constellationStringColumn(varargin{:});
end

function summary = localMergeMultiUserSummaries(dlSummary, ulSummary, multiUser)
parts = {};
if istable(dlSummary) && ~isempty(dlSummary)
    parts{end+1} = dlSummary; %#ok<AGROW>
end
if istable(ulSummary) && ~isempty(ulSummary)
    parts{end+1} = ulSummary; %#ok<AGROW>
end
if isempty(parts)
    summary = localBuildDirectionUserSummaryFromRaw(table(), "", multiUser, struct());
    summary.NumUsersConfigured = zeros(0, 1);
    return;
end
summary = table();
for pi = 1:numel(parts)
    summary = localAppendCompatTable(summary, parts{pi});
end
summary.NumUsersConfigured = repmat(double(multiUser.NumUsers), height(summary), 1);
end

function T = localBuildSNRSweepFromRawTrials(rawTrials, cfg, snrGrid)
snrSet = unique(sort(double(snrGrid(:))));
if isempty(snrSet)
    snrSet = unique(sort([ ...
        localTableUniqueFinite(rawTrials, "DL", "SNR_dB"); ...
        localTableUniqueFinite(rawTrials, "UL", "SNR_dB"); ...
        localTableUniqueFinite(rawTrials, "SRS", "SNR_dB")]));
end
if isempty(snrSet)
    T = table();
    return;
end

n = numel(snrSet);
rows = repmat(localEmptySweepSummaryRow(0), n, 1);

for i = 1:n
    snr = double(snrSet(i));
    row = localEmptySweepSummaryRow(snr);
    dlT = localSubsetTrialsBySNR(sixgr.util.structGet(rawTrials, "DL", table()), snr);
    if ~isempty(dlT)
        dlStats = localSummarizeLinkTrialTable(dlT, cfg);
        row = localApplyLinkSweepStats(row, "DL", dlStats);
    elseif logical(sixgr.util.structGet(cfg, "phy.pdsch.enable", false))
        % An enabled link with no executed waveform trial at this operating
        % point is unavailable evidence, not a zero-error success.
        row.DL_TrialCount = 0;
        row.DL_FailureCount = 0;
        row.DL_Incomplete = true;
        row.DL_StopReason = "NO_RUNTIME_TRIALS_AT_OPERATING_POINT";
    end

    ulT = localSubsetTrialsBySNR(sixgr.util.structGet(rawTrials, "UL", table()), snr);
    if ~isempty(ulT)
        ulStats = localSummarizeLinkTrialTable(ulT, cfg);
        row = localApplyLinkSweepStats(row, "UL", ulStats);
    elseif logical(sixgr.util.structGet(cfg, "phy.pusch.enable", false))
        row.UL_TrialCount = 0;
        row.UL_FailureCount = 0;
        row.UL_Incomplete = true;
        row.UL_StopReason = "NO_RUNTIME_TRIALS_AT_OPERATING_POINT";
    end

    srsT = localSubsetTrialsBySNR(sixgr.util.structGet(rawTrials, "SRS", table()), snr);
    row = sixgr.truth.applySRSSweepStatistics(row,localEffectiveTrialRows(srsT));
    rows(i) = row;
end

T = struct2table(rows);
end

function cfgRef = localBuildFixedReferenceCfg(cfg)
cfgRef = cfg;
cfgRef = sixgr.util.structSet(cfgRef, "phy.linkAdaptation.mode", "fixed");
cfgRef = sixgr.util.structSet(cfgRef, "phy.linkAdaptation.dlPolicy", "fixed");
cfgRef = sixgr.util.structSet(cfgRef, "phy.linkAdaptation.ulPolicy", "fixed");
cfgRef = sixgr.util.structSet(cfgRef, "phy.linkAdaptation.rankPolicy", "fixed");
cfgRef = sixgr.util.structSet(cfgRef, "phy.linkAdaptation.beamPolicy", "fixed");
cfgRef = sixgr.util.structSet(cfgRef, "phy.linkAdaptation.deltaCQIPolicy", "none");
cfgRef = sixgr.util.structSet(cfgRef, "phy.linkAdaptation.deltaMCSPolicy", "none");
cfgRef = sixgr.util.structSet(cfgRef, "phy.linkAdaptation.fixedReferenceMode", true);
cfgRef = sixgr.util.structSet(cfgRef, "run.fixedReferenceMode", true);
cfgRef = sixgr.util.structSet(cfgRef, "run.noiseOperatingMode", "standalone_awgn_snr_argument");
end

function T = localRunReferenceLinkSNRSweep(cfg, snrGrid, nFrames, multiUser, sweepPlan)
if nargin < 5 || ~isstruct(sweepPlan)
    sweepPlan = localResolveSweepPlan(struct(), nFrames);
end
campaign = localRunFixedLinkCampaign(cfg, localBuildReferenceSweepGrid(snrGrid, sweepPlan), sweepPlan, multiUser);
T = sixgr.util.structGet(campaign, "Summary", table());
end

function campaign = localEmptyFixedLinkCampaignResult(enabled)
if nargin < 1
    enabled = false;
end
campaign = struct( ...
    "Enabled", logical(enabled), ...
    "CampaignKind", "fixed_link_monte_carlo", ...
    "Summary", table(), ...
    "DLTrials", table(), ...
    "ULTrials", table(), ...
    "TaskPlan", table(), ...
    "SNRGrid_dB", [], ...
    "SeedBase", NaN, ...
    "DLBlerCurve", table(), ...
    "ULBlerCurve", table(), ...
    "DLBerCurve", table(), ...
    "ULBerCurve", table(), ...
    "ReportSummary", table(), ...
    "TargetCrossings", table(), ...
    "Notes", "");
end

function localWriteFixedLinkCampaignEvidence(runFolder, campaign)
if ~(isstruct(campaign) && logical(sixgr.util.structGet(campaign, "Enabled", false)))
    return;
end
taskPlan = sixgr.util.structGet(campaign, "TaskPlan", table());
if istable(taskPlan) && ~isempty(taskPlan)
    sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "fixed_link_campaign_task_plan.csv"), taskPlan);
end
dlTrials = sixgr.util.structGet(campaign, "DLTrials", table());
if istable(dlTrials) && ~isempty(dlTrials)
    sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "dl_fixed_link_campaign_trials.csv"), dlTrials);
end
ulTrials = sixgr.util.structGet(campaign, "ULTrials", table());
if istable(ulTrials) && ~isempty(ulTrials)
    sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "ul_fixed_link_campaign_trials.csv"), ulTrials);
end
end

function rawTrials = localPublishFixedLinkCanonicalTruthEvidence( ...
        runFolder, cfg, multiUser, campaign)
% Publish the real fixed-link PHY trials under the canonical browser paths.
%
% A fixed-link campaign has no live scheduler or HARQ lifecycle. Its
% canonical truth is the independently decoded PDSCH/PUSCH transport-block
% trial set returned by runFixedLinkCampaign.
rawTrials = struct( ...
    "DL", sixgr.util.structGet(campaign, "DLTrials", table()), ...
    "UL", sixgr.util.structGet(campaign, "ULTrials", table()));
rawTrials.DL = localCanonicalizeLinkTrialExport(rawTrials.DL, "DL", cfg);
rawTrials.UL = localCanonicalizeLinkTrialExport(rawTrials.UL, "UL", cfg);

rootRunFolder = fileparts(char(string(runFolder)));
layout = sixgr.report.resultLayout(rootRunFolder);
if istable(rawTrials.DL) && ~isempty(rawTrials.DL)
    sixgr.util.csvWriteTable( ...
        fullfile(layout.AirInterfaceCSVDir, "dl_pdsch_trials.csv"), ...
        rawTrials.DL, "PreserveSchema", true);
end
if istable(rawTrials.UL) && ~isempty(rawTrials.UL)
    sixgr.util.csvWriteTable( ...
        fullfile(layout.AirInterfaceCSVDir, "ul_pusch_trials.csv"), ...
        rawTrials.UL, "PreserveSchema", true);
end

localPublishRuntimeReferenceArtifacts( ...
    runFolder, cfg, multiUser, rawTrials);
controlSummary = localBuildFixedLinkControlApplicabilityTable(cfg);
rawTrials.ControlGatingSummaryTable = controlSummary;
sixgr.util.csvWriteTable( ...
    fullfile(layout.ReportCSVDir, "live_control_gating_summary.csv"), ...
    controlSummary);
end

function T = localBuildFixedLinkControlApplicabilityTable(cfg)
disableAuxiliarySignals = logical(sixgr.util.structGet( ...
    cfg, "validation.fixed_link_campaign.disable_auxiliary_signals", true));
if ~disableAuxiliarySignals
    error("sixgr:truth:FixedLinkAuxiliarySignalsMustBeDisabled", ...
        "A FixedLinkCampaignOnly run cannot publish the fixed-link " + ...
        "control-applicability table unless " + ...
        "validation.fixed_link_campaign.disable_auxiliary_signals=true.");
end
T = table( ...
    "fixed_link_calibration_auxiliary_signals_disabled", ...
    false, false, false, false, false, ...
    "validation.fixed_link_campaign.disable_auxiliary_signals", ...
    "not_applicable_no_scheduler_or_control_lifecycle", ...
    'VariableNames', { ...
    'ControlIntegrationMode', ...
    'PBCHGatingActive', ...
    'PRACHGatingActive', ...
    'PDCCHGatingActive', ...
    'SRSGatingActive', ...
    'TRSGatingActive', ...
    'AppliedConfigurationSource', ...
    'Applicability'});
end

function grid = localResolveFixedLinkCampaignGrid(snrGrid, sweepPlan)
explicit = double(sixgr.util.structGet(sweepPlan, "FixedLinkSNRGrid_dB", []));
explicit = explicit(:);
explicit = explicit(isfinite(explicit));
if ~isempty(explicit)
    grid = unique(sort(explicit));
    return;
end
grid = localBuildReferenceSweepGrid(snrGrid, sweepPlan);
end

function cfgCampaign = localResolveFixedLinkCampaignConfig(cfg, snrGrid, sweepPlan)
runtimeCfg = sixgr.util.structGet(sweepPlan, "FixedLinkCampaignConfig", struct());
cfgCampaign = localOverlayStruct( ...
    sixgr.util.structGet(cfg, "validation.fixed_link_campaign", struct()), ...
    runtimeCfg);
if isstruct(runtimeCfg) && ~isempty(fieldnames(runtimeCfg))
    % The resolved validation.fixed_link_campaign block is the production
    % authority. Do not rewrite it from legacy LinkFixedLink* convenience
    % options after schema validation.
    return;
end
cfgCampaign.Enabled = logical(sixgr.util.structGet(runtimeCfg, "Enabled", ...
    sixgr.util.structGet(runtimeCfg, "enabled", logical(sixgr.util.structGet(sweepPlan, "FixedLinkCampaignEnabled", false)))));
cfgCampaign.SNR_dB = double(sixgr.util.structGet(runtimeCfg, "SNR_dB", ...
    sixgr.util.structGet(runtimeCfg, "snr_db", double(snrGrid(:).'))));
cfgCampaign.MinTBPerPoint = max(1, round(double(sixgr.util.structGet(runtimeCfg, "MinTBPerPoint", ...
    sixgr.util.structGet(runtimeCfg, "min_tb_per_point", sixgr.util.structGet(sweepPlan, "FixedLinkMinTrials", 1))))));
cfgCampaign.MaxTBPerPoint = max(cfgCampaign.MinTBPerPoint, round(double(sixgr.util.structGet(runtimeCfg, "MaxTBPerPoint", ...
    sixgr.util.structGet(runtimeCfg, "max_tb_per_point", sixgr.util.structGet(sweepPlan, "FixedLinkMaxTrials", cfgCampaign.MinTBPerPoint))))));
cfgCampaign.MinErrorsForCI = max(0, round(double(sixgr.util.structGet(runtimeCfg, "MinErrorsForCI", ...
    sixgr.util.structGet(runtimeCfg, "min_errors_for_ci", sixgr.util.structGet(sweepPlan, "FixedLinkErrorTarget", inf))))));
cfgCampaign.MaxCIHalfWidth = double(sixgr.util.structGet(runtimeCfg, "MaxCIHalfWidth", ...
    sixgr.util.structGet(runtimeCfg, "max_ci_half_width", double(sixgr.util.structGet(sweepPlan, "FixedLinkCIWidthTarget", inf)) / 2)));
cfgCampaign.BatchTBCount = max(1, round(double(sixgr.util.structGet(runtimeCfg, "BatchTBCount", ...
    sixgr.util.structGet(runtimeCfg, "batch_tb_count", sixgr.util.structGet(sweepPlan, "FixedLinkTrialsPerDrop", 1))))));
cfgCampaign.TargetBLER = double(sixgr.util.structGet(runtimeCfg, "TargetBLER", ...
    sixgr.util.structGet(runtimeCfg, "target_bler", sixgr.util.structGet(sweepPlan, "FixedLinkTargetBLER", 0.10))));
cfgCampaign.Seeds = double(sixgr.util.structGet(runtimeCfg, "Seeds", ...
    sixgr.util.structGet(runtimeCfg, "seeds", sixgr.util.structGet(sweepPlan, "FixedLinkSeed", 730001))));
cfgCampaign.SeedBase = double(sixgr.util.structGet(runtimeCfg, "SeedBase", ...
    sixgr.util.structGet(runtimeCfg, "seed_base", sixgr.util.structGet(sweepPlan, "FixedLinkSeed", 730001))));
cfgCampaign.ConfidenceLevel = double(sixgr.util.structGet(runtimeCfg, "ConfidenceLevel", ...
    sixgr.util.structGet(runtimeCfg, "confidence_level", ...
    sixgr.util.structGet(sweepPlan,"FixedLinkConfidenceLevel", ...
    localConfiguredConfidenceLevel(cfg)))));
end

function tf = localFixedLinkCampaignEvidenceOk(campaign)
summary = sixgr.util.structGet(campaign, "ReportSummary", table());
if ~(istable(summary) && ~isempty(summary))
    tf = false;
    return;
end
curvePresent = localTableLogicalColumn(summary, "CurvePresent");
ciPresent = localTableLogicalColumn(summary, "ConfidenceIntervalsPresent");
tf = any(curvePresent) && all(curvePresent & ciPresent);
end

function values = localTableLogicalColumn(T, varName)
values = false(height(T), 1);
if ~(istable(T) && ismember(char(string(varName)), T.Properties.VariableNames))
    return;
end
raw = T.(char(string(varName)));
if islogical(raw)
    values = logical(raw);
elseif isnumeric(raw)
    values = double(raw) ~= 0;
else
    values = lower(strtrim(string(raw))) == "true";
end
end

function out = localOverlayStruct(base, overlay)
out = base;
if ~(builtin("isstruct", overlay) && isscalar(overlay))
    return;
end
fields = string(fieldnames(overlay));
for i = 1:numel(fields)
    out.(char(fields(i))) = overlay.(char(fields(i)));
end
end

function campaign = localRunFixedLinkCampaign(cfg, snrGrid, sweepPlan, multiUser)
cfgCampaign = localResolveFixedLinkCampaignConfig(cfg, snrGrid, sweepPlan);
campaign = sixgr.lls6g.campaign.runFixedLinkCampaign(cfg, ...
    "Config", cfgCampaign, ...
    "RootRunFolder", sixgr.util.structGet(cfg, "run.rootRunFolder", ""), ...
    "WriteArtifacts", logical(sixgr.util.structGet(cfg, "run.fixedLinkCampaignWriteArtifacts", true)));
end

function campaign = localRunFixedLinkCampaignSingleUser(cfg, snrGrid, sweepPlan)
campaign = localEmptyFixedLinkCampaignResult(true);
cfgRef = localBuildFixedReferenceCfg(cfg);
snrGrid = unique(sort(double(snrGrid(:))));
n = numel(snrGrid);
rows = repmat(localEmptySweepSummaryRow(0), n, 1);
dlAll = table();
ulAll = table();
taskPlan = localBuildFixedLinkTaskPlan(cfgRef, snrGrid, sweepPlan);
campaign.TaskPlan = taskPlan;

for i = 1:n
    snr = double(snrGrid(i));
    pointSeed = localTaskPlanSeed(taskPlan, i, 0, "POINT", sweepPlan);
    row = localEmptySweepSummaryRow(snr);
    row.CampaignKind = "fixed_link_monte_carlo";
    row.SweepKind = "fixed_reference_awgn_snr_campaign";
    row.FixedReferenceMode = true;
    row.NoiseOperatingMode = "standalone_awgn_snr_argument";
    row.ConfidenceLevel = double(sweepPlan.FixedLinkConfidenceLevel);
    row.SequentialMinTrials = double(sweepPlan.FixedLinkMinTrials);
    row.SequentialMaxTrials = double(sweepPlan.FixedLinkMaxTrials);
    row.SequentialErrorTarget = double(sweepPlan.FixedLinkErrorTarget);
    row.SequentialCIWidthTarget = double(sweepPlan.FixedLinkCIWidthTarget);
    row.TrialsPerDrop = double(sweepPlan.FixedLinkTrialsPerDrop);
    row.PointIndex = double(i);
    row.PointSeed = double(pointSeed);
    row.DL_TargetBLER = double(sweepPlan.FixedLinkTargetBLER);
    row.UL_TargetBLER = double(sweepPlan.FixedLinkTargetBLER);

    if logical(sixgr.util.structGet(cfgRef, "phy.pdsch.enable", false))
        [stats, trials] = localRunFixedDirectionCampaignPoint(cfgRef, "DL", snr, i, sweepPlan, taskPlan);
        row = localApplyFixedDirectionStats(row, "DL", stats);
        dlAll = localAppendCompatTable(dlAll, trials);
    end

    if logical(sixgr.util.structGet(cfgRef, "phy.pusch.enable", false))
        [stats, trials] = localRunFixedDirectionCampaignPoint(cfgRef, "UL", snr, i, sweepPlan, taskPlan);
        row = localApplyFixedDirectionStats(row, "UL", stats);
        ulAll = localAppendCompatTable(ulAll, trials);
    end

    if logical(sixgr.util.structGet(cfgRef, "phy.srs.enable", false))
        row = localApplyFixedSRSMeasurement(row, cfgRef, snr, i, sweepPlan, taskPlan);
    end

    rows(i, 1) = row;
end

summary = struct2table(rows);
summary = localAnnotateFixedLinkCurveCrossings(summary, sweepPlan);
campaign.Summary = summary;
campaign.DLTrials = dlAll;
campaign.ULTrials = ulAll;
campaign.SNRGrid_dB = snrGrid(:).';
campaign.SeedBase = double(sweepPlan.FixedLinkSeed);
campaign.Notes = "fixed_link_campaign_uses_waveform_dl_ul_kernels_with_standalone_awgn_snr_argument";
end

function taskPlan = localBuildFixedLinkTaskPlan(cfg, snrGrid, sweepPlan)
tokens = strings(0, 1);
if logical(sixgr.util.structGet(cfg, "phy.pdsch.enable", false))
    tokens(end+1, 1) = "DL";
end
if logical(sixgr.util.structGet(cfg, "phy.pusch.enable", false))
    tokens(end+1, 1) = "UL";
end
if logical(sixgr.util.structGet(cfg, "phy.srs.enable", false))
    tokens(end+1, 1) = "SRS";
end
if isempty(tokens)
    tokens = "POINT";
end
taskPlan = sixgr.util.buildDeterministicTaskPlan(double(sweepPlan.FixedLinkSeed), double(snrGrid(:)), tokens, ...
    "MaxTrials", double(sweepPlan.FixedLinkMaxTrials), ...
    "TrialsPerDrop", double(sweepPlan.FixedLinkTrialsPerDrop), ...
    "IncludePointTasks", true, ...
    "ExecutionGranularity", "fixed_link_campaign_point_drop_link");
end

function seed = localTaskPlanSeed(taskPlan, pointIndex, dropIndex, linkToken, sweepPlan)
linkToken = upper(string(linkToken));
seed = sixgr.util.hierarchicalSeed(double(sweepPlan.FixedLinkSeed), pointIndex, dropIndex, 0, linkToken);
if ~(istable(taskPlan) && ~isempty(taskPlan))
    return;
end
mask = double(taskPlan.PointIndex) == double(pointIndex) & ...
    double(taskPlan.DropIndex) == double(dropIndex) & ...
    upper(string(taskPlan.LinkToken)) == linkToken;
if any(mask)
    seed = double(taskPlan.TaskSeed(find(mask, 1, "first")));
end
end

function [stats, T] = localRunFixedDirectionCampaignPoint(cfg, direction, snr, pointIndex, sweepPlan, taskPlan)
direction = upper(string(direction));
T = localEmptyLinkTrialTable(0);
dropIndex = 0;
while true
    stats = localSummarizeFixedLinkTrialTable(T, cfg, sweepPlan);
    stopReason = localFixedLinkStopReason(stats, sweepPlan);
    if stopReason ~= "continue"
        stats.StopReason = stopReason;
        stats.Incomplete = localFixedLinkIncomplete(stats, sweepPlan, stopReason);
        return;
    end

    completed = max(0, round(double(sixgr.util.structGet(stats, "TrialCount", 0))));
    if completed >= double(sweepPlan.FixedLinkMaxTrials)
        stats.StopReason = "MAX_TRIALS_REACHED_INCOMPLETE";
        stats.Incomplete = localFixedLinkIncomplete(stats, sweepPlan, stats.StopReason);
        return;
    end

    dropIndex = dropIndex + 1;
    remaining = double(sweepPlan.FixedLinkMaxTrials) - completed;
    nFrames = max(1, min(round(double(sweepPlan.FixedLinkTrialsPerDrop)), round(remaining)));
    dropSeed = localTaskPlanSeed(taskPlan, pointIndex, dropIndex, direction, sweepPlan);
    cfgDrop = cfg;
    cfgDrop = sixgr.util.structSet(cfgDrop, "run.seed", double(dropSeed));
    cfgDrop = sixgr.util.structSet(cfgDrop, "channel.snr_dB", double(snr));
    cfgDrop = sixgr.util.structSet(cfgDrop, "run.noiseOperatingMode", "standalone_awgn_snr_argument");
    startFrame = 1 + completed;

    if direction == "DL"
        res = sixgr.link.runDLPDSCHThroughput(cfgDrop, ...
            "NumFrames", nFrames, ...
            "SNR_dB", snr, ...
            "StartFrameIndex", startFrame);
    else
        res = sixgr.link.runULPUSCHThroughput(cfgDrop, ...
            "NumFrames", nFrames, ...
            "SNR_dB", snr, ...
            "StartFrameIndex", startFrame);
    end

    if logical(sixgr.util.structGet(res, "Skipped", false))
        error("sixgr:truth:FixedLinkCampaignSkipped", ...
            "%s fixed-link campaign point %.6g dB skipped: %s", direction, snr, string(sixgr.util.structGet(res, "Notes", "")));
    end

    Ti = localEnsureLinkTrialTable(sixgr.util.structGet(res, "TrialTable", table()), direction, snr, cfgDrop);
    Ti = localAnnotateFixedLinkTrialRows(Ti, pointIndex, dropIndex, dropSeed, completed, direction, sweepPlan);
    T = localAppendCompatTable(T, Ti);
end
end

function T = localAnnotateFixedLinkTrialRows(T, pointIndex, dropIndex, dropSeed, completed, direction, sweepPlan)
if ~(istable(T) && ~isempty(T))
    return;
end
n = height(T);
T.FixedLinkCampaign = true(n, 1);
T.FixedLinkCampaignKind = repmat("fixed_link_monte_carlo", n, 1);
T.FixedReferenceMode = true(n, 1);
T.FixedLinkPointIndex = repmat(double(pointIndex), n, 1);
T.FixedLinkDropIndex = repmat(double(dropIndex), n, 1);
T.FixedLinkDropSeed = repmat(double(dropSeed), n, 1);
T.FixedLinkTrialIndex = double(completed) + (1:n).';
T.FixedLinkDirection = repmat(upper(string(direction)), n, 1);
T.FixedLinkNoiseVariable = repmat("SNR_dB", n, 1);
T.FixedLinkConfidenceLevel = repmat(double(sweepPlan.FixedLinkConfidenceLevel), n, 1);
T.FixedLinkSeedHierarchy = "campaign=" + string(double(sweepPlan.FixedLinkSeed)) + ...
    "|point=" + string(double(pointIndex)) + ...
    "|drop=" + string(double(dropIndex)) + ...
    "|trial=" + string(T.FixedLinkTrialIndex) + ...
    "|link=" + upper(string(direction));
end

function stats = localSummarizeFixedLinkTrialTable(T, cfg, sweepPlan)
stats = localSummarizeLinkTrialTable(T, cfg);
stats.BLER_CI_Method = "clopper_pearson_exact";
stats.BER_CI_Method = "clopper_pearson_exact";
stats.BLER_CI_Width = NaN;
stats.DropCount = NaN;
stats.BLER_ClusterCI_Low = NaN;
stats.BLER_ClusterCI_High = NaN;
stats.StopReason = "continue";
stats.Incomplete = false;
Te = localEffectiveTrialRows(T);
if isempty(Te)
    stats.TrialCount = 0;
    stats.FailureCount = 0;
    return;
end
status = upper(strtrim(string(Te.Status)));
failMask = status == "FAIL" | status == "CRASH";
bits = double(Te.BitsCompared);
bits(~isfinite(bits)) = 0;
bitErr = double(Te.BitErrors);
bitErr(~isfinite(bitErr)) = 0;
stats.TrialCount = double(height(Te));
stats.FailureCount = double(sum(failMask));
[stats.BLER_CI_Low, stats.BLER_CI_High] = localClopperPearsonInterval(stats.FailureCount, stats.TrialCount, sweepPlan.FixedLinkConfidenceLevel);
[stats.BER_CI_Low, stats.BER_CI_High] = localClopperPearsonInterval(sum(bitErr), sum(bits), sweepPlan.FixedLinkConfidenceLevel);
stats.BLER_CI_Width = stats.BLER_CI_High - stats.BLER_CI_Low;
if ismember("FixedLinkDropIndex", string(Te.Properties.VariableNames))
    drops = double(Te.FixedLinkDropIndex);
    valid = isfinite(drops);
    if any(valid)
        [g, ~] = findgroups(drops(valid));
        dropFail = splitapply(@mean, double(failMask(valid)), g);
        stats.DropCount = double(numel(dropFail));
        [stats.BLER_ClusterCI_Low, stats.BLER_ClusterCI_High] = ...
            localMeanConfidenceInterval(dropFail, ...
            sweepPlan.FixedLinkConfidenceLevel);
    end
end
end

function stopReason = localFixedLinkStopReason(stats, sweepPlan)
trialCount = double(sixgr.util.structGet(stats, "TrialCount", 0));
failureCount = double(sixgr.util.structGet(stats, "FailureCount", 0));
ciWidth = double(sixgr.util.structGet(stats, "BLER_CI_Width", inf));
if trialCount < double(sweepPlan.FixedLinkMinTrials)
    stopReason = "continue";
elseif isfinite(double(sweepPlan.FixedLinkErrorTarget)) && failureCount >= double(sweepPlan.FixedLinkErrorTarget)
    stopReason = "MIN_ERRORS_AND_CI_MET";
elseif isfinite(double(sweepPlan.FixedLinkCIWidthTarget)) && isfinite(ciWidth) && ciWidth <= double(sweepPlan.FixedLinkCIWidthTarget)
    stopReason = "MIN_ERRORS_AND_CI_MET";
elseif trialCount >= double(sweepPlan.FixedLinkMaxTrials)
    stopReason = "MAX_TRIALS_REACHED_INCOMPLETE";
else
    stopReason = "continue";
end
end

function tf = localFixedLinkIncomplete(stats, sweepPlan, stopReason)
tf = false;
if string(stopReason) ~= "MAX_TRIALS_REACHED_INCOMPLETE"
    return;
end
failureCount = double(sixgr.util.structGet(stats, "FailureCount", 0));
ciWidth = double(sixgr.util.structGet(stats, "BLER_CI_Width", inf));
metErrorTarget = isfinite(double(sweepPlan.FixedLinkErrorTarget)) && failureCount >= double(sweepPlan.FixedLinkErrorTarget);
metCIWidth = isfinite(double(sweepPlan.FixedLinkCIWidthTarget)) && isfinite(ciWidth) && ciWidth <= double(sweepPlan.FixedLinkCIWidthTarget);
tf = ~(metErrorTarget || metCIWidth);
end

function row = localApplyFixedDirectionStats(row, prefix, stats)
prefix = upper(string(prefix));
row = localApplyLinkSweepStats(row, prefix, stats);
row.(char(prefix + "_BLER_CI_Method")) = string(sixgr.util.structGet(stats, "BLER_CI_Method", ""));
row.(char(prefix + "_BLER_CI_Width")) = double(sixgr.util.structGet(stats, "BLER_CI_Width", NaN));
row.(char(prefix + "_BER_CI_Method")) = string(sixgr.util.structGet(stats, "BER_CI_Method", ""));
row.(char(prefix + "_DropCount")) = double(sixgr.util.structGet(stats, "DropCount", NaN));
row.(char(prefix + "_BLER_ClusterCI_Low")) = double(sixgr.util.structGet(stats, "BLER_ClusterCI_Low", NaN));
row.(char(prefix + "_BLER_ClusterCI_High")) = double(sixgr.util.structGet(stats, "BLER_ClusterCI_High", NaN));
row.(char(prefix + "_StopReason")) = string(sixgr.util.structGet(stats, "StopReason", ""));
row.(char(prefix + "_Incomplete")) = logical(sixgr.util.structGet(stats, "Incomplete", false));
end

function row = localApplyFixedSRSMeasurement(row, cfg, snr, pointIndex, sweepPlan, taskPlan)
seed = localTaskPlanSeed(taskPlan, pointIndex, 1, "SRS", sweepPlan);
cfgSRS = cfg;
cfgSRS = sixgr.util.structSet(cfgSRS, "run.seed", double(seed));
cfgSRS = sixgr.util.structSet(cfgSRS, "channel.snr_dB", double(snr));
cfgSRS = sixgr.util.structSet(cfgSRS, "run.noiseOperatingMode", "standalone_awgn_snr_argument");
rng(double(seed), "twister");
srs = sixgr.link.runSRSChannelEstimation(cfgSRS, "SNR_dB", snr);
if logical(sixgr.util.structGet(srs, "Skipped", false))
    error("sixgr:truth:FixedLinkCampaignSkippedSRS", ...
        "SRS fixed-link campaign point %.6g dB skipped: %s", snr, string(sixgr.util.structGet(srs, "Notes", "")));
end
row = sixgr.truth.applySRSSweepStatistics(row,srs);
end

function [lo, hi] = localClopperPearsonInterval(k, n, confidenceLevel)
lo = NaN;
hi = NaN;
k = double(k);
n = double(n);
if ~(isfinite(n) && n > 0 && isfinite(k) && k >= 0)
    return;
end
k = min(max(k, 0), n);
alpha = 1 - double(confidenceLevel);
alpha = min(max(alpha, eps), 1 - eps);
if k == 0
    lo = 0;
else
    lo = betaincinv(alpha / 2, k, n - k + 1);
end
if k == n
    hi = 1;
else
    hi = betaincinv(1 - alpha / 2, k + 1, n - k);
end
lo = max(0, min(1, double(lo)));
hi = max(0, min(1, double(hi)));
end

function T = localAnnotateFixedLinkCurveCrossings(T, sweepPlan)
if ~(istable(T) && ~isempty(T))
    return;
end
for prefix = ["DL", "UL"]
    targetCol = prefix + "_TargetBLER";
    statusCol = prefix + "_TargetCrossingStatus";
    snrCol = prefix + "_TargetCrossingSNR_dB";
    if ~all(ismember(["SNR_dB", prefix + "_BLER", statusCol, snrCol], string(T.Properties.VariableNames)))
        continue;
    end
    [status, crossingSNR] = localFixedLinkCrossingStatus(T, prefix, ...
        double(sweepPlan.FixedLinkTargetBLER), ...
        double(sweepPlan.FixedLinkMaxTargetCrossingBracket_dB));
    T.(char(targetCol)) = repmat(double(sweepPlan.FixedLinkTargetBLER), height(T), 1);
    T.(char(statusCol)) = repmat(string(status), height(T), 1);
    T.(char(snrCol)) = repmat(double(crossingSNR), height(T), 1);
end
end

function [status, crossingSNR] = localFixedLinkCrossingStatus(T, prefix, targetBLER, maxBracketWidth_dB)
prefix = upper(string(prefix));
x = double(T.SNR_dB);
y = double(T.(char(prefix + "_BLER")));
[status, crossingSNR] = sixgr.validation.qualifyObservedBLERCrossing( ...
    x(:), y(:), double(targetBLER), double(maxBracketWidth_dB));
end

function res = localApplyPrimarySweepResults(res, rawTrials, cfg, snrGrid, pruneMissingPrimaryEvidence)
if nargin < 5
    pruneMissingPrimaryEvidence = false;
end
snrGrid = unique(sort(double(snrGrid(:))));
operatingAuthority = localPrimaryOperatingAuthority(cfg);
authorityLabel = replace(operatingAuthority, "_", "-");
if logical(pruneMissingPrimaryEvidence)
    % Coupled truth deliberately skips the legacy preflight execution.  Its
    % authoritative KPI rows must therefore be created from the primary
    % slot-runtime evidence before the aggregate results are applied.  An
    % empty legacy table is not evidence that the completed coupled bundle
    % failed.
    res = localEnsureCoupledPrimaryKPIRows(res, rawTrials);
end
if isfield(rawTrials, "PBCH") && istable(rawTrials.PBCH) && ~isempty(rawTrials.PBCH)
    aggPBCH = localAggregatePrimaryPassFailCase(rawTrials.PBCH, "PBCH " + authorityLabel);
    res = localReplaceCaseResult(res, "CellSearch_MIB_SIB1", aggPBCH);
end
if isfield(rawTrials, "PRACH") && istable(rawTrials.PRACH) && ~isempty(rawTrials.PRACH)
    aggPRACH = localAggregatePrimaryPassFailCase(rawTrials.PRACH, "PRACH " + authorityLabel);
    res = localReplaceCaseResult(res, "PRACH_Detection", aggPRACH);
end
if isfield(rawTrials, "DL") && istable(rawTrials.DL) && ~isempty(rawTrials.DL)
    aggDL = localAggregatePrimaryLinkCase(rawTrials.DL, cfg, "DL " + authorityLabel);
    res = localReplaceCaseResult(res, "DL_PDSCH_Throughput", aggDL);
end
if isfield(rawTrials, "UL") && istable(rawTrials.UL) && ~isempty(rawTrials.UL)
    aggUL = localAggregatePrimaryLinkCase(rawTrials.UL, cfg, "UL " + authorityLabel);
    res = localReplaceCaseResult(res, "UL_PUSCH_Throughput", aggUL);
    aggPAPR = localAggregatePrimaryULPAPRCase(rawTrials.UL, operatingAuthority);
    res = localReplaceCaseResult(res, "UL_LowPAPR", aggPAPR);
end
if isfield(rawTrials, "SRS") && istable(rawTrials.SRS) && ~isempty(rawTrials.SRS)
    aggSRS = localAggregatePrimarySRSCase(rawTrials.SRS, operatingAuthority);
    res = localReplaceCaseResult(res, "UL_SRS_ChannelEst", aggSRS);
end
if logical(pruneMissingPrimaryEvidence)
    res = localPrunePrimaryCasesWithoutEvidence(res, rawTrials);
end
res.Ok = localLinkKPITableHealthy(res.KPITable);
end

function res = localEnsureCoupledPrimaryKPIRows(res, rawTrials)
specs = [ ...
    struct("Case", "CellSearch_MIB_SIB1", "Field", "PBCH"); ...
    struct("Case", "PRACH_Detection", "Field", "PRACH"); ...
    struct("Case", "DL_PDSCH_Throughput", "Field", "DL"); ...
    struct("Case", "UL_PUSCH_Throughput", "Field", "UL"); ...
    struct("Case", "UL_SRS_ChannelEst", "Field", "SRS"); ...
    struct("Case", "UL_LowPAPR", "Field", "UL")];

if ~(isfield(res, "KPITable") && istable(res.KPITable))
    res.KPITable = table();
end
existingCases = strings(0, 1);
if ~isempty(res.KPITable) && ismember("Case", string(res.KPITable.Properties.VariableNames))
    existingCases = string(res.KPITable.Case);
end

newRows = repmat(localMakeBundleAnchorKpiRow("", struct()), 0, 1);
for i = 1:numel(specs)
    if ~localHasPrimaryEvidence(rawTrials, specs(i).Field) || ...
            any(strcmpi(existingCases, specs(i).Case))
        continue;
    end
    deferred = struct( ...
        "Ok", false, ...
        "Skipped", false, ...
        "Notes", "pending_primary_coupled_runtime_aggregation");
    newRows(end+1, 1) = localMakeBundleAnchorKpiRow(specs(i).Case, deferred); %#ok<AGROW>
    existingCases(end+1, 1) = specs(i).Case; %#ok<AGROW>
end

if isempty(newRows)
    return;
end
newTable = struct2table(newRows);
if isempty(res.KPITable)
    res.KPITable = newTable;
else
    res.KPITable = localAppendCompatTable(res.KPITable, newTable);
end
end

function res = localPrunePrimaryCasesWithoutEvidence(res, rawTrials)
if ~(isstruct(res) && isfield(res, "KPITable") && istable(res.KPITable) && ~isempty(res.KPITable))
    return;
end
specs = [ ...
    struct("Case", "CellSearch_MIB_SIB1", "Field", "PBCH"); ...
    struct("Case", "PRACH_Detection", "Field", "PRACH"); ...
    struct("Case", "DL_PDSCH_Throughput", "Field", "DL"); ...
    struct("Case", "UL_PUSCH_Throughput", "Field", "UL"); ...
    struct("Case", "UL_SRS_ChannelEst", "Field", "SRS")];
keep = true(height(res.KPITable), 1);
caseCol = string(res.KPITable.Case);
for i = 1:numel(specs)
    if ~localHasPrimaryEvidence(rawTrials, specs(i).Field)
        keep(strcmpi(caseCol, specs(i).Case)) = false;
    end
end
res.KPITable = res.KPITable(keep, :);
end

function tf = localHasPrimaryEvidence(rawTrials, fieldName)
tf = false;
if ~(isstruct(rawTrials) && isfield(rawTrials, char(fieldName)))
    return;
end
T = rawTrials.(char(fieldName));
if ~(istable(T) && ~isempty(T))
    return;
end
T = localEffectiveTrialRows(T);
if isempty(T)
    return;
end

n = height(T);
valueRole = repmat("", n, 1);
artifactClass = repmat("", n, 1);
runtimeConsumer = repmat("", n, 1);
if ismember("ValueRole", string(T.Properties.VariableNames))
    valueRole = strtrim(string(T.ValueRole));
end
if ismember("ArtifactClass", string(T.Properties.VariableNames))
    artifactClass = strtrim(string(T.ArtifactClass));
end
if ismember("RuntimeStateConsumer", string(T.Properties.VariableNames))
    runtimeConsumer = strtrim(string(T.RuntimeStateConsumer));
end

diagnosticOnlyMask = valueRole == "diagnostic_not_primary_runtime_evidence" | ...
    artifactClass == "diagnostic_control_reference_signal_sweep" | ...
    runtimeConsumer == "not_consumed_by_coupled_runtime";
tf = any(~diagnosticOnlyMask);
end

function res = localApplyMultiUserPrimaryResults(res, rawTrials, multiUser, cfg)
if ~(isstruct(res) && isfield(res, "KPITable") && istable(res.KPITable))
    return;
end
if isfield(rawTrials, "DL") && istable(rawTrials.DL)
    aggDL = localAggregatePrimaryLinkCase(rawTrials.DL, cfg, "multi_user_" + string(multiUser.ExecutionModel), unique(double(rawTrials.DL.SNR_dB)));
    res = localReplaceCaseResult(res, "DL_PDSCH_Throughput", aggDL);
end
if isfield(rawTrials, "UL") && istable(rawTrials.UL)
    aggUL = localAggregatePrimaryLinkCase(rawTrials.UL, cfg, "multi_user_" + string(multiUser.ExecutionModel), unique(double(rawTrials.UL.SNR_dB)));
    res = localReplaceCaseResult(res, "UL_PUSCH_Throughput", aggUL);
end
res.MultiUserMode = string(multiUser.ExecutionModel);
res.MultiUserEnabled = logical(multiUser.Enabled);
res.MultiUserCount = double(multiUser.NumUsers);
res.Ok = localLinkKPITableHealthy(res.KPITable);
end

function agg = localAggregatePrimaryLinkCase(T, cfg, label, snrGrid)
agg = struct();
agg.Ok = false;
agg.Skipped = isempty(T);
agg.BER = NaN;
agg.BLER = NaN;
agg.Throughput_Mbps = NaN;
agg.EVM_rms = NaN;
agg.NMSE_dB = NaN;
agg.Notes = "";
agg.TrialTable = T;
if isempty(T)
    return;
end
stats = localSummarizeLinkTrialTable(T, cfg);
status = upper(strtrim(string(stats.Table.Status)));
passMask = status == "PASS";
observedMask = passMask | status == "FAIL" | status == "CRASH";
bits = double(stats.Table.BitsCompared);
bits(~isfinite(bits)) = 0;
bitErr = double(stats.Table.BitErrors);
bitErr(~isfinite(bitErr)) = 0;
agg.BER = sum(bitErr) / max(sum(bits), 1);
agg.BLER = stats.BLER;
agg.Throughput_Mbps = stats.Throughput_Mbps;
agg.EVM_rms = stats.EVM_rms;
agg.Ok = any(passMask);
if ~any(observedMask)
    agg.Skipped = true;
end
agg.Notes = string(label) + "; operating_mode_authority=" + localPrimaryOperatingAuthority(cfg) + ...
    localMeasuredSINRRangeNoteFromTable(stats.Table) + ...
    "; steady_state_warmup_rows_excluded=true";
end

function agg = localAggregatePrimaryPassFailCase(T, label)
agg = struct();
agg.Ok = false;
agg.Skipped = isempty(T);
agg.BER = NaN;
agg.BLER = NaN;
agg.Throughput_Mbps = NaN;
agg.EVM_rms = NaN;
agg.NMSE_dB = NaN;
agg.Notes = "";
agg.TrialTable = T;
if isempty(T)
    return;
end
Te = localEffectiveTrialRows(T);
status = upper(strtrim(string(Te.Status)));
failMask = status == "FAIL" | status == "CRASH";
passMask = status == "PASS";
observedMask = passMask | failMask;
agg.BLER = sum(failMask) / max(height(Te), 1);
agg.Ok = any(passMask);
if ~any(observedMask)
    agg.Skipped = true;
end
agg.Notes = string(label) + localMeasuredSINRRangeNoteFromTable(Te);
end

function agg = localAggregatePrimarySRSCase(T, operatingAuthority)
agg = struct();
agg.Ok = false;
agg.Skipped = isempty(T);
agg.BER = NaN;
agg.BLER = NaN;
agg.Throughput_Mbps = NaN;
agg.EVM_rms = NaN;
agg.NMSE_dB = NaN;
agg.Notes = "";
agg.TrialTable = T;
if isempty(T)
    return;
end
Te = localEffectiveTrialRows(T);
qualification = sixgr.truth.summarizeSRSChannelQualification(Te);
agg.NMSE_dB = qualification.NMSE_dB;
% Match the sweep's at-least-one-qualified-point convention, not merely
% the presence of a numeric NMSE. Retain failed points and explicit counts.
agg.Ok = qualification.AnyQualifiedTrial;
agg.Notes = "SRS runtime-measured; operating_mode_authority=" + string(operatingAuthority) + ...
    "; nmse_source=srs_trials.NMSE_dB; nmse_aggregation=" + qualification.NMSEAggregation + ...
    "; measured_trials=" + qualification.MeasuredTrials + ...
    "; qualified_trials=" + qualification.QualifiedTrials + ...
    "; unqualified_trials=" + qualification.UnqualifiedTrials + ...
    "; all_trials_qualified=" + qualification.AllTrialsQualified + ...
    localMeasuredSINRRangeNoteFromTable(Te);
end

function agg = localAggregatePrimaryULPAPRCase(T, operatingAuthority)
agg = struct();
agg.Ok = false;
agg.Skipped = isempty(T);
agg.BER = NaN;
agg.BLER = NaN;
agg.Throughput_Mbps = NaN;
agg.EVM_rms = NaN;
agg.PAPR_CP_dB = NaN;
agg.PAPR_DFTs_dB = NaN;
agg.PAPR_Gain_dB = NaN;
agg.NMSE_dB = NaN;
agg.Notes = "";
agg.TrialTable = T;
if isempty(T)
    return;
end

Te = localEffectiveTrialRows(T);
papr = localFiniteColumn(Te, "PAPR_dB");
if isempty(papr)
    agg.Notes = "UL low-PAPR primary raw trial metric; papr_source=ul_pusch_trials.PAPR_dB_unavailable";
    return;
end

transformMask = false(height(Te), 1);
hasTransformFlag = ismember("TransformPrecodingApplied", string(Te.Properties.VariableNames));
if hasTransformFlag
    transformMask = logical(Te.TransformPrecodingApplied);
end

if hasTransformFlag && any(~transformMask)
    cpVals = double(Te.PAPR_dB(~transformMask));
    cpVals = cpVals(isfinite(cpVals));
else
    cpVals = papr;
end
if ~isempty(cpVals)
    agg.PAPR_CP_dB = mean(cpVals, "omitnan");
end

if hasTransformFlag && any(transformMask)
    dftsVals = double(Te.PAPR_dB(transformMask));
    dftsVals = dftsVals(isfinite(dftsVals));
    if ~isempty(dftsVals)
        agg.PAPR_DFTs_dB = mean(dftsVals, "omitnan");
    end
end
if isfinite(agg.PAPR_CP_dB) && isfinite(agg.PAPR_DFTs_dB)
    agg.PAPR_Gain_dB = agg.PAPR_CP_dB - agg.PAPR_DFTs_dB;
end

agg.Ok = true;
agg.Notes = "UL low-PAPR runtime-measured; operating_mode_authority=" + string(operatingAuthority) + ...
    "; papr_source=ul_pusch_trials.PAPR_dB" + ...
    localMeasuredSINRRangeNoteFromTable(Te);
if ~isfinite(agg.PAPR_DFTs_dB)
    agg.Notes = agg.Notes + "; dfts_comparison_unavailable_without_transform_precoding_trials";
end
end

function note = localMeasuredSINRRangeNoteFromTable(T)
note = "; measured_sinr_source=not_applicable_or_unavailable";
if ~istable(T) || isempty(T)
    return;
end
source = "";
sinr = [];
for candidate = ["PostEqSINR_dB", "MeasuredSINR_dB", "MeasuredTrialSINR_dB", "ReceiverHestSINR_dB"]
    vals = localFiniteColumn(T, candidate);
    if ~isempty(vals)
        source = candidate;
        sinr = vals;
        break;
    end
end
if isempty(sinr)
    return;
end
note = sprintf("; measured_sinr_source=%s; measured_sinr_range_db=[%.3g,%.3g]", ...
    char(source), min(sinr), max(sinr));
end

function stats = localSummarizeLinkTrialTable(T, cfg)
Te = localEffectiveTrialRows(T);
stats = struct( ...
    "Table", Te, ...
    "TrialCount", NaN, ...
    "FailureCount", NaN, ...
    "BER", NaN, ...
    "BER_CI_Low", NaN, ...
    "BER_CI_High", NaN, ...
    "BLER", NaN, ...
    "BLER_CI_Low", NaN, ...
    "BLER_CI_High", NaN, ...
    "Throughput_Mbps", NaN, ...
    "Throughput_CI_Low", NaN, ...
    "Throughput_CI_High", NaN, ...
    "OfferedThroughput_Mbps", NaN, ...
    "Goodput_Mbps", NaN, ...
    "CodeBlockBLER", NaN, ...
    "CBG_BLER", NaN, ...
    "EVM_rms", NaN, ...
    "DecodeLatency_ms", NaN, ...
    "DecoderComplexityUnits", NaN, ...
    "NormalizedDecoderComplexity", NaN);
if isempty(Te)
    return;
end
bits = double(Te.BitsCompared);
bits(~isfinite(bits)) = 0;
bitErr = double(Te.BitErrors);
bitErr(~isfinite(bitErr)) = 0;
status = upper(strtrim(string(Te.Status)));
failMask = status == "FAIL" | status == "CRASH";
stats.TrialCount = double(height(Te));
stats.FailureCount = double(sum(failMask));
goodBits = double(Te.GoodBits);
goodBits(~isfinite(goodBits)) = 0;
offeredBits = double(Te.OfferedBits);
offeredBits(~isfinite(offeredBits)) = 0;
stats.BER = sum(bitErr) / max(sum(bits), 1);
stats.BLER = sum(failMask) / max(height(Te), 1);
confidenceLevel = localConfiguredConfidenceLevel(cfg);
[stats.BER_CI_Low, stats.BER_CI_High] = localWilsonInterval( ...
    sum(bitErr),sum(bits),confidenceLevel);
[stats.BLER_CI_Low, stats.BLER_CI_High] = localWilsonInterval( ...
    sum(failMask),height(Te),confidenceLevel);
stats.Throughput_Mbps = localAggregateThroughputFromTrials(Te, cfg);
[stats.Throughput_CI_Low, stats.Throughput_CI_High] = ...
    localMeanConfidenceInterval(localTrialThroughputSamples(Te,cfg), ...
    confidenceLevel);
stats.OfferedThroughput_Mbps = localAggregateBitRateFromTrials(Te, cfg, "OfferedBits");
stats.Goodput_Mbps = localAggregateBitRateFromTrials(Te, cfg, "GoodBits");
stats.CodeBlockBLER = localRatioFromColumns(Te, "CodeBlockErrors", "CodeBlockCount");
stats.CBG_BLER = localRatioFromColumns(Te, "CBGErrors", "CBGCount");
stats.EVM_rms = localTableMean(Te, "EVM_rms");
stats.DecodeLatency_ms = localTableMean(Te, "DecodeLatency_ms");
stats.DecoderComplexityUnits = localTableMean(Te, "DecoderComplexityUnits");
stats.NormalizedDecoderComplexity = localTableMean(Te, "NormalizedDecoderComplexity");
end

function T = localEffectiveTrialRows(T)
if ~(istable(T) && ~isempty(T))
    T = table();
    return;
end
mask = true(height(T), 1);
if ismember("IsWarmupFrame", string(T.Properties.VariableNames))
    warmMask = logical(T.IsWarmupFrame);
    if any(~warmMask)
        mask = ~warmMask;
    end
end
T = T(mask, :);
end

function ratio = localRatioFromColumns(T, numVar, denVar)
ratio = NaN;
if ~(istable(T) && ~isempty(T) && all(ismember([numVar denVar], string(T.Properties.VariableNames))))
    return;
end
num = double(T.(numVar));
den = double(T.(denVar));
num(~isfinite(num)) = 0;
den(~isfinite(den)) = 0;
if sum(den) <= 0
    return;
end
ratio = sum(num) / sum(den);
end

function thr = localAggregateThroughputFromTrials(T, cfg)
thr = localAggregateBitRateFromTrials(T, cfg, "TBSize_bits");
end

function authority = localPrimaryOperatingAuthority(cfg)
noiseMode = lower(strtrim(string(sixgr.util.structGet(cfg, ...
    "run.noiseOperatingMode", ""))));
if noiseMode == "standalone_awgn_snr_argument"
    authority = "fixed_snr_sweep";
elseif noiseMode == "receiver_noise_figure_thermal_noise"
    authority = "geometry_link_budget";
elseif noiseMode == "absolute_reference_esn0"
    authority = "absolute_reference_esn0";
else
    error("sixgr:truth:UnknownOperatingModeAuthority", ...
        "run.noiseOperatingMode='%s' has no canonical LLS operating-mode authority.", ...
        noiseMode);
end
end

function samples = localTrialThroughputSamples(T, cfg)
samples = localTrialBitRateSamples(T, cfg, "TBSize_bits");
end

function thr = localAggregateBitRateFromTrials(T, cfg, bitVar, durationOverride_s)
if nargin < 4
    durationOverride_s = NaN;
end
thr = NaN;
if isempty(T)
    return;
end
samples = localTrialBitRateSamples(T, cfg, bitVar);
if isempty(samples)
    return;
end
if isfinite(durationOverride_s) && durationOverride_s > 0
    totalBits = localAggregateTrialBits(T, bitVar);
    if isfinite(totalBits)
        thr = double(totalBits) / double(durationOverride_s) / 1e6;
        return;
    end
end
thr = mean(samples, "omitnan");
end

function samples = localTrialBitRateSamples(T, cfg, bitVar)
samples = NaN(0, 1);
if isempty(T)
    return;
end
slotDurDefault_s = localSlotDuration(cfg);
if ~(isfinite(slotDurDefault_s) && slotDurDefault_s > 0)
    return;
end
bitValues = localResolvedTrialBits(T, bitVar);
if isempty(bitValues)
    return;
end
slotKeys = localTrialSlotKeys(T);
slotDurByRow_s = localTrialRowDurationsSeconds(T, slotDurDefault_s);
if numel(slotKeys) ~= numel(bitValues)
    slotKeys = strings(numel(bitValues), 1);
end
slotKeys = string(slotKeys(:));
if all(strlength(strtrim(slotKeys)) == 0)
    slotKeys = "row_" + string((1:numel(bitValues)).');
end
[uniqueKeys, ~, groupIdx] = unique(slotKeys, "stable");
if isempty(uniqueKeys)
    return;
end
bitSums = accumarray(groupIdx, bitValues, [numel(uniqueKeys) 1], @localNaNSumCompat, NaN);
slotDurByGroup_s = accumarray(groupIdx, slotDurByRow_s, [numel(uniqueKeys) 1], @(x) localRepresentativePositiveDuration(x, slotDurDefault_s), NaN);
samples = (bitSums ./ max(slotDurByGroup_s, eps)) / 1e6;
samples = samples(isfinite(samples));
end

function total = localNaNSumCompat(x)
x = double(x(:));
x = x(isfinite(x));
if isempty(x)
    total = 0;
    return;
end
total = sum(x);
end

function totalBits = localAggregateTrialBits(T, bitVar)
totalBits = NaN;
if isempty(T)
    return;
end
bitValues = localResolvedTrialBits(T, bitVar);
if isempty(bitValues)
    return;
end
totalBits = sum(bitValues, "omitnan");
end

function bitValues = localResolvedTrialBits(T, bitVar)
bitValues = NaN(0, 1);
if ~(istable(T) && ~isempty(T))
    return;
end
vars = string(T.Properties.VariableNames);
if nargin < 2 || strlength(string(bitVar)) == 0
    bitVar = "GoodBits";
end
bitVar = string(bitVar);
if ismember(bitVar, vars)
    bitValues = double(T.(bitVar));
    bitValues(~isfinite(bitValues)) = NaN;
else
    bitValues = NaN(height(T), 1);
end
if bitVar == "GoodBits" && all(~isfinite(bitValues))
    if ismember("TBSize_bits", vars)
        bitTotals = double(T.TBSize_bits);
        bitTotals(~isfinite(bitTotals)) = 0;
        passMask = false(height(T), 1);
        if ismember("Status", vars)
            passMask = upper(strtrim(string(T.Status))) == "PASS";
        elseif ismember("CRCPass", vars)
            passMask = logical(T.CRCPass);
        end
        goodBits = zeros(size(bitTotals));
        goodBits(passMask) = bitTotals(passMask);
        bitValues = goodBits;
    end
elseif bitVar == "OfferedBits" && all(~isfinite(bitValues)) && ismember("TBSize_bits", vars)
    bitTotals = double(T.TBSize_bits);
    bitTotals(~isfinite(bitTotals)) = NaN;
    bitValues = bitTotals;
end
end

function duration_s = localObservedTrialWindowSeconds(T, cfg)
duration_s = NaN;
if ~(istable(T) && ~isempty(T))
    return;
end
slotDurDefault_s = localSlotDuration(cfg);
if ~(isfinite(slotDurDefault_s) && slotDurDefault_s > 0)
    slotDurDefault_s = 0.5e-3;
end
slotKeys = localTrialSlotKeys(T);
slotKeys = string(slotKeys(:));
slotKeys = slotKeys(strlength(strtrim(slotKeys)) > 0);
if ~isempty(slotKeys)
    duration_s = double(numel(unique(slotKeys, "stable"))) * double(slotDurDefault_s);
    return;
end
slotDurByRow_s = localTrialRowDurationsSeconds(T, slotDurDefault_s);
validDur = slotDurByRow_s(isfinite(slotDurByRow_s) & slotDurByRow_s > 0);
if ~isempty(validDur)
    duration_s = sum(validDur, "omitnan");
end
end

function slotKeys = localTrialSlotKeys(T)
slotKeys = strings(0, 1);
if ~(istable(T) && ~isempty(T))
    return;
end
vars = string(T.Properties.VariableNames);
if all(ismember(["Frame","Slot"], vars))
    frameVals = double(T.Frame);
    slotVals = double(T.Slot);
    slotKeys = "frame_" + string(round(frameVals)) + "_slot_" + string(round(slotVals));
elseif all(ismember(["SFN","Slot"], vars))
    frameVals = double(T.SFN);
    slotVals = double(T.Slot);
    slotKeys = "sfn_" + string(round(frameVals)) + "_slot_" + string(round(slotVals));
elseif ismember("CanonicalSlot", vars)
    slotKeys = "canonical_slot_" + string(round(double(T.CanonicalSlot)));
elseif ismember("Slot", vars)
    slotKeys = "slot_" + string(round(double(T.Slot)));
else
    slotKeys = strings(height(T), 1);
end
invalidMask = strlength(strtrim(slotKeys)) == 0;
if any(invalidMask)
    slotKeys(invalidMask) = "";
end
end

function durations_s = localTrialRowDurationsSeconds(T, slotDurDefault_s)
durations_s = repmat(double(slotDurDefault_s), height(T), 1);
if ~(istable(T) && ~isempty(T) && ismember("AirInterfaceTTI_ms", string(T.Properties.VariableNames)))
    return;
end
tti_ms = double(T.AirInterfaceTTI_ms);
validMask = isfinite(tti_ms) & tti_ms > 0;
durations_s(validMask) = tti_ms(validMask) / 1000;
end

function duration_s = localRepresentativePositiveDuration(x, fallback_s)
duration_s = double(fallback_s);
x = double(x(:));
x = x(isfinite(x) & x > 0);
if ~isempty(x)
    duration_s = max(x);
end
if ~(isfinite(duration_s) && duration_s > 0)
    duration_s = double(fallback_s);
end
end

function [lo, hi] = localWilsonInterval(k,n,confidenceLevel)
lo = NaN;
hi = NaN;
n = double(n);
k = double(k);
if ~(isfinite(n) && n > 0 && isfinite(k) && k >= 0)
    return;
end
interval=sixgr.validation.BinomialIntervalEngine.wilson( ...
    k,n,confidenceLevel);
lo=interval.Lower;
hi=interval.Upper;
end

function [lo, hi] = localMeanConfidenceInterval(x,confidenceLevel)
lo = NaN;
hi = NaN;
x = double(x(:));
x = x(isfinite(x));
if isempty(x)
    return;
end
m = mean(x, "omitnan");
if numel(x) < 2
    lo = m;
    hi = m;
    return;
end
if ~(isnumeric(confidenceLevel)&&isscalar(confidenceLevel)&& ...
        isfinite(confidenceLevel)&&confidenceLevel>0&&confidenceLevel<1)
    error("sixgr:validation:InvalidConfidenceLevel", ...
        "Mean confidence interval requires an explicit confidence level.");
end
z=-sqrt(2)*erfcinv(2*((1+double(confidenceLevel))/2));
se = std(x, 0, "omitnan") / sqrt(numel(x));
lo = m - z * se;
hi = m + z * se;
end

function row = localEmptySweepSummaryRow(snr)
row = struct( ...
    "SNR_dB", double(snr), ...
    "CampaignKind", "raw_trial_summary", ...
    "SweepKind", "operating_point_summary", ...
    "FixedReferenceMode", false, ...
    "NoiseOperatingMode", "", ...
    "ConfidenceLevel", NaN, ...
    "SequentialMinTrials", NaN, ...
    "SequentialMaxTrials", NaN, ...
    "SequentialErrorTarget", NaN, ...
    "SequentialCIWidthTarget", NaN, ...
    "TrialsPerDrop", NaN, ...
    "PointIndex", NaN, ...
    "PointSeed", NaN, ...
    "DL_BER", NaN, "DL_BER_CI_Low", NaN, "DL_BER_CI_High", NaN, ...
    "DL_BLER", NaN, "DL_BLER_CI_Low", NaN, "DL_BLER_CI_High", NaN, "DL_TrialCount", NaN, "DL_FailureCount", NaN, ...
    "DL_BLER_CI_Method", "", "DL_BLER_CI_Width", NaN, "DL_BER_CI_Method", "", ...
    "DL_DropCount", NaN, "DL_BLER_ClusterCI_Low", NaN, "DL_BLER_ClusterCI_High", NaN, ...
    "DL_StopReason", "", "DL_Incomplete", false, "DL_TargetBLER", NaN, ...
    "DL_TargetCrossingStatus", "", "DL_TargetCrossingSNR_dB", NaN, ...
    "DL_Throughput_Mbps", NaN, "DL_Throughput_CI_Low", NaN, "DL_Throughput_CI_High", NaN, ...
    "DL_OfferedThroughput_Mbps", NaN, "DL_Goodput_Mbps", NaN, "DL_CodeBlockBLER", NaN, "DL_CBG_BLER", NaN, ...
    "DL_DecodeLatency_ms", NaN, "DL_DecoderComplexityUnits", NaN, "DL_NormalizedDecoderComplexity", NaN, ...
    "UL_BER", NaN, "UL_BER_CI_Low", NaN, "UL_BER_CI_High", NaN, ...
    "UL_BLER", NaN, "UL_BLER_CI_Low", NaN, "UL_BLER_CI_High", NaN, "UL_TrialCount", NaN, "UL_FailureCount", NaN, ...
    "UL_BLER_CI_Method", "", "UL_BLER_CI_Width", NaN, "UL_BER_CI_Method", "", ...
    "UL_DropCount", NaN, "UL_BLER_ClusterCI_Low", NaN, "UL_BLER_ClusterCI_High", NaN, ...
    "UL_StopReason", "", "UL_Incomplete", false, "UL_TargetBLER", NaN, ...
    "UL_TargetCrossingStatus", "", "UL_TargetCrossingSNR_dB", NaN, ...
    "UL_Throughput_Mbps", NaN, "UL_Throughput_CI_Low", NaN, "UL_Throughput_CI_High", NaN, ...
    "UL_OfferedThroughput_Mbps", NaN, "UL_Goodput_Mbps", NaN, "UL_CodeBlockBLER", NaN, "UL_CBG_BLER", NaN, ...
    "UL_DecodeLatency_ms", NaN, "UL_DecoderComplexityUnits", NaN, "UL_NormalizedDecoderComplexity", NaN, ...
    "SRS_NMSE_dB", NaN, "SRS_NMSE_CI_Low", NaN, "SRS_NMSE_CI_High", NaN, "SRS_TrialCount", NaN);
end

function row = localApplyLinkSweepStats(row, prefix, stats)
prefix = upper(string(prefix));
row.(char(prefix + "_BER")) = double(sixgr.util.structGet(stats, "BER", NaN));
row.(char(prefix + "_BER_CI_Low")) = double(sixgr.util.structGet(stats, "BER_CI_Low", NaN));
row.(char(prefix + "_BER_CI_High")) = double(sixgr.util.structGet(stats, "BER_CI_High", NaN));
row.(char(prefix + "_BLER")) = double(sixgr.util.structGet(stats, "BLER", NaN));
row.(char(prefix + "_BLER_CI_Low")) = double(sixgr.util.structGet(stats, "BLER_CI_Low", NaN));
row.(char(prefix + "_BLER_CI_High")) = double(sixgr.util.structGet(stats, "BLER_CI_High", NaN));
row.(char(prefix + "_TrialCount")) = double(sixgr.util.structGet(stats, "TrialCount", NaN));
row.(char(prefix + "_FailureCount")) = double(sixgr.util.structGet(stats, "FailureCount", NaN));
row.(char(prefix + "_Throughput_Mbps")) = double(sixgr.util.structGet(stats, "Throughput_Mbps", NaN));
row.(char(prefix + "_Throughput_CI_Low")) = double(sixgr.util.structGet(stats, "Throughput_CI_Low", NaN));
row.(char(prefix + "_Throughput_CI_High")) = double(sixgr.util.structGet(stats, "Throughput_CI_High", NaN));
row.(char(prefix + "_OfferedThroughput_Mbps")) = double(sixgr.util.structGet(stats, "OfferedThroughput_Mbps", NaN));
row.(char(prefix + "_Goodput_Mbps")) = double(sixgr.util.structGet(stats, "Goodput_Mbps", NaN));
row.(char(prefix + "_CodeBlockBLER")) = double(sixgr.util.structGet(stats, "CodeBlockBLER", NaN));
row.(char(prefix + "_CBG_BLER")) = double(sixgr.util.structGet(stats, "CBG_BLER", NaN));
row.(char(prefix + "_DecodeLatency_ms")) = double(sixgr.util.structGet(stats, "DecodeLatency_ms", NaN));
row.(char(prefix + "_DecoderComplexityUnits")) = double(sixgr.util.structGet(stats, "DecoderComplexityUnits", NaN));
row.(char(prefix + "_NormalizedDecoderComplexity")) = double(sixgr.util.structGet(stats, "NormalizedDecoderComplexity", NaN));
end

function vals = localTableUniqueFinite(rawTrials, fieldName, varName)
vals = [];
T = sixgr.util.structGet(rawTrials, fieldName, table());
if ~(istable(T) && ~isempty(T) && ismember(varName, string(T.Properties.VariableNames)))
    return;
end
x = double(T.(varName));
vals = unique(sort(x(isfinite(x))));
end

function T = localSubsetTrialsBySNR(T, snr)
if ~(istable(T) && ~isempty(T) && ismember("SNR_dB", string(T.Properties.VariableNames)))
    T = table();
    return;
end
mask = isfinite(double(T.SNR_dB)) & abs(double(T.SNR_dB) - double(snr)) < 1e-9;
T = T(mask, :);
end

function res = localReplaceCaseResult(res, caseName, agg)
fieldName = matlab.lang.makeValidName(char(caseName));
if isfield(res, "Cases")
    res.Cases.(fieldName) = agg;
end
if ~(isfield(res, "KPITable") && istable(res.KPITable) && ~isempty(res.KPITable))
    return;
end
mask = strcmpi(string(res.KPITable.Case), string(caseName));
if ~any(mask)
    return;
end
res.KPITable.Ok(mask) = logical(agg.Ok);
res.KPITable.Skipped(mask) = logical(sixgr.util.structGet(agg, "Skipped", false));
if ismember("BER", string(res.KPITable.Properties.VariableNames))
    res.KPITable.BER(mask) = double(sixgr.util.structGet(agg, "BER", NaN));
end
if ismember("BLER", string(res.KPITable.Properties.VariableNames))
    res.KPITable.BLER(mask) = double(sixgr.util.structGet(agg, "BLER", NaN));
end
if ismember("Throughput_Mbps", string(res.KPITable.Properties.VariableNames))
    res.KPITable.Throughput_Mbps(mask) = double(sixgr.util.structGet(agg, "Throughput_Mbps", NaN));
end
if ismember("EVM_rms", string(res.KPITable.Properties.VariableNames))
    res.KPITable.EVM_rms(mask) = double(sixgr.util.structGet(agg, "EVM_rms", NaN));
end
if ismember("PAPR_CP_dB", string(res.KPITable.Properties.VariableNames))
    res.KPITable.PAPR_CP_dB(mask) = double(sixgr.util.structGet(agg, "PAPR_CP_dB", NaN));
end
if ismember("PAPR_DFTs_dB", string(res.KPITable.Properties.VariableNames))
    res.KPITable.PAPR_DFTs_dB(mask) = double(sixgr.util.structGet(agg, "PAPR_DFTs_dB", NaN));
end
if ismember("PAPR_Gain_dB", string(res.KPITable.Properties.VariableNames))
    res.KPITable.PAPR_Gain_dB(mask) = double(sixgr.util.structGet(agg, "PAPR_Gain_dB", NaN));
end
if ismember("NMSE_dB", string(res.KPITable.Properties.VariableNames))
    res.KPITable.NMSE_dB(mask) = double(sixgr.util.structGet(agg, "NMSE_dB", NaN));
end
if ismember("Notes", string(res.KPITable.Properties.VariableNames))
    res.KPITable.Notes(mask) = string(sixgr.util.structGet(agg, "Notes", ""));
end
end

function nLayers = localConfiguredLayerCount(cfg, direction)
direction = upper(string(direction));
switch direction
    case "UL"
        nLayers = double(sixgr.util.structGet(cfg, "phy.pusch.nLayers", sixgr.util.structGet(cfg, "phy.pusch.numLayers", 1)));
    otherwise
        nLayers = double(sixgr.util.structGet(cfg, "phy.pdsch.nLayers", sixgr.util.structGet(cfg, "phy.pdsch.numLayers", 1)));
end
if ~(isscalar(nLayers) && isfinite(nLayers) && nLayers >= 1)
    nLayers = 1;
end
nLayers = max(1, round(nLayers));
end

function varargout = localConfiguredTxAntennaCount(varargin)
% Compatibility delegate; completion/publication has one production owner.
[varargout{1:nargout}] = sixgr.truth.SharedDataCompletionRuntime.configuredTxAntennaCount(varargin{:});
end

function varargout = localConfiguredRxAntennaCount(varargin)
% Compatibility delegate; completion/publication has one production owner.
[varargout{1:nargout}] = sixgr.truth.SharedDataCompletionRuntime.configuredRxAntennaCount(varargin{:});
end

function varargout = directionFromTable(varargin)
% Compatibility delegate; completion/publication has one production owner.
[varargout{1:nargout}] = sixgr.truth.SharedDataCompletionRuntime.directionFromTable(varargin{:});
end

function T = localSortTrialTableBySweep(T)
if ~(istable(T) && ~isempty(T))
    return;
end
sortVars = string.empty(0,1);
if ismember("SNR_dB", string(T.Properties.VariableNames))
    sortVars(end+1,1) = "SNR_dB"; %#ok<AGROW>
end
if ismember("Frame", string(T.Properties.VariableNames))
    sortVars(end+1,1) = "Frame"; %#ok<AGROW>
end
if isempty(sortVars)
    return;
end
T = sortrows(T, cellstr(sortVars));
end

function v = localTableMean(T, varName)
v = NaN;
if ~(istable(T) && ~isempty(T) && ismember(varName, string(T.Properties.VariableNames)))
    return;
end
x = double(T.(varName));
x = x(isfinite(x));
if isempty(x)
    return;
end
v = mean(x, "omitnan");
end

function tf = localLinkKPITableHealthy(kpi)
tf = false;
if ~(istable(kpi) && ~isempty(kpi))
    return;
end
if ~all(ismember(["Ok","Skipped"], string(kpi.Properties.VariableNames)))
    return;
end
tf = all(logical(kpi.Ok) & ~logical(kpi.Skipped));
end

function g = localReduceSweepGrid(gridIn, maxPts, anchorSNR)
g = unique(double(gridIn(:)), "sorted");
if isempty(g)
    g = double(anchorSNR);
    return;
end
maxPts = max(3, round(double(maxPts)));
if numel(g) <= maxPts
    return;
end
anchorIdx = find(g <= anchorSNR, 1, "last");
if isempty(anchorIdx)
    anchorIdx = 1;
end
keep = unique([1; anchorIdx; numel(g)]);
if numel(keep) < maxPts
    need = maxPts - numel(keep);
    rem = setdiff((1:numel(g)).', keep(:), "stable");
    if ~isempty(rem)
        pickIdx = round(linspace(1, numel(rem), min(need, numel(rem))));
        keep = unique([keep(:); rem(pickIdx(:))], "stable");
    end
end
g = g(sort(keep));
end

function plan = localResolveSweepPlan(opt, numFrames)
if nargin < 1 || ~isstruct(opt)
    opt = struct();
end
baseTrials = max(1, round(double(numFrames)));
plan = struct();
defaultPrimaryTrials = baseTrials;
explicitTrials = round(double(sixgr.util.structGet(opt, "LinkSweepTrialsPerSNR", NaN)));
legacyIterations = round(double(sixgr.util.structGet(opt, "LinkSweepFrames", NaN)));
if isfinite(explicitTrials) && explicitTrials >= 1
    requestedPrimaryTrials = explicitTrials;
elseif isfinite(legacyIterations) && legacyIterations >= 1
    requestedPrimaryTrials = baseTrials * legacyIterations;
else
    requestedPrimaryTrials = defaultPrimaryTrials;
end
plan.PrimaryTrialsPerSNR = max(1, requestedPrimaryTrials);

defaultReferenceTrials = plan.PrimaryTrialsPerSNR;
requestedReferenceTrials = round(double(sixgr.util.structGet(opt, "LinkReferenceSweepFrames", NaN)));
if ~(isfinite(requestedReferenceTrials) && requestedReferenceTrials >= 1)
    requestedReferenceTrials = defaultReferenceTrials;
end
plan.ReferenceTrialsPerSNR = max(1, requestedReferenceTrials);
plan.MaxSweepPoints = max(3, round(double(sixgr.util.structGet(opt, "LinkSweepMaxPoints", 7))));
plan.ReferenceSweepStep_dB = max(1, double(sixgr.util.structGet(opt, "LinkReferenceSweepStep_dB", 5)));
plan.ReferenceSweepMargin_dB = max(plan.ReferenceSweepStep_dB * 3, double(sixgr.util.structGet(opt, "LinkReferenceSweepMargin_dB", 24)));
plan.ReferenceMaxSweepPoints = max(plan.MaxSweepPoints + 1, round(double(sixgr.util.structGet(opt, "LinkReferenceSweepMaxPoints", 8))));
plan.FixedLinkCampaignEnabled = logical(sixgr.util.structGet(opt, "LinkFixedLinkCampaignEnabled", false));
plan.FixedLinkCampaignConfig = sixgr.util.structGet(opt, "LinkFixedLinkCampaignConfig", struct());
plan.FixedLinkSNRGrid_dB = double(sixgr.util.structGet(opt, "LinkFixedLinkSNRGrid_dB", []));
plan.FixedLinkMinTrials = max(1, round(double(sixgr.util.structGet(opt, "LinkFixedLinkMinTrials", plan.ReferenceTrialsPerSNR))));
plan.FixedLinkMaxTrials = max(plan.FixedLinkMinTrials, round(double(sixgr.util.structGet(opt, "LinkFixedLinkMaxTrials", plan.ReferenceTrialsPerSNR))));
plan.FixedLinkTrialsPerDrop = max(1, round(double(sixgr.util.structGet(opt, "LinkFixedLinkTrialsPerDrop", min(plan.FixedLinkMaxTrials, baseTrials)))));
plan.FixedLinkErrorTarget = max(1, round(double(sixgr.util.structGet(opt, "LinkFixedLinkErrorTarget", inf))));
plan.FixedLinkCIWidthTarget = double(sixgr.util.structGet(opt, "LinkFixedLinkCIWidthTarget", inf));
if ~(isfinite(plan.FixedLinkCIWidthTarget) && plan.FixedLinkCIWidthTarget >= 0)
    plan.FixedLinkCIWidthTarget = inf;
end
defaultConfidenceLevel=localConfiguredConfidenceLevel(struct());
plan.FixedLinkConfidenceLevel = double(sixgr.util.structGet(opt, ...
    "LinkFixedLinkConfidenceLevel",defaultConfidenceLevel));
if ~(isfinite(plan.FixedLinkConfidenceLevel) && plan.FixedLinkConfidenceLevel > 0 && plan.FixedLinkConfidenceLevel < 1)
    plan.FixedLinkConfidenceLevel = defaultConfidenceLevel;
end
plan.FixedLinkSeed = double(sixgr.util.structGet(opt, "LinkFixedLinkSeed", 730001));
if ~(isfinite(plan.FixedLinkSeed) && plan.FixedLinkSeed >= 0)
    plan.FixedLinkSeed = 730001;
end
plan.FixedLinkTargetBLER = double(sixgr.util.structGet(opt, "LinkFixedLinkTargetBLER", 0.10));
if ~(isfinite(plan.FixedLinkTargetBLER) && plan.FixedLinkTargetBLER > 0 && plan.FixedLinkTargetBLER < 1)
    plan.FixedLinkTargetBLER = 0.10;
end
plan.FixedLinkMaxTargetCrossingBracket_dB = double(sixgr.util.structGet( ...
    opt, "LinkFixedLinkMaxTargetCrossingBracket_dB", 2));
if ~(isfinite(plan.FixedLinkMaxTargetCrossingBracket_dB) && ...
        plan.FixedLinkMaxTargetCrossingBracket_dB > 0)
    plan.FixedLinkMaxTargetCrossingBracket_dB = 2;
end
end

function grid = localBuildAdaptiveRefinedGrid(sweepT, anchorGrid, cfg, opt)
grid = [];
if ~(istable(sweepT) && ~isempty(sweepT) && ismember("SNR_dB", string(sweepT.Properties.VariableNames)))
    return;
end
if ~logical(sixgr.util.structGet(opt, "LinkAdaptiveSweepEnabled", false))
    return;
end
step = max(eps, double(sixgr.util.structGet(opt, "LinkAdaptiveSweepStep_dB", 1)));
maxExtra = max(0, round(double(sixgr.util.structGet(opt, "LinkAdaptiveSweepMaxPoints", 0))));
if maxExtra == 0
    return;
end

anchorGrid = unique(sort(double(anchorGrid(:))));
if numel(anchorGrid) < 2
    return;
end

for prefix = ["DL","UL"]
    grid = [grid; localBuildDirectionAdaptiveGrid(sweepT, prefix, step)]; %#ok<AGROW>
end
grid = unique(sort(double(grid(:))));
grid = setdiff(grid, anchorGrid, "stable");
if isempty(grid)
    return;
end
if numel(grid) > maxExtra
    pick = round(linspace(1, numel(grid), maxExtra));
    grid = unique(grid(pick(:)), "stable");
end
end

function tf = localShouldAdaptiveRefineTruthSweep(cfg)
tf = logical(sixgr.util.structGet(cfg, "run.strictMode", false)) || ...
    logical(sixgr.util.structGet(cfg, "run.noProxyTruthContract", false));
end

function grid = localBuildDirectionAdaptiveGrid(sweepT, prefix, step)
grid = [];
prefix = upper(string(prefix));
blCol = prefix + "_BLER";
thrCol = prefix + "_Throughput_Mbps";
if ~(all(ismember(["SNR_dB", blCol, thrCol], string(sweepT.Properties.VariableNames))))
    return;
end
x = double(sweepT.SNR_dB);
bler = double(sweepT.(blCol));
thr = double(sweepT.(thrCol));
[x, order] = sort(x(:));
bler = bler(order);
thr = thr(order);
finiteThr = double(thr(isfinite(thr)));
if isempty(finiteThr)
    maxThr = NaN;
else
    maxThr = max(finiteThr(:));
end
for i = 1:max(numel(x) - 1, 0)
    x1 = x(i);
    x2 = x(i + 1);
    if ~(isfinite(x1) && isfinite(x2) && x2 - x1 > step)
        continue;
    end
    b1 = bler(i);
    b2 = bler(i + 1);
    t1 = thr(i);
    t2 = thr(i + 1);
    largeBLERJump = all(isfinite([b1 b2])) && (abs(b2 - b1) >= 0.5 || (b1 >= 0.9 && b2 <= 0.1) || (b2 >= 0.9 && b1 <= 0.1));
    largeThrJump = isfinite(maxThr) && maxThr > 0 && all(isfinite([t1 t2])) && abs(t2 - t1) >= 0.25 * maxThr;
    if ~(largeBLERJump || largeThrJump)
        continue;
    end
    grid = [grid; (x1 + step:step:x2 - step).']; %#ok<AGROW>
end
end

function grid = localBuildReferenceSweepGrid(snrGrid, sweepPlan)
grid = unique(sort(double(snrGrid(:))));
if isempty(grid)
    return;
end
step = double(sweepPlan.ReferenceSweepStep_dB);
margin = double(sweepPlan.ReferenceSweepMargin_dB);
lo = min(grid) - margin;
hi = max(grid);
dense = (lo:step:hi).';
grid = unique(sort([grid; dense]));
grid = localReduceSweepGrid(grid, double(sweepPlan.ReferenceMaxSweepPoints), max(double(snrGrid(:))));
end

function varargout = localSlotDuration(varargin)
% Compatibility delegate; the implementation and schema have one owner.
[varargout{1:nargout}] = sixgr.truth.PDCCHControlRuntime.slotDuration(varargin{:});
end

function [y, nVar] = localAddAwgn(x, snr_dB)
[y, nVar] = sixgr.util.addAwgnComplex(x, snr_dB);
end

function varargout = localBitErrors(varargin)
% Compatibility delegate; the implementation and schema have one owner.
[varargout{1:nargout}] = sixgr.truth.PDCCHControlRuntime.bitErrors(varargin{:});
end

function artifacts = localExportBeamformingDiagnostics(cfg, airInterfaceRunFolder, rawTrials, saveFigures)
artifacts = struct("CSV", "", "SummaryCSV", "", "TraceCSV", "", "StateTraceCSV", "", "EventTraceCSV", "", ...
    "Images", {{}}, "Table", table(), "SummaryTable", table(), "TraceTable", table(), ...
    "StateTraceTable", table(), "EventTraceTable", table());

rootRunFolder = fileparts(char(string(airInterfaceRunFolder)));
layout = sixgr.report.resultLayout(rootRunFolder);
sixgr.util.ensureFolder(layout.BeamformingCSVDir);
sixgr.util.ensureFolder(layout.BeamformingImageDir);

T = localBuildBeamformingTable(cfg, rawTrials);
if isempty(T)
    return;
end

csvPath = fullfile(layout.BeamformingCSVDir, "probe_beam_mimo.csv");
sixgr.util.csvWriteTable(csvPath, T);
artifacts.CSV = csvPath;
artifacts.Table = T;

summaryT = localBuildBeamManagementSummaryTable(T, cfg);
if ~isempty(summaryT)
    summaryT = sixgr.truth.finalizeProbeMetricTable(summaryT);
    summaryPath = fullfile(layout.BeamformingCSVDir, "probe_beam_management.csv");
    sixgr.util.csvWriteTable(summaryPath, summaryT);
    artifacts.SummaryCSV = summaryPath;
    artifacts.SummaryTable = summaryT;
end

traceT = localBuildBeamScoreTraceTable(T, cfg);
if ~isempty(traceT)
    tracePath = fullfile(layout.BeamformingCSVDir, "beam_score_trace.csv");
    sixgr.util.csvWriteTable(tracePath, traceT);
    artifacts.TraceCSV = tracePath;
    artifacts.TraceTable = traceT;
end

[stateTraceT, eventTraceT] = localBuildBeamManagementRuntimeTraceTables(T, cfg);
if ~isempty(stateTraceT)
    statePath = fullfile(layout.BeamformingCSVDir, "beam_management_state_trace.csv");
    % The coupled runtime owns the causal P1/P2/decoded-TCI state trace.
    % Preserve it when present; a post-hoc table derived from data trials
    % must not overwrite receiver/control evidence with reconstructed rows.
    if exist(statePath, "file") == 2
        stateTraceT = sixgr.util.csvReadTable(statePath);
    else
        sixgr.util.csvWriteTable(statePath, stateTraceT);
    end
    artifacts.StateTraceCSV = statePath;
    artifacts.StateTraceTable = stateTraceT;
end
if ~isempty(eventTraceT)
    eventPath = fullfile(layout.BeamformingCSVDir, "beam_management_event_trace.csv");
    sixgr.util.csvWriteTable(eventPath, eventTraceT);
    artifacts.EventTraceCSV = eventPath;
    artifacts.EventTraceTable = eventTraceT;
end

if ~saveFigures
    return;
end

img1 = fullfile(layout.BeamformingImageDir, "beam_channel_sinr.png");
localWriteGroupedMetricPlot(T, "PostEqSINR_dB", img1, "Post-Eq SINR by Trial", "Post-equalization SINR (dB)");
if exist(img1, "file") == 2
    artifacts.Images{end+1} = img1;
end

img2 = fullfile(layout.BeamformingImageDir, "beam_condition_number.png");
localWriteGroupedMetricPlot(T, "ConditionNumber_dB", img2, "Channel Condition Number by Trial", "Condition Number (dB)");
if exist(img2, "file") == 2
    artifacts.Images{end+1} = img2;
end

img3 = fullfile(layout.BeamformingImageDir, "beam_gain_gap.png");
localWriteGroupedMetricPlot(T, "BeamGainGap_dB", img3, "Beam Gain Gap by Trial", "Gain gap (dB)");
if exist(img3, "file") == 2
    artifacts.Images{end+1} = img3;
end
beamImages = [string(img1); string(img2); string(img3)];
beamIds = ["beam_channel_sinr"; "beam_condition_number"; "beam_gain_gap"];
beamSources = repmat(string(csvPath), 3, 1);
existsMask = arrayfun(@(x) exist(char(x), "file") == 2, beamImages);
if any(existsMask)
    lineagePath = fullfile(layout.BeamformingCSVDir, "beamforming_plot_lineage.csv");
    sixgr.visual.writeComponentPlotLineage(rootRunFolder, lineagePath, ...
        beamIds(existsMask), beamImages(existsMask), beamSources(existsMask), ...
        "sixgr.truth.runWaveformLinkBundle.localExportBeamformingDiagnostics");
end
end

function T = localBuildBeamformingTable(cfg, rawTrials)
T = table();
beamSweepEnabled = logical(sixgr.util.structGet(cfg, "phy.beamManagement.enabled", false));
beamCount = double(sixgr.util.structGet(cfg, "phy.beamManagement.beamCount", NaN));
tables = {};
if isstruct(rawTrials)
    if isfield(rawTrials, "DL")
        Tdl = localResolveTrialTable(rawTrials.DL);
        if istable(Tdl) && ~isempty(Tdl)
            tables{end+1} = Tdl; %#ok<AGROW>
        end
    end
    if isfield(rawTrials, "UL")
        Tul = localResolveTrialTable(rawTrials.UL);
        if istable(Tul) && ~isempty(Tul)
            tables{end+1} = Tul; %#ok<AGROW>
        end
    end
end
if isempty(tables)
    return;
end

keepVars = ["RunID","ExecutionID","UEIndex","RNTI","ServingCell","CellID","Direction","SNR_dB","Frame","Slot","RuntimeAbsoluteSlotIndex0","CarrierNSlot","CarrierNFrame","MCS","PRBs","Layers", ...
    "ConfiguredLayers","ConfiguredTxAntennas","ConfiguredRxAntennas", ...
    "PostEqSINR_dB","ReceiverHestSINR_dB","WidebandCQI","RankIndicator","PMI","ChannelGain_dB","ConditionNumber_dB", ...
    "RankEstimate","NumRxAntennas","NumTxPorts","SelectedBeamIndex","BestBeamIndex", ...
    "BeamHit","TopKBeamHit","BeamCandidateCount","SelectedBeamGain_dB","BestBeamGain_dB","BeamGainGap_dB", ...
    "BeamSelectionStrategy","BeamIndexSet","ConfiguredBeamSelectionStrategy","AppliedBeamIndexSet", ...
    "PrecoderSource","PrecodingMode","PrecodingApplicationStage","PrecodingActive","ExplicitBeamWeightsApplied","TransformPrecodingApplied","BeamformingApplied", ...
    "AppliedPrecoderPMI","AppliedPrecoderPMIType","AppliedPrecoderCodebookMode","PrecodingNumPorts","PrecodingNumLayers","PrecodingMatrixRows","PrecodingMatrixCols", ...
    "AppliedPrecoderPMIBasis","EquivalentPDSCHPortBasisCodebookIndex","AppliedCSIResourceIndex", ...
    "QCLStatus","QCLType","QCLSourceRS","QCLSourceResourceID","QCLSourceSlot0", ...
    "QCLSourceAvailableAtSample","TCIStateID","TCICodepoint","TCIStatus","TCIInitializationSource", ...
    "QCLTimingPriorUsed","QCLTimingPriorSamples","QCLDMRSDelayResidual_samples","QCLMeasurementStatus", ...
    "PMICodebookMatrixCSIPortsSHA256","CSIRSPortToElementMatrixSHA256","ComposedElementMatrixSHA256", ...
    "RequestedPrecoderPMI","RequestedPrecoderSHA256","AppliedPrecoderSHA256","PrecoderDigestDomain", ...
    "ExecutionModel","Status"];

chunks = cell(numel(tables), 1);
for i = 1:numel(tables)
    Ti = tables{i};
    if ~all(ismember(["PostEqSINR_dB","ConditionNumber_dB","ChannelGain_dB"], string(Ti.Properties.VariableNames)))
        continue;
    end
    hasMetrics = isfinite(double(Ti.PostEqSINR_dB)) | isfinite(double(Ti.ConditionNumber_dB)) | isfinite(double(Ti.ChannelGain_dB));
    Ti = Ti(hasMetrics, :);
    if isempty(Ti)
        continue;
    end
    Ti = Ti(:, keepVars(ismember(keepVars, string(Ti.Properties.VariableNames))));
    for beamSetVar = ["BeamIndexSet","AppliedBeamIndexSet"]
        if ismember(beamSetVar, string(Ti.Properties.VariableNames))
            Ti.(char(beamSetVar)) = localBeamIndexSetStringColumn( ...
                Ti.(char(beamSetVar)), height(Ti));
        end
    end
    if ~ismember("BeamIndexSet", string(Ti.Properties.VariableNames))
        appliedBeamSet = strings(height(Ti), 1);
        if ismember("AppliedBeamIndexSet", string(Ti.Properties.VariableNames))
            appliedBeamSet = string(Ti.AppliedBeamIndexSet);
        end
        Ti.BeamIndexSet = appliedBeamSet;
    end
    Ti.BeamSweepEnabled = repmat(beamSweepEnabled, height(Ti), 1);
    Ti.BeamCount = repmat(beamCount, height(Ti), 1);
    chunks{i} = Ti;
end

chunks = chunks(~cellfun(@isempty, chunks));
if isempty(chunks)
    return;
end
for i = 1:numel(chunks)
    T = localAppendCompatTable(T, chunks{i});
end
end

function out = localBeamIndexSetStringColumn(value, nRows)
% Persist one canonical scalar text token per trial regardless of whether
% the producer used a scalar, row vector, string, or cell-wrapped set.
out = strings(nRows, 1);
if nRows < 1 || isempty(value)
    return;
end
if iscell(value)
    for row = 1:min(nRows, numel(value))
        item = value{row};
        if iscell(item) && isscalar(item)
            item = item{1};
        end
        out(row) = sixgr.truth.GrantPreparation.formatIndexSet(item);
    end
    return;
end
if ischar(value) || isstring(value) || iscategorical(value)
    token = string(value);
    token = token(:);
    out(1:min(nRows, numel(token))) = token(1:min(nRows, numel(token)));
    return;
end
if isnumeric(value) || islogical(value)
    if isvector(value) && nRows == numel(value)
        out = string(value(:));
    elseif size(value, 1) == nRows
        for row = 1:nRows
            out(row) = sixgr.truth.GrantPreparation.formatIndexSet(value(row, :));
        end
    else
        out(:) = sixgr.truth.GrantPreparation.formatIndexSet(value);
    end
    return;
end
error("sixgr:truth:UnsupportedBeamIndexSetColumnType", ...
    "Beam index set columns must be numeric, logical, text, categorical, or cell-wrapped values; received %s.", ...
    class(value));
end

function summaryT = localBuildBeamManagementSummaryTable(T, cfg)
summaryT = localEmptyProbeMetricTable();
if ~(istable(T) && ~isempty(T))
    return;
end
[stateTraceT, eventTraceT] = localBuildBeamManagementRuntimeTraceTables(T, cfg);
if isempty(stateTraceT)
    return;
end

dirs = localUniqueDirections(stateTraceT);
numTRPs = max(1, round(double(sixgr.util.structGet(cfg, "scenario.nTRP", ...
    sixgr.util.structGet(cfg, "deployment_topology.num_trps", 1)))));
for i = 1:numel(dirs)
    dirMask = string(stateTraceT.Direction) == dirs(i);
    stateDirT = stateTraceT(dirMask, :);
    eventDirT = eventTraceT(string(eventTraceT.Direction) == dirs(i), :);
    if isempty(stateDirT)
        continue;
    end

    beamDetected = localFiniteColumn(stateDirT, "BeamDetectedFlag");
    beamHit = localFiniteColumn(stateDirT, "BeamHit");
    topKHit = localFiniteColumn(stateDirT, "TopKBeamHit");
    beamGap = localFiniteColumn(stateDirT, "BeamGainGap_dB");
    beamCount = localFiniteColumn(stateDirT, "BeamCandidateCount");
    detectionRate = mean(beamDetected, "omitnan");
    hitRate = mean(beamHit, "omitnan");
    topKRate = mean(topKHit, "omitnan");
    misalignmentRate = mean(double(beamHit < 0.5), "omitnan");
    failureThreshold_dB = double(sixgr.util.structGet(cfg, ...
        "channel.awgnBeamFailureDetectionThreshold_dB", 3));
    failureRate = mean(double(beamGap > failureThreshold_dB), "omitnan");
    overhead = mean(beamCount, "omitnan");

    recoveryEnabled = logical(sixgr.util.structGet(cfg, ...
        "channel.awgnBeamFailureRecoveryEnabled", false));
    recoveryLatency = localFiniteColumn( ...
        eventDirT(eventDirT.RecoveryEventFlag > 0, :), "RecoveryLatency_s");
    failureIds = localFiniteColumn(eventDirT,"FailureEventID");
    failureIds = unique(failureIds(isfinite(failureIds)));
    recoveredIds = localFiniteColumn( ...
        eventDirT(eventDirT.RecoveryEventFlag > 0,:),"FailureEventID");
    recoveredIds = unique(recoveredIds(isfinite(recoveredIds)));
    recoveryFailureProbability = NaN;
    recoveryFailureAvailability = "not_available";
    if ~isempty(failureIds)
        recoveryFailureProbability = 1-numel(intersect(failureIds,recoveredIds))/numel(failureIds);
        recoveryFailureAvailability = "observed";
    end
    if ~recoveryEnabled
        recoveryAvailability = "disabled";
        recoveryValue = NaN;
        recoveryNote = "No physical beam-failure/recovery episode is configured.";
    elseif isempty(recoveryLatency)
        recoveryAvailability = "not_available";
        recoveryValue = NaN;
        recoveryNote = "A physical beam-failure episode is configured, but no measured failure-to-restored-service event completed in this direction.";
    else
        recoveryAvailability = "observed";
        recoveryValue = mean(recoveryLatency,"omitnan");
        recoveryNote = "Measured from an observed beam-gain failure trigger to the first subsequent detected successful beam hit; no configured slot duration is reported as an observation.";
    end

    switchingEnabled = logical(sixgr.util.structGet(cfg, ...
        "lls6g.mimo_and_beam_management.beam_switching", ...
        sixgr.util.structGet(cfg, "mimo_and_beam_management.beam_switching", false)));
    switchLatency = localFiniteColumn(eventDirT(eventDirT.SwitchEventFlag > 0, :), "SwitchLatency_s");
    if ~switchingEnabled
        switchAvailability = "disabled";
        switchValue = NaN;
        switchNote = "Beam switching is disabled by the resolved scenario configuration.";
    elseif isempty(switchLatency)
        switchAvailability = "not_available";
        switchValue = NaN;
        switchNote = "Beam switching is enabled, but no runtime switch event was observed for this direction.";
    else
        switchAvailability = "observed";
        switchValue = mean(switchLatency, "omitnan");
        switchNote = "Measured from explicit runtime beam-switch events in the beam-management event trace.";
    end

    refinementEnabled = logical(sixgr.util.structGet(cfg, ...
        "lls6g.mimo_and_beam_management.beam_refinement", ...
        sixgr.util.structGet(cfg, "mimo_and_beam_management.beam_refinement", false)));
    firstHitTrials = localFiniteColumn(eventDirT(eventDirT.FirstHitEventFlag > 0, :), "TrialsToFirstHit");
    if ~refinementEnabled
        refinementAvailability = "disabled";
        refinementValue = NaN;
        refinementNote = "Beam refinement is disabled by the resolved scenario configuration.";
    elseif isempty(firstHitTrials)
        refinementAvailability = "not_available";
        refinementValue = NaN;
        refinementNote = "Beam refinement is enabled, but no runtime convergence event was observed for this direction.";
    else
        refinementAvailability = "observed";
        refinementValue = mean(firstHitTrials, "omitnan");
        refinementNote = "Measured trials-to-first-hit from the runtime beam-management event trace.";
    end

    if numTRPs <= 1
        mtrpAvailability = "disabled";
        mtrpGain = NaN;
        mtrpNote = "Single-TRP runtime; mTRP beam-selection gain is not enabled for this scenario.";
    else
        mtrpAvailability = "observed";
        mtrpGain = mean(max(beamGap, 0), "omitnan");
        mtrpNote = "Measured selected-vs-best beam gain delta from runtime multi-TRP beam traces.";
    end

    summaryT = [summaryT; ... %#ok<AGROW>
        localProbeMetricRow("beam_detection_probability", dirs(i), "rate", detectionRate, "", "fraction", ...
            "Measured from runtime beam-detection states in the beam-management trace.", "observed"); ...
        localProbeMetricRow("beam_index_hit_rate", dirs(i), "rate", hitRate, "", "fraction", ...
            "Selected beam matches the best measured beam in the runtime beam-management trace.", "observed"); ...
        localProbeMetricRow("top_k_beam_hit_rate", dirs(i), "top2_rate", topKRate, "", "fraction", ...
            "Selected beam lies within the top-2 measured beam set in the runtime beam-management trace.", "observed"); ...
        localProbeMetricRow("beam_switch_latency", dirs(i), "mean_between_switches", switchValue, "", "s", switchNote, switchAvailability); ...
        localProbeMetricRow("beam_misalignment_probability", dirs(i), "rate", misalignmentRate, "", "fraction", ...
            "Measured from runtime trials where the selected beam differs from the best measured beam.", "observed"); ...
        localProbeMetricRow("beam_prediction_accuracy", dirs(i), "rate", hitRate, "", "fraction", ...
            "Measured selected-beam accuracy under the active runtime beam-selection strategy.", "observed"); ...
        localProbeMetricRow("beam_refinement_convergence", dirs(i), "mean_trials_to_first_hit", refinementValue, "", "trials", ...
            refinementNote, refinementAvailability); ...
        localProbeMetricRow("beam_failure_rate", dirs(i), "rate", failureRate, "", "fraction", ...
            "Measured from runtime trials whose beam gain gap exceeds the configured " + string(failureThreshold_dB) + " dB threshold.", "observed"); ...
        localProbeMetricRow("beam_recovery_time", dirs(i), "mean_completed_event", recoveryValue, "", "s", ...
            recoveryNote, recoveryAvailability); ...
        localProbeMetricRow("beam_recovery_failure_probability", dirs(i), "right_censored_event_rate", recoveryFailureProbability, "", "fraction", ...
            "Failure events without an observed restored-service completion before the execution boundary are counted as right-censored failures; they are not assigned a synthetic latency.", recoveryFailureAvailability); ...
        localProbeMetricRow("mtrp_beam_selection_gain", dirs(i), "delta_dB", mtrpGain, "", "dB", mtrpNote, mtrpAvailability); ...
        localProbeMetricRow("beam_management_overhead", dirs(i), "mean_beams_evaluated", overhead, "", "beams", ...
            "Average candidate-beam count evaluated per runtime beam-management sample.", "observed")];
end
end

function [stateT, eventT] = localBuildBeamManagementRuntimeTraceTables(T, cfg)
stateT = table();
eventT = table();
if ~(istable(T) && ~isempty(T))
    return;
end

sortVars = intersect(["Direction","SNR_dB","UEIndex","RNTI","Frame","Slot"], string(T.Properties.VariableNames), "stable");
if ~isempty(sortVars)
    T = sortrows(T, cellstr(sortVars));
end

groupVars = intersect(["Direction","SNR_dB","UEIndex","RNTI"], string(T.Properties.VariableNames), "stable");
if isempty(groupVars)
    groupKey = repmat("group_1", height(T), 1);
else
    groupKey = strings(height(T), 1);
    for idx = 1:numel(groupVars)
        groupKey = groupKey + "|" + localTableColumnAsString(T, groupVars(idx));
    end
end

slotDur_s = localSlotDuration(cfg);
slotsPerFrame = localSlotsPerFrame(cfg);
uniqueKeys = unique(groupKey, "stable");
stateChunks = cell(numel(uniqueKeys), 1);
eventChunks = cell(numel(uniqueKeys), 1);
beamSweepEnabled = logical(sixgr.util.structGet(cfg, "phy.beamManagement.enabled", false));
beamCountConfigured = double(sixgr.util.structGet(cfg, "phy.beamManagement.beamCount", NaN));

for idx = 1:numel(uniqueKeys)
    Ti = T(groupKey == uniqueKeys(idx), :);
    if isempty(Ti)
        continue;
    end

    n = height(Ti);
    selectedBeam = localFiniteOrNaNColumn(Ti, "SelectedBeamIndex");
    bestBeam = localFiniteOrNaNColumn(Ti, "BestBeamIndex");
    beamHit = localBackfillBeamHit(selectedBeam, bestBeam, localFiniteOrNaNColumn(Ti, "BeamHit"));
    topKHit = localBackfillTopKHit(beamHit, localFiniteOrNaNColumn(Ti, "TopKBeamHit"));
    beamGap = localFiniteOrNaNColumn(Ti, "BeamGainGap_dB");
    beamCount = localFiniteOrNaNColumn(Ti, "BeamCandidateCount");
    absSlot = localBeamAbsoluteSlot(Ti, slotsPerFrame);

    beamDetected = isfinite(bestBeam);
    selectedDefined = isfinite(selectedBeam);
    misalignmentFlag = isfinite(beamHit) & beamHit < 0.5;
    failureThreshold_dB = double(sixgr.util.structGet(cfg, ...
        "channel.awgnBeamFailureDetectionThreshold_dB", 3));
    failureFlag = isfinite(beamGap) & beamGap > failureThreshold_dB;

    acquisitionFlag = false(n, 1);
    switchFlag = false(n, 1);
    firstHitFlag = false(n, 1);
    switchLatencySlots = nan(n, 1);
    switchLatency_s = nan(n, 1);
    trialsSinceLastSwitch = nan(n, 1);
    trialsToFirstHit = nan(n, 1);
    recoveryFlag = false(n,1);
    recoveryLatencySlots = nan(n,1);
    recoveryLatency_s = nan(n,1);
    recoveryLatency_ms = nan(n,1);
    failureEventId = nan(n,1);
    failureTriggerSlot = nan(n,1);
    failureTriggerTime_s = nan(n,1);
    recoveryCompletionSlot = nan(n,1);
    recoveryCompletionTime_s = nan(n,1);
    stateBefore = repmat("uninitialized", n, 1);
    stateAfter = repmat("searching", n, 1);
    eventType = repmat("BEAM_SEARCH", n, 1);

    firstHitIdx = find(beamHit > 0.5, 1, "first");
    if ~isempty(firstHitIdx)
        firstHitFlag(firstHitIdx) = true;
        trialsToFirstHit(:) = double(firstHitIdx);
    end

    prevState = "uninitialized";
    prevSelectedBeam = NaN;
    prevDetected = false;
    lastSwitchSlot = NaN;
    lastSwitchOrdinal = NaN;
    failureStartSlot = NaN;
    activeFailureEventId = NaN;
    nextFailureEventId = 1;
    detectedEventFlag = false(n, 1);

    for k = 1:n
        if beamDetected(k) && ~prevDetected
            detectedEventFlag(k) = true;
        end

        if selectedDefined(k) && ~isfinite(prevSelectedBeam)
            acquisitionFlag(k) = true;
            lastSwitchSlot = absSlot(k);
            lastSwitchOrdinal = double(k);
        elseif selectedDefined(k) && isfinite(prevSelectedBeam) && abs(selectedBeam(k) - prevSelectedBeam) > 0
            switchFlag(k) = true;
            if isfinite(lastSwitchSlot)
                switchLatencySlots(k) = absSlot(k) - lastSwitchSlot;
                if isfinite(switchLatencySlots(k))
                    switchLatency_s(k) = switchLatencySlots(k) * slotDur_s;
                end
            end
            lastSwitchSlot = absSlot(k);
            lastSwitchOrdinal = double(k);
        end

        if isfinite(lastSwitchOrdinal)
            trialsSinceLastSwitch(k) = double(k) - lastSwitchOrdinal;
        end

        stateBefore(k) = prevState;
        stateAfter(k) = localBeamRuntimeStateName(selectedDefined(k), beamDetected(k), misalignmentFlag(k), failureFlag(k));
        if failureFlag(k) && ~isfinite(failureStartSlot)
            failureStartSlot=absSlot(k);
            activeFailureEventId=nextFailureEventId;
            nextFailureEventId=nextFailureEventId+1;
        elseif isfinite(failureStartSlot) && ~failureFlag(k) && ...
                beamDetected(k) && isfinite(beamHit(k)) && beamHit(k)>0.5
            recoveryFlag(k)=true;
            recoveryLatencySlots(k)=absSlot(k)-failureStartSlot;
            recoveryLatency_s(k)=recoveryLatencySlots(k)*slotDur_s;
            recoveryLatency_ms(k)=1e3*recoveryLatency_s(k);
            recoveryCompletionSlot(k)=absSlot(k);
            recoveryCompletionTime_s(k)=absSlot(k)*slotDur_s;
            failureEventId(k)=activeFailureEventId;
            failureTriggerSlot(k)=failureStartSlot;
            failureTriggerTime_s(k)=failureStartSlot*slotDur_s;
            failureStartSlot=NaN;
            activeFailureEventId=NaN;
        end
        if isfinite(failureStartSlot)
            failureEventId(k)=activeFailureEventId;
            failureTriggerSlot(k)=failureStartSlot;
            failureTriggerTime_s(k)=failureStartSlot*slotDur_s;
        end
        eventType(k) = localBeamRuntimeEventLabel(acquisitionFlag(k), switchFlag(k), firstHitFlag(k), ...
            detectedEventFlag(k), misalignmentFlag(k), failureFlag(k), stateAfter(k));

        prevState = stateAfter(k);
        prevDetected = beamDetected(k);
        if selectedDefined(k)
            prevSelectedBeam = selectedBeam(k);
        end
    end

    stateVars = intersect(["Direction","SNR_dB","Frame","Slot","UEIndex","RNTI","SelectedBeamIndex","BestBeamIndex", ...
        "BeamHit","TopKBeamHit","BeamCandidateCount","SelectedBeamGain_dB","BestBeamGain_dB","BeamGainGap_dB", ...
        "BeamSelectionStrategy","ConfiguredBeamSelectionStrategy","AppliedBeamIndexSet","ExecutionModel","Status"], ...
        string(Ti.Properties.VariableNames), "stable");
    stateTi = Ti(:, stateVars);
    stateTi.TrialOrdinal = (1:n).';
    stateTi.AbsoluteSlot = absSlot;
    stateTi.BeamDetectedFlag = double(beamDetected);
    stateTi.MisalignmentFlag = double(misalignmentFlag);
    stateTi.BeamFailureFlag = double(failureFlag);
    stateTi.PredictionSuccessFlag = beamHit;
    stateTi.TrialsSinceLastSwitch = trialsSinceLastSwitch;
    stateTi.StateBefore = stateBefore;
    stateTi.StateAfter = stateAfter;
    stateTi.BeamSweepEnabled = repmat(beamSweepEnabled, n, 1);
    stateTi.BeamCountConfigured = repmat(beamCountConfigured, n, 1);

    eventVars = intersect(["Direction","SNR_dB","Frame","Slot","UEIndex","RNTI","TrialOrdinal","AbsoluteSlot", ...
        "SelectedBeamIndex","BestBeamIndex","BeamHit","TopKBeamHit","BeamCandidateCount","BeamGainGap_dB", ...
        "BeamSelectionStrategy","ExecutionModel","Status"], string(stateTi.Properties.VariableNames), "stable");
    eventTi = stateTi(:, eventVars);
    eventTi.EventType = eventType;
    eventTi.AcquisitionEventFlag = double(acquisitionFlag);
    eventTi.SwitchEventFlag = double(switchFlag);
    eventTi.FirstHitEventFlag = double(firstHitFlag);
    eventTi.BeamDetectedEventFlag = double(detectedEventFlag);
    eventTi.MisalignmentEventFlag = double(misalignmentFlag);
    eventTi.FailureEventFlag = double(failureFlag);
    eventTi.RecoveryEventFlag = double(recoveryFlag);
    eventTi.RecoveryLatencySlots = recoveryLatencySlots;
    eventTi.RecoveryLatency_s = recoveryLatency_s;
    eventTi.RecoveryLatency_ms = recoveryLatency_ms;
    eventTi.FailureEventID = failureEventId;
    eventTi.FailureTriggerSlot = failureTriggerSlot;
    eventTi.FailureTriggerTime_s = failureTriggerTime_s;
    eventTi.RecoveryCompletionSlot = recoveryCompletionSlot;
    eventTi.RecoveryCompletionTime_s = recoveryCompletionTime_s;
    eventTi.BeamFailureThreshold_dB = repmat(failureThreshold_dB,n,1);
    eventTi.SwitchLatencySlots = switchLatencySlots;
    eventTi.SwitchLatency_s = switchLatency_s;
    eventTi.TrialsToFirstHit = trialsToFirstHit;
    eventTi.StateBefore = stateBefore;
    eventTi.StateAfter = stateAfter;

    stateChunks{idx} = stateTi;
    eventChunks{idx} = eventTi;
end

stateChunks = stateChunks(~cellfun(@isempty, stateChunks));
eventChunks = eventChunks(~cellfun(@isempty, eventChunks));
if ~isempty(stateChunks)
    stateT = vertcat(stateChunks{:});
end
if ~isempty(eventChunks)
    eventT = vertcat(eventChunks{:});
end
end

function paprT = localBuildPAPRCCDFTable(rawTrials)
paprT = table();
if ~isstruct(rawTrials)
    return;
end
for direction=["DL","UL"]
    if isfield(rawTrials,direction)
        rawTrials.(direction)=localResolveTrialTable(rawTrials.(direction));
    end
end
paprT=sixgr.report.buildPAPRCCDFTable(rawTrials);
end

function traceT = localBuildBeamScoreTraceTable(T, cfg)
traceT = table();
if ~(istable(T) && ~isempty(T))
    return;
end
candidateTraceT = localBuildBeamCandidateScoreTraceTable(T, cfg);
if istable(candidateTraceT) && ~isempty(candidateTraceT)
    traceT = candidateTraceT;
    return;
end
vars = ["Direction","SNR_dB","Frame","Slot","UEIndex","RNTI","SelectedBeamIndex","BestBeamIndex", ...
    "BeamHit","TopKBeamHit","BeamCandidateCount","SelectedBeamGain_dB","BestBeamGain_dB", ...
    "BeamGainGap_dB","ReceiverHestSINR_dB","ChannelGain_dB","BeamSelectionStrategy","BeamIndexSet","ConfiguredBeamSelectionStrategy","AppliedBeamIndexSet", ...
    "PrecoderSource","PrecodingMode","PrecodingApplicationStage","PrecodingActive","ExplicitBeamWeightsApplied","TransformPrecodingApplied","BeamformingApplied", ...
    "AppliedPrecoderPMI","AppliedPrecoderPMIType","AppliedPrecoderCodebookMode","PrecodingNumPorts","PrecodingNumLayers","PrecodingMatrixRows","PrecodingMatrixCols", ...
    "ExecutionModel","Status"];
vars = vars(ismember(vars, string(T.Properties.VariableNames)));
traceT = T(:, vars);
traceT.BeamSweepEnabled = repmat(logical(sixgr.util.structGet(cfg, "phy.beamManagement.enabled", false)), height(traceT), 1);
traceT.BeamCountConfigured = repmat(double(sixgr.util.structGet(cfg, "phy.beamManagement.beamCount", NaN)), height(traceT), 1);
end

function traceT = localBuildBeamCandidateScoreTraceTable(T, cfg)
traceT = table();
if ~(istable(T) && ~isempty(T)) || ~ismember("BeamScoreVector_dB", string(T.Properties.VariableNames))
    return;
end
rowTemplate = struct( ...
    "Direction", "", ...
    "SNR_dB", NaN, ...
    "Frame", NaN, ...
    "Slot", NaN, ...
    "UEIndex", NaN, ...
    "RNTI", NaN, ...
    "CandidateBeamIndex", NaN, ...
    "CandidateBeamGain_dB", NaN, ...
    "CandidateRank", NaN, ...
    "SelectedBeamIndex", NaN, ...
    "BestBeamIndex", NaN, ...
    "SelectedCandidateFlag", false, ...
    "BestCandidateFlag", false, ...
    "Top2CandidateFlag", false, ...
    "BeamCandidateCount", NaN, ...
    "SelectedBeamGain_dB", NaN, ...
    "BestBeamGain_dB", NaN, ...
    "BeamGainGap_dB", NaN, ...
    "BeamScoreSource", "", ...
    "ConfiguredBeamSelectionStrategy", "", ...
    "AppliedBeamIndexSet", "", ...
    "PrecoderSource", "", ...
    "PrecodingMode", "", ...
    "PrecodingActive", false, ...
    "BeamformingApplied", false, ...
    "AppliedPrecoderPMI", NaN, ...
    "AppliedPrecoderCodebookMode", "", ...
    "ExecutionModel", "", ...
    "Status", "", ...
    "BeamSweepEnabled", false, ...
    "BeamCountConfigured", NaN);
rows = repmat(rowTemplate, 0, 1);
beamSweepEnabled = logical(sixgr.util.structGet(cfg, "phy.beamManagement.enabled", false));
configuredBeamCount = double(sixgr.util.structGet(cfg, "phy.beamManagement.beamCount", NaN));
for ii = 1:height(T)
    scores = localParseDelimitedNumericVector(localTableStringValue(T, "BeamScoreVector_dB", ii));
    scores = scores(isfinite(scores));
    if isempty(scores)
        continue;
    end
    selectedBeam = localTableNumericValue(T, "SelectedBeamIndex", ii);
    bestBeam = localTableNumericValue(T, "BestBeamIndex", ii);
    [~, order] = sort(scores(:), "descend");
    ranks = nan(numel(scores), 1);
    ranks(order) = (1:numel(order)).';
    for beamIdx = 1:numel(scores)
        row = rowTemplate;
        row.Direction = localTableStringValue(T, "Direction", ii);
        row.SNR_dB = localTableNumericValue(T, "SNR_dB", ii);
        row.Frame = localTableNumericValue(T, "Frame", ii);
        row.Slot = localTableNumericValue(T, "Slot", ii);
        row.UEIndex = localTableNumericValue(T, "UEIndex", ii);
        row.RNTI = localTableNumericValue(T, "RNTI", ii);
        row.CandidateBeamIndex = double(beamIdx);
        row.CandidateBeamGain_dB = double(scores(beamIdx));
        row.CandidateRank = double(ranks(beamIdx));
        row.SelectedBeamIndex = selectedBeam;
        row.BestBeamIndex = bestBeam;
        row.SelectedCandidateFlag = isfinite(selectedBeam) && round(selectedBeam) == beamIdx;
        row.BestCandidateFlag = isfinite(bestBeam) && round(bestBeam) == beamIdx;
        row.Top2CandidateFlag = isfinite(row.CandidateRank) && row.CandidateRank <= min(2, numel(scores));
        row.BeamCandidateCount = double(numel(scores));
        row.SelectedBeamGain_dB = localTableNumericValue(T, "SelectedBeamGain_dB", ii);
        row.BestBeamGain_dB = localTableNumericValue(T, "BestBeamGain_dB", ii);
        row.BeamGainGap_dB = localTableNumericValue(T, "BeamGainGap_dB", ii);
        row.BeamScoreSource = localTableStringValue(T, "BeamScoreSource", ii);
        row.ConfiguredBeamSelectionStrategy = localTableStringValue(T, "ConfiguredBeamSelectionStrategy", ii);
        row.AppliedBeamIndexSet = localTableStringValue(T, "AppliedBeamIndexSet", ii);
        row.PrecoderSource = localTableStringValue(T, "PrecoderSource", ii);
        row.PrecodingMode = localTableStringValue(T, "PrecodingMode", ii);
        row.PrecodingActive = localTableLogicalValue(T, "PrecodingActive", ii);
        row.BeamformingApplied = localTableLogicalValue(T, "BeamformingApplied", ii);
        row.AppliedPrecoderPMI = localTableNumericValue(T, "AppliedPrecoderPMI", ii);
        row.AppliedPrecoderCodebookMode = localTableStringValue(T, "AppliedPrecoderCodebookMode", ii);
        row.ExecutionModel = localTableStringValue(T, "ExecutionModel", ii);
        row.Status = localTableStringValue(T, "Status", ii);
        row.BeamSweepEnabled = beamSweepEnabled;
        row.BeamCountConfigured = configuredBeamCount;
        rows(end+1, 1) = row; %#ok<AGROW>
    end
end
if isempty(rows)
    return;
end
traceT = struct2table(rows);
end

function values = localParseDelimitedNumericVector(token)
values = [];
token = strtrim(string(token));
if any(ismissing(token)) || strlength(token) == 0
    return;
end
parts = regexp(char(token), "[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?", "match");
if isempty(parts)
    return;
end
values = str2double(parts(:)).';
values = values(isfinite(values));
end

function value = localTableNumericValue(T, varName, rowIdx)
value = NaN;
if ~(istable(T) && ismember(varName, string(T.Properties.VariableNames)))
    return;
end
try
    raw = T.(varName)(rowIdx);
    value = double(raw(1));
catch
    value = NaN;
end
end

function value = localTableLogicalValue(T, varName, rowIdx)
numVal = localTableNumericValue(T, varName, rowIdx);
value = isfinite(numVal) && numVal ~= 0;
end

function value = localTableStringValue(T, varName, rowIdx)
value = "";
if ~(istable(T) && ismember(varName, string(T.Properties.VariableNames)))
    return;
end
try
    raw = T.(varName)(rowIdx);
    if isnumeric(raw) || islogical(raw)
        value = string(sprintf("%g", double(raw(1))));
    elseif isstring(raw)
        value = string(raw(1));
    elseif iscell(raw)
        value = string(raw{1});
    else
        value = string(raw);
    end
catch
    value = "";
end
end

function T = localResolveTrialTable(v)
T = table();
if istable(v)
    T = v;
    return;
end
if isstring(v) || ischar(v)
    p = char(string(v));
    if exist(p, "file") == 2
        T = sixgr.util.csvReadTable(p);
    end
end
end

function varargout = localUnavailablePHYSignalDiagnostic(varargin)
% Compatibility delegate; completion/publication has one production owner.
[varargout{1:nargout}] = sixgr.truth.SharedDataCompletionRuntime.unavailablePHYSignalDiagnostic(varargin{:});
end

function varargout = localSelectPHYSignalDiagnostic(varargin)
% Compatibility delegate; completion/publication has one production owner.
[varargout{1:nargout}] = sixgr.truth.SharedDataCompletionRuntime.selectPHYSignalDiagnostic(varargin{:});
end

function varargout = localPHYSignalDiagnosticEvidenceRank(varargin)
% Compatibility delegate; completion/publication has one production owner.
[varargout{1:nargout}] = sixgr.truth.SharedDataCompletionRuntime.pHYSignalDiagnosticEvidenceRank(varargin{:});
end

function varargout = localPHYSignalDiagnosticRank(varargin)
% Compatibility delegate; completion/publication has one production owner.
[varargout{1:nargout}] = sixgr.truth.SharedDataCompletionRuntime.pHYSignalDiagnosticRank(varargin{:});
end

function varargout = localRecordPHYSignalDiagnostic(varargin)
% Compatibility delegate; completion/publication has one production owner.
[varargout{1:nargout}] = sixgr.truth.SharedDataCompletionRuntime.recordPHYSignalDiagnostic(varargin{:});
end

function images = localExportTrialDiagnosticPlots(airInterfaceRunFolder, rawTrials, saveFigures)
images = sixgr.report.exportTrialDiagnosticPlots( ...
    fileparts(char(string(airInterfaceRunFolder))),rawTrials,saveFigures);
end


function localWriteTrialMetricScatterPlot(T, metricName, outPath, plotTitle, yLabel)
if ~(istable(T) && ~isempty(T) && ismember(metricName, string(T.Properties.VariableNames)))
    return;
end
[x, xLabel] = localResolveTrialScatterXAxis(T);
y = localNumericColumn(T, metricName);
mask = isfinite(x) & isfinite(y);
if ~any(mask)
    return;
end
fig = figure("Visible", "off", "Color", "w");
cleanupObj = onCleanup(@() close(fig)); %#ok<NASGU>
ax = axes(fig);
hold(ax, "on");
group = localTrialGroupLabels(T);
groups = unique(group(mask), "stable");
colorOrder = get(ax, "ColorOrder");
for i = 1:numel(groups)
    gm = mask & group == groups(i);
    if ~any(gm)
        continue;
    end
    scatter(ax, x(gm), y(gm), 18, "MarkerEdgeColor", colorOrder(1 + mod(i - 1, size(colorOrder, 1)), :), ...
        "MarkerFaceColor", "none", "DisplayName", char(groups(i)));
end
grid(ax, "on");
xlabel(ax, xLabel);
ylabel(ax, yLabel);
title(ax, plotTitle + " (scatter; no implied temporal continuity)");
if numel(groups) <= 12
    legend(ax, "Location", "best");
end
sixgr.util.exportFigureArtifact(fig, outPath, "Resolution", 160);
end


function localWriteTrialMetricPlot(T, metricName, outPath, plotTitle, yLabel)
if ~(istable(T) && ~isempty(T) && ismember(metricName, string(T.Properties.VariableNames)))
    return;
end
localWriteTrialMetricScatterPlot(T, metricName, outPath, plotTitle, yLabel);
end

function localWriteGroupedMetricPlot(T, metricName, outPath, plotTitle, yLabel)
if ~(istable(T) && ~isempty(T) && ismember(metricName, string(T.Properties.VariableNames)))
    return;
end
fig = figure("Visible", "off", "Color", "w");
cleanupObj = onCleanup(@() close(fig)); %#ok<NASGU>
ax = axes(fig);
hold(ax, "on");
groupValues = strings(0,1);
groupMask = cell(0,1);
if ismember("UEIndex", string(T.Properties.VariableNames))
    ues = unique(double(T.UEIndex));
    for i = 1:numel(ues)
        mask = double(T.UEIndex) == ues(i);
        if ismember("Direction", string(T.Properties.VariableNames))
            dirVals = unique(string(T.Direction(mask)));
            for d = 1:numel(dirVals)
                maskDir = mask & string(T.Direction) == dirVals(d);
                groupValues(end+1,1) = dirVals(d) + " UE" + string(ues(i)); %#ok<AGROW>
                groupMask{end+1,1} = maskDir; %#ok<AGROW>
            end
        else
            groupValues(end+1,1) = "UE" + string(ues(i)); %#ok<AGROW>
            groupMask{end+1,1} = mask; %#ok<AGROW>
        end
    end
elseif ismember("Direction", string(T.Properties.VariableNames))
    dirs = unique(string(T.Direction));
    for i = 1:numel(dirs)
        groupValues(end+1,1) = dirs(i); %#ok<AGROW>
        groupMask{end+1,1} = string(T.Direction) == dirs(i); %#ok<AGROW>
    end
else
    localWriteTrialMetricPlot(T, metricName, outPath, plotTitle, yLabel);
    return;
end

made = false;
xLabel = "Frame";
for i = 1:numel(groupValues)
    maskDir = groupMask{i};
    [xAll, xLabel] = localResolveTrialScatterXAxis(T);
    x = xAll(maskDir);
    yAll = localNumericColumn(T, metricName);
    y = yAll(maskDir);
    mask = isfinite(x) & isfinite(y);
    if ~any(mask)
        continue;
    end
    seriesColor = ax.ColorOrder(1 + mod(i - 1, size(ax.ColorOrder, 1)), :);
    scatter(ax, x(mask), y(mask), 16, "MarkerEdgeColor", seriesColor, ...
        "MarkerFaceColor", "none", "DisplayName", char(groupValues(i)));
    made = true;
end
if ~made
    return;
end
grid(ax, "on");
xlabel(ax, xLabel);
ylabel(ax, yLabel);
title(ax, plotTitle);
if strcmpi(xLabel, "Configured SNR (dB)")
    localApplySweepXAxis(ax, T, xLabel);
end
if numel(groupValues) <= 12
    legend(ax, "Location", "best");
end
sixgr.util.exportFigureArtifact(fig, outPath, "Resolution", 160);
end

function [x, xLabel] = localResolveTrialScatterXAxis(T)
vars = string(T.Properties.VariableNames);
for name = ["TrialId","TrialID","TrialIndex","TransportBlockID","Slot","SampleIndex"]
    if ismember(name, vars)
        candidate = localNumericColumn(T, name);
        if numel(candidate) == height(T) && any(isfinite(candidate))
            x = candidate;
            xLabel = char(name);
            return;
        end
    end
end
x = (1:height(T)).';
xLabel = "Trial row index";
end

function labels = localTrialGroupLabels(T)
labels = repmat("all_trials", height(T), 1);
vars = string(T.Properties.VariableNames);
if ismember("UEIndex", vars)
    ue = localNumericColumn(T, "UEIndex");
    labels = "UE" + string(ue);
elseif ismember("UEId", vars)
    ue = localNumericColumn(T, "UEId");
    labels = "UE" + string(ue);
end
if ismember("Direction", vars)
    labels = string(T.Direction) + " " + labels;
end
labels = strtrim(labels);
labels(strlength(labels) == 0 | labels == "UE" | contains(labels, "NaN")) = "all_trials";
end

function values = localNumericColumn(T, name)
values = nan(height(T), 1);
if ~(istable(T) && ismember(string(name), string(T.Properties.VariableNames)))
    return;
end
try
    values = double(T.(string(name)));
catch
    values = str2double(string(T.(string(name))));
end
values = reshape(values, [], 1);
if numel(values) ~= height(T)
    values = nan(height(T), 1);
end
end

function values = localNumericColumnOrDefault(T, names, fallback)
values = [];
names = string(names);
for i = 1:numel(names)
    if ismember(names(i), string(T.Properties.VariableNames))
        values = localNumericColumn(T, names(i));
        return;
    end
end
if nargin >= 3
    values = repmat(double(fallback), height(T), 1);
end
end



function localDeleteIfExists(path)
try
    if exist(path, "file") == 2
        delete(path);
    end
catch
end
end

function [x, xLabel] = localResolveTrialPlotXAxis(T, groupIndex, groupCount)
multiSweep = localHasMultipleSweepPoints(T);
if multiSweep && ismember("SNR_dB", string(T.Properties.VariableNames))
    x = double(T.SNR_dB);
    if nargin >= 3 && groupCount > 1
        x = x + localSymmetricGroupOffset(groupIndex, groupCount, 0.35);
    end
    xLabel = "Configured SNR (dB)";
    return;
end
if ismember("Frame", string(T.Properties.VariableNames))
    x = double(T.Frame);
    xLabel = "Frame";
else
    x = (1:height(T)).';
    xLabel = "Trial";
end
end

function offset = localSymmetricGroupOffset(groupIndex, groupCount, maxMagnitude)
if nargin < 3
    maxMagnitude = 0.35;
end
if groupCount <= 1
    offset = 0;
    return;
end
centers = linspace(-double(maxMagnitude), double(maxMagnitude), groupCount);
offset = centers(groupIndex);
end

function localApplySweepXAxis(ax, T, xLabel)
if ~(strcmpi(string(xLabel), "Configured SNR (dB)") && istable(T) && ismember("SNR_dB", string(T.Properties.VariableNames)))
    return;
end
snrVals = unique(double(T.SNR_dB), "sorted");
snrVals = snrVals(isfinite(snrVals));
if isempty(snrVals)
    return;
end
xticks(ax, snrVals.');
if numel(snrVals) >= 2
    xlim(ax, [min(snrVals) - 1, max(snrVals) + 1]);
else
    xlim(ax, [snrVals(1) - 1, snrVals(1) + 1]);
end
end

function tf = localHasMultipleSweepPoints(T)
tf = false;
if ~(istable(T) && ismember("SNR_dB", string(T.Properties.VariableNames)))
    return;
end
snrVals = double(T.SNR_dB);
snrVals = unique(snrVals(isfinite(snrVals)));
tf = numel(snrVals) > 1;
end


function T = localEmptyProbeMetricTable()
T = table('Size', [0 8], ...
    'VariableTypes', {'string','string','string','double','string','string','string','string'}, ...
    'VariableNames', {'MetricKey','Entity','Statistic','Value','TextValue','Unit','Notes','Availability'});
end

function T = localProbeMetricRow(metricKey, entity, statistic, value, textValue, unit, notes, varargin)
availability = "";
if ~isempty(varargin)
    availability = string(varargin{1});
end
if strlength(strtrim(string(textValue))) == 0 && isfinite(double(value))
    textValue = sprintf('%.12g', double(value));
end
T = table(string(metricKey), string(entity), string(statistic), double(value), string(textValue), string(unit), string(notes), string(availability), ...
    'VariableNames', {'MetricKey','Entity','Statistic','Value','TextValue','Unit','Notes','Availability'});
end

function dirs = localUniqueDirections(T)
dirs = strings(0, 1);
if ~(istable(T) && ismember("Direction", string(T.Properties.VariableNames)))
    return;
end
dirs = unique(string(T.Direction), "stable");
end

function vals = localFiniteMaskValue(T, varName)
vals = [];
if ~(istable(T) && ismember(varName, string(T.Properties.VariableNames)))
    return;
end
x = double(T.(varName));
vals = x(isfinite(x));
end

function vals = localFiniteColumn(T, varName)
vals = [];
if ~(istable(T) && ismember(varName, string(T.Properties.VariableNames)))
    return;
end
x = double(T.(varName));
vals = x(isfinite(x));
end

function count = localBeamSwitchCount(selectedBeam)
count = 0;
if isempty(selectedBeam)
    return;
end
selectedBeam = double(selectedBeam(:));
selectedBeam = selectedBeam(isfinite(selectedBeam));
if numel(selectedBeam) <= 1
    return;
end
count = sum(abs(diff(selectedBeam)) > 0);
end

function meanInterval = localMeanBeamSwitchInterval(selectedBeam)
meanInterval = NaN;
if isempty(selectedBeam)
    return;
end
selectedBeam = double(selectedBeam(:));
selectedBeam = selectedBeam(isfinite(selectedBeam));
if numel(selectedBeam) <= 1
    meanInterval = 0;
    return;
end
switchIdx = find(abs(diff(selectedBeam)) > 0) + 1;
if isempty(switchIdx)
    meanInterval = numel(selectedBeam);
    return;
end
intervals = diff([1; switchIdx(:)]);
meanInterval = mean(double(intervals), "omitnan");
end

function meanTrials = localMeanTrialsToFirstHit(T)
meanTrials = NaN;
if ~(istable(T) && ismember("BeamHit", string(T.Properties.VariableNames)))
    return;
end
hits = double(T.BeamHit);
hits = hits(isfinite(hits));
if isempty(hits)
    return;
end
firstHit = find(hits > 0, 1, "first");
if isempty(firstHit)
    meanTrials = numel(hits);
else
    meanTrials = double(firstHit);
end
end

function vals = localFiniteOrNaNColumn(T, varName)
if ~(istable(T) && ismember(varName, string(T.Properties.VariableNames)))
    vals = nan(height(T), 1);
    return;
end
vals = double(T.(varName));
vals = vals(:);
end

function out = localBackfillBeamHit(selectedBeam, bestBeam, beamHit)
out = beamHit;
mask = ~isfinite(out) & isfinite(selectedBeam) & isfinite(bestBeam);
out(mask) = double(abs(selectedBeam(mask) - bestBeam(mask)) < 1e-9);
end

function out = localBackfillTopKHit(beamHit, topKHit)
out = topKHit;
mask = ~isfinite(out) & isfinite(beamHit);
out(mask) = beamHit(mask);
end

function stateName = localBeamRuntimeStateName(selectedDefined, beamDetected, misalignmentFlag, failureFlag)
if ~beamDetected
    stateName = "searching";
elseif failureFlag
    stateName = "failed_alignment";
elseif misalignmentFlag
    stateName = "misaligned";
elseif selectedDefined
    stateName = "aligned";
else
    stateName = "detected_pending_selection";
end
end

function label = localBeamRuntimeEventLabel(acquired, switched, firstHit, detected, misaligned, failed, stateAfter)
parts = strings(0, 1);
if acquired
    parts(end+1, 1) = "BEAM_ACQUIRED"; %#ok<AGROW>
end
if switched
    parts(end+1, 1) = "BEAM_SWITCH"; %#ok<AGROW>
end
if firstHit
    parts(end+1, 1) = "BEAM_REFINEMENT_CONVERGED"; %#ok<AGROW>
end
if detected
    parts(end+1, 1) = "BEAM_DETECTED"; %#ok<AGROW>
end
if misaligned
    parts(end+1, 1) = "BEAM_MISALIGNED"; %#ok<AGROW>
end
if failed
    parts(end+1, 1) = "BEAM_FAILURE"; %#ok<AGROW>
end
if isempty(parts)
    if stateAfter == "searching"
        label = "BEAM_SEARCH";
    else
        label = "BEAM_TRACK";
    end
else
    label = strjoin(parts, "|");
end
end

function absSlot = localBeamAbsoluteSlot(T, slotsPerFrame)
absSlot = nan(height(T), 1);
runtimeAbsoluteSlot0 = localFiniteOrNaNColumn(T, "RuntimeAbsoluteSlotIndex0");
runtimeMask = isfinite(runtimeAbsoluteSlot0);
absSlot(runtimeMask) = runtimeAbsoluteSlot0(runtimeMask);
frame = localFiniteOrNaNColumn(T, "Frame");
slot = localFiniteOrNaNColumn(T, "Slot");
% Independent-link tables use zero-based frame/local-slot coordinates,
% whereas coupled-runtime Slot is one-based absolute time.  Prefer the
% explicit runtime clock above; only use frame/local-slot arithmetic when
% no absolute clock was exported.
mask = ~runtimeMask & isfinite(frame) & isfinite(slot);
absSlot(mask) = frame(mask) * slotsPerFrame + slot(mask);
end

function slotsPerFrame = localSlotsPerFrame(cfg)
[~, numerology] = sixgr.time.slotDurationSec(cfg);
slotsPerFrame = double(numerology.SlotsPerFrame);
end

function vals = localTableColumnAsString(T, varName)
vals = repmat("", height(T), 1);
if ~(istable(T) && ismember(varName, string(T.Properties.VariableNames)))
    return;
end
v = T.(varName);
if isnumeric(v) || islogical(v)
    vals = compose("%g", double(v));
elseif isstring(v)
    vals = v;
elseif ischar(v)
    vals = string(cellstr(v));
elseif iscellstr(v)
    vals = string(v);
else
    vals = string(v);
end
end

function confidenceLevel=localConfiguredConfidenceLevel(cfg)
profileID=string(sixgr.util.structGet(cfg, ...
    "validation.profile_id","nr_rel18_phy_lls_strict"));
profile=sixgr.validation.ValidationCapabilityProfile.plan(profileID).toStruct();
confidenceLevel=double(sixgr.util.structGet(cfg, ...
    "validation.fixed_link_campaign.confidence_level", ...
    profile.NominalConfidenceLevel));
if ~(isscalar(confidenceLevel)&&isfinite(confidenceLevel)&& ...
        confidenceLevel>0&&confidenceLevel<1)
    error("sixgr:validation:InvalidConfidenceLevel", ...
        "Configured validation confidence level must be in (0,1).");
end
end

function result = localSuppressedLegacyRasterResult(runFolder)
% Contract-enabled LLS runs render only after all runtime CSVs have been
% finalized and audited. This explicit empty result keeps legacy callers
% structurally compatible without creating transient MATLAB PNGs or a
% lineage table for images that the contract materializer intentionally
% does not publish.
result = struct( ...
    "Ok", true, ...
    "RunDir", string(runFolder), ...
    "Plots", strings(0, 1), ...
    "LineageCSV", "", ...
    "LineageTable", table(), ...
    "Status", "suppressed_contract_raster_authority", ...
    "Producer", "scripts.regenerate_lls_rasters_from_csv");
end
