function out = runWaveformLinkBundle(cfg, runFolder, opt)
%RUNWAVEFORMLINKBUNDLE Run strict waveform link/control validation exports.

if nargin < 3 || ~isstruct(opt)
    opt = struct();
end
persistenceEnabled = localResolvePersistenceEnabled(opt);
persistenceCleanup = sixgr.util.persistenceScope(persistenceEnabled); %#ok<NASGU>

cfgL = cfg;
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
cfgExec = localPrepareUserCfg(cfgL, multiUser, 1);
rootRunFolder = fileparts(char(string(runFolder)));
cfgL = sixgr.util.structSet(cfgL, "run.rootRunFolder", rootRunFolder);
cfgExec = sixgr.util.structSet(cfgExec, "run.rootRunFolder", rootRunFolder);

sixgr.util.ensureFolder(runFolder);
sixgr.util.ensureFolder(fullfile(runFolder, "csv"));
sixgr.util.ensureFolder(fullfile(runFolder, "mat"));
sixgr.util.ensureFolder(fullfile(runFolder, "image"));

ctx = sixgr.core.SimContext(cfgExec, "RunFolder", runFolder);
ctx.Logger.EchoToConsole = false;

slotDur_s = localSlotDuration(cfgExec);
reqFrames = ceil(double(sixgr.util.structGet(opt, "LinkDuration_s", 0.02)) / max(slotDur_s, eps));
requestedMaxFrames = round(double(sixgr.util.structGet(opt, "LinkMaxSimFrames", reqFrames)));
numFrames = max(1, min(requestedMaxFrames, reqFrames));
sweepPlan = localResolveSweepPlan(opt, numFrames);

if logical(sixgr.util.structGet(opt, "FixedLinkCampaignOnly", false))
    fixedGridFallback = sixgr.util.structGet(opt, "LinkSNRGrid_dB", ...
        sixgr.util.structGet(opt, "LinkSNR_dB", cfgExec.channel.snr_dB));
    fixedLinkGrid = localResolveFixedLinkCampaignGrid(double(fixedGridFallback), sweepPlan);
    campaign = localRunFixedLinkCampaign(cfgExec, fixedLinkGrid(:), sweepPlan, multiUser);
    fixedSummary = sixgr.util.structGet(campaign, "Summary", table());
    if istable(fixedSummary) && ~isempty(fixedSummary)
        sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "lls_snr_sweep.csv"), fixedSummary);
        sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "lls_reference_snr_sweep.csv"), fixedSummary);
        sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "lls_fixed_link_campaign.csv"), fixedSummary);
    end
    if logical(persistenceEnabled)
        localWriteFixedLinkCampaignEvidence(runFolder, campaign);
    end
    out = struct();
    out.Ok = istable(fixedSummary) && ~isempty(fixedSummary);
    out.RunFolder = runFolder;
    out.Result = struct("SNRSweep", fixedSummary, "ReferenceSweep", fixedSummary, "FixedLinkCampaign", campaign);
    out.KPITable = table();
    out.SNRSweep = fixedSummary;
    out.ReferenceSweep = fixedSummary;
    out.FixedLinkCampaign = campaign;
    out.RawTrials = struct("DL", sixgr.util.structGet(campaign, "DLTrials", table()), ...
        "UL", sixgr.util.structGet(campaign, "ULTrials", table()));
    out.Artifacts = struct();
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
anchorCaseNames = localResolveBundleAnchorCases(opt);
receiverNoiseMode = localUsesReceiverNoiseMeasurement(cfgExec, opt);

if receiverNoiseMode
    localLogStage(ctx, "Starting strict waveform LLS bundle: slot_steps=" + string(numFrames) + ...
        ", quality_mode=receiver_noise_figure_thermal_noise, operating_point_label_db=" + string(double(sixgr.util.structGet(opt, "LinkSNR_dB", 30))));
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
localPublishWaveformBundleStageStatus(runFolder, struct( ...
    "Stage", "link_anchor_complete", ...
    "AnchorKPIsReady", istable(sixgr.util.structGet(res, "KPITable", table())), ...
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
localPublishAnchorKPIArtifacts(runFolder, res);
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
rawTrials = localExportLinkRawTrialTables(cfgExec, runFolder, res, sweepPlan.PrimaryTrialsPerSNR, snrGrid(:), multiUser, saveFigures, liveMobilityArtifacts);
slotTrace = struct();
if isCoupledTruth
    slotTrace = sixgr.util.structGet(rawTrials, "CoupledRuntime", struct());
    if isstruct(slotTrace) && ~isempty(fieldnames(slotTrace))
        liveMobilityArtifacts = localBuildMobilityArtifactsFromCoupledRuntime(slotTrace);
    end
end
localPublishRuntimeReferenceArtifacts(runFolder, cfgL, multiUser, rawTrials);
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
if isstruct(sixgr.util.structGet(liveDerivedArtifacts, "HARQ", struct()))
    harqArtifacts = sixgr.util.structGet(liveDerivedArtifacts, "HARQ", harqArtifacts);
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
if isstruct(sixgr.util.structGet(liveDerivedArtifacts, "HARQ", struct()))
    harqArtifacts = sixgr.util.structGet(liveDerivedArtifacts, "HARQ", harqArtifacts);
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
    sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "lls_snr_sweep.csv"), res.SNRSweep);
end
if istable(res.ReferenceSweep) && ~isempty(res.ReferenceSweep)
    sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "lls_reference_snr_sweep.csv"), res.ReferenceSweep);
end
fixedLinkSummary = sixgr.util.structGet(sixgr.util.structGet(res, "FixedLinkCampaign", struct()), "Summary", table());
if istable(fixedLinkSummary) && ~isempty(fixedLinkSummary)
    sixgr.util.csvWriteTable(fullfile(runFolder, "csv", "lls_fixed_link_campaign.csv"), fixedLinkSummary);
end
if logical(persistenceEnabled)
    localWriteFixedLinkCampaignEvidence(runFolder, sixgr.util.structGet(res, "FixedLinkCampaign", struct()));
end
[stageRows, stageOrder] = localAppendRuntimeStageProfile(rootRunFolder, stageRows, stageOrder, ...
    "sweep_csv_export", toc(stageStart), toc(bundleStart), "Controlled sweep CSV artifact export completed when fixed-link or raw sweep evidence was available.");
legacyHARQReady = localLegacyHARQArtifactsReady(rootRunFolder);
runtimeHARQReady = localArtifactStructReady(harqArtifacts, "SummaryTable") || ...
    localArtifactStructReady(harqArtifacts, "TimelineTable");
harqDiagnosticsEnabled = logical(sixgr.util.structGet(opt, "HARQDiagnosticsEnabled", true));
if ~harqDiagnosticsEnabled && runtimeHARQReady
    [stageRows, stageOrder] = localAppendRuntimeStageProfile(rootRunFolder, stageRows, stageOrder, ...
        "harq_export_runtime_observation_reuse", 0, toc(bundleStart), ...
        "Live runtime HARQ observation artifacts reused; optional standalone HARQ probe disabled by runtime tuning.");
elseif ~harqDiagnosticsEnabled
    [stageRows, stageOrder] = localAppendRuntimeStageProfile(rootRunFolder, stageRows, stageOrder, ...
        "harq_export_disabled_no_runtime_observation", 0, toc(bundleStart), ...
        "Optional standalone HARQ probe disabled by runtime tuning and no runtime HARQ observation table was available.");
elseif ~localArtifactStructReady(harqArtifacts, "SummaryTable") || ...
        logical(sixgr.util.structGet(harqArtifacts, "PreviewOnly", false)) || ~legacyHARQReady
    localLogStage(ctx, "Exporting HARQ diagnostics.");
    stageStart = tic;
    harqArtifacts = sixgr.truth.exportLLSHARQDiagnostics(cfgExec, runFolder, opt);
    [stageRows, stageOrder] = localAppendRuntimeStageProfile(rootRunFolder, stageRows, stageOrder, ...
        "harq_export", toc(stageStart), toc(bundleStart), "HARQ diagnostics exported.");
else
    [stageRows, stageOrder] = localAppendRuntimeStageProfile(rootRunFolder, stageRows, stageOrder, ...
        "harq_export_reuse", 0, toc(bundleStart), "HARQ diagnostics were already available.");
end
localPublishWaveformBundleStageStatus(runFolder, struct( ...
    "Stage", "harq_ready", ...
    "AnchorKPIsReady", true, ...
    "DLTrialsReady", true, ...
    "ULTrialsReady", true, ...
    "ControlReady", localRawControlTablesReady(rawTrials), ...
    "HARQReady", localArtifactStructReady(harqArtifacts, "SummaryTable"), ...
    "BeamReady", false, ...
    "RFReady", false, ...
    "SweepReady", true, ...
    "FinalBundleReady", false, ...
    "Notes", "HARQ diagnostics were exported."));
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
[stageRows, stageOrder] = localAppendRuntimeStageProfile(rootRunFolder, stageRows, stageOrder, ...
    "trial_plot_export", toc(stageStart), toc(bundleStart), "Trial diagnostic plots exported.");

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
measuredSINRArtifacts = struct();
try
    measuredSINRArtifacts.Curves = sixgr.analytics.generateMeasuredSINRCurves(rootRunFolder, ...
        string(sixgr.util.structGet(cfgExec, "run.runTag", "")), ...
        "TrialData", rawTrials, ...
        "ScenarioConfig", cfgExec, ...
        "WriteKPISummary", true, ...
        "UpdateAnchorKPIs", true);
    measuredSINRArtifacts.Plots = sixgr.analytics.generateMeasuredSINRPlots(rootRunFolder, ...
        string(sixgr.util.structGet(cfgExec, "run.runTag", "")));
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

out = struct();
out.Ok = logical(localLinkKPITableHealthy(kpi));
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
out.LiveMobilityArtifacts = liveMobilityArtifacts;
out.LiveDerivedArtifacts = liveDerivedArtifacts;
out.RuntimeStageProfile = struct2table(stageRows);
out.Integrity = integrity;
out.Errors = sixgr.util.structGet(res, "Errors", strings(0,1));
out.UnsupportedCases = unsupportedCases;
out.MultiUser = multiUser;
out.PersistenceEnabled = logical(persistenceEnabled);
out.CoreOnly = ~logical(persistenceEnabled);
localLogStage(ctx, "Strict waveform LLS bundle completed.");
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
caseDefs = localBundleAnchorCaseDefs();
res = struct();
res.Ok = false;
res.Skipped = false;
res.Errors = strings(0, 1);
res.Cases = struct();
res.KPITable = table();
res.Artifacts = struct('csv', {{}}, 'mat', {{}}, 'fig', {{}});

rows = repmat(localMakeBundleAnchorKpiRow("", struct()), 0, 1);
for k = 1:numel(caseDefs)
    cName = string(caseDefs{k}.name);
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
if ~res.Ok
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

if logical(sixgr.util.structGet(cfg, "phy.pdsch.enable", true))
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

if logical(sixgr.util.structGet(cfg, "phy.pusch.enable", true))
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

if logical(sixgr.util.structGet(cfg, "phy.srs.enable", true))
    rng(double(seed) + 20000, "twister");
    srs = sixgr.link.runSRSChannelEstimation(cfg, "SNR_dB", snr);
    if logical(sixgr.util.structGet(srs, "Skipped", false))
        error("sixgr:truth:FixedSweepSkippedSRS", ...
            "SRS fixed-link sweep point at %.6g dB was skipped: %s", snr, string(sixgr.util.structGet(srs, "Notes", "")));
    end
    nmse = double(sixgr.util.structGet(srs, "NMSE_dB", NaN));
    if isfinite(nmse)
        row.SRS_NMSE_dB = nmse;
        row.SRS_NMSE_CI_Low = nmse;
        row.SRS_NMSE_CI_High = nmse;
        row.SRS_TrialCount = 1;
    end
end
end

function out = localExportLinkRawTrialTables(cfg, runFolder, linkRes, nFrames, snrGrid_dB, multiUser, saveFigures, mobilityArtifacts)
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
if isLiveDBMode
    dlLiveConstellationPath = fullfile(csvDir, "dl_constellation_preview.csv");
    ulLiveConstellationPath = fullfile(csvDir, "ul_constellation_preview.csv");
end
if isLiveDBMode
    emptyTrials = localEmptyLinkTrialTable(0);
    sixgr.util.csvWriteTable(fDL, emptyTrials);
    sixgr.util.csvWriteTable(fUL, emptyTrials);
    sixgr.util.csvWriteTable(fPBCH, emptyTrials);
    sixgr.util.csvWriteTable(fPRACH, emptyTrials);
    sixgr.util.csvWriteTable(fPDCCH, emptyTrials);
    sixgr.util.csvWriteTable(fPUCCH, emptyTrials);
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
standaloneFallbackForDisabledGating = coupledTruth && localCoupledControlGatingDisabled(cfg);
exportStandaloneControlDiagnostics = logical(sixgr.util.structGet(cfg, "outputs.exportStandaloneControlDiagnostics", false)) || ...
    standaloneFallbackForDisabledGating;

if coupledTruth
    if exportStandaloneControlDiagnostics
        diagDir = localStandaloneControlDiagnosticDir(runFolder, csvDir);
        standalonePBCH = localCollectTrialsAcrossSweep(@(snr) localCollectPBCHTrials(cfg, snr, max(1, ceil(nTrials/4))), snrGrid, ...
            fullfile(diagDir, "pbch_standalone_trials.csv"), "PBCH standalone diagnostic");
        standalonePBCH = localCanonicalizeControlTrialTable("PBCH", localMarkStandaloneControlDiagnostic("PBCH", standalonePBCH));
        sixgr.util.csvWriteTable(fullfile(diagDir, "pbch_standalone_trials.csv"), standalonePBCH);

        standalonePRACH = localCollectTrialsAcrossSweep(@(snr) localCollectPRACHTrials(cfg, snr, max(1, ceil(nTrials/4))), snrGrid, ...
            fullfile(diagDir, "prach_standalone_trials.csv"), "PRACH standalone diagnostic");
        standalonePRACH = localCanonicalizeControlTrialTable("PRACH", localMarkStandaloneControlDiagnostic("PRACH", standalonePRACH));
        sixgr.util.csvWriteTable(fullfile(diagDir, "prach_standalone_trials.csv"), standalonePRACH);

        standalonePDCCH = localCollectTrialsAcrossSweep(@(snr) localCollectPDCCHTrials(cfg, snr, max(1, ceil(nTrials/2))), snrGrid, ...
            fullfile(diagDir, "pdcch_aggregation_sweep_trials.csv"), "PDCCH aggregation sweep diagnostic");
        standalonePDCCH = localCanonicalizeControlTrialTable("PDCCH", localMarkStandaloneControlDiagnostic("PDCCH", standalonePDCCH));
        sixgr.util.csvWriteTable(fullfile(diagDir, "pdcch_aggregation_sweep_trials.csv"), standalonePDCCH);

        standalonePUCCH = localCollectTrialsAcrossSweep(@(snr) localCollectPUCCHTrials(cfg, snr, max(1, ceil(nTrials/2))), snrGrid, ...
            fullfile(diagDir, "pucch_standalone_trials.csv"), "PUCCH standalone diagnostic");
        standalonePUCCH = localCanonicalizeControlTrialTable("PUCCH", localMarkStandaloneControlDiagnostic("PUCCH", standalonePUCCH));
        sixgr.util.csvWriteTable(fullfile(diagDir, "pucch_standalone_trials.csv"), standalonePUCCH);

        standaloneSRS = localCollectTrialsAcrossSweep(@(snr) localCollectSRSTrials(cfg, snr, max(1, ceil(nTrials/3))), snrGrid, ...
            fullfile(diagDir, "srs_standalone_trials.csv"), "SRS standalone diagnostic");
        standaloneSRS = localCanonicalizeControlTrialTable("SRS", localMarkStandaloneControlDiagnostic("SRS", standaloneSRS));
        sixgr.util.csvWriteTable(fullfile(diagDir, "srs_standalone_trials.csv"), standaloneSRS);

        standaloneTRS = localCollectTrialsAcrossSweep(@(snr) localCollectTRSTrials(cfg, snr, max(1, ceil(nTrials/3))), snrGrid, ...
            fullfile(diagDir, "trs_standalone_trials.csv"), "TRS standalone diagnostic");
        standaloneTRS = localCanonicalizeControlTrialTable("TRS", localMarkStandaloneControlDiagnostic("TRS", standaloneTRS));
        sixgr.util.csvWriteTable(fullfile(diagDir, "trs_standalone_trials.csv"), standaloneTRS);

        if standaloneFallbackForDisabledGating
            pbchTrials = standalonePBCH;
            prachTrials = standalonePRACH;
            pdcchTrials = standalonePDCCH;
            pucchTrials = standalonePUCCH;
            srsTrials = standaloneSRS;
            trsTrials = standaloneTRS;
        end
    end
else
    pbchTrials = localCollectTrialsAcrossSweep(@(snr) localCollectPBCHTrials(cfg, snr, max(1, ceil(nTrials/4))), snrGrid, fPBCH, "PBCH");
    pbchTrials = localCanonicalizeControlTrialTable("PBCH", pbchTrials);
    sixgr.util.csvWriteTable(fPBCH, pbchTrials);

    [prachTrials, prachCorrelationTrace, prachRAEvidence] = localCollectPRACHTrialsAcrossSweep(cfg, snrGrid, max(1, ceil(nTrials/4)), fPRACH, "PRACH");
    prachTrials = localCanonicalizeControlTrialTable("PRACH", prachTrials);
    sixgr.util.csvWriteTable(fPRACH, prachTrials);

    pdcchTrials = localCollectTrialsAcrossSweep(@(snr) localCollectPDCCHTrials(cfg, snr, max(1, ceil(nTrials/2))), snrGrid, fPDCCH, "PDCCH");
    pdcchTrials = localCanonicalizeControlTrialTable("PDCCH", pdcchTrials);
    sixgr.util.csvWriteTable(fPDCCH, pdcchTrials);

    pucchTrials = localCollectTrialsAcrossSweep(@(snr) localCollectPUCCHTrials(cfg, snr, max(1, ceil(nTrials/2))), snrGrid, fPUCCH, "PUCCH");
    pucchTrials = localCanonicalizeControlTrialTable("PUCCH", pucchTrials);
    sixgr.util.csvWriteTable(fPUCCH, pucchTrials);

    srsTrials = localCollectTrialsAcrossSweep(@(snr) localCollectSRSTrials(cfg, snr, max(1, ceil(nTrials/3))), snrGrid, fSRS, "SRS");
    srsTrials = localCanonicalizeControlTrialTable("SRS", srsTrials);
    sixgr.util.csvWriteTable(fSRS, srsTrials);

    trsTrials = localCollectTrialsAcrossSweep(@(snr) localCollectTRSTrials(cfg, snr, max(1, ceil(nTrials/3))), snrGrid, fTRS, "TRS");
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
        fDL, fUL, dlLiveConstellationPath, ulLiveConstellationPath, struct());
    pbchTrials = localPreferNonEmptyControlTrials(localRuntimeControlTrials(sixgr.util.structGet(controlTrials, "PBCH", table())), pbchTrials);
    prachTrials = localPreferNonEmptyControlTrials(localRuntimeControlTrials(sixgr.util.structGet(controlTrials, "PRACH", table())), prachTrials);
    prachCorrelationTrace = localRuntimeControlTrials(sixgr.util.structGet(controlTrials, "PRACHCorrelationTrace", table()));
    prachRAEvidence = localAppendRAEvidenceTables(prachRAEvidence, sixgr.util.structGet(controlTrials, "RAEvidenceTables", struct()));
    pdcchTrials = localPreferNonEmptyControlTrials(localRuntimeControlTrials(sixgr.util.structGet(controlTrials, "PDCCH", table())), pdcchTrials);
    pucchTrials = localPreferNonEmptyControlTrials(localRuntimeControlTrials(sixgr.util.structGet(controlTrials, "PUCCH", table())), pucchTrials);
    srsTrials = localPreferNonEmptyControlTrials(localRuntimeControlTrials(sixgr.util.structGet(controlTrials, "SRS", table())), srsTrials);
    csirsTrials = localPreferNonEmptyControlTrials(localRuntimeControlTrials(sixgr.util.structGet(controlTrials, "CSIRS", table())), csirsTrials);
    trsTrials = localPreferNonEmptyControlTrials(localRuntimeControlTrials(sixgr.util.structGet(controlTrials, "TRS", table())), trsTrials);
elseif logical(multiUser.Enabled) && isLiveDBMode
    [dlTrials, ulTrials, dlUserSummary, ulUserSummary, dlConst, ulConst, csirsTrials] = ...
        localCollectInterleavedMultiUserLinkTrialsAcrossSweep(cfg, runFolder, multiUser, nTrials, snrGrid, ...
        fDL, fUL, dlLiveConstellationPath, ulLiveConstellationPath, saveFigures, mobilityArtifacts);
else
    if logical(multiUser.Enabled)
        [dlTrials, dlUserSummary, dlConst, csirsTrials] = localCollectMultiUserLinkTrialsAcrossSweep(cfg, multiUser, "DL", nTrials, snrGrid, fDL, dlLiveConstellationPath, "DL PDSCH");
    else
        [dlTrials, dlConst, csirsTrials] = localCollectSingleUserLinkTrialsAcrossSweep(cfg, "DL", nTrials, snrGrid, ...
            fDL, dlLiveConstellationPath, "DL PDSCH");
        dlUserSummary = table();
    end
    dlTrials = localCanonicalizeLinkTrialExport(dlTrials, "DL", cfg);
    sixgr.util.csvWriteTable(fDL, dlTrials);
    if istable(csirsTrials) && ~isempty(csirsTrials)
        sixgr.util.csvWriteTable(fCSIRS, csirsTrials);
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
        [ulTrials, ulUserSummary, ulConst] = localCollectMultiUserLinkTrialsAcrossSweep(cfg, multiUser, "UL", nTrials, snrGrid, fUL, ulLiveConstellationPath, "UL PUSCH");
    else
        [ulTrials, ulConst] = localCollectSingleUserLinkTrialsAcrossSweep(cfg, "UL", nTrials, snrGrid, ...
            fUL, ulLiveConstellationPath, "UL PUSCH");
        ulUserSummary = table();
    end
    ulTrials = localCanonicalizeLinkTrialExport(ulTrials, "UL", cfg);
    sixgr.util.csvWriteTable(fUL, ulTrials);
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

function T = localPreferNonEmptyControlTrials(runtimeT, fallbackT)
if nargin < 1 || ~istable(runtimeT)
    runtimeT = table();
end
if nargin < 2 || ~istable(fallbackT)
    fallbackT = table();
end
if ~isempty(runtimeT)
    T = runtimeT;
else
    T = fallbackT;
end
end

function T = localRuntimeControlTrials(runtimeT)
if nargin < 1 || ~istable(runtimeT)
    T = table();
else
    T = runtimeT;
end
end

function tf = localCoupledControlGatingDisabled(cfg)
flags = [ ...
    logical(sixgr.util.structGet(cfg, "run.controlGating.pbchRequired", ...
        sixgr.util.structGet(cfg, "control_gating.pbch_required", false))), ...
    logical(sixgr.util.structGet(cfg, "run.controlGating.prachRequired", ...
        sixgr.util.structGet(cfg, "control_gating.prach_required", false))), ...
    logical(sixgr.util.structGet(cfg, "run.controlGating.pdcchRequired", ...
        sixgr.util.structGet(cfg, "control_gating.pdcch_required", false))), ...
    logical(sixgr.util.structGet(cfg, "run.controlGating.srsRequired", ...
        sixgr.util.structGet(cfg, "control_gating.srs_required", false))), ...
    logical(sixgr.util.structGet(cfg, "run.controlGating.trsRequired", ...
        sixgr.util.structGet(cfg, "control_gating.trs_required", false)))];
tf = ~any(flags);
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
sixgr.util.csvWriteTable(fullfile(layout.ControlCSVDir, fileName), T);
end

function tf = localShouldExportSSBBeamSweep(cfg)
tf = logical(sixgr.util.structGet(cfg, "outputs.exportSSBBeamSweep", ...
    sixgr.util.structGet(cfg, "analytics.export_ssb_beam_sweep", ...
    sixgr.util.structGet(cfg, "phy.beamManagement.enabled", false)))) && ...
    logical(sixgr.util.structGet(cfg, "phy.ssb.enable", true)) && ...
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
    mobilityArtifacts = localBuildMobilityArtifactsFromCoupledRuntime(coupledRuntime);
end
dlTrials = localCanonicalizeLinkTrialExport(dlTrials, "DL", cfg);
ulTrials = localCanonicalizeLinkTrialExport(ulTrials, "UL", cfg);
pbchTrials = localCanonicalizeControlTrialTable("PBCH", pbchTrials);
prachTrials = localCanonicalizeControlTrialTable("PRACH", prachTrials);
pdcchTrials = localCanonicalizeControlTrialTable("PDCCH", pdcchTrials);
pucchTrials = localCanonicalizeControlTrialTable("PUCCH", pucchTrials);
srsTrials = localCanonicalizeControlTrialTable("SRS", srsTrials);
trsTrials = localCanonicalizeControlTrialTable("TRS", trsTrials);
sixgr.util.csvWriteTable(fPBCH, pbchTrials);
if localShouldExportSSBBeamSweep(cfg)
    ssbBeamSweep = localCollectSSBBeamSweepArtifact(cfg, snrGrid(1), fSSBBeamSweep);
    localWriteSSBBeamSweepMirrors(runFolder, ssbBeamSweep);
end
sixgr.util.csvWriteTable(fPRACH, prachTrials);
if istable(prachCorrelationTrace) && ~isempty(prachCorrelationTrace)
    rootRunFolderForPRACHTrace = fileparts(char(string(runFolder)));
    layoutForPRACHTrace = sixgr.report.resultLayout(rootRunFolderForPRACHTrace);
    sixgr.util.csvWriteTable(fullfile(layoutForPRACHTrace.ReportCSVDir, "prach_correlation_trace.csv"), prachCorrelationTrace);
    sixgr.util.csvWriteTable(fullfile(layoutForPRACHTrace.ReportCSVDir, "prach_correlation_traces.csv"), prachCorrelationTrace);
end
localWriteRAEvidenceTables(fileparts(char(string(runFolder))), prachRAEvidence);
sixgr.util.csvWriteTable(fPDCCH, pdcchTrials);
sixgr.util.csvWriteTable(fPUCCH, pucchTrials);
sixgr.util.csvWriteTable(fSRS, srsTrials);
sixgr.util.csvWriteTable(fTRS, trsTrials);
if coupledTruth
    localWriteCoupledControlMirror(runFolder, "pbch_trials.csv", pbchTrials);
    localWriteCoupledControlMirror(runFolder, "prach_trials.csv", prachTrials);
    localWriteCoupledControlMirror(runFolder, "pdcch_trials.csv", pdcchTrials);
    localWriteCoupledControlMirror(runFolder, "pucch_trials.csv", pucchTrials);
    localWriteCoupledControlMirror(runFolder, "srs_trials.csv", srsTrials);
    localWriteCoupledControlMirror(runFolder, "trs_trials.csv", trsTrials);
end
if istable(csirsTrials) && ~isempty(csirsTrials)
    sixgr.util.csvWriteTable(fCSIRS, csirsTrials);
end

if istable(dlConst) && ~isempty(dlConst)
    if isLiveDBMode
        outDLConst = fullfile(csvDir, "dl_constellation_preview.csv");
        sixgr.util.csvWriteTable(outDLConst, localDownsampleConstellationTable(dlConst, 2500));
    else
        outDLConst = fullfile(csvDir, "dl_constellation_samples.csv");
        sixgr.util.csvWriteTable(outDLConst, dlConst);
    end
else
    outDLConst = "";
end

if istable(ulConst) && ~isempty(ulConst)
    if isLiveDBMode
        outULConst = fullfile(csvDir, "ul_constellation_preview.csv");
        sixgr.util.csvWriteTable(outULConst, localDownsampleConstellationTable(ulConst, 2500));
    else
        outULConst = fullfile(csvDir, "ul_constellation_samples.csv");
        sixgr.util.csvWriteTable(outULConst, ulConst);
    end
else
    outULConst = "";
end

out = struct();
out.DL = dlTrials;
out.UL = ulTrials;
out.PBCH = pbchTrials;
out.PRACH = prachTrials;
out.PRACHCorrelationTrace = prachCorrelationTrace;
out.PDCCH = pdcchTrials;
out.PUCCH = pucchTrials;
out.SRS = srsTrials;
out.CSIRS = csirsTrials;
out.TRS = trsTrials;
out.DLPath = fDL;
out.ULPath = fUL;
out.DLConstellation = dlConst;
out.ULConstellation = ulConst;
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
    [dlTrials, dlUserSummary] = localCollectMultiUserLinkTrialsAcrossSweep(cfg, multiUser, "DL", nFrames, snrGrid);
    [ulTrials, ulUserSummary] = localCollectMultiUserLinkTrialsAcrossSweep(cfg, multiUser, "UL", nFrames, snrGrid);
    out.MultiUserDL = localAppendCompatTable(sixgr.util.structGet(rawTrials, "MultiUserDL", table()), dlUserSummary);
    out.MultiUserUL = localAppendCompatTable(sixgr.util.structGet(rawTrials, "MultiUserUL", table()), ulUserSummary);
else
    [dlTrials, ~] = localCollectSingleUserLinkTrialsAcrossSweep(cfg, "DL", nFrames, snrGrid);
    [ulTrials, ~] = localCollectSingleUserLinkTrialsAcrossSweep(cfg, "UL", nFrames, snrGrid);
end

srsTrials = localCollectTrialsAcrossSweep(@(snr) localCollectSRSTrials(cfg, snr, max(6, ceil(nFrames/3))), snrGrid);

out.DL = localAppendCompatTable(rawTrials.DL, dlTrials);
out.UL = localAppendCompatTable(rawTrials.UL, ulTrials);
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

sixgr.util.csvWriteTable(fullfile(csvDir, "dl_pdsch_trials.csv"), out.DL);
sixgr.util.csvWriteTable(fullfile(csvDir, "ul_pusch_trials.csv"), out.UL);
if istable(out.SRS) && ~isempty(out.SRS)
    sixgr.util.csvWriteTable(fullfile(csvDir, "srs_trials.csv"), out.SRS);
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
T = struct2table(orderfields(status));
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
for i = 1:size(pairs, 1)
    signal = lower(string(pairs{i, 1}));
    fieldName = char(pairs{i, 2});
    count = double(sixgr.util.structGet(status, fieldName, NaN));
    count = localMaxFiniteScalar(count, ...
        localCSVDataRowCount(fullfile(layout.AirInterfaceCSVDir, signal + "_trials.csv")), ...
        localCSVDataRowCount(fullfile(layout.ControlCSVDir, signal + "_trials.csv")));
    if ~isfinite(count)
        count = 0;
    end
    status.(fieldName) = double(count);
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
    T = readtable(statusPath, "VariableNamingRule", "preserve");
    if istable(T) && ~isempty(T)
        status = table2struct(T(1, :), "ToScalar", true);
    end
catch
    status = struct();
end
end

function rootRunFolder = localNormalizeBundleRootRunFolder(runFolder)
runFolder = char(string(runFolder));
[~, leaf] = fileparts(runFolder);
domainLeaves = {"air_interface","beamforming","control","harq","meta","reports","rf"};
if any(strcmpi(leaf, domainLeaves))
    rootRunFolder = fileparts(runFolder);
else
    rootRunFolder = runFolder;
end
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
    payload.current_frame = localStatusScalarValue(sixgr.util.structGet(status, "CompletedFrames", NaN));
    payload.total_frames = localStatusScalarValue(sixgr.util.structGet(status, "TotalFrames", NaN));
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
    "ChannelUsesSameRuntimeAntennaAssumptions", false, ...
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
    rows(i).ChannelUsesSameRuntimeAntennaAssumptions = logical(channelEvidence.ChannelUsesSameRuntimeAntennaAssumptions);
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
tf = mode == "receiver_noise_figure_thermal_noise";
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

function mode = localResolveDopplerSourceMode(cfg)
mode = string(sixgr.util.structGet(cfg, "channel.dopplerSourceMode", "configured"));
mode = lower(strtrim(mode));
if strlength(mode) == 0
    mode = "configured";
end
end

function mask = localRowsUseFadingChannelDoppler(T)
mask = false(height(T), 1);
if ~(istable(T) && height(T) > 0)
    return;
end
n = height(T);
trackingSource = lower(strtrim(string(localColumnOrDefault(T, "TrackingEstimateSource", repmat("", n, 1)))));
sourceArtifact = lower(strtrim(string(localColumnOrDefault(T, "SourceArtifact", repmat("", n, 1)))));
isTRS = contains(trackingSource, "trs") | contains(sourceArtifact, "trs_trials");
channelModel = upper(strtrim(string(localColumnOrDefault(T, "ChannelModel", repmat("", n, 1)))));
channelModelApplied = upper(strtrim(string(localColumnOrDefault(T, "ChannelModelApplied", repmat("", n, 1)))));
fadingApplied = logical(localColumnOrDefault(T, "ChannelFadingApplied", false(n, 1)));
fadingModel = startsWith(channelModel, "TDL") | startsWith(channelModel, "CDL") | ...
    startsWith(channelModelApplied, "TDL") | startsWith(channelModelApplied, "CDL");
mask = logical(isTRS & (fadingApplied | fadingModel));
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

function [mode, policy, actualMode] = localResolveLinkAdaptationTokens(cfg, direction)
mode = lower(string(sixgr.util.structGet(cfg, "phy.linkAdaptation.mode", "fixed")));
if upper(string(direction)) == "UL"
    policy = lower(string(sixgr.util.structGet(cfg, "phy.linkAdaptation.ulPolicy", mode)));
else
    policy = lower(string(sixgr.util.structGet(cfg, "phy.linkAdaptation.dlPolicy", mode)));
end
if strlength(strtrim(policy)) == 0
    policy = mode;
end
actualMode = "configured_fixed";
if policy ~= "fixed"
    switch sixgr.link.resolveLinkAdaptationDomain(cfg, direction)
        case "effective_sinr"
            actualMode = "effective_sinr_driven";
        case "bler_margin"
            actualMode = "bler_margin_proxy";
        case "legacy_mcs"
            actualMode = "legacy_mcs_smoothed";
        otherwise
            actualMode = "cqi_driven";
    end
end
end

function values = localResolveOperatingPointSourceColumn(actualMode, linkMode)
values = repmat("", numel(actualMode), 1);
actualMode = lower(strtrim(string(actualMode)));
linkMode = lower(strtrim(string(linkMode)));
values(actualMode == "scheduler_grant") = "scheduler_grant";
values(actualMode == "cqi_driven") = "cqi_link_adaptation";
values(actualMode == "effective_sinr_driven") = "effective_sinr_link_adaptation";
values(actualMode == "bler_margin_proxy") = "bler_margin_proxy_link_adaptation";
values(actualMode == "legacy_mcs_smoothed") = "legacy_mcs_domain_smoothing";
values(actualMode == "cqi_table") = "cqi_link_adaptation";
values(actualMode == "configured_fixed") = "configured_fixed_mcs";
values(actualMode == "feedback_cqi_derived_reference") = "feedback_cqi_derived_reference";
values(actualMode == "bootstrap_large_scale_preview_cqi_lab_default") = "bootstrap_large_scale_preview_cqi_lab_default";
values(actualMode == "bootstrap_cqi_conservative_lab_default") = "bootstrap_cqi_conservative_lab_default";
mask = strlength(values) == 0 & strlength(linkMode) > 0;
values(mask) = "link_adaptation_mode_reference";
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
if ~logical(sixgr.util.structGet(cfg, "phy.linkAdaptation.outerLoopFlag", true))
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
    "ChannelUsesSameRuntimeAntennaAssumptions", false, ...
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
summary.ChannelUsesSameRuntimeAntennaAssumptions = localDominantLogicalValue(trialTable, "ChannelUsesSameRuntimeAntennaAssumptions");
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

function [T, constT, csirsT] = localCollectSingleUserLinkTrialsAcrossSweep(cfg, direction, nTrials, snrGrid, liveTablePath, liveConstellationPath, progressLabel)
T = localEmptyLinkTrialTable(0);
constT = table();
csirsT = table();
direction = upper(string(direction));
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
    T = localAppendCompatTable(T, Ti);
    constT = localAppendCompatTable(constT, sixgr.util.structGet(res, "ConstellationSamples", table()));
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

function [dlTrials, ulTrials, dlSummaryT, ulSummaryT, dlConstT, ulConstT, csirsT] = localCollectInterleavedMultiUserLinkTrialsAcrossSweep(cfg, runFolder, multiUser, nTrials, snrGrid, dlTablePath, ulTablePath, dlConstellationPath, ulConstellationPath, ~, mobilityArtifacts)
dlTrials = localEmptyLinkTrialTable(0);
ulTrials = localEmptyLinkTrialTable(0);
dlConstT = table();
ulConstT = table();
csirsT = table();
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
        [dlUserT, dlUserSummary, dlUserConst, dlUserCSIRS] = localRunSingleUserDirectionTrials( ...
            cfg, multiUser, ueIdx, "DL", nTrials, snrVal, dlLivePublisher);
        dlTrials = localAppendCompatTable(dlTrials, dlUserT);
        dlConstT = localAppendCompatTable(dlConstT, dlUserConst);
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
        [ulUserT, ulUserSummary, ulUserConst] = localRunSingleUserDirectionTrials( ...
            cfg, multiUser, ueIdx, "UL", nTrials, snrVal, ulLivePublisher);
        ulTrials = localAppendCompatTable(ulTrials, ulUserT);
        ulConstT = localAppendCompatTable(ulConstT, ulUserConst);
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

function [dlTrials, ulTrials, dlSummaryT, ulSummaryT, dlConstT, ulConstT, controlTrials, runtimeState] = localCollectCoupledTruthMultiUserLinkTrialsAcrossSweep(cfg, runFolder, multiUser, nTrials, snrGrid, dlTablePath, ulTablePath, dlConstellationPath, ulConstellationPath, controlTrials)
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
userCfg = cell(numUsers, 1);
for ueIdx = 1:numUsers
    userCfg{ueIdx} = localPrepareUserCfg(cfg, multiUser, ueIdx);
end
runtimeState = localInitCoupledTruthRuntimeState(cfg, runFolder, multiUser, controlTrials, nFramesPerPoint * numel(snrGrid));
pendingULGrants = repmat(struct(), 0, 1);
rootRunFolder = fileparts(char(string(runFolder)));
profileCtl = localResolveCoupledProfileControl(runFolder, nFramesPerPoint);
profileCtl.StartTic = tic;
stopCoupledProfile = false;

for sweepIdx = 1:numel(snrGrid)
    snrVal = double(snrGrid(sweepIdx));
    dlStates = cell(numUsers, 1);
    ulStates = cell(numUsers, 1);
    for frameLocal = 1:nFramesPerPoint
        absoluteFrame = (sweepIdx - 1) * nFramesPerPoint + frameLocal;
        runtimeState = localAdvanceCoupledRuntimeFrame(runtimeState, cfg, multiUser, absoluteFrame, snrVal);
        [allowDL, allowUL, slotLabel] = localCoupledSlotDuplexState(cfg, absoluteFrame);
        localAppendRuntimeLog("INFO", ...
            "Coupled canonical slot prepared: sweep=%d/%d slot=%d/%d duplex=%s allow_dl=%d allow_ul=%d.", ...
            round(double(sweepIdx)), round(double(numel(snrGrid))), round(double(frameLocal)), round(double(nFramesPerPoint)), ...
            char(string(slotLabel)), double(logical(allowDL)), double(logical(allowUL)));
        if allowDL
            runtimeState = sixgr.truth.CoupledTruthRuntime.startSlot(runtimeState, cfg, "DL", sweepIdx, numel(snrGrid), absoluteFrame, nFramesPerPoint, snrVal);
        elseif allowUL
            runtimeState = sixgr.truth.CoupledTruthRuntime.startSlot(runtimeState, cfg, "UL", sweepIdx, numel(snrGrid), absoluteFrame, nFramesPerPoint, snrVal);
        else
            localAppendRuntimeLog("WARN", ...
                "Coupled canonical slot skipped because no duplex direction is enabled: sweep=%d/%d slot=%d/%d duplex=%s.", ...
                round(double(sweepIdx)), round(double(numel(snrGrid))), round(double(frameLocal)), round(double(nFramesPerPoint)), ...
                char(string(slotLabel)));
            continue;
        end
        runtimeState = localRunCoupledPreSchedulingControlGating(runtimeState, cfg, runFolder, userCfg, snrVal);
        liveRawTrials = localBuildCoupledTruthRawTrialsAggregate(dlTrials, ulTrials, multiUser, runtimeState.ControlTrials);
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
            localAppendRuntimeLog("INFO", ...
                "Coupled DL schedule complete: sweep=%d/%d slot=%d/%d active=%d granted=%d grants=%d.", ...
                round(double(sweepIdx)), round(double(numel(snrGrid))), round(double(frameLocal)), round(double(nFramesPerPoint)), ...
                round(double(sixgr.util.structGet(dlInfo, "ActiveUsers", NaN))), ...
                round(double(sixgr.util.structGet(dlInfo, "GrantedUsers", NaN))), numel(dlGrants));
            [runtimeState, dlGrants] = localQualifyCoupledGrantsWithPDCCH(runtimeState, userCfg, dlGrants, "DL", snrVal);
            localAppendRuntimeLog("INFO", ...
                "Coupled DL PDCCH qualification complete: sweep=%d/%d slot=%d/%d executable_grants=%d.", ...
                round(double(sweepIdx)), round(double(numel(snrGrid))), round(double(frameLocal)), round(double(nFramesPerPoint)), numel(dlGrants));
            [runtimeState, dlTrials, dlConstT, dlStates] = localExecuteCoupledDirectionBatch( ...
                runtimeState, cfg, runFolder, multiUser, userCfg, dlGrants, "DL", snrVal, absoluteFrame, dlStates, ...
                dlTrials, ulTrials, dlConstT, ulConstT, dlTablePath, ulTablePath, dlConstellationPath, ulConstellationPath, ...
                sweepIdx, numel(snrGrid), frameLocal, nFramesPerPoint);
            [runtimeState, pendingULGrants] = localScheduleCoupledFutureULGrantsFromDLControl( ...
                runtimeState, cfg, userCfg, pendingULGrants, snrVal, sweepIdx, numel(snrGrid), frameLocal, nFramesPerPoint);
        end
        if allowUL
            if allowDL
                runtimeState = sixgr.truth.CoupledTruthRuntime.startSlot(runtimeState, cfg, "UL", sweepIdx, numel(snrGrid), absoluteFrame, nFramesPerPoint, snrVal);
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
            runtimeState = localRecordQueuedULScheduleForCurrentSlot(runtimeState, ulGrants);
            if ~isempty(ulGrants)
                [runtimeState, ulTrials, ulConstT, ulStates] = localExecuteCoupledDirectionBatch( ...
                    runtimeState, cfg, runFolder, multiUser, userCfg, ulGrants, "UL", snrVal, absoluteFrame, ulStates, ...
                    ulTrials, dlTrials, ulConstT, dlConstT, ulTablePath, dlTablePath, ulConstellationPath, dlConstellationPath, ...
                    sweepIdx, numel(snrGrid), frameLocal, nFramesPerPoint);
            end
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

controlTrials = runtimeState.ControlTrials;
harqTimelineT = sixgr.util.structGet(runtimeState, "HARQTimelineTable", table());
dlTrials = localHydrateHARQTrialColumnsFromTimeline(dlTrials, harqTimelineT, "DL");
ulTrials = localHydrateHARQTrialColumnsFromTimeline(ulTrials, harqTimelineT, "UL");
finalRawTrials = localBuildCoupledTruthRawTrialsAggregate(dlTrials, ulTrials, multiUser, controlTrials);
dlSummaryT = sixgr.util.structGet(finalRawTrials, "MultiUserDL", table());
ulSummaryT = sixgr.util.structGet(finalRawTrials, "MultiUserUL", table());
dlTrials = localCanonicalizeLinkTrialExport(dlTrials, "DL", cfg);
ulTrials = localCanonicalizeLinkTrialExport(ulTrials, "UL", cfg);
sixgr.util.csvWriteTable(dlTablePath, dlTrials);
sixgr.util.csvWriteTable(ulTablePath, ulTrials);
if strlength(string(dlConstellationPath)) > 0 && istable(dlConstT) && ~isempty(dlConstT)
    sixgr.util.csvWriteTable(dlConstellationPath, localDownsampleConstellationTable(dlConstT, 2500));
end
if strlength(string(ulConstellationPath)) > 0 && istable(ulConstT) && ~isempty(ulConstT)
    sixgr.util.csvWriteTable(ulConstellationPath, localDownsampleConstellationTable(ulConstT, 2500));
end
localWriteCoupledRuntimeTables(runtimeState, fileparts(char(string(runFolder))));
end

function [state, pendingULGrants] = localScheduleCoupledFutureULGrantsFromDLControl(state, cfg, userCfg, pendingULGrants, snr_dB, sweepIdx, sweepCount, frameLocal, nFramesPerPoint)
if nargin < 4 || ~isstruct(pendingULGrants)
    pendingULGrants = repmat(struct(), 0, 1);
end
slotDLControlAllowed = logical(sixgr.util.structGet(state, "CurrentSlotDLAllowed", true)) && ...
    double(sixgr.util.structGet(state, "CurrentSlotDLNumSymbols", 0)) > 0;
if ~slotDLControlAllowed
    return;
end
k2Slots = localResolveCoupledULK2Slots(cfg);
controlSlot = double(sixgr.util.structGet(state, "CurrentSlot", frameLocal));
dueSlot = controlSlot + k2Slots;
if ~(isfinite(dueSlot) && dueSlot >= 1 && dueSlot <= nFramesPerPoint)
    return;
end
[~, dueAllowUL] = localCoupledSlotDuplexState(cfg, dueSlot);
if ~logical(dueAllowUL)
    return;
end
if localHasPendingCoupledULGrantForSlot(pendingULGrants, dueSlot)
    return;
end

planState = sixgr.truth.CoupledTruthRuntime.startSlot(state, cfg, "UL", sweepIdx, sweepCount, dueSlot, nFramesPerPoint, snr_dB);
% K2 scheduling decides for the future UL slot, so its MAC buffer view must
% include traffic that arrived up to that due slot.
planState = sixgr.truth.CoupledTruthRuntime.enqueueTrafficForFrameRuntime(planState, dueSlot);
pucchDueUEs = sixgr.truth.CoupledTruthRuntime.pucchFeedbackDueUEsRuntime(state, dueSlot);
uciOnPUSCHAvailable = localPUSCHUCIOnPUSCHAvailable(cfg);
if ~isempty(pucchDueUEs) && ~uciOnPUSCHAvailable
    queueLen = numel(sixgr.util.structGet(planState, "ULQueueBits", []));
    pucchDueUEs = unique(round(double(pucchDueUEs(:))));
    pucchDueUEs = pucchDueUEs(isfinite(pucchDueUEs) & pucchDueUEs >= 1 & pucchDueUEs <= queueLen);
    if ~isempty(pucchDueUEs)
        planState.ULQueueBits(pucchDueUEs) = 0;
        localAppendRuntimeLog("INFO", ...
            "Deferred same-slot PUSCH candidates with due HARQ-ACK PUCCH before UL scheduling: control_slot=%d due_slot=%d deferred_ues=%d policy=avoid_standalone_pusch_without_uci_on_pusch_multiplexing.", ...
            round(double(controlSlot)), round(double(dueSlot)), numel(pucchDueUEs));
    end
elseif ~isempty(pucchDueUEs)
    localAppendRuntimeLog("INFO", ...
        "Retained PUSCH candidates with due HARQ-ACK because UCI-on-PUSCH multiplexing is available: control_slot=%d due_slot=%d due_ues=%d policy=nrULSCHMultiplex_harq_ack_on_pusch.", ...
        round(double(controlSlot)), round(double(dueSlot)), numel(unique(round(double(pucchDueUEs(:))))));
end
[planState, grants, info] = sixgr.truth.CoupledTruthRuntime.scheduleDirection(planState, cfg, "UL"); %#ok<ASGLU>
if uciOnPUSCHAvailable
    grants = localAttachDueHARQACKToULGrants(state, grants, dueSlot);
end
localAppendRuntimeLog("INFO", ...
    "Coupled UL K2 preschedule complete: control_slot=%d due_slot=%d k2=%d active=%d granted=%d grants=%d.", ...
    round(double(controlSlot)), round(double(dueSlot)), round(double(k2Slots)), ...
    round(double(sixgr.util.structGet(info, "ActiveUsers", NaN))), ...
    round(double(sixgr.util.structGet(info, "GrantedUsers", NaN))), numel(grants));
if isempty(grants)
    return;
end
for gi = 1:numel(grants)
    grants(gi).ControlSlot = double(controlSlot);
    grants(gi).ControlFrame = double(sixgr.util.structGet(state, "CurrentFrame", controlSlot));
    grants(gi).ScheduledAbsoluteSlot = double(dueSlot);
    grants(gi).K2Slots = double(k2Slots);
    grants(gi).Slot = double(dueSlot);
    grants(gi).Frame = double(sixgr.util.structGet(planState, "CurrentFrame", ...
        sixgr.util.structGet(state, "CurrentFrame", 1)));
    grants(gi).ULGrantTimingMode = "dci_k2_queued_grant";
end

[state, qualifiedGrants] = localQualifyCoupledGrantsWithPDCCH(state, userCfg, grants, "UL", snr_dB);
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
    ueIdx = localResolveGrantUEIndex(qualifiedGrants(gi), state.MultiUser);
    feedback = sixgr.truth.CoupledTruthRuntime.latestFeedbackForDirectionRuntime(state, ueIdx, "UL");
    state = sixgr.truth.CoupledTruthRuntime.appendGrantTraceRuntime(state, qualifiedGrants(gi), "UL", feedback);
end
pendingULGrants = localAppendCoupledPendingULGrants(pendingULGrants, qualifiedGrants);
localAppendRuntimeLog("INFO", ...
    "Queued coupled UL grants after K2 PDCCH qualification: control_slot=%d due_slot=%d executable_grants=%d pending_total=%d.", ...
    round(double(controlSlot)), round(double(dueSlot)), numel(qualifiedGrants), numel(pendingULGrants));
end

function k2Slots = localResolveCoupledULK2Slots(cfg)
k2Slots = localFirstFiniteNumeric( ...
    sixgr.util.structGet(cfg, "phy.pusch.k2_slots", NaN), ...
    sixgr.util.structGet(cfg, "phy.pusch.k2Slots", NaN), ...
    sixgr.util.structGet(cfg, "phy.pusch.k2", NaN), ...
    sixgr.util.structGet(cfg, "mac.scheduler.k2_slots", NaN), ...
    sixgr.util.structGet(cfg, "mac.scheduler.k2Slots", NaN), ...
    sixgr.util.structGet(cfg, "phy.ul.grantK2Slots", NaN), ...
    1);
k2Slots = max(1, round(double(k2Slots)));
end

function tf = localPUSCHUCIOnPUSCHAvailable(cfg)
tf = exist("nrULSCHMultiplex", "file") == 2 && exist("nrULSCHDemultiplex", "file") == 2 && ...
    exist("nrUCIEncode", "file") == 2 && exist("nrUCIDecode", "file") == 2;
if ~tf
    return;
end
mode = lower(strtrim(string(sixgr.util.structGet(cfg, "phy.pusch.uciMultiplexingMode", ...
    sixgr.util.structGet(cfg, "pusch.uci_multiplexing_mode", ...
    sixgr.util.structGet(cfg, "mac.scheduler.uciMultiplexingMode", "harq_ack_on_pusch_when_pucch_collides"))))));
if any(mode == ["disabled","off","none","pucch_only"])
    tf = false;
end
end

function grants = localAttachDueHARQACKToULGrants(state, grants, dueSlot)
if ~(isstruct(grants) && ~isempty(grants))
    return;
end
due = sixgr.truth.CoupledTruthRuntime.pucchFeedbackDueHARQACKRuntime(state, dueSlot);
if ~(isstruct(due) && ~isempty(due))
    return;
end
for gi = 1:numel(grants)
    ueIdx = double(sixgr.util.structGet(grants(gi), "UEIndex", NaN));
    rnti = double(sixgr.util.structGet(grants(gi), "RNTI", NaN));
    matchIdx = [];
    for di = 1:numel(due)
        dueUE = double(sixgr.util.structGet(due(di), "UEIndex", NaN));
        dueRNTI = double(sixgr.util.structGet(due(di), "RNTI", NaN));
        if (isfinite(ueIdx) && isfinite(dueUE) && abs(ueIdx - dueUE) < 1e-9) || ...
                (isfinite(rnti) && isfinite(dueRNTI) && abs(rnti - dueRNTI) < 1e-9)
            matchIdx = di;
            break;
        end
    end
    if isempty(matchIdx)
        continue;
    end
    ackBit = int8(logical(sixgr.util.structGet(due(matchIdx), "AckBit", int8(0))));
    grants(gi).ExpectedUCIBits = ackBit;
    grants(gi).MultiplexedHARQACKBits = ackBit;
    grants(gi).UCIOnPUSCHApplied = true;
    grants(gi).UCIOnPUSCHSource = "pending_harq_ack_nrULSCHMultiplex";
    grants(gi).PUCCHCollisionPolicy = "harq_ack_multiplexed_on_pusch";
    grants(gi).PUCCHSourceSlot = double(sixgr.util.structGet(due(matchIdx), "SourceSlot", NaN));
    grants(gi).PUCCHGrantId = char(string(sixgr.util.structGet(due(matchIdx), "PUCCHGrantId", "")));
    grants(gi).UCIOnPUSCHEvidenceSource = char(string(sixgr.util.structGet(due(matchIdx), "EvidenceSource", "")));
end
end

function tf = localHasPendingCoupledULGrantForSlot(pendingULGrants, dueSlot)
tf = false;
if ~(isstruct(pendingULGrants) && ~isempty(pendingULGrants))
    return;
end
slots = arrayfun(@(g) double(sixgr.util.structGet(g, "ScheduledAbsoluteSlot", sixgr.util.structGet(g, "Slot", NaN))), pendingULGrants(:));
tf = any(abs(slots - double(dueSlot)) < 1e-9);
end

function pendingULGrants = localAppendCoupledPendingULGrants(pendingULGrants, grants)
if ~(isstruct(grants) && ~isempty(grants))
    return;
end
if ~(isstruct(pendingULGrants) && ~isempty(pendingULGrants))
    pendingULGrants = grants;
    return;
end
[pendingULGrants, grants] = localHarmonizeStructArrays(pendingULGrants, grants);
pendingULGrants = vertcat(pendingULGrants, grants);
end

function [dueGrants, pendingULGrants, staleCount] = localPopDueCoupledULGrants(pendingULGrants, slotIdx)
dueGrants = repmat(struct(), 0, 1);
staleCount = 0;
if ~(isstruct(pendingULGrants) && ~isempty(pendingULGrants))
    pendingULGrants = repmat(struct(), 0, 1);
    return;
end
slots = arrayfun(@(g) double(sixgr.util.structGet(g, "ScheduledAbsoluteSlot", sixgr.util.structGet(g, "Slot", NaN))), pendingULGrants(:));
dueMask = abs(slots - double(slotIdx)) < 1e-9;
staleMask = isfinite(slots) & slots < double(slotIdx) & ~dueMask;
staleCount = sum(staleMask);
if any(dueMask)
    dueGrants = pendingULGrants(dueMask);
end
pendingULGrants = pendingULGrants(~dueMask & ~staleMask);
end

function state = localRecordQueuedULScheduleForCurrentSlot(state, grants)
if ~(isstruct(grants) && ~isempty(grants))
    grants = repmat(struct(), 0, 1);
end
ueIdx = arrayfun(@(g) double(sixgr.util.structGet(g, "UEIndex", NaN)), grants(:));
ueIdx = ueIdx(isfinite(ueIdx));
queueBitsByUE = double(sixgr.util.structGet(state, "ULQueueBits", 0));
if isempty(ueIdx)
    activeUsers = sum(isfinite(queueBitsByUE(:)) & queueBitsByUE(:) > 0);
else
    activeUsers = numel(unique(ueIdx));
end
info = struct( ...
    "Direction", "UL", ...
    "ActiveUsers", activeUsers, ...
    "GrantedUsers", numel(unique(ueIdx)), ...
    "GrantCount", numel(grants), ...
    "QueueBits", sum(queueBitsByUE, "omitnan"));
state.LastULGrantCount = numel(grants);
state.LastULGrantedUsers = numel(unique(ueIdx));
state.LastULActiveUsers = activeUsers;
state = sixgr.truth.CoupledTruthRuntime.recordSlotTraceScheduleRuntime(state, "UL", info);
end

function [Tu, constT, waveT, laState, res] = localRunSingleFrameDirectionTrial(cfg, multiUser, ueIdx, direction, snr_dB, frameIdx, laStateIn, trialContext)
cfgU = cfg;
userMeta = sixgr.util.structGet(cfgU, "lls6g.userContext", struct());
userMeta.RuntimeCurrentDirection = upper(string(direction));
cfgU = sixgr.util.structSet(cfgU, "lls6g.userContext", userMeta);
if nargin < 8 || ~isstruct(trialContext)
    trialContext = struct();
end
cfgU = localApplyHARQGrantContext(cfgU, upper(string(direction)), sixgr.util.structGet(trialContext, "GrantSnapshot", struct()));
cfgU = localApplyExecutionGrantSnapshot(cfgU, upper(string(direction)), sixgr.util.structGet(trialContext, "GrantSnapshot", struct()));
    job = sixgr.truth.buildGrantPHYJob(cfgU, upper(string(direction)), snr_dB, frameIdx, laStateIn, trialContext);
    jobResult = sixgr.truth.executeGrantPHYJob(job);
    res = sixgr.util.structGet(jobResult, "Result", struct());
    laState = sixgr.util.structGet(jobResult, "LinkAdaptationState", laStateIn);
Tu = localEnsureLinkTrialTable(sixgr.util.structGet(res, "TrialTable", table()), upper(string(direction)), snr_dB, cfgU);
Tu = localAnnotateUserTrials(Tu, cfgU, multiUser, ueIdx, userMeta);
constT = localAnnotateConstellationSamples( ...
    sixgr.util.structGet(res, "ConstellationSamples", table()), cfgU, multiUser, ueIdx, userMeta, snr_dB, direction);
waveT = localAnnotateWaveformPreviewTable(sixgr.util.structGet(res, "WaveformPreviewTable", table()), multiUser, ueIdx);
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
chunkSize = max(1, round(double(sixgr.util.structGet(cfg, "run.batchSizeLinks", numel(grants)))));
resolvedGrantCache = localBuildCoupledResolvedGrantCache(runtimeState, cfg, multiUser, userCfg, grants, direction);
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
    chunk = localPrepareCoupledGrantBatch(runtimeState, cfg, multiUser, userCfg, grantChunk, direction, snr_dB, absoluteFrame, laStates, grants, chunkStart - 1, resolvedGrantCache);
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
        primaryTrials = localAppendCompatTable(primaryTrials, userT);
        primaryConstT = localAppendCompatTable(primaryConstT, sixgr.util.structGet(chunk(bi), "ConstellationTable", table()));
        if direction == "DL"
            runtimeState.ControlTrials.CSIRS = localAppendCompatTable( ...
                sixgr.util.structGet(runtimeState.ControlTrials, "CSIRS", table()), ...
                sixgr.util.structGet(chunk(bi).Result, "CSIRSTrialTable", table()));
        end
        laStates{ueIdx} = sixgr.util.structGet(chunk(bi), "LinkAdaptationState", laStates{ueIdx});
        chunkWaveformPreviewT = localAppendCompatTable(chunkWaveformPreviewT, sixgr.util.structGet(chunk(bi), "WaveformPreviewTable", table()));
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
        liveRawTrials = localBuildCoupledTruthRawTrialsAggregate(primaryTrials, secondaryTrials, multiUser, runtimeState.ControlTrials);
        localPublishCoupledTruthRuntimeState(cfg, runFolder, liveRawTrials, multiUser, runtimeState, ...
            primaryTablePath, secondaryTablePath, primaryConstellationPath, secondaryConstellationPath, primaryConstT, secondaryConstT, ...
            direction, snr_dB, sweepIdx, sweepCount, chunkLastUEIdx, numel(userCfg), frameLocal, nFramesPerPoint, chunkWaveformPreviewT, ...
            "SlotComplete", localIsCoupledDirectionalPublishSlotComplete(runtimeState, direction), ...
            "FinalDirectionChunk", chunkEnd >= numel(grants), "PublishReason", "post_grant_chunk");
    else
        liveRawTrials = localBuildCoupledTruthRawTrialsAggregate(secondaryTrials, primaryTrials, multiUser, runtimeState.ControlTrials);
        localPublishCoupledTruthRuntimeState(cfg, runFolder, liveRawTrials, multiUser, runtimeState, ...
            secondaryTablePath, primaryTablePath, secondaryConstellationPath, primaryConstellationPath, secondaryConstT, primaryConstT, ...
            direction, snr_dB, sweepIdx, sweepCount, chunkLastUEIdx, numel(userCfg), frameLocal, nFramesPerPoint, chunkWaveformPreviewT, ...
            "SlotComplete", localIsCoupledDirectionalPublishSlotComplete(runtimeState, direction), ...
            "FinalDirectionChunk", chunkEnd >= numel(grants), "PublishReason", "post_grant_chunk");
    end
end
end

function batch = localPrepareCoupledGrantBatch(runtimeState, cfg, multiUser, userCfg, grants, direction, snr_dB, absoluteFrame, laStates, allGrants, grantIndexOffset, resolvedGrantCache)
direction = upper(string(direction));
if nargin < 10 || ~(isstruct(allGrants) && ~isempty(allGrants))
    allGrants = grants;
end
if nargin < 11 || ~(isnumeric(grantIndexOffset) && isscalar(grantIndexOffset) && isfinite(grantIndexOffset))
    grantIndexOffset = 0;
end
if nargin < 12 || ~isstruct(resolvedGrantCache)
    resolvedGrantCache = struct([]);
end
batch = repmat(struct( ...
    "Valid", false, ...
    "UEIndex", NaN, ...
    "LinkSNR_dB", NaN, ...
    "RuntimeReportedLinkQuality_dB", NaN, ...
    "Cfg", struct(), ...
    "GrantSnapshot", struct(), ...
    "GrantRow", table(), ...
    "TrialContext", struct(), ...
    "GrantIndex", NaN, ...
    "LinkAdaptationStateIn", struct(), ...
    "TrialTable", table(), ...
    "ConstellationTable", table(), ...
    "WaveformPreviewTable", table(), ...
    "LinkAdaptationState", struct(), ...
    "Result", struct()), 0, 1);
if ~(isstruct(grants) && ~isempty(grants))
    return;
end
for gi = 1:numel(grants)
    grant = grants(gi);
    absoluteGrantIndex = double(grantIndexOffset + gi);
    ueIdx = localResolveGrantUEIndex(grant, multiUser);
    if ~(isfinite(ueIdx) && ueIdx >= 1 && ueIdx <= numel(userCfg))
        continue;
    end
    tempState = sixgr.truth.CoupledTruthRuntime.setCurrentUE(runtimeState, ueIdx, direction);
    [cfgDir, tempState] = localApplyCoupledRuntimeUserContext(userCfg{ueIdx}, tempState, ueIdx, direction);
    [tempState, trialContext, grantRow] = sixgr.truth.CoupledTruthRuntime.buildTrialContextFromGrant(tempState, cfgDir, ueIdx, direction, grant);
    cacheEntry = localFindCoupledResolvedGrantCacheEntry(resolvedGrantCache, absoluteGrantIndex, ueIdx);
    if isstruct(cacheEntry) && logical(sixgr.util.structGet(cacheEntry, "Valid", false))
        liveGrant = sixgr.util.structGet(trialContext, "GrantSnapshot", struct());
        grantResolved = localMergeLiveRuntimeGrantFields( ...
            sixgr.util.structGet(cacheEntry, "GrantSnapshot", struct()), liveGrant);
        trialContext.GrantSnapshot = grantResolved;
        trialContext.TransportBlockBits = int8(sixgr.util.structGet(cacheEntry, "TransportBlockBits", int8([])));
        rvCached = sixgr.util.structGet(cacheEntry, "RV", []);
        if ~isempty(rvCached)
            trialContext.RV = rvCached;
        end
        expectedUCI = sixgr.util.structGet(cacheEntry, "ExpectedUCIBits", int8([]));
        if ~isempty(expectedUCI)
            trialContext.ExpectedUCIBits = int8(expectedUCI(:));
        end
        trialContext.HARQContext = sixgr.util.structGet(trialContext, "HARQContext", struct());
        trialContext.HARQContext.GrantSnapshot = grantResolved;
        if ~isempty(rvCached)
            trialContext.HARQContext.RV = double(rvCached);
        end
        resolvedBits = double(sixgr.util.structGet(grantResolved, "TBSBits", ...
            sixgr.util.structGet(grantResolved, "TransportBlockSize", numel(trialContext.TransportBlockBits))));
    else
        [trialContext, resolvedBits] = localFinalizeGrantTrialContext(cfgDir, direction, trialContext);
        grantResolved = sixgr.util.structGet(trialContext, "GrantSnapshot", struct());
    end
    grantRow = localRefreshGrantRowFromGrant(grantRow, grantResolved, resolvedBits);
    if ~(isfinite(resolvedBits) && resolvedBits > 0)
        continue;
    end
    runtimeReportedLinkQuality_dB = localResolveCoupledRuntimeLinkSNR(tempState, cfgDir, ueIdx, direction, snr_dB);
    trialContext.RuntimeReportedLinkQuality_dB = double(runtimeReportedLinkQuality_dB);
    trialContext.ConfiguredReplaySNR_dB = double(snr_dB);
    plan = struct( ...
        "Valid", true, ...
        "UEIndex", double(ueIdx), ...
        "LinkSNR_dB", double(snr_dB), ...
        "RuntimeReportedLinkQuality_dB", double(runtimeReportedLinkQuality_dB), ...
        "Cfg", cfgDir, ...
        "GrantSnapshot", grantResolved, ...
        "GrantRow", grantRow, ...
        "TrialContext", trialContext, ...
        "GrantIndex", double(absoluteGrantIndex), ...
        "LinkAdaptationStateIn", laStates{ueIdx}, ...
        "TrialTable", table(), ...
        "ConstellationTable", table(), ...
        "WaveformPreviewTable", table(), ...
        "LinkAdaptationState", laStates{ueIdx}, ...
        "Result", struct());
    batch(end + 1, 1) = plan; %#ok<AGROW>
end
end

function entry = localFindCoupledResolvedGrantCacheEntry(cache, grantIndex, ueIdx)
entry = struct("Valid", false);
if ~(isstruct(cache) && ~isempty(cache))
    return;
end
grantIndex = double(grantIndex);
ueIdx = double(ueIdx);
for ci = 1:numel(cache)
    if logical(sixgr.util.structGet(cache(ci), "Valid", false)) && ...
            double(sixgr.util.structGet(cache(ci), "GrantIndex", NaN)) == grantIndex && ...
            double(sixgr.util.structGet(cache(ci), "UEIndex", NaN)) == ueIdx
        entry = cache(ci);
        return;
    end
end
end

function grantOut = localMergeLiveRuntimeGrantFields(grantCached, grantLive)
grantOut = grantCached;
if ~(isstruct(grantOut) && ~isempty(fieldnames(grantOut)))
    grantOut = grantLive;
end
if ~(isstruct(grantLive) && ~isempty(fieldnames(grantLive)))
    return;
end
fields = ["RuntimeChannelLinkKey", "RuntimeChannelSeed", "RuntimeChannelStateContract", ...
    "GrantWorkerSafe", "GrantSharedStateCommitMode", "Frame", "Slot", "UEIndex", ...
    "ServingCell", "Direction"];
for fi = 1:numel(fields)
    f = char(fields(fi));
    if isfield(grantLive, f)
        grantOut.(f) = grantLive.(f);
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
planSNR_dB = double(sixgr.util.structGet(plan, "LinkSNR_dB", snr_dB));
planFrameIdx = double(sixgr.util.structGet(plan.GrantSnapshot, "Frame", ...
    sixgr.util.structGet(runtimeState, "CurrentFrame", absoluteFrame)));
[userT, userConst, waveT, laStateOut, res] = localRunSingleFrameDirectionTrial( ...
    plan.Cfg, multiUser, plan.UEIndex, direction, planSNR_dB, planFrameIdx, plan.LinkAdaptationStateIn, trialContext);
plan.TrialTable = userT;
plan.GrantSnapshot = localRefreshGrantSnapshotFromTrial(plan.GrantSnapshot, userT);
plan.GrantRow = localRefreshGrantRowFromGrant( ...
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
keepFields = ["HARQ", "CSIRSTrialTable", "LinkAdaptationState", "ChannelState", ...
    "Throughput_Mbps", "Goodput_Mbps", "BLER", "BER", "Ok", "Notes"];
for i = 1:numel(keepFields)
    f = char(keepFields(i));
    if isfield(res, f)
        out.(f) = res.(f);
    end
end
end

function cfgOut = localApplyExecutionGrantSnapshot(cfgIn, direction, grant)
cfgOut = cfgIn;
direction = upper(string(direction));
if ~(isstruct(grant) && ~isempty(fieldnames(grant)))
    return;
end
if direction ~= "DL"
    return;
end
nLayers = double(sixgr.util.structGet(grant, "NumLayers", sixgr.util.structGet(grant, "Layers", NaN)));
if isfinite(nLayers) && nLayers >= 1
    cfgOut = localPruneIncompatibleDLPrecodingConfigForLayers(cfgOut, nLayers);
end
precodingMatrix = sixgr.util.structGet(grant, "PrecodingMatrix", []);
paths = ["phy.pdsch.precoding.matrix", "phy.pdsch.precodingMatrix", "phy.pdsch.W"];
if localGrantCarriesActiveDLPrecoding(grant, precodingMatrix)
    nPorts = localPrecodingPortCount(precodingMatrix, nLayers);
    expectedPorts = localResolveDLPDSCHLogicalPortCount(cfgOut, grant, nLayers);
    if ~(isfinite(nPorts) && nPorts >= max(1, round(double(nLayers)))) || ...
            (isfinite(expectedPorts) && expectedPorts >= 1 && nPorts ~= round(double(expectedPorts)))
        % The grant may still carry a PMI; do not replay a dimensionally
        % invalid explicit matrix as if it were a physical precoder.
        for i = 1:numel(paths)
            cfgOut = sixgr.util.structSet(cfgOut, paths(i), []);
        end
        if isfinite(expectedPorts) && expectedPorts >= max(1, round(double(nLayers)))
            cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.numPorts", round(double(expectedPorts)));
            cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.nPorts", round(double(expectedPorts)));
        end
        return;
    end
    for i = 1:numel(paths)
        cfgOut = sixgr.util.structSet(cfgOut, paths(i), precodingMatrix);
    end
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.numPorts", nPorts);
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.nPorts", nPorts);
else
    for i = 1:numel(paths)
        cfgOut = sixgr.util.structSet(cfgOut, paths(i), []);
    end
    expectedPorts = localResolveDLPDSCHLogicalPortCount(cfgOut, grant, nLayers);
    if isfinite(expectedPorts) && expectedPorts >= max(1, round(double(nLayers)))
        cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.numPorts", round(double(expectedPorts)));
        cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.nPorts", round(double(expectedPorts)));
    else
        cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.numPorts", []);
        cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.nPorts", []);
    end
end
end

function [trialContext, resolvedBits] = localFinalizeGrantTrialContext(cfgIn, direction, trialContext)
resolvedBits = NaN;
if ~(isstruct(trialContext) && isstruct(sixgr.util.structGet(trialContext, "GrantSnapshot", struct())))
    return;
end
grant = sixgr.util.structGet(trialContext, "GrantSnapshot", struct());
direction = upper(string(direction));
isRetx = logical(sixgr.util.structGet(sixgr.util.structGet(trialContext, "HARQContext", struct()), "IsRetransmission", false));
queueBitsUpper = 8 * floor(max(0, double(sixgr.util.structGet(grant, "BufferBytesBefore", sixgr.util.structGet(grant, "TBSBytes", 0)))));
if isRetx
    replayBits = double(numel(sixgr.util.structGet(trialContext, "TransportBlockBits", [])));
    grant = localResolveRetransmissionGrantSnapshot(cfgIn, direction, grant, replayBits);
else
    grant = localResolveStrictGrantSnapshot(cfgIn, direction, grant, queueBitsUpper);
    grant = localClearFrozenPHYGrantSnapshot(grant);
    if isfield(trialContext, "PHYGrant")
        trialContext = rmfield(trialContext, "PHYGrant");
    end
end
trialContext.GrantSnapshot = grant;
resolvedBits = double(sixgr.util.structGet(grant, "TransportBlockSize", sixgr.util.structGet(grant, "TBSBits", NaN)));
if ~isRetx
    needNewTB = isempty(sixgr.util.structGet(trialContext, "TransportBlockBits", [])) || ...
        ~(isfinite(resolvedBits) && resolvedBits > 0 && numel(trialContext.TransportBlockBits) == round(resolvedBits));
    if needNewTB && isfinite(resolvedBits) && resolvedBits > 0
        trialContext.TransportBlockBits = localGenerateGrantTransportBlockBits(cfgIn, grant, direction, round(resolvedBits));
    end
end
end

function grant = localClearFrozenPHYGrantSnapshot(grant)
if ~(isstruct(grant) && ~isempty(fieldnames(grant)))
    return;
end
dropFields = ["PHYGrant", "PHYGrantContextId"];
for i = 1:numel(dropFields)
    f = char(dropFields(i));
    if isfield(grant, f)
        grant = rmfield(grant, f);
    end
end
end

function cache = localBuildCoupledResolvedGrantCache(runtimeState, cfg, multiUser, userCfg, grants, direction)
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
        entries{gi} = localBuildCoupledResolvedGrantCacheEntry(runtimeStateWorker, cfgWorker, multiUser, userCfgWorker, grants(gi), direction, gi);
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
        entry = localBuildCoupledResolvedGrantCacheEntry(runtimeState, cfg, multiUser, userCfg, grants(gi), direction, gi);
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
localAppendRuntimeLog("INFO", ...
    "Prepared coupled %s resolved grant cache complete: entries=%d elapsed_s=%.3f.", ...
    char(upper(string(direction))), numel(cache), toc(tStart));
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
mode = string(sixgr.util.structGet(cfg, "run.interferenceExecutionMode", ""));
mode = strtrim(lower(mode));
tf = mode == "full_per_link_channel_waveform_sum" && ...
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

function entry = localBuildCoupledResolvedGrantCacheEntry(runtimeState, cfg, multiUser, userCfg, grant, direction, grantIndex)
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
    ueIdx = localResolveGrantUEIndex(grant, multiUser);
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
    [cfgI, tempState] = localApplyCoupledRuntimeUserContext(userCfg{ueIdx}, tempState, ueIdx, direction);
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
    [grantContext, ~] = localFinalizeGrantTrialContext(cfgI, direction, grantContext);
    if verboseCacheLog
        localAppendRuntimeLog("INFO", ...
            "Coupled %s grant cache entry %d finalized grant context: ue=%d elapsed_s=%.3f.", ...
            char(upper(string(direction))), round(double(grantIndex)), round(double(ueIdx)), toc(stageTimer));
    end
    grantResolved = sixgr.util.structGet(grantContext, "GrantSnapshot", struct());
    resolvedBits = double(sixgr.util.structGet(grantResolved, "TBSBits", ...
        sixgr.util.structGet(grantResolved, "TransportBlockSize", NaN)));
    if ~(isfinite(resolvedBits) && resolvedBits > 0)
        return;
    end
    stageTimer = tic;
    cfgI = localApplyHARQGrantContext(cfgI, direction, grantResolved);
    cfgI = localApplyExecutionGrantSnapshot(cfgI, direction, grantResolved);
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
    localAppendRuntimeLog("ERROR", ...
        "Coupled %s resolved grant cache entry failed: grant_index=%d ue=%s serving_cell=%s signal=%s err=%s msg=%s", ...
        char(upper(string(direction))), round(double(grantIndex)), ...
        localDisplayProgressValue(ueIdx), localDisplayProgressValue(servingCell), char(signalType), ...
        char(string(ME.identifier)), char(string(ME.message)));
    rethrow(ME);
end
end

function tf = localShouldPrecomputeCoupledInterfererTxWaveform(cfg)
mode = lower(strtrim(string(sixgr.util.structGet(cfg, "run.interferenceExecutionMode", ""))));
tf = mode == "full_per_link_channel_waveform_sum" || ...
    logical(sixgr.util.structGet(cfg, "run.precomputeInterfererTxWaveforms", false));
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
mode = string(sixgr.util.structGet(cfg, "run.interferenceExecutionMode", ""));
mode = strtrim(lower(mode));
if mode ~= "full_per_link_channel_waveform_sum"
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
    if ~(isfinite(interfererCell) && interfererCell >= 1) || interfererCell == victimServingCell
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
    bundle(count).InterferenceMode = char(mode); %#ok<AGROW>
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
[runtimeState, chState] = localResolveSharedSlotRuntimeChannelState( ...
    runtimeState, cfgC, direction, linkKey, double(metricUE), double(metricCell));
chState = sixgr.channel.ChannelFactory.materializeRuntimeChannelState(chState, cfgC, txWave, txInfoC, ...
    "NumTxAnt", runtimeNumTx, ...
    "NumRxAnt", numRx, ...
    "TransmitAntennaRuntime", txRuntimeAntenna, ...
    "ReceiveAntennaRuntime", rxRuntimeAntenna, ...
    "TransmitAntennaMeta", txRuntimeMeta, ...
    "ReceiveAntennaMeta", rxRuntimeMeta);
slotStart_s = double(sixgr.util.structGet(cfgC, "lls6g.userContext.RuntimeSlotStartTime_s", NaN));
if isfinite(slotStart_s) && slotStart_s >= 0
    chState = sixgr.channel.ChannelFactory.advanceRuntimeChannelStateToTime(chState, slotStart_s, runtimeNumTx, txWave);
end
[rxContribution, channelReplay, chState] = sixgr.channel.ChannelFactory.applyRuntimeChannelState(chState, txWave);
runtimeState = sixgr.truth.CoupledTruthRuntime.commitRuntimeChannelState(runtimeState, chState);
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
    "Source", "runtime_pre_adc_shared_slot_receiver_contribution", ...
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
userMeta.RuntimeServingShadowFading_dB = localLargeScaleMatrixValue(ls, "Shadow_dB", metricUE, metricCell);
userMeta.RuntimeServingO2I_dB = localLargeScaleMatrixValue(ls, "O2I_dB", metricUE, metricCell);
userMeta.RuntimeServingRSRP_dBm = localLargeScaleMatrixValue(ls, "RSRP_dBm", metricUE, metricCell);
userMeta.RuntimeServingRxPower_dBm = localLargeScaleMatrixValue(ls, "RxPower_dBm", metricUE, metricCell);
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
if isfinite(userMeta.RuntimeServingDopplerHz)
    cfgOut = sixgr.util.structSet(cfgOut, "channel.doppler_Hz", userMeta.RuntimeServingDopplerHz);
end
if isfinite(userMeta.RuntimeServingSignedDopplerHz)
    cfgOut = sixgr.util.structSet(cfgOut, "channel.runtimeSignedDoppler_Hz", userMeta.RuntimeServingSignedDopplerHz);
end
if isfinite(userMeta.RuntimeServingLOSProbability)
    cfgOut = sixgr.util.structSet(cfgOut, "channel.losProbability", userMeta.RuntimeServingLOSProbability);
end
cfgOut = sixgr.util.structSet(cfgOut, "channel.runtimeLOS", userMeta.RuntimeServingLOS);
cfgOut = sixgr.util.structSet(cfgOut, "run.noiseOperatingMode", "receiver_noise_figure_thermal_noise");
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
[txAnt, txMeta] = sixgr.rf.AntennaArrayFactory.logicalPortView(txAnt, txMeta, ...
    max(1, round(double(runtimeNumTx))), sourceToken);
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
    if isfinite(numTx) && numTx > localMaxNRLogicalPDSCHPorts()
        numTx = activePortCount;
    end
end
numTx = max(activePortCount, round(double(numTx)));
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
symA = double(sixgr.util.structGet(grantA, "SymbolAllocation", [0 14]));
symB = double(sixgr.util.structGet(grantB, "SymbolAllocation", [0 14]));
if numel(symA) < 2 || numel(symB) < 2
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
        uciBits = int8(sixgr.util.structGet(grantContext, "ExpectedUCIBits", int8([])));
        if isempty(uciBits)
            uciBits = int8(1);
        end
        txArgs = {};
        resolvedFormat = double(sixgr.util.structGet(grantContext, "ResolvedFormat", NaN));
        if isfinite(resolvedFormat)
            txArgs = [txArgs {"Format", resolvedFormat}]; %#ok<AGROW>
        end
        rnti = double(sixgr.util.structGet(grantContext, "RNTI", sixgr.util.structGet(cfg, "phy.rnti", NaN)));
        if isfinite(rnti)
            txArgs = [txArgs {"RNTI", rnti}]; %#ok<AGROW>
        end
        [tx, txInfo] = sixgr.phy.ul.PUCCH_Tx(cfg, uciBits, txArgs{:});
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
    else
        txArgs = {"CompactOutput", true};
        txArgs = localAppendCoupledGrantReplayTxArgs(txArgs, grantResolved, "DL");
        transportBlockBits = sixgr.util.structGet(grantContext, "TransportBlockBits", int8([]));
        if ~isempty(transportBlockBits)
            txArgs = [txArgs {"TransportBlockBits", transportBlockBits}]; %#ok<AGROW>
        end
        rv = sixgr.util.structGet(grantContext, "RV", []);
        if ~isempty(rv)
            txArgs = [txArgs {"RV", rv}]; %#ok<AGROW>
        end
        precodingMatrix = sixgr.util.structGet(grantResolved, "PrecodingMatrix", []);
        if localGrantCarriesActiveDLPrecoding(grantResolved, precodingMatrix)
            txArgs = [txArgs {"PrecodingMatrix", precodingMatrix}]; %#ok<AGROW>
        end
        [tx, txInfo] = sixgr.phy.dl.PDSCH_Tx(cfg, txArgs{:});
    end
    txWave = sixgr.util.structGet(tx, "Waveform", []);
    if ~isempty(txWave)
        [txWave, powerContext] = sixgr.rf.applyPowerContext(txWave, cfg, char(direction), txInfo);
        tx.PowerContext = powerContext; %#ok<NASGU>
    end
    sampleRateHz = localResolveCoupledTxSampleRate(tx, txInfo);
catch ME
    error("sixgr:truth:InterfererTxPrecomputeFailed", ...
        "Coupled %s interferer Tx precompute failed for signal %s: %s %s", ...
        char(direction), char(signalType), char(string(ME.identifier)), char(string(ME.message)));
end
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
tf = logical(sixgr.util.structGet(grant, "IsRetransmission", false)) || ...
    logical(sixgr.util.structGet(grant, "HARQIsRetransmission", false)) || ...
    logical(sixgr.util.structGet(grant, "HARQProcessKey.IsRetransmission", false)) || ...
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

function grant = localResolveRetransmissionGrantSnapshot(cfgIn, direction, grant, replayBits)
direction = upper(string(direction));
hasCarrier = ~isempty(sixgr.util.structGet(grant, "CarrierConfig", []));
if direction == "UL"
    hasDirectionConfig = ~isempty(sixgr.util.structGet(grant, "PUSCHConfig", []));
else
    hasDirectionConfig = ~isempty(sixgr.util.structGet(grant, "PDSCHConfig", []));
end
if ~(hasCarrier && hasDirectionConfig)
    grant = localHydrateGrantSnapshot(cfgIn, direction, grant);
end
if isfinite(replayBits) && replayBits > 0
    harq = sixgr.util.structGet(grant, "HARQ", struct());
    if ~isstruct(harq)
        harq = struct();
    end
    harq.IsRetransmission = true;
    grant.HARQ = harq;
    grant.IsRetransmission = true;
    grant.TransportBlockSize = double(replayBits);
    grant.TBSBits = double(replayBits);
    grant.TBSBytes = floor(double(replayBits) / 8);
    grant.ScheduledTransportBlockSize = double(replayBits);
    grant = localClearFrozenPHYGrantSnapshot(grant);
end
end

function grantRow = localRefreshGrantRowFromGrant(grantRow, grant, resolvedBits)
if ~(istable(grantRow) && ~isempty(grantRow) && isstruct(grant) && ~isempty(fieldnames(grant)))
    return;
end
prbSet = double(sixgr.util.structGet(grant, "PRBSet", []));
symAlloc = double(sixgr.util.structGet(grant, "SymbolAllocation", []));
tbsBits = double(sixgr.util.structGet(grant, "TransportBlockSize", sixgr.util.structGet(grant, "TBSBits", resolvedBits)));
if ~(isfinite(tbsBits) && tbsBits >= 0)
    tbsBits = resolvedBits;
end
if ismember("PRBStart", string(grantRow.Properties.VariableNames))
    grantRow.PRBStart(1) = localFirstNumeric(prbSet, NaN);
end
if ismember("PRBCount", string(grantRow.Properties.VariableNames))
    grantRow.PRBCount(1) = double(numel(prbSet));
end
if ismember("SymbolStart", string(grantRow.Properties.VariableNames))
    grantRow.SymbolStart(1) = localFirstNumeric(symAlloc, NaN);
end
if ismember("NumSymbols", string(grantRow.Properties.VariableNames))
    grantRow.NumSymbols(1) = localSecondNumeric(symAlloc, NaN);
end
if ismember("TBSBits", string(grantRow.Properties.VariableNames)) && isfinite(tbsBits)
    grantRow.TBSBits(1) = double(tbsBits);
end
if ismember("TBSBytes", string(grantRow.Properties.VariableNames)) && isfinite(tbsBits)
    grantRow.TBSBytes(1) = floor(double(tbsBits) / 8);
end
if ismember("MCSIndex", string(grantRow.Properties.VariableNames))
    grantRow.MCSIndex(1) = double(sixgr.util.structGet(grant, "MCSIndex", sixgr.util.structGet(grant, "MCS", NaN)));
end
if ismember("Modulation", string(grantRow.Properties.VariableNames))
    grantRow.Modulation(1) = string(sixgr.util.structGet(grant, "Modulation", ""));
end
if ismember("TargetCodeRate", string(grantRow.Properties.VariableNames))
    grantRow.TargetCodeRate(1) = double(sixgr.util.structGet(grant, "TargetCodeRate", NaN));
end
if ismember("NumLayers", string(grantRow.Properties.VariableNames))
    grantRow.NumLayers(1) = double(sixgr.util.structGet(grant, "NumLayers", sixgr.util.structGet(grant, "Layers", NaN)));
end
if ismember("PMI", string(grantRow.Properties.VariableNames))
    grantRow.PMI(1) = double(sixgr.util.structGet(grant, "PMI", NaN));
end
if ismember("CRI", string(grantRow.Properties.VariableNames))
    grantRow.CRI(1) = double(sixgr.util.structGet(grant, "CRI", NaN));
end
if ismember("ConfiguredBeamSelectionStrategy", string(grantRow.Properties.VariableNames))
    grantRow.ConfiguredBeamSelectionStrategy(1) = string(sixgr.util.structGet(grant, "ConfiguredBeamSelectionStrategy", ""));
end
if ismember("PrecoderSource", string(grantRow.Properties.VariableNames))
    grantRow.PrecoderSource(1) = string(sixgr.util.structGet(grant, "PrecoderSource", ""));
end
if ismember("PrecodingMode", string(grantRow.Properties.VariableNames))
    grantRow.PrecodingMode(1) = string(sixgr.util.structGet(grant, "PrecodingMode", ""));
end
if ismember("PrecodingApplicationStage", string(grantRow.Properties.VariableNames))
    grantRow.PrecodingApplicationStage(1) = string(sixgr.util.structGet(grant, "PrecodingApplicationStage", ""));
end
if ismember("PrecodingActive", string(grantRow.Properties.VariableNames))
    grantRow.PrecodingActive(1) = logical(sixgr.util.structGet(grant, "PrecodingActive", false));
end
if ismember("ExplicitBeamWeightsApplied", string(grantRow.Properties.VariableNames))
    grantRow.ExplicitBeamWeightsApplied(1) = logical(sixgr.util.structGet(grant, "ExplicitBeamWeightsApplied", false));
end
if ismember("TransformPrecodingApplied", string(grantRow.Properties.VariableNames))
    grantRow.TransformPrecodingApplied(1) = logical(sixgr.util.structGet(grant, "TransformPrecodingApplied", false));
end
if ismember("BeamformingApplied", string(grantRow.Properties.VariableNames))
    grantRow.BeamformingApplied(1) = logical(sixgr.util.structGet(grant, "BeamformingApplied", false));
end
if ismember("AppliedBeamIndexSet", string(grantRow.Properties.VariableNames))
    grantRow.AppliedBeamIndexSet(1) = string(sixgr.util.structGet(grant, "AppliedBeamIndexSet", ""));
end
if ismember("AppliedPrecoderPMI", string(grantRow.Properties.VariableNames))
    grantRow.AppliedPrecoderPMI(1) = double(sixgr.util.structGet(grant, "AppliedPrecoderPMI", NaN));
end
if ismember("AppliedPrecoderPMIType", string(grantRow.Properties.VariableNames))
    grantRow.AppliedPrecoderPMIType(1) = string(sixgr.util.structGet(grant, "AppliedPrecoderPMIType", ""));
end
if ismember("AppliedPrecoderCodebookMode", string(grantRow.Properties.VariableNames))
    grantRow.AppliedPrecoderCodebookMode(1) = string(sixgr.util.structGet(grant, "AppliedPrecoderCodebookMode", ""));
end
if ismember("PrecodingNumPorts", string(grantRow.Properties.VariableNames))
    grantRow.PrecodingNumPorts(1) = double(sixgr.util.structGet(grant, "PrecodingNumPorts", NaN));
end
if ismember("PrecodingNumLayers", string(grantRow.Properties.VariableNames))
    grantRow.PrecodingNumLayers(1) = double(sixgr.util.structGet(grant, "PrecodingNumLayers", NaN));
end
if ismember("PrecodingMatrixRows", string(grantRow.Properties.VariableNames))
    grantRow.PrecodingMatrixRows(1) = double(sixgr.util.structGet(grant, "PrecodingMatrixRows", NaN));
end
if ismember("PrecodingMatrixCols", string(grantRow.Properties.VariableNames))
    grantRow.PrecodingMatrixCols(1) = double(sixgr.util.structGet(grant, "PrecodingMatrixCols", NaN));
end
if ismember("GrantContextId", string(grantRow.Properties.VariableNames))
    grantRow.GrantContextId(1) = string(sixgr.util.structGet(grant, "GrantContextId", ""));
end
if ismember("GrantWorkerSafe", string(grantRow.Properties.VariableNames))
    grantRow.GrantWorkerSafe(1) = logical(sixgr.util.structGet(grant, "GrantWorkerSafe", true));
end
if ismember("GrantSharedStateCommitMode", string(grantRow.Properties.VariableNames))
    grantRow.GrantSharedStateCommitMode(1) = string(sixgr.util.structGet(grant, "GrantSharedStateCommitMode", "serial_coordinator_commit"));
end
if ismember("SRSGatingActive", string(grantRow.Properties.VariableNames))
    grantRow.SRSGatingActive(1) = logical(sixgr.util.structGet(grant, "SRSGatingActive", false));
end
if ismember("ControlEligible", string(grantRow.Properties.VariableNames))
    grantRow.ControlEligible(1) = logical(sixgr.util.structGet(grant, "ControlEligible", true));
end
if ismember("SchedulingEligible", string(grantRow.Properties.VariableNames))
    grantRow.SchedulingEligible(1) = logical(sixgr.util.structGet(grant, "SchedulingEligible", true));
end
if ismember("SchedulingBlockedBySRS", string(grantRow.Properties.VariableNames))
    grantRow.SchedulingBlockedBySRS(1) = logical(sixgr.util.structGet(grant, "SchedulingBlockedBySRS", false));
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
    "UCIOnPUSCHSource","HARQACKDecodeStatus","HARQACKDecodeReason", ...
    "GrantContextId","GrantSharedStateCommitMode"];
logicalFields = [ ...
    "PrecodingActive","ExplicitBeamWeightsApplied","TransformPrecodingApplied","BeamformingApplied", ...
    "UCIOnPUSCHApplied","HARQACKContentMatch","GrantWorkerSafe"];
numericFields = [ ...
    "PMI","CRI","AppliedPrecoderPMI","PrecodingNumPorts","PrecodingNumLayers", ...
    "PrecodingMatrixRows","PrecodingMatrixCols","TBSBits","TBSBytes","HARQACKBitCount"];

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

function value = localFirstNumeric(data, defaultValue)
value = defaultValue;
if nargin < 2
    value = NaN;
end
if isempty(data)
    return;
end
data = double(data(:));
idx = find(isfinite(data), 1, "first");
if ~isempty(idx)
    value = double(data(idx));
end
end

function value = localSecondNumeric(data, defaultValue)
value = defaultValue;
if nargin < 2
    value = NaN;
end
if isempty(data)
    return;
end
data = double(data(:));
data = data(isfinite(data));
if numel(data) >= 2
    value = double(data(2));
elseif numel(data) == 1
    value = double(data(1));
end
end

function grant = localResolveStrictGrantSnapshot(cfgIn, direction, grant, queueBitsUpper)
if ~(isstruct(grant) && ~isempty(fieldnames(grant)))
    return;
end
direction = upper(string(direction));
if ~(isfinite(queueBitsUpper) && queueBitsUpper > 0)
    queueBitsUpper = inf;
end
prbSet = double(sixgr.util.structGet(grant, "PRBSet", []));
if isempty(prbSet)
    nPrb = max(1, round(double(sixgr.util.structGet(grant, "PRBs", sixgr.util.structGet(cfgIn, "phy.carrier.NSizeGrid", 1)))));
    prbSet = 0:(nPrb - 1);
end
fullGrant = localHydrateGrantSnapshot(cfgIn, direction, grant);
fullBits = double(sixgr.util.structGet(fullGrant, "TransportBlockSize", ...
    sixgr.util.structGet(fullGrant, "TBSBits", NaN)));
if isfinite(fullBits) && fullBits > 0 && fullBits <= queueBitsUpper
    fullGrant.TBSBits = double(fullBits);
    fullGrant.TBSBytes = floor(double(fullBits) / 8);
    grant = fullGrant;
    return;
end
bestGrant = struct();
bestBits = -inf;
for nUse = 1:numel(prbSet)
    candidate = grant;
    candidate.PRBSet = double(prbSet(1:nUse));
    candidate.PRBs = double(numel(candidate.PRBSet));
    candidate = localHydrateGrantSnapshot(cfgIn, direction, candidate);
    candBits = double(sixgr.util.structGet(candidate, "TransportBlockSize", NaN));
    if ~(isfinite(candBits) && candBits > 0)
        continue;
    end
    if candBits > queueBitsUpper
        continue;
    end
    if candBits > bestBits
        bestGrant = candidate;
        bestBits = candBits;
    end
end
if isempty(fieldnames(bestGrant))
    bestGrant = fullGrant;
end
bestGrant.TBSBits = double(sixgr.util.structGet(bestGrant, "TransportBlockSize", sixgr.util.structGet(bestGrant, "TBSBits", NaN)));
bestGrant.TBSBytes = floor(double(bestGrant.TBSBits) / 8);
grant = bestGrant;
end

function grant = localHydrateGrantSnapshot(cfgIn, direction, grant)
originalDLPrecodingMatrix = [];
if upper(string(direction)) == "DL"
    originalDLPrecodingMatrix = sixgr.util.structGet(cfgIn, "phy.pdsch.precoding.matrix", ...
        sixgr.util.structGet(cfgIn, "phy.pdsch.precodingMatrix", ...
        sixgr.util.structGet(cfgIn, "phy.pdsch.W", [])));
end
cfgGrant = localApplyHARQGrantContext(cfgIn, direction, grant);
direction = upper(string(direction));
cfgGrant = localPrepareGrantReplayExecutionConfig(cfgGrant, direction, grant);
if direction == "UL"
    replayPRBSet = localGrantReplayPRBSet(cfgGrant, grant);
    [carrier, ~] = sixgr.phy.grid.makeCarrier(cfgGrant);
    [~, info, pusch] = sixgr.phy.grid.allocREsPUSCH(carrier, cfgGrant, ...
        "PRBSet", replayPRBSet, ...
        "SymbolAllocation", sixgr.util.structGet(grant, "SymbolAllocation", []), ...
        "Modulation", char(string(sixgr.util.structGet(grant, "Modulation", "QPSK"))), ...
        "NumLayers", double(sixgr.util.structGet(grant, "NumLayers", sixgr.util.structGet(grant, "Layers", 1))));
    nrePerPRB = localExtractGrantNREPerPRB(info, numel(pusch.PRBSet), char(string(pusch.Modulation)), double(pusch.NumLayers));
    xOverhead = double(sixgr.util.structGet(cfgGrant, "phy.pusch.xOverhead", 0));
    if isfinite(double(nrePerPRB)) && double(nrePerPRB) > 0 && ~isempty(pusch.PRBSet)
        tbsBits = double(nrTBS(char(pusch.Modulation), double(pusch.NumLayers), double(numel(pusch.PRBSet)), double(nrePerPRB), ...
            double(sixgr.util.structGet(grant, "TargetCodeRate", sixgr.util.structGet(cfgGrant, "phy.pusch.codeRate", 0.5))), double(xOverhead)));
        grant.GrantPHYDataStatus = "ok";
    else
        tbsBits = 0;
        grant.GrantPHYDataStatus = "no_data_re";
    end
    grant.CarrierConfig = carrier;
    grant.PUSCHConfig = pusch;
    grant.TransformPrecoding = logical(sixgr.util.structGet(cfgGrant, "phy.pusch.transformPrecoding", false));
    grant.XOverhead = xOverhead;
    grant.NREPerPRB = double(nrePerPRB);
    grant.NumTxAnt = double(sixgr.phy.ul.resolveULDirectionalAntennaCount(cfgGrant, "tx", NaN));
    grant.ReplayPRBOffset = double(sixgr.util.structGet(cfgGrant, "system.waveform.replayPRBOffset", 0));
    grant.ReplayGridMode = char(string(sixgr.util.structGet(cfgGrant, "system.waveform.replayGridMode", "")));
else
    rawPrecodingMatrix = originalDLPrecodingMatrix;
    replayPRBSet = localGrantReplayPRBSet(cfgGrant, grant);
    [carrier, ~] = sixgr.phy.grid.makeCarrier(cfgGrant);
    [~, info, pdsch] = sixgr.phy.grid.allocREsPDSCH(carrier, cfgGrant, ...
        "PRBSet", replayPRBSet, ...
        "SymbolAllocation", sixgr.util.structGet(grant, "SymbolAllocation", []), ...
        "Modulation", char(string(sixgr.util.structGet(grant, "Modulation", "QPSK"))), ...
        "NumLayers", double(sixgr.util.structGet(grant, "NumLayers", sixgr.util.structGet(grant, "Layers", 1))));
    nrePerPRB = localExtractGrantNREPerPRB(info, numel(pdsch.PRBSet), char(string(pdsch.Modulation)), double(pdsch.NumLayers));
    xOverhead = double(sixgr.util.structGet(cfgGrant, "phy.pdsch.xOverhead", 0));
    if isfinite(double(nrePerPRB)) && double(nrePerPRB) > 0 && ~isempty(pdsch.PRBSet)
        tbsBits = double(nrTBS(char(pdsch.Modulation), double(pdsch.NumLayers), double(numel(pdsch.PRBSet)), double(nrePerPRB), ...
            double(sixgr.util.structGet(grant, "TargetCodeRate", sixgr.util.structGet(cfgGrant, "phy.pdsch.codeRate", 0.5))), double(xOverhead)));
        grant.GrantPHYDataStatus = "ok";
    else
        tbsBits = 0;
        grant.GrantPHYDataStatus = "no_data_re";
    end
    cfgGrant = localPruneIncompatibleDLPrecodingConfig(cfgGrant, pdsch);
    [grant, cfgGrant] = localSanitizeDLGrantFeedback(cfgGrant, pdsch, grant);
    prec = sixgr.phy.dl.resolvePDSCHPrecoding(pdsch, cfgGrant);
    precActive = logical(sixgr.util.structGet(prec, "Active", false));
    precMatrix = [];
    if precActive
        precMatrix = sixgr.util.structGet(prec, "MatrixPorts", sixgr.util.structGet(prec, "MatrixNR", []));
    end
    if precActive && isempty(precMatrix)
        precMatrix = localAdaptDLPrecodingMatrix(rawPrecodingMatrix, double(pdsch.NumLayers));
    end
    if precActive && ~isempty(precMatrix)
        precMatrix = localAdaptDLPrecodingMatrix(precMatrix, double(pdsch.NumLayers));
        if isempty(precMatrix)
            error("sixgr:truth:BadGrantDLPrecodingMatrix", ...
                "DL grant hydration could not resolve a %d-layer precoder from the configured/grant matrix.", ...
                round(double(pdsch.NumLayers)));
        end
    end
    numTxAnt = localResolveDLPDSCHLogicalPortCount(cfgGrant, grant, double(pdsch.NumLayers));
    matrixPorts = localPrecodingPortCount(precMatrix, double(pdsch.NumLayers));
    if isfinite(matrixPorts) && matrixPorts ~= round(double(numTxAnt))
        if matrixPorts > localMaxNRLogicalPDSCHPorts()
            [precMatrix, precSource] = localResolveDLLogicalPrecoderFromPMI(cfgGrant, grant, double(pdsch.NumLayers), numTxAnt);
            grant.PrecoderSource = char(string(precSource));
        else
            numTxAnt = max(numTxAnt, matrixPorts);
        end
    end
    if isempty(precMatrix) && isfinite(numTxAnt) && numTxAnt >= 1 && double(pdsch.NumLayers) == 1
        precMatrix = zeros(max(1, round(numTxAnt)), 1);
        precMatrix(1, 1) = 1;
    end
    matrixPorts = localPrecodingPortCount(precMatrix, double(pdsch.NumLayers));
    if isfinite(matrixPorts) && matrixPorts ~= round(double(numTxAnt))
        if matrixPorts > localMaxNRLogicalPDSCHPorts()
            [precMatrix, precSource] = localResolveDLLogicalPrecoderFromPMI(cfgGrant, grant, double(pdsch.NumLayers), numTxAnt);
            grant.PrecoderSource = char(string(precSource));
        else
            numTxAnt = max(numTxAnt, matrixPorts);
        end
    end
    grant.CarrierConfig = carrier;
    grant.PDSCHConfig = pdsch;
    grant.XOverhead = xOverhead;
    grant.NREPerPRB = double(nrePerPRB);
    grant.NumTxAnt = double(numTxAnt);
    grant.PrecodingMatrix = precMatrix;
    grant.ConfiguredBeamSelectionStrategy = char(string(sixgr.util.structGet(cfgGrant, "lls6g.userContext.BeamSelectionStrategy", ...
        sixgr.util.structGet(grant, "ConfiguredBeamSelectionStrategy", ""))));
    grant.PrecoderSource = char(string(sixgr.util.structGet(prec, "Source", sixgr.util.structGet(grant, "PrecoderSource", "none"))));
    grant.PrecodingMode = char(string(sixgr.util.structGet(prec, "Mode", sixgr.util.structGet(grant, "PrecodingMode", "siso-bypass"))));
    grant.PrecodingApplicationStage = char(string(sixgr.util.structGet(prec, "ApplicationStage", sixgr.util.structGet(grant, "PrecodingApplicationStage", "none"))));
    grant.PrecodingActive = precActive;
    grant.ExplicitBeamWeightsApplied = precActive;
    grant.BeamformingApplied = precActive;
    grant.AppliedBeamIndexSet = char(localFormatIndexSet(sixgr.util.structGet(prec, "BeamIndices", [])));
    grant.AppliedPrecoderPMI = double(sixgr.util.structGet(prec, "PMI", NaN));
    grant.AppliedPrecoderPMIType = char(string(sixgr.util.structGet(prec, "PMIType", "")));
    grant.AppliedPrecoderCodebookMode = char(string(sixgr.util.structGet(prec, "CodebookMode", "")));
    if ~isempty(precMatrix)
        grant.PrecodingNumPorts = double(size(precMatrix, 1));
        grant.PrecodingNumLayers = double(size(precMatrix, 2));
        grant.PrecodingMatrixRows = double(size(precMatrix, 1));
        grant.PrecodingMatrixCols = double(size(precMatrix, 2));
    else
        grant.PrecodingNumPorts = double(sixgr.util.structGet(prec, "NumPorts", NaN));
        grant.PrecodingNumLayers = double(sixgr.util.structGet(prec, "NumLayers", NaN));
        grant.PrecodingMatrixRows = double(sixgr.util.structGet(prec, "MatrixRows", NaN));
        grant.PrecodingMatrixCols = double(sixgr.util.structGet(prec, "MatrixCols", NaN));
    end
    grant.ReplayPRBOffset = double(sixgr.util.structGet(cfgGrant, "system.waveform.replayPRBOffset", 0));
    grant.ReplayGridMode = char(string(sixgr.util.structGet(cfgGrant, "system.waveform.replayGridMode", "")));
end
grant.PRBSet = double(sixgr.util.structGet(grant, "PRBSet", []));
grant.PRBs = double(numel(grant.PRBSet));
grant.TransportBlockSize = double(tbsBits);
grant.TBSBits = double(tbsBits);
grant.TBSBytes = floor(max(double(tbsBits), 0) / 8);
end

function cfgOut = localPrepareGrantReplayExecutionConfig(cfgIn, direction, grant)
cfgOut = cfgIn;
direction = upper(string(direction));
numLayers = double(sixgr.util.structGet(grant, "NumLayers", sixgr.util.structGet(grant, "Layers", NaN)));
if ~(isfinite(numLayers) && numLayers >= 1)
    numLayers = 1;
end

txAnt = localGrantReplayTxAntennas(cfgOut, direction, grant, numLayers);
rxAnt = localGrantReplayRxAntennas(cfgOut, direction, grant, numLayers);
cfgOut = sixgr.util.structSet(cfgOut, "phy.nTxAnt", txAnt);
cfgOut = sixgr.util.structSet(cfgOut, "phy.nRxAnt", rxAnt);
cfgOut = sixgr.util.structSet(cfgOut, "channel.nTxAnt", txAnt);
cfgOut = sixgr.util.structSet(cfgOut, "channel.nRxAnt", rxAnt);

if direction == "UL"
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pusch.numLayers", numLayers);
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pusch.nLayers", numLayers);
else
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.numLayers", numLayers);
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.nLayers", numLayers);
end

cfgOut = localAlignGrantReplayCarrier(cfgOut, grant);
replayPRBSet = localGrantReplayPRBSet(cfgOut, grant);
if direction == "UL"
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pusch.prbSet", replayPRBSet);
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pusch.nPRB", numel(replayPRBSet));
else
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.prbSet", replayPRBSet);
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.nPRB", numel(replayPRBSet));
end
end

function cfgOut = localAlignGrantReplayCarrier(cfgIn, grant)
cfgOut = cfgIn;
prbSet = double(sixgr.util.structGet(grant, "PRBSet", []));
prbOffset = 0;
requiredNSizeGrid = NaN;
useGrantLocalGrid = logical(sixgr.util.structGet(cfgOut, "system.waveform.useGrantLocalGrid", false));
if ~isempty(prbSet)
    prbSet = unique(prbSet(isfinite(prbSet) & prbSet >= 0));
    if ~isempty(prbSet)
        if useGrantLocalGrid
            prbOffset = min(prbSet);
            requiredNSizeGrid = max(prbSet) - prbOffset + 1;
        else
            requiredNSizeGrid = max(prbSet) + 1;
        end
    end
end
if ~(isfinite(requiredNSizeGrid) && requiredNSizeGrid >= 1)
    nprb = double(sixgr.util.structGet(grant, "NPRB", NaN));
    if isfinite(nprb) && nprb >= 1
        requiredNSizeGrid = round(nprb);
    end
end
if ~(isfinite(requiredNSizeGrid) && requiredNSizeGrid >= 1)
    return;
end
currentNSizeGrid = double(sixgr.util.structGet(cfgOut, "phy.carrier.NSizeGrid", NaN));
if ~(isfinite(currentNSizeGrid) && currentNSizeGrid >= 1)
    currentNSizeGrid = requiredNSizeGrid;
end
if useGrantLocalGrid
    cfgOut = sixgr.util.structSet(cfgOut, "phy.carrier.NSizeGrid", max(1, round(requiredNSizeGrid)));
    cfgOut = sixgr.util.structSet(cfgOut, "phy.carrier.NStartGrid", max(0, round(double(sixgr.util.structGet(cfgOut, "phy.carrier.NStartGrid", 0))) + round(prbOffset)));
    cfgOut = sixgr.util.structSet(cfgOut, "system.waveform.replayPRBOffset", double(prbOffset));
    cfgOut = sixgr.util.structSet(cfgOut, "system.waveform.replayGridMode", "grant_allocation");
else
    cfgOut = sixgr.util.structSet(cfgOut, "phy.carrier.NSizeGrid", max(round(currentNSizeGrid), round(requiredNSizeGrid)));
    cfgOut = sixgr.util.structSet(cfgOut, "phy.carrier.NStartGrid", max(0, round(double(sixgr.util.structGet(cfgOut, "phy.carrier.NStartGrid", 0)))));
    cfgOut = sixgr.util.structSet(cfgOut, "system.waveform.replayPRBOffset", 0);
    cfgOut = sixgr.util.structSet(cfgOut, "system.waveform.replayGridMode", "full_carrier");
end
end

function prbSet = localGrantReplayPRBSet(cfgIn, grant)
prbSet = double(unique(sixgr.util.structGet(grant, "PRBSet", [])));
prbSet = prbSet(isfinite(prbSet) & prbSet >= 0);
offset = double(sixgr.util.structGet(cfgIn, "system.waveform.replayPRBOffset", 0));
if isfinite(offset) && offset > 0
    prbSet = prbSet - offset;
end
prbSet = prbSet(isfinite(prbSet) & prbSet >= 0);
if isempty(prbSet)
    nGrid = max(1, round(double(sixgr.util.structGet(cfgIn, "phy.carrier.NSizeGrid", 1))));
    prbSet = 0:(nGrid - 1);
end
end

function n = localGrantReplayTxAntennas(cfgIn, direction, grant, numLayers)
direction = upper(string(direction));
if direction == "UL"
    explicit = localFirstFiniteNumeric( ...
        sixgr.util.structGet(grant, "NumTxAnt", NaN), ...
        sixgr.util.structGet(cfgIn, "channel.ul.nTxAnt", NaN), ...
        sixgr.util.structGet(cfgIn, "phy.ul.nTxAnt", NaN), ...
        sixgr.util.structGet(cfgIn, "scenario.ue.nTxAnt", NaN), ...
        sixgr.util.structGet(cfgIn, "channel.nTxAnt", NaN), ...
        sixgr.util.structGet(cfgIn, "phy.nTxAnt", NaN));
    n = localApplyGrantReplayAntennaCap(cfgIn, explicit, numLayers);
else
    explicit = localFirstFiniteNumeric( ...
        sixgr.util.structGet(grant, "PrecodingNumPorts", NaN), ...
        sixgr.util.structGet(grant, "NumTxAnt", NaN), ...
        sixgr.util.structGet(cfgIn, "channel.nTxAnt", NaN), ...
        sixgr.util.structGet(cfgIn, "phy.nTxAnt", NaN), ...
        sixgr.util.structGet(cfgIn, "scenario.bs.nTxAnt", NaN));
    explicitAtLeastRank = localFirstFiniteAtLeastNumeric(numLayers, ...
        sixgr.util.structGet(grant, "PrecodingNumPorts", NaN), ...
        sixgr.util.structGet(grant, "NumTxAnt", NaN), ...
        sixgr.util.structGet(cfgIn, "channel.nTxAnt", NaN), ...
        sixgr.util.structGet(cfgIn, "phy.nTxAnt", NaN), ...
        sixgr.util.structGet(cfgIn, "scenario.bs.nTxAnt", NaN));
    if isfinite(explicitAtLeastRank)
        explicit = explicitAtLeastRank;
    end
    n = localApplyGrantReplayAntennaCap(cfgIn, explicit, numLayers);
end
end

function n = localGrantReplayRxAntennas(cfgIn, direction, grant, numLayers)
direction = upper(string(direction));
if direction == "UL"
    explicit = localFirstFiniteNumeric( ...
        sixgr.util.structGet(cfgIn, "channel.ul.nRxAnt", NaN), ...
        sixgr.util.structGet(cfgIn, "phy.ul.nRxAnt", NaN), ...
        sixgr.util.structGet(cfgIn, "scenario.bs.nRxAnt", NaN), ...
        sixgr.util.structGet(cfgIn, "scenario.bs.nTxAnt", NaN), ...
        sixgr.util.structGet(cfgIn, "channel.nRxAnt", NaN), ...
        sixgr.util.structGet(cfgIn, "phy.nRxAnt", NaN));
    n = localApplyGrantReplayAntennaCap(cfgIn, explicit, numLayers);
else
    explicit = localFirstFiniteNumeric( ...
        sixgr.util.structGet(cfgIn, "scenario.ue.nRxAnt", NaN), ...
        sixgr.util.structGet(cfgIn, "channel.nRxAnt", NaN), ...
        sixgr.util.structGet(cfgIn, "phy.nRxAnt", NaN));
    n = localApplyGrantReplayAntennaCap(cfgIn, explicit, numLayers);
end
end

function n = localApplyGrantReplayAntennaCap(cfgIn, explicitValue, numLayers)
n = max(1, round(double(localFirstFiniteNumeric(explicitValue, numLayers))));
if logical(sixgr.util.structGet(cfgIn, "system.waveform.capReplayAntennasToLayers", false))
    n = max(1, min(n, max(1, round(double(numLayers)))));
end
end

function value = localFirstFiniteNumeric(varargin)
value = NaN;
for i = 1:nargin
    candidate = double(varargin{i});
    candidate = candidate(isfinite(candidate));
    if ~isempty(candidate)
        value = candidate(1);
        return;
    end
end
end

function value = localFirstFiniteAtLeastNumeric(minValue, varargin)
value = NaN;
minValue = max(1, round(double(minValue)));
for i = 1:nargin-1
    candidate = double(varargin{i});
    candidate = candidate(isfinite(candidate) & candidate >= minValue);
    if ~isempty(candidate)
        value = double(candidate(1));
        return;
    end
end
end

function nPorts = localResolveDLPDSCHLogicalPortCount(cfg, grant, nLayers)
nLayers = max(1, round(double(nLayers)));
nPorts = localFirstFiniteAtLeastNumeric(nLayers, ...
    sixgr.util.structGet(cfg, "phy.maxDLLayers", NaN), ...
    sixgr.util.structGet(cfg, "phy.pdsch.maxLayers", NaN), ...
    sixgr.util.structGet(cfg, "phy.pdsch.dmrs.nPorts", NaN), ...
    sixgr.util.structGet(cfg, "phy.pdsch.numPorts", NaN), ...
    sixgr.util.structGet(cfg, "phy.pdsch.nPorts", NaN), ...
    sixgr.util.structGet(cfg, "phy.pdsch.NumAntennaPorts", NaN), ...
    sixgr.util.structGet(cfg, "phy.pdsch.numAntennaPorts", NaN), ...
    sixgr.util.structGet(cfg, "phy.pdsch.numLayers", NaN), ...
    sixgr.util.structGet(cfg, "phy.pdsch.nLayers", NaN));
if isfinite(nPorts) && nPorts > localMaxNRLogicalPDSCHPorts()
    nPorts = NaN;
end
if ~(isfinite(nPorts) && nPorts >= nLayers)
    grantPorts = localFirstFiniteAtLeastNumeric(nLayers, ...
        sixgr.util.structGet(grant, "NumLogicalPorts", NaN), ...
        sixgr.util.structGet(grant, "PortCount", NaN));
    if isfinite(grantPorts) && grantPorts <= localMaxNRLogicalPDSCHPorts()
        nPorts = grantPorts;
    end
end
if ~(isfinite(nPorts) && nPorts >= nLayers)
    nPorts = nLayers;
end
nPorts = max(nLayers, round(double(nPorts)));
end

function nPorts = localMaxNRLogicalPDSCHPorts()
nPorts = 32;
end

function [W, source] = localResolveDLLogicalPrecoderFromPMI(cfg, grant, nLayers, nPorts)
nLayers = max(1, round(double(nLayers)));
nPorts = max(nLayers, round(double(nPorts)));
source = "logical_identity_from_element_domain_precoder";
W = eye(nPorts, nLayers);
pmi = localFirstFiniteNumeric( ...
    sixgr.util.structGet(grant, "AppliedPrecoderPMI", NaN), ...
    sixgr.util.structGet(grant, "PMI", NaN), ...
    sixgr.util.structGet(grant, "TPMI", NaN), ...
    sixgr.util.structGet(cfg, "phy.pdsch.PMI", NaN), ...
    sixgr.util.structGet(cfg, "phy.pdsch.pmi", NaN), ...
    sixgr.util.structGet(cfg, "phy.pdsch.TPMI", NaN), ...
    sixgr.util.structGet(cfg, "phy.pdsch.tpmi", NaN));
mode = char(string(sixgr.util.structGet(grant, "AppliedPrecoderCodebookMode", ...
    sixgr.util.structGet(grant, "PMICodebookMode", ...
    sixgr.util.structGet(cfg, "phy.csi.pmiCodebookMode", "type1_su_mimo")))));
if strlength(strtrim(string(mode))) == 0
    mode = "type1_su_mimo";
end
try
    [candidates, ~] = sixgr.phy.dl.pmiCodebookCandidates(cfg, nLayers, nPorts, "Mode", mode);
    if isempty(candidates)
        return;
    end
    idx = 1;
    if isfinite(pmi)
        pmi0 = round(double(pmi));
        if pmi0 >= 0 && pmi0 < numel(candidates)
            idx = pmi0 + 1;
        end
    end
    Wcand = double(candidates(idx).W);
    if isequal(size(Wcand), [nPorts nLayers])
        W = Wcand;
        source = "logical_pmi_codebook_from_element_domain_precoder";
    end
catch
    % Leave the identity logical precoder. The element-domain matrix cannot
    % define NR waveform ports without explicit hybrid element-domain TX.
end
end

function token = localFormatIndexSet(values)
if isstring(values) || ischar(values)
    token = string(values);
    return;
end
values = double(values(:).');
values = values(isfinite(values));
if isempty(values)
    token = "";
    return;
end
token = join(string(round(values)), "|");
end

function token = localFormatNumericVector(values)
if isstring(values) || ischar(values)
    token = string(values);
    return;
end
values = double(values(:).');
values = values(isfinite(values));
if isempty(values)
    token = "";
    return;
end
parts = strings(1, numel(values));
for ii = 1:numel(values)
    parts(ii) = string(sprintf("%.6g", values(ii)));
end
token = join(parts, "|");
end

function cfgOut = localPruneIncompatibleDLPrecodingConfig(cfgIn, pdsch)
cfgOut = cfgIn;
nLayers = double(sixgr.util.structGet(pdsch, "NumLayers", 1));
if ~(isfinite(nLayers) && nLayers >= 1)
    nLayers = 1;
end
paths = ["phy.pdsch.precoding.matrix", "phy.pdsch.precodingMatrix", "phy.pdsch.W"];
expectedPorts = localResolveDLPDSCHLogicalPortCount(cfgOut, struct(), nLayers);
resolvedPorts = NaN;
for i = 1:numel(paths)
    path = paths(i);
    Wcfg = sixgr.util.structGet(cfgOut, path, []);
    if isempty(Wcfg)
        continue;
    end
    Wcfg = localAdaptDLPrecodingMatrix(Wcfg, nLayers);
    if isempty(Wcfg)
        cfgOut = sixgr.util.structSet(cfgOut, path, []);
        continue;
    end
    nPorts = localPrecodingPortCount(Wcfg, nLayers);
    if isfinite(expectedPorts) && expectedPorts >= 1 && nPorts ~= round(double(expectedPorts))
        cfgOut = sixgr.util.structSet(cfgOut, path, []);
        continue;
    end
    cfgOut = sixgr.util.structSet(cfgOut, path, Wcfg);
    resolvedPorts = nPorts;
end
if isfinite(resolvedPorts) && resolvedPorts >= max(1, round(double(nLayers)))
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.numPorts", resolvedPorts);
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.nPorts", resolvedPorts);
elseif isfinite(expectedPorts) && expectedPorts >= max(1, round(double(nLayers)))
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.numPorts", round(double(expectedPorts)));
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.nPorts", round(double(expectedPorts)));
end
end

function [grantOut, cfgOut] = localSanitizeDLGrantFeedback(cfgIn, pdsch, grantIn)
grantOut = grantIn;
cfgOut = cfgIn;

nLayers = max(1, round(double(sixgr.util.structGet(pdsch, "NumLayers", ...
    sixgr.util.structGet(grantOut, "NumLayers", sixgr.util.structGet(grantOut, "Layers", 1))))));
numTxPorts = localResolveDLPDSCHLogicalPortCount(cfgOut, grantOut, nLayers);
explicitMatrix = sixgr.util.structGet(cfgOut, "phy.pdsch.precoding.matrix", ...
    sixgr.util.structGet(cfgOut, "phy.pdsch.precodingMatrix", ...
    sixgr.util.structGet(cfgOut, "phy.pdsch.W", [])));
pmi = double(sixgr.util.structGet(grantOut, "PMI", ...
    sixgr.util.structGet(cfgOut, "phy.pdsch.PMI", ...
    sixgr.util.structGet(cfgOut, "phy.pdsch.TPMI", ...
    sixgr.util.structGet(cfgOut, "phy.pdsch.tpmi", NaN)))));
try
    candidates = sixgr.phy.dl.pmiCodebookCandidates(cfgOut, nLayers, numTxPorts);
    needsDefaultPMI = isempty(explicitMatrix) && ~isempty(candidates) && (~isfinite(pmi) || pmi < 0 || pmi >= numel(candidates));
    if needsDefaultPMI
        if localStrictTruthMode(cfgOut)
            grantOut.PMI = NaN;
            grantOut.PMIResolutionStatus = "missing_csi_pmi_no_strict_default";
            grantOut.PrecoderSource = "pmi_unavailable_strict_truth";
            cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.PMI", []);
            cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.TPMI", []);
            cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.tpmi", []);
        else
            grantOut.PMI = 0;
            grantOut.PMIResolutionStatus = "legacy_non_strict_default_pmi";
            cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.PMI", 0);
            cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.TPMI", 0);
            cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.tpmi", 0);
        end
    elseif isempty(candidates) && isfinite(pmi)
        grantOut.PMI = NaN;
        cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.PMI", []);
        cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.TPMI", []);
        cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.tpmi", []);
    end
catch
    if isempty(explicitMatrix)
        grantOut.PMI = NaN;
        cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.PMI", []);
        cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.TPMI", []);
        cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.tpmi", []);
    end
end

cri = double(sixgr.util.structGet(grantOut, "CRI", NaN));
if isfinite(cri)
    numCandidates = sixgr.util.structGet(cfgOut, "phy.csi.numResourceCandidates", ...
        sixgr.util.structGet(cfgOut, "phy.csirs.numResources", ...
        sixgr.util.structGet(cfgOut, "phy.beamManagement.trpCount", 1)));
    numCandidates = max(1, round(double(numCandidates)));
    if cri < 0 || cri >= numCandidates
        grantOut.CRI = NaN;
        cfgOut = sixgr.util.structSet(cfgOut, "phy.beamManagement.selectedCRI", []);
        cfgOut = sixgr.util.structSet(cfgOut, "phy.csi.selectedCRI", []);
    end
end
end

function tf = localStrictTruthMode(cfg)
tf = logical(sixgr.util.structGet(cfg, "run.strictMode", false)) || ...
    logical(sixgr.util.structGet(cfg, "run.noProxyTruthContract", false)) || ...
    lower(strtrim(string(sixgr.util.structGet(cfg, "run.honestyMode", "")))) == "strict";
end

function tf = localGrantCarriesActiveDLPrecoding(grant, Wcfg)
tf = false;
if ~(isstruct(grant) && ~isempty(fieldnames(grant))) || isempty(Wcfg)
    return;
end
mode = lower(strtrim(string(sixgr.util.structGet(grant, "PrecodingMode", ""))));
source = lower(strtrim(string(sixgr.util.structGet(grant, "PrecoderSource", ""))));
stage = lower(strtrim(string(sixgr.util.structGet(grant, "PrecodingApplicationStage", ""))));
active = logical(sixgr.util.structGet(grant, "PrecodingActive", false));
beamApplied = logical(sixgr.util.structGet(grant, "BeamformingApplied", false));
explicitApplied = logical(sixgr.util.structGet(grant, "ExplicitBeamWeightsApplied", false));
tf = active || beamApplied || explicitApplied || ...
    (strlength(mode) > 0 && mode ~= "siso-bypass" && mode ~= "none") || ...
    (strlength(source) > 0 && source ~= "none" && source ~= "siso-bypass") || ...
    (strlength(stage) > 0 && stage ~= "none");
end

function Wout = localAdaptDLPrecodingMatrix(Wcfg, nLayers)
Wout = [];
if isempty(Wcfg)
    return;
end
nLayers = max(1, round(double(nLayers)));
sz = size(Wcfg);
if ndims(Wcfg) > 2 && sz(3) == 1
    Wcfg = squeeze(Wcfg);
    sz = size(Wcfg);
end
if ndims(Wcfg) > 2 || numel(sz) < 2
    return;
end
if sz(2) >= nLayers
    Wout = double(Wcfg(:, 1:nLayers));
    elseif sz(1) == nLayers && sz(2) >= nLayers
    % Accept the documented transposed convention Nlayers-by-Nports only
    % when the row count exactly matches the requested layer count.  A stale
    % Nports-by-1 rank-1 beam must not be reshaped into a rank-2 precoder.
    Wout = double(Wcfg.');
end
if ~isempty(Wout) && size(Wout, 1) < nLayers
    Wout = [];
    return;
end
if ~isempty(Wout)
    colNorm = sqrt(sum(abs(Wout).^2, 1));
    colNorm(colNorm <= eps) = 1;
    Wout = Wout ./ colNorm;
end
end

function nPorts = localPrecodingPortCount(Wcfg, nLayers)
nPorts = 0;
if isempty(Wcfg)
    return;
end
nLayers = max(1, round(double(nLayers)));
sz = size(Wcfg);
if ndims(Wcfg) > 2 && sz(3) == 1
    Wcfg = squeeze(Wcfg);
    sz = size(Wcfg);
end
if ndims(Wcfg) > 2 || numel(sz) < 2
    return;
end
if sz(2) == nLayers
    nPorts = sz(1);
elseif sz(1) == nLayers
    nPorts = sz(2);
end
end

function nrePerPRB = localExtractGrantNREPerPRB(info, nPRB, modStr, nLayers)
[nrePerPRB, ~] = sixgr.util.resolveDataNREPerPRB(info, nPRB, modStr, nLayers);
end

function bits = localGenerateGrantTransportBlockBits(cfgIn, grant, direction, nBits)
nBits = max(0, round(double(nBits)));
if nBits < 1
    bits = int8([]);
    return;
end
seedBase = double(sixgr.util.structGet(cfgIn, "run.seed", 1));
seed = mod(seedBase + 53 * round(double(sixgr.util.structGet(grant, "RNTI", 1))) + 7919 * round(double(sixgr.util.structGet(grant, "Slot", 1))) + sum(double(char(upper(string(direction))))), 2^31 - 1);
rs = RandStream("mt19937ar", "Seed", max(1, round(seed)));
bits = int8(randi(rs, [0 1], nBits, 1));
end

function cfgOut = localApplyHARQGrantContext(cfgIn, direction, grant)
cfgOut = cfgIn;
if ~(isstruct(grant) && ~isempty(fieldnames(grant)))
    return;
end
direction = upper(string(direction));
if direction == "UL"
    root = "phy.pusch";
else
    root = "phy.pdsch";
end
grantMCS = double(sixgr.util.structGet(grant, "MCS", sixgr.util.structGet(grant, "MCSIndex", NaN)));
grantMod = string(sixgr.util.structGet(grant, "Modulation", ""));
grantRate = double(sixgr.util.structGet(grant, "TargetCodeRate", NaN));
grantLayers = double(sixgr.util.structGet(grant, "Layers", sixgr.util.structGet(grant, "NumLayers", NaN)));
grantPRBs = double(sixgr.util.structGet(grant, "PRBs", numel(double(sixgr.util.structGet(grant, "PRBSet", [])))));
grantPRBSet = sixgr.util.structGet(grant, "PRBSet", []);
grantSymbolAllocation = sixgr.util.structGet(grant, "SymbolAllocation", []);
grantMappingType = string(sixgr.util.structGet(grant, "MappingType", ""));
grantTransformPrecoding = sixgr.util.structGet(grant, "TransformPrecoding", []);
grantPMI = double(sixgr.util.structGet(grant, "PMI", NaN));
grantCRI = double(sixgr.util.structGet(grant, "CRI", NaN));
grantMCSTable = string(sixgr.util.structGet(grant, "MCSTable", ""));
grantCQITable = string(sixgr.util.structGet(grant, "CQITable", ""));
if isfinite(grantMCS)
    cfgOut = sixgr.util.structSet(cfgOut, root + ".mcsIndex", grantMCS);
end
if strlength(strtrim(grantMod)) > 0
    cfgOut = sixgr.util.structSet(cfgOut, root + ".modulation", char(grantMod));
end
if isfinite(grantRate) && grantRate > 0
    cfgOut = sixgr.util.structSet(cfgOut, root + ".codeRate", grantRate);
end
if isfinite(grantLayers) && grantLayers >= 1
    cfgOut = sixgr.util.structSet(cfgOut, root + ".numLayers", grantLayers);
    cfgOut = sixgr.util.structSet(cfgOut, root + ".nLayers", grantLayers);
end
if isfinite(grantPRBs) && grantPRBs >= 1
    cfgOut = sixgr.util.structSet(cfgOut, root + ".nPRB", grantPRBs);
end
if ~isempty(grantPRBSet)
    cfgOut = sixgr.util.structSet(cfgOut, root + ".prbSet", grantPRBSet);
end
if ~isempty(grantSymbolAllocation)
    cfgOut = sixgr.util.structSet(cfgOut, root + ".symbolAllocation", grantSymbolAllocation);
end
if strlength(strtrim(grantMappingType)) > 0
    cfgOut = sixgr.util.structSet(cfgOut, root + ".mappingType", char(grantMappingType));
end
if ~isempty(grantTransformPrecoding) && direction == "UL"
    cfgOut = sixgr.util.structSet(cfgOut, root + ".transformPrecoding", logical(grantTransformPrecoding));
end
if strlength(strtrim(grantMCSTable)) > 0
    cfgOut = sixgr.util.structSet(cfgOut, root + ".mcsTable", char(grantMCSTable));
end
if strlength(strtrim(grantCQITable)) > 0
    cfgOut = sixgr.util.structSet(cfgOut, root + ".cqiTable", char(grantCQITable));
end
if direction == "DL"
    if isfinite(grantLayers) && grantLayers >= 1
        cfgOut = localPruneIncompatibleDLPrecodingConfigForLayers(cfgOut, grantLayers);
    end
    if isfinite(grantPMI)
        cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.PMI", grantPMI);
    end
    if isfinite(grantCRI)
        cfgOut = sixgr.util.structSet(cfgOut, "phy.beamManagement.selectedCRI", grantCRI);
        cfgOut = sixgr.util.structSet(cfgOut, "phy.csi.selectedCRI", grantCRI);
    end
elseif direction == "UL"
    if isfinite(grantPMI)
        cfgOut = sixgr.util.structSet(cfgOut, "phy.pusch.PMI", grantPMI);
        cfgOut = sixgr.util.structSet(cfgOut, "phy.pusch.TPMI", grantPMI);
    end
end
end

function cfgOut = localPruneIncompatibleDLPrecodingConfigForLayers(cfgIn, nLayers)
cfgOut = cfgIn;
nLayers = max(1, round(double(nLayers)));
paths = ["phy.pdsch.precoding.matrix", "phy.pdsch.precodingMatrix", "phy.pdsch.W"];
expectedPorts = localResolveDLPDSCHLogicalPortCount(cfgOut, struct(), nLayers);
resolvedPorts = NaN;
for i = 1:numel(paths)
    path = paths(i);
    Wcfg = sixgr.util.structGet(cfgOut, path, []);
    if isempty(Wcfg)
        continue;
    end
    Wcfg = localAdaptDLPrecodingMatrix(Wcfg, nLayers);
    if isempty(Wcfg)
        cfgOut = sixgr.util.structSet(cfgOut, path, []);
        continue;
    end
    nPorts = localPrecodingPortCount(Wcfg, nLayers);
    if ~(isfinite(nPorts) && nPorts >= nLayers) || ...
            (isfinite(expectedPorts) && expectedPorts >= 1 && nPorts ~= round(double(expectedPorts)))
        cfgOut = sixgr.util.structSet(cfgOut, path, []);
        continue;
    end
    cfgOut = sixgr.util.structSet(cfgOut, path, Wcfg);
    resolvedPorts = nPorts;
end
if isfinite(resolvedPorts) && resolvedPorts >= nLayers
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.numPorts", resolvedPorts);
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.nPorts", resolvedPorts);
end
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
partition = sixgr.util.resolveTDDSlotPartition(cfg, canonicalSlot);
allowDL = logical(partition.AllowDL);
allowUL = logical(partition.AllowUL);
slotLabel = string(partition.SlotLabel);
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

function [cfgU, state] = localApplyCoupledRuntimeUserContext(cfgIn, state, ueIdx, direction)
[cfgU, state] = sixgr.truth.CoupledTruthRuntime.applyUserContext(cfgIn, state, ueIdx, direction);
end

function context = localResolveCoupledHARQTrialContext(state, ueIdx, direction)
context = sixgr.truth.CoupledTruthRuntime.resolveHARQTrialContext(state, ueIdx, direction);
end

function [state, trialT] = localCompleteCoupledRuntimeSlot(state, cfgU, ueIdx, direction, trialT, res)
[state, trialT] = sixgr.truth.CoupledTruthRuntime.completeSlot(state, cfgU, ueIdx, direction, trialT, res);
end

function state = localWriteCoupledRuntimeTables(state, runFolder)
state = sixgr.truth.CoupledTruthRuntime.writeTables(state, runFolder);
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
            rnti = double(localUserRNTI(stateWorker.MultiUser, ueIdx));
            cfgU = userCfgWorker{ueIdx};
            tempState = stateWorker;
            [cfgU, tempState] = localApplyCoupledRuntimeUserContext(cfgU, tempState, ueIdx, "DL"); %#ok<ASGLU>
            cfgU = localApplyPBCHSSBBeamContext(cfgU, slotIdx, ueIdx);
            trialCache{ueIdx} = localAnnotateCoupledControlTrial( ...
                localCollectPBCHTrials(cfgU, double(snr_dB), 1), ...
                slotIdx, frameIdx, ueIdx, rnti, "DL");
        end
    end
catch ME
    trialCache = cell(numUsers, 1);
    localAppendRuntimeLog("WARN", ...
        "Coupled PBCH control gating parfor precompute unavailable; falling back to serial PBCH trials: %s %s", ...
        char(string(ME.identifier)), char(string(ME.message)));
end
end

function state = localRunCoupledPreSchedulingControlGating(state, cfg, runFolder, userCfg, snr_dB)
state = sixgr.truth.CoupledTruthRuntime.refreshControlState(state);
numUsers = numel(userCfg);
slotIdx = double(sixgr.util.structGet(state, "CurrentSlot", NaN));
frameIdx = double(sixgr.util.structGet(state, "CurrentFrame", NaN));
slotDLAllowed = logical(sixgr.util.structGet(state, "CurrentSlotDLAllowed", true)) && ...
    double(sixgr.util.structGet(state, "CurrentSlotDLNumSymbols", 0)) > 0;
slotULAllowed = logical(sixgr.util.structGet(state, "CurrentSlotULAllowed", true)) && ...
    double(sixgr.util.structGet(state, "CurrentSlotULNumSymbols", 0)) > 0;
pbchPeriod = max(1, round(double(sixgr.util.structGet(state, "PBCHSlotPeriod", 20))));
prachPeriod = max(1, round(double(sixgr.util.structGet(cfg, "phy.prach.period_slots", pbchPeriod))));
srsPeriod = max(1, round(double(sixgr.util.structGet(state, "SRSSlotPeriod", 4))));
srsMaxUEsPerSlot = max(1, round(double(sixgr.util.structGet(cfg, "phy.srs.maxUEsPerSlot", 1))));
srsSchedulingPolicy = lower(strtrim(string(sixgr.util.structGet(cfg, "phy.srs.schedulingPolicy", "round_robin_phase"))));
trsEnabled = logical(sixgr.util.structGet(cfg, "phy.trs.enable", false));
trsPeriod = max(1, round(double(sixgr.util.structGet(state, "TRSSlotPeriod", 4))));
prachRequired = logical(sixgr.util.structGet(state.ControlGating, "PRACHRequired", false));
prachEnabled = logical(sixgr.util.structGet(cfg, "phy.prach.enable", false));
shouldAttemptTRS = trsEnabled && slotDLAllowed && (double(sixgr.util.structGet(state, "LastTRSSlot", 0)) <= 0 || ...
    slotIdx <= 1 || (isfinite(slotIdx) && (slotIdx - double(sixgr.util.structGet(state, "LastTRSSlot", 0))) >= trsPeriod));
prachSignalOpportunityThisSlot = prachEnabled && slotULAllowed && localIsActivePRACHOccasion(cfg, slotIdx);
prachOccasionActiveThisSlot = prachRequired && prachSignalOpportunityThisSlot;
sharedPBCHEligible = false(numUsers, 1);
if logical(sixgr.util.structGet(state.ControlGating, "PBCHRequired", false)) && slotDLAllowed
    pbchStateAll = string(sixgr.util.structGet(state, "CellAcquisitionState", strings(numUsers, 1)));
    sharedPBCHEligible = pbchStateAll ~= "acquired";
end
trsObservedServingCells = [];
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
    "Phase", "starting", ...
    "Notes", sprintf("Starting coupled pre-scheduling control gating for slot %s/%s with %d UEs.", ...
        localDisplayProgressValue(slotIdx), localDisplayProgressValue(double(sixgr.util.structGet(state, "CanonicalSlotsPerSweepPoint", NaN))), round(double(numUsers)))));
pbchTrialCache = localPrecomputePBCHControlGatingTrials(state, cfg, userCfg, sharedPBCHEligible, slotIdx, frameIdx, snr_dB, slotDLAllowed);
for ueIdx = 1:numUsers
    rnti = double(localUserRNTI(state.MultiUser, ueIdx));
    cfgU = userCfg{ueIdx};
    tempState = state;
    [cfgU, tempState] = localApplyCoupledRuntimeUserContext(cfgU, tempState, ueIdx, "DL"); %#ok<ASGLU>
    servingCell = double(sixgr.util.structGet(tempState, "CurrentServingIdx", nan(numUsers, 1)));
    if numel(servingCell) >= ueIdx
        servingCell = double(servingCell(ueIdx));
    else
        servingCell = NaN;
    end

    if shouldAttemptTRS && isfinite(servingCell) && servingCell >= 1 && ~ismember(servingCell, trsObservedServingCells)
        trsSNR_dB = localResolveCoupledRuntimeLinkSNR(state, cfgU, ueIdx, "DL", snr_dB);
        trsT = localAnnotateCoupledControlTrial(localCollectTRSTrials(cfgU, trsSNR_dB, 1), slotIdx, frameIdx, ueIdx, rnti, "DL");
        if istable(trsT) && ~isempty(trsT)
            trsAttemptCount = trsAttemptCount + 1;
            state = sixgr.truth.CoupledTruthRuntime.applyTRSTrial(state, servingCell, trsT);
            trsStates = string(sixgr.util.structGet(state, "TRSValidityStateByCell", strings(0, 1)));
            trackingEligibility = logical(sixgr.util.structGet(state, "TrackingEligibilityByCell", false(0, 1)));
            lastTRSSuccess = double(sixgr.util.structGet(state, "LastSuccessfulTRSSlotByCell", nan(0, 1)));
            lastTRSDoppler = double(sixgr.util.structGet(state, "LastEstimatedTRSDopplerHzByCell", nan(0, 1)));
            trsStateToken = "unknown";
            trackingEligible = false;
            lastTRSSlot = NaN;
            trackedDoppler = NaN;
            if servingCell <= numel(trsStates)
                trsStateToken = string(trsStates(servingCell));
            end
            if servingCell <= numel(trackingEligibility)
                trackingEligible = logical(trackingEligibility(servingCell));
            end
            if servingCell <= numel(lastTRSSuccess)
                lastTRSSlot = double(lastTRSSuccess(servingCell));
            end
            if servingCell <= numel(lastTRSDoppler)
                trackedDoppler = double(lastTRSDoppler(servingCell));
            end
            trsContext = sixgr.truth.CoupledTruthRuntime.resolveTRSRuntimeContextRuntime(state, cfgU, ueIdx, servingCell);
            trsT.ServingCell = repmat(servingCell, height(trsT), 1);
            trsT.TraceRole = repmat("runtime_shared_receiver_tracking_state_update", height(trsT), 1);
            trsT.TRSGatingActive = repmat(logical(sixgr.util.structGet(state.ControlGating, "TRSRequired", false)), height(trsT), 1);
            trsT.TRSValidityState = repmat(trsStateToken, height(trsT), 1);
            trsT.TrackingEligibility = repmat(trackingEligible, height(trsT), 1);
            trsT.LastSuccessfulTRSSlot = repmat(lastTRSSlot, height(trsT), 1);
            trsT.LastEstimatedTRSDopplerHz = repmat(trackedDoppler, height(trsT), 1);
            trsT.TRSAgeSlots = repmat(double(sixgr.truth.CoupledTruthRuntime.trsAgeSlotsRuntime(state, servingCell)), height(trsT), 1);
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
            trsObservedServingCells(end + 1, 1) = servingCell; %#ok<AGROW>
        end
    end

    if logical(sixgr.util.structGet(state.ControlGating, "PBCHRequired", false)) && slotDLAllowed
        shouldAttemptPBCH = ueIdx <= numel(sharedPBCHEligible) && sharedPBCHEligible(ueIdx);
        if shouldAttemptPBCH
            pbchT = table();
            if ueIdx <= numel(pbchTrialCache) && istable(pbchTrialCache{ueIdx}) && ~isempty(pbchTrialCache{ueIdx})
                pbchT = pbchTrialCache{ueIdx};
            end
            if isempty(pbchT)
                pbchSNR_dB = localResolveCoupledRuntimeLinkSNR(state, cfgU, ueIdx, "DL", snr_dB);
                cfgU = localApplyPBCHSSBBeamContext(cfgU, slotIdx, ueIdx);
                pbchT = localAnnotateCoupledControlTrial(localCollectPBCHTrials(cfgU, pbchSNR_dB, 1), slotIdx, frameIdx, ueIdx, rnti, "DL");
            end
            pbchAttemptCount = pbchAttemptCount + 1;
            state.ControlTrials.PBCH = localAppendCompatTable(state.ControlTrials.PBCH, pbchT);
            state = sixgr.truth.CoupledTruthRuntime.applyPBCHTrial(state, ueIdx, pbchT);
        end
    end

    if prachSignalOpportunityThisSlot
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
            shouldAttemptPRACH = shouldAttemptPRACH && pbchAcquired && isfinite(lastPbchSuccess) && slotIdx > lastPbchSuccess;
            shouldAttemptPRACH = shouldAttemptPRACH && prachOccasionActiveThisSlot;
        else
            lastAttempt = 0;
            if ueIdx <= numel(lastPrachAttempt)
                lastAttempt = double(lastPrachAttempt(ueIdx));
            end
            shouldAttemptPRACH = ~isfinite(lastAttempt) || lastAttempt <= 0;
        end
        if shouldAttemptPRACH
            [cfgU, tempState] = localApplyCoupledRuntimeUserContext(cfgU, tempState, ueIdx, "UL"); %#ok<ASGLU>
            cfgU = localApplyDeterministicPrachUserContext(cfgU, ueIdx);
            prachSNR_dB = localResolveCoupledRuntimeLinkSNR(state, cfgU, ueIdx, "UL", snr_dB);
            [prachRawT, prachCorrT, prachRAEvidenceT] = localCollectPRACHTrials(cfgU, prachSNR_dB, 1, slotIdx);
            prachT = localAnnotateCoupledControlTrial(prachRawT, slotIdx, frameIdx, ueIdx, rnti, "UL");
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
            prachCorrT = localAnnotateCoupledControlTrial(prachCorrT, slotIdx, frameIdx, ueIdx, rnti, "UL");
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
    srsGatingActive = logical(sixgr.util.structGet(state.ControlGating, "SRSRequired", false));
    if srsEnabled && slotULAllowed
        accessState = string(sixgr.util.structGet(state, "AccessState", strings(numUsers,1)));
        lastSRSAttempt = double(sixgr.util.structGet(state, "LastSRSSlotByUE", zeros(numUsers,1)));
        lastSuccessfulPRACH = double(sixgr.util.structGet(state, "LastSuccessfulPRACHSlotByUE", nan(numUsers,1)));
        lastAttempt = 0;
        if ueIdx <= numel(lastSRSAttempt)
            lastAttempt = double(lastSRSAttempt(ueIdx));
        end
        shouldAttemptSRS = ~isfinite(lastAttempt) || lastAttempt == 0 || (isfinite(slotIdx) && (slotIdx - lastAttempt) >= srsPeriod);
        accessSucceeded = ueIdx <= numel(accessState) && accessState(ueIdx) == "succeeded";
        lastPrachSuccess = NaN;
        if ueIdx <= numel(lastSuccessfulPRACH)
            lastPrachSuccess = double(lastSuccessfulPRACH(ueIdx));
        end
        if srsGatingActive
            shouldAttemptSRS = shouldAttemptSRS && accessSucceeded && isfinite(lastPrachSuccess) && slotIdx > lastPrachSuccess;
        end
        srsResourceOpportunity = localCoupledSRSResourceOpportunity( ...
            cfg, slotIdx, ueIdx, numUsers, srsPeriod, srsSchedulingPolicy, srsMaxUEsPerSlot);
        shouldAttemptSRS = shouldAttemptSRS && srsResourceOpportunity && srsScheduledThisSlot < srsMaxUEsPerSlot;
        if shouldAttemptSRS
            [cfgSRSU, tempState] = localApplyCoupledRuntimeUserContext(cfgU, tempState, ueIdx, "UL"); %#ok<ASGLU>
            srsSNR_dB = localResolveCoupledRuntimeLinkSNR(state, cfgSRSU, ueIdx, "UL", snr_dB);
            if ~isfield(state, "SRSChannelStateByUE") || numel(state.SRSChannelStateByUE) < ueIdx
                state.SRSChannelStateByUE{ueIdx, 1} = [];
            end
            [srsRawT, srsChState] = localCollectSRSTrials( ...
                cfgSRSU, srsSNR_dB, 1, state.SRSChannelStateByUE{ueIdx}, slotIdx);
            state.SRSChannelStateByUE{ueIdx, 1} = srsChState;
            srsT = localAnnotateCoupledControlTrial(srsRawT, slotIdx, frameIdx, ueIdx, rnti, "UL");
            srsAttemptCount = srsAttemptCount + 1;
            srsScheduledThisSlot = srsScheduledThisSlot + 1;
            state.ControlTrials.SRS = localAppendCompatTable(state.ControlTrials.SRS, srsT);
            state = sixgr.truth.CoupledTruthRuntime.applySRSTrial(state, ueIdx, srsT);
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
trsValidByCell = string(sixgr.util.structGet(state, "TRSValidityStateByCell", strings(0, 1))) == "valid";
trsValidCellCount = sum(trsValidByCell);
trackingEligibilityByCell = logical(sixgr.util.structGet(state, "TrackingEligibilityByCell", false(0, 1)));
trackedServingUserCount = 0;
servingVec = double(sixgr.util.structGet(state, "CurrentServingIdx", nan(numUsers, 1)));
for ueIdx = 1:numUsers
    if ueIdx <= numel(servingVec)
        servingCell = round(double(servingVec(ueIdx)));
        if isfinite(servingCell) && servingCell >= 1 && servingCell <= numel(trackingEligibilityByCell) && trackingEligibilityByCell(servingCell)
            trackedServingUserCount = trackedServingUserCount + 1;
        end
    end
end
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
slotIdx = double(sixgr.util.structGet(state, "CurrentSlot", NaN));
totalSlots = double(sixgr.util.structGet(state, "CanonicalSlotsPerSweepPoint", NaN));
completedFrames = double(sixgr.util.structGet(state, "CurrentFrameLocal", sixgr.util.structGet(state, "CurrentFrame", NaN)));
totalFrames = double(sixgr.util.structGet(state, "FramesPerSweepPoint", NaN));
runCompletion = NaN;
if isfinite(totalSlots) && totalSlots > 0 && isfinite(slotIdx)
    runCompletion = min(max(double(slotIdx) / double(totalSlots), 0), 1);
elseif isfinite(totalFrames) && totalFrames > 0 && isfinite(completedFrames)
    runCompletion = min(max(double(completedFrames) / double(totalFrames), 0), 1);
end
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
    "Notes", char(notes)));
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

function tf = localIsActivePRACHOccasion(cfg, slotIdx)
tf = false;
if ~(isfinite(double(slotIdx)) && double(slotIdx) >= 1)
    return;
end
validSlots1 = double(sixgr.util.structGet(cfg, "phy.prach.validSlots1Based", []));
validSlots1 = validSlots1(isfinite(validSlots1) & validSlots1 >= 1);
if ~isempty(validSlots1)
    slotsPerFrame = double(sixgr.util.structGet(cfg, "phy.numerology.slotsPerFrame", ...
        sixgr.util.structGet(cfg, "frame_timing.slots_per_frame", max(validSlots1))));
    slotsPerFrame = max(1, round(double(slotsPerFrame)));
    canonicalSlotInFrame = mod(round(double(slotIdx)) - 1, slotsPerFrame) + 1;
    if ~ismember(canonicalSlotInFrame, round(validSlots1(:).'))
        return;
    end
else
    try
        fs = sixgr.phy.FrameStructureEngine(cfg);
        if ~fs.IsPRACHSlot(slotIdx)
            return;
        end
    catch
        partition = sixgr.util.resolveTDDSlotPartition(cfg, slotIdx);
        if ~(logical(partition.AllowUL) && ~logical(partition.IsSpecialSlot))
            return;
        end
    end
end
carrierSlot = max(0, round(double(slotIdx)) - 1);
try
    [tx, info] = sixgr.phy.ul.PRACH_Tx(cfg, "NPRACHSlot", carrierSlot);
    tf = logical(sixgr.util.structGet(info, "ActiveOccasionPresent", false)) && ...
        ~isempty(sixgr.util.structGet(tx, "Waveform", []));
catch
    tf = false;
end
end

function [state, qualifiedGrants] = localQualifyCoupledGrantsWithPDCCH(state, userCfg, grants, direction, snr_dB)
qualifiedGrants = repmat(struct(), 0, 1);
direction = upper(string(direction));
if ~(isstruct(grants) && ~isempty(grants))
    return;
end
pdcchRequired = logical(sixgr.util.structGet(state.ControlGating, "PDCCHRequired", false));
slotDLControlAllowed = logical(sixgr.util.structGet(state, "CurrentSlotDLAllowed", true)) && ...
    double(sixgr.util.structGet(state, "CurrentSlotDLNumSymbols", 0)) > 0;
pdcchCCEUsedByResource = containers.Map('KeyType', 'char', 'ValueType', 'double');
pdcchCCEBudgetByResource = containers.Map('KeyType', 'char', 'ValueType', 'double');
for gi = 1:numel(grants)
    grant = grants(gi);
    ueIdx = localResolveGrantUEIndex(grant, state.MultiUser);
    if ~(isfinite(ueIdx) && ueIdx >= 1 && ueIdx <= numel(userCfg))
        continue;
    end
    cfgU = userCfg{ueIdx};
    tempState = state;
    [cfgU, tempState] = localApplyCoupledRuntimeUserContext(cfgU, tempState, ueIdx, direction); %#ok<ASGLU>
    slotIdx = double(sixgr.util.structGet(grant, "Slot", sixgr.util.structGet(state, "CurrentSlot", NaN)));
    frameIdx = double(sixgr.util.structGet(grant, "Frame", sixgr.util.structGet(state, "CurrentFrame", NaN)));
    controlSlotIdx = double(sixgr.util.structGet(grant, "ControlSlot", sixgr.util.structGet(state, "CurrentSlot", slotIdx)));
    controlFrameIdx = double(sixgr.util.structGet(grant, "ControlFrame", sixgr.util.structGet(state, "CurrentFrame", frameIdx)));
    rnti = double(sixgr.util.structGet(grant, "RNTI", localUserRNTI(state.MultiUser, ueIdx)));
    if ~slotDLControlAllowed
        if pdcchRequired
            [state, grant] = sixgr.truth.CoupledTruthRuntime.blockPDCCHGrantTrial( ...
                state, grant, direction, "control_blocked_no_dl_control_symbols_in_tdd_slot");
            state = sixgr.truth.CoupledTruthRuntime.cancelUnexecutedHARQGrantRuntime(state, grant, direction);
        else
            grant.PDCCHGatingActive = false;
            grant.ControlDecodeOk = true;
            grant.GrantControlState = "control_not_required_no_dl_control_symbols_in_tdd_slot";
            if isempty(qualifiedGrants)
                qualifiedGrants = grant;
            else
                [qualifiedGrants, grant] = localHarmonizeStructArrays(qualifiedGrants, grant);
                qualifiedGrants(end + 1, 1) = grant; %#ok<AGROW>
            end
        end
        continue;
    end
    pdcchSNR_dB = localResolveCoupledRuntimeLinkSNR(state, cfgU, ueIdx, "DL", snr_dB);
    plannedAggLevel = localResolveGrantPDCCHAggregationLevelForCapacity(cfgU, pdcchSNR_dB, grant);
    controlResourceKey = localPDCCHControlResourceKey(grant, controlFrameIdx, controlSlotIdx);
    pdcchCCEUsedThisSlot = localMapGetDouble(pdcchCCEUsedByResource, controlResourceKey, 0);
    pdcchCCEBudgetThisSlot = localMapGetDouble(pdcchCCEBudgetByResource, controlResourceKey, NaN);
    cfgCCEBudget = localResolvePDCCHCCEBudgetFromConfig(cfgU);
    if ~isfinite(pdcchCCEBudgetThisSlot) && isfinite(cfgCCEBudget)
        pdcchCCEBudgetThisSlot = cfgCCEBudget;
        localMapSetDouble(pdcchCCEBudgetByResource, controlResourceKey, pdcchCCEBudgetThisSlot);
    end
    if pdcchRequired && isfinite(plannedAggLevel) && isfinite(pdcchCCEBudgetThisSlot) && ...
            (pdcchCCEUsedThisSlot + plannedAggLevel) > pdcchCCEBudgetThisSlot
        reason = "control_blocked_coreset_cce_capacity_exhausted";
        [state, grant] = sixgr.truth.CoupledTruthRuntime.blockPDCCHGrantTrial(state, grant, direction, reason);
        state = sixgr.truth.CoupledTruthRuntime.cancelUnexecutedHARQGrantRuntime(state, grant, direction);
        pdcchT = localBuildPDCCHCapacityBlockedTrial(cfgU, pdcchSNR_dB, plannedAggLevel, ...
            pdcchCCEBudgetThisSlot, pdcchCCEUsedThisSlot, reason);
        pdcchT = localAnnotateCoupledControlTrial(pdcchT, controlSlotIdx, controlFrameIdx, ueIdx, rnti, direction);
        pdcchT = localAnnotateGrantControlTrial(pdcchT, grant);
        state.ControlTrials.PDCCH = localAppendCompatTable(state.ControlTrials.PDCCH, pdcchT);
        continue;
    end
    if localPDCCHPreAttachAssumptionApplies(state, cfgU, ueIdx, controlSlotIdx)
        grant.PDCCHGatingActive = true;
        grant.ControlDecodeOk = true;
        grant.ControlEligible = true;
        grant.GrantControlState = "pre_attach_assumed_ok_no_trial_in_warmup";
        grant.CellAcquisitionState = "pre_attach_assumed_ok";
        grant.AccessState = "pre_attach_assumed_ok";
        grant.PDCCHControlEvidenceSource = "run.controlGating.preAttachUEsBeforeMeasurement";
        if isfield(state, "LastPDCCHStatus") && ueIdx <= numel(state.LastPDCCHStatus)
            state.LastPDCCHStatus(ueIdx) = "pre_attach_assumed_ok_no_trial_in_warmup";
        end
        if isfield(state, "LastSuccessfulPDCCHSlotByUE") && ueIdx <= numel(state.LastSuccessfulPDCCHSlotByUE)
            state.LastSuccessfulPDCCHSlotByUE(ueIdx) = controlSlotIdx;
        end
        state = sixgr.truth.CoupledTruthRuntime.updateGrantControlTrace(state, grant, direction);
        if isempty(qualifiedGrants)
            qualifiedGrants = grant;
        else
            [qualifiedGrants, grant] = localHarmonizeStructArrays(qualifiedGrants, grant);
            qualifiedGrants(end + 1, 1) = grant; %#ok<AGROW>
        end
        continue;
    end
    pdcchT = localAnnotateCoupledControlTrial(localCollectPDCCHTrials(cfgU, pdcchSNR_dB, 1, grant), controlSlotIdx, controlFrameIdx, ueIdx, rnti, direction);
    attemptedCCEs = localTrialTableScalar(pdcchT, "UsedCCECount", plannedAggLevel);
    attemptedBudget = localTrialTableScalar(pdcchT, "AvailableCCECount", pdcchCCEBudgetThisSlot);
    if isfinite(attemptedBudget)
        pdcchCCEBudgetThisSlot = attemptedBudget;
        localMapSetDouble(pdcchCCEBudgetByResource, controlResourceKey, pdcchCCEBudgetThisSlot);
    end
    if pdcchRequired && isfinite(attemptedCCEs) && attemptedCCEs > 0
        pdcchCCEUsedThisSlot = pdcchCCEUsedThisSlot + attemptedCCEs;
        localMapSetDouble(pdcchCCEUsedByResource, controlResourceKey, pdcchCCEUsedThisSlot);
    end
    [state, grant, allowExecution] = sixgr.truth.CoupledTruthRuntime.applyPDCCHGrantTrial(state, grant, direction, pdcchT);
    pdcchT = localAnnotateGrantControlTrial(pdcchT, grant);
    state.ControlTrials.PDCCH = localAppendCompatTable(state.ControlTrials.PDCCH, pdcchT);
    if ~allowExecution
        state = sixgr.truth.CoupledTruthRuntime.cancelUnexecutedHARQGrantRuntime(state, grant, direction);
    end
    if allowExecution
        if isempty(qualifiedGrants)
            qualifiedGrants = grant;
        else
            [qualifiedGrants, grant] = localHarmonizeStructArrays(qualifiedGrants, grant);
            qualifiedGrants(end + 1, 1) = grant; %#ok<AGROW>
        end
    end
end
end

function tf = localPDCCHPreAttachAssumptionApplies(state, cfgU, ueIdx, controlSlotIdx)
tf = false;
if ~logical(sixgr.util.structGet(state.ControlGating, "PDCCHRequired", false))
    return;
end
if ~logical(sixgr.util.structGet(state.ControlGating, "PreAttachUEsBeforeMeasurement", ...
        sixgr.util.structGet(cfgU, "run.controlGating.preAttachUEsBeforeMeasurement", false)))
    return;
end
warmupSlots = double(sixgr.util.structGet(cfgU, "run.warmupSlots", ...
    sixgr.util.structGet(cfgU, "run_control.warmup_slots", 0)));
if ~(isfinite(warmupSlots) && warmupSlots >= 0)
    warmupSlots = 0;
end
if ~(isfinite(controlSlotIdx) && controlSlotIdx >= warmupSlots)
    return;
end
lastSlot = NaN;
if isfield(state, "LastSuccessfulPDCCHSlotByUE") && ueIdx <= numel(state.LastSuccessfulPDCCHSlotByUE)
    lastSlot = double(state.LastSuccessfulPDCCHSlotByUE(ueIdx));
end
tf = ~(isfinite(lastSlot) && lastSlot >= 0 && lastSlot < warmupSlots);
end

function state = localCollectCanonicalCoupledControlTrials(state, cfgU, ueIdx, direction, snr_dB, trialT)
direction = upper(string(direction));
if ~(istable(trialT) && ~isempty(trialT))
    return;
end
rnti = double(localUserRNTI(state.MultiUser, ueIdx));
slotIdx = localTrialTableScalar(trialT, "Slot", double(sixgr.util.structGet(state, "CurrentSlot", NaN)));
frameIdx = localTrialTableScalar(trialT, "Frame", double(sixgr.util.structGet(state, "CurrentFrame", NaN)));
slotDLAllowed = logical(sixgr.util.structGet(state, "CurrentSlotDLAllowed", true)) && ...
    double(sixgr.util.structGet(state, "CurrentSlotDLNumSymbols", 0)) > 0;
slotULAllowed = logical(sixgr.util.structGet(state, "CurrentSlotULAllowed", true)) && ...
    double(sixgr.util.structGet(state, "CurrentSlotULNumSymbols", 0)) > 0;
if direction == "DL"
    if ~slotDLAllowed
        return;
    end
    state.ControlTrials.PDCCH = localAppendCompatTable(state.ControlTrials.PDCCH, ...
        localAnnotateCoupledControlTrial(localCollectPDCCHTrials(cfgU, snr_dB, 1), slotIdx, frameIdx, ueIdx, rnti, direction));
    pbchPeriod = max(1, round(double(sixgr.util.structGet(state, "PBCHSlotPeriod", 20))));
    lastPBCHSlot = double(sixgr.util.structGet(state, "LastPBCHSlot", 0));
    if lastPBCHSlot <= 0 || slotIdx == 1 || (isfinite(slotIdx) && (slotIdx - lastPBCHSlot) >= pbchPeriod)
        cfgU = localApplyPBCHSSBBeamContext(cfgU, slotIdx, ueIdx);
        state.ControlTrials.PBCH = localAppendCompatTable(state.ControlTrials.PBCH, ...
            localAnnotateCoupledControlTrial(localCollectPBCHTrials(cfgU, snr_dB, 1), slotIdx, frameIdx, ueIdx, rnti, direction));
        state.LastPBCHSlot = slotIdx;
    end
    trsPeriod = max(1, round(double(sixgr.util.structGet(state, "TRSSlotPeriod", 4))));
    lastTRSSlot = double(sixgr.util.structGet(state, "LastTRSSlot", 0));
    if lastTRSSlot <= 0 || slotIdx == 1 || (isfinite(slotIdx) && (slotIdx - lastTRSSlot) >= trsPeriod)
        state.ControlTrials.TRS = localAppendCompatTable(state.ControlTrials.TRS, ...
            localAnnotateCoupledControlTrial(localCollectTRSTrials(cfgU, snr_dB, 1), slotIdx, frameIdx, ueIdx, rnti, direction));
        state.LastTRSSlot = slotIdx;
    end
else
    if ~slotULAllowed
        return;
    end
    lastPRACH = double(sixgr.util.structGet(state, "LastPRACHSlotByUE", zeros(max(1, ueIdx), 1)));
    if ueIdx > numel(lastPRACH) || lastPRACH(ueIdx) == 0
        cfgU = localApplyDeterministicPrachUserContext(cfgU, ueIdx);
        prachSNR_dB = localResolveCoupledRuntimeLinkSNR(state, cfgU, ueIdx, "UL", snr_dB);
        [prachRawT, prachCorrT, prachRAEvidenceT] = localCollectPRACHTrials(cfgU, prachSNR_dB, 1, slotIdx);
        state.ControlTrials.PRACH = localAppendCompatTable(state.ControlTrials.PRACH, ...
            localAnnotateCoupledControlTrial(prachRawT, slotIdx, frameIdx, ueIdx, rnti, direction));
        state.ControlTrials.PRACHCorrelationTrace = localAppendCompatTable( ...
            sixgr.util.structGet(state.ControlTrials, "PRACHCorrelationTrace", table()), ...
            localAnnotateCoupledControlTrial(prachCorrT, slotIdx, frameIdx, ueIdx, rnti, direction));
        state.ControlTrials.RAEvidenceTables = localAppendRAEvidenceTables( ...
            sixgr.util.structGet(state.ControlTrials, "RAEvidenceTables", struct()), prachRAEvidenceT);
        if ueIdx > numel(state.LastPRACHSlotByUE)
            state.LastPRACHSlotByUE(ueIdx, 1) = 0;
        end
        state.LastPRACHSlotByUE(ueIdx) = slotIdx;
    end
    lastSRS = double(sixgr.util.structGet(state, "LastSRSSlotByUE", zeros(max(1, ueIdx), 1)));
    srsPeriod = max(1, round(double(sixgr.util.structGet(state, "SRSSlotPeriod", 4))));
    if ueIdx > numel(lastSRS) || lastSRS(ueIdx) == 0 || (isfinite(slotIdx) && (slotIdx - lastSRS(ueIdx)) >= srsPeriod)
        [cfgSRSU, state] = localApplyCoupledRuntimeUserContext(cfgU, state, ueIdx, "UL");
        srsSNR_dB = localResolveCoupledRuntimeLinkSNR(state, cfgSRSU, ueIdx, "UL", snr_dB);
        if ~isfield(state, "SRSChannelStateByUE") || numel(state.SRSChannelStateByUE) < ueIdx
            state.SRSChannelStateByUE{ueIdx, 1} = [];
        end
        [srsRawT, srsChState] = localCollectSRSTrials( ...
            cfgSRSU, srsSNR_dB, 1, state.SRSChannelStateByUE{ueIdx}, slotIdx);
        state.SRSChannelStateByUE{ueIdx, 1} = srsChState;
        state.ControlTrials.SRS = localAppendCompatTable(state.ControlTrials.SRS, ...
            localAnnotateCoupledControlTrial(srsRawT, slotIdx, frameIdx, ueIdx, rnti, direction));
        if ueIdx > numel(state.LastSRSSlotByUE)
            state.LastSRSSlotByUE(ueIdx, 1) = 0;
        end
        state.LastSRSSlotByUE(ueIdx) = slotIdx;
    end
end
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

function linkSNR_dB = localResolveCoupledRuntimeLinkSNR(state, cfg, ueIdx, direction, fallbackSNR_dB)
direction = upper(string(direction));
cfgEval = cfg;
if ~(isstruct(cfgEval) && ~isempty(fieldnames(cfgEval)))
    cfgEval = sixgr.util.structGet(state, "CfgMobility", struct());
end
if localUsesReceiverNoiseMeasurement(cfgEval, struct())
    linkSNR_dB = NaN;
else
    linkSNR_dB = double(fallbackSNR_dB);
end
if ~(isfinite(double(ueIdx)) && ueIdx >= 1)
    return;
end

feedback = sixgr.truth.CoupledTruthRuntime.latestFeedbackForDirectionRuntime(state, ueIdx, direction);
feedbackSINR_dB = double(sixgr.util.structGet(feedback, "SINR_dB", NaN));
if logical(sixgr.util.structGet(feedback, "Valid", false)) && isfinite(feedbackSINR_dB)
    linkSNR_dB = double(feedbackSINR_dB);
    return;
end

pendingT = sixgr.util.structGet(state, "PendingCSITable", table());
if istable(pendingT) && ~isempty(pendingT) && ...
        all(ismember(["UEIndex", "Direction", "SINR_dB"], string(pendingT.Properties.VariableNames)))
    pendingMask = isfinite(double(pendingT.UEIndex)) & ...
        double(pendingT.UEIndex) == double(ueIdx) & ...
        upper(string(pendingT.Direction)) == direction & ...
        isfinite(double(pendingT.SINR_dB));
    if any(pendingMask)
        pendingSlice = pendingT(pendingMask, :);
        if ismember("SourceSlot", string(pendingSlice.Properties.VariableNames))
            [~, order] = sort(double(pendingSlice.SourceSlot), "descend");
            pendingSlice = pendingSlice(order, :);
        end
        linkSNR_dB = double(pendingSlice.SINR_dB(1));
        return;
    end
end

servingVec = double(sixgr.util.structGet(state, "CurrentServingIdx", []));
servingCell = NaN;
if ueIdx <= numel(servingVec)
    servingCell = double(servingVec(ueIdx));
end
largeScaleSINR_dB = localEstimateCoupledRuntimeLargeScaleSINR(state, ueIdx, servingCell);
if isfinite(largeScaleSINR_dB)
    linkSNR_dB = double(largeScaleSINR_dB);
    return;
end
interferenceMode = string(sixgr.util.structGet(cfgEval, "run.interferenceExecutionMode", ...
    sixgr.util.structGet(cfgEval, "interference.inter_cell_execution_mode", "")));
if strlength(strtrim(interferenceMode)) > 0 && isfinite(servingCell)
    estimatedSINR_dB = sixgr.truth.CoupledTruthRuntime.estimateRuntimeWidebandSINRRuntime(state, ueIdx, servingCell, interferenceMode);
    if isfinite(estimatedSINR_dB)
        linkSNR_dB = double(estimatedSINR_dB);
        return;
    end
end

runState = sixgr.util.structGet(state, "RunState", struct());
representativeSNR_dB = double(sixgr.util.structGet(runState, "CurrentSNR_dB", NaN));
valueRole = string(sixgr.util.structGet(runState, "ValueRole", ""));
if isfinite(representativeSNR_dB) && ~contains(lower(valueRole), "configured")
    linkSNR_dB = double(representativeSNR_dB);
end
end

function sinr_dB = localEstimateCoupledRuntimeLargeScaleSINR(state, ueIdx, servingCell)
sinr_dB = NaN;
ueIdx = double(ueIdx);
servingCell = double(servingCell);
largeScale = sixgr.util.structGet(state, "LargeScaleState", struct());
rxPower = sixgr.util.structGet(largeScale, "RxPower_dBm", []);
if isempty(rxPower) || ~(isfinite(ueIdx) && ueIdx >= 1) || ~(isfinite(servingCell) && servingCell >= 1)
    return;
end
rxPower = double(rxPower);
if ueIdx > size(rxPower, 1) || servingCell > size(rxPower, 2)
    return;
end
bandwidthHz = double(sixgr.util.structGet(state, "Bandwidth_Hz", NaN));
noiseFigure_dB = double(sixgr.util.structGet(state, "NoiseFigure_dB", NaN));
if ~(isfinite(bandwidthHz) && bandwidthHz > 0 && isfinite(noiseFigure_dB))
    return;
end
rxPowerRow = double(rxPower(ueIdx, :));
desired_dBm = double(rxPowerRow(servingCell));
desired_mW = 10.^(desired_dBm / 10);
interfererMask = true(size(rxPowerRow));
interfererMask(servingCell) = false;
interferer_mW = 10.^(rxPowerRow(interfererMask) / 10);
interferer_mW = interferer_mW(isfinite(interferer_mW) & interferer_mW >= 0);
noise_dBm = -174 + 10 * log10(max(bandwidthHz, eps)) + noiseFigure_dB;
noise_mW = 10.^(noise_dBm / 10);
denom_mW = sum(interferer_mW, "omitnan") + noise_mW;
if isfinite(desired_mW) && desired_mW > 0 && isfinite(denom_mW) && denom_mW > 0
    sinr_dB = 10 * log10(desired_mW / denom_mW);
end
end

function T = localAnnotateCoupledControlTrial(T, slotIdx, frameIdx, ueIdx, rnti, direction)
if ~istable(T)
    T = table();
    return;
end
n = height(T);
if n < 1
    return;
end
if ismember("Frame", string(T.Properties.VariableNames))
    T.Frame(:) = double(frameIdx);
else
    T.Frame = repmat(double(frameIdx), n, 1);
end
if ismember("Slot", string(T.Properties.VariableNames))
    T.Slot(:) = double(slotIdx);
else
    T.Slot = repmat(double(slotIdx), n, 1);
end
if ~ismember("UEIndex", string(T.Properties.VariableNames))
    T.UEIndex = repmat(double(ueIdx), n, 1);
end
if ~ismember("RNTI", string(T.Properties.VariableNames))
    T.RNTI = repmat(double(rnti), n, 1);
end
if ~ismember("Direction", string(T.Properties.VariableNames))
    T.Direction = repmat(string(direction), n, 1);
end
T.TrialDirection = repmat(string(direction), n, 1);
T.LinkDirection = repmat(string(direction), n, 1);
T.GrantDirection = repmat(string(direction), n, 1);
end

function rawTrials = localBuildCoupledTruthRawTrialsAggregate(dlTrials, ulTrials, multiUser, controlTrials)
if nargin < 4 || ~isstruct(controlTrials)
    controlTrials = struct();
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
    "MultiUserDL", localBuildDirectionUserSummaryFromRaw(dlTrials, "DL", multiUser, struct()), ...
    "MultiUserUL", localBuildDirectionUserSummaryFromRaw(ulTrials, "UL", multiUser, struct()));
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
        "HARQCurrentDecodeOK", "HARQCombinedDecodeOK", "HARQCombiningApplied", "HARQLLRCombiningGain_dB", ...
        "HARQPreviousLLRCount", "HARQCurrentLLRCount", "HARQCombinedLLRCount"}, ...
    "TimelineName", { ...
        "HarqID", "NDI", "RV", "IsRetransmission", "FeedbackDueSlot", ...
        "CurrentDecodeOK", "CombinedDecodeOK", "HARQCombiningApplied", "LLRCombiningGain_dB", ...
        "PreviousLLRCount", "CurrentLLRCount", "CombinedLLRCount"}, ...
    "IsLogical", { ...
        false, false, false, true, false, ...
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
        row.Throughput_Mbps = localAggregateBitRateFromTrials(slice, cfg, "GoodBits", observedDuration_s);
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
opt = localResolveLivePublishOptions(varargin{:});
liveArtifacts = struct("Beam", struct(), "Energy", struct(), "IQImpairment", struct(), "LiveDerived", struct(), "HARQ", struct());
signalDirection = upper(string(direction));
meta = struct( ...
    "Direction", char(signalDirection), ...
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
    "Notes", sprintf("Coupled truth streaming %s slot %d/%d for UE %d/%d at receiver-noise operating point label %d/%d (%.3f dB, not a measured SINR). MeasuredTrialSINR_dB and ReceiverHestSINR_dB carry the live waveform/receiver SINR evidence when available.", ...
        char(signalDirection), round(double(frameIdx)), round(double(totalFrames)), round(double(ueIdx)), round(double(totalUsers)), ...
        round(double(sweepIdx)), round(double(sweepCount)), double(snr_dB)));

refreshHeavyArtifacts = localShouldRefreshHeavyLiveArtifacts(cfg, meta);
writeRawTablesNow = logical(opt.WriteRawTables) && localShouldWriteLiveRawTables(cfg, meta, refreshHeavyArtifacts);
if writeRawTablesNow
    rawTrials = localForceDirectionalRawTrialArtifacts(rawTrials);
    sixgr.util.csvWriteTable(dlTablePath, sixgr.util.structGet(rawTrials, "DL", table()));
    sixgr.util.csvWriteTable(ulTablePath, sixgr.util.structGet(rawTrials, "UL", table()));
    if strlength(string(dlConstellationPath)) > 0 && istable(dlConstT) && ~isempty(dlConstT)
        sixgr.util.csvWriteTable(dlConstellationPath, localDownsampleConstellationTable(dlConstT, 2500));
    end
    if strlength(string(ulConstellationPath)) > 0 && istable(ulConstT) && ~isempty(ulConstT)
        sixgr.util.csvWriteTable(ulConstellationPath, localDownsampleConstellationTable(ulConstT, 2500));
    end
end

rootRunFolder = fileparts(char(string(runFolder)));
if localShouldMirrorCoupledRuntimeTables(cfg, opt, meta, refreshHeavyArtifacts, writeRawTablesNow)
    runtimeState = localWriteCoupledRuntimeTables(runtimeState, rootRunFolder);
end
if refreshHeavyArtifacts
    rawTrials = localForceDirectionalRawTrialArtifacts(rawTrials);
    mergedSignalTrials = localAppendCompatTable( ...
        sixgr.util.structGet(rawTrials, "DL", table()), ...
        sixgr.util.structGet(rawTrials, "UL", table()));
    mergedSignalConst = localAppendCompatTable(dlConstT, ulConstT);
    sixgr.truth.exportLLSLiveSignalChainTables(rootRunFolder, mergedSignalTrials, mergedSignalConst, struct( ...
        "WaveformPreviewTable", waveformPreviewT));
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
        notes = notes + " Heavy live raw-table, signal-chain, runtime-table, and derived artifact refresh deferred until the next configured slot-complete milestone.";
        meta = localMergeLiveMeta(meta, struct("Notes", notes));
    else
        notes = string(sixgr.util.structGet(meta, "Notes", ""));
        notes = notes + " Pre-schedule progress update only; raw trial and heavy derived artifacts remain unchanged until executable grants commit.";
        meta = localMergeLiveMeta(meta, struct("Notes", notes));
    end
    localPublishWaveformBundleStageStatus(runFolder, localBuildLightweightLiveStageStatus(rawTrials, meta));
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

function [T, summaryT, constT, csirsT] = localCollectMultiUserLinkTrialsAcrossSweep(cfg, multiUser, direction, nTrials, snrGrid, liveTablePath, liveConstellationPath, progressLabel)
T = localEmptyLinkTrialTable(0);
constT = table();
csirsT = table();
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
    [Ti, Si, Ci, Csi] = localCollectMultiUserLinkTrials(cfg, multiUser, direction, nTrials, double(snrGrid(i)), livePublisher);
    T = localAppendCompatTable(T, Ti);
    constT = localAppendCompatTable(constT, Ci);
    csirsT = localAppendCompatTable(csirsT, Csi);
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

function T = localCollectTrialsAcrossSweep(collectorFcn, snrGrid, liveTablePath, progressLabel)
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
    T = localAppendCompatTable(T, Ti);
    localMaybeWritePartialTable(liveTablePath, T);
    localMaybeAppendSweepProgressLog(progressLabel, double(snrGrid(i)), i, numel(snrGrid), T);
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
sixgr.util.csvWriteTable(pathOut, T);
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
if ~(isstruct(opt) && localIsMySQLWebMode(cfg))
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
rawTrials = localForceDirectionalRawTrialArtifacts(rawTrials);
artifacts = struct("Beam", struct(), "Energy", struct(), "LiveDerived", struct(), "HARQ", struct());
artifacts.Beam = localExportBeamformingDiagnostics(cfg, runFolder, rawTrials, false);
artifacts.Energy = sixgr.truth.exportLLSEnergyDiagnostics(cfg, runFolder, rawTrials);
artifacts.IQImpairment = sixgr.truth.exportLLSRFImpairmentDiagnostics(cfg, runFolder, rawTrials);
artifacts.LiveDerived = sixgr.truth.exportLLSLiveDerivedTables(cfg, fileparts(char(string(runFolder))), rawTrials, multiUser, mobilityArtifacts, runtimeState);
artifacts.HARQ = sixgr.util.structGet(artifacts.LiveDerived, "HARQ", struct());
end

function localPublishLiveSweepSnapshot(baseTrials, partialTrials, baseConst, partialConst, liveTablePath, liveConstellationPath, cfg, meta)
if nargin < 8 || ~isstruct(meta)
    meta = struct();
end
mergedTrials = localAppendCompatTable(baseTrials, partialTrials);
direction = upper(strtrim(string(sixgr.util.structGet(meta, "Direction", ""))));
if any(direction == ["DL", "UL"])
    mergedTrials = localForceLinkTrialSourceArtifact(mergedTrials, direction);
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
        rawTrials = localForceDirectionalRawTrialArtifacts(rawTrials);
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
if ~sixgr.db.isArtifactStoreActive()
    return;
end
try
    sixgr.db.appendLogLine(string(levelStr), timeStamp, string(messageText));
catch
end
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
if roundedFrame <= 1
    tf = true;
    return;
end
if isfinite(totalFrames) && roundedFrame >= round(double(totalFrames))
    tf = true;
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

function Tout = localAppendCompatTable(Ta, Tb)
if ~(istable(Ta) && ~isempty(Ta))
    if istable(Tb)
        Tout = Tb;
    else
        Tout = table();
    end
    return;
end
if ~(istable(Tb) && ~isempty(Tb))
    Tout = Ta;
    return;
end
vars = union(string(Ta.Properties.VariableNames), string(Tb.Properties.VariableNames), "stable");
Ta = localEnsureTableVars(Ta, vars, Tb);
Tb = localEnsureTableVars(Tb, vars, Ta);
Tout = [Ta(:, cellstr(vars)); Tb(:, cellstr(vars))];
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

function rawTrials = localForceDirectionalRawTrialArtifacts(rawTrials)
if ~isstruct(rawTrials)
    return;
end
if isfield(rawTrials, "DL")
    rawTrials.DL = localForceLinkTrialSourceArtifact(rawTrials.DL, "DL");
end
if isfield(rawTrials, "UL")
    rawTrials.UL = localForceLinkTrialSourceArtifact(rawTrials.UL, "UL");
end
end

function T = localCanonicalizeControlTrialTable(signalName, T)
if ~(istable(T) && ~isempty(T))
    return;
end
T = sixgr.truth.CoupledTruthRuntime.canonicalizePersistedControlReferenceTable(signalName, T);
end

function T = localEnsureTableVars(T, vars, refT)
for i = 1:numel(vars)
    v = char(vars(i));
    if ~ismember(v, T.Properties.VariableNames)
        T.(v) = localDefaultColumnLike(refT, v, height(T));
    end
end
end

function col = localDefaultColumnLike(refT, varName, nRows)
if istable(refT) && ismember(varName, refT.Properties.VariableNames)
    refVal = refT.(varName);
    if isstring(refVal)
        col = strings(nRows, 1);
        return;
    end
    if islogical(refVal)
        col = false(nRows, 1);
        return;
    end
    if isnumeric(refVal)
        col = NaN(nRows, 1);
        return;
    end
end
col = strings(nRows, 1);
end

function T = localEnsureLinkTrialTable(Tin, direction, snr_dB, cfg)
vars = {'Direction','SNR_dB','Seed','Frame','Slot','MCS','PRBs','Layers','ConfiguredLayers','ConfiguredTxAntennas','ConfiguredRxAntennas','Modulation','TargetCodeRate','TBSize_bits', ...
    'ChannelModel','ChannelModelApplied','ChannelFadingApplied','DopplerHz','CRCPass','CRCApplicable','CRCOutcome', ...
    'HARQProcess','HARQNDI','HARQRV','HARQIsRetransmission','HARQFeedbackDueSlot', ...
    'HARQCurrentDecodeOK','HARQCombinedDecodeOK','HARQCombiningApplied','HARQLLRCombiningGain_dB', ...
    'HARQPreviousLLRCount','HARQCurrentLLRCount','HARQCombinedLLRCount', ...
    'DecoderIterations','EVM_rms','NMSE_dB', ...
    'DetectionMetric','CorrelationPeak','DetectionThreshold','DetectionThresholdMode','DetectionMetricStatus', ...
    'DetectorPeakMetric','DetectorNoiseFloor','RxAntennaCount','PDPAverageNoiseFloor','PeakToThresholdRatio','PeakToNoiseRatio','PeakToNoiseRatio_dB', ...
    'CandidateCount','CandidatesAboveThreshold','TargetFalseAlarmProbability','ThresholdBackgroundComponent','ThresholdGlobalPeakComponent','PeakGuardFactor','DetectorPeakLagSamples', ...
    'NoiseOnlyDetectionMetric','MissedDetection','FalseAlarm','FalseAlarmCandidateScope','FalseAlarmCandidateCount','DTXFlag','DTXReason', ...
    'PreambleIndex','RequestedPreambleIndex','DetectedPreambleIndex','PreambleIndexFromPeak', ...
    'PRACHRootSequenceIndex','PRACHZeroCorrelationZone','PRACHConfigurationIndex','PRACHOccasionIndex','PRACHCarrierSlot', ...
    'MeasuredSINR_dB','WidebandCQI','CQIDerivedMCS','CQIDerivedModulation','CQIDerivedTargetCodeRate', ...
    'LinkAdaptationMode','ConfiguredLinkAdaptationMode','LinkAdaptationDomain','ActualMCSSelectionMode','ConfiguredMCSSelectionPolicy','SchedulerGrantMCSSelectionMode', ...
    'CQISource','MCSSelectionSource','MCSValueStatus','OLLADomain','OuterLoopEnabled','InnerLoopEnabled','OuterLoopApplied','InnerLoopApplied','OLLADeltaDb','OLLADeltaMCS','OLLAAdjustedMCSBeforeCQICeiling','OLLABaseRequiredSINR_dB','OLLATargetRequiredSINR_dB','OLLAThresholdSource','OLLAUpdateCount','OLLAState','CalibrationProfile', ...
    'RequestedOperatingPointSource','CQITable','MCSTable', ...
    'RankIndicator','PMI','CRI','PMIType', ...
    'PMICodebookMode','CSIReportMode','CSIPayloadBitLength','CSIPayloadHex', ...
    'ConfiguredBeamSelectionStrategy','PrecoderSource','PrecodingMode','PrecodingApplicationStage', ...
    'PrecodingActive','ExplicitBeamWeightsApplied','TransformPrecodingApplied','BeamformingApplied', ...
    'AppliedBeamIndexSet','AppliedPrecoderPMI','AppliedPrecoderPMIType','AppliedPrecoderCodebookMode','RequestedVsAppliedPrecoderPMIMatchStatus', ...
    'BeamSelectionStrategy','BeamSelectionAuthority','BeamSelectionPolicyType','BeamSelectionPolicyFixed','RequestedBeamIndexSet', ...
    'RequestedPrecoderPMI','RequestedPrecoderSource','AppliedPrecoderSource', ...
    'RequestedBeamTruthClassification','RequestedPrecoderPMITruthClassification', ...
    'AppliedBeamApplicationSource','AppliedBeamTruthClassification', ...
    'AppliedPrecoderPMIApplicationSource','AppliedPrecoderPMITruthClassification', ...
    'MCSAuthority','ModulationAuthority','GrantOperatingPointSource','AppliedOperatingPointSource', ...
    'PrecodingNumPorts','PrecodingNumLayers','PrecodingMatrixRows','PrecodingMatrixCols', ...
    'RequestedFormat','ResolvedFormat','FormatAdapted','FormatAdaptationReason','ControlResourceValidity','ControlResourceSource', ...
    'PUCCHFormat','PUCCHResourceId','PUCCHPRBSet','PUCCHPRBStart','PUCCHPRBCount','PUCCHSymbolStart','PUCCHNumSymbols', ...
    'PUCCHRECount','PUCCHDMRSRECount','ExpectedBitCount','DecodedBitCount','PUCCHExpectedBitCount','PUCCHDecodedBitCount', ...
    'UCIExpectedBitVector','UCIDecodedBitVector','UCIBitErrorVector','UCICodedBitCount','UCICRCBitCount','UCICRCApplicable', ...
    'PUCCHControlSINR_dB','PUCCHReceiverEvidenceSource','PUCCHGridHash','PUCCHWaveformHash','ReceiverHestSINRApplicable', ...
    'FalseAlarmFlag','NoiseFalseAlarmFlag','CollisionFalseAlarmFlag','FalseAlarmClassification','BlockingFlag','BlindDecodeCount', ...
    'CandidatesAttempted','DCICrcPass','PDCCHPayloadMatch','PDCCHCausalGrantDecodeOk', ...
    'PDCCHExpectedDCIBitCount','PDCCHDecodedDCIBitCount','PDCCHDCIBitsCompared','PDCCHDCIBitErrors', ...
    'PDCCHMissedDetection','PDCCHFalseAlarm','PDCCHErrFlag','TxCCEIndex','SelectedCCEIndex','GrantValid','NegativeExpectedOk', ...
    'PDCCHBlindSearchEnabled','PDCCHCandidatesAvailable','PDCCHCandidatesAttempted','PDCCHCandidateIndex','PDCCHTxCCEIndex','PDCCHSelectedCCEIndex', ...
    'PDCCHDCICrcRNTI','PDCCHScramblingRNTI','PDCCHEncodedBits','PDCCHRECount','PDCCHDMRSRECount', ...
    'PDCCHCandidateErrFlagVector','PDCCHCandidateDecodeOKVector','PDCCHCandidateSINRVector_dB','PDCCHCandidateRECountVector','PDCCHCandidateDMRSRECountVector', ...
    'PDCCHCRCDecodeSource','PDCCHBlindDecodeEvidenceSource','PDCCHCCE_REGMappingEvidence','PDCCHREGMappingAvailable', ...
    'PDCCHCORESETDuration','PDCCHCORESETFrequencyResources','PDCCHSearchSpaceNumCandidates','PDCCHGridHash','PDCCHWaveformHash','PDCCHResourceHash', ...
    'AvailableCCECount','UsedCCECount', ...
    'NonOverlappedCCEUsage','AggregationLevel','DCISize_bits','ControlCapacityBits', ...
    'ControlCapacityUtilization','CORESETUtilization','ControlLatency_ms', ...
    'ChannelGain_dB','NoiseVariance','DesiredSignalPowerBeforeNoise','CompositeSignalPowerBeforeNoise','AppliedNoiseSNR_dB','NoiseVarianceSource', ...
    'NoiseVarStatus','NoiseVarSource','NoiseVarReason','NoiseVarStrictFailure', ...
    'ReceiverUsable','DecodeAttempted','DecodeUsable','StrictReceiverEvidenceOk','StrictOk','TruthStatus', ...
    'ChannelEstimateAttempted','ChannelEstimateAvailable','ChannelEstimateSource', ...
    'ResourceExtractionAttempted','ResourceExtractionAvailable', ...
    'EqualizationAttempted','EqualizationAvailable','DLSCHDecodeAttempted','DLSCHDecodeAvailable', ...
    'ULSCHDecodeAttempted','ULSCHDecodeAvailable','LLRAvailable','LLRFinite','LLRScaleSource','LLRNoiseVariance', ...
    'PostEqSINRWidebanddB','PostEqSINRAvailable','PostEqSINRReceiverDerived', ...
    'SINRValidationStatus','SINRValidationReason','SINRComputationMethod','ConfiguredSNRLikeSourceRejected', ...
    'EqualizerType','EqualizerRequestedType','EqualizerEngine', ...
    'InterferenceCovarianceAvailable','InterferenceCovarianceSource','InterferenceCovarianceStatus', ...
    'DetectionAttempted','DetectionSuccess','DetectionUsable', ...
    'MeasurementAttempted','MeasurementUsable','FailureReason','TimingOffset_samples','TimingAdvance_samples','TimingAdvance_us','TAOutOfRangeFlag','TAOutOfRangeReason','TAMaxValid_samples','TAMaxValid_us','RankEstimate', ...
    'SRSOccupiedPRBCount','SRSCarrierPRBCount','SRSBandwidthFraction','SRSFrequencyPRBStart','SRSFrequencyPRBEnd','SRSBandwidthCoverageStatus', ...
    'ConditionNumber_dB','NumRxAntennas','NumTxPorts', ...
    'SelectedBeamIndex','BestBeamIndex','BeamHit','TopKBeamHit','BeamCandidateCount', ...
    'SelectedBeamGain_dB','BestBeamGain_dB','BeamGainGap_dB', ...
    'ConfiguredPMI','ConfiguredCRI','BitErrors','BitsCompared','RawBER', ...
    'OfferedBits','GoodBits','OfferedThroughput_Mbps','Goodput_Mbps', ...
    'ComputeLatency_ms','ProcedureDelay_ms','AirInterfaceTTI_ms','AirInterfaceObservation_ms', ...
    'Latency_ms','DecodeLatency_ms','EarlyStopRate','DecoderComplexityUnits','NormalizedDecoderComplexity','AreaEfficiencyProxy', ...
    'NumCodeBlocks','CodeBlockLength_bits','SegmentationOccurred','SegmentationPaddingBits','TBCRCLength_bits','TBLengthWithCRC_bits','BaseGraph', ...
    'EncodedBits','RateMatchedBits','RateMatchPunctureBits','RateMatchRepetitionBits', ...
    'MeasuredDMRSRECount','MeasuredDMRSAntennaRECount','MeasuredDMRSSymbolCount','MeasuredDMRSPortCount','MeasuredDMRSAntennaPortCount', ...
    'MeasuredDMRSCDMLengthFD','MeasuredDMRSCDMLengthTD', ...
    'MeasuredRateMatchedCodewordLLRBits','MeasuredRateRecoveredLLRBits','MeasuredRateRecoveredFiniteLLRCount','MeasuredRateRecoverFillerBits', ...
    'MeasuredRateRecoveredCodeBlockCount','MeasuredRateRecoveredCodeBlockLength_bits','MeasuredRateRecoverNrefBits', ...
    'MeasuredLDPCDecoderMeanIterations','MeasuredLDPCDecoderMinIterations','MeasuredLDPCDecoderMaxIterations','MeasuredLDPCParityCheckFailures', ...
    'MeasuredCodeBlockDecodeErrorCount','MeasuredCodeBlockDecodeCount','MeasuredCodeBlockDecodeFailureRate', ...
    'MeasuredCodeBlockCRCErrorCount','MeasuredCodeBlockCRCCount','MeasuredCodeBlockCRCFailureRate', ...
    'MeasuredLDPCDecoderAlgorithm','MeasuredLDPCDecoderEngine','MeasuredLDPCIterationVector','MeasuredLDPCParityCheckVector','MeasuredCodeBlockDecodeErrorVector','MeasuredCodeBlockCRCErrorVector', ...
    'CodeBlockErrors','CodeBlockCount','CodeBlockBLER','CBGErrors','CBGCount','CBGBLER', ...
    'PAPR_dB','PeakClippingEvents','SymbolErrors','SymbolsCompared','SymbolErrorRate', ...
    'ResidualInterferencePower_dB', ...
    'LLRMeanAbs','LLRStdAbs','LLRImbalance','ModulationMappingSensitivity', ...
    'ShapingRateLoss','DistributionMatchingLatency_ms','HighOrderRobustness', ...
    'DetectorComplexityUnits_Modulation','DataRECount','DataRECountPerLayer','TotalDataRECount','ModulationOrderQm','ComputedE_TS38212','RateMatchedBitsDelta_TS38212','DMRSRECount','PTRSRECount','RSOverheadFraction', ...
    'InjectedCFO_Hz','EstimatedCFO_PreCorrection_Hz','ResidualCFO_PostCorrection_Hz', ...
    'EstimatedCFO_Hz','TrueCFO_Hz','CFOError_Hz', ...
    'InjectedTimingOffset_samples','EstimatedTimingOffset_PreCorrection_samples','ResidualTimingError_PostCorrection_samples', ...
    'TrueTimingOffset_samples','TimingError_samples', ...
    'IQImbalanceConfigured','IQImbalanceApplied','IQImbalanceModel', ...
    'ConfiguredIQGainImbalance_dB','ConfiguredIQPhaseImbalance_deg', ...
    'IQImbalanceMirrorPowerRatio_dB','IQImbalanceImageRejection_dB', ...
    'IQImbalanceIQPowerRatio_dB','IQImbalanceIQCorrelation', ...
    'IQImbalanceEstimatedAlphaAbs','IQImbalanceEstimatedBetaAbs', ...
    'IQImbalanceMeasurementSource','IQImbalanceMeasurementStatus', ...
    'InjectedDoppler_Hz','EstimatedDopplerHz','DopplerError_Hz','PhaseTrackingError_deg','QCLAccuracy', ...
    'ChannelAgingLoss_dB','InterpolationLoss_dB','MismatchSensitivity_dB','AcquisitionTime_ms','TrackingFailureProbability', ...
    'Status','Crash', ...
    'LinkAdaptationApplied','LinkAdaptationScheduled','IsWarmupFrame','Notes', ...
    'SFN','UEID','UEIndex','RNTI','BaseStationID','AllocatedPRBCount','PRBStart','MCSIndex','Rank', ...
    'ConfiguredSNR_dB','ConfiguredSNRSource','SNRValueRole','AppliedAWGNSNR_dB','AppliedAWGNSNRSource', ...
    'PRACHSNRCalibrationStatus','PRACHSNRCalibrationSource','PRACHSNRCalibrationError_dB','PRACHNoiseReferencePower', ...
    'ReceiverHestSINR_dB','ReceiverHestSINRSource','ReceiverHestSINRValueRole','ReceiverHestSINRValueStatus','ReceiverHestSINRNAReason', ...
    'PostEqSINR_dB','PostEqSINRSource','PostEqSINRValueRole','PostEqSINRValueStatus','PostEqSINRNAReason','PostEqSINRPerLayer_dB', ...
    'EVMProxySINR_dB','EVMProxySINRSource','EVMProxySINRValueRole','EVMProxySINRValueStatus','EVMProxySINRNAReason', ...
    'DecoderTruthProxySINR_dB','DecoderTruthProxySINRSource','DecoderTruthProxySINRValueRole','DecoderTruthProxySINRValueStatus','DecoderTruthProxySINRNAReason', ...
    'SINRValueRole','SINRSource','SINRValueStatus','SINRValueDefinition', ...
    'MeasuredTrialSINR_dB','MeasuredTrialSINRSource','MeasuredTrialSINRValueRole','MeasuredTrialSINRValueStatus','MeasuredTrialSINRNAReason', ...
    'LargeScaleSINR_dB','LargeScaleSINRSource', ...
    'ServingRSRP_dBm','ServingRSRPSource', ...
    'CSI_RSRP_dB','CSI_RSRPSource', ...
    'AppliedLargeScaleGain_dB','AppliedLargeScaleLoss_dB','AppliedBasePathloss_dB','AppliedPathloss_dB', ...
    'AppliedShadowFading_dB','AppliedO2I_dB','AppliedLargeScaleGainSource', ...
    'ChannelComplianceMode','PathlossModelSource','PathlossComplianceStatus','FallbackUsedForPathloss', ...
    'O2IModelSource','O2IComplianceStatus','O2IComplianceReason', ...
    'LOSProbabilitySource','LOSComplianceStatus','LOSComplianceReason', ...
    'TimingEstimateUsed','UseIdealTimingSync','AppliedTimingCorrection_samples','TimingEstimateApplicationPolicy','TimingEstimateStatus','TimingEstimateWasClipped', ...
    'InterferenceMode','InterferenceContributorCount','InterferenceAggregatedRxPower_dBm', ...
    'InterferencePowerSource','FullInterfererChannelTruthUsed', ...
    'CFOEstimateAvailability','CFOErrorDefinition','CFOValueStatus', ...
    'TimingEstimateAvailability','TimingErrorDefinition','TimingValueStatus', ...
    'LargeScaleSINRValueStatus','LargeScaleSINRFinalizedFlag','LargeScaleSINRNAReason', ...
    'PrimaryTruthValueStatus','SecondaryFieldGapFlag','SecondaryFieldGapCount','SecondaryFieldGapReason', ...
    'RowLifecycleState','PartialRowFlag','FinalizedFlag','FallbackFlag','PlaceholderFlag','NAReason', ...
    'RunUUID','RunTag','ScenarioID','RunnerProfile','ConfigHash','SourceArtifact','SourceTable','ArtifactClass','SemanticState', ...
    'CountsTowardCoverage','MachineReadable','HumanReadable', ...
    'InterfererBeamformingAppliedCount','InterfererExplicitBeamWeightCount','InterfererTransformPrecodingCount', ...
    'InterfererPrecoderSourceSet','InterfererPrecodingModeSet','InterfererBeamIndexSetSummary', ...
    'DopplerSourceMode','DopplerValueRole', ...
    'PBCHGatingActive','PRACHGatingActive','PDCCHGatingActive','SRSGatingActive', ...
    'ControlEligible','ControlDecodeOk','PDCCHCausalGrantDecodeOk','PDCCHControlFailureReason', ...
    'PDCCHControlEvidenceSource','ControlDecodeSource','GrantControlState', ...
    'CellAcquisitionState','AccessState','SRSValidityState','CSIValidityState','SRSValid','SRSAgeSlots', ...
    'TRSGatingActive','TRSValidityState','TrackingEligibility','TRSAgeSlots','LastSuccessfulTRSSlot','LastEstimatedTRSDopplerHz', ...
    'TRSStateSource','TRSRuntimeConsumer','TRSInfluencedDecision','TRSInfluenceDefinition','TRSReceiverIntegrationStatus','TRSReceiverIntegrationBlocker', ...
    'GrantContextId','GrantWorkerSafe','GrantSharedStateCommitMode', ...
    'BSAntennaArrayClass','BSAntennaElementClass','BSAntennaArrayType', ...
    'BSAntennaRows','BSAntennaCols','BSAntennaElements','BSAntennaSpacingH_lambda','BSAntennaSpacingV_lambda', ...
    'BSAntennaPolarization','BSAntennaAzimuth_deg','BSAntennaNumPorts','BSAntennaHasPhasedArrayObject', ...
    'UEAntennaArrayClass','UEAntennaElementClass','UEAntennaArrayType', ...
    'UEAntennaRows','UEAntennaCols','UEAntennaElements','UEAntennaSpacingH_lambda','UEAntennaSpacingV_lambda', ...
    'UEAntennaPolarization','UEAntennaHeading_deg','UEAntennaNumPorts','UEAntennaHasPhasedArrayObject', ...
    'AntennaConfigSource','RuntimeAntennaObjectSource','AntennaRuntimeObjectCreated', ...
    'ChannelArrayModel','ChannelObjectSource','ChannelObjectClass','ChannelArrayHandlingStatus','ChannelArrayHandlingBlocker', ...
    'ChannelGeometryCouplingLevel','GeometryAdapterType','GeometryAdapterSource','GeometryAdapterLimitation','GeometryAdapterPortMapping', ...
    'ChannelUsesCountOnlyAntennaModel','ChannelUsesSameRuntimeAntennaAssumptions', ...
    'InterferenceChannelObjectSource','InterferenceChannelObjectClass','InterferenceChannelArrayHandlingStatus','InterferenceChannelArrayHandlingBlocker', ...
    'InterferenceUsesSameRuntimeAntennaAssumptions','InterferencePathUsesSameArrayAssumptions', ...
    'PropagationDistance_m','GeometricPropagationDelay_s','DominantPathDelay_s','ChannelFilterDelay_s','PropagationDelay_s', ...
    'ToD_s','ToA_s','ToAEstimate_s', ...
    'ToDSource','ToASource','ToAEstimateSource','ChannelDelaySource','AntennaGeometrySource', ...
    'RuntimeTraceSource','AntennaEvidenceSource','SameFlowEvidenceSource'};
if nargin < 1 || ~istable(Tin)
    Tin = table();
end
if isempty(Tin)
    T = localEmptyLinkTrialTable(0);
    return;
end
T = Tin;
for i = 1:numel(vars)
    v = vars{i};
    if ~ismember(v, T.Properties.VariableNames)
                switch v
                    case {'Direction','ChannelModel','ChannelModelApplied','Status','Notes','PMIType','PMICodebookMode','CSIReportMode','Modulation', ...
                            'CQIDerivedModulation','LinkAdaptationMode','ConfiguredLinkAdaptationMode','LinkAdaptationDomain','ActualMCSSelectionMode','ConfiguredMCSSelectionPolicy', ...
                            'SchedulerGrantMCSSelectionMode','CQISource','MCSSelectionSource','MCSValueStatus','OLLADomain','OLLAState','CalibrationProfile', ...
                            'RequestedOperatingPointSource','CQITable','MCSTable','CSIPayloadHex', ...
                            'CRCOutcome','NoiseVarianceSource','NoiseVarStatus','NoiseVarSource','NoiseVarReason','FailureReason','TAOutOfRangeReason', ...
                            'TruthStatus','ChannelEstimateSource','LLRScaleSource', ...
                            'SINRValidationStatus','SINRValidationReason','SINRComputationMethod', ...
                            'EqualizerType','EqualizerRequestedType','EqualizerEngine','InterferenceCovarianceSource','InterferenceCovarianceStatus', ...
                            'ConfiguredSNRSource','SNRValueRole','AppliedAWGNSNRSource','PRACHSNRCalibrationStatus','PRACHSNRCalibrationSource', ...
                            'ReceiverHestSINRSource','ReceiverHestSINRValueRole','ReceiverHestSINRValueStatus','ReceiverHestSINRNAReason', ...
                            'PostEqSINRSource','PostEqSINRValueRole','PostEqSINRValueStatus','PostEqSINRNAReason','PostEqSINRPerLayer_dB', ...
                            'EVMProxySINRSource','EVMProxySINRValueRole','EVMProxySINRValueStatus','EVMProxySINRNAReason', ...
                            'DecoderTruthProxySINRSource','DecoderTruthProxySINRValueRole','DecoderTruthProxySINRValueStatus','DecoderTruthProxySINRNAReason', ...
                            'SINRValueRole','SINRSource','SINRValueStatus','SINRValueDefinition', ...
                            'MeasuredTrialSINRSource','MeasuredTrialSINRValueRole','MeasuredTrialSINRValueStatus','MeasuredTrialSINRNAReason','LargeScaleSINRSource','ServingRSRPSource','CSI_RSRPSource', ...
                            'AppliedLargeScaleGainSource','ChannelComplianceMode','PathlossModelSource','PathlossComplianceStatus', ...
                            'O2IModelSource','O2IComplianceStatus','O2IComplianceReason', ...
                            'LOSProbabilitySource','LOSComplianceStatus','LOSComplianceReason', ...
                            'IQImbalanceModel','IQImbalanceMeasurementSource','IQImbalanceMeasurementStatus', ...
                            'InterferenceMode','InterferencePowerSource','DopplerSourceMode','DopplerValueRole', ...
                            'GrantControlState','PDCCHControlFailureReason','PDCCHControlEvidenceSource','ControlDecodeSource', ...
                            'CellAcquisitionState','AccessState','SRSValidityState','CSIValidityState','TRSValidityState','SRSBandwidthCoverageStatus', ...
                            'ConfiguredBeamSelectionStrategy','PrecoderSource','PrecodingMode','PrecodingApplicationStage', ...
                            'AppliedBeamIndexSet','AppliedPrecoderPMIType','AppliedPrecoderCodebookMode','RequestedVsAppliedPrecoderPMIMatchStatus', ...
                            'BeamSelectionStrategy','BeamSelectionAuthority','BeamSelectionPolicyType', ...
                            'RequestedBeamIndexSet','RequestedPrecoderSource','AppliedPrecoderSource', ...
                            'RequestedBeamTruthClassification','RequestedPrecoderPMITruthClassification', ...
                            'AppliedBeamApplicationSource','AppliedBeamTruthClassification', ...
                            'AppliedPrecoderPMIApplicationSource','AppliedPrecoderPMITruthClassification', ...
                            'MCSAuthority','ModulationAuthority','GrantOperatingPointSource','AppliedOperatingPointSource', ...
                            'MeasuredLDPCDecoderAlgorithm','MeasuredLDPCDecoderEngine','MeasuredLDPCIterationVector','MeasuredLDPCParityCheckVector','MeasuredCodeBlockDecodeErrorVector','MeasuredCodeBlockCRCErrorVector', ...
                            'FormatAdaptationReason','ControlResourceSource','PUCCHResourceId','PUCCHPRBSet','UCIExpectedBitVector','UCIDecodedBitVector','UCIBitErrorVector', ...
                            'PUCCHReceiverEvidenceSource','PUCCHGridHash','PUCCHWaveformHash', ...
                            'PDCCHCandidateErrFlagVector','PDCCHCandidateDecodeOKVector','PDCCHCandidateSINRVector_dB','PDCCHCandidateRECountVector','PDCCHCandidateDMRSRECountVector', ...
                            'PDCCHCRCDecodeSource','PDCCHBlindDecodeEvidenceSource','PDCCHCCE_REGMappingEvidence','PDCCHCORESETFrequencyResources','PDCCHSearchSpaceNumCandidates', ...
                            'PDCCHGridHash','PDCCHWaveformHash','PDCCHResourceHash', ...
                            'CFOEstimateAvailability','CFOErrorDefinition','CFOValueStatus', ...
                            'TimingEstimateAvailability','TimingErrorDefinition','TimingValueStatus','TimingEstimateApplicationPolicy','TimingEstimateStatus', ...
                            'LargeScaleSINRValueStatus','LargeScaleSINRNAReason','PrimaryTruthValueStatus','SecondaryFieldGapReason','RowLifecycleState','NAReason', ...
                            'RunUUID','RunTag','ScenarioID','RunnerProfile','ConfigHash','SourceArtifact','SourceTable','ArtifactClass','SemanticState', ...
                            'InterfererPrecoderSourceSet','InterfererPrecodingModeSet','InterfererBeamIndexSetSummary', ...
                            'TRSStateSource','TRSRuntimeConsumer','TRSInfluenceDefinition','TRSReceiverIntegrationStatus','TRSReceiverIntegrationBlocker', ...
                            'GrantContextId','GrantSharedStateCommitMode', ...
                            'BSAntennaArrayClass','BSAntennaElementClass','BSAntennaArrayType','BSAntennaPolarization', ...
                            'UEAntennaArrayClass','UEAntennaElementClass','UEAntennaArrayType','UEAntennaPolarization', ...
                            'AntennaConfigSource','RuntimeAntennaObjectSource','ChannelArrayModel','ChannelObjectSource','ChannelObjectClass', ...
                            'ChannelArrayHandlingStatus','ChannelArrayHandlingBlocker','ChannelGeometryCouplingLevel','GeometryAdapterType','GeometryAdapterSource','GeometryAdapterLimitation','GeometryAdapterPortMapping', ...
                            'InterferenceChannelObjectSource','InterferenceChannelObjectClass','InterferenceChannelArrayHandlingStatus','InterferenceChannelArrayHandlingBlocker', ...
                            'ToDSource','ToASource','ToAEstimateSource','ChannelDelaySource','AntennaGeometrySource', ...
                            'RuntimeTraceSource','AntennaEvidenceSource','SameFlowEvidenceSource'}
                        T.(v) = strings(height(T),1);
                    case 'Crash'
                        T.(v) = false(height(T),1);
                    case {'LinkAdaptationApplied','LinkAdaptationScheduled','OuterLoopEnabled','InnerLoopEnabled','OuterLoopApplied','InnerLoopApplied', ...
                            'IsWarmupFrame','TimingEstimateUsed','UseIdealTimingSync','TimingEstimateWasClipped', ...
                            'HARQIsRetransmission','HARQCurrentDecodeOK','HARQCombinedDecodeOK','HARQCombiningApplied', ...
                            'CRCApplicable','NoiseVarStrictFailure','ReceiverUsable','DecodeAttempted','DecodeUsable','StrictReceiverEvidenceOk','StrictOk', ...
                            'ChannelEstimateAttempted','ChannelEstimateAvailable','ResourceExtractionAttempted','ResourceExtractionAvailable', ...
                            'EqualizationAttempted','EqualizationAvailable','DLSCHDecodeAttempted','DLSCHDecodeAvailable', ...
                            'ULSCHDecodeAttempted','ULSCHDecodeAvailable','LLRAvailable','LLRFinite','PostEqSINRAvailable','PostEqSINRReceiverDerived', ...
                            'ConfiguredSNRLikeSourceRejected','InterferenceCovarianceAvailable','DetectionAttempted','DetectionSuccess','DetectionUsable', ...
                            'MeasurementAttempted','MeasurementUsable','TAOutOfRangeFlag', ...
                            'PBCHGatingActive','PRACHGatingActive','PDCCHGatingActive','SRSGatingActive','TRSGatingActive','ControlEligible','ControlDecodeOk','PDCCHCausalGrantDecodeOk','SRSValid', ...
                            'TrackingEligibility','TRSInfluencedDecision', ...
                            'IQImbalanceConfigured','IQImbalanceApplied', ...
                            'FallbackUsedForPathloss', ...
                            'FullInterfererChannelTruthUsed','PrecodingActive','ExplicitBeamWeightsApplied','TransformPrecodingApplied','BeamformingApplied','ChannelFadingApplied', ...
                            'FormatAdapted','ControlResourceValidity','UCICRCApplicable','ReceiverHestSINRApplicable', ...
                            'DCICrcPass','PDCCHPayloadMatch','PDCCHCausalGrantDecodeOk','PDCCHMissedDetection','PDCCHFalseAlarm', ...
                            'GrantValid','NegativeExpectedOk','PDCCHBlindSearchEnabled','PDCCHREGMappingAvailable', ...
                            'BeamSelectionPolicyFixed','LargeScaleSINRFinalizedFlag','SecondaryFieldGapFlag','PartialRowFlag','FinalizedFlag','FallbackFlag','PlaceholderFlag', ...
                            'CountsTowardCoverage','MachineReadable','HumanReadable', ...
                            'GrantWorkerSafe','BSAntennaHasPhasedArrayObject','UEAntennaHasPhasedArrayObject', ...
                            'AntennaRuntimeObjectCreated','ChannelUsesCountOnlyAntennaModel','ChannelUsesSameRuntimeAntennaAssumptions', ...
                            'InterferenceUsesSameRuntimeAntennaAssumptions','InterferencePathUsesSameArrayAssumptions'}
                        T.(v) = false(height(T),1);
                    otherwise
                        T.(v) = NaN(height(T),1);
                end
    end
end
T = T(:, vars);
if all(strlength(string(T.Direction)) == 0)
    T.Direction(:) = string(direction);
end
if all(~isfinite(double(T.SNR_dB)))
    T.SNR_dB(:) = double(snr_dB);
end
if all(strlength(string(T.ConfiguredSNRSource)) == 0)
    T.ConfiguredSNRSource(:) = "configured_operating_point_metadata";
end
if all(strlength(string(T.SNRValueRole)) == 0)
    T.SNRValueRole(:) = "configured_operating_point_metadata";
end
if all(~isfinite(double(T.ConfiguredLayers)))
    T.ConfiguredLayers(:) = double(localConfiguredLayerCount(cfg, direction));
end
if all(~isfinite(double(T.ConfiguredTxAntennas)))
    T.ConfiguredTxAntennas(:) = double(localConfiguredTxAntennaCount(cfg, direction));
end
if all(~isfinite(double(T.ConfiguredRxAntennas)))
    T.ConfiguredRxAntennas(:) = double(localConfiguredRxAntennaCount(cfg, direction));
end
reqModel = localResolveRequestedLinkChannelModel(cfg);
if all(strlength(string(T.ChannelModel)) == 0)
    T.ChannelModel(:) = reqModel;
end
if all(strlength(string(T.DopplerSourceMode)) == 0)
    T.DopplerSourceMode(:) = localResolveDopplerSourceMode(cfg);
end
if all(strlength(string(T.DopplerValueRole)) == 0)
    T.DopplerValueRole(:) = "scenario_resolved_metadata";
end
if all(strlength(string(T.LinkAdaptationMode)) == 0)
    [~, policy, ~] = localResolveLinkAdaptationTokens(cfg, direction);
    T.LinkAdaptationMode(:) = string(policy);
end
if all(strlength(string(T.CQITable)) == 0)
    T.CQITable(:) = localResolveCQITable(cfg, direction);
end
if all(strlength(string(T.MCSTable)) == 0)
    if strcmpi(string(direction), "UL")
        T.MCSTable(:) = localResolveMCSTable(cfg, "UL");
    else
        T.MCSTable(:) = localResolveMCSTable(cfg, "DL");
    end
end
uCm = upper(strtrim(string(T.ChannelModel)));
maskTDL = (uCm == "TDL") & startsWith(reqModel, "TDL");
if any(maskTDL)
    T.ChannelModel(maskTDL) = reqModel;
end
maskCDL = (uCm == "CDL") & startsWith(reqModel, "CDL");
if any(maskCDL)
    T.ChannelModel(maskCDL) = reqModel;
end
if all(~isfinite(double(T.DopplerHz)))
    T.DopplerHz(:) = double(sixgr.util.structGet(cfg, "channel.doppler_Hz", ...
        sixgr.util.structGet(cfg, "channel.dopplerHz", sixgr.util.structGet(cfg, "channel.fading.maxDoppler_Hz", 0))));
end
if all(~isfinite(double(T.InjectedDoppler_Hz))) && any(isfinite(double(T.DopplerHz)))
    scalarDopplerRows = ~localRowsUseFadingChannelDoppler(T);
    if any(scalarDopplerRows)
        injected = double(T.InjectedDoppler_Hz);
        doppler = double(T.DopplerHz);
        fillMask = scalarDopplerRows & ~isfinite(injected) & isfinite(doppler);
        injected(fillMask) = doppler(fillMask);
        T.InjectedDoppler_Hz = injected;
    end
end
if all(~isfinite(double(T.Seed)))
    seed0 = double(sixgr.util.structGet(cfg, "run.seed", 1));
    T.Seed = seed0 + (0:height(T)-1).';
end
if all(~isfinite(double(T.Frame)))
    T.Frame = (1:height(T)).';
end
if all(~isfinite(double(T.Slot)))
    T.Slot = T.Frame;
end
if all(strlength(string(T.Status)) == 0)
    T.Status(:) = "NA";
end
if all(strlength(string(T.Notes)) == 0)
    T.Notes(:) = "";
end
if all(~isfinite(double(T.ComputeLatency_ms))) && any(isfinite(double(T.Latency_ms)))
    T.ComputeLatency_ms = double(T.Latency_ms);
end
if all(~isfinite(double(T.InjectedCFO_Hz))) && any(isfinite(double(T.TrueCFO_Hz)))
    T.InjectedCFO_Hz = double(T.TrueCFO_Hz);
end
if all(~isfinite(double(T.EstimatedCFO_PreCorrection_Hz))) && any(isfinite(double(T.EstimatedCFO_Hz)))
    T.EstimatedCFO_PreCorrection_Hz = double(T.EstimatedCFO_Hz);
end
if all(~isfinite(double(T.InjectedTimingOffset_samples))) && any(isfinite(double(T.TrueTimingOffset_samples)))
    T.InjectedTimingOffset_samples = double(T.TrueTimingOffset_samples);
end
if all(~isfinite(double(T.EstimatedTimingOffset_PreCorrection_samples))) && any(isfinite(double(T.TimingOffset_samples)))
    T.EstimatedTimingOffset_PreCorrection_samples = double(T.TimingOffset_samples);
end
if ~ismember("AppliedTimingCorrection_samples", string(T.Properties.VariableNames))
    T.AppliedTimingCorrection_samples = nan(height(T), 1);
end
missingAppliedTimingMask = ~isfinite(double(T.AppliedTimingCorrection_samples)) & isfinite(double(T.TimingOffset_samples));
if any(missingAppliedTimingMask)
    T.AppliedTimingCorrection_samples(missingAppliedTimingMask) = double(T.TimingOffset_samples(missingAppliedTimingMask));
end
if ~ismember("TimingEstimateApplicationPolicy", string(T.Properties.VariableNames))
    T.TimingEstimateApplicationPolicy = strings(height(T), 1);
end
if ~ismember("TimingEstimateStatus", string(T.Properties.VariableNames))
    T.TimingEstimateStatus = strings(height(T), 1);
end
if ~ismember("TimingEstimateWasClipped", string(T.Properties.VariableNames))
    T.TimingEstimateWasClipped = false(height(T), 1);
end
if all(~isfinite(double(T.ResidualTimingError_PostCorrection_samples))) && any(isfinite(double(T.TimingError_samples)))
    T.ResidualTimingError_PostCorrection_samples = double(T.TimingError_samples);
end
warmMask = false(height(T), 1);
if ismember("LinkAdaptationScheduled", string(T.Properties.VariableNames)) && ...
        ismember("LinkAdaptationApplied", string(T.Properties.VariableNames))
    warmMask = logical(T.LinkAdaptationScheduled) & ~logical(T.LinkAdaptationApplied);
end
T.IsWarmupFrame = logical(warmMask);
if all(~isfinite(double(T.SFN)))
    T.SFN = mod(max(0, round(double(T.Frame)) - 1), 1024);
end
if all(~isfinite(double(T.ConfiguredSNR_dB)))
    T.ConfiguredSNR_dB = double(T.SNR_dB);
end
T = localPopulateSINRTruthColumns(T);
T = localRepairLinkTrialEvidenceColumns(T, direction, cfg);
if all(~isfinite(double(T.MCSIndex))) && any(isfinite(double(T.MCS)))
    T.MCSIndex = double(T.MCS);
end
if all(~isfinite(double(T.AllocatedPRBCount))) && any(isfinite(double(T.PRBs)))
    T.AllocatedPRBCount = double(T.PRBs);
end
if ismember("Layers", string(T.Properties.VariableNames)) && any(isfinite(double(T.Layers)))
    layers = double(T.Layers);
    rank = double(T.Rank);
    mask = isfinite(layers) & (~isfinite(rank) | abs(rank - layers) > 1e-9);
    if any(mask)
        T.Rank(mask) = layers(mask);
    end
elseif all(~isfinite(double(T.Rank))) && any(isfinite(double(T.RankIndicator)))
    T.Rank = double(T.RankIndicator);
end
if all(~isfinite(double(T.BaseStationID))) && ismember("ServingCell", string(T.Properties.VariableNames)) && any(isfinite(double(T.ServingCell)))
    T.BaseStationID = double(T.ServingCell);
end
if all(~isfinite(double(T.UEID))) && ismember("UEIndex", string(T.Properties.VariableNames)) && any(isfinite(double(T.UEIndex)))
    T.UEID = double(T.UEIndex);
end
T = localApplyTrialTruthAnnotations(T, direction, cfg);
end

function T = localPopulateSINRTruthColumns(T)
if ~(istable(T) && ~isempty(T))
    return;
end
n = height(T);
vars = string(T.Properties.VariableNames);
if ~ismember("ReceiverHestSINR_dB", vars)
    T.ReceiverHestSINR_dB = nan(n, 1);
end
if ~ismember("ReceiverHestSINRSource", vars)
    T.ReceiverHestSINRSource = strings(n, 1);
end
if ~ismember("DecoderTruthProxySINR_dB", vars)
    T.DecoderTruthProxySINR_dB = nan(n, 1);
end
if ~ismember("DecoderTruthProxySINRSource", vars)
    T.DecoderTruthProxySINRSource = strings(n, 1);
end
if ~ismember("DecoderTruthProxySINRValueRole", vars)
    T.DecoderTruthProxySINRValueRole = strings(n, 1);
end
if ~ismember("DecoderTruthProxySINRValueStatus", vars)
    T.DecoderTruthProxySINRValueStatus = strings(n, 1);
end
if ~ismember("DecoderTruthProxySINRNAReason", vars)
    T.DecoderTruthProxySINRNAReason = strings(n, 1);
end
if ~ismember("SINRValueRole", vars)
    T.SINRValueRole = strings(n, 1);
end
if ~ismember("SINRSource", vars)
    T.SINRSource = strings(n, 1);
end
if ~ismember("MeasuredTrialSINR_dB", vars)
    T.MeasuredTrialSINR_dB = nan(n, 1);
end
if ~ismember("MeasuredTrialSINRSource", vars)
    T.MeasuredTrialSINRSource = strings(n, 1);
end
if ~ismember("MeasuredTrialSINRValueRole", vars)
    T.MeasuredTrialSINRValueRole = strings(n, 1);
end
if ~ismember("MeasuredTrialSINRValueStatus", vars)
    T.MeasuredTrialSINRValueStatus = strings(n, 1);
end
if ~ismember("MeasuredTrialSINRNAReason", vars)
    T.MeasuredTrialSINRNAReason = strings(n, 1);
end
if ~ismember("PostEqSINR_dB", vars)
    T.PostEqSINR_dB = nan(n, 1);
end
if ~ismember("PostEqSINRSource", vars)
    T.PostEqSINRSource = strings(n, 1);
end
if ~ismember("PostEqSINRValueRole", vars)
    T.PostEqSINRValueRole = strings(n, 1);
end
if ~ismember("PostEqSINRValueStatus", vars)
    T.PostEqSINRValueStatus = strings(n, 1);
end
if ~ismember("MeasuredSINR_dB", vars)
    T.MeasuredSINR_dB = nan(n, 1);
end
vars = string(T.Properties.VariableNames);

receiverHest = double(T.ReceiverHestSINR_dB);
postEqSINR = double(T.PostEqSINR_dB);
measuredTrial = double(T.MeasuredTrialSINR_dB);
measuredSINR = double(T.MeasuredSINR_dB);
postEqSource = strtrim(string(T.PostEqSINRSource));
postEqRole = strtrim(string(T.PostEqSINRValueRole));
postEqStatus = strtrim(string(T.PostEqSINRValueStatus));
postEqEligible = isfinite(postEqSINR) & localPostEqSINRProvenanceEligible(postEqSource, postEqRole, postEqStatus);
fillMeasuredTrialFromPostEq = ~isfinite(measuredTrial) & postEqEligible;
if any(fillMeasuredTrialFromPostEq)
    measuredTrial(fillMeasuredTrialFromPostEq) = postEqSINR(fillMeasuredTrialFromPostEq);
    T.MeasuredTrialSINR_dB = measuredTrial;
    measuredSource = strtrim(string(T.MeasuredTrialSINRSource));
    measuredRole = strtrim(string(T.MeasuredTrialSINRValueRole));
    measuredStatus = strtrim(string(T.MeasuredTrialSINRValueStatus));
    fillSourceMask = fillMeasuredTrialFromPostEq & (strlength(measuredSource) == 0);
    fillRoleMask = fillMeasuredTrialFromPostEq & (strlength(measuredRole) == 0);
    fillStatusMask = fillMeasuredTrialFromPostEq & (strlength(measuredStatus) == 0);
    measuredSource(fillSourceMask) = postEqSource(fillSourceMask);
    measuredRole(fillRoleMask) = "measured_post_equalization_scheduling_input";
    measuredStatus(fillStatusMask) = "OK";
    T.MeasuredTrialSINRSource = measuredSource;
    T.MeasuredTrialSINRValueRole = measuredRole;
    T.MeasuredTrialSINRValueStatus = measuredStatus;
end
fillMeasuredAliasMask = ~isfinite(measuredSINR) & isfinite(measuredTrial);
if any(fillMeasuredAliasMask)
    measuredSINR(fillMeasuredAliasMask) = measuredTrial(fillMeasuredAliasMask);
    T.MeasuredSINR_dB = measuredSINR;
end

receiverSource = strtrim(string(T.ReceiverHestSINRSource));
fillReceiverSourceMask = strlength(receiverSource) == 0 & isfinite(receiverHest);
if any(fillReceiverSourceMask)
    receiverSource(fillReceiverSourceMask) = "receiver_hest_reference_signal_measurement";
    T.ReceiverHestSINRSource = receiverSource;
end
sinrValueRole = strtrim(string(T.SINRValueRole));
fillRoleMask = strlength(sinrValueRole) == 0 & postEqEligible;
if any(fillRoleMask)
    sinrValueRole(fillRoleMask) = "measured_post_equalization_scheduling_input";
    T.SINRValueRole = sinrValueRole;
end
sinrSource = strtrim(string(T.SINRSource));
fillSINRSourceMask = strlength(sinrSource) == 0 & postEqEligible & strlength(postEqSource) > 0;
if any(fillSINRSourceMask)
    sinrSource(fillSINRSourceMask) = postEqSource(fillSINRSourceMask);
    T.SINRSource = sinrSource;
end

decoderProxy = double(T.DecoderTruthProxySINR_dB);
decoderSource = strtrim(string(T.DecoderTruthProxySINRSource));
decoderRole = strtrim(string(T.DecoderTruthProxySINRValueRole));
decoderStatus = strtrim(string(T.DecoderTruthProxySINRValueStatus));
decoderReason = strtrim(string(T.DecoderTruthProxySINRNAReason));
proxyLike = isfinite(decoderProxy) | contains(lower(decoderSource), "evm_proxy") | ...
    contains(lower(decoderRole), "proxy") | contains(lower(decoderSource), "proxy");
if any(proxyLike)
    decoderProxy(proxyLike) = NaN;
    decoderSource(proxyLike) = "evm_proxy_quarantined_not_decoder_truth";
    decoderRole(proxyLike) = "unavailable";
    decoderStatus(proxyLike) = "unavailable";
    decoderReason(proxyLike) = "decoder_truth_sinr_requires_receiver_or_decoder_evidence_not_evm_proxy";
end
blankSource = strlength(decoderSource) == 0;
decoderSource(blankSource) = "unavailable_decoder_truth_proxy_not_materialized";
blankRole = strlength(decoderRole) == 0;
decoderRole(blankRole) = "unavailable";
blankStatus = strlength(decoderStatus) == 0;
decoderStatus(blankStatus) = "unavailable";
blankReason = strlength(decoderReason) == 0;
decoderReason(blankReason) = "decoder_truth_proxy_not_materialized";
T.DecoderTruthProxySINR_dB = decoderProxy;
T.DecoderTruthProxySINRSource = decoderSource;
T.DecoderTruthProxySINRValueRole = decoderRole;
T.DecoderTruthProxySINRValueStatus = decoderStatus;
T.DecoderTruthProxySINRNAReason = decoderReason;
end

function tf = localPostEqSINRProvenanceEligible(source, role, status)
token = lower(strjoin([string(source), string(role), string(status)], " "));
hasBareHest = arrayfun(@(s) any(string(regexp(char(s), '[a-z0-9]+', 'match')) == "hest"), token);
blocked = ["receiverhest", "receiver_hest", "pilot", ...
    "reference_signal", "evm_proxy", "proxy", "fallback", "configured", "sweep", ...
    "unavailable", "failed", "rejected"];
tf = contains(token, "post_equalization") & ~hasBareHest & ~arrayfun(@(s) any(contains(s, blocked)), token);
end

function T = localRepairLinkTrialEvidenceColumns(T, direction, cfg)
if ~(istable(T) && ~isempty(T))
    return;
end
n = height(T);
status = lower(strtrim(string(localColumnOrDefault(T, "Status", repmat("", n, 1)))));
crash = logical(localColumnOrDefault(T, "Crash", false(n, 1)));
crcPass = double(localColumnOrDefault(T, "CRCPass", nan(n, 1)));
decodeAttempted = logical(localColumnOrDefault(T, "DecodeAttempted", false(n, 1)));
decodeUsable = logical(localColumnOrDefault(T, "DecodeUsable", false(n, 1)));
receiverUsable = logical(localColumnOrDefault(T, "ReceiverUsable", false(n, 1)));

receiverSINR = double(localColumnOrDefault(T, "ReceiverHestSINR_dB", nan(n, 1)));
measuredSINR = double(localColumnOrDefault(T, "MeasuredTrialSINR_dB", nan(n, 1)));
evm = double(localColumnOrDefault(T, "EVM_rms", nan(n, 1)));
nmse = double(localColumnOrDefault(T, "NMSE_dB", nan(n, 1)));
noiseVar = double(localColumnOrDefault(T, "NoiseVariance", nan(n, 1)));
bitErrors = double(localColumnOrDefault(T, "BitErrors", nan(n, 1)));
bitsCompared = double(localColumnOrDefault(T, "BitsCompared", nan(n, 1)));
decoderIterations = double(localColumnOrDefault(T, "DecoderIterations", nan(n, 1)));
tbBits = double(localColumnOrDefault(T, "TBSize_bits", nan(n, 1)));

if ismember("RawBER", string(T.Properties.VariableNames))
    rawBER = double(localColumnOrDefault(T, "RawBER", nan(n, 1)));
    rawBERMask = ~isfinite(rawBER) & isfinite(bitErrors) & isfinite(bitsCompared) & bitsCompared > 0;
    rawBER(rawBERMask) = bitErrors(rawBERMask) ./ bitsCompared(rawBERMask);
    T.RawBER = rawBER;
end

activeOutcome = ~crash & any(status == ["pass","fail"], 2);
decodeEvidence = ~crash & (decodeAttempted | activeOutcome | isfinite(crcPass) | ...
    isfinite(bitErrors) | isfinite(bitsCompared) | isfinite(decoderIterations) | isfinite(tbBits));
if ismember("DecodeAttempted", string(T.Properties.VariableNames))
    T.DecodeAttempted = logical(decodeAttempted | decodeEvidence);
end
decodeUsableEvidence = decodeEvidence & (receiverUsable | isfinite(crcPass) | isfinite(bitErrors) | ...
    isfinite(bitsCompared) | isfinite(evm) | isfinite(nmse));
if ismember("DecodeUsable", string(T.Properties.VariableNames))
    T.DecodeUsable = logical(decodeUsable | decodeUsableEvidence);
end

detMetric = double(localColumnOrDefault(T, "DetectionMetric", nan(n, 1)));
corrPeak = double(localColumnOrDefault(T, "CorrelationPeak", nan(n, 1)));
detectorPeak = double(localColumnOrDefault(T, "DetectorPeakMetric", nan(n, 1)));
detectEvidence = decodeEvidence | isfinite(detMetric) | isfinite(corrPeak) | isfinite(detectorPeak);
if ismember("DetectionAttempted", string(T.Properties.VariableNames))
    T.DetectionAttempted = logical(localColumnOrDefault(T, "DetectionAttempted", false(n, 1)) | detectEvidence);
end
if ismember("DetectionUsable", string(T.Properties.VariableNames))
    T.DetectionUsable = logical(localColumnOrDefault(T, "DetectionUsable", false(n, 1)) | ...
        (detectEvidence & (isfinite(detMetric) | decodeUsableEvidence | receiverUsable)));
end

widebandCQI = double(localColumnOrDefault(T, "WidebandCQI", nan(n, 1)));
channelGain = double(localColumnOrDefault(T, "ChannelGain_dB", nan(n, 1)));
conditionNumber = double(localColumnOrDefault(T, "ConditionNumber_dB", nan(n, 1)));
measurementEvidence = ~crash & (isfinite(receiverSINR) | isfinite(measuredSINR) | isfinite(noiseVar) | ...
    isfinite(evm) | isfinite(nmse) | isfinite(widebandCQI) | isfinite(channelGain) | isfinite(conditionNumber));
if ismember("MeasurementAttempted", string(T.Properties.VariableNames))
    T.MeasurementAttempted = logical(localColumnOrDefault(T, "MeasurementAttempted", false(n, 1)) | measurementEvidence);
end
if ismember("MeasurementUsable", string(T.Properties.VariableNames))
    T.MeasurementUsable = logical(localColumnOrDefault(T, "MeasurementUsable", false(n, 1)) | ...
        (~crash & (isfinite(receiverSINR) | isfinite(measuredSINR) | receiverUsable)));
end
if ismember("ReceiverUsable", string(T.Properties.VariableNames))
    T.ReceiverUsable = logical(receiverUsable | (~crash & (isfinite(receiverSINR) | isfinite(measuredSINR))));
end

if ismember("ChannelModelApplied", string(T.Properties.VariableNames))
    modelApplied = strtrim(string(T.ChannelModelApplied));
    model = strtrim(string(localColumnOrDefault(T, "ChannelModel", repmat("", n, 1))));
    blankApplied = strlength(modelApplied) == 0 & strlength(model) > 0;
    modelApplied(blankApplied) = model(blankApplied);
    T.ChannelModelApplied = modelApplied;
end
if ismember("ChannelFadingApplied", string(T.Properties.VariableNames))
    channelModel = upper(strtrim(string(localColumnOrDefault(T, "ChannelModel", repmat("", n, 1)))));
    channelModelApplied = upper(strtrim(string(localColumnOrDefault(T, "ChannelModelApplied", repmat("", n, 1)))));
    channelClass = lower(strtrim(string(localColumnOrDefault(T, "ChannelObjectClass", repmat("", n, 1)))));
    channelSource = lower(strtrim(string(localColumnOrDefault(T, "ChannelObjectSource", repmat("", n, 1)))));
    arrayStatus = lower(strtrim(string(localColumnOrDefault(T, "ChannelArrayHandlingStatus", repmat("", n, 1)))));
    configuredAWGNOnly = logical(sixgr.util.structGet(cfg, "channel.awgnOnly", false));
    fadingModel = startsWith(channelModel, "TDL") | startsWith(channelModel, "CDL") | ...
        startsWith(channelModelApplied, "TDL") | startsWith(channelModelApplied, "CDL");
    fadingRuntimeEvidence = contains(channelClass, "nrtdl") | contains(channelClass, "nrcdl") | ...
        contains(channelSource, "tdl") | contains(channelSource, "cdl") | contains(arrayStatus, "runtime_array");
    T.ChannelFadingApplied = logical(localColumnOrDefault(T, "ChannelFadingApplied", false(n, 1)) | ...
        (~configuredAWGNOnly & fadingModel & fadingRuntimeEvidence));
end

if ismember("LinkAdaptationScheduled", string(T.Properties.VariableNames))
    mcsIdx = double(localColumnOrDefault(T, "MCSIndex", localColumnOrDefault(T, "MCS", nan(n, 1))));
    mcsAuthority = strtrim(string(localColumnOrDefault(T, "MCSAuthority", repmat("", n, 1))));
    grantSource = strtrim(string(localColumnOrDefault(T, "GrantOperatingPointSource", repmat("", n, 1))));
    laEvidence = ~crash & (isfinite(mcsIdx) | strlength(mcsAuthority) > 0 | strlength(grantSource) > 0);
    T.LinkAdaptationScheduled = logical(localColumnOrDefault(T, "LinkAdaptationScheduled", false(n, 1)) | laEvidence);
end
if ismember("LinkAdaptationApplied", string(T.Properties.VariableNames))
    modulation = strtrim(string(localColumnOrDefault(T, "Modulation", repmat("", n, 1))));
    mcsIdx = double(localColumnOrDefault(T, "MCSIndex", localColumnOrDefault(T, "MCS", nan(n, 1))));
    appliedEvidence = ~crash & isfinite(mcsIdx) & strlength(modulation) > 0 & decodeEvidence;
    T.LinkAdaptationApplied = logical(localColumnOrDefault(T, "LinkAdaptationApplied", false(n, 1)) | appliedEvidence);
end

if ismember("AppliedPrecoderPMIType", string(T.Properties.VariableNames))
    pmiType = strtrim(string(T.AppliedPrecoderPMIType));
    codebookMode = strtrim(string(localColumnOrDefault(T, "AppliedPrecoderCodebookMode", repmat("", n, 1))));
    precoderSource = lower(strtrim(string(localColumnOrDefault(T, "PrecoderSource", repmat("", n, 1)))));
    precodingMode = lower(strtrim(string(localColumnOrDefault(T, "PrecodingMode", repmat("", n, 1)))));
    precodingActive = logical(localColumnOrDefault(T, "PrecodingActive", false(n, 1)));
    beamformingApplied = logical(localColumnOrDefault(T, "BeamformingApplied", false(n, 1)));
    appliedBeam = strtrim(string(localColumnOrDefault(T, "AppliedBeamIndexSet", repmat("", n, 1))));
    dftMask = (precodingActive | beamformingApplied) & (contains(precoderSource, "codebook_dft") | strlength(appliedBeam) > 0);
    transformMask = logical(localColumnOrDefault(T, "TransformPrecodingApplied", false(n, 1))) | contains(precodingMode, "transform");
    pmiType(strlength(pmiType) == 0 & dftMask) = "dft_beam_index_precoder";
    pmiType(strlength(pmiType) == 0 & transformMask) = "transform_precoding_no_pmi";
    pmiType(strlength(pmiType) == 0 & (precodingActive | beamformingApplied)) = "runtime_precoder_no_pmi_index";
    T.AppliedPrecoderPMIType = pmiType;
    if ismember("AppliedPrecoderCodebookMode", string(T.Properties.VariableNames))
        codebookMode(strlength(codebookMode) == 0 & dftMask) = "dft_beam_codebook";
        codebookMode(strlength(codebookMode) == 0 & transformMask) = "transform_precoding";
        codebookMode(strlength(codebookMode) == 0 & (precodingActive | beamformingApplied)) = "runtime_precoder_mode";
        T.AppliedPrecoderCodebookMode = codebookMode;
    end
end
end

function T = localApplyTrialTruthAnnotations(T, direction, cfg)
if ~(istable(T) && ~isempty(T))
    return;
end
n = height(T);
strategy = strtrim(string(T.ConfiguredBeamSelectionStrategy));
if ismember("BeamSelectionStrategy", string(T.Properties.VariableNames)) && all(strlength(strtrim(string(T.BeamSelectionStrategy))) == 0)
    T.BeamSelectionStrategy = strategy;
end
T.BeamSelectionAuthority = repmat("configured_beam_policy_reference", n, 1);
fixedPolicyMask = startsWith(lower(strategy), "fixed");
dynamicPolicyMask = strlength(strategy) > 0 & ~fixedPolicyMask;
T.BeamSelectionPolicyType = repmat("", n, 1);
T.BeamSelectionPolicyType(fixedPolicyMask) = "fixed_policy";
T.BeamSelectionPolicyType(dynamicPolicyMask) = "dynamic_policy";
T.BeamSelectionPolicyFixed = fixedPolicyMask;
if ismember("BeamIndexSet", string(T.Properties.VariableNames))
    requestedBeam = strtrim(string(T.BeamIndexSet));
else
    requestedBeam = strings(n, 1);
end
configuredBeamSet = strtrim(string(sixgr.util.structGet(cfg, "lls6g.userContext.BeamIndexSet", "")));
if strlength(configuredBeamSet) > 0
    requestedBeam(strlength(requestedBeam) == 0) = configuredBeamSet;
end
selectedFinite = isfinite(double(T.SelectedBeamIndex));
selectedMask = strlength(requestedBeam) == 0 & selectedFinite;
requestedBeam(selectedMask) = string(round(double(T.SelectedBeamIndex(selectedMask))));
T.RequestedBeamIndexSet = requestedBeam;
requestedPMI = nan(n, 1);
if ismember("PMI", string(T.Properties.VariableNames))
    requestedPMI = double(T.PMI);
end
cfgPmiMask = ~isfinite(requestedPMI) & isfinite(double(T.ConfiguredPMI));
ulCfgPmiMask = upper(string(direction)) == "UL" & isfinite(double(T.ConfiguredPMI));
requestedPMI(cfgPmiMask) = double(T.ConfiguredPMI(cfgPmiMask));
requestedPMI(ulCfgPmiMask) = double(T.ConfiguredPMI(ulCfgPmiMask));
T.RequestedPrecoderPMI = requestedPMI;
T.RequestedPrecoderSource = repmat("", n, 1);
T.RequestedPrecoderSource(isfinite(double(T.PMI))) = "scheduler_grant_or_csi_feedback_request";
T.RequestedPrecoderSource(cfgPmiMask) = "configured_pmi_reference";
T.RequestedPrecoderSource(ulCfgPmiMask) = "configured_pusch_tpmi_runtime_request";
precoderSource = localNormalizeULAppliedPrecoderSourceBundle( ...
    localColumnOrDefault(T, "PrecoderSource", ""), ...
    localColumnOrDefault(T, "PrecodingMode", ""), ...
    localColumnOrDefault(T, "TransformPrecodingApplied", false));
T.PrecoderSource = precoderSource;
T.AppliedPrecoderSource = precoderSource;
T = localDecorateBeamAndPrecoderTruthFieldsBundle(T, direction);
configuredLinkMode = repmat("", n, 1);
configuredSelectionMode = repmat("", n, 1);
[configuredMode, policy, configuredActualMode] = localResolveLinkAdaptationTokens(cfg, direction);
configuredLinkMode(:) = string(configuredMode);
configuredSelectionMode(:) = string(configuredActualMode);
T.ConfiguredLinkAdaptationMode = configuredLinkMode;
T.ConfiguredMCSSelectionPolicy = configuredSelectionMode;
T.RequestedOperatingPointSource = localResolveOperatingPointSourceColumn(configuredSelectionMode, configuredLinkMode);
T.SchedulerGrantMCSSelectionMode = string(T.SchedulerGrantMCSSelectionMode);
operatingPointSource = localResolveOperatingPointSourceColumn(T.ActualMCSSelectionMode, T.LinkAdaptationMode);
T.GrantOperatingPointSource = operatingPointSource;
T.AppliedOperatingPointSource = operatingPointSource;
T.MCSAuthority = operatingPointSource;
T.ModulationAuthority = operatingPointSource;
T = sixgr.util.applyLLSRawTrialLifecycle(T);

storeState = localResolveArtifactStoreState();
T.RunUUID = repmat(string(sixgr.util.structGet(storeState, "RunUUID", "")), n, 1);
T.RunTag = repmat(string(sixgr.util.structGet(cfg, "run.runTag", "")), n, 1);
scenarioId = string(sixgr.util.structGet(cfg, "run.scenarioID", sixgr.util.structGet(cfg, "meta.lls6gScenarioID", sixgr.util.structGet(cfg, "meta.loadedFrom", ""))));
T.ScenarioID = repmat(scenarioId, n, 1);
T.RunnerProfile = repmat(string(sixgr.util.structGet(cfg, "run.runnerProfile", "waveform_bundle")), n, 1);
T.ConfigHash = repmat(string(sixgr.util.structGet(cfg, "meta.configHash", "")), n, 1);
sourceArtifact = repmat(localResolveDirectionalTrialArtifact(T, direction), n, 1);
T.SourceArtifact = sourceArtifact;
T.SourceTable = sourceArtifact;
T.ArtifactClass = repmat("raw_runtime_trial_evidence", n, 1);
T.SemanticState = string(T.RowLifecycleState);
T.CountsTowardCoverage = ~logical(T.Crash) & ~logical(T.IsWarmupFrame);
runtimeStatus = strtrim(string(localColumnOrDefault(T, "RuntimeMaterializationStatus", "")));
runtimeEvidence = strtrim(string(localColumnOrDefault(T, "RuntimeEvidenceSource", "")));
runtimeToken = repmat("active_waveform_pdsch_runtime", n, 1);
if strcmpi(string(direction), "UL")
    runtimeToken(:) = "active_waveform_pusch_runtime";
end
activeRuntimeMask = ~logical(localColumnOrDefault(T, "Crash", false));
runtimeStatus(activeRuntimeMask & strlength(runtimeStatus) == 0) = runtimeToken(activeRuntimeMask & strlength(runtimeStatus) == 0);
runtimeEvidence(activeRuntimeMask & strlength(runtimeEvidence) == 0) = "sixgr.truth.runWaveformLinkBundle";
T.RuntimeMaterializationStatus = runtimeStatus;
T.RuntimeEvidenceSource = runtimeEvidence;
T.MachineReadable = true(n, 1);
T.HumanReadable = true(n, 1);
end

function T = localDecorateBeamAndPrecoderTruthFieldsBundle(T, direction)
if ~(istable(T) && ~isempty(T))
    return;
end
n = height(T);
requestedBeam = strtrim(string(localColumnOrDefault(T, "RequestedBeamIndexSet", "")));
requestedPMI = double(localColumnOrDefault(T, "RequestedPrecoderPMI", NaN));
appliedBeam = strtrim(string(localColumnOrDefault(T, "AppliedBeamIndexSet", "")));
appliedPMI = double(localColumnOrDefault(T, "AppliedPrecoderPMI", NaN));
appliedSource = strtrim(string(localColumnOrDefault(T, "AppliedPrecoderSource", localColumnOrDefault(T, "PrecoderSource", ""))));
precodingMode = lower(strtrim(string(localColumnOrDefault(T, "PrecodingMode", ""))));
transformApplied = logical(localColumnOrDefault(T, "TransformPrecodingApplied", false)) | precodingMode == "transform_precoding";
explicitBeamWeights = logical(localColumnOrDefault(T, "ExplicitBeamWeightsApplied", false));
beamformingApplied = logical(localColumnOrDefault(T, "BeamformingApplied", false));
isUL = upper(string(direction)) == "UL";
codebookMask = isUL & (precodingMode == "ul_codebook_tpmi" | lower(appliedSource) == "ul_pusch_native_codebook_tpmi");
implicitTPMIBeamRequestMask = codebookMask & strlength(requestedBeam) == 0 & ...
    strlength(appliedBeam) > 0 & isfinite(requestedPMI);
requestedBeam(implicitTPMIBeamRequestMask) = appliedBeam(implicitTPMIBeamRequestMask);
T.RequestedBeamIndexSet = requestedBeam;

T.RequestedBeamTruthClassification = repmat("", n, 1);
T.RequestedPrecoderPMITruthClassification = repmat("", n, 1);
T.AppliedBeamApplicationSource = appliedSource;
T.AppliedBeamTruthClassification = repmat("", n, 1);
T.AppliedPrecoderPMIApplicationSource = appliedSource;
T.AppliedPrecoderPMITruthClassification = repmat("", n, 1);

requestedBeamMask = strlength(requestedBeam) > 0;
requestedPMIMask = isfinite(requestedPMI);
appliedBeamMask = strlength(appliedBeam) > 0;
appliedPMIMask = isfinite(appliedPMI);

T.RequestedBeamTruthClassification(requestedBeamMask) = "requested_reference";
T.RequestedPrecoderPMITruthClassification(requestedPMIMask) = "requested_reference";
T.AppliedBeamTruthClassification(appliedBeamMask) = "applied_runtime_value";
T.AppliedPrecoderPMITruthClassification(appliedPMIMask) = "applied_runtime_value";
matchStatus = strings(n, 1);
for ii = 1:n
    matchStatus(ii) = localRequestedVsAppliedPMIStatusBundle(requestedPMI(ii), appliedPMI(ii));
end
T.RequestedVsAppliedPrecoderPMIMatchStatus = matchStatus;

if ~isUL
    return;
end

directMask = ~transformApplied & ~codebookMask;
missingAppliedBeamMask = ~appliedBeamMask & ~explicitBeamWeights;
missingAppliedPMIMask = ~appliedPMIMask & ~explicitBeamWeights;
nativeCodebookAppliedBeamMask = appliedBeamMask & codebookMask;

beamAppSource = T.AppliedBeamApplicationSource;
pmiAppSource = T.AppliedPrecoderPMIApplicationSource;
beamAppSource(nativeCodebookAppliedBeamMask) = "ul_pusch_native_codebook_tpmi_port_support";
beamAppSource(missingAppliedBeamMask & directMask) = "ul_direct_mapping_no_materialized_beam_index_set";
beamAppSource(missingAppliedBeamMask & transformApplied) = "ul_transform_precoding_no_materialized_beam_index_set";
beamAppSource(missingAppliedBeamMask & codebookMask) = "ul_pusch_native_codebook_no_materialized_beam_index_set";
pmiAppSource(missingAppliedPMIMask & directMask) = "ul_direct_mapping_no_materialized_applied_pmi";
pmiAppSource(missingAppliedPMIMask & transformApplied) = "ul_transform_precoding_no_materialized_applied_pmi";
pmiAppSource(missingAppliedPMIMask & codebookMask) = "ul_pusch_native_codebook_no_runtime_tpmi";
T.AppliedBeamApplicationSource = beamAppSource;
T.AppliedPrecoderPMIApplicationSource = pmiAppSource;
T.AppliedBeamTruthClassification(missingAppliedBeamMask) = "not_materialized_in_active_ul_path";
T.AppliedPrecoderPMITruthClassification(missingAppliedPMIMask) = "not_materialized_in_active_ul_path";
T.BeamformingApplied(missingAppliedBeamMask & ~beamformingApplied) = false;
end

function status = localRequestedVsAppliedPMIStatusBundle(requestedPMI, appliedPMI)
requestedFinite = isfinite(double(requestedPMI));
appliedFinite = isfinite(double(appliedPMI));
if requestedFinite && appliedFinite
    if round(double(requestedPMI)) == round(double(appliedPMI))
        status = "requested_matches_runtime_applied";
    else
        status = "requested_differs_from_runtime_applied";
    end
elseif requestedFinite && ~appliedFinite
    status = "requested_present_applied_unavailable";
elseif ~requestedFinite && appliedFinite
    status = "runtime_applied_without_request_reference";
else
    status = "no_requested_or_applied_pmi";
end
end

function values = localColumnOrDefault(T, name, defaultValue)
n = height(T);
if ismember(name, string(T.Properties.VariableNames))
    values = T.(name);
    return;
end
if isstring(defaultValue) && numel(defaultValue) == n && ~isscalar(defaultValue)
    values = reshape(string(defaultValue), n, 1);
elseif islogical(defaultValue) && numel(defaultValue) == n && ~isscalar(defaultValue)
    values = reshape(logical(defaultValue), n, 1);
elseif isnumeric(defaultValue) && numel(defaultValue) == n && ~isscalar(defaultValue)
    values = reshape(double(defaultValue), n, 1);
else
    values = repmat(defaultValue, n, 1);
end
end

function source = localNormalizeULAppliedPrecoderSourceBundle(source, mode, transformApplied)
source = strtrim(string(source));
mode = lower(strtrim(string(mode)));
transformApplied = logical(transformApplied);
directMask = mode == "direct_mapping_no_explicit_beam_weights" | (~transformApplied & strlength(mode) == 0);
transformMask = mode == "transform_precoding" | transformApplied;
repairMask = strlength(source) == 0 | lower(source) == "codebook_dft";
source(repairMask & directMask) = "ul_direct_mapping_no_explicit_beam_weights";
source(repairMask & transformMask) = "ul_pusch_transform_precoding";
end

function token = localResolveDirectionalTrialArtifact(T, direction)
direction = upper(strtrim(string(direction)));
vars = strings(0, 1);
if istable(T)
    vars = string(T.Properties.VariableNames);
end
hasFiniteTB = false;
if istable(T) && ismember("TBSize_bits", vars)
    tbBits = double(T.TBSize_bits);
    hasFiniteTB = any(isfinite(tbBits) & tbBits > 0);
end
hasTBSizeColumn = istable(T) && ismember("TBSize_bits", vars);
allTBMissing = ~hasTBSizeColumn;
if hasTBSizeColumn
    tbBits = double(T.TBSize_bits);
    allTBMissing = all(~isfinite(tbBits) | tbBits <= 0);
end
if hasFiniteTB && direction == "DL"
    token = "air_interface/csv/dl_pdsch_trials.csv";
elseif hasFiniteTB && direction == "UL"
    token = "air_interface/csv/ul_pusch_trials.csv";
elseif direction == "UL" && (ismember("PUCCHResourceId", vars) || ...
        (ismember("RequestedFormat", vars) && any(isfinite(double(T.RequestedFormat)))))
    token = "air_interface/csv/pucch_trials.csv";
elseif ismember("DCISize_bits", vars) && any(isfinite(double(T.DCISize_bits)))
    token = "air_interface/csv/pdcch_trials.csv";
elseif ismember("TrackingEstimateSource", vars) && any(strlength(strtrim(string(T.TrackingEstimateSource))) > 0)
    if direction == "UL"
        token = "air_interface/csv/srs_trials.csv";
    else
        token = "air_interface/csv/trs_trials.csv";
    end
elseif ismember("AcquisitionTime_ms", vars) && direction == "DL" && allTBMissing
    token = "air_interface/csv/pbch_trials.csv";
elseif ismember("DetectionMetric", vars) && direction == "UL" && allTBMissing
    token = "air_interface/csv/prach_trials.csv";
elseif direction == "UL"
    token = "air_interface/csv/ul_pusch_trials.csv";
else
    token = "air_interface/csv/dl_pdsch_trials.csv";
end
end

function state = localResolveArtifactStoreState()
state = struct();
try
    state = sixgr.db.artifactStore("get_state");
catch
    state = struct();
end
end

function model = localResolveRequestedLinkChannelModel(cfg)
model = upper(strtrim(string(sixgr.util.structGet(cfg, "channel.model", "AWGN"))));
if strlength(model) == 0 || model == "NONE" || model == "OFF"
    model = "AWGN";
end
if model == "TDL"
    prof = upper(strtrim(string(sixgr.util.structGet(cfg, "channel.tdlProfile", ...
        sixgr.util.structGet(cfg, "channel.fading.profile", "")))));
    if strlength(prof) > 0
        model = prof;
    end
elseif model == "CDL"
    prof = upper(strtrim(string(sixgr.util.structGet(cfg, "channel.cdlProfile", ...
        sixgr.util.structGet(cfg, "channel.fading.profile", "")))));
    if strlength(prof) > 0
        model = prof;
    end
end
end

function T = localCollectPBCHTrials(cfg, snr_dB, nTrials)
nTrials = max(1, round(double(nTrials)));
rows = repmat(localMakeLinkTrialRow(cfg, "DL", snr_dB, 1), nTrials, 1);
pbchObservationSubframes = localResolvePBCHObservationSubframes(cfg);
rootRunFolder = string(sixgr.util.structGet(cfg, "run.rootRunFolder", ""));
writeSIB1Artifacts = strlength(rootRunFolder) > 0 && ...
    logical(sixgr.util.structGet(cfg, "phy.sib1.enable", false));
for k = 1:nTrials
    r = localMakeLinkTrialRow(cfg, "DL", snr_dB, k);
    r.Status = "FAIL";
    try
        ssbIndex = localResolvePBCHSSBIndex(cfg, k);
        cellSearchArgs = {"NumSubframes", pbchObservationSubframes, "SSBIndex", ssbIndex};
        if writeSIB1Artifacts && k == 1
            cellSearchArgs = [cellSearchArgs, {"RunFolder", rootRunFolder, ...
                "RunId", "sib1_runtime_waveform", "WriteArtifacts", true}]; %#ok<AGROW>
        end
        out = sixgr.link.runCellSearch_MIB_SIB1(cfg, cellSearchArgs{:});
        skipped = logical(sixgr.util.structGet(out, "Skipped", false));
        pbch = sixgr.util.structGet(out, "PBCH", struct());
        sib1 = sixgr.util.structGet(out, "SIB1", struct());
        bchCrcPass = localStructLogical(sib1, "BCHCrcPass", ...
            localStructLogical(pbch, "Ok", logical(sixgr.util.structGet(out, "Ok", false))));
        mibDecoded = localStructLogical(sib1, "MIBDecoded", bchCrcPass);
        sib1StrictOk = localStructLogical(sib1, "StrictOk", logical(sixgr.util.structGet(out, "Ok", false)));
        sib1TreeEqual = localStructLogical(sib1, "SIB1TreeEqual", false);
        sib1DciCrcPass = localStructLogical(sib1, "DCICrcPass", false);
        sib1DlschCrcPass = localStructLogical(sib1, "DLSCHCrcPass", false);
        sib1Asn1DecodeOk = localStructLogical(sib1, "SIB1ASN1DecodeOk", false);
        pbchAcquired = bchCrcPass && mibDecoded && ~skipped;
        r.CRCPass = double(pbchAcquired);
        r.CRCApplicable = true;
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
        r.MIBSSBIndex = double(sixgr.util.structGet(sib1, "MIBSSBIndex", ...
            sixgr.util.structGet(pbch, "MIBSSBIndex", NaN)));
        r.PBCHiBarSSB = double(sixgr.util.structGet(sib1, "PBCHiBarSSB", ...
            sixgr.util.structGet(pbch, "iBar_SSB", NaN)));
        r.PBCHv = double(sixgr.util.structGet(sib1, "PBCHv", ...
            sixgr.util.structGet(pbch, "v", NaN)));
        r.SIB1StrictOk = double(sib1StrictOk);
        r.SIB1TreeEqual = double(sib1TreeEqual);
        r.SIB1DCICrcPass = double(sib1DciCrcPass);
        r.SIB1DLSCHCrcPass = double(sib1DlschCrcPass);
        r.SIB1ASN1DecodeOk = double(sib1Asn1DecodeOk);
        r.SIB1FailureReason = string(sixgr.util.structGet(sib1, "FailureReason", ""));
        r.SSBIndex = double(sixgr.util.structGet(out, "SSBIndex", ssbIndex));
        r.BeamIndex = double(sixgr.util.structGet(out, "SSBBeamIndex", r.SSBIndex + 1));
        r.InjectedCFO_Hz = double(sixgr.util.structGet(out, "InjectedCFO_Hz", NaN));
        r.EstimatedCFO_PreCorrection_Hz = double(sixgr.util.structGet(out, "EstimatedCFO_PreCorrection_Hz", NaN));
        r.ResidualCFO_PostCorrection_Hz = double(sixgr.util.structGet(out, "ResidualCFO_PostCorrection_Hz", NaN));
        r.EstimatedCFO_Hz = double(sixgr.util.structGet(out, "EstimatedCFO_Hz", ...
            sixgr.util.structGet(out, "FreqOffsetEstimate_Hz", NaN)));
        r.TrueCFO_Hz = double(sixgr.util.structGet(out, "TrueCFO_Hz", NaN));
        r.CFOError_Hz = double(sixgr.util.structGet(out, "CFOError_Hz", NaN));
        r.InjectedTimingOffset_samples = double(sixgr.util.structGet(out, "InjectedTimingOffset_samples", NaN));
        r.AppliedTimingCorrection_samples = double(sixgr.util.structGet(out, "AppliedTimingCorrection_samples", NaN));
        r.EstimatedTimingOffset_PreCorrection_samples = double(sixgr.util.structGet(out, "EstimatedTimingOffset_PreCorrection_samples", NaN));
        r.ResidualTimingError_PostCorrection_samples = double(sixgr.util.structGet(out, "ResidualTimingError_PostCorrection_samples", NaN));
        r.TimingOffset_samples = double(sixgr.util.structGet(out, "TimingOffset_samples", NaN));
        r.TrueTimingOffset_samples = double(sixgr.util.structGet(out, "TrueTimingOffset_samples", 0));
        r.TimingError_samples = double(sixgr.util.structGet(out, "TimingError_samples", NaN));
        r.TimingEstimateApplicationPolicy = string(sixgr.util.structGet(out, "TimingEstimateApplicationPolicy", ""));
        r.TimingEstimateStatus = string(sixgr.util.structGet(out, "TimingEstimateStatus", ""));
        r.TimingEstimateWasClipped = logical(sixgr.util.structGet(out, "TimingEstimateWasClipped", false));
        r.ComputeLatency_ms = double(sixgr.util.structGet(out, "ComputeLatency_ms", NaN));
        r.ProcedureDelay_ms = double(sixgr.util.structGet(out, "ProcedureDelay_ms", NaN));
        r.AirInterfaceObservation_ms = double(sixgr.util.structGet(out, "AirInterfaceObservation_ms", NaN));
        r.AcquisitionTime_ms = double(sixgr.util.structGet(out, "AcquisitionTime_ms", NaN));
        r.NoiseVariance = double(sixgr.util.structGet(out, "PBCHNoiseVar", ...
            sixgr.util.structGet(pbch, "NoiseVar", NaN)));
        if isfinite(r.NoiseVariance)
            r.NoiseVarStatus = "OK";
            r.NoiseVarSource = "nrChannelEstimate_pbch_dmrs_sss";
            r.NoiseVarReason = "";
        else
            r.NoiseVarStatus = "unavailable";
            r.NoiseVarSource = "";
            r.NoiseVarReason = "pbch_noise_variance_not_reported_by_receiver";
        end
        r.ChannelEstimateAttempted = true;
        r.ChannelEstimateAvailable = logical(sixgr.util.structGet(out, "ChannelEstimateAvailable", ...
            sixgr.util.structGet(pbch, "ChannelEstimateAvailable", false)));
        r.ChannelEstimateSource = string(sixgr.util.structGet(out, "ChannelEstimateSource", ...
            sixgr.util.structGet(pbch, "ChannelEstimateSource", "")));
        r.ResourceExtractionAttempted = true;
        r.ResourceExtractionAvailable = r.ChannelEstimateAvailable;
        r.EqualizationAttempted = true;
        r.EqualizationAvailable = logical(sixgr.util.structGet(out, "EqualizationAvailable", ...
            sixgr.util.structGet(pbch, "EqualizationAvailable", false)));
        r.EqualizerType = string(sixgr.util.structGet(out, "EqualizerType", ...
            sixgr.util.structGet(pbch, "EqualizerType", "")));
        r.ReceiverHestSINR_dB = double(sixgr.util.structGet(out, "ReceiverHestSINR_dB", ...
            sixgr.util.structGet(pbch, "ReceiverHestSINR_dB", NaN)));
        r.ReceiverHestSINRSource = string(sixgr.util.structGet(out, "ReceiverHestSINRSource", ...
            sixgr.util.structGet(pbch, "ReceiverHestSINRSource", "")));
        r.ReceiverHestSINRValueRole = string(sixgr.util.structGet(out, "ReceiverHestSINRValueRole", ...
            sixgr.util.structGet(pbch, "ReceiverHestSINRValueRole", "")));
        r.ReceiverHestSINRValueStatus = string(sixgr.util.structGet(out, "ReceiverHestSINRValueStatus", ...
            sixgr.util.structGet(pbch, "ReceiverHestSINRValueStatus", "")));
        r.ReceiverHestSINRNAReason = string(sixgr.util.structGet(out, "ReceiverHestSINRNAReason", ...
            sixgr.util.structGet(pbch, "ReceiverHestSINRNAReason", "")));
        r.MeasuredTrialSINR_dB = double(sixgr.util.structGet(out, "MeasuredTrialSINR_dB", ...
            sixgr.util.structGet(pbch, "MeasuredTrialSINR_dB", NaN)));
        r.MeasuredTrialSINRSource = string(sixgr.util.structGet(out, "MeasuredTrialSINRSource", ...
            sixgr.util.structGet(pbch, "MeasuredTrialSINRSource", "")));
        r.MeasuredTrialSINRValueRole = string(sixgr.util.structGet(out, "MeasuredTrialSINRValueRole", ...
            sixgr.util.structGet(pbch, "MeasuredTrialSINRValueRole", "")));
        r.MeasuredTrialSINRValueStatus = string(sixgr.util.structGet(out, "MeasuredTrialSINRValueStatus", ...
            sixgr.util.structGet(pbch, "MeasuredTrialSINRValueStatus", "")));
        r.MeasuredTrialSINRNAReason = string(sixgr.util.structGet(out, "MeasuredTrialSINRNAReason", ...
            sixgr.util.structGet(pbch, "MeasuredTrialSINRNAReason", "")));
        r.PostEqSINR_dB = double(sixgr.util.structGet(out, "PostEqSINR_dB", ...
            sixgr.util.structGet(pbch, "PostEqSINR_dB", NaN)));
        r.PostEqSINRSource = string(sixgr.util.structGet(out, "PostEqSINRSource", ...
            sixgr.util.structGet(pbch, "PostEqSINRSource", "")));
        r.PostEqSINRValueRole = string(sixgr.util.structGet(out, "PostEqSINRValueRole", ...
            sixgr.util.structGet(pbch, "PostEqSINRValueRole", "")));
        r.PostEqSINRValueStatus = string(sixgr.util.structGet(out, "PostEqSINRValueStatus", ...
            sixgr.util.structGet(pbch, "PostEqSINRValueStatus", "")));
        r.PostEqSINRNAReason = string(sixgr.util.structGet(out, "PostEqSINRNAReason", ...
            sixgr.util.structGet(pbch, "PostEqSINRNAReason", "")));
        r.MeasuredSINR_dB = r.MeasuredTrialSINR_dB;
        r.SINRValueRole = "measured";
        r.SINRSource = r.MeasuredTrialSINRSource;
        r.SINRValueStatus = r.MeasuredTrialSINRValueStatus;
        r.SINRValueDefinition = "measured_trial_sinr_from_pbch_dmrs_channel_estimate";
        r.LLRAvailable = true;
        r.LLRFinite = logical(pbchAcquired);
        r.LLRNoiseVariance = r.NoiseVariance;
        r.StrictReceiverEvidenceOk = logical(sixgr.util.structGet(out, "StrictReceiverEvidenceOk", ...
            sixgr.util.structGet(pbch, "StrictReceiverEvidenceOk", false))) && ...
            r.ChannelEstimateAvailable && r.EqualizationAvailable && isfinite(r.ReceiverHestSINR_dB);
        r.StrictOk = logical(sib1StrictOk) && logical(r.StrictReceiverEvidenceOk);
        r.ReceiverUsable = logical(r.StrictReceiverEvidenceOk);
        r.MeasurementAttempted = true;
        r.MeasurementUsable = isfinite(r.ReceiverHestSINR_dB) || isfinite(r.MeasuredTrialSINR_dB);
        r.TrackingFailureProbability = double(~pbchAcquired);
        if pbchAcquired
            r.DetectionMetric = 1;
            r.DetectionAttempted = true;
            r.DetectionSuccess = true;
            r.DetectionUsable = true;
            r.MissedDetection = false;
            r.FalseAlarm = false;
            r.DetectionOutcome = "ssb_pbch_mib_acquired";
            r.DecodeAttempted = true;
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
        end
        detectorNotes = string(sixgr.util.structGet(out, "Notes", ""));
        if strlength(strtrim(string(r.Notes))) == 0
            r.Notes = detectorNotes;
        elseif strlength(strtrim(detectorNotes)) > 0
            r.Notes = string(r.Notes) + "; prach_detector_notes=" + detectorNotes;
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
beamCount = localResolveSSBBeamCount(cfg);
if beamCount <= 1
    ssbIndex = 0;
    return;
end
slotBase = 0;
slotVal = double(slotIdx);
if ~isempty(slotVal) && isscalar(slotVal) && isfinite(slotVal)
    slotBase = max(0, round(slotVal) - 1);
end
ueBase = 0;
ueVal = double(ueIdx);
if ~isempty(ueVal) && isscalar(ueVal) && isfinite(ueVal)
    ueBase = max(0, round(ueVal) - 1);
end
ssbIndex = mod(slotBase + ueBase, beamCount);
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

function [T, correlationTraceT, raEvidenceTables] = localCollectPRACHTrials(cfg, snr_dB, nTrials, slotIdx)
nTrials = max(1, round(double(nTrials)));
if nargin < 4
    slotIdx = NaN;
end
rows = repmat(localMakeLinkTrialRow(cfg, "UL", snr_dB, 1), nTrials, 1);
correlationTraceT = table();
raEvidenceTables = localEmptyRAEvidenceTables();
fourStepRequired = localShouldRunFourStepRAForPRACH(cfg);
for k = 1:nTrials
    r = localMakeLinkTrialRow(cfg, "UL", snr_dB, k);
    r.Status = "FAIL";
    try
        if fourStepRequired
            [ra, raRunOk, raRunFailure] = localRunFourStepRAForPRACHTrial(cfg, k, slotIdx, snr_dB);
            if raRunOk
                r = localApplyFourStepRAEvidenceToPRACHRow(r, ra, k, slotIdx);
                raEvidenceTables = localAppendRAEvidenceTables(raEvidenceTables, sixgr.util.structGet(ra, "ArtifactTables", struct()));
            else
                r.CRCPass = 0;
                r.StrictOk = false;
                r.StrictReceiverEvidenceOk = false;
                r.DecodeAttempted = true;
                r.DecodeUsable = false;
                r.ReceiverUsable = false;
                r.Status = "CRASH";
                r.FailureReason = string(raRunFailure);
                r.RAFailureReason = string(raRunFailure);
                r.Notes = "strict_four_step_ra_failed_before_complete_runtime_evidence:" + string(raRunFailure);
                r.RuntimeMaterializationStatus = "four_step_ra_runtime_failed";
                r.RuntimeEvidenceSource = "sixgr.phy.ra.runFourStepRA";
            end
            rows(k) = r;
            continue;
        end
        out = sixgr.link.runPRACHDetection(cfg, "SNR_dB", snr_dB, "CanonicalSlot", slotIdx);
        corrT = sixgr.util.structGet(out, "CorrelationTraceTable", table());
        if istable(corrT) && ~isempty(corrT)
            if ismember("trial_id", string(corrT.Properties.VariableNames))
                corrT.trial_id(:) = double(k);
            end
            correlationTraceT = localAppendCompatTable(correlationTraceT, corrT);
        end
        completed = logical(sixgr.util.structGet(out, "Ok", false)) && ~logical(sixgr.util.structGet(out, "Skipped", false));
        detected = logical(sixgr.util.structGet(out, "Detected", false));
        r.CRCPass = double(detected);
        r.DetectionSuccess = detected;
        r.DetectionMetric = double(sixgr.util.structGet(out, "DetectionMetric", double(detected)));
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
        r.TimingAdvance_samples = double(sixgr.util.structGet(out, "TimingAdvance_samples", r.TimingOffset_samples));
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
        r.CRCPass = 0;
        r.Status = "CRASH";
        r.Notes = string(ME.message);
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

function [ra, ok, failure] = localRunFourStepRAForPRACHTrial(cfg, trialIdx, slotIdx, snr_dB)
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
    ra = sixgr.truth.CoupledTruthRuntime.runFourStepRARuntime(cfg, ...
        "RunFolder", char(raRunFolder), ...
        "RunId", runId, ...
        "ScenarioName", scenarioName, ...
        "UEId", double(ueId), ...
        "CellId", double(cellId), ...
        "AttemptId", double(trialIdx), ...
        "RuntimeSlot", double(slotIdx), ...
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
fields = ["RAProcedureType","RABindingSource","RACHConfigHash", ...
    "PreambleIndexTx","PreambleIndexDetected","PreambleDetectionMetric", ...
    "PreambleDetectionThreshold","PreambleDetected","CollisionDetected", ...
    "PreambleAmbiguityDetected","TimingAdvanceCommand","PreambleReceivedTargetPower_dBm", ...
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
    "RARBytesHex","RAPIDDecoded","RAPIDMatches","TemporaryCRNTI", ...
    "RARULGrantHex","RARULGrantValid","Msg3ScheduledSlot","Msg3PUSCHPRBStart", ...
    "Msg3PUSCHNumPRB","Msg3PUSCHSymbolStart","Msg3PUSCHNumSymbols","Msg3MCS", ...
    "Msg3Modulation","Msg3TBS","Msg3TimingAdvanceApplied","Msg3PUSCHCrcPass", ...
    "Msg3PayloadHex","Msg3ContentionIdentity","Msg4ScheduledSlot","Msg4PDCCHCrcPass", ...
    "Msg4PDSCHCrcPass","Msg4PDSCHNumLayers","Msg4PDSCHConfiguredNumPorts", ...
    "Msg4PDSCHResolvedNumPorts","Msg4PDSCHExplicitMatrixPresent", ...
    "Msg4PDSCHPrecodingActive","Msg4PDSCHPrecodingMode","Msg4PDSCHPrecodingSource", ...
    "Msg4TimingEstimateUsed","Msg4RawTimingEstimate_samples","Msg4AppliedTimingCorrection_samples", ...
    "Msg4TimingEstimateSource","Msg4PostEqSINR_dB","Msg4ReceiverHestSINR_dB", ...
    "Msg4PreEqualizationNoiseVar","Msg4DecoderNoiseVar","Msg4ChannelEstimateAvailable", ...
    "Msg4ChannelEstimateMethod","Msg4ChannelEstimatePilotResidualNMSE_dB", ...
    "Msg4EqualizationAvailable","Msg4LLRFinite","Msg4DemapperLLRCount","Msg4DecoderIterations", ...
    "Msg4PayloadHex","Msg4ContentionIdentity","ContentionIdentityMatches", ...
    "FinalCRNTI","RACompleted","FailureReason","ProxyUsed","Skipped","ToolboxMissing", ...
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
r.RequestedPreambleIndex = r.PreambleIndex;
r.DetectedPreambleIndex = double(sixgr.util.structGet(ra, "PreambleIndexDetected", r.DetectedPreambleIndex));
r.DetectionMetric = double(sixgr.util.structGet(ra, "PreambleDetectionMetric", r.DetectionMetric));
r.CorrelationPeak = r.DetectionMetric;
r.DetectionThreshold = double(sixgr.util.structGet(ra, "PreambleDetectionThreshold", r.DetectionThreshold));
r.RxAntennaCount = double(sixgr.util.structGet(ra, "Msg1RxAntennaCount", r.RxAntennaCount));
r.PDPAverageNoiseFloor = double(sixgr.util.structGet(ra, "Msg1PDPAverageNoiseFloor", r.PDPAverageNoiseFloor));
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
r.TimingOffset_samples = r.TimingAdvance_samples;
r.TimingError_samples = r.TimingAdvance_samples;
r.CollisionFlag = double(logical(sixgr.util.structGet(ra, "CollisionDetected", false)));
r.FalseAlarm = preambleDetected && isfinite(r.DetectedPreambleIndex) && isfinite(r.PreambleIndex) && ...
    round(double(r.DetectedPreambleIndex)) ~= round(double(r.PreambleIndex));
r.FalseAlarmFlag = double(logical(r.FalseAlarm));
r.MissedDetection = ~preambleDetected;
r.CRCPass = double(strictOk);
r.CRCApplicable = true;
if strictOk
    r.CRCOutcome = "pass";
else
    r.CRCOutcome = "fail";
end
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
    r.Notes = "strict_four_step_ra_waveform_chain_completed_msg1_msg2_msg3_msg4";
else
    r.Status = "FAIL";
    r.RAStage = string(sixgr.util.structGet(ra, "ObservedFailureStage", ""));
    r.Notes = "strict_four_step_ra_waveform_chain_failed:" + string(sixgr.util.structGet(ra, "FailureReason", ""));
end
r.RAFailureReason = string(sixgr.util.structGet(ra, "FailureReason", ""));
r.TruthStatus = "real_lls_evidence";
r.SourceClassification = "active_integrated";
r.RuntimeMaterializationStatus = "active_integrated_four_step_ra_waveform_msg1_msg2_msg3_msg4";
r.ControlGatingEffect = "random_access_gate_full_four_step_ra";
r.RuntimeStateConsumer = "CoupledTruthRuntime.applyPRACHTrial";
r.RuntimeConsumer = "CoupledTruthRuntime.applyPRACHTrial";
r.RuntimeEvidenceSource = "sixgr.phy.ra.runFourStepRA";
r.FullRAEvidenceSource = "sixgr.phy.ra.runFourStepRA";
r.FullRAArtifactRunFolder = "control/csv";
end

function tables = localEmptyRAEvidenceTables()
names = localRAEvidenceTableNames();
tables = struct();
for i = 1:numel(names)
    tables.(char(names(i))) = table();
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
    if isfield(in, f) && istable(in.(f)) && ~isempty(in.(f))
        out.(f) = localAppendCompatTable(out.(f), in.(f));
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
    if isfield(tables, f) && istable(tables.(f)) && ~isempty(tables.(f))
        sixgr.util.csvWriteTable(fullfile(layout.ControlCSVDir, string(f) + ".csv"), tables.(f));
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
    "msg2_rar_trials","msg2_pdcch_candidates","msg3_pusch_trials", ...
    "msg4_contention_resolution","ra_timer_events","ra_negative_trials", ...
    "ra_collision_trials","ra_oracle_guard","ra_runtime_stage_waveforms"];
end

function T = localCollectPDCCHTrials(cfg, snr_dB, nTrials, grantContext)
nTrials = max(1, round(double(nTrials)));
rows = repmat(localMakeLinkTrialRow(cfg, "DL", snr_dB, 1), nTrials, 1);
if nargin < 4 || ~isstruct(grantContext)
    grantContext = struct();
end
dciBitsSeed = int8([]);
if isstruct(sixgr.util.structGet(grantContext, "DCI", struct()))
    dciBitsSeed = int8(sixgr.util.structGet(sixgr.util.structGet(grantContext, "DCI", struct()), "Bits", int8([])));
end
for k = 1:nTrials
    r = localMakeLinkTrialRow(cfg, "DL", snr_dB, k);
    r.Status = "FAIL";
    try
        cfgTrial = localResolvePDCCHTrialConfig(cfg, snr_dB, k, nTrials, grantContext);
        txArgs = {};
        if ~isempty(dciBitsSeed)
            txArgs = [txArgs {"DCIBits", dciBitsSeed}]; %#ok<AGROW>
        else
            txArgs = [txArgs {"K", 64}]; %#ok<AGROW>
        end
        [tx, txInfo] = sixgr.phy.dl.PDCCH_Tx(cfgTrial, txArgs{:});
        [rxWave, nVar, replay, noiseOnly] = localApplyPDCCHChannelAndNoise(tx.Waveform, cfgTrial, tx, txInfo, snr_dB);
        tDecode = tic;
        rxArgs = {"Carrier", tx.Carrier, "PDCCH", tx.PDCCH, "K", numel(tx.DCIBits), ...
            "ListLength", 16, "NoiseOnlyWaveform", noiseOnly, "ExpectedDCIBits", tx.DCIBits};
        if isfinite(double(nVar)) && double(nVar) >= 0
            rxArgs = [rxArgs {"NoiseVar", nVar}]; %#ok<AGROW>
        end
        [rx, rxInfo] = sixgr.phy.dl.PDCCH_Rx(rxWave, cfgTrial, rxArgs{:});
        controlLatency_ms = toc(tDecode) * 1e3;
        radioTTI_ms = localSlotDuration(cfgTrial) * 1e3;
        noiseArgs = {"Carrier", tx.Carrier, "PDCCH", tx.PDCCH, "K", numel(tx.DCIBits), ...
            "ListLength", 16, "ExpectedDCIBits", tx.DCIBits};
        if isfinite(double(nVar)) && double(nVar) >= 0
            noiseArgs = [noiseArgs {"NoiseVar", nVar}]; %#ok<AGROW>
        end
        [rxNoise, ~] = sixgr.phy.dl.PDCCH_Rx(noiseOnly, cfgTrial, noiseArgs{:});
        [be, bt] = localBitErrors(tx.DCIBits, rx.DCIBits);
        dciCrcPass = logical(sixgr.util.structGet(rx, "Ok", false)) && ...
            double(sixgr.util.structGet(rx, "ErrFlag", 1)) == 0;
        payloadMatch = logical(sixgr.util.structGet(rx, "DCIPayloadMatch", (be == 0) && (bt == numel(tx.DCIBits))));
        ok = dciCrcPass && payloadMatch;
        candidateT = sixgr.util.structGet(rxInfo, "CandidateResults", table());
        if ~istable(candidateT)
            candidateT = table();
        end
        aggLevel = localPDCCHScalar(tx.PDCCH, "AggregationLevel", NaN);
        usedCCEs = aggLevel;
        availCCEs = localPDCCHAvailableCCEs(tx.PDCCH);
        controlBits = double(sixgr.util.structGet(txInfo, "E", NaN));
        r.TBSize_bits = double(numel(tx.DCIBits));
        r.DCISize_bits = double(numel(tx.DCIBits));
        r.BitsCompared = double(bt);
        r.BitErrors = double(be);
        r.CRCApplicable = true;
        r.CRCPass = double(ok);
        r.CRCOutcome = string(localPDCCHCRCOutcome(dciCrcPass, payloadMatch));
        r.DCICrcPass = logical(dciCrcPass);
        r.PDCCHPayloadMatch = logical(payloadMatch);
        r.PDCCHCausalGrantDecodeOk = logical(sixgr.util.structGet(rx, "CausalGrantDecodeOk", ok));
        r.PDCCHExpectedDCIBitCount = double(numel(tx.DCIBits));
        r.PDCCHDecodedDCIBitCount = double(numel(sixgr.util.structGet(rx, "DCIBits", int8([]))));
        r.PDCCHDCIBitsCompared = double(sixgr.util.structGet(rx, "DCIBitsCompared", bt));
        r.PDCCHDCIBitErrors = double(sixgr.util.structGet(rx, "DCIBitErrors", be));
        r.PDCCHMissedDetection = logical(sixgr.util.structGet(rx, "MissedDetection", ~dciCrcPass));
        r.PDCCHFalseAlarm = logical(sixgr.util.structGet(rx, "FalseAlarm", dciCrcPass && ~payloadMatch));
        r.PDCCHErrFlag = double(sixgr.util.structGet(rx, "ErrFlag", NaN));
        r.DetectionMetric = 1 - (double(be) / max(double(bt), 1));
        r.ConfiguredSNR_dB = double(sixgr.util.structGet(replay, "ConfiguredSNR_dB", snr_dB));
        r.AppliedAWGNSNR_dB = double(sixgr.util.structGet(replay, "AppliedAWGNSNR_dB", NaN));
        r.DesiredSignalPowerBeforeNoise = double(sixgr.util.structGet(replay, "DesiredSignalPowerBeforeNoise", NaN));
        r.CompositeSignalPowerBeforeNoise = double(sixgr.util.structGet(replay, "CompositeSignalPowerBeforeNoise", NaN));
        r.AppliedNoiseSNR_dB = double(sixgr.util.structGet(replay, "AppliedNoiseSNR_dB", NaN));
        r.NoiseVarianceSource = string(sixgr.util.structGet(replay, "NoiseVarianceSource", ""));
        r.ChannelModelApplied = string(sixgr.util.structGet(replay, "ChannelModelApplied", ""));
        r.ChannelFadingApplied = logical(sixgr.util.structGet(replay, "ChannelFadingApplied", false));
        r.AppliedLargeScaleGain_dB = double(sixgr.util.structGet(replay, "AppliedLargeScaleGain_dB", NaN));
        r.AppliedLargeScaleLoss_dB = double(sixgr.util.structGet(replay, "AppliedLargeScaleLoss_dB", NaN));
        r.AppliedBasePathloss_dB = double(sixgr.util.structGet(replay, "AppliedBasePathloss_dB", NaN));
        r.AppliedPathloss_dB = double(sixgr.util.structGet(replay, "AppliedPathloss_dB", NaN));
        r.AppliedShadowFading_dB = double(sixgr.util.structGet(replay, "AppliedShadowFading_dB", NaN));
        r.AppliedO2I_dB = double(sixgr.util.structGet(replay, "AppliedO2I_dB", NaN));
        r.AppliedLargeScaleGainSource = string(sixgr.util.structGet(replay, "AppliedLargeScaleGainSource", ""));
        r.ServingRSRP_dBm = double(sixgr.util.structGet(replay, "ServingRSRP_dBm", NaN));
        r.ServingRSRPSource = string(sixgr.util.structGet(replay, "ServingRSRPSource", ""));
        r.LargeScaleSINR_dB = double(sixgr.util.structGet(replay, "LargeScaleSINR_dB", NaN));
        r.LargeScaleSINRSource = string(sixgr.util.structGet(replay, "LargeScaleSINRSource", ""));
        r.InterferenceMode = string(sixgr.util.structGet(replay, "InterferenceMode", ""));
        r.InjectedCFO_Hz = double(sixgr.util.structGet(replay, "InjectedCFO_Hz", NaN));
        r.TrueCFO_Hz = r.InjectedCFO_Hz;
        r.InjectedTimingOffset_samples = double(sixgr.util.structGet(replay, "InjectedTimingOffset_samples", 0));
        r.TrueTimingOffset_samples = r.InjectedTimingOffset_samples;
        r.IQImbalanceConfigured = logical(sixgr.util.structGet(replay, "IQImbalanceConfigured", false));
        r.IQImbalanceApplied = logical(sixgr.util.structGet(replay, "IQImbalanceApplied", false));
        r.IQImbalanceModel = string(sixgr.util.structGet(replay, "IQImbalanceModel", ""));
        r.ConfiguredIQGainImbalance_dB = double(sixgr.util.structGet(replay, "ConfiguredIQGainImbalance_dB", NaN));
        r.ConfiguredIQPhaseImbalance_deg = double(sixgr.util.structGet(replay, "ConfiguredIQPhaseImbalance_deg", NaN));
        r.IQImbalanceMirrorPowerRatio_dB = double(sixgr.util.structGet(replay, "IQImbalanceMirrorPowerRatio_dB", NaN));
        r.IQImbalanceImageRejection_dB = double(sixgr.util.structGet(replay, "IQImbalanceImageRejection_dB", NaN));
        r.IQImbalanceIQPowerRatio_dB = double(sixgr.util.structGet(replay, "IQImbalanceIQPowerRatio_dB", NaN));
        r.IQImbalanceIQCorrelation = double(sixgr.util.structGet(replay, "IQImbalanceIQCorrelation", NaN));
        r.IQImbalanceEstimatedAlphaAbs = double(sixgr.util.structGet(replay, "IQImbalanceEstimatedAlphaAbs", NaN));
        r.IQImbalanceEstimatedBetaAbs = double(sixgr.util.structGet(replay, "IQImbalanceEstimatedBetaAbs", NaN));
        r.IQImbalanceMeasurementSource = string(sixgr.util.structGet(replay, "IQImbalanceMeasurementSource", ""));
        r.IQImbalanceMeasurementStatus = string(sixgr.util.structGet(replay, "IQImbalanceMeasurementStatus", ""));
        r.ReceiverHestSINR_dB = double(sixgr.util.structGet(rx, "ReceiverHestSINR_dB", NaN));
        r.ReceiverHestSINRSource = string(sixgr.util.structGet(rx, "ReceiverHestSINRSource", ""));
        r.ReceiverHestSINRValueRole = string(sixgr.util.structGet(rx, "ReceiverHestSINRValueRole", ""));
        r.ReceiverHestSINRValueStatus = string(sixgr.util.structGet(rx, "ReceiverHestSINRValueStatus", ""));
        r.ReceiverHestSINRNAReason = string(sixgr.util.structGet(rx, "ReceiverHestSINRNAReason", ""));
        r.MeasuredTrialSINR_dB = NaN;
        r.MeasuredTrialSINRSource = "";
        r.MeasuredTrialSINRValueRole = "unavailable";
        r.MeasuredTrialSINRValueStatus = "unavailable";
        r.MeasuredTrialSINRNAReason = "pdcch_has_no_data_post_equalization_sinr_measurement";
        r.NoiseVariance = double(sixgr.util.structGet(rx, "NoiseVar", NaN));
        r.NoiseVarStatus = string(sixgr.util.structGet(rx, "NoiseVarStatus", ""));
        r.NoiseVarSource = string(sixgr.util.structGet(rx, "NoiseVarSource", ""));
        r.NoiseVarReason = string(sixgr.util.structGet(rx, "NoiseVarReason", ""));
        if strlength(strtrim(r.NoiseVarStatus)) == 0 && isfinite(r.NoiseVariance) && r.NoiseVariance > 0
            r.NoiseVarStatus = "OK";
            r.NoiseVarSource = "pdcch_receiver_noise_variance";
        elseif ~(isfinite(r.NoiseVariance) && r.NoiseVariance > 0)
            r.NoiseVarStrictFailure = true;
            r.NoiseVarReason = "pdcch_noise_variance_missing_or_nonpositive";
        elseif r.NoiseVarStatus ~= "OK"
            r.NoiseVarStrictFailure = true;
        end
        if localThermalNoiseSINRUnavailable(replay)
            r = localMarkControlSINRUnavailable(r, ...
                "thermal_noise_sinr_unavailable_without_runtime_rx_power_or_pathloss");
        end
        r.EVM_rms = double(sixgr.util.structGet(rx, "EVM_rms", NaN));
        r.DecodeAttempted = true;
        r.DecodeUsable = logical(ok);
        r.DetectionAttempted = true;
        r.DetectionSuccess = logical(ok);
        r.DetectionUsable = isfinite(r.DetectionMetric) && height(candidateT) > 0;
        r.MeasurementAttempted = true;
        r.MeasurementUsable = isfinite(r.ReceiverHestSINR_dB) && strcmpi(string(r.ReceiverHestSINRValueStatus), "OK");
        r.FalseAlarmFlag = double(logical(sixgr.util.structGet(rxNoise, "Ok", false)));
        r.BlockingFlag = double(isfinite(aggLevel) && isfinite(availCCEs) && aggLevel > availCCEs);
        r.BlindDecodeCount = double(sixgr.util.structGet(rxInfo, "NumCandidatesTried", height(candidateT)));
        r.AvailableCCECount = availCCEs;
        r.UsedCCECount = usedCCEs;
        r.NonOverlappedCCEUsage = usedCCEs / max(availCCEs, 1);
        r.AggregationLevel = aggLevel;
        r.CandidatesAttempted = r.BlindDecodeCount;
        r.PDCCHBlindSearchEnabled = logical(sixgr.util.structGet(rxInfo, "BlindSearch", false));
        r.PDCCHCandidatesAvailable = double(sixgr.util.structGet(rxInfo, "NumCandidatesAvailable", height(candidateT)));
        r.PDCCHCandidatesAttempted = r.BlindDecodeCount;
        r.PDCCHCandidateIndex = double(sixgr.util.structGet(rx, "CandidateIndex", NaN));
        r.PDCCHSelectedCCEIndex = double(localFiniteOrNaN(r.PDCCHCandidateIndex - 1));
        r.SelectedCCEIndex = r.PDCCHSelectedCCEIndex;
        r.TxCCEIndex = double(sixgr.util.structGet(cfgTrial, "phy.pdcch.candidateCCEIndex", 0));
        r.PDCCHTxCCEIndex = r.TxCCEIndex;
        r.PDCCHDCICrcRNTI = double(sixgr.util.structGet(txInfo, "DCICrcRNTI", NaN));
        r.PDCCHScramblingRNTI = double(sixgr.util.structGet(txInfo, "PDCCHScramblingRNTI", NaN));
        r.PDCCHEncodedBits = controlBits;
        r.PDCCHRECount = double(sixgr.util.structGet(txInfo, "NumPDCCHRE", numel(tx.PDCCHInd)));
        r.PDCCHDMRSRECount = double(sixgr.util.structGet(txInfo, "NumDMRSRE", numel(tx.DMRSInd)));
        r.PDCCHCandidateErrFlagVector = localFormatNumericVector(localColumnOrDefault(candidateT, "ErrFlag", nan(height(candidateT), 1)));
        r.PDCCHCandidateDecodeOKVector = localFormatNumericVector(double(localColumnOrDefault(candidateT, "DecodeOK", false(height(candidateT), 1))));
        r.PDCCHCandidateSINRVector_dB = localFormatNumericVector(localColumnOrDefault(candidateT, "ReceiverHestSINR_dB", nan(height(candidateT), 1)));
        r.PDCCHCandidateRECountVector = localFormatNumericVector(localColumnOrDefault(candidateT, "PDCCHRECount", nan(height(candidateT), 1)));
        r.PDCCHCandidateDMRSRECountVector = localFormatNumericVector(localColumnOrDefault(candidateT, "DMRSRECount", nan(height(candidateT), 1)));
        r.PDCCHCRCDecodeSource = "nrDCIDecode_crc_masked_by_rnti";
        r.PDCCHBlindDecodeEvidenceSource = "nrPDCCHSpace_nrPDCCHDecode_nrDCIDecode";
        r.PDCCHCCE_REGMappingEvidence = "nrPDCCHResources_coreset_search_space_candidate_mapping";
        r.PDCCHREGMappingAvailable = ~isempty(tx.PDCCHInd) && ~isempty(tx.DMRSInd);
        r.PDCCHCORESETDuration = localPDCCHScalar(tx.PDCCH.CORESET, "Duration", NaN);
        r.PDCCHCORESETFrequencyResources = localFormatNumericVector(localPDCCHScalarVector(tx.PDCCH.CORESET, "FrequencyResources"));
        r.PDCCHSearchSpaceNumCandidates = localFormatNumericVector(localPDCCHScalarVector(tx.PDCCH.SearchSpace, "NumCandidates"));
        r.PDCCHGridHash = localComplexSHA256(tx.Grid);
        r.PDCCHWaveformHash = localComplexSHA256(tx.Waveform);
        r.PDCCHResourceHash = localPDCCHResourceHash(tx.PDCCHInd, tx.DMRSInd);
        r.ControlCapacityBits = controlBits;
        r.ControlCapacityUtilization = double(numel(tx.DCIBits)) / max(controlBits, 1);
        r.CORESETUtilization = usedCCEs / max(availCCEs, 1);
        r.ComputeLatency_ms = controlLatency_ms;
        r.ProcedureDelay_ms = NaN;
        r.AirInterfaceTTI_ms = radioTTI_ms;
        % Legacy alias preserved for backward compatibility with older exports.
        % It mirrors the control opportunity duration, not wall-clock decode runtime.
        r.ControlLatency_ms = radioTTI_ms;
        r.ResourceExtractionAttempted = true;
        r.ResourceExtractionAvailable = ~isempty(tx.PDCCHInd) && ~isempty(rx.EqualizedSymbols);
        r.ChannelEstimateAttempted = true;
        r.ChannelEstimateAvailable = localHasFiniteNumericEvidence(sixgr.util.structGet(rx, "ChannelEstimate", []));
        r.ChannelEstimateSource = "nrChannelEstimate_pdcch_dmrs";
        r.EqualizationAttempted = true;
        r.EqualizationAvailable = localHasFiniteNumericEvidence(sixgr.util.structGet(rx, "EqualizedSymbols", []));
        noiseOk = isfinite(r.NoiseVariance) && r.NoiseVariance > 0 && strcmpi(string(r.NoiseVarStatus), "OK") && ...
            ~logical(r.NoiseVarStrictFailure);
        strictOk = logical(ok) && logical(r.DetectionUsable) && logical(r.MeasurementUsable) && ...
            logical(r.ChannelEstimateAvailable) && logical(r.ResourceExtractionAvailable) && ...
            logical(r.EqualizationAvailable) && noiseOk && ~logical(r.FalseAlarmFlag);
        r.StrictReceiverEvidenceOk = logical(strictOk);
        r.StrictOk = logical(strictOk);
        r.ReceiverUsable = logical(strictOk);
        r.TruthStatus = "real_pdcch_waveform_blind_dci_crc_evidence";
        r.SourceClassification = "active_integrated";
        r.RuntimeMaterializationStatus = "active_integrated_pdcch_blind_dci_crc_cce_reg_evidence";
        r.RuntimeEvidenceSource = "sixgr.phy.dl.PDCCH_Tx|sixgr.phy.dl.PDCCH_Rx";
        if strictOk
            r.Status = "PASS";
        else
            r.Status = "FAIL";
            r.FailureReason = localPDCCHStrictFailureReason(r, rx, be, bt, payloadMatch, dciCrcPass, noiseOk);
        end
        if ~isempty(dciBitsSeed)
            r.Notes = "Grant-coupled PDCCH DCI payload decoded through blind candidate search, channel estimation, MMSE equalization, and RNTI-masked DCI CRC.";
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

function tf = localThermalNoiseSINRUnavailable(replay)
noiseMode = lower(strtrim(string(sixgr.util.structGet(replay, "NoiseOperatingMode", ""))));
if noiseMode ~= "receiver_noise_figure_thermal_noise"
    tf = false;
    return;
end
servingSource = lower(strtrim(string(sixgr.util.structGet(replay, "ServingRxPowerSource", ""))));
noiseSource = lower(strtrim(string(sixgr.util.structGet(replay, "NoisePowerSource", ""))));
tf = servingSource == "unavailable_missing_pathloss_or_runtime_rx_power" || ...
    noiseSource == "thermal_noise_unavailable_missing_pathloss_or_runtime_rx_power";
end

function r = localMarkControlSINRUnavailable(r, reason)
reason = string(reason);
r.ReceiverHestSINR_dB = NaN;
r.ReceiverHestSINRSource = "";
r.ReceiverHestSINRValueRole = "unavailable";
r.ReceiverHestSINRValueStatus = "unavailable";
r.ReceiverHestSINRNAReason = reason;
r.MeasuredTrialSINR_dB = NaN;
r.MeasuredTrialSINRSource = "";
r.MeasuredTrialSINRValueRole = "unavailable";
r.MeasuredTrialSINRValueStatus = "unavailable";
r.MeasuredTrialSINRNAReason = reason;
r.MeasuredSINR_dB = NaN;
r.SINRValueRole = "unavailable";
r.SINRSource = "";
r.SINRValueStatus = "unavailable";
r.SINRValueDefinition = "no_control_sinr_observation_available_without_runtime_noise_power_anchor";
end

function [y, nVar, replay, noiseOnlyWave] = localApplyPDCCHChannelAndNoise(x, cfg, tx, txInfo, snr_dB)
if nargin < 4 || ~isstruct(txInfo)
    txInfo = struct();
end
if ~isfield(txInfo, "OFDM")
    try
        txInfo.OFDM = nrOFDMInfo(tx.Carrier);
    catch
        txInfo.OFDM = struct();
    end
end
state = sixgr.link.initWaveformTruthChannelState(cfg, tx, txInfo);
sampleRateHz = double(sixgr.util.structGet(state, "SampleRate_Hz", localResolvePDCCHSampleRate(tx, txInfo)));
y = x;
replay = struct( ...
    "ConfiguredSNR_dB", double(snr_dB), ...
    "AppliedAWGNSNR_dB", double(snr_dB), ...
    "InjectedNoiseVariance", NaN, ...
    "NoiseVarianceSource", "", ...
    "ChannelModelApplied", string(sixgr.util.structGet(cfg, "channel.model", "AWGN")), ...
    "ChannelFadingApplied", false);

[y, channelReplay, state] = sixgr.link.applyRuntimeFadingChannel(x, state); %#ok<ASGLU>
chFields = fieldnames(channelReplay);
for chIdx = 1:numel(chFields)
    replay.(chFields{chIdx}) = channelReplay.(chFields{chIdx});
end

cfgReplay = sixgr.util.structSet(cfg, "channel.snr_dB", double(snr_dB));
% Thermal receiver noise is injected below from the calibrated replay link
% budget. Keep grant-coupled PDCCH at the pre-ADC analog sample point so a
% pathloss-scaled control waveform is not quantized to exact zero before
% the noise/pilot evidence reaches PDCCH_Rx.
[y, impairmentReplay] = sixgr.link.applyWaveformImpairments(y, cfgReplay, sampleRateHz, "ApplyADC", false);
fields = fieldnames(impairmentReplay);
for ii = 1:numel(fields)
    replay.(fields{ii}) = impairmentReplay.(fields{ii});
end
replay.ChannelModelApplied = string(sixgr.util.structGet(cfg, "channel.model", replay.ChannelModelApplied));
replay.ChannelFadingApplied = logical(sixgr.util.structGet(replay, "ChannelFadingApplied", false)) || ...
    logical(sixgr.util.structGet(state, "UseFading", false));
desiredWaveform = y;
[y, nVar, noiseInfo] = localPDCCHAddAwgnFromReplay(y, replay, desiredWaveform, txInfo);
replay.InjectedNoiseVariance = double(nVar);
noiseFields = fieldnames(noiseInfo);
for ni = 1:numel(noiseFields)
    replay.(noiseFields{ni}) = noiseInfo.(noiseFields{ni});
end
if isfinite(nVar) && nVar > 0 && strlength(strtrim(string(sixgr.util.structGet(replay, "NoiseVarianceSource", "")))) == 0
    replay.NoiseVarianceSource = "pdcch_replay_reference_waveform_awgn";
end
noiseOnlyWave = localPDCCHNoiseOnlyWaveformLike(y, nVar);
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
if isempty(sampleRateHz) || ~(isfinite(double(sampleRateHz)) && double(sampleRateHz) > 0)
    sampleRateHz = 30.72e6;
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
    y = x;
    nVar = NaN;
    return;
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
[y, nVar] = sixgr.util.addAwgnComplex(x, appliedSNR_dB);
noiseInfo = localPDCCHNoiseCalibrationInfo(x, referenceWaveform, nVar, "legacy_addAwgnComplex_last_resort", replay);
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

function nVar = localPDCCHResolveThermalNoiseVariance(replay, referenceWaveform, txInfo)
nVar = NaN;
thermalNoisePower_dBm = double(sixgr.util.structGet(replay, "ThermalNoisePower_dBm", NaN));
servingRxPower_dBm = double(sixgr.util.structGet(replay, "ServingRxPower_dBm", NaN));
if ~(isfinite(thermalNoisePower_dBm) && isfinite(servingRxPower_dBm))
    return;
end
refPower = localPDCCHUsefulOFDMReferencePower(referenceWaveform, txInfo);
if ~(isfinite(refPower) && refPower >= 0)
    return;
end
relativeNoise_dB = thermalNoisePower_dBm - servingRxPower_dBm;
nVar = refPower * 10.^(relativeNoise_dB / 10);
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

function noiseOnlyWave = localPDCCHNoiseOnlyWaveformLike(referenceWaveform, nVar)
noiseOnlyWave = zeros(size(referenceWaveform), "like", referenceWaveform);
if isfinite(double(nVar)) && double(nVar) > 0
    n = sqrt(double(nVar) / 2) .* ...
        (randn(size(referenceWaveform), "like", real(referenceWaveform)) + ...
        1i * randn(size(referenceWaveform), "like", real(referenceWaveform)));
    noiseOnlyWave = cast(n, "like", referenceWaveform);
end
end

function T = localBuildPDCCHCapacityBlockedTrial(cfg, snr_dB, aggLevel, availableCCEs, usedBefore, reason)
r = localMakeLinkTrialRow(cfg, "DL", snr_dB, 1);
r.Status = "BLOCKED";
r.CRCPass = NaN;
r.CRCApplicable = false;
r.DetectionMetric = NaN;
r.DecodeAttempted = false;
r.DecodeUsable = false;
r.DetectionAttempted = false;
r.DetectionUsable = false;
r.MeasurementAttempted = false;
r.MeasurementUsable = false;
r.ReceiverUsable = false;
r.BlockingFlag = 1;
r.AggregationLevel = double(aggLevel);
r.UsedCCECount = double(aggLevel);
r.AvailableCCECount = double(availableCCEs);
r.NonOverlappedCCEUsage = double(usedBefore + aggLevel) / max(double(availableCCEs), 1);
r.CORESETUtilization = double(usedBefore) / max(double(availableCCEs), 1);
r.ControlCapacityUtilization = r.NonOverlappedCCEUsage;
r.FailureReason = string(reason);
r.NoiseVarStatus = "NOT_APPLICABLE";
r.NoiseVarSource = "pdcch_decode_not_attempted";
r.NoiseVarReason = string(reason);
r.ReceiverHestSINRValueStatus = "not_applicable";
r.ReceiverHestSINRNAReason = string(reason);
r.MeasuredTrialSINRValueStatus = "not_applicable";
r.MeasuredTrialSINRNAReason = string(reason);
r.RuntimeMaterializationStatus = "active_integrated_grant_coupled_dci_control_capacity_gate";
r.ValueStatus = "blocked_no_control_channel_resource";
r.Notes = "PDCCH decode was not attempted because the configured CORESET/search-space CCE budget was exhausted before this grant.";
T = struct2table(r, "AsArray", true);
end

function key = localPDCCHControlResourceKey(grant, controlFrameIdx, controlSlotIdx)
servingCell = double(sixgr.util.structGet(grant, "ServingCell", ...
    sixgr.util.structGet(grant, "BaseStationID", NaN)));
if ~(isfinite(servingCell) && servingCell >= 1)
    servingCell = 0;
end
key = sprintf("frame_%d_slot_%d_cell_%d", ...
    round(double(controlFrameIdx)), round(double(controlSlotIdx)), round(double(servingCell)));
end

function value = localMapGetDouble(mapObj, key, defaultValue)
value = double(defaultValue);
try
    key = char(string(key));
    if isKey(mapObj, key)
        value = double(mapObj(key));
    end
catch
    value = double(defaultValue);
end
end

function localMapSetDouble(mapObj, key, value)
try
    mapObj(char(string(key))) = double(value);
catch
end
end

function reason = localPDCCHDecodeFailureReason(rx, bitErrors, bitsCompared)
if ~logical(sixgr.util.structGet(rx, "Ok", false))
    errFlag = double(sixgr.util.structGet(rx, "ErrFlag", NaN));
    if isfinite(errFlag) && errFlag ~= 0
        reason = "pdcch_dci_crc_failed";
    else
        reason = "pdcch_decode_not_ok";
    end
else
    reason = "pdcch_dci_bit_mismatch_after_crc";
end
bitErrors = double(bitErrors);
bitsCompared = double(bitsCompared);
if isfinite(bitErrors) && bitErrors > 0 && isfinite(bitsCompared) && bitsCompared > 0
    reason = reason + "_bit_errors_" + string(round(bitErrors)) + "_of_" + string(round(bitsCompared));
end
noiseStatus = string(sixgr.util.structGet(rx, "NoiseVarStatus", ""));
if strlength(strtrim(noiseStatus)) > 0 && noiseStatus ~= "OK"
    reason = reason + "_noisevar_" + noiseStatus;
end
end

function outcome = localPDCCHCRCOutcome(dciCrcPass, payloadMatch)
if logical(dciCrcPass) && logical(payloadMatch)
    outcome = "pass";
elseif logical(dciCrcPass)
    outcome = "crc_pass_payload_mismatch";
else
    outcome = "fail";
end
end

function reason = localPDCCHStrictFailureReason(r, rx, bitErrors, bitsCompared, payloadMatch, dciCrcPass, noiseOk)
parts = strings(0, 1);
if ~logical(dciCrcPass)
    parts(end+1, 1) = "pdcch_dci_crc_failed"; %#ok<AGROW>
end
if ~logical(payloadMatch)
    parts(end+1, 1) = localPDCCHDecodeFailureReason(rx, bitErrors, bitsCompared); %#ok<AGROW>
end
if ~logical(r.DetectionUsable)
    parts(end+1, 1) = "pdcch_blind_candidate_detection_evidence_missing"; %#ok<AGROW>
end
if ~logical(r.MeasurementUsable)
    parts(end+1, 1) = "pdcch_receiver_hest_sinr_missing_or_not_ok"; %#ok<AGROW>
end
if ~logical(r.ChannelEstimateAvailable)
    parts(end+1, 1) = "pdcch_dmrs_channel_estimate_missing"; %#ok<AGROW>
end
if ~logical(r.ResourceExtractionAvailable)
    parts(end+1, 1) = "pdcch_resource_extraction_missing"; %#ok<AGROW>
end
if ~logical(r.EqualizationAvailable)
    parts(end+1, 1) = "pdcch_equalized_symbol_evidence_missing"; %#ok<AGROW>
end
if ~logical(noiseOk)
    parts(end+1, 1) = "pdcch_noise_variance_missing_or_not_ok"; %#ok<AGROW>
end
if logical(r.FalseAlarmFlag)
    parts(end+1, 1) = "pdcch_noise_only_false_alarm_detected"; %#ok<AGROW>
end
if isempty(parts)
    parts(end+1, 1) = "pdcch_strict_receiver_evidence_incomplete"; %#ok<AGROW>
end
reason = strjoin(parts, ";");
end

function aggLevel = localResolveGrantPDCCHAggregationLevelForCapacity(cfg, snr_dB, grantContext)
grantAggLevel = double(sixgr.util.structGet(grantContext, "PDCCHAggregationLevel", NaN));
policy = lower(strtrim(string(sixgr.util.structGet(cfg, "phy.pdcch.aggregationSelectionPolicy", "snr_threshold"))));
grantAggAuthority = lower(strtrim(string(sixgr.util.structGet(grantContext, "PDCCHAggregationLevelAuthority", ""))));
trustedGrantAL = any(grantAggAuthority == ["runtime_pdcch_decode", "measured_pdcch_decode", "explicit_grant_control"]);
if isfinite(grantAggLevel) && any(grantAggLevel == [1 2 4 8 16]) && ...
        (trustedGrantAL || policy == "configured_scheduler_level")
    aggLevel = double(grantAggLevel);
    return;
end
cfgTrial = localResolvePDCCHTrialConfig(cfg, snr_dB, 1, 1, grantContext);
aggLevel = double(sixgr.util.structGet(cfgTrial, "phy.pdcch.aggregationLevel", NaN));
if ~(isfinite(aggLevel) && any(aggLevel == [1 2 4 8 16]))
    aggLevel = 4;
end
end

function availCCEs = localResolvePDCCHCCEBudgetFromConfig(cfg)
freqResources = double(sixgr.util.structGet(cfg, "phy.pdcch.coreset.frequencyResources", []));
if isempty(freqResources)
    freqResources = ones(1, 6);
end
duration = double(sixgr.util.structGet(cfg, "phy.pdcch.coreset.duration", 2));
if ~(isfinite(duration) && duration > 0)
    availCCEs = NaN;
    return;
end
numREG = 6 * sum(freqResources(:) ~= 0) * duration;
availCCEs = floor(numREG / 6);
end

function cfgTrial = localResolvePDCCHTrialConfig(cfg, snr_dB, trialIdx, nTrials, grantContext)
cfgTrial = cfg;
levels = double(sixgr.util.structGet(cfg, "phy.pdcch.aggregationLevels", ...
    sixgr.util.structGet(cfg, "control.aggregation_levels", ...
    sixgr.util.structGet(cfg, "ctrl6gr.StudyAggregationLevels", ...
    sixgr.util.structGet(cfg, "phy.pdcch.aggregationLevel", 4)))));
levels = unique(levels(ismember(levels, [1 2 4 8 16])), "stable");
if isempty(levels)
    levels = 4;
end
if nargin >= 5 && isstruct(grantContext) && ~isempty(fieldnames(grantContext))
    aggLevel = localSelectGrantPDCCHAggregationLevel(cfg, levels, snr_dB);
else
    nTrials = max(1, round(double(nTrials)));
    idx = mod(max(1, round(double(trialIdx))) - 1, numel(levels)) + 1;
    if nTrials == 1
        aggLevel = localSelectPDCCHAggregationLevel(levels, snr_dB);
    else
        aggLevel = levels(idx);
    end
end
cfgTrial = sixgr.util.structSet(cfgTrial, "phy.pdcch.aggregationLevel", double(aggLevel));
cfgTrial = sixgr.util.structSet(cfgTrial, "phy.pdcch.blindSearch", true);
cfgTrial = sixgr.util.structSet(cfgTrial, "lls6g.userContext.RuntimeSignalFamily", "PDCCH");
cfgTrial = sixgr.util.structSet(cfgTrial, "phy.runtimeSignalFamily", "PDCCH");
end

function aggLevel = localSelectGrantPDCCHAggregationLevel(cfg, levels, snr_dB)
levels = unique(double(levels(ismember(levels, [1 2 4 8 16]))), "stable");
if isempty(levels)
    levels = 4;
end
policy = lower(strtrim(string(sixgr.util.structGet(cfg, "phy.pdcch.aggregationSelectionPolicy", "snr_threshold"))));
configuredAL = double(sixgr.util.structGet(cfg, "phy.pdcch.schedulerAggregationLevel", NaN));
if (policy == "configured_scheduler_level") && isfinite(configuredAL)
    if any(levels == configuredAL)
        aggLevel = configuredAL;
        return;
    end
    [~, idx] = min(abs(levels - configuredAL));
    aggLevel = double(levels(idx));
    return;
end
if policy == "most_robust"
    aggLevel = max(levels);
    return;
end
aggLevel = localSelectPDCCHAggregationLevel(levels, snr_dB);
end

function aggLevel = localSelectPDCCHAggregationLevel(levels, snr_dB)
snr_dB = double(snr_dB);
if ~isfinite(snr_dB)
    target = 4;
elseif snr_dB < 0
    target = 16;
elseif snr_dB < 5
    target = 8;
elseif snr_dB < 10
    target = 4;
elseif snr_dB < 15
    target = 2;
else
    target = 1;
end
[~, idx] = min(abs(double(levels(:)) - double(target)));
aggLevel = double(levels(idx));
end

function T = localAnnotateGrantControlTrial(T, grant)
if ~(istable(T) && ~isempty(T) && isstruct(grant))
    return;
end
heightT = height(T);
transmittedLayers = double(sixgr.util.structGet(grant, "NumLayers", sixgr.util.structGet(grant, "Layers", NaN)));
rankIndicator = double(sixgr.util.structGet(grant, "RIUsed", ...
    sixgr.util.structGet(grant, "RankIndicator", ...
    sixgr.util.structGet(grant, "RI", ...
    sixgr.util.structGet(grant, "Rank", transmittedLayers)))));
if ~(isfinite(rankIndicator) && rankIndicator >= 1) && isfinite(transmittedLayers) && transmittedLayers >= 1
    rankIndicator = double(transmittedLayers);
end
annotations = {
    "PDCCHGatingActive", logical(sixgr.util.structGet(grant, "PDCCHGatingActive", false));
    "GrantControlState", string(sixgr.util.structGet(grant, "GrantControlState", "control_pending"));
    "ControlDecodeOk", logical(sixgr.util.structGet(grant, "ControlDecodeOk", false));
    "UEID", double(sixgr.util.structGet(grant, "UEIndex", NaN));
    "BaseStationID", double(sixgr.util.structGet(grant, "ServingCell", NaN));
    "GrantFrame", double(sixgr.util.structGet(grant, "Frame", NaN));
    "GrantSlot", double(sixgr.util.structGet(grant, "Slot", NaN));
    "ControlFrame", double(sixgr.util.structGet(grant, "ControlFrame", NaN));
    "ControlSlot", double(sixgr.util.structGet(grant, "ControlSlot", NaN));
    "ScheduledAbsoluteSlot", double(sixgr.util.structGet(grant, "ScheduledAbsoluteSlot", sixgr.util.structGet(grant, "Slot", NaN)));
    "K2Slots", double(sixgr.util.structGet(grant, "K2Slots", NaN));
    "LastSuccessfulSRSSlot", double(sixgr.util.structGet(grant, "LastSuccessfulSRSSlot", NaN));
    "SRSAgeSlots", double(sixgr.util.structGet(grant, "SRSAgeSlots", NaN));
    "AllocatedPRBCount", double(numel(double(sixgr.util.structGet(grant, "PRBSet", []))));
    "PRBStart", double(localFirstFinite(double(sixgr.util.structGet(grant, "PRBSet", [])), NaN));
    "MCSIndex", double(sixgr.util.structGet(grant, "MCSIndex", NaN));
    "Layers", transmittedLayers;
    "Rank", transmittedLayers;
    "RankIndicator", rankIndicator
    };
for i = 1:size(annotations, 1)
    name = char(annotations{i, 1});
    value = annotations{i, 2};
    if isstring(value) || ischar(value)
        token = string(value);
        if ~isscalar(token)
            token = token(1);
        end
        T.(name) = repmat(token, heightT, 1);
    elseif islogical(value)
        flag = logical(value);
        if ~isscalar(flag)
            flag = flag(1);
        end
        T.(name) = repmat(flag, heightT, 1);
    else
        numValue = double(value);
        if ~isscalar(numValue)
            numValue = localFirstFinite(numValue, NaN);
        end
        T.(name) = repmat(numValue, heightT, 1);
    end
end
end

function value = localFirstFinite(vals, defaultValue)
vals = double(vals(:));
vals = vals(isfinite(vals));
if isempty(vals)
    value = double(defaultValue);
else
    value = double(vals(1));
end
end

function [lhs, rhs] = localHarmonizeStructArrays(lhs, rhs)
if ~isstruct(lhs)
    lhs = struct();
end
if ~isstruct(rhs)
    rhs = struct();
end
lhsFields = string(fieldnames(lhs));
rhsFields = string(fieldnames(rhs));
allFields = union(lhsFields, rhsFields, "stable");
for i = 1:numel(allFields)
    fieldName = char(allFields(i));
    if ~isfield(lhs, fieldName)
        [lhs(1:numel(lhs)).(fieldName)] = deal([]);
    end
    if ~isfield(rhs, fieldName)
        [rhs(1:numel(rhs)).(fieldName)] = deal([]);
    end
end
end

function availCCEs = localPDCCHAvailableCCEs(pdcch)
availCCEs = NaN;
if isempty(pdcch)
    return;
end
core = [];
try
    core = pdcch.CORESET;
catch
end
if isempty(core)
    return;
end
freqResources = localPDCCHScalar(core, "FrequencyResources", []);
duration = localPDCCHScalar(core, "Duration", NaN);
if isempty(freqResources) || ~isfinite(duration) || duration <= 0
    return;
end
numREG = 6 * sum(freqResources ~= 0) * duration;
availCCEs = floor(numREG / 6);
end

function value = localPDCCHScalar(obj, propName, defaultValue)
value = defaultValue;
if isempty(obj)
    return;
end
try
    value = obj.(propName);
catch
    return;
end
if isnumeric(value)
    value = double(value);
elseif islogical(value)
    value = double(value);
end
end

function value = localPDCCHScalarVector(obj, propName)
value = [];
if isempty(obj)
    return;
end
try
    value = obj.(propName);
catch
    value = [];
    return;
end
if isnumeric(value) || islogical(value)
    value = double(value(:).');
else
    value = [];
end
end

function value = localFiniteOrNaN(value)
value = double(value);
if ~(isscalar(value) && isfinite(value))
    value = NaN;
end
end

function tf = localHasFiniteNumericEvidence(value)
tf = false;
if isempty(value)
    return;
end
try
    vals = abs(double(value(:)));
    tf = any(isfinite(vals));
catch
    tf = false;
end
end

function hash = localComplexSHA256(value)
hash = "";
if isempty(value)
    return;
end
try
    data = single([real(value(:)).'; imag(value(:)).']);
    hash = string(sixgr.rrc.asn1.sha256Hex(typecast(data(:), "uint8")));
catch
    hash = "";
end
end

function hash = localPDCCHResourceHash(pdcchInd, dmrsInd)
hash = "";
try
    payload = struct("PDCCHInd", double(pdcchInd(:).'), "DMRSInd", double(dmrsInd(:).'));
    hash = string(sixgr.rrc.asn1.sha256Hex(uint8(unicode2native(jsonencode(payload), "UTF-8"))));
catch
    hash = "";
end
end

function T = localCollectPUCCHTrials(cfg, snr_dB, nTrials)
nTrials = max(1, round(double(nTrials)));
rows = repmat(localMakeLinkTrialRow(cfg, "UL", snr_dB, 1), nTrials, 1);
chState = [];
for k = 1:nTrials
    r = localMakeLinkTrialRow(cfg, "UL", snr_dB, k);
    r.Status = "FAIL";
    uci = int8(randi([0 1], 20, 1));
    try
        out = sixgr.link.runPUCCHWaveformTrial(cfg, ...
            "ExpectedUCIBits", uci, ...
            "Format", 2, ...
            "SNR_dB", snr_dB, ...
            "TrialIndex", k, ...
            "ChannelState", chState);
        chState = sixgr.util.structGet(out, "ChannelState", chState);
        ok = logical(sixgr.util.structGet(out, "Ok", false)) && ~logical(sixgr.util.structGet(out, "Skipped", false));
        r.TBSize_bits = double(numel(uci));
        r.BitsCompared = double(sixgr.util.structGet(out, "BitsCompared", NaN));
        r.BitErrors = double(sixgr.util.structGet(out, "BitErrors", NaN));
        r.ExpectedBitCount = double(sixgr.util.structGet(out, "ExpectedBitCount", numel(uci)));
        r.DecodedBitCount = double(sixgr.util.structGet(out, "DecodedBitCount", NaN));
        r.UCIExpectedBitVector = string(sixgr.util.structGet(out, "UCIExpectedBitVector", ""));
        r.UCIDecodedBitVector = string(sixgr.util.structGet(out, "UCIDecodedBitVector", ""));
        r.UCIBitErrorVector = string(sixgr.util.structGet(out, "UCIBitErrorVector", ""));
        r.UCICodedBitCount = double(sixgr.util.structGet(out, "UCICodedBitCount", NaN));
        r.UCICRCBitCount = double(sixgr.util.structGet(out, "UCICRCBitCount", NaN));
        r.UCICRCApplicable = logical(sixgr.util.structGet(out, "UCICRCApplicable", false));
        r.CRCApplicable = logical(sixgr.util.structGet(out, "CRCApplicable", false));
        r.CRCOutcome = string(sixgr.util.structGet(out, "CRCOutcome", ternaryPUCCHCRCOutcome(r.CRCApplicable, ok)));
        r.UCIContentMatch = logical(sixgr.util.structGet(out, "UCIContentMatch", ok));
        r.DetectionOutcome = string(sixgr.util.structGet(out, "DetectionOutcome", ternaryPUCCHDetectionOutcome( ...
            logical(sixgr.util.structGet(out, "DetectionUsable", false)), r.UCIContentMatch)));
        if logical(r.CRCApplicable)
            r.CRCPass = double(ok);
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
        r.ProcedureDelay_ms = double(sixgr.util.structGet(out, "ProcedureDelay_ms", 0));
        r.NoiseVariance = double(sixgr.util.structGet(out, "NoiseVariance", NaN));
        r.NoiseVarStatus = string(sixgr.util.structGet(out, "NoiseVarStatus", ""));
        r.NoiseVarSource = string(sixgr.util.structGet(out, "NoiseVarSource", ""));
        r.NoiseVarReason = string(sixgr.util.structGet(out, "NoiseVarReason", ""));
        r.NoiseVarStrictFailure = logical(sixgr.util.structGet(out, "NoiseVarStrictFailure", false));
        r.ReceiverUsable = logical(sixgr.util.structGet(out, "ReceiverUsable", false));
        r.DetectionAttempted = logical(sixgr.util.structGet(out, "DetectionAttempted", false));
        r.DetectionSuccess = logical(ok);
        r.DetectionUsable = logical(sixgr.util.structGet(out, "DetectionUsable", false));
        r.FailureReason = string(sixgr.util.structGet(out, "FailureReason", ""));
        r.ChannelEstimateAttempted = logical(sixgr.util.structGet(out, "ChannelEstimateAttempted", false));
        r.ChannelEstimateAvailable = logical(sixgr.util.structGet(out, "ChannelEstimateAvailable", false));
        r.ChannelEstimateSource = "nrPUCCHDMRS_nrChannelEstimate";
        r.ResourceExtractionAttempted = logical(sixgr.util.structGet(out, "ResourceExtractionAttempted", false));
        r.ResourceExtractionAvailable = logical(sixgr.util.structGet(out, "ResourceExtractionAvailable", false));
        r.EqualizationAttempted = logical(sixgr.util.structGet(out, "EqualizationAttempted", false));
        r.EqualizationAvailable = logical(sixgr.util.structGet(out, "EqualizationAvailable", false));
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
        r.DecodeAttempted = true;
        r.DecodeUsable = logical(r.StrictOk);
        r.MeasurementAttempted = true;
        r.MeasurementUsable = isfinite(r.PUCCHControlSINR_dB) || ...
            (isfinite(r.ReceiverHestSINR_dB) && strcmpi(string(r.ReceiverHestSINRValueStatus), "OK"));
        r.ReceiverUsable = logical(r.StrictReceiverEvidenceOk);
        r.TruthStatus = "real_pucch_waveform_uci_receiver_evidence";
        r.SourceClassification = "active_integrated";
        r.RuntimeMaterializationStatus = "active_integrated_pucch_waveform_uci_resource_receiver_evidence";
        r.RuntimeEvidenceSource = "sixgr.link.runPUCCHWaveformTrial";
        r.Crash = logical(sixgr.util.structGet(out, "Crash", false));
        r.Notes = string(sixgr.util.structGet(out, "Notes", ""));
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

function [T, chState] = localCollectSRSTrials(cfg, snr_dB, nTrials, chState, trialOffset)
if nargin < 4
    chState = [];
end
if nargin < 5
    trialOffset = 0;
end
nTrials = max(1, round(double(nTrials)));
rows = repmat(localMakeLinkTrialRow(cfg, "UL", snr_dB, 1), nTrials, 1);
for k = 1:nTrials
    r = localMakeLinkTrialRow(cfg, "UL", snr_dB, k);
    r.Status = "FAIL";
    try
        srsArgs = {"SNR_dB", snr_dB, ...
            "TrialIndex", double(trialOffset) + k, "ChannelState", chState};
        if isfinite(double(trialOffset)) && double(trialOffset) > 0
            srsArgs = [srsArgs, {"SlotIndex", double(trialOffset)}]; %#ok<AGROW>
        end
        outSRS = sixgr.link.runSRSChannelEstimation(cfg, srsArgs{:});
        chState = sixgr.util.structGet(outSRS, "ChannelState", chState);
        ok = logical(sixgr.util.structGet(outSRS, "Ok", false)) && ~logical(sixgr.util.structGet(outSRS, "Skipped", false));
        r.NMSE_dB = double(sixgr.util.structGet(outSRS, "NMSE_dB", NaN));
        r.NMSEReferenceSource = string(sixgr.util.structGet(outSRS, "NMSEReferenceSource", ""));
        r.TrueChannelOracleAvailable = logical(sixgr.util.structGet(outSRS, "TrueChannelOracleAvailable", false));
        r.TrueChannelNMSE_dB = double(sixgr.util.structGet(outSRS, "TrueChannelNMSE_dB", r.NMSE_dB));
        r.ChannelNMSEThreshold_dB = double(sixgr.util.structGet(outSRS, "ChannelNMSEThreshold_dB", NaN));
        r.PilotResidualNMSE_dB = double(sixgr.util.structGet(outSRS, "PilotResidualNMSE_dB", NaN));
        r.DetectionMetric = -r.NMSE_dB;
        r.InjectedDoppler_Hz = double(sixgr.util.structGet(outSRS, "InjectedDoppler_Hz", r.DopplerHz));
        r.EstimatedDopplerHz = double(sixgr.util.structGet(outSRS, "EstimatedDopplerHz", NaN));
        r.DopplerError_Hz = double(sixgr.util.structGet(outSRS, "DopplerError_Hz", NaN));
        r.QCLAccuracy = double(sixgr.util.structGet(outSRS, "QCLAccuracy", NaN));
        r.InterpolationLoss_dB = double(sixgr.util.structGet(outSRS, "InterpolationLoss_dB", NaN));
        r.MismatchSensitivity_dB = double(sixgr.util.structGet(outSRS, "MismatchSensitivity_dB", NaN));
        r.ComputeLatency_ms = double(sixgr.util.structGet(outSRS, "ComputeLatency_ms", NaN));
        r.ProcedureDelay_ms = double(sixgr.util.structGet(outSRS, "ProcedureDelay_ms", NaN));
        r.AirInterfaceObservation_ms = double(sixgr.util.structGet(outSRS, "AirInterfaceObservation_ms", NaN));
        r.AcquisitionTime_ms = double(sixgr.util.structGet(outSRS, "AcquisitionTime_ms", NaN));
        r.TrackingFailureProbability = double(sixgr.util.structGet(outSRS, "TrackingFailure", NaN));
        r.NoiseVariance = double(sixgr.util.structGet(outSRS, "NoiseVariance", NaN));
        r.NoiseVarStatus = string(sixgr.util.structGet(outSRS, "NoiseVarStatus", ""));
        r.NoiseVarSource = string(sixgr.util.structGet(outSRS, "NoiseVarSource", ""));
        r.NoiseVarReason = string(sixgr.util.structGet(outSRS, "NoiseVarReason", ""));
        r.NoiseVarStrictFailure = logical(sixgr.util.structGet(outSRS, "NoiseVarStrictFailure", false));
        r.NoiseOperatingMode = string(sixgr.util.structGet(outSRS, "NoiseOperatingMode", ""));
        r.NoisePowerSource = string(sixgr.util.structGet(outSRS, "NoisePowerSource", ""));
        r.ThermalNoisePower_dBm = double(sixgr.util.structGet(outSRS, "ThermalNoisePower_dBm", NaN));
        r.ServingRxPower_dBm = double(sixgr.util.structGet(outSRS, "ServingRxPower_dBm", NaN));
        r.ServingRxPowerSource = string(sixgr.util.structGet(outSRS, "ServingRxPowerSource", ""));
        r.PowerContextDirection = string(sixgr.util.structGet(outSRS, "PowerContextDirection", ""));
        r.PowerContextTotalTxPower_dBm = double(sixgr.util.structGet(outSRS, "PowerContextTotalTxPower_dBm", NaN));
        r.ConfiguredSNR_dB = double(sixgr.util.structGet(outSRS, "ConfiguredSNR_dB", snr_dB));
        r.AppliedAWGNSNR_dB = double(sixgr.util.structGet(outSRS, "AppliedAWGNSNR_dB", NaN));
        r.DesiredSignalPowerBeforeNoise = double(sixgr.util.structGet(outSRS, "DesiredSignalPowerBeforeNoise", NaN));
        r.CompositeSignalPowerBeforeNoise = double(sixgr.util.structGet(outSRS, "CompositeSignalPowerBeforeNoise", NaN));
        r.AppliedNoiseSNR_dB = double(sixgr.util.structGet(outSRS, "AppliedNoiseSNR_dB", NaN));
        r.NoiseVarianceSource = string(sixgr.util.structGet(outSRS, "NoiseVarianceSource", ""));
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
        r.StrictReceiverEvidenceOk = logical(sixgr.util.structGet(outSRS, "StrictReceiverEvidenceOk", false));
        r.SRSRuntimeEvidenceUsable = logical(sixgr.util.structGet(outSRS, "SRSRuntimeEvidenceUsable", false));
        r.StrictOk = logical(sixgr.util.structGet(outSRS, "StrictOk", false));
        r.ReceiverUsable = logical(r.StrictReceiverEvidenceOk);
        r.DecodeUsable = logical(r.StrictOk);
        r.MeasurementAttempted = logical(sixgr.util.structGet(outSRS, "MeasurementAttempted", false));
        r.MeasurementUsable = logical(sixgr.util.structGet(outSRS, "MeasurementUsable", false));
        r.FailureReason = string(sixgr.util.structGet(outSRS, "FailureReason", ""));
        r.ReceiverHestSINR_dB = double(sixgr.util.structGet(outSRS, "SINR_dB", NaN));
        r.ReceiverHestSINRSource = string(sixgr.util.structGet(outSRS, "SINRSource", ""));
        r.MeasuredTrialSINR_dB = double(sixgr.util.structGet(outSRS, "SINR_dB", NaN));
        r.MeasuredTrialSINRSource = string(sixgr.util.structGet(outSRS, "SINRSource", "ul_srs_receiver_hest_link_state"));
        r.WidebandCQI = double(sixgr.util.structGet(outSRS, "CQI", NaN));
        r.CQIDerivedMCS = double(sixgr.util.structGet(outSRS, "MCSIndex", NaN));
        r.CQIDerivedModulation = string(sixgr.util.structGet(outSRS, "Modulation", ""));
        r.CQIDerivedTargetCodeRate = double(sixgr.util.structGet(outSRS, "TargetCodeRate", NaN));
        r.RankEstimate = double(sixgr.util.structGet(outSRS, "RankEstimate", NaN));
        r.SRSOccupiedPRBCount = double(sixgr.util.structGet(outSRS, "SRSOccupiedPRBCount", NaN));
        r.SRSCarrierPRBCount = double(sixgr.util.structGet(outSRS, "SRSCarrierPRBCount", NaN));
        r.SRSBandwidthFraction = double(sixgr.util.structGet(outSRS, "SRSBandwidthFraction", NaN));
        r.SRSFrequencyPRBStart = double(sixgr.util.structGet(outSRS, "SRSFrequencyPRBStart", NaN));
        r.SRSFrequencyPRBEnd = double(sixgr.util.structGet(outSRS, "SRSFrequencyPRBEnd", NaN));
        r.SRSBandwidthCoverageStatus = string(sixgr.util.structGet(outSRS, "SRSBandwidthCoverageStatus", ""));
        r.RankIndicator = double(sixgr.util.structGet(outSRS, "RIEstimate", outSRS.RankEstimate));
        r.PMI = double(sixgr.util.structGet(outSRS, "TPMIEstimate", NaN));
        r.ConditionNumber_dB = double(sixgr.util.structGet(outSRS, "SRSConditionNumber_dB", r.ConditionNumber_dB));
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

function T = localCollectTRSTrials(cfg, snr_dB, nTrials)
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
        out = sixgr.link.runTRSTracking(cfg, "SNR_dB", snr_dB);
        ok = logical(sixgr.util.structGet(out, "Ok", false)) && ~logical(sixgr.util.structGet(out, "Skipped", false));
        r.CRCPass = NaN;
        r.NMSE_dB = double(sixgr.util.structGet(out, "NMSE_dB", NaN));
        r.DetectionMetric = double(sixgr.util.structGet(out, "DetectionMetric", NaN));
        r.DetectionThreshold = double(sixgr.util.structGet(out, "DetectionThreshold", NaN));
        r.ResourceCoverageRatio = double(sixgr.util.structGet(out, "ResourceCoverageRatio", NaN));
        r.MinCoverageRatio = double(sixgr.util.structGet(out, "MinCoverageRatio", NaN));
        r.DetectionAttempted = logical(sixgr.util.structGet(out, "DetectionAttempted", false));
        r.DetectionSuccess = logical(sixgr.util.structGet(out, "DetectionSuccess", false));
        r.DetectionUsable = logical(r.DetectionAttempted) && logical(r.DetectionSuccess) && isfinite(r.DetectionMetric);
        r.MeasurementAttempted = logical(sixgr.util.structGet(out, "ChannelEstimationAttempted", false));
        r.MeasurementUsable = logical(ok);
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
        r.InjectedCFO_Hz = double(sixgr.util.structGet(out, "InjectedCFO_Hz", NaN));
        r.TrueCFO_Hz = double(sixgr.util.structGet(out, "TrueCFO_Hz", r.InjectedCFO_Hz));
        r.EstimatedCFO_Hz = double(sixgr.util.structGet(out, "EstimatedCFO_Hz", NaN));
        r.EstimatedCFO_PreCorrection_Hz = double(sixgr.util.structGet(out, "EstimatedCFO_PreCorrection_Hz", r.EstimatedCFO_Hz));
        r.InjectedTimingOffset_samples = double(sixgr.util.structGet(out, "InjectedTimingOffset_samples", r.InjectedTimingOffset_samples));
        r.TrueTimingOffset_samples = double(sixgr.util.structGet(out, "TrueTimingOffset_samples", r.InjectedTimingOffset_samples));
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
        r.TRSRuntimeEvidenceUsable = logical(sixgr.util.structGet(out, "TRSRuntimeEvidenceUsable", false));
        r.StrictOk = logical(sixgr.util.structGet(out, "StrictOk", false));
        if isfinite(r.EstimatedCFO_Hz)
            if isfinite(r.TrueCFO_Hz)
                r.ResidualCFO_PostCorrection_Hz = double(r.TrueCFO_Hz) - double(r.EstimatedCFO_Hz);
                r.CFOError_Hz = double(r.ResidualCFO_PostCorrection_Hz);
            else
                r.ResidualCFO_PostCorrection_Hz = NaN;
                r.CFOError_Hz = NaN;
            end
            r.CFOEstimateAvailability = "available";
            r.CFOErrorDefinition = "residual_post_correction_hz_relative_to_estimated_pre_correction";
            if isfinite(r.CFOError_Hz)
                r.CFOValueStatus = "OK";
            else
                r.CFOValueStatus = "PARTIAL";
            end
            r.TRSCFOEstimateAvailable = true;
            r.TRSEstimatedCFO_Hz = double(r.EstimatedCFO_Hz);
        end
        r.ComputeLatency_ms = double(sixgr.util.structGet(out, "ComputeLatency_ms", NaN));
        r.ProcedureDelay_ms = double(sixgr.util.structGet(out, "ProcedureDelay_ms", NaN));
        r.AirInterfaceObservation_ms = double(sixgr.util.structGet(out, "AirInterfaceObservation_ms", NaN));
        r.AcquisitionTime_ms = double(sixgr.util.structGet(out, "AcquisitionTime_ms", NaN));
        r.TrackingFailureProbability = double(sixgr.util.structGet(out, "TrackingFailure", NaN));
        r.NoiseVariance = double(sixgr.util.structGet(out, "NoiseVariance", r.NoiseVariance));
        if ~ok && strlength(strtrim(string(sixgr.util.structGet(out, "FailureReason", "")))) > 0
            r.FailureReason = string(sixgr.util.structGet(out, "FailureReason", ""));
        end
        if ok
            r.Status = "PASS";
        end
        r.Notes = string(sixgr.util.structGet(out, "Notes", ""));
    catch ME
        r.Crash = true;
        r.CRCPass = NaN;
        r.Status = "CRASH";
        r.Notes = string(ME.message);
    end
    rows(k) = r;
end
T = struct2table(rows, "AsArray", true);
end

function row = localMakeLinkTrialRow(cfg, direction, snr_dB, trialIdx)
seed0 = double(sixgr.util.structGet(cfg, "run.seed", 1));
dopp = double(sixgr.util.structGet(cfg, "channel.doppler_Hz", ...
    sixgr.util.structGet(cfg, "channel.dopplerHz", sixgr.util.structGet(cfg, "channel.fading.maxDoppler_Hz", 0))));
row = struct();
row.Direction = string(direction);
row.SNR_dB = double(snr_dB);
row.Seed = seed0 + double(trialIdx) - 1;
row.Frame = double(trialIdx);
row.Slot = double(trialIdx);
row.SSBIndex = NaN;
row.BeamIndex = NaN;
row.MCS = NaN;
row.PRBs = NaN;
row.Layers = NaN;
row.Modulation = "";
    row.TargetCodeRate = NaN;
row.TBSize_bits = NaN;
row.ChannelModel = localResolveRequestedLinkChannelModel(cfg);
row.ChannelModelApplied = "";
row.ChannelFadingApplied = false;
row.DopplerHz = dopp;
    row.CRCPass = NaN;
    row.CRCApplicable = false;
    row.CRCOutcome = "";
    row.BCHCrcPass = NaN;
    row.MIBDecoded = NaN;
    row.BCHTransportBlockNumBits = NaN;
    row.BCHTransportBlockHex = "";
    row.BCHTransportBlockHash = "";
    row.BCHScrambledBlockNumBits = NaN;
    row.BCHScrambledBlockHex = "";
    row.BCHScrambledBlockHash = "";
    row.MIBDecodedBitSource = "";
    row.MIBSFN4LSBValue = NaN;
    row.MIBSFN4LSBBitString = "";
    row.MIBHalfFrameBit = NaN;
    row.MIBKSSBSubcarrierOffset = NaN;
    row.MIBSSBIndex = NaN;
    row.PBCHiBarSSB = NaN;
    row.PBCHv = NaN;
    row.SIB1StrictOk = NaN;
    row.SIB1TreeEqual = NaN;
    row.SIB1DCICrcPass = NaN;
    row.SIB1DLSCHCrcPass = NaN;
    row.SIB1ASN1DecodeOk = NaN;
    row.SIB1FailureReason = "";
    row.UCIContentMatch = false;
    row.ExpectedBitCount = NaN;
    row.DecodedBitCount = NaN;
    row.UCIExpectedBitVector = "";
    row.UCIDecodedBitVector = "";
    row.UCIBitErrorVector = "";
    row.UCICodedBitCount = NaN;
    row.UCICRCBitCount = NaN;
    row.UCICRCApplicable = false;
    row.DetectionOutcome = "";
    row.RequestedFormat = NaN;
    row.ResolvedFormat = NaN;
    row.FormatAdapted = false;
    row.FormatAdaptationReason = "";
    row.ControlResourceValidity = false;
    row.ControlResourceSource = "";
    row.PUCCHFormat = NaN;
    row.PUCCHResourceId = "";
    row.PUCCHPRBSet = "";
    row.PUCCHPRBStart = NaN;
    row.PUCCHPRBCount = NaN;
    row.PUCCHSymbolStart = NaN;
    row.PUCCHNumSymbols = NaN;
    row.PUCCHRECount = NaN;
    row.PUCCHDMRSRECount = NaN;
    row.PUCCHExpectedBitCount = NaN;
    row.PUCCHDecodedBitCount = NaN;
    row.PUCCHControlSINR_dB = NaN;
    row.PUCCHReceiverEvidenceSource = "";
    row.PUCCHGridHash = "";
    row.PUCCHWaveformHash = "";
    row.ReceiverHestSINRApplicable = false;
    row.DecoderIterations = NaN;
row.EVM_rms = NaN;
row.NMSE_dB = NaN;
row.NMSEReferenceSource = "";
row.TrueChannelOracleAvailable = false;
row.TrueChannelNMSE_dB = NaN;
row.ChannelNMSEThreshold_dB = NaN;
row.PilotResidualNMSE_dB = NaN;
row.DetectionMetric = NaN;
row.DetectionThreshold = NaN;
row.DetectionThresholdMode = "";
row.ResourceCoverageRatio = NaN;
row.MinCoverageRatio = NaN;
row.DetectionMetricStatus = "";
row.DetectorPeakMetric = NaN;
row.DetectorNoiseFloor = NaN;
row.RxAntennaCount = NaN;
row.PDPAverageNoiseFloor = NaN;
row.PeakToThresholdRatio = NaN;
row.PeakToNoiseRatio = NaN;
row.PeakToNoiseRatio_dB = NaN;
row.CandidateCount = NaN;
row.CandidatesAboveThreshold = NaN;
row.TargetFalseAlarmProbability = NaN;
row.ThresholdBackgroundComponent = NaN;
row.ThresholdGlobalPeakComponent = NaN;
row.PeakGuardFactor = NaN;
row.DetectorPeakLagSamples = NaN;
row.CorrelationPeak = NaN;
row.NoiseOnlyDetectionMetric = NaN;
row.MissedDetection = false;
row.FalseAlarm = false;
row.FalseAlarmCandidateScope = "";
row.FalseAlarmCandidateCount = NaN;
row.DTXFlag = false;
row.DTXReason = "";
row.PreambleIndex = NaN;
row.RequestedPreambleIndex = NaN;
row.DetectedPreambleIndex = NaN;
row.PreambleIndexFromPeak = NaN;
row.PRACHRootSequenceIndex = NaN;
row.PRACHZeroCorrelationZone = NaN;
row.PRACHConfigurationIndex = NaN;
row.PRACHOccasionIndex = NaN;
row.PRACHCarrierSlot = NaN;
row.RAProcedureType = "";
row.RABindingSource = "";
row.RACHConfigHash = "";
row.RARunId = "";
row.RAScenarioName = "";
row.RACellId = NaN;
row.RAUEId = NaN;
row.RAAttemptId = NaN;
row.PreambleIndexTx = NaN;
row.PreambleIndexDetected = NaN;
row.PreambleDetectionMetric = NaN;
row.PreambleDetectionThreshold = NaN;
row.PreambleDetected = false;
row.CollisionDetected = false;
row.CollisionFlag = NaN;
row.PreambleAmbiguityDetected = false;
row.PreambleReceivedTargetPower_dBm = NaN;
row.PowerRampingStep_dB = NaN;
row.PreambleTransMax = NaN;
row.PreambleAttemptNumber = NaN;
row.PowerPathloss_dB = NaN;
row.PowerBasePathloss_dB = NaN;
row.PowerPathlossSource = "";
row.ReferenceTxPower_dBm = NaN;
row.PreambleDelta_dB = NaN;
row.PreambleTargetReceivedPower_dBm = NaN;
row.PreambleRequestedTxPower_dBm = NaN;
row.PreambleTxPower_dBm = NaN;
row.PreamblePowerHeadroom_dB = NaN;
row.PreambleTxAmplitudeScale = NaN;
row.PowerControlStatus = "";
row.P0PUSCH_dBm = NaN;
row.AlphaPUSCH = NaN;
row.Pcmax_dBm = NaN;
row.Msg3Pathloss_dB = NaN;
row.Msg3P0PUSCH_dBm = NaN;
row.Msg3Alpha = NaN;
row.Msg3NumPRBForPower = NaN;
row.Msg3DeltaTF_dB = NaN;
row.Msg3ClosedLoopCorrection_dB = NaN;
row.Msg3RequestedTxPower_dBm = NaN;
row.Msg3TxPower_dBm = NaN;
row.Msg3PowerHeadroom_dB = NaN;
row.Msg3TxAmplitudeScale = NaN;
row.DownlinkTxPower_dBm = NaN;
row.DownlinkTxPowerSource = "";
row.Msg2TxPower_dBm = NaN;
row.Msg2TxAmplitudeScale = NaN;
row.Msg4TxPower_dBm = NaN;
row.Msg4TxAmplitudeScale = NaN;
row.TimingAdvanceCommand = NaN;
row.RARNTI = NaN;
row.RAResponseWindowStartSlot = NaN;
row.RAResponseWindowEndSlot = NaN;
row.RARWindowExpired = false;
row.Msg2PDCCHCandidatesAttempted = NaN;
row.Msg2RARNTIDetected = false;
row.Msg2DCICrcPass = false;
row.Msg2DCIFormat = "";
row.Msg2PDSCHCrcPass = false;
row.Msg2PDSCHNumLayers = NaN;
row.Msg2PDSCHConfiguredNumPorts = NaN;
row.Msg2PDSCHResolvedNumPorts = NaN;
row.Msg2PDSCHExplicitMatrixPresent = false;
row.Msg2PDSCHPrecodingActive = false;
row.Msg2PDSCHPrecodingMode = "";
row.Msg2PDSCHPrecodingSource = "";
row.Msg2TimingEstimateUsed = false;
row.Msg2RawTimingEstimate_samples = NaN;
row.Msg2AppliedTimingCorrection_samples = NaN;
row.Msg2TimingEstimateSource = "";
row.Msg2PostEqSINR_dB = NaN;
row.Msg2ReceiverHestSINR_dB = NaN;
row.Msg2PreEqualizationNoiseVar = NaN;
row.Msg2DecoderNoiseVar = NaN;
row.Msg2ChannelEstimateAvailable = false;
row.Msg2ChannelEstimateMethod = "";
row.Msg2ChannelEstimatePilotResidualNMSE_dB = NaN;
row.Msg2EqualizationAvailable = false;
row.Msg2LLRFinite = false;
row.Msg2DemapperLLRCount = NaN;
row.Msg2DecoderIterations = NaN;
row.RARBytesHex = "";
row.RAPIDDecoded = NaN;
row.RAPIDMatches = false;
row.TemporaryCRNTI = NaN;
row.RARULGrantHex = "";
row.RARULGrantValid = false;
row.Msg3ScheduledSlot = NaN;
row.Msg3PUSCHPRBStart = NaN;
row.Msg3PUSCHNumPRB = NaN;
row.Msg3PUSCHSymbolStart = NaN;
row.Msg3PUSCHNumSymbols = NaN;
row.Msg3MCS = NaN;
row.Msg3Modulation = "";
row.Msg3TBS = NaN;
row.Msg3TimingAdvanceApplied = false;
row.Msg3PUSCHCrcPass = false;
row.Msg3PayloadHex = "";
row.Msg3ContentionIdentity = "";
row.Msg4ScheduledSlot = NaN;
row.Msg4PDCCHCrcPass = false;
row.Msg4PDSCHCrcPass = false;
row.Msg4PDSCHNumLayers = NaN;
row.Msg4PDSCHConfiguredNumPorts = NaN;
row.Msg4PDSCHResolvedNumPorts = NaN;
row.Msg4PDSCHExplicitMatrixPresent = false;
row.Msg4PDSCHPrecodingActive = false;
row.Msg4PDSCHPrecodingMode = "";
row.Msg4PDSCHPrecodingSource = "";
row.Msg4TimingEstimateUsed = false;
row.Msg4RawTimingEstimate_samples = NaN;
row.Msg4AppliedTimingCorrection_samples = NaN;
row.Msg4TimingEstimateSource = "";
row.Msg4PostEqSINR_dB = NaN;
row.Msg4ReceiverHestSINR_dB = NaN;
row.Msg4PreEqualizationNoiseVar = NaN;
row.Msg4DecoderNoiseVar = NaN;
row.Msg4ChannelEstimateAvailable = false;
row.Msg4ChannelEstimateMethod = "";
row.Msg4ChannelEstimatePilotResidualNMSE_dB = NaN;
row.Msg4EqualizationAvailable = false;
row.Msg4LLRFinite = false;
row.Msg4DemapperLLRCount = NaN;
row.Msg4DecoderIterations = NaN;
row.Msg4PayloadHex = "";
row.Msg4ContentionIdentity = "";
row.ContentionIdentityMatches = false;
row.FinalCRNTI = NaN;
row.RACompleted = false;
row.RAStage = "";
row.RAFailureReason = "";
row.ProxyUsed = false;
row.Skipped = false;
row.ToolboxMissing = false;
row.UsedOracleFields = "";
row.FullRAEvidenceSource = "";
row.FullRAArtifactRunFolder = "";
row.RuntimeIntegrationMode = "";
row.RuntimeTransportMode = "";
row.RuntimeStageWaveformsRequired = false;
row.RuntimeStageWaveformsUsed = false;
row.RuntimeSelfLoopWaveformsUsed = false;
row.RuntimeChannelStateUsed = false;
row.RuntimeNoiseApplied = false;
row.RuntimeNoiseVarianceMean = NaN;
row.RuntimeChannelLinkKeys = "";
row.RuntimeStageCount = NaN;
row.MeasuredSINR_dB = NaN;
row.ReceiverHestSINR_dB = NaN;
row.ReceiverHestSINRSource = "";
row.ReceiverHestSINRValueRole = "";
row.ReceiverHestSINRValueStatus = "";
row.ReceiverHestSINRNAReason = "";
row.PostEqSINR_dB = NaN;
row.PostEqSINRSource = "";
row.PostEqSINRValueRole = "";
row.PostEqSINRValueStatus = "";
row.PostEqSINRNAReason = "";
row.PostEqSINRPerLayer_dB = "";
row.MeasuredTrialSINR_dB = NaN;
row.MeasuredTrialSINRSource = "";
row.MeasuredTrialSINRValueRole = "";
row.MeasuredTrialSINRValueStatus = "";
row.MeasuredTrialSINRNAReason = "";
row.DecoderTruthProxySINR_dB = NaN;
row.DecoderTruthProxySINRSource = "";
row.SINRValueRole = "";
row.SINRSource = "";
row.SINRValueStatus = "";
row.SINRValueDefinition = "";
row.WidebandCQI = NaN;
row.CQIDerivedMCS = NaN;
row.CQIDerivedModulation = "";
row.CQIDerivedTargetCodeRate = NaN;
row.LinkAdaptationMode = "";
row.ConfiguredLinkAdaptationMode = "";
row.LinkAdaptationDomain = "";
row.ActualMCSSelectionMode = "";
row.ConfiguredMCSSelectionPolicy = "";
row.SchedulerGrantMCSSelectionMode = "";
row.CQISource = "";
row.MCSSelectionSource = "";
row.MCSValueStatus = "";
row.OLLADomain = "";
row.OuterLoopEnabled = false;
row.InnerLoopEnabled = false;
row.OuterLoopApplied = false;
row.InnerLoopApplied = false;
row.OLLADeltaDb = NaN;
row.OLLADeltaMCS = NaN;
row.OLLAAdjustedMCSBeforeCQICeiling = NaN;
row.OLLABaseRequiredSINR_dB = NaN;
row.OLLATargetRequiredSINR_dB = NaN;
row.OLLAThresholdSource = "";
row.OLLAUpdateCount = NaN;
row.OLLAState = "";
row.CalibrationProfile = "";
row.RequestedOperatingPointSource = "";
row.CQITable = "";
row.MCSTable = "";
row.RankIndicator = NaN;
row.PMI = NaN;
row.CRI = NaN;
row.PMIType = "";
row.PMICodebookMode = "";
row.CSIReportMode = "";
row.CSIPayloadBitLength = NaN;
row.CSIPayloadHex = "";
row.ConfiguredBeamSelectionStrategy = "";
row.PrecoderSource = "";
row.PrecodingMode = "";
row.PrecodingApplicationStage = "";
row.PrecodingActive = false;
row.ExplicitBeamWeightsApplied = false;
row.TransformPrecodingApplied = false;
row.BeamformingApplied = false;
row.AppliedBeamIndexSet = "";
row.AppliedPrecoderPMI = NaN;
row.AppliedPrecoderPMIType = "";
row.AppliedPrecoderCodebookMode = "";
row.RequestedVsAppliedPrecoderPMIMatchStatus = "";
row.PrecodingNumPorts = NaN;
row.PrecodingNumLayers = NaN;
row.PrecodingMatrixRows = NaN;
row.PrecodingMatrixCols = NaN;
row.FalseAlarmFlag = NaN;
row.NoiseFalseAlarmFlag = NaN;
row.CollisionFalseAlarmFlag = NaN;
row.FalseAlarmClassification = "";
row.BlockingFlag = NaN;
row.BlindDecodeCount = NaN;
row.CandidatesAttempted = NaN;
row.DCICrcPass = false;
row.PDCCHPayloadMatch = false;
row.PDCCHCausalGrantDecodeOk = false;
row.PDCCHExpectedDCIBitCount = NaN;
row.PDCCHDecodedDCIBitCount = NaN;
row.PDCCHDCIBitsCompared = NaN;
row.PDCCHDCIBitErrors = NaN;
row.PDCCHMissedDetection = false;
row.PDCCHFalseAlarm = false;
row.PDCCHErrFlag = NaN;
row.TxCCEIndex = NaN;
row.SelectedCCEIndex = NaN;
row.GrantValid = false;
row.NegativeExpectedOk = false;
row.PDCCHBlindSearchEnabled = false;
row.PDCCHCandidatesAvailable = NaN;
row.PDCCHCandidatesAttempted = NaN;
row.PDCCHCandidateIndex = NaN;
row.PDCCHTxCCEIndex = NaN;
row.PDCCHSelectedCCEIndex = NaN;
row.PDCCHDCICrcRNTI = NaN;
row.PDCCHScramblingRNTI = NaN;
row.PDCCHEncodedBits = NaN;
row.PDCCHRECount = NaN;
row.PDCCHDMRSRECount = NaN;
row.PDCCHCandidateErrFlagVector = "";
row.PDCCHCandidateDecodeOKVector = "";
row.PDCCHCandidateSINRVector_dB = "";
row.PDCCHCandidateRECountVector = "";
row.PDCCHCandidateDMRSRECountVector = "";
row.PDCCHCRCDecodeSource = "";
row.PDCCHBlindDecodeEvidenceSource = "";
row.PDCCHCCE_REGMappingEvidence = "";
row.PDCCHREGMappingAvailable = false;
row.PDCCHCORESETDuration = NaN;
row.PDCCHCORESETFrequencyResources = "";
row.PDCCHSearchSpaceNumCandidates = "";
row.PDCCHGridHash = "";
row.PDCCHWaveformHash = "";
row.PDCCHResourceHash = "";
row.AvailableCCECount = NaN;
row.UsedCCECount = NaN;
row.NonOverlappedCCEUsage = NaN;
row.AggregationLevel = NaN;
row.DCISize_bits = NaN;
row.ControlCapacityBits = NaN;
row.ControlCapacityUtilization = NaN;
row.CORESETUtilization = NaN;
row.ControlLatency_ms = NaN;
row.ChannelGain_dB = NaN;
row.NoiseVariance = NaN;
row.DesiredSignalPowerBeforeNoise = NaN;
row.CompositeSignalPowerBeforeNoise = NaN;
row.AppliedNoiseSNR_dB = NaN;
row.NoiseVarianceSource = "";
row.NoiseOperatingMode = "";
row.NoisePowerSource = "";
row.ThermalNoisePower_dBm = NaN;
row.ServingRxPower_dBm = NaN;
row.ServingRxPowerSource = "";
row.PowerContextDirection = "";
row.PowerContextTotalTxPower_dBm = NaN;
row.NoiseVarStatus = "";
row.NoiseVarSource = "";
row.NoiseVarReason = "";
row.NoiseVarStrictFailure = false;
row.ReceiverUsable = false;
row.DecodeAttempted = false;
row.DecodeUsable = false;
row.StrictReceiverEvidenceOk = false;
row.StrictOk = false;
row.TruthStatus = "";
row.SourceClassification = "";
row.RuntimeMaterializationStatus = "";
row.ControlGatingEffect = "";
row.RuntimeStateConsumer = "";
row.RuntimeConsumer = "";
row.RuntimeEvidenceSource = "";
row.ChannelEstimateAttempted = false;
row.ChannelEstimateAvailable = false;
row.SRSChannelEstimateAvailable = false;
row.ChannelEstimateSource = "";
row.ResourceExtractionAttempted = false;
row.ResourceExtractionAvailable = false;
row.EqualizationAttempted = false;
row.EqualizationAvailable = false;
row.DLSCHDecodeAttempted = false;
row.DLSCHDecodeAvailable = false;
row.ULSCHDecodeAttempted = false;
row.ULSCHDecodeAvailable = false;
row.LLRAvailable = false;
row.LLRFinite = false;
row.LLRScaleSource = "";
row.LLRNoiseVariance = NaN;
row.PostEqSINRWidebanddB = NaN;
row.PostEqSINRAvailable = false;
row.PostEqSINRReceiverDerived = false;
row.SINRValidationStatus = "";
row.SINRValidationReason = "";
row.SINRComputationMethod = "";
row.ConfiguredSNRLikeSourceRejected = false;
row.EqualizerType = "";
row.EqualizerRequestedType = "";
row.EqualizerEngine = "";
row.InterferenceCovarianceAvailable = false;
row.InterferenceCovarianceSource = "";
row.InterferenceCovarianceStatus = "";
row.DetectionAttempted = false;
row.DetectionSuccess = false;
row.DetectionUsable = false;
row.MeasurementAttempted = false;
row.MeasurementUsable = false;
row.SRSRuntimeEvidenceUsable = false;
row.FailureReason = "";
row.TimingOffset_samples = NaN;
row.TimingAdvance_samples = NaN;
row.TimingAdvance_us = NaN;
row.TAOutOfRangeFlag = false;
row.TAOutOfRangeReason = "";
row.TAMaxValid_samples = NaN;
row.TAMaxValid_us = NaN;
row.RankEstimate = NaN;
row.SRSOccupiedPRBCount = NaN;
row.SRSCarrierPRBCount = NaN;
row.SRSBandwidthFraction = NaN;
row.SRSFrequencyPRBStart = NaN;
row.SRSFrequencyPRBEnd = NaN;
row.SRSBandwidthCoverageStatus = "";
row.ConditionNumber_dB = NaN;
row.NumRxAntennas = NaN;
row.NumTxPorts = NaN;
row.SelectedBeamIndex = NaN;
row.BestBeamIndex = NaN;
row.BeamHit = NaN;
row.TopKBeamHit = NaN;
row.BeamCandidateCount = NaN;
row.SelectedBeamGain_dB = NaN;
row.BestBeamGain_dB = NaN;
row.BeamGainGap_dB = NaN;
row.ConfiguredPMI = NaN;
row.ConfiguredCRI = NaN;
row.BitErrors = NaN;
row.BitsCompared = NaN;
row.RawBER = NaN;
row.OfferedBits = NaN;
row.GoodBits = NaN;
row.OfferedThroughput_Mbps = NaN;
row.Goodput_Mbps = NaN;
row.ComputeLatency_ms = NaN;
row.ProcedureDelay_ms = NaN;
row.AirInterfaceTTI_ms = NaN;
row.AirInterfaceObservation_ms = NaN;
row.Latency_ms = NaN;
row.DecodeLatency_ms = NaN;
row.EarlyStopRate = NaN;
row.DecoderComplexityUnits = NaN;
row.NormalizedDecoderComplexity = NaN;
row.AreaEfficiencyProxy = NaN;
row.NumCodeBlocks = NaN;
row.CodeBlockLength_bits = NaN;
row.SegmentationOccurred = NaN;
row.SegmentationPaddingBits = NaN;
row.TBCRCLength_bits = NaN;
row.TBLengthWithCRC_bits = NaN;
row.BaseGraph = NaN;
row.EncodedBits = NaN;
row.RateMatchedBits = NaN;
row.RateMatchPunctureBits = NaN;
row.RateMatchRepetitionBits = NaN;
row.CodeBlockErrors = NaN;
row.CodeBlockCount = NaN;
row.CodeBlockBLER = NaN;
row.CBGErrors = NaN;
row.CBGCount = NaN;
row.CBGBLER = NaN;
row.PAPR_dB = NaN;
row.PeakClippingEvents = NaN;
row.SymbolErrors = NaN;
row.SymbolsCompared = NaN;
row.SymbolErrorRate = NaN;
row.ResidualInterferencePower_dB = NaN;
row.LLRMeanAbs = NaN;
row.LLRStdAbs = NaN;
row.LLRImbalance = NaN;
row.ModulationMappingSensitivity = NaN;
row.ShapingRateLoss = NaN;
row.DistributionMatchingLatency_ms = NaN;
row.HighOrderRobustness = NaN;
row.DetectorComplexityUnits_Modulation = NaN;
row.DataRECount = NaN;
row.DataRECountPerLayer = NaN;
row.TotalDataRECount = NaN;
row.ModulationOrderQm = NaN;
row.ComputedE_TS38212 = NaN;
row.RateMatchedBitsDelta_TS38212 = NaN;
row.DMRSRECount = NaN;
row.PTRSRECount = NaN;
row.RSOverheadFraction = NaN;
row.InjectedCFO_Hz = NaN;
row.EstimatedCFO_PreCorrection_Hz = NaN;
row.ResidualCFO_PostCorrection_Hz = NaN;
row.EstimatedCFO_Hz = NaN;
row.TrueCFO_Hz = NaN;
row.CFOError_Hz = NaN;
row.CFOEstimateAvailability = "missing";
row.CFOErrorDefinition = "not_available_without_cfo_estimate";
row.CFOValueStatus = "NOT_AVAILABLE";
row.InjectedTimingOffset_samples = 0;
row.EstimatedTimingOffset_PreCorrection_samples = NaN;
row.EstimatedTimingOffset_samples = NaN;
row.TimingEstimate_samples = NaN;
row.AppliedTimingCorrection_samples = NaN;
row.ResidualTimingError_PostCorrection_samples = NaN;
row.TrueTimingOffset_samples = 0;
row.TimingError_samples = NaN;
row.TimingEstimateApplicationPolicy = "";
row.TimingEstimateStatus = "";
row.TimingEstimateWasClipped = false;
row.IQImbalanceConfigured = false;
row.IQImbalanceApplied = false;
row.IQImbalanceModel = "";
row.ConfiguredIQGainImbalance_dB = NaN;
row.ConfiguredIQPhaseImbalance_deg = NaN;
row.IQImbalanceMirrorPowerRatio_dB = NaN;
row.IQImbalanceImageRejection_dB = NaN;
row.IQImbalanceIQPowerRatio_dB = NaN;
row.IQImbalanceIQCorrelation = NaN;
row.IQImbalanceEstimatedAlphaAbs = NaN;
row.IQImbalanceEstimatedBetaAbs = NaN;
row.IQImbalanceMeasurementSource = "";
row.IQImbalanceMeasurementStatus = "";
row.InjectedDoppler_Hz = dopp;
row.EstimatedDopplerHz = NaN;
row.DopplerError_Hz = NaN;
row.PhaseTrackingError_deg = NaN;
row.TrackingEstimateSource = "";
row.QCLAccuracy = NaN;
row.ChannelAgingLoss_dB = NaN;
row.InterpolationLoss_dB = NaN;
row.MismatchSensitivity_dB = NaN;
row.AcquisitionTime_ms = NaN;
row.TrackingFailureProbability = NaN;
row.Status = "NA";
row.Crash = false;
row.LinkAdaptationApplied = false;
row.LinkAdaptationScheduled = false;
row.IsWarmupFrame = false;
row.SFN = mod(max(0, round(double(row.Frame)) - 1), 1024);
row.UEID = NaN;
row.BaseStationID = NaN;
row.AllocatedPRBCount = NaN;
row.PRBStart = NaN;
row.MCSIndex = NaN;
row.Rank = NaN;
row.ConfiguredSNR_dB = double(snr_dB);
row.ConfiguredSNRSource = "configured_operating_point_metadata";
row.SNRValueRole = "configured_operating_point_metadata";
row.AppliedAWGNSNR_dB = NaN;
row.AppliedAWGNSNRSource = "";
row.PRACHSNRCalibrationStatus = "";
row.PRACHSNRCalibrationSource = "";
row.PRACHSNRCalibrationError_dB = NaN;
row.PRACHNoiseReferencePower = NaN;
row.ReceiverHestSINR_dB = NaN;
row.ReceiverHestSINRSource = "";
row.ReceiverHestSINRValueRole = "";
row.ReceiverHestSINRValueStatus = "";
row.ReceiverHestSINRNAReason = "";
row.PostEqSINR_dB = NaN;
row.PostEqSINRSource = "";
row.PostEqSINRValueRole = "";
row.PostEqSINRValueStatus = "";
row.PostEqSINRNAReason = "";
row.PostEqSINRPerLayer_dB = "";
row.DecoderTruthProxySINR_dB = NaN;
row.DecoderTruthProxySINRSource = "";
row.SINRValueRole = "";
row.SINRSource = "";
row.MeasuredTrialSINR_dB = NaN;
row.MeasuredTrialSINRSource = "";
row.LargeScaleSINR_dB = NaN;
row.LargeScaleSINRSource = "";
row.ServingRSRP_dBm = NaN;
row.ServingRSRPSource = "";
row.CSI_RSRP_dB = NaN;
row.CSI_RSRPSource = "";
row.AppliedLargeScaleGain_dB = NaN;
row.AppliedLargeScaleLoss_dB = NaN;
row.AppliedBasePathloss_dB = NaN;
row.AppliedPathloss_dB = NaN;
row.AppliedShadowFading_dB = NaN;
row.AppliedO2I_dB = NaN;
row.AppliedLargeScaleGainSource = "";
row.TimingEstimateUsed = false;
row.UseIdealTimingSync = false;
row.InterferenceMode = "";
row.InterfererBeamformingAppliedCount = 0;
row.InterfererExplicitBeamWeightCount = 0;
row.InterfererTransformPrecodingCount = 0;
row.InterfererPrecoderSourceSet = "";
row.InterfererPrecodingModeSet = "";
row.InterfererBeamIndexSetSummary = "";
row.MCSAuthority = "";
row.ModulationAuthority = "";
row.GrantOperatingPointSource = "";
row.AppliedOperatingPointSource = "";
row.DopplerSourceMode = localResolveDopplerSourceMode(cfg);
row.DopplerValueRole = "scenario_resolved_metadata";
row.TRSGatingActive = false;
row.TRSValidityState = "";
row.TrackingEligibility = false;
row.TRSAgeSlots = NaN;
row.LastSuccessfulTRSSlot = NaN;
row.LastEstimatedTRSDopplerHz = NaN;
row.TRSStateSource = "";
row.TRSRuntimeConsumer = "";
row.TRSInfluencedDecision = false;
row.TRSInfluenceDefinition = "";
row.TRSReceiverIntegrationStatus = "";
row.TRSReceiverIntegrationBlocker = "";
row.TRSProcessed = false;
row.TRSReceiverConsumerType = "";
row.TRSTrackingStateBefore = "";
row.TRSTrackingStateAfter = "";
row.TRSTrackingUpdateTime_s = NaN;
row.TRSAssociatedCell = NaN;
row.TRSUpdateOutcome = "";
row.TRSChannelTrackingFreshnessState = "";
row.TRSFrequencyTrackingState = "";
row.TRSTimingTrackingState = "";
row.TimingTrackingAttempted = false;
row.TRSTimingEstimateAvailable = false;
row.TRSTimingEstimateUsable = false;
row.TRSTimingEstimate_samples = NaN;
row.FrequencyTrackingAttempted = false;
row.TRSCFOEstimateAvailable = false;
row.TRSCFOEstimateUsable = false;
row.TRSEstimatedCFO_Hz = NaN;
row.ChannelEstimationAttempted = false;
row.TRSChannelEstimateAvailable = false;
row.TRSRuntimeEvidenceSource = "";
row.TRSRuntimeEvidenceUsable = false;
row.StrictOk = false;
row.GrantContextId = "";
row.GrantWorkerSafe = false;
row.GrantSharedStateCommitMode = "";
row.Notes = "";
end

function outcome = ternaryPUCCHCRCOutcome(crcApplicable, ok)
if ~logical(crcApplicable)
    outcome = "not_applicable";
elseif logical(ok)
    outcome = "pass";
else
    outcome = "fail";
end
end

function outcome = ternaryPUCCHDetectionOutcome(detectionUsable, contentMatch)
if ~logical(detectionUsable)
    outcome = "unavailable";
elseif logical(contentMatch)
    outcome = "detected";
else
    outcome = "missed";
end
end

function T = localEmptyLinkTrialTable(nRows)
nRows = max(0, round(double(nRows)));
rows = repmat(localMakeLinkTrialRow(struct(), "", NaN, 1), nRows, 1);
T = struct2table(rows);
T.RequestedBeamTruthClassification = strings(nRows, 1);
T.RequestedPrecoderPMITruthClassification = strings(nRows, 1);
T.AppliedBeamApplicationSource = strings(nRows, 1);
T.AppliedBeamTruthClassification = strings(nRows, 1);
T.AppliedPrecoderPMIApplicationSource = strings(nRows, 1);
T.AppliedPrecoderPMITruthClassification = strings(nRows, 1);
T.RequestedVsAppliedPrecoderPMIMatchStatus = strings(nRows, 1);
T = sixgr.link.appendMeasuredPHYEvidenceColumns(T, cell(nRows, 1));
end

function T = localEmptyCSIRSTrialTable()
T = struct2table(repmat(localEmptyCSIRSTrialRow(), 0, 1), "AsArray", true);
end

function row = localEmptyCSIRSTrialRow()
row = struct( ...
    "Direction", "", "SignalFamily", "CSI-RS", "SNR_dB", NaN, "SFN", NaN, "Frame", NaN, "Slot", NaN, "Time_s", NaN, ...
    "CellID", NaN, "BWPID", NaN, "UEIndex", NaN, "RNTI", NaN, ...
    "ResourceID", NaN, "ResourceSetID", NaN, "CSIRSType", "", "NumPorts", NaN, "RowNumber", NaN, ...
    "Density", "", "Periodicity", "", "SymbolLocations", "", "SubcarrierLocations", "", "RBOffset", NaN, "NumRB", NaN, "NRE", NaN, ...
    "Scheduled", false, "Transmitted", false, "Observed", false, "Consumed", false, "Consumer", "", ...
    "MeasurementRSRP_dB", NaN, "MeasurementSource", "", "UpdateOutcome", "", ...
    "RuntimeMaterializationStatus", "", "RuntimeBlocker", "", "RuntimeEvidenceSource", "", ...
    "RuntimeEventObserved", false, "SourceArtifact", "air_interface/csv/csi_rs_trials.csv", "SourceTable", "air_interface/csv/csi_rs_trials.csv");
end

function spec = localResolveMultiUserSpec(cfg)
userCfg = sixgr.util.structGet(cfg, "lls6g.users", struct());
hasUsersCfg = isstruct(userCfg) && isscalar(userCfg) && ~isempty(fieldnames(userCfg));
if hasUsersCfg
    numUsers = max(1, round(double(sixgr.util.structGet(userCfg, "n_users", 1))));
    enabled = logical(sixgr.util.structGet(userCfg, "enabled", false)) || numUsers > 1;
else
    numUsers = 1;
    enabled = false;
end
spec = struct();
spec.Enabled = enabled;
spec.NumUsers = numUsers;
spec.RNTIStart = max(1, round(double(sixgr.util.structGet(userCfg, "rnti_start", 1))));
spec.SeedStride = max(1, round(double(sixgr.util.structGet(userCfg, "seed_stride", 101))));
spec.ExecutionModel = string(sixgr.util.structGet(userCfg, "execution_model", "independent_link_sweep"));
spec.BeamSelectionStrategy = lower(string(sixgr.util.structGet(userCfg, "beam_selection_strategy", "")));
if strlength(strtrim(spec.BeamSelectionStrategy)) == 0
    spec.BeamSelectionStrategy = "missing_from_config";
end
spec.SaveUserTables = logical(sixgr.util.structGet(userCfg, "save_user_tables", true));
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
    cfgU = sixgr.util.structSet(cfgU, "phy.pdsch.precoding.matrix", W);
    cfgU = sixgr.util.structSet(cfgU, "phy.pdsch.numPorts", size(W, 1));
    cfgU = sixgr.util.structSet(cfgU, "phy.pdsch.nPorts", size(W, 1));
    cfgU.phy.nTxAnt = size(W, 1);
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

function [T, summaryT, constT, csirsT] = localCollectMultiUserLinkTrials(cfg, multiUser, direction, nTrials, snr_dB, livePublisher)
if nargin < 6
    livePublisher = [];
end
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
    Tu = localAnnotateUserTrials(Tu, cfgU, multiUser, ueIdx, userMeta);
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

function [Tu, summaryT, constT, csirsT] = localRunSingleUserDirectionTrials(cfg, multiUser, ueIdx, direction, nTrials, snr_dB, livePublisher)
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
Tu = localAnnotateUserTrials(Tu, cfgU, multiUser, ueIdx, userMeta);
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
    meta.WaveformPreviewTable = localAnnotateWaveformPreviewTable(meta.WaveformPreviewTable, multiUser, ueIdx);
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
if isfinite(dlCompletedFrames) && isfinite(ulCompletedFrames)
    completedFrames = min(dlCompletedFrames, ulCompletedFrames);
elseif isfinite(dlCompletedFrames)
    completedFrames = dlCompletedFrames;
elseif isfinite(ulCompletedFrames)
    completedFrames = ulCompletedFrames;
end
notes = string(sixgr.util.structGet(meta, "Notes", ""));
dlUserProgress = NaN;
ulUserProgress = NaN;
if isfinite(totalUsers) && totalUsers > 0
    dlUserProgress = min(double(dlUsers) / double(totalUsers), 1);
    ulUserProgress = min(double(ulUsers) / double(totalUsers), 1);
end
if strlength(notes) == 0
    notes = sprintf("Streaming %s at %.3f dB: UE %s/%s, completed frames DL=%s/%s UL=%s/%s, bidirectional=%s/%s, DL users=%d/%s, UL users=%d/%s.", ...
        char(direction), currentSNR, localDisplayProgressValue(currentUE), localDisplayProgressValue(totalUsers), ...
        localDisplayProgressValue(dlCompletedFrames), localDisplayProgressValue(totalFrames), ...
        localDisplayProgressValue(ulCompletedFrames), localDisplayProgressValue(totalFrames), ...
        localDisplayProgressValue(completedFrames), localDisplayProgressValue(totalFrames), ...
        dlUsers, localDisplayProgressValue(totalUsers), ulUsers, localDisplayProgressValue(totalUsers));
end
currentSlot = double(sixgr.util.structGet(runtimeState, "CurrentSlot", NaN));
runCompletion = NaN;
if isfinite(totalSlots) && totalSlots > 0 && isfinite(currentSlot)
    runCompletion = min(max(currentSlot / totalSlots, 0), 1);
elseif isfinite(completedFrames) && isfinite(totalFrames) && totalFrames > 0
    runCompletion = min(max(completedFrames / totalFrames, 0), 1);
end
status = struct( ...
    "Stage", "dl_ul_raw_trials_streaming", ...
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
    "DLTrialRows", double(height(dlT)), ...
    "ULTrialRows", double(height(ulT)), ...
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
    "ControlReady", true, ...
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
summary = localFormatOperatingPointSINRObservabilitySummary(trialT, configuredSNR_dB);
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
txt = sprintf("%s pending", char(string(label)));
if ~(istable(trialT) && ~isempty(trialT) && ismember(string(varName), string(trialT.Properties.VariableNames)))
    return;
end
vals = double(trialT.(varName));
vals = vals(isfinite(vals));
if isempty(vals)
    return;
end
txt = sprintf("median %s %.3f dB", char(string(label)), median(vals));
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
    meta.WaveformPreviewTable = localAnnotateWaveformPreviewTable(meta.WaveformPreviewTable, multiUser, ueIdx);
end
try
    feval(livePublisher, combinedT, combinedConstT, meta);
catch
end
end

function T = localAnnotateWaveformPreviewTable(T, multiUser, ueIdx)
if ~istable(T)
    T = table();
    return;
end
n = height(T);
if ~ismember("UEIndex", string(T.Properties.VariableNames))
    T.UEIndex = repmat(double(ueIdx), n, 1);
end
if ~ismember("RNTI", string(T.Properties.VariableNames))
    T.RNTI = repmat(double(localUserRNTI(multiUser, ueIdx)), n, 1);
end
end

function T = localAnnotateUserTrials(T, cfg, multiUser, ueIdx, userMeta)
if ~istable(T)
    T = table();
    return;
end
n = height(T);
T.UEIndex = repmat(double(ueIdx), n, 1);
T.UEID = repmat(double(ueIdx), n, 1);
T.RNTI = repmat(double(localUserRNTI(multiUser, ueIdx)), n, 1);
if ~ismember("SFN", string(T.Properties.VariableNames)) || all(~isfinite(double(T.SFN)))
    T.SFN = mod(max(0, round(double(T.Frame)) - 1), 1024);
end
if ~ismember("ConfiguredSNR_dB", string(T.Properties.VariableNames)) || all(~isfinite(double(T.ConfiguredSNR_dB)))
    T.ConfiguredSNR_dB = double(T.SNR_dB);
end
T = localPopulateSINRTruthColumns(T);
if ~ismember("MCSIndex", string(T.Properties.VariableNames)) || all(~isfinite(double(T.MCSIndex)))
    T.MCSIndex = double(T.MCS);
end
if ~ismember("AllocatedPRBCount", string(T.Properties.VariableNames)) || all(~isfinite(double(T.AllocatedPRBCount)))
    T.AllocatedPRBCount = double(T.PRBs);
end
if ismember("Layers", string(T.Properties.VariableNames)) && any(isfinite(double(T.Layers)))
    if ~ismember("Rank", string(T.Properties.VariableNames))
        T.Rank = double(T.Layers);
    else
        layers = double(T.Layers);
        rank = double(T.Rank);
        mask = isfinite(layers) & (~isfinite(rank) | abs(rank - layers) > 1e-9);
        if any(mask)
            T.Rank(mask) = layers(mask);
        end
    end
elseif ~ismember("Rank", string(T.Properties.VariableNames)) || all(~isfinite(double(T.Rank)))
    T.Rank = double(T.RankIndicator);
end
T.BaseStationID = repmat(double(sixgr.util.structGet(userMeta, "RuntimeServingCell", NaN)), n, 1);
if ~ismember("ServingCell", string(T.Properties.VariableNames))
    T.ServingCell = double(T.BaseStationID);
end
if ~ismember("ServingRSRP_dBm", string(T.Properties.VariableNames)) || all(~isfinite(double(T.ServingRSRP_dBm)))
    T.ServingRSRP_dBm = repmat(double(sixgr.util.structGet(userMeta, "RuntimeServingRSRP_dBm", NaN)), n, 1);
end
if (~ismember("ServingRSRPSource", string(T.Properties.VariableNames)) || all(strlength(string(T.ServingRSRPSource)) == 0)) && any(isfinite(double(T.ServingRSRP_dBm)))
    T.ServingRSRPSource = repmat("large_scale_per_reference_re_power", n, 1);
end
if ~ismember("LargeScaleSINR_dB", string(T.Properties.VariableNames)) || all(~isfinite(double(T.LargeScaleSINR_dB)))
    T.LargeScaleSINR_dB = repmat(double(sixgr.util.structGet(userMeta, "RuntimeServingLargeScaleSINR_dB", NaN)), n, 1);
end
if (~ismember("LargeScaleSINRSource", string(T.Properties.VariableNames)) || all(strlength(string(T.LargeScaleSINRSource)) == 0)) && any(isfinite(double(T.LargeScaleSINR_dB)))
    T.LargeScaleSINRSource = repmat("large_scale_interference_budget_preview", n, 1);
end
if ~ismember("InterferenceMode", string(T.Properties.VariableNames)) || all(strlength(string(T.InterferenceMode)) == 0)
    T.InterferenceMode = repmat(string(sixgr.util.structGet(userMeta, "RuntimeInterferenceMode", ...
        ternaryInterferenceMode(cfg))), n, 1);
end
direction = directionFromTable(T);
T.ConfiguredTxAntennas = repmat(double(localConfiguredTxAntennaCount(cfg, direction)), n, 1);
T.ConfiguredRxAntennas = repmat(double(localConfiguredRxAntennaCount(cfg, direction)), n, 1);
T.ConfiguredLayers = repmat(double(localConfiguredLayerCount(cfg, direction)), n, 1);
T.ExecutionModel = repmat(string(multiUser.ExecutionModel), n, 1);
T.BeamSelectionStrategy = repmat(string(sixgr.util.structGet(userMeta, "BeamSelectionStrategy", multiUser.BeamSelectionStrategy)), n, 1);
T.BeamIndexSet = repmat(string(sixgr.util.structGet(userMeta, "BeamIndexSet", "")), n, 1);
T = localApplyTrialTruthAnnotations(T, directionFromTable(T), cfg);
end

function mode = ternaryInterferenceMode(cfg)
mode = "none";
configuredMode = string(sixgr.util.structGet(cfg, "run.interferenceExecutionMode", ""));
if strlength(strtrim(configuredMode)) > 0
    mode = configuredMode;
elseif logical(sixgr.util.structGet(cfg, "run.useAbstractInterferenceModel", false))
    error("sixgr:truth:AbstractInterferenceModeRemoved", ...
        "run.useAbstractInterferenceModel=true is not allowed in no-proxy waveform LLS.");
end
end

function ueIdx = localResolveGrantUEIndex(grant, multiUser)
ueIdx = double(sixgr.util.structGet(grant, "UEIndex", NaN));
if isfinite(ueIdx) && ueIdx >= 1
    return;
end
rnti = double(sixgr.util.structGet(grant, "RNTI", NaN));
rntiStart = double(sixgr.util.structGet(multiUser, "RNTIStart", 1));
if isfinite(rnti)
    ueIdx = round(rnti - rntiStart + 1);
else
    ueIdx = NaN;
end
end

function T = localAnnotateGrantDrivenTrials(T, grantRow)
if ~(istable(T) && ~isempty(T) && istable(grantRow) && ~isempty(grantRow))
    return;
end
vars = string(grantRow.Properties.VariableNames);
for i = 1:numel(vars)
    name = char(vars(i));
    value = grantRow.(name)(1);
    if ismember(name, string(T.Properties.VariableNames))
        if isstring(T.(name))
            T.(name)(:) = string(value);
        elseif islogical(T.(name))
            T.(name)(:) = logical(value);
        else
            T.(name)(:) = double(value);
        end
    else
        if isstring(value) || ischar(value)
            T.(name) = repmat(string(value), height(T), 1);
        elseif islogical(value)
            T.(name) = repmat(logical(value), height(T), 1);
        else
            T.(name) = repmat(double(value), height(T), 1);
        end
    end
end
end

function T = localAnnotateConstellationSamples(T, cfg, multiUser, ueIdx, userMeta, snr_dB, direction)
if ~istable(T) || isempty(T)
    T = table();
    return;
end
n = height(T);
if ~ismember("UEIndex", string(T.Properties.VariableNames))
    T.UEIndex = repmat(double(ueIdx), n, 1);
end
if ~ismember("RNTI", string(T.Properties.VariableNames))
    T.RNTI = repmat(double(localUserRNTI(multiUser, ueIdx)), n, 1);
end
if ~ismember("Direction", string(T.Properties.VariableNames))
    if ismember("direction", string(T.Properties.VariableNames))
        T.Direction = string(T.direction);
    else
        T.Direction = repmat(string(direction), n, 1);
    end
end
if ~ismember("Modulation", string(T.Properties.VariableNames)) && ismember("modulation", string(T.Properties.VariableNames))
    T.Modulation = string(T.modulation);
end
if ~ismember("SNR_dB", string(T.Properties.VariableNames))
    if ismember("snr_db", string(T.Properties.VariableNames))
        T.SNR_dB = double(T.snr_db);
    else
        T.SNR_dB = repmat(double(snr_dB), n, 1);
    end
end
if ~ismember("Modulation", string(T.Properties.VariableNames))
    T.Modulation = strings(n, 1);
end
if ~ismember("BeamSelectionStrategy", string(T.Properties.VariableNames))
    T.BeamSelectionStrategy = repmat(string(sixgr.util.structGet(userMeta, "BeamSelectionStrategy", ...
        sixgr.util.structGet(multiUser, "BeamSelectionStrategy", "missing_from_config"))), n, 1);
end
if ~ismember("ConfiguredTxAntennas", string(T.Properties.VariableNames))
    T.ConfiguredTxAntennas = repmat(double(localConfiguredTxAntennaCount(cfg, direction)), n, 1);
end
if ~ismember("ConfiguredRxAntennas", string(T.Properties.VariableNames))
    T.ConfiguredRxAntennas = repmat(double(localConfiguredRxAntennaCount(cfg, direction)), n, 1);
end
T = localCanonicalizeConstellationSampleTable(T, direction, snr_dB);
end

function T = localCanonicalizeConstellationSampleTable(T, direction, snr_dB)
if ~(istable(T) && ~isempty(T))
    return;
end
n = height(T);
if ~ismember("Direction", string(T.Properties.VariableNames))
    T.Direction = repmat(string(direction), n, 1);
end
if ~ismember("SNR_dB", string(T.Properties.VariableNames))
    T.SNR_dB = repmat(double(snr_dB), n, 1);
end
if ~ismember("Modulation", string(T.Properties.VariableNames))
    T.Modulation = localConstellationStringColumn(T, ["modulation","RuntimeModulation"], strings(n, 1));
end
if ~ismember("TBId", string(T.Properties.VariableNames))
    if all(ismember(["Frame","Slot"], string(T.Properties.VariableNames)))
        T.TBId = double(T.Frame) .* 10000 + double(T.Slot);
    else
        T.TBId = nan(n, 1);
    end
end
if ismember("TxReal", string(T.Properties.VariableNames)) && ~ismember("ReferenceSymbolReal", string(T.Properties.VariableNames))
    T.ReferenceSymbolReal = T.TxReal;
end
if ismember("TxImag", string(T.Properties.VariableNames)) && ~ismember("ReferenceSymbolImag", string(T.Properties.VariableNames))
    T.ReferenceSymbolImag = T.TxImag;
end
if ~ismember("MCSIndex", string(T.Properties.VariableNames)) && ismember("MCS", string(T.Properties.VariableNames))
    T.MCSIndex = double(T.MCS);
end
if ~ismember("PostEqSINR_dB", string(T.Properties.VariableNames)) && ismember("MeasuredSINR_dB", string(T.Properties.VariableNames))
    T.PostEqSINR_dB = double(T.MeasuredSINR_dB);
end
if ~ismember("EVM_rms_pct", string(T.Properties.VariableNames))
    if ismember("evm_rms_pct", string(T.Properties.VariableNames))
        T.EVM_rms_pct = double(T.evm_rms_pct);
    elseif ismember("EVM_rms", string(T.Properties.VariableNames))
        T.EVM_rms_pct = double(T.EVM_rms) .* 100;
    elseif ismember("SymbolEVM_rms", string(T.Properties.VariableNames))
        T.EVM_rms_pct = double(T.SymbolEVM_rms) .* 100;
    else
        T.EVM_rms_pct = nan(n, 1);
    end
end
if ~ismember("EVM_dB", string(T.Properties.VariableNames))
    if ismember("evm_db", string(T.Properties.VariableNames))
        T.EVM_dB = double(T.evm_db);
    elseif ismember("EVM_rms", string(T.Properties.VariableNames))
        T.EVM_dB = 20 .* log10(max(double(T.EVM_rms), realmin));
    elseif ismember("SymbolEVM_rms", string(T.Properties.VariableNames))
        T.EVM_dB = 20 .* log10(max(double(T.SymbolEVM_rms), realmin));
    else
        T.EVM_dB = nan(n, 1);
    end
end
if ~ismember("Normalization", string(T.Properties.VariableNames))
    if any(ismember(["normalization","RuntimeNormalization"], string(T.Properties.VariableNames)))
        T.Normalization = localConstellationStringColumn(T, ["normalization","RuntimeNormalization"], ...
            repmat("post_equalized_and_reference_unit_power_constellation", n, 1));
    else
        T.Normalization = repmat("post_equalized_and_reference_unit_power_constellation", n, 1);
    end
end
if ~ismember("TruthStatus", string(T.Properties.VariableNames))
    T.TruthStatus = localConstellationStringColumn(T, ["truth_status","RuntimeTruthStatus"], ...
        repmat("real_lls_evidence", n, 1));
end

T.direction = localConstellationStringColumn(T, ["direction","Direction","RuntimeDirection"], repmat(string(direction), n, 1));
T.ue_id = localConstellationNumericColumn(T, ["ue_id","UEIndex","UEId","UEID","RNTI"]);
T.slot = localConstellationNumericColumn(T, ["slot","Slot","RuntimeSlot"]);
T.tb_id = localConstellationNumericColumn(T, ["tb_id","TBId"]);
T.layer = localConstellationNumericColumn(T, ["layer","LayerIndex","Layer"]);
T.modulation = localConstellationStringColumn(T, ["modulation","Modulation","RuntimeModulation"], strings(n, 1));
T.mcs_index = localConstellationNumericColumn(T, ["mcs_index","MCSIndex","MCS"]);
T.snr_db = localConstellationNumericColumn(T, ["snr_db","SNR_dB","RuntimeSNR_dB"]);
T.posteq_sinr_db = localConstellationNumericColumn(T, ["posteq_sinr_db","PostEqSINR_dB","MeasuredSINR_dB","MeasuredTrialSINR_dB"]);
T.symbol_index = localConstellationNumericColumn(T, ["symbol_index","SampleIndex"]);
T.reference_symbol_i = localConstellationNumericColumn(T, ["reference_symbol_i","ReferenceSymbolReal","TxReal"]);
T.reference_symbol_q = localConstellationNumericColumn(T, ["reference_symbol_q","ReferenceSymbolImag","TxImag"]);
T.equalized_i = localConstellationNumericColumn(T, ["equalized_i","EqualizedReal"]);
T.equalized_q = localConstellationNumericColumn(T, ["equalized_q","EqualizedImag"]);
T.evm_rms_pct = localConstellationNumericColumn(T, ["evm_rms_pct","EVM_rms_pct","RuntimeEVMRms_pct"]);
T.evm_db = localConstellationNumericColumn(T, ["evm_db","EVM_dB","RuntimeEVM_dB"]);
T.normalization = localConstellationStringColumn(T, ["Normalization","normalization","RuntimeNormalization"], ...
    repmat("post_equalized_and_reference_unit_power_constellation", n, 1));
T.truth_status = localConstellationStringColumn(T, ["TruthStatus","truth_status","RuntimeTruthStatus"], ...
    repmat("real_lls_evidence", n, 1));
T = localDisambiguateConstellationCaseCollisionColumns(T);
end

function T = localDisambiguateConstellationCaseCollisionColumns(T)
renameMap = [ ...
    "Direction", "RuntimeDirection"; ...
    "Modulation", "RuntimeModulation"; ...
    "SNR_dB", "RuntimeSNR_dB"; ...
    "Slot", "RuntimeSlot"; ...
    "EVM_rms_pct", "RuntimeEVMRms_pct"; ...
    "EVM_dB", "RuntimeEVM_dB"; ...
    "Normalization", "RuntimeNormalization"];
for i = 1:size(renameMap, 1)
    src = renameMap(i, 1);
    dst = renameMap(i, 2);
    names = string(T.Properties.VariableNames);
    if ~ismember(src, names)
        continue;
    end
    collidesCaseInsensitive = any(strcmpi(names, src) & names ~= src);
    if ~collidesCaseInsensitive
        continue;
    end
    target = dst;
    while ismember(target, names)
        T.(char(src)) = [];
        break;
    end
    if ~ismember(src, string(T.Properties.VariableNames))
        continue;
    end
    T = renamevars(T, src, target);
end
end

function values = localConstellationNumericColumn(T, names)
values = nan(height(T), 1);
names = string(names);
fallback = values;
haveFallback = false;
for i = 1:numel(names)
    if ~ismember(names(i), string(T.Properties.VariableNames))
        continue;
    end
    try
        candidate = double(T.(names(i)));
    catch
        candidate = str2double(string(T.(names(i))));
    end
    candidate = reshape(candidate, [], 1);
    if numel(candidate) == height(T)
        if any(isfinite(candidate))
            values = candidate;
            return;
        end
        if ~haveFallback
            fallback = candidate;
            haveFallback = true;
        end
    end
end
if haveFallback
    values = fallback;
end
end

function values = localConstellationStringColumn(T, names, defaultValues)
n = height(T);
values = string(defaultValues);
if isscalar(values) && n ~= 1
    values = repmat(values, n, 1);
else
    values = reshape(values, [], 1);
    if numel(values) ~= n
        if isempty(values)
            values = strings(n, 1);
        else
            values = repmat(values(1), n, 1);
        end
    end
end
names = string(names);
fallback = values;
haveFallback = false;
for i = 1:numel(names)
    if ~ismember(names(i), string(T.Properties.VariableNames))
        continue;
    end
    try
        candidate = string(T.(names(i)));
    catch
        continue;
    end
    candidate = candidate(:);
    if isscalar(candidate) && n ~= 1
        candidate = repmat(candidate, n, 1);
    end
    if numel(candidate) ~= n
        continue;
    end
    candidate(ismissing(candidate)) = "";
    if any(strlength(strtrim(candidate)) > 0)
        values = candidate;
        return;
    end
    if ~haveFallback
        fallback = candidate;
        haveFallback = true;
    end
end
if haveFallback
    values = fallback;
end
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
    summary = table();
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
    end

    ulT = localSubsetTrialsBySNR(sixgr.util.structGet(rawTrials, "UL", table()), snr);
    if ~isempty(ulT)
        ulStats = localSummarizeLinkTrialTable(ulT, cfg);
        row = localApplyLinkSweepStats(row, "UL", ulStats);
    end

    srsT = localSubsetTrialsBySNR(sixgr.util.structGet(rawTrials, "SRS", table()), snr);
    row = localApplyScalarSweepStats(row, "SRS_NMSE_dB", srsT, "NMSE_dB");
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

function campaign = localRunFixedLinkCampaign(cfg, snrGrid, sweepPlan, multiUser)
campaign = localEmptyFixedLinkCampaignResult(true);
snrGrid = unique(sort(double(snrGrid(:))));
snrGrid = snrGrid(isfinite(snrGrid));
if isempty(snrGrid)
    campaign.Notes = "skipped_empty_snr_grid";
    return;
end
campaign.SNRGrid_dB = snrGrid(:).';
campaign.SeedBase = double(sweepPlan.FixedLinkSeed);
if nargin < 4 || ~isstruct(multiUser)
    multiUser = localResolveMultiUserSpec(cfg);
end

if logical(sixgr.util.structGet(multiUser, "Enabled", false))
    summary = table();
    dlTrials = table();
    ulTrials = table();
    for ueIdx = 1:max(1, round(double(multiUser.NumUsers)))
        cfgU = localPrepareUserCfg(cfg, multiUser, ueIdx);
        userCampaign = localRunFixedLinkCampaignSingleUser(cfgU, snrGrid, sweepPlan);
        Su = sixgr.util.structGet(userCampaign, "Summary", table());
        if istable(Su) && ~isempty(Su)
            Su.UEIndex = repmat(double(ueIdx), height(Su), 1);
            Su.RNTI = repmat(double(localUserRNTI(multiUser, ueIdx)), height(Su), 1);
            Su.ExecutionModel = repmat(string(multiUser.ExecutionModel), height(Su), 1);
            summary = localAppendCompatTable(summary, Su);
        end
        dlTrials = localAppendCompatTable(dlTrials, sixgr.util.structGet(userCampaign, "DLTrials", table()));
        ulTrials = localAppendCompatTable(ulTrials, sixgr.util.structGet(userCampaign, "ULTrials", table()));
        userTaskPlan = sixgr.util.structGet(userCampaign, "TaskPlan", table());
        if istable(userTaskPlan) && ~isempty(userTaskPlan)
            userTaskPlan.UEIndex = repmat(double(ueIdx), height(userTaskPlan), 1);
            userTaskPlan.RNTI = repmat(double(localUserRNTI(multiUser, ueIdx)), height(userTaskPlan), 1);
            userTaskPlan.ExecutionModel = repmat(string(multiUser.ExecutionModel), height(userTaskPlan), 1);
            campaign.TaskPlan = localAppendCompatTable(campaign.TaskPlan, userTaskPlan);
        end
    end
    campaign.Summary = summary;
    campaign.DLTrials = dlTrials;
    campaign.ULTrials = ulTrials;
    campaign.Notes = "multi_user_fixed_link_campaign_executed_as_independent_fixed_links";
    return;
end

campaign = localRunFixedLinkCampaignSingleUser(cfg, snrGrid, sweepPlan);
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

    if logical(sixgr.util.structGet(cfgRef, "phy.pdsch.enable", true))
        [stats, trials] = localRunFixedDirectionCampaignPoint(cfgRef, "DL", snr, i, sweepPlan, taskPlan);
        row = localApplyFixedDirectionStats(row, "DL", stats);
        dlAll = localAppendCompatTable(dlAll, trials);
    end

    if logical(sixgr.util.structGet(cfgRef, "phy.pusch.enable", true))
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
if logical(sixgr.util.structGet(cfg, "phy.pdsch.enable", true))
    tokens(end+1, 1) = "DL";
end
if logical(sixgr.util.structGet(cfg, "phy.pusch.enable", true))
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
        stats.StopReason = "max_trials_reached";
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
        [stats.BLER_ClusterCI_Low, stats.BLER_ClusterCI_High] = localMeanConfidenceInterval(dropFail);
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
    stopReason = "error_target_reached";
elseif isfinite(double(sweepPlan.FixedLinkCIWidthTarget)) && isfinite(ciWidth) && ciWidth <= double(sweepPlan.FixedLinkCIWidthTarget)
    stopReason = "ci_width_target_reached";
elseif trialCount >= double(sweepPlan.FixedLinkMaxTrials)
    stopReason = "max_trials_reached";
else
    stopReason = "continue";
end
end

function tf = localFixedLinkIncomplete(stats, sweepPlan, stopReason)
tf = false;
if string(stopReason) ~= "max_trials_reached"
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
nmse = double(sixgr.util.structGet(srs, "NMSE_dB", NaN));
if isfinite(nmse)
    row.SRS_NMSE_dB = nmse;
    row.SRS_NMSE_CI_Low = nmse;
    row.SRS_NMSE_CI_High = nmse;
    row.SRS_TrialCount = 1;
end
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
    [status, crossingSNR] = localFixedLinkCrossingStatus(T, prefix, double(sweepPlan.FixedLinkTargetBLER));
    T.(char(targetCol)) = repmat(double(sweepPlan.FixedLinkTargetBLER), height(T), 1);
    T.(char(statusCol)) = repmat(string(status), height(T), 1);
    T.(char(snrCol)) = repmat(double(crossingSNR), height(T), 1);
end
end

function [status, crossingSNR] = localFixedLinkCrossingStatus(T, prefix, targetBLER)
status = "insufficient_finite_points";
crossingSNR = NaN;
prefix = upper(string(prefix));
x = double(T.SNR_dB);
y = double(T.(char(prefix + "_BLER")));
mask = isfinite(x) & isfinite(y);
if nnz(mask) < 2
    return;
end
x = x(mask);
y = y(mask);
[x, order] = sort(x(:));
y = y(order);
target = double(targetBLER);
for i = 1:numel(x)-1
    y1 = y(i);
    y2 = y(i + 1);
    if (y1 >= target && y2 <= target) || (y1 <= target && y2 >= target)
        if abs(y2 - y1) < eps
            crossingSNR = x(i);
        else
            crossingSNR = x(i) + (target - y1) .* (x(i + 1) - x(i)) ./ (y2 - y1);
        end
        status = "crossing_observed";
        return;
    end
end
if all(y > target)
    status = "no_crossing_all_points_above_target";
elseif all(y < target)
    status = "no_crossing_all_points_below_target";
else
    status = "no_crossing_nonmonotonic_points";
end
end

function res = localApplyPrimarySweepResults(res, rawTrials, cfg, snrGrid, pruneMissingPrimaryEvidence)
if nargin < 5
    pruneMissingPrimaryEvidence = false;
end
snrGrid = unique(sort(double(snrGrid(:))));
if isfield(rawTrials, "PBCH") && istable(rawTrials.PBCH) && ~isempty(rawTrials.PBCH)
    aggPBCH = localAggregatePrimaryPassFailCase(rawTrials.PBCH, "PBCH geometry-driven");
    res = localReplaceCaseResult(res, "CellSearch_MIB_SIB1", aggPBCH);
end
if isfield(rawTrials, "PRACH") && istable(rawTrials.PRACH) && ~isempty(rawTrials.PRACH)
    aggPRACH = localAggregatePrimaryPassFailCase(rawTrials.PRACH, "PRACH geometry-driven");
    res = localReplaceCaseResult(res, "PRACH_Detection", aggPRACH);
end
if isfield(rawTrials, "DL") && istable(rawTrials.DL) && ~isempty(rawTrials.DL)
    aggDL = localAggregatePrimaryLinkCase(rawTrials.DL, cfg, "DL geometry-driven");
    res = localReplaceCaseResult(res, "DL_PDSCH_Throughput", aggDL);
end
if isfield(rawTrials, "UL") && istable(rawTrials.UL) && ~isempty(rawTrials.UL)
    aggUL = localAggregatePrimaryLinkCase(rawTrials.UL, cfg, "UL geometry-driven");
    res = localReplaceCaseResult(res, "UL_PUSCH_Throughput", aggUL);
    aggPAPR = localAggregatePrimaryULPAPRCase(rawTrials.UL);
    res = localReplaceCaseResult(res, "UL_LowPAPR", aggPAPR);
end
if isfield(rawTrials, "SRS") && istable(rawTrials.SRS) && ~isempty(rawTrials.SRS)
    aggSRS = localAggregatePrimarySRSCase(rawTrials.SRS);
    res = localReplaceCaseResult(res, "UL_SRS_ChannelEst", aggSRS);
end
if logical(pruneMissingPrimaryEvidence)
    res = localPrunePrimaryCasesWithoutEvidence(res, rawTrials);
end
res.Ok = localLinkKPITableHealthy(res.KPITable);
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
agg.Notes = string(label) + "; geometry_driven=true" + ...
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
agg.Notes = string(label) + "; geometry_driven=true" + localMeasuredSINRRangeNoteFromTable(Te);
end

function agg = localAggregatePrimarySRSCase(T)
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
nmse = localFiniteColumn(Te, "NMSE_dB");
agg.NMSE_dB = mean(nmse, "omitnan");
agg.Ok = ~isempty(nmse);
agg.Notes = "SRS geometry-driven; nmse_source=srs_trials.NMSE_dB" + localMeasuredSINRRangeNoteFromTable(Te);
end

function agg = localAggregatePrimaryULPAPRCase(T)
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
agg.Notes = "UL low-PAPR geometry-driven; papr_source=ul_pusch_trials.PAPR_dB" + ...
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
[stats.BER_CI_Low, stats.BER_CI_High] = localWilsonInterval(sum(bitErr), sum(bits));
[stats.BLER_CI_Low, stats.BLER_CI_High] = localWilsonInterval(sum(failMask), height(Te));
stats.Throughput_Mbps = localAggregateThroughputFromTrials(Te, cfg);
[stats.Throughput_CI_Low, stats.Throughput_CI_High] = localMeanConfidenceInterval(localTrialThroughputSamples(Te, cfg));
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
thr = localAggregateBitRateFromTrials(T, cfg, "GoodBits");
end

function samples = localTrialThroughputSamples(T, cfg)
samples = localTrialBitRateSamples(T, cfg, "GoodBits");
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

function [lo, hi] = localWilsonInterval(k, n)
lo = NaN;
hi = NaN;
n = double(n);
k = double(k);
if ~(isfinite(n) && n > 0 && isfinite(k) && k >= 0)
    return;
end
z = 1.95996398454005;
p = min(max(k / n, 0), 1);
den = 1 + (z^2 / n);
center = (p + z^2 / (2 * n)) / den;
spread = (z / den) * sqrt((p * (1 - p) / n) + (z^2 / (4 * n^2)));
lo = max(0, center - spread);
hi = min(1, center + spread);
end

function [lo, hi] = localMeanConfidenceInterval(x)
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
z = 1.95996398454005;
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

function row = localApplyScalarSweepStats(row, fieldPrefix, trialT, valueVar)
trialT = localEffectiveTrialRows(trialT);
vals = [];
if istable(trialT) && ~isempty(trialT) && ismember(valueVar, string(trialT.Properties.VariableNames))
    vals = double(trialT.(valueVar));
    vals = vals(isfinite(vals));
end
base = string(fieldPrefix);
if isempty(vals)
    return;
end
[lo, hi] = localMeanConfidenceInterval(vals);
row.(char(base)) = mean(vals, "omitnan");
ciBase = base;
countName = base;
if endsWith(base, "_dB")
    ciBase = erase(base, "_dB");
end
row.(char(ciBase + "_CI_Low")) = lo;
row.(char(ciBase + "_CI_High")) = hi;
parts = split(ciBase, "_");
if ~isempty(parts) && strlength(parts(1)) > 0
    countName = parts(1);
end
row.(char(countName + "_TrialCount")) = double(numel(vals));
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

function nTx = localConfiguredTxAntennaCount(cfg, direction)
direction = upper(string(direction));
if direction == "UL"
    userMeta = sixgr.util.structGet(cfg, "lls6g.userContext", struct());
    nTx = localFirstFiniteScalar( ...
        sixgr.util.structGet(userMeta, "RuntimeUEAntennaMeta.NumPorts", NaN), ...
        sixgr.util.structGet(userMeta, "RuntimeUEAntenna.NumPorts", NaN), ...
        sixgr.util.structGet(cfg, "scenario.ue.nTxAnt", NaN), ...
        sixgr.util.structGet(cfg, "channel.ul.nTxAnt", NaN), ...
        sixgr.util.structGet(cfg, "phy.ul.nTxAnt", NaN), ...
        sixgr.util.structGet(cfg, "phy.pusch.NumAntennaPorts", NaN), ...
        sixgr.util.structGet(cfg, "phy.pusch.numPorts", NaN), ...
        sixgr.util.structGet(cfg, "channel.nTxAntUL", NaN), ...
        sixgr.util.structGet(cfg, "antenna.ue.numPorts", NaN), ...
        sixgr.util.structGet(cfg, "antenna.ue.numElements", NaN), ...
        1);
else
    nTx = double(sixgr.util.structGet(cfg, "scenario.bs.nTxAnt", ...
        sixgr.util.structGet(cfg, "channel.nTxAnt", sixgr.util.structGet(cfg, "phy.nTxAnt", 1))));
end
if ~(isscalar(nTx) && isfinite(nTx) && nTx >= 1)
    nTx = 1;
end
nTx = max(1, round(nTx));
end

function nRx = localConfiguredRxAntennaCount(cfg, direction)
direction = upper(string(direction));
if direction == "UL"
    userMeta = sixgr.util.structGet(cfg, "lls6g.userContext", struct());
    nRx = localFirstFiniteScalar( ...
        sixgr.util.structGet(userMeta, "RuntimeServingBSAntennaMeta.NumPorts", NaN), ...
        sixgr.util.structGet(userMeta, "RuntimeServingBSAntenna.NumPorts", NaN), ...
        sixgr.util.structGet(cfg, "scenario.bs.nRxAnt", NaN), ...
        sixgr.util.structGet(cfg, "channel.ul.nRxAnt", NaN), ...
        sixgr.util.structGet(cfg, "phy.ul.nRxAnt", NaN), ...
        sixgr.util.structGet(cfg, "channel.nRxAntUL", NaN), ...
        sixgr.util.structGet(cfg, "scenario.bs.nTxAnt", NaN), ...
        sixgr.util.structGet(cfg, "antenna.bs.numPorts", NaN), ...
        sixgr.util.structGet(cfg, "antenna.bs.numElements", NaN), ...
        sixgr.util.structGet(cfg, "channel.nRxAnt", NaN), ...
        sixgr.util.structGet(cfg, "phy.nRxAnt", NaN), ...
        1);
else
    nRx = double(sixgr.util.structGet(cfg, "scenario.ue.nRxAnt", ...
        sixgr.util.structGet(cfg, "channel.nRxAnt", sixgr.util.structGet(cfg, "phy.nRxAnt", 1))));
end
if ~(isscalar(nRx) && isfinite(nRx) && nRx >= 1)
    nRx = 1;
end
nRx = max(1, round(nRx));
end

function direction = directionFromTable(T)
direction = "DL";
if istable(T) && ~isempty(T) && ismember("Direction", string(T.Properties.VariableNames))
    direction = string(T.Direction(1));
end
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
plan.FixedLinkSNRGrid_dB = double(sixgr.util.structGet(opt, "LinkFixedLinkSNRGrid_dB", []));
plan.FixedLinkMinTrials = max(1, round(double(sixgr.util.structGet(opt, "LinkFixedLinkMinTrials", plan.ReferenceTrialsPerSNR))));
plan.FixedLinkMaxTrials = max(plan.FixedLinkMinTrials, round(double(sixgr.util.structGet(opt, "LinkFixedLinkMaxTrials", plan.ReferenceTrialsPerSNR))));
plan.FixedLinkTrialsPerDrop = max(1, round(double(sixgr.util.structGet(opt, "LinkFixedLinkTrialsPerDrop", min(plan.FixedLinkMaxTrials, baseTrials)))));
plan.FixedLinkErrorTarget = max(1, round(double(sixgr.util.structGet(opt, "LinkFixedLinkErrorTarget", inf))));
plan.FixedLinkCIWidthTarget = double(sixgr.util.structGet(opt, "LinkFixedLinkCIWidthTarget", inf));
if ~(isfinite(plan.FixedLinkCIWidthTarget) && plan.FixedLinkCIWidthTarget >= 0)
    plan.FixedLinkCIWidthTarget = inf;
end
plan.FixedLinkConfidenceLevel = double(sixgr.util.structGet(opt, "LinkFixedLinkConfidenceLevel", 0.95));
if ~(isfinite(plan.FixedLinkConfidenceLevel) && plan.FixedLinkConfidenceLevel > 0 && plan.FixedLinkConfidenceLevel < 1)
    plan.FixedLinkConfidenceLevel = 0.95;
end
plan.FixedLinkSeed = double(sixgr.util.structGet(opt, "LinkFixedLinkSeed", 730001));
if ~(isfinite(plan.FixedLinkSeed) && plan.FixedLinkSeed >= 0)
    plan.FixedLinkSeed = 730001;
end
plan.FixedLinkTargetBLER = double(sixgr.util.structGet(opt, "LinkFixedLinkTargetBLER", 0.10));
if ~(isfinite(plan.FixedLinkTargetBLER) && plan.FixedLinkTargetBLER > 0 && plan.FixedLinkTargetBLER < 1)
    plan.FixedLinkTargetBLER = 0.10;
end
end

function grid = localBuildAdaptiveRefinedGrid(sweepT, anchorGrid, cfg, opt)
grid = [];
if ~(istable(sweepT) && ~isempty(sweepT) && ismember("SNR_dB", string(sweepT.Properties.VariableNames)))
    return;
end
if ~logical(sixgr.util.structGet(opt, "LinkAdaptiveSweepEnabled", localShouldAdaptiveRefineTruthSweep(cfg)))
    return;
end
step = max(1, double(sixgr.util.structGet(opt, "LinkAdaptiveSweepStep_dB", 2)));
maxExtra = max(0, round(double(sixgr.util.structGet(opt, "LinkAdaptiveSweepMaxPoints", 12))));
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

function slotDur_s = localSlotDuration(cfg)
scs = double(sixgr.util.structGet(cfg, "phy.carrier.SubcarrierSpacing", 30));
mu = log2(scs/15);
if ~isfinite(mu) || mu < 0
    mu = 0;
end
slotDur_s = 1e-3 / (2^mu);
end

function [y, nVar] = localAddAwgn(x, snr_dB)
[y, nVar] = sixgr.util.addAwgnComplex(x, snr_dB);
end

function [be, bt] = localBitErrors(txBits, rxBits)
txBits = int8(txBits(:));
rxBits = int8(rxBits(:));
L = min(numel(txBits), numel(rxBits));
if L <= 0
    be = numel(txBits);
    bt = max(numel(txBits), 1);
    return;
end
be = sum(txBits(1:L) ~= rxBits(1:L));
bt = max(numel(txBits), L);
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
    sixgr.util.csvWriteTable(statePath, stateTraceT);
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

keepVars = ["UEIndex","RNTI","Direction","SNR_dB","Frame","Slot","MCS","PRBs","Layers", ...
    "ConfiguredLayers","ConfiguredTxAntennas","ConfiguredRxAntennas", ...
    "PostEqSINR_dB","ReceiverHestSINR_dB","WidebandCQI","RankIndicator","PMI","ChannelGain_dB","ConditionNumber_dB", ...
    "RankEstimate","NumRxAntennas","NumTxPorts","SelectedBeamIndex","BestBeamIndex", ...
    "BeamHit","TopKBeamHit","BeamCandidateCount","SelectedBeamGain_dB","BestBeamGain_dB","BeamGainGap_dB", ...
    "BeamSelectionStrategy","BeamIndexSet","ConfiguredBeamSelectionStrategy","AppliedBeamIndexSet", ...
    "PrecoderSource","PrecodingMode","PrecodingApplicationStage","PrecodingActive","ExplicitBeamWeightsApplied","TransformPrecodingApplied","BeamformingApplied", ...
    "AppliedPrecoderPMI","AppliedPrecoderPMIType","AppliedPrecoderCodebookMode","PrecodingNumPorts","PrecodingNumLayers","PrecodingMatrixRows","PrecodingMatrixCols", ...
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
    failureRate = mean(double(beamGap > 3), "omitnan");
    overhead = mean(beamCount, "omitnan");

    switchLatency = localFiniteColumn(eventDirT(eventDirT.SwitchEventFlag > 0, :), "SwitchLatency_s");
    if isempty(switchLatency)
        switchAvailability = "not_exercised";
        switchValue = NaN;
        switchNote = "No runtime beam-switch events were observed for this direction.";
    else
        switchAvailability = "observed";
        switchValue = mean(switchLatency, "omitnan");
        switchNote = "Measured from explicit runtime beam-switch events in the beam-management event trace.";
    end

    firstHitTrials = localFiniteColumn(eventDirT(eventDirT.FirstHitEventFlag > 0, :), "TrialsToFirstHit");
    if isempty(firstHitTrials)
        refinementAvailability = "not_exercised";
        refinementValue = NaN;
        refinementNote = "No runtime beam-refinement convergence event was observed for this direction.";
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
            "Measured from runtime trials whose beam gain gap exceeds 3 dB.", "observed"); ...
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
    failureFlag = isfinite(beamGap) & beamGap > 3;

    acquisitionFlag = false(n, 1);
    switchFlag = false(n, 1);
    firstHitFlag = false(n, 1);
    switchLatencySlots = nan(n, 1);
    switchLatency_s = nan(n, 1);
    trialsSinceLastSwitch = nan(n, 1);
    trialsToFirstHit = nan(n, 1);
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

dirs = ["DL","UL"];
chunks = cell(numel(dirs), 1);
for i = 1:numel(dirs)
    if ~isfield(rawTrials, dirs(i))
        continue;
    end
    Ti = localResolveTrialTable(rawTrials.(dirs(i)));
    if ~(istable(Ti) && ismember("PAPR_dB", string(Ti.Properties.VariableNames)))
        continue;
    end
    samples = double(Ti.PAPR_dB);
    samples = samples(isfinite(samples));
    if isempty(samples)
        continue;
    end
    lo = floor(min(samples) * 2) / 2;
    hi = ceil(max(samples) * 2) / 2;
    if ~isfinite(lo) || ~isfinite(hi)
        continue;
    end
    if hi <= lo
        grid = lo;
    else
        grid = linspace(lo, hi, min(64, max(16, numel(unique(round(samples, 2)))))).';
    end
    ccdf = arrayfun(@(thr) mean(samples >= thr, "omitnan"), grid);
    chunks{i} = table(repmat(dirs(i), numel(grid), 1), grid, ccdf, ...
        'VariableNames', {'Direction','PAPR_dB','CCDF'});
end

chunks = chunks(~cellfun(@isempty, chunks));
if isempty(chunks)
    return;
end
paprT = vertcat(chunks{:});
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
        T = readtable(p, "VariableNamingRule", "preserve");
    end
end
end

function images = localExportTrialDiagnosticPlots(airInterfaceRunFolder, rawTrials, saveFigures)
images = {};
if ~saveFigures
    return;
end
imgDir = fullfile(airInterfaceRunFolder, "image");
sixgr.util.ensureFolder(imgDir);

if isstruct(rawTrials) && isfield(rawTrials, "DL")
    Tdl = localResolveTrialTable(rawTrials.DL);
else
    Tdl = table();
end
if isstruct(rawTrials) && isfield(rawTrials, "DLConstellation")
    TdlConst = localResolveTrialTable(rawTrials.DLConstellation);
else
    TdlConst = table();
end
if istable(Tdl) && ~isempty(Tdl)
    localDeleteIfExists(fullfile(imgDir, "dl_trial_sinr.png"));
    localDeleteIfExists(fullfile(imgDir, "dl_trial_channel_gain.png"));
    localWriteTrialMetricSummaryTable(airInterfaceRunFolder, Tdl, "PostEqSINR_dB", "DL", "posteq_sinr", "dl_posteq_sinr_by_trial_summary.csv");
    localWriteTrialMetricSummaryTable(airInterfaceRunFolder, Tdl, "ChannelGain_dB", "DL", "channel_gain", "dl_channel_gain_distribution_summary.csv");

    img = fullfile(imgDir, "dl_posteq_sinr_by_trial_scatter.png");
    localWriteTrialMetricScatterPlot(Tdl, "PostEqSINR_dB", img, "DL Post-Eq SINR by Trial", "Post-equalization SINR (dB)");
    if exist(img, "file") == 2
        images{end+1} = img; %#ok<AGROW>
    end

    img = fullfile(imgDir, "dl_channel_gain_distribution.png");
    localWriteTrialMetricDistributionPlot(Tdl, "ChannelGain_dB", img, "DL Channel Gain Distribution", "Gain (dB)");
    if exist(img, "file") == 2
        images{end+1} = img; %#ok<AGROW>
    end
end
if istable(TdlConst) && ~isempty(TdlConst)
    img = fullfile(imgDir, "dl_constellation_scatter.png");
    localDeleteIfExists(img);
    localWriteConstellationScatterPlot(TdlConst, img, "DL Constellation Scatter");
    if exist(img, "file") == 2
        images{end+1} = img; %#ok<AGROW>
    end
end

if isstruct(rawTrials) && isfield(rawTrials, "UL")
    Tul = localResolveTrialTable(rawTrials.UL);
else
    Tul = table();
end
if isstruct(rawTrials) && isfield(rawTrials, "ULConstellation")
    TulConst = localResolveTrialTable(rawTrials.ULConstellation);
else
    TulConst = table();
end
if istable(Tul) && ~isempty(Tul)
    localDeleteIfExists(fullfile(imgDir, "ul_trial_sinr.png"));
    localDeleteIfExists(fullfile(imgDir, "ul_trial_channel_gain.png"));
    localWriteTrialMetricSummaryTable(airInterfaceRunFolder, Tul, "PostEqSINR_dB", "UL", "posteq_sinr", "ul_posteq_sinr_by_trial_summary.csv");
    localWriteTrialMetricSummaryTable(airInterfaceRunFolder, Tul, "ChannelGain_dB", "UL", "channel_gain", "ul_channel_gain_distribution_summary.csv");

    img = fullfile(imgDir, "ul_posteq_sinr_by_trial_scatter.png");
    localWriteTrialMetricScatterPlot(Tul, "PostEqSINR_dB", img, "UL Post-Eq SINR by Trial", "Post-equalization SINR (dB)");
    if exist(img, "file") == 2
        images{end+1} = img; %#ok<AGROW>
    end

    img = fullfile(imgDir, "ul_channel_gain_distribution.png");
    localWriteTrialMetricDistributionPlot(Tul, "ChannelGain_dB", img, "UL Channel Gain Distribution", "Gain (dB)");
    if exist(img, "file") == 2
        images{end+1} = img; %#ok<AGROW>
    end
end
if istable(TulConst) && ~isempty(TulConst)
    img = fullfile(imgDir, "ul_constellation_scatter.png");
    localDeleteIfExists(img);
    localWriteConstellationScatterPlot(TulConst, img, "UL Constellation Scatter");
    if exist(img, "file") == 2
        images{end+1} = img; %#ok<AGROW>
    end
end
end

function localWriteTrialMetricSummaryTable(airInterfaceRunFolder, T, metricName, direction, metricLabel, fileName)
if ~(istable(T) && ~isempty(T) && ismember(metricName, string(T.Properties.VariableNames)))
    return;
end
csvDir = fullfile(airInterfaceRunFolder, "csv");
sixgr.util.ensureFolder(csvDir);
values = localNumericColumn(T, metricName);
ue = localNumericColumnOrDefault(T, ["UEIndex","UEId","UEID"], NaN);
layer = localLayerGroupColumn(T);
if isempty(ue)
    ue = nan(height(T), 1);
end
if isempty(layer)
    layer = repmat("all_layers", height(T), 1);
end
ueKeys = unique(ue(isfinite(ue)));
if isempty(ueKeys)
    ueKeys = NaN;
end
rows = repmat(struct("Direction", "", "MetricName", "", "MetricColumn", "", "UEIndex", NaN, "Layer", "", ...
    "p5", NaN, "p50", NaN, "p95", NaN, "mean", NaN, "std", NaN, "n_samples", 0), 0, 1);
for i = 1:numel(ueKeys)
    if isfinite(ueKeys(i))
        ueMask = ue == ueKeys(i);
    else
        ueMask = true(height(T), 1);
    end
    layerKeys = unique(layer(ueMask), "stable");
    for j = 1:numel(layerKeys)
        mask = ueMask & layer == layerKeys(j) & isfinite(values);
        samples = values(mask);
        samples = samples(isfinite(samples));
        if isempty(samples)
            continue;
        end
        rows(end + 1, 1) = struct( ... %#ok<AGROW>
            "Direction", string(direction), ...
            "MetricName", string(metricLabel), ...
            "MetricColumn", string(metricName), ...
            "UEIndex", double(ueKeys(i)), ...
            "Layer", string(layerKeys(j)), ...
            "p5", localPercentile(samples, 5), ...
            "p50", localPercentile(samples, 50), ...
            "p95", localPercentile(samples, 95), ...
            "mean", mean(samples, "omitnan"), ...
            "std", std(samples, "omitnan"), ...
            "n_samples", double(numel(samples)));
    end
end
if isempty(rows)
    return;
end
sixgr.util.csvWriteTable(fullfile(csvDir, fileName), struct2table(rows));
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

function localWriteTrialMetricDistributionPlot(T, metricName, outPath, plotTitle, yLabel)
if ~(istable(T) && ~isempty(T) && ismember(metricName, string(T.Properties.VariableNames)))
    return;
end
y = localNumericColumn(T, metricName);
y = y(isfinite(y));
if isempty(y)
    return;
end
fig = figure("Visible", "off", "Color", "w");
cleanupObj = onCleanup(@() close(fig)); %#ok<NASGU>
ax = axes(fig);
histogram(ax, y, "Normalization", "probability");
grid(ax, "on");
xlabel(ax, yLabel);
ylabel(ax, "Probability");
title(ax, plotTitle);
text(ax, 0.98, 0.95, sprintf("n=%d, p50=%.3g", numel(y), localPercentile(y, 50)), ...
    "Units", "normalized", "HorizontalAlignment", "right", "VerticalAlignment", "top");
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

function layer = localLayerGroupColumn(T)
layer = strings(0, 1);
vars = string(T.Properties.VariableNames);
for name = ["LayerIndex","Layer","NumLayers","Layers","n_layers"]
    if ismember(name, vars)
        raw = T.(name);
        layer = string(raw);
        layer = reshape(layer, [], 1);
        if numel(layer) == height(T)
            layer = string(name) + "=" + layer;
            return;
        end
    end
end
layer = repmat("all_layers", height(T), 1);
end

function value = localPercentile(samples, pct)
samples = sort(double(samples(:)));
samples = samples(isfinite(samples));
if isempty(samples)
    value = NaN;
    return;
end
if numel(samples) == 1
    value = samples(1);
    return;
end
pos = 1 + (double(pct) / 100) * (numel(samples) - 1);
lo = floor(pos);
hi = ceil(pos);
if lo == hi
    value = samples(lo);
else
    value = samples(lo) + (pos - lo) * (samples(hi) - samples(lo));
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

function rendered = localWriteConstellationScatterPlot(T, outPath, plotTitle)
rendered = false;
T = localCanonicalizeConstellationSampleTable(T, "", NaN);
[Tplot, reason] = localSelectConstellationPlotSlice(T);
if isempty(Tplot)
    localDeleteIfExists(outPath);
    if strlength(reason) > 0
        fprintf("Suppressing %s: %s\n", string(outPath), reason);
    end
    return;
end
fig = figure("Visible", "off", "Color", "w");
cleanupObj = onCleanup(@() close(fig)); %#ok<NASGU>
ax = axes(fig);
hold(ax, "on");
eqMask = isfinite(double(Tplot.equalized_i)) & isfinite(double(Tplot.equalized_q));
if any(eqMask)
    scatter(ax, double(Tplot.equalized_i(eqMask)), double(Tplot.equalized_q(eqMask)), 12, ...
        "filled", "MarkerFaceAlpha", 0.35, "DisplayName", "Aligned equalized");
end
hardRealName = localFirstExistingConstellationVar(Tplot, ["HardDecisionReal","DecisionReal"]);
hardImagName = localFirstExistingConstellationVar(Tplot, ["HardDecisionImag","DecisionImag"]);
decMask = false(height(Tplot), 1);
if strlength(hardRealName) > 0 && strlength(hardImagName) > 0
    decMask = isfinite(double(Tplot.(hardRealName))) & isfinite(double(Tplot.(hardImagName)));
end
if any(decMask)
    scatter(ax, double(Tplot.(hardRealName)(decMask)), double(Tplot.(hardImagName)(decMask)), 18, ...
        "x", "DisplayName", "Hard decision");
end
refMask = isfinite(double(Tplot.reference_symbol_i)) & isfinite(double(Tplot.reference_symbol_q));
if any(refMask)
    scatter(ax, double(Tplot.reference_symbol_i(refMask)), double(Tplot.reference_symbol_q(refMask)), 14, ...
        "+", "DisplayName", "Reference");
end
[idealI, idealQ] = localIdealConstellationPoints(string(Tplot.modulation(1)), ...
    double(Tplot.reference_symbol_i), double(Tplot.reference_symbol_q));
if ~isempty(idealI)
    scatter(ax, idealI, idealQ, 36, "kd", "LineWidth", 1.1, "DisplayName", "Ideal constellation");
    localDrawConstellationDecisionBoundaries(ax, idealI, idealQ);
end
grid(ax, "on");
axis(ax, "equal");
xlabel(ax, "In-phase");
ylabel(ax, "Quadrature");
evmPct = mean(double(Tplot.evm_rms_pct), "omitnan");
evmDb = mean(double(Tplot.evm_db), "omitnan");
ctxLine = sprintf("%s | mod=%s | layer=%g | SNR=%.3g dB | MCS=%g | N=%d | EVM=%.3g%% / %.3g dB", ...
    char(string(Tplot.direction(1))), char(string(Tplot.modulation(1))), double(Tplot.layer(1)), ...
    double(Tplot.snr_db(1)), double(Tplot.mcs_index(1)), height(Tplot), evmPct, evmDb);
title(ax, string(plotTitle) + newline + string(ctxLine));
text(ax, 0.02, 0.02, string(ctxLine), "Units", "normalized", "Interpreter", "none", ...
    "FontSize", 8, "BackgroundColor", [1 1 1], "Margin", 4, "VerticalAlignment", "bottom");
legend(ax, "Location", "best");
sixgr.util.exportFigureArtifact(fig, outPath, "Resolution", 160);
rendered = exist(outPath, "file") == 2;
end

function [Tplot, reason] = localSelectConstellationPlotSlice(T)
Tplot = table();
reason = "";
if ~(istable(T) && ~isempty(T))
    reason = "missing_constellation_table";
    return;
end
required = ["direction","modulation","layer","snr_db","mcs_index","posteq_sinr_db", ...
    "reference_symbol_i","reference_symbol_q","equalized_i","equalized_q","truth_status"];
if ~all(ismember(required, string(T.Properties.VariableNames)))
    reason = "missing_constellation_lineage_columns";
    return;
end
mask = isfinite(double(T.equalized_i)) & isfinite(double(T.equalized_q)) & ...
    isfinite(double(T.reference_symbol_i)) & isfinite(double(T.reference_symbol_q)) & ...
    isfinite(double(T.layer)) & isfinite(double(T.snr_db)) & ...
    isfinite(double(T.mcs_index)) & isfinite(double(T.posteq_sinr_db)) & ...
    strlength(strtrim(string(T.modulation))) > 0 & ...
    ismember(lower(strtrim(string(T.truth_status))), ["real_lls_evidence","truth","runtime_measured"]);
if ~any(mask)
    reason = "no_constellation_rows_with_modulation_layer_snr_lineage";
    return;
end
Tv = T(mask, :);
key = string(Tv.direction) + "|" + string(Tv.modulation) + "|layer=" + string(double(Tv.layer)) + "|snr=" + string(double(Tv.snr_db));
[keys, ~, g] = unique(key, "stable");
counts = accumarray(g, 1);
[~, best] = max(counts);
Tplot = Tv(key == keys(best), :);
if height(Tplot) > 2000
    idx = unique(round(linspace(1, height(Tplot), 2000)));
    Tplot = Tplot(idx, :);
end
end

function name = localFirstExistingConstellationVar(T, names)
name = "";
names = string(names);
for i = 1:numel(names)
    if ismember(names(i), string(T.Properties.VariableNames))
        name = names(i);
        return;
    end
end
end

function [idealI, idealQ] = localIdealConstellationPoints(modulation, refI, refQ)
modToken = upper(regexprep(char(strtrim(string(modulation))), "[^A-Z0-9/]", ""));
pts = [];
if contains(modToken, "BPSK") && ~contains(modToken, "QPSK")
    pts = [-1; 1];
else
    m = NaN;
    if contains(modToken, "QPSK")
        m = 4;
    else
        tok = regexp(modToken, "(\d+)QAM", "tokens", "once");
        if ~isempty(tok)
            m = str2double(tok{1});
        end
    end
    if isfinite(m) && m >= 4
        side = sqrt(m);
        if abs(side - round(side)) < 1e-9
            levels = (-(side - 1):2:(side - 1)).';
            [ii, qq] = meshgrid(levels, levels);
            pts = ii(:) + 1i .* qq(:);
            pts = pts ./ sqrt(mean(abs(pts).^2, "omitnan"));
        end
    end
end
if isempty(pts)
    ref = complex(refI(:), refQ(:));
    ref = ref(isfinite(real(ref)) & isfinite(imag(ref)));
    pts = complex(round(real(ref) .* 1e6) ./ 1e6, round(imag(ref) .* 1e6) ./ 1e6);
    pts = unique(pts, "stable");
    if numel(pts) > 64
        pts = pts(1:64);
    end
end
idealI = real(pts);
idealQ = imag(pts);
end

function localDrawConstellationDecisionBoundaries(ax, idealI, idealQ)
levelsI = unique(round(double(idealI(:)), 8));
levelsQ = unique(round(double(idealQ(:)), 8));
levelsI = sort(levelsI(isfinite(levelsI)));
levelsQ = sort(levelsQ(isfinite(levelsQ)));
if numel(levelsI) > 1
    mids = (levelsI(1:end-1) + levelsI(2:end)) ./ 2;
    for i = 1:numel(mids)
        xline(ax, mids(i), ":", "Color", [0.65 0.65 0.65], "HandleVisibility", "off");
    end
end
if numel(levelsQ) > 1
    mids = (levelsQ(1:end-1) + levelsQ(2:end)) ./ 2;
    for i = 1:numel(mids)
        yline(ax, mids(i), ":", "Color", [0.65 0.65 0.65], "HandleVisibility", "off");
    end
end
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
frame = localFiniteOrNaNColumn(T, "Frame");
slot = localFiniteOrNaNColumn(T, "Slot");
mask = isfinite(frame) & isfinite(slot);
absSlot(mask) = frame(mask) * slotsPerFrame + slot(mask);
end

function slotsPerFrame = localSlotsPerFrame(cfg)
slotDur_s = localSlotDuration(cfg);
if ~(isfinite(slotDur_s) && slotDur_s > 0)
    slotsPerFrame = 1;
    return;
end
slotsPerFrame = max(1, round(0.01 / slotDur_s));
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
