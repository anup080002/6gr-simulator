function out = exportSystemLevelCanonicalArtifacts(runFolder, scfg, cfg, systemOut)
%EXPORTSYSTEMLEVELCANONICALARTIFACTS Bridge system-level LLS results into canonical browser-owned artifacts.

layout = sixgr.report.resultLayout(runFolder);
sixgr.util.ensureFolder(layout.ReportCSVDir);
sixgr.util.ensureFolder(layout.AirInterfaceCSVDir);
sixgr.util.ensureFolder(layout.PacketFlowCSVDir);

details = sixgr.util.structGet(systemOut, "Details", struct());
grantT = sixgr.util.structGet(details, "SchedulerGrants", table());
if ~istable(grantT)
    grantT = table();
end

numerology = localCanonicalNumerology(cfg);
canonicalTTI_s = double(numerology.SlotDurationSeconds);
tti_s = double(sixgr.util.structGet(details, "TTI_s", ...
    sixgr.util.structGet(cfg, "system.tti_s", ...
    double(sixgr.util.structGet(cfg, "phy.numerology.slotDuration_ms", NaN)) / 1e3)));
tti_s = tti_s(:);
tti_s = tti_s(find(isfinite(tti_s) & tti_s > 0, 1, "first"));
if isempty(tti_s)
    tti_s = canonicalTTI_s;
elseif abs(tti_s - canonicalTTI_s) > max(eps(canonicalTTI_s), 1e-15)
    error("sixgr:truth:exportSystemLevelCanonicalArtifacts:TTINumerologyMismatch", ...
        "Configured/system TTI %.15g s conflicts with canonical SCS=%g kHz slot duration %.15g s.", ...
        tti_s, double(numerology.SubcarrierSpacingKHz), canonicalTTI_s);
end
slotDuration_ms = tti_s * 1e3;
slotsPerFrame = double(sixgr.util.structGet(cfg, ...
    "phy.numerology.slotsPerFrame", NaN));
if isfinite(slotsPerFrame) && ...
        slotsPerFrame ~= double(numerology.SlotsPerFrame)
    error("sixgr:truth:exportSystemLevelCanonicalArtifacts:FrameNumerologyMismatch", ...
        "Configured SlotsPerFrame=%g conflicts with canonical SCS=%g kHz value %g.", ...
        slotsPerFrame, double(numerology.SubcarrierSpacingKHz), ...
        double(numerology.SlotsPerFrame));
end
slotsPerFrame = double(numerology.SlotsPerFrame);

dlGrantT = localBuildDirectionalGrantTable(grantT, "DL", cfg, details, tti_s, slotsPerFrame);
ulGrantT = localBuildDirectionalGrantTable(grantT, "UL", cfg, details, tti_s, slotsPerFrame);
controlPDCCHT = localBuildSystemPDCCHTrialTable(dlGrantT, ulGrantT, slotDuration_ms);
controlPUCCHGrantT = localBuildSystemPUCCHGrantTable(dlGrantT, slotDuration_ms);
controlPUCCHT = localBuildSystemPUCCHTrialTable(controlPUCCHGrantT, slotDuration_ms);
sixgr.util.csvWriteTable(fullfile(layout.PacketFlowCSVDir, "live_dl_scheduler_grants.csv"), dlGrantT);
sixgr.util.csvWriteTable(fullfile(layout.PacketFlowCSVDir, "live_ul_scheduler_grants.csv"), ulGrantT);
sixgr.util.csvWriteTable(fullfile(layout.PacketFlowCSVDir, "live_pucch_grants.csv"), controlPUCCHGrantT);

dlRaw = localBuildDirectionalRawTrialTable(dlGrantT, "DL", scfg, cfg, details, tti_s, slotsPerFrame);
ulRaw = localBuildDirectionalRawTrialTable(ulGrantT, "UL", scfg, cfg, details, tti_s, slotsPerFrame);
dlRaw = sixgr.util.applyLLSRawTrialLifecycle(dlRaw);
ulRaw = sixgr.util.applyLLSRawTrialLifecycle(ulRaw);
sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir, "dl_pdsch_trials.csv"), dlRaw);
sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir, "ul_pusch_trials.csv"), ulRaw);

sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir, "pbch_trials.csv"), localEmptyControlTrialTable("PBCH"));
sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir, "prach_trials.csv"), localEmptyControlTrialTable("PRACH"));
sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir, "pdcch_trials.csv"), controlPDCCHT);
sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir, "pucch_trials.csv"), controlPUCCHT);
sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir, "srs_trials.csv"), localEmptyControlTrialTable("SRS"));
sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir, "trs_trials.csv"), localEmptyControlTrialTable("TRS"));

multiUserT = localBuildMultiUserSummaryTable(dlRaw, ulRaw, cfg, details, tti_s);
sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir, "multiuser_user_summary.csv"), multiUserT);

rawTrials = struct( ...
    "DL", dlRaw, ...
    "UL", ulRaw, ...
    "PBCH", table(), ...
    "PRACH", table(), ...
    "PDCCH", controlPDCCHT, ...
    "PUCCH", controlPUCCHT, ...
    "SRS", table(), ...
    "TRS", table(), ...
    "MultiUserDL", table(), ...
    "MultiUserUL", table());

energyArtifacts = sixgr.truth.exportLLSEnergyDiagnostics(cfg, fullfile(runFolder, "air_interface"), rawTrials);
iqImpairmentArtifacts = sixgr.truth.exportLLSRFImpairmentDiagnostics(cfg, fullfile(runFolder, "air_interface"), rawTrials);

runtimeT = localBuildRuntimeOperatingModeTable(cfg, scfg, details, rawTrials);
layoutT = localBuildDeploymentLayoutReferenceTable(cfg, scfg, details);
scaleProfileT = localBuildSystemWaveformScaleProfileTable(cfg, scfg, details, systemOut, dlRaw, ulRaw, dlGrantT, ulGrantT);
runtimeProfileT = localBuildSystemWaveformRuntimeProfileTable(cfg, scfg, details, systemOut, dlRaw, ulRaw, dlGrantT, ulGrantT);
cqiT = localBuildCQITableReferenceTable(cfg);
mcsT = localBuildMCSTableReferenceTable(cfg);
controlSummaryT = localBuildControlGatingSummaryTable(cfg, dlRaw, ulRaw);
controlStateT = localEmptyControlGatingStateTable();
stageT = localBuildStageStatusTable(cfg, systemOut, dlRaw, ulRaw, dlGrantT, ulGrantT, slotsPerFrame);
rsrpTraceT = localBuildServingRSRPTraceTable(details, cfg, slotsPerFrame, tti_s);

sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "runtime_operating_mode.csv"), runtimeT);
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "deployment_layout_reference.csv"), layoutT);
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "system_waveform_scale_profile.csv"), scaleProfileT);
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "system_waveform_runtime_profile.csv"), runtimeProfileT);
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "cqi_table_reference.csv"), cqiT);
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "mcs_table_reference.csv"), mcsT);
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "live_control_gating_summary.csv"), controlSummaryT);
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "live_control_gating_state.csv"), controlStateT);
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "live_stage_status.csv"), stageT);
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "live_rsrp_serving_trace.csv"), rsrpTraceT);

signalChain = sixgr.truth.exportLLSLiveSignalChainTables(runFolder, localVertcatTables(dlRaw, ulRaw), table(), struct());
derived = sixgr.truth.exportLLSLiveDerivedTables(cfg, runFolder, rawTrials, localConfiguredMultiUserContext(cfg, scfg), struct(), struct());

out = struct();
out.RawTrials = rawTrials;
out.DLGrantTable = dlGrantT;
out.ULGrantTable = ulGrantT;
out.MultiUserSummaryTable = multiUserT;
out.RuntimeOperatingModeTable = runtimeT;
out.DeploymentLayoutReferenceTable = layoutT;
out.SystemWaveformScaleProfileTable = scaleProfileT;
out.SystemWaveformRuntimeProfileTable = runtimeProfileT;
out.ControlGatingSummaryTable = controlSummaryT;
out.ControlGatingStateTable = controlStateT;
out.StageStatusTable = stageT;
out.ServingRSRPTraceTable = rsrpTraceT;
out.EnergyArtifacts = energyArtifacts;
out.IQImpairmentArtifacts = iqImpairmentArtifacts;
out.SignalChainArtifacts = signalChain;
out.DerivedArtifacts = derived;
end

function T = localBuildDirectionalGrantTable(grantT, direction, cfg, details, tti_s, slotsPerFrame)
grantT = localFilterDirection(grantT, direction);
if isempty(grantT)
    T = localEmptySchedulerGrantTable();
    return;
end

n = height(grantT);
dirToken = repmat(string(direction), n, 1);
tti = localNumericColumn(grantT, "TTI", NaN);
ueIdx = localNumericColumn(grantT, "UE", NaN);
cellId = localNumericColumn(grantT, "CellID", NaN);
[frameIdx, slotIdx] = localFrameSlotFromTTI(tti, slotsPerFrame);
cfgMode = localConfiguredLinkMode(cfg);
schedulerMode = localConfiguredSchedulerGrantMode(cfg);
schedulerModeColumn = localStringColumn(grantT, "AMCMode", schedulerMode);
mcsSelectionSourceColumn = localStringColumn(grantT, "MCSSelectionSource", "");
mcsSelectionSourceMissing = strlength(strtrim(mcsSelectionSourceColumn)) == 0;
mcsSelectionSourceFallback = localMCSSelectionSourceFromMode(schedulerModeColumn);
mcsSelectionSourceColumn(mcsSelectionSourceMissing) = mcsSelectionSourceFallback(mcsSelectionSourceMissing);
mcsValueStatusColumn = localStringColumn(grantT, "MCSValueStatus", "");
mcsValueStatusMissing = strlength(strtrim(mcsValueStatusColumn)) == 0;
mcsValueStatusFallback = localMCSValueStatusFromMode(schedulerModeColumn);
mcsValueStatusColumn(mcsValueStatusMissing) = mcsValueStatusFallback(mcsValueStatusMissing);
requestedSource = localRequestedOperatingPointSource(cfgMode);
interferenceMode = localConfiguredInterferenceMode(cfg);
status = repmat("FAIL", n, 1);
ack = localLogicalColumn(grantT, "Ack", false);
status(ack) = "PASS";
phyDecisionStatus = localStringColumn(grantT, "PHYDecisionStatus", "");
status(upper(strtrim(phyDecisionStatus)) == "NOT_AVAILABLE") = "NOT_AVAILABLE";

[modulation, targetCodeRate] = localGrantOperatingPointColumns(cfg, direction, ...
    localNumericColumn(grantT, "MCSIndex", NaN), localNumericColumn(grantT, "TargetCodeRate", NaN));

T = table( ...
    dirToken, tti, localNumericColumn(grantT, "Time_s", NaN), ...
    frameIdx, slotIdx, cellId, cellId, ueIdx, ueIdx, ueIdx, ...
    localStringColumn(grantT, "SlotDirection", ""), ...
    localNumericColumn(grantT, "PRBStart", NaN), localNumericColumn(grantT, "PRBCount", NaN), ...
    localNumericColumn(grantT, "SymbolStart", NaN), localNumericColumn(grantT, "NumSymbols", NaN), ...
    localNumericColumn(grantT, "TBSBits", NaN), localNumericColumn(grantT, "TBSBits", NaN) ./ 8, ...
    localNumericColumn(grantT, "CQIUsed", NaN), localNumericColumn(grantT, "MCSIndex", NaN), ...
    modulation, localNumericColumn(grantT, "NumLayers", NaN), targetCodeRate, ...
    localNumericColumn(grantT, "SINR_dB", NaN), localNumericColumn(grantT, "BLER", NaN), ...
    ack, localNumericColumn(grantT, "HarqID", NaN), localNumericColumn(grantT, "RV", NaN), localNumericColumn(grantT, "NDI", NaN), ...
    localLogicalColumn(grantT, "IsRetransmission", false), localStringColumn(grantT, "GrantReason", ""), ...
    localNumericColumn(grantT, "HeadOfLineDelay_ms", NaN), localNumericColumn(grantT, "BufferBytesBefore", NaN), localNumericColumn(grantT, "BufferBytesAfter", NaN), ...
    localSyntheticGrantId(direction, tti, cellId, ueIdx), repmat(cfgMode, n, 1), schedulerModeColumn, ...
    mcsSelectionSourceColumn, mcsValueStatusColumn, repmat(requestedSource, n, 1), repmat("scheduler_grant", n, 1), repmat("scheduler_grant", n, 1), ...
    repmat(interferenceMode, n, 1), status, ...
    localStringColumn(grantT, "PHYDecisionRole", ""), phyDecisionStatus, ...
    localStringColumn(grantT, "PHYDecisionSource", ""), localStringColumn(grantT, "PHYDecisionReason", ""), ...
    localLogicalColumn(grantT, "WaveformReplayExecuted", true), localLogicalColumn(grantT, "WaveformReplayReused", false), ...
    localStringColumn(grantT, "WaveformReplayKey", ""), ...
    'VariableNames', {'Direction','TTI','Time_s','Frame','Slot','CellID','BaseStationID','UE','UEID','RNTI', ...
    'SlotDirection','PRBStart','PRBCount','SymbolStart','NumSymbols','TBSBits','TBSBytes','CQIUsed','MCSIndex','Modulation', ...
    'NumLayers','TargetCodeRate','SINR_dB','BLER','Ack','HarqID','RV','NDI','IsRetransmission','GrantReason', ...
    'HeadOfLineDelay_ms','BufferBytesBefore','BufferBytesAfter','GrantContextId','LinkAdaptationMode', ...
    'SchedulerGrantMCSSelectionMode','MCSSelectionSource','MCSValueStatus','RequestedOperatingPointSource','AppliedOperatingPointSource','ActualMCSSelectionMode', ...
    'InterferenceMode','Status','PHYDecisionRole','PHYDecisionStatus','PHYDecisionSource','PHYDecisionReason', ...
    'WaveformReplayExecuted','WaveformReplayReused','WaveformReplayKey'});
T = localAppendSystemGrantReplayEvidence(T, grantT);
end

function T = localBuildDirectionalRawTrialTable(grantT, direction, scfg, cfg, details, tti_s, slotsPerFrame)
if isempty(grantT)
    T = localEmptyRawTrialTable();
    return;
end

n = height(grantT);
tti = localNumericColumn(grantT, "TTI", NaN);
ue = localNumericColumn(grantT, "UEID", NaN);
slotsPerFrame = max(1, round(double(slotsPerFrame)));
cfgMode = localConfiguredLinkMode(cfg);
configuredPolicy = localConfiguredMCSSelectionPolicy(cfg);
requestedSource = localRequestedOperatingPointSource(cfgMode);
interferenceMode = localConfiguredInterferenceMode(cfg);
phyProfile = localSystemPHYTruthProfile(cfg, details);
ttiCount = max([size(double(sixgr.util.structGet(details, "ServingCell", [])), 1), max(tti, [], "omitnan"), 1]);
runDuration_s = max(ttiCount * tti_s, eps);
warmupMask = ((tti - 1) .* tti_s .* 1e3) < double(sixgr.util.structGet(cfg, "run.warmupTime_ms", 0));

sinrSource = "system_level_desired_interference_noise_budget";
largeScaleSource = "system_level_large_scale_state_cache_plus_interference_budget";
directionSINR = localDirectionalMetric(details, direction, "SINR_dB", "SINR_UL_dB", tti, ue);
rsrp = localDirectionalMetric(details, direction, "RSRP_dBm", "RSRP_dBm", tti, ue);
pathloss = localDirectionalMetric(details, direction, "Pathloss_dB", "Pathloss_dB", tti, ue);
servingDistance = localDirectionalMetric(details, direction, "ServingDistance_m", "ServingDistance_m", tti, ue);
servingBeam = localDirectionalMetric(details, direction, "ServingBeamIndex", "ServingBeamIndex", tti, ue);
servingBeamGain = localDirectionalMetric(details, direction, "ServingBeamGain_dB", "ServingBeamGain_dB", tti, ue);
interfPower = localDirectionalMetric(details, direction, "InterferencePowerDL_dBm", "InterferencePowerUL_dBm", tti, ue);
noisePower = localDirectionalMetric(details, direction, "NoiseDL_dBm", "NoiseUL_dBm", tti, ue);
interfCount = localDirectionalMetric(details, direction, "ActiveInterfererCountDL", "ActiveInterfererCountUL", tti, ue);

widebandCQI = localNumericColumn(grantT, "CQIUsed", NaN);
[cqiDerivedMcs, cqiDerivedMod, cqiDerivedRate] = localCQIDerivedOperatingPoint(cfg, direction, widebandCQI);

goodputMbps = zeros(n, 1);
ack = localLogicalColumn(grantT, "Ack", false);
tbsBits = localNumericColumn(grantT, "TBSBits", NaN);
goodputMbps(ack & isfinite(tbsBits)) = double(tbsBits(ack & isfinite(tbsBits))) ./ runDuration_s ./ 1e6;

T = table();
T.Direction = repmat(string(direction), n, 1);
T.SFN = localNumericColumn(grantT, "Frame", NaN);
T.Frame = localNumericColumn(grantT, "Frame", NaN);
T.Slot = localNumericColumn(grantT, "Slot", NaN);
T.Time_s = localNumericColumn(grantT, "Time_s", NaN);
T.UEID = localNumericColumn(grantT, "UEID", NaN);
T.UEIndex = localNumericColumn(grantT, "UEID", NaN);
T.RNTI = localNumericColumn(grantT, "RNTI", NaN);
T.BaseStationID = localNumericColumn(grantT, "BaseStationID", NaN);
T.CellID = localNumericColumn(grantT, "CellID", NaN);
T.GrantContextId = localStringColumn(grantT, "GrantContextId", "");
T.AllocatedPRBCount = localNumericColumn(grantT, "PRBCount", NaN);
T.PRBStart = localNumericColumn(grantT, "PRBStart", NaN);
T.SymbolStart = localNumericColumn(grantT, "SymbolStart", NaN);
T.NumSymbols = localNumericColumn(grantT, "NumSymbols", NaN);
T.TBSize_bits = tbsBits;
T.TBSBits = tbsBits;
T.BitErrors = localNumericColumn(grantT, "BitErrors", NaN);
T.BitsCompared = localNumericColumn(grantT, "BitsCompared", NaN);
T.RawBER = localNumericColumn(grantT, "RawBER", NaN);
T.CRCPass = double(ack);
T.Crash = false(n, 1);
T.Goodput_Mbps = goodputMbps;
T.Status = localStringColumn(grantT, "Status", "");
T.PHYDecisionRole = localStringColumn(grantT, "PHYDecisionRole", "");
T.PHYDecisionStatus = localStringColumn(grantT, "PHYDecisionStatus", "");
T.PHYDecisionSource = localStringColumn(grantT, "PHYDecisionSource", "");
T.PHYDecisionReason = localStringColumn(grantT, "PHYDecisionReason", "");
T.WaveformReplayExecuted = localLogicalColumn(grantT, "WaveformReplayExecuted", true);
T.WaveformReplayReused = localLogicalColumn(grantT, "WaveformReplayReused", false);
T.WaveformReplayKey = localStringColumn(grantT, "WaveformReplayKey", "");
T.BLER = localNumericColumn(grantT, "BLER", NaN);
T.MCS = localNumericColumn(grantT, "MCSIndex", NaN);
T.MCSIndex = localNumericColumn(grantT, "MCSIndex", NaN);
T.Modulation = localStringColumn(grantT, "Modulation", "");
T.TargetCodeRate = localNumericColumn(grantT, "TargetCodeRate", NaN);
layerValues = localNumericColumn(grantT, "NumLayers", NaN);
rankValues = localNumericColumn(grantT, "RIUsed", NaN);
rankMissing = ~isfinite(rankValues);
rankValues(rankMissing) = layerValues(rankMissing);
T.Layers = layerValues;
T.RankIndicator = rankValues;
T.WidebandCQI = widebandCQI;
T.CQIDerivedMCS = cqiDerivedMcs;
T.CQIDerivedModulation = cqiDerivedMod;
T.CQIDerivedTargetCodeRate = cqiDerivedRate;
T.LinkAdaptationMode = repmat(cfgMode, n, 1);
T.ConfiguredLinkAdaptationMode = repmat(cfgMode, n, 1);
T.ConfiguredMCSSelectionPolicy = repmat(configuredPolicy, n, 1);
T.SchedulerGrantMCSSelectionMode = localStringColumn(grantT, "AMCMode", localConfiguredSchedulerGrantMode(cfg));
T.MCSSelectionSource = localStringColumn(grantT, "MCSSelectionSource", "");
missingMCSSelectionSource = strlength(strtrim(T.MCSSelectionSource)) == 0;
fallbackMCSSelectionSource = localMCSSelectionSourceFromMode(T.SchedulerGrantMCSSelectionMode);
T.MCSSelectionSource(missingMCSSelectionSource) = fallbackMCSSelectionSource(missingMCSSelectionSource);
T.MCSValueStatus = localStringColumn(grantT, "MCSValueStatus", "");
missingMCSValueStatus = strlength(strtrim(T.MCSValueStatus)) == 0;
fallbackMCSValueStatus = localMCSValueStatusFromMode(T.SchedulerGrantMCSSelectionMode);
T.MCSValueStatus(missingMCSValueStatus) = fallbackMCSValueStatus(missingMCSValueStatus);
T.RequestedOperatingPointSource = repmat(requestedSource, n, 1);
T.AppliedOperatingPointSource = repmat("scheduler_grant", n, 1);
T.ActualMCSSelectionMode = repmat("scheduler_grant", n, 1);
T.ActualMCSSelectionModeAuthority = repmat("raw_trial_runtime_evidence", n, 1);
T.MCSAuthority = repmat("scheduler_grant", n, 1);
T.ModulationAuthority = repmat("scheduler_grant", n, 1);
T.GrantOperatingPointSource = repmat("scheduler_grant", n, 1);
T.ConfiguredSNR_dB = repmat(double(sixgr.util.structGet(cfg, "channel.snr_dB", NaN)), n, 1);
T.ConfiguredSNRSource = repmat("simulation.snr_db", n, 1);
T.SNRValueRole = repmat("applied", n, 1);
T.AppliedAWGNSNR_dB = nan(n, 1);
if phyProfile.AppliedAWGNSNRAvailable
    T.AppliedAWGNSNR_dB = directionSINR;
end
T.SNR_dB = directionSINR;
T.AppliedAWGNSNRSource = repmat(phyProfile.AppliedAWGNSNRSource, n, 1);
T.SystemLevelSINR_dB = directionSINR;
T.SystemLevelSINRSource = repmat(sinrSource, n, 1);
T.SystemLevelSINRValueRole = repmat("runtime_state_derived", n, 1);
T.SystemLevelSINRValueStatus = repmat("available_system_level_estimate", n, 1);
T.SystemLevelSINRDefinition = repmat("desired_signal_power_over_interference_plus_noise_budget_not_receiver_hest_or_decoder_truth", n, 1);
T.ReceiverHestSINR_dB = localNumericColumn(grantT, "ReceiverHestSINR_dB", NaN);
T.ReceiverHestSINRSource = localStringColumn(grantT, "ReceiverHestSINRSource", "unavailable_system_level_no_receiver_hest_grid");
T.ReceiverHestSINRValueRole = localStringColumn(grantT, "ReceiverHestSINRValueRole", "unavailable");
T.ReceiverHestSINRValueStatus = localStringColumn(grantT, "ReceiverHestSINRValueStatus", "unavailable");
T.ReceiverHestSINRNAReason = localStringColumn(grantT, "ReceiverHestSINRNAReason", "system_level_adapter_does_not_export_receiver_hest_or_csi_grid");
T.PostEqSINR_dB = localNumericColumn(grantT, "PostEqSINR_dB", NaN);
T.PostEqSINRSource = localStringColumn(grantT, "PostEqSINRSource", "unavailable_system_level_no_post_equalizer_measurement");
T.PostEqSINRValueRole = localStringColumn(grantT, "PostEqSINRValueRole", "unavailable");
T.PostEqSINRValueStatus = localStringColumn(grantT, "PostEqSINRValueStatus", "unavailable");
T.PostEqSINRNAReason = localStringColumn(grantT, "PostEqSINRNAReason", "system_level_adapter_does_not_export_post_equalizer_measurement");
T.PostEqSINRPerLayer_dB = localStringColumn(grantT, "PostEqSINRPerLayer_dB", "");
T.DecoderTruthProxySINR_dB = localNumericColumn(grantT, "DecoderTruthProxySINR_dB", NaN);
T.DecoderTruthProxySINRSource = localStringColumn(grantT, "DecoderTruthProxySINRSource", "unavailable_system_level_no_decoder_truth_proxy");
T.DecoderTruthProxySINRValueRole = localStringColumn(grantT, "DecoderTruthProxySINRValueRole", "unavailable");
T.DecoderTruthProxySINRValueStatus = localStringColumn(grantT, "DecoderTruthProxySINRValueStatus", "unavailable");
T.DecoderTruthProxySINRNAReason = localStringColumn(grantT, "DecoderTruthProxySINRNAReason", "system_level_sinr_budget_is_not_decoder_truth_proxy");
T = localQuarantineDecoderTruthProxy(T);
T.SINRValueRole = repmat("runtime_state_derived", n, 1);
T.SINRSource = repmat(sinrSource, n, 1);
T.SINRValueStatus = repmat("available_system_level_estimate", n, 1);
T.SINRValueDefinition = repmat("system_level_desired_over_interference_plus_noise_budget", n, 1);
T.MeasuredTrialSINR_dB = nan(n, 1);
T.MeasuredTrialSINRSource = repmat("deprecated_unavailable_in_system_level_lls", n, 1);
T.MeasuredTrialSINRValueRole = repmat("deprecated_unavailable", n, 1);
T.MeasuredTrialSINRValueStatus = repmat("unavailable", n, 1);
T.MeasuredTrialSINRNAReason = repmat("measured_trial_sinr_not_exported_for_system_level_adapter", n, 1);
postEqUsable = isfinite(double(T.PostEqSINR_dB)) & ...
    sixgr.util.isAcceptableSINRStatus(T.PostEqSINRValueStatus) & ...
    contains(lower(string(T.PostEqSINRSource)), "post_equalization");
T.MeasuredTrialSINR_dB(postEqUsable) = double(T.PostEqSINR_dB(postEqUsable));
T.MeasuredTrialSINRSource(postEqUsable) = string(T.PostEqSINRSource(postEqUsable));
T.MeasuredTrialSINRValueRole(postEqUsable) = string(T.PostEqSINRValueRole(postEqUsable));
T.MeasuredTrialSINRValueStatus(postEqUsable) = "OK";
T.MeasuredTrialSINRNAReason(postEqUsable) = "";
T.LargeScaleSINR_dB = directionSINR;
T.LargeScaleSINRSource = repmat(largeScaleSource, n, 1);
T.LargeScaleSINRValueRole = repmat("runtime_state_derived", n, 1);
T.ChannelModel = repmat(string(localResolvedChannelToken(cfg)), n, 1);
T.DopplerHz = repmat(double(sixgr.util.structGet(cfg, "channel.doppler_Hz", NaN)), n, 1);
T.DopplerSourceMode = repmat(string(sixgr.util.structGet(cfg, "channel.dopplerSourceMode", "")), n, 1);
T.DopplerValueRole = repmat("derived", n, 1);
T.InterferenceMode = repmat(interferenceMode, n, 1);
T.InterferenceContributorCount = interfCount;
T.InterferenceAggregatedRxPower_dBm = interfPower;
T.InterferencePowerSource = repmat("system_level_active_interferer_power_sum", n, 1);
T.FullInterfererChannelTruthUsed = repmat(localConfiguredInterferenceMode(cfg) == "full_per_link_channel_waveform_sum", n, 1);
T.NoiseVariance = localNoiseVarianceFromdBm(noisePower);
T.ServingRSRP_dBm = rsrp;
T.ServingRSRPSource = repmat("system_level_serving_cell_trace", n, 1);
T.CSI_RSRP_dB = rsrp;
T.CSI_RSRPSource = repmat("system_level_serving_cell_trace", n, 1);
T.AppliedLargeScaleGain_dB = -pathloss;
T.AppliedLargeScaleGainSource = repmat("system_level_pathloss_and_beam_gain_state", n, 1);
T.ChannelGain_dB = -pathloss;
T.PropagationDistance_m = servingDistance;
T.SelectedBeamIndex = servingBeam;
T.BestBeamIndex = servingBeam;
T.BeamHit = double(isfinite(servingBeam));
T.TopKBeamHit = double(isfinite(servingBeam));
T.BeamCandidateCount = repmat(double(sixgr.util.structGet(cfg, "system.beam.numBeams", sixgr.util.structGet(cfg, "phy.ssb.nBeams", 8))), n, 1);
T.SelectedBeamGain_dB = servingBeamGain;
T.BestBeamGain_dB = servingBeamGain;
T.BeamGainGap_dB = zeros(n, 1);
T.ConfiguredBeamSelectionStrategy = repmat(string(sixgr.util.structGet(scfg.toStruct(), "users.beam_selection_strategy", "")), n, 1);
T.BeamSelectionStrategy = repmat("runtime_best_beam_per_link", n, 1);
T.BeamSelectionAuthority = repmat("system_level_beam_selection_state", n, 1);
T.BeamSelectionPolicyType = repmat("runtime_best_beam_per_link", n, 1);
T.BeamSelectionPolicyFixed = false(n, 1);
T.SelectedBeamValueRole = repmat("runtime_state_derived", n, 1);
T.SelectedBeamValueStatus = repmat("available", n, 1);
T.SelectedBeamNAReason = repmat("", n, 1);
T.SelectedBeamValueStatus(~isfinite(servingBeam)) = "unavailable";
T.SelectedBeamNAReason(~isfinite(servingBeam)) = "system_level_beam_selection_state_missing_for_grant";
T.RequestedBeamIndexSet = repmat("", n, 1);
T.RequestedBeamValueRole = repmat("unavailable", n, 1);
T.RequestedBeamValueStatus = repmat("not_requested_separate_from_runtime_selection", n, 1);
T.RequestedBeamNAReason = repmat("system_level_scheduler_uses_runtime_best_beam_state_not_a_separate_requested_beam_set", n, 1);
T.PrecoderSource = localStringColumn(grantT, "PrecoderSource", "system_level_beam_state_reference");
T.RequestedPrecoderSource = localStringColumn(grantT, "RequestedPrecoderSource", "system_level_beam_state_reference");
T.AppliedPrecoderSource = localStringColumn(grantT, "AppliedPrecoderSource", "not_materialized_in_system_level_lls");
T.RequestedPrecoderPMI = localNumericColumn(grantT, "RequestedPrecoderPMI", NaN);
T.PrecodingMode = localStringColumn(grantT, "PrecodingMode", "system_level_codebook_reference_no_explicit_replay_matrix");
T.PrecodingApplicationStage = localStringColumn(grantT, "PrecodingApplicationStage", "scheduler_link_state_only");
T.PrecodingActive = localLogicalColumn(grantT, "PrecodingActive", false);
T.ExplicitBeamWeightsApplied = localLogicalColumn(grantT, "ExplicitBeamWeightsApplied", false);
T.TransformPrecodingApplied = localLogicalColumn(grantT, "TransformPrecodingApplied", localConfiguredTransformPrecoding(cfg));
T.BeamformingApplied = localLogicalColumn(grantT, "BeamformingApplied", false);
T.AppliedBeamIndexSet = localStringColumn(grantT, "AppliedBeamIndexSet", "");
T.AppliedPrecoderPMI = localNumericColumn(grantT, "AppliedPrecoderPMI", NaN);
T.AppliedBeamValueRole = repmat("unavailable", n, 1);
T.AppliedBeamValueStatus = repmat("not_materialized_as_explicit_waveform_weight_application", n, 1);
T.AppliedBeamNAReason = repmat("system_level_waveform_replay_uses_scheduler_beam_state_for_link_budget_not_explicit_beam_weights", n, 1);
T.AppliedPrecoderValueRole = localStringColumn(grantT, "AppliedPrecoderValueRole", "unavailable");
T.AppliedPrecoderValueStatus = localStringColumn(grantT, "AppliedPrecoderValueStatus", "not_materialized");
T.AppliedPrecoderNAReason = localStringColumn(grantT, "AppliedPrecoderNAReason", "system_level_grant_replay_does_not_materialize_precoder_matrix_or_pmi");
T.ExplicitPrecoderReplayStatus = localStringColumn(grantT, "ExplicitPrecoderReplayStatus", "not_materialized");
T.ExplicitPrecoderReplayBlocker = localStringColumn(grantT, "ExplicitPrecoderReplayBlocker", "sixgr.system.WaveformPHY.replayGrant_receives_grant_operating_point_not_explicit_precoder_matrix");
T.AppliedPrecoderPMIType = localStringColumn(grantT, "AppliedPrecoderPMIType", "");
T.AppliedPrecoderCodebookMode = localStringColumn(grantT, "AppliedPrecoderCodebookMode", "");
T.PrecodingNumPorts = localNumericColumn(grantT, "PrecodingNumPorts", NaN);
T.PrecodingNumLayers = localNumericColumn(grantT, "PrecodingNumLayers", NaN);
T.PrecodingMatrixRows = localNumericColumn(grantT, "PrecodingMatrixRows", NaN);
T.PrecodingMatrixCols = localNumericColumn(grantT, "PrecodingMatrixCols", NaN);
T.GrantControlState = repmat(phyProfile.GrantControlState, n, 1);
T.DecoderIterations = localNumericColumn(grantT, "DecoderIterations", NaN);
T = localAttachMeasuredPHYEvidenceColumnsFromGrant(T, grantT);
T.ChannelEstimateAvailable = localLogicalColumn(grantT, "ChannelEstimateAvailable", false);
T.EqualizationAvailable = localLogicalColumn(grantT, "EqualizationAvailable", false);
T.DecodeAttempted = localLogicalColumn(grantT, "DecodeAttempted", false);
T.DecodeAvailable = localLogicalColumn(grantT, "DecodeAvailable", false);
T.LLRAvailable = localLogicalColumn(grantT, "LLRAvailable", false);
T.LLRFinite = localLogicalColumn(grantT, "LLRFinite", false);
T.DLSCHDecodeAvailable = false(n, 1);
T.ULSCHDecodeAvailable = false(n, 1);
if upper(string(direction)) == "DL"
    T.DLSCHDecodeAvailable = T.DecodeAvailable;
else
    T.ULSCHDecodeAvailable = T.DecodeAvailable;
end
T.ChannelEstimateAttempted = T.ChannelEstimateAvailable;
T.EqualizationAttempted = T.EqualizationAvailable;
T.TimingEstimateUsed = localLogicalColumn(grantT, "TimingEstimateUsed", false);
T.UseIdealTimingSync = repmat(logical(sixgr.util.structGet(cfg, "phy.rx.useIdealTimingSync", false)), n, 1);
T.RawTimingEstimate_samples = localNumericColumn(grantT, "RawTimingEstimate_samples", NaN);
T.AppliedTimingCorrection_samples = localNumericColumn(grantT, "AppliedTimingCorrection_samples", NaN);
T.TimingEstimateApplicationPolicy = localStringColumn(grantT, "TimingEstimateApplicationPolicy", "");
T.TimingEstimateStatus = localStringColumn(grantT, "TimingEstimateStatus", "");
T.TimingEstimateWasClipped = localLogicalColumn(grantT, "TimingEstimateWasClipped", false);
T.TimingEstimateAvailability = localStringColumn(grantT, "TimingEstimateAvailability", localTimingAvailabilityFromFlag(T.TimingEstimateUsed));
T.TimingErrorDefinition = localStringColumn(grantT, "TimingErrorDefinition", localTimingErrorDefinitionFromFlag(T.TimingEstimateUsed));
T.TimingValueStatus = localStringColumn(grantT, "TimingValueStatus", repmat("NOT_AVAILABLE", n, 1));
T.InjectedTimingOffset_samples = localNumericColumn(grantT, "InjectedTimingOffset_samples", NaN);
T.TrueTimingOffset_samples = localNumericColumn(grantT, "TrueTimingOffset_samples", T.InjectedTimingOffset_samples);
T.EstimatedTimingOffset_PreCorrection_samples = localNumericColumn(grantT, "EstimatedTimingOffset_PreCorrection_samples", T.RawTimingEstimate_samples);
T.TimingError_samples = localNumericColumn(grantT, "TimingError_samples", NaN);
T.EstimatedCFO_Hz = localNumericColumn(grantT, "EstimatedCFO_Hz", NaN);
T.InjectedCFO_Hz = localNumericColumn(grantT, "InjectedCFO_Hz", NaN);
T.TrueCFO_Hz = localNumericColumn(grantT, "TrueCFO_Hz", T.InjectedCFO_Hz);
T.EstimatedCFO_PreCorrection_Hz = localNumericColumn(grantT, "EstimatedCFO_PreCorrection_Hz", T.EstimatedCFO_Hz);
T.ResidualCFO_PostCorrection_Hz = localNumericColumn(grantT, "ResidualCFO_PostCorrection_Hz", NaN);
T.CFOError_Hz = localNumericColumn(grantT, "CFOError_Hz", NaN);
T.CFOEstimateAvailable = localLogicalColumn(grantT, "CFOEstimateAvailable", false);
T.CFOEstimateAvailability = localStringColumn(grantT, "CFOEstimateAvailability", localCFOAvailabilityFromEstimate(T.EstimatedCFO_Hz));
T.ReceiverTrackingCorrectionSource = localStringColumn(grantT, "ReceiverTrackingCorrectionSource", "");
T.ReceiverTrackingCorrectionStatus = localStringColumn(grantT, "ReceiverTrackingCorrectionStatus", "");
T.ReceiverTrackingCorrectionNAReason = localStringColumn(grantT, "ReceiverTrackingCorrectionNAReason", "");
T.CFOErrorDefinition = localStringColumn(grantT, "CFOErrorDefinition", localCFOErrorDefinitionFromEstimate(T.EstimatedCFO_Hz));
T.CFOValueStatus = localStringColumn(grantT, "CFOValueStatus", localValueStatusFromFinite(T.EstimatedCFO_Hz));
T.AppliedPathloss_dB = localNumericColumn(grantT, "AppliedPathloss_dB", NaN);
T.AppliedShadowFading_dB = localNumericColumn(grantT, "AppliedShadowFading_dB", NaN);
T.AppliedLargeScaleGain_dB = localNumericColumn(grantT, "AppliedLargeScaleGain_dB", NaN);
T.AppliedO2I_dB = localNumericColumn(grantT, "AppliedO2I_dB", NaN);
T.ServingRxPower_dBm = localNumericColumn(grantT, "ServingRxPower_dBm", NaN);
T.ThermalNoisePower_dBm = localNumericColumn(grantT, "ThermalNoisePower_dBm", NaN);
T.NoisePowerSource = localStringColumn(grantT, "NoisePowerSource", "");
T.PhaseNoiseConfigured = localLogicalColumn(grantT, "PhaseNoiseConfigured", false);
T.PhaseNoiseApplied = localLogicalColumn(grantT, "PhaseNoiseApplied", false);
T.PhaseNoiseRMS_rad = localNumericColumn(grantT, "PhaseNoiseRMS_rad", NaN);
T.IQImbalanceConfigured = localLogicalColumn(grantT, "IQImbalanceConfigured", false);
T.IQImbalanceApplied = localLogicalColumn(grantT, "IQImbalanceApplied", false);
T.IQImbalanceImageRejection_dB = localNumericColumn(grantT, "IQImbalanceImageRejection_dB", NaN);
T.IQImbalanceMeasurementStatus = localStringColumn(grantT, "IQImbalanceMeasurementStatus", "");
T.BSAntennaArrayType = repmat(string(sixgr.util.structGet(scfg.toStruct(), "antenna_and_array.bs_array_geometry", "")), n, 1);
T.UEAntennaArrayType = repmat(string(sixgr.util.structGet(scfg.toStruct(), "antenna_and_array.ue_array_geometry", "")), n, 1);
T.BSAntennaElements = repmat(double(sixgr.util.structGet(scfg.toStruct(), "antenna_and_array.bs_num_antenna_elements", NaN)), n, 1);
T.UEAntennaElements = repmat(double(sixgr.util.structGet(scfg.toStruct(), "antenna_and_array.ue_num_antenna_elements", NaN)), n, 1);
T.BSAntennaSpacingH_lambda = repmat(double(sixgr.util.structGet(scfg.toStruct(), "antenna_and_array.element_spacing_h", NaN)), n, 1);
T.BSAntennaSpacingV_lambda = repmat(double(sixgr.util.structGet(scfg.toStruct(), "antenna_and_array.element_spacing_v", NaN)), n, 1);
T.BSAntennaPolarization = repmat(string(sixgr.util.structGet(scfg.toStruct(), "antenna_and_array.polarization", "")), n, 1);
T.RuntimeAntennaObjectSource = repmat("not_materialized_explicit_array_object_in_system_level_lls", n, 1);
T.AntennaRuntimeObjectCreated = false(n, 1);
T.AntennaRuntimeObjectValueRole = repmat("unavailable", n, 1);
T.AntennaRuntimeObjectValueStatus = repmat("not_materialized", n, 1);
T.AntennaRuntimeObjectNAReason = repmat("system_level_lls_uses_configured_mimo_dimensions_not_runtime_phased_array_objects", n, 1);
T.ChannelArrayModel = repmat(phyProfile.ChannelArrayModel, n, 1);
T.ChannelObjectSource = repmat(phyProfile.ChannelObjectSource, n, 1);
T.ChannelObjectClass = repmat(phyProfile.ChannelObjectClass, n, 1);
T.ChannelArrayHandlingStatus = repmat(phyProfile.ChannelArrayHandlingStatus, n, 1);
T.ChannelArrayHandlingBlocker = repmat(phyProfile.ChannelArrayHandlingBlocker, n, 1);
T.ChannelArrayValueRole = repmat("system_level_approximation_label", n, 1);
T.ChannelArrayValueStatus = repmat("approximate_system_context", n, 1);
T.ChannelUsesCountOnlyAntennaModel = false(n, 1);
T.ChannelUsesSameRuntimeAntennaAssumptions = false(n, 1);
T.InterferenceChannelObjectSource = repmat(phyProfile.InterferenceChannelObjectSource, n, 1);
T.InterferenceChannelObjectClass = repmat(phyProfile.InterferenceChannelObjectClass, n, 1);
T.InterferenceChannelArrayHandlingStatus = repmat(phyProfile.InterferenceChannelArrayHandlingStatus, n, 1);
T.InterferenceChannelArrayHandlingBlocker = repmat(phyProfile.InterferenceChannelArrayHandlingBlocker, n, 1);
T.InterferenceChannelArrayValueRole = repmat("system_level_approximation_label", n, 1);
T.InterferenceChannelArrayValueStatus = repmat("large_scale_interference_budget_no_runtime_interferer_channel_object", n, 1);
T.InterferenceUsesSameRuntimeAntennaAssumptions = false(n, 1);
T.InterferencePathUsesSameArrayAssumptions = false(n, 1);
T.IsWarmupFrame = warmupMask;
T.RunTag = repmat(string(sixgr.util.structGet(cfg, "run.runTag", "")), n, 1);
T.ScenarioID = repmat(string(sixgr.util.structGet(cfg, "meta.scenarioID", "")), n, 1);
T.RunnerProfile = repmat("system_level_lls", n, 1);
T.ConfigHash = repmat(string(sixgr.util.structGet(cfg, "meta.configHash", "")), n, 1);
end

function T = localBuildMultiUserSummaryTable(dlRaw, ulRaw, cfg, details, tti_s)
userCount = max([ ...
    double(sixgr.util.structGet(cfg, "scenario.nUE", NaN)), ...
    double(sixgr.util.structGet(cfg, "scenario.ue.nUE", NaN)), ...
    1], [], "omitnan");
if ~(isfinite(userCount) && userCount >= 1)
    userCount = 1;
end
userList = (1:round(userCount)).';
rows = repmat(localEmptyMultiUserSummaryRow(), numel(userList) * 2, 1);
rowIdx = 0;
for direction = ["DL", "UL"]
    sourceT = dlRaw;
    if direction == "UL"
        sourceT = ulRaw;
    end
    for u = reshape(userList, 1, [])
        rowIdx = rowIdx + 1;
        ueMask = false(height(sourceT), 1);
        if ismember("UEIndex", string(sourceT.Properties.VariableNames))
            ueMask = abs(double(sourceT.UEIndex) - double(u)) < 1e-9;
        end
        Tu = sourceT(ueMask, :);
        sem = sixgr.truth.deriveUserSummarySemantics(Tu);
        throughputMbps = 0;
        if ~isempty(Tu)
            tbs = double(localOptionalTrialColumn(Tu, "TBSBits", NaN));
            ack = logical(localOptionalTrialColumn(Tu, "CRCPass", 0));
            throughputMbps = sum(tbs(ack), "omitnan") ./ max(double(max(localNumericColumn(Tu, "Time_s", NaN), [], "omitnan") + tti_s), eps) ./ 1e6;
        end
        rows(rowIdx).UEIndex = double(u);
        rows(rowIdx).RNTI = double(u);
        rows(rowIdx).Direction = char(direction);
        rows(rowIdx).ConfiguredLayers = double(sixgr.util.structGet(cfg, "phy.pdsch.nLayers", sixgr.util.structGet(cfg, "phy.pusch.nLayers", NaN)));
        rows(rowIdx).ConfiguredTxAntennas = double(sixgr.util.structGet(cfg, "phy.nTxAnt", NaN));
        rows(rowIdx).ConfiguredRxAntennas = double(sixgr.util.structGet(cfg, "phy.nRxAnt", NaN));
        rows(rowIdx).BeamformingApplied = false;
        rows(rowIdx).BeamSelectionStrategy = char(string(sixgr.util.structGet(cfg, "users.beam_selection_strategy", "runtime_best_beam_per_link")));
        rows(rowIdx).BeamIndexSet = "";
        rows(rowIdx).ExecutionModel = char(string(sixgr.util.structGet(cfg, "run.executionMode", "LLS")));
        rows(rowIdx).Throughput_Mbps = double(throughputMbps);
        rows(rowIdx).ObservedRowCount = double(sem.ObservedRowCount);
        rows(rowIdx).BLER = localSafeMean(localOptionalTrialColumn(Tu, "BLER", NaN));
        rows(rowIdx).BER = NaN;
        rows(rowIdx).PassRate = double(sem.PassRate);
        rows(rowIdx).MeanMeasuredSINR_dB = localSafeMean(localOptionalTrialColumn(Tu, "MeasuredTrialSINR_dB", NaN));
        rows(rowIdx).MeanChannelGain_dB = localSafeMean(localOptionalTrialColumn(Tu, "ChannelGain_dB", NaN));
        rows(rowIdx).SummaryRowValid = logical(sem.SummaryRowValid);
        rows(rowIdx).RuntimeDataPresent = logical(sem.RuntimeDataPresent);
        rows(rowIdx).UserHadAnySuccessfulTx = logical(sem.UserHadAnySuccessfulTx);
        rows(rowIdx).UserHadAnySuccessfulRx = logical(sem.UserHadAnySuccessfulRx);
        rows(rowIdx).PartialSuccess = logical(sem.PartialSuccess);
        rows(rowIdx).AllObservedRowsSuccessful = logical(sem.AllObservedRowsSuccessful);
        rows(rowIdx).SummaryStatus = char(string(sem.SummaryStatus));
        rows(rowIdx).Ok = logical(sem.Ok);
        rows(rowIdx).OkDefinition = char(string(sem.OkDefinition));
    end
end
T = struct2table(rows(1:rowIdx), "AsArray", true);
end

function T = localBuildRuntimeOperatingModeTable(cfg, scfg, details, rawTrials)
numerology = localCanonicalNumerology(cfg);
rows = repmat(struct( ...
    "Direction", "", ...
    "LinkAdaptationMode", "", ...
    "ConfiguredLinkAdaptationMode", "", ...
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
    "NoiseOperatingMode", "", ...
    "DopplerSourceMode", "", ...
    "ResolvedDopplerHz", NaN, ...
    "MobilitySpeed_kmh", NaN, ...
    "InterferenceMode", "", ...
    "FullInterfererChannelTruthUsed", false, ...
    "SystemLevelSINRSource", "", ...
    "SystemLevelSINRValueRole", "", ...
    "SystemLevelSINRValueStatus", "", ...
    "ReceiverHestSINRSource", "", ...
    "ReceiverHestSINRValueStatus", "", ...
    "DecoderTruthProxySINRSource", "", ...
    "DecoderTruthProxySINRValueStatus", "", ...
    "MeasuredTrialSINRSource", "", ...
    "MeasuredTrialSINRValueStatus", "", ...
    "ExplicitPrecoderReplayStatus", "", ...
    "ExplicitPrecoderReplayBlocker", "", ...
    "AntennaRuntimeObjectSource", "", ...
    "AntennaRuntimeObjectValueStatus", "", ...
    "ChannelArrayModel", "", ...
    "ChannelObjectSource", "", ...
    "ChannelObjectClass", "", ...
    "ChannelArrayHandlingStatus", "", ...
    "ChannelArrayHandlingBlocker", "", ...
    "ChannelArrayValueStatus", "", ...
    "ChannelUsesSameRuntimeAntennaAssumptions", false, ...
    "InterferenceChannelObjectSource", "", ...
    "InterferenceChannelObjectClass", "", ...
    "InterferenceChannelArrayHandlingStatus", "", ...
    "InterferenceChannelArrayHandlingBlocker", "", ...
    "InterferenceChannelArrayValueStatus", "", ...
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
    "ExecutionBackend", "", ...
    "PHYMode", "", ...
    "WaveformBacked", false, ...
    "WaveformPHYActive", false, ...
    "ProxyPHYActive", true, ...
    "FallbackUsed", true), 2, 1);

cfgMode = localConfiguredLinkMode(cfg);
cfgPolicy = localConfiguredMCSSelectionPolicy(cfg);
requestedSource = localRequestedOperatingPointSource(cfgMode);
interferenceMode = localConfiguredInterferenceMode(cfg);
parallelActive = logical(sixgr.util.structGet(cfg, "run.useParallel", false));
workerCount = double(sixgr.util.structGet(cfg, "run.numWorkers", NaN));
beamUpdate = double(sixgr.util.structGet(cfg, "system.beam.updatePeriod_slots", NaN));
measurementPeriod = double(sixgr.util.structGet(cfg, "system.measurement.periodSlots", NaN));
trafficModel = char(string(sixgr.util.structGet(details, "TrafficModel", "")));
trafficTransport = char(string(sixgr.util.structGet(details, "TrafficTransport", "")));
trafficFlowDirection = char(string(sixgr.util.structGet(details, "FlowDirection", "")));
trafficTargetRate = localResolvedTrafficTargetRate(scfg);
phyProfile = localSystemPHYTruthProfile(cfg, details);

for i = 1:2
    direction = "DL";
    if i == 2
        direction = "UL";
    end
    evidenceT = sixgr.util.structGet(rawTrials, char(direction), table());
    rows(i).Direction = char(direction);
    rows(i).LinkAdaptationMode = char(cfgMode);
    rows(i).ConfiguredLinkAdaptationMode = char(cfgMode);
    rows(i).DirectionPolicy = char(cfgMode);
    rows(i).ActualMCSSelectionMode = char(localDominantStringValue(evidenceT, "ActualMCSSelectionMode", "scheduler_grant"));
    rows(i).ConfiguredMCSSelectionPolicy = char(cfgPolicy);
    rows(i).ConfiguredMCSSelectionMode = char(cfgPolicy);
    rows(i).SchedulerGrantMCSSelectionMode = char(localDominantStringValue(evidenceT, "SchedulerGrantMCSSelectionMode", localConfiguredSchedulerGrantMode(cfg)));
    rows(i).RequestedOperatingPointSource = char(requestedSource);
    rows(i).AppliedOperatingPointSource = char(localDominantStringValue(evidenceT, "AppliedOperatingPointSource", "scheduler_grant"));
    rows(i).ActualMCSSelectionModeAuthority = "raw_trial_runtime_evidence";
    rows(i).CQITable = char(sixgr.link.resolveConfiguredCQITable(cfg, direction));
    rows(i).MCSTable = char(sixgr.link.resolveConfiguredMCSTable(cfg, direction));
    rows(i).Numerology_mu = double(numerology.Mu);
    rows(i).SCS_kHz = double(numerology.SubcarrierSpacingKHz);
    rows(i).ConfiguredBandwidth_Hz = double(sixgr.util.structGet(cfg, ...
        "channel.bandwidth_Hz", NaN));
    rows(i).CyclicPrefix = char(string(sixgr.util.structGet(cfg, ...
        "phy.carrier.CyclicPrefix", "")));
    rows(i).SlotDuration_ms = double(numerology.SlotDurationMilliseconds);
    rows(i).SlotsPerFrame = double(numerology.SlotsPerFrame);
    rows(i).SymbolsPerSlot = double(numerology.SymbolsPerSlot);
    rows(i).ConfiguredGridNumRBs = double(sixgr.util.structGet(cfg, "phy.numerology.configuredGridNumRBs", sixgr.util.structGet(cfg, "phy.carrier.NSizeGrid", NaN)));
    rows(i).ActiveGridNumRBs = double(sixgr.util.structGet(cfg, "phy.numerology.activeGridNumRBs", sixgr.util.structGet(cfg, "phy.carrier.NSizeGrid", NaN)));
    rows(i).ActiveGridSource = char(string(sixgr.util.structGet(cfg, "phy.numerology.activeGridSource", "configured_n_size_grid")));
    rows(i).NumerologySource = char(string(sixgr.util.structGet(cfg, "phy.numerology.numerologySource", "carrier_subcarrier_spacing_khz")));
    rows(i).TimingInterpretationSource = char(string(sixgr.util.structGet(cfg, "phy.numerology.timingInterpretationSource", "nr_mu_from_scs")));
    rows(i).CQISource = char(string(sixgr.util.structGet(cfg, "phy.linkAdaptation.cqiSource", "csi_feedback")));
    rows(i).WidebandSINRMargin_dB = NaN;
    rows(i).MultiUserEnabled = true;
    rows(i).ConfiguredUsers = double(sixgr.util.structGet(cfg, "scenario.nUE", NaN));
    rows(i).BrowserExecutionMode = char(string(sixgr.util.structGet(cfg, "run.executionMode", "LLS")));
    rows(i).UserExecutionModel = char(string(sixgr.util.structGet(scfg.toStruct(), "users.execution_model", "slot_coupled_truth")));
    rows(i).NoiseOperatingMode = char(string(sixgr.util.structGet(cfg, "run.noiseOperatingMode", "receiver_noise_figure_thermal_noise")));
    rows(i).DopplerSourceMode = char(string(sixgr.util.structGet(cfg, "channel.dopplerSourceMode", "")));
    rows(i).ResolvedDopplerHz = double(sixgr.util.structGet(cfg, "channel.doppler_Hz", NaN));
    rows(i).MobilitySpeed_kmh = localResolvedMobilitySpeed(cfg);
    rows(i).InterferenceMode = char(interferenceMode);
    rows(i).FullInterfererChannelTruthUsed = interferenceMode == "full_per_link_channel_waveform_sum";
    rows(i).SystemLevelSINRSource = "system_level_desired_interference_noise_budget";
    rows(i).SystemLevelSINRValueRole = "runtime_state_derived";
    rows(i).SystemLevelSINRValueStatus = "available_system_level_estimate";
    rows(i).ReceiverHestSINRSource = char(localDominantStringValue(evidenceT, "ReceiverHestSINRSource", "unavailable_system_level_no_receiver_hest_grid"));
    rows(i).ReceiverHestSINRValueStatus = char(localDominantStringValue(evidenceT, "ReceiverHestSINRValueStatus", "unavailable"));
    rows(i).DecoderTruthProxySINRSource = char(localDominantStringValue(evidenceT, "DecoderTruthProxySINRSource", "unavailable_system_level_no_decoder_truth_proxy"));
    rows(i).DecoderTruthProxySINRValueStatus = char(localDominantStringValue(evidenceT, "DecoderTruthProxySINRValueStatus", "unavailable"));
    rows(i).MeasuredTrialSINRSource = "deprecated_unavailable_in_system_level_lls";
    rows(i).MeasuredTrialSINRValueStatus = "unavailable";
    rows(i).ExplicitPrecoderReplayStatus = char(localDominantStringValue(evidenceT, "ExplicitPrecoderReplayStatus", "not_materialized"));
    rows(i).ExplicitPrecoderReplayBlocker = char(localDominantStringValue(evidenceT, "ExplicitPrecoderReplayBlocker", "sixgr.system.WaveformPHY.replayGrant_receives_grant_operating_point_not_explicit_precoder_matrix"));
    rows(i).AntennaRuntimeObjectSource = "not_materialized_explicit_array_object_in_system_level_lls";
    rows(i).AntennaRuntimeObjectValueStatus = "not_materialized";
    rows(i).ChannelArrayModel = char(phyProfile.ChannelArrayModel);
    rows(i).ChannelObjectSource = char(phyProfile.ChannelObjectSource);
    rows(i).ChannelObjectClass = char(phyProfile.ChannelObjectClass);
    rows(i).ChannelArrayHandlingStatus = char(phyProfile.ChannelArrayHandlingStatus);
    rows(i).ChannelArrayHandlingBlocker = char(phyProfile.ChannelArrayHandlingBlocker);
    rows(i).ChannelArrayValueStatus = "approximate_system_context";
    rows(i).ChannelUsesSameRuntimeAntennaAssumptions = false;
    rows(i).InterferenceChannelObjectSource = char(phyProfile.InterferenceChannelObjectSource);
    rows(i).InterferenceChannelObjectClass = char(phyProfile.InterferenceChannelObjectClass);
    rows(i).InterferenceChannelArrayHandlingStatus = char(phyProfile.InterferenceChannelArrayHandlingStatus);
    rows(i).InterferenceChannelArrayHandlingBlocker = char(phyProfile.InterferenceChannelArrayHandlingBlocker);
    rows(i).InterferenceChannelArrayValueStatus = "large_scale_interference_budget_no_runtime_interferer_channel_object";
    rows(i).InterferenceUsesSameRuntimeAntennaAssumptions = false;
    rows(i).InterferencePathUsesSameArrayAssumptions = false;
    rows(i).ControlIntegrationMode = char(phyProfile.ControlIntegrationMode);
    rows(i).PBCHMode = "missing_system_level_no_pbch_trial_materialization";
    rows(i).PRACHMode = "missing_system_level_no_prach_trial_materialization";
    rows(i).PDCCHMode = "active_but_simplified_scheduler_grant_signaling_not_separately_trialized";
    rows(i).PUCCHMode = "missing_system_level_no_pucch_grant_or_waveform_feedback";
    rows(i).SRSMode = "missing_system_level_no_srs_trial_materialization";
    rows(i).TRSMode = "missing_system_level_no_trs_tracking_trial_materialization";
    rows(i).TRSRuntimeConsumer = "none_system_level_no_trs_state";
    rows(i).TRSInfluencedDecision = false;
    rows(i).TRSInfluenceDefinition = "trs_not_materialized_in_system_level_lls";
    rows(i).TRSReceiverIntegrationStatus = "missing_system_level_no_trs_state";
    rows(i).TRSReceiverIntegrationBlocker = "system_level_runner_has_no_runtime_trs_trial_or_tracker_state";
    rows(i).PBCHGatingActive = false;
    rows(i).PRACHGatingActive = false;
    rows(i).PDCCHGatingActive = false;
    rows(i).SRSGatingActive = false;
    rows(i).TRSGatingActive = false;
    rows(i).ParallelExecutionActive = parallelActive;
    rows(i).ConfiguredWorkers = workerCount;
    rows(i).EffectiveWorkers = workerCount;
    rows(i).ParallelDisabledReason = char(string(sixgr.util.structGet(cfg, "run.parallelDisabledReason", "")));
    rows(i).ConfiguredBatchSizeLinks = double(sixgr.util.structGet(cfg, "run.batchSizeLinks", NaN));
    rows(i).ConfiguredSchedulerType = char(string(sixgr.util.structGet(cfg, "system.scheduler.type", sixgr.util.structGet(cfg, "mac.scheduler.type", ""))));
    rows(i).ConfiguredMeasurementPeriodSlots = measurementPeriod;
    rows(i).ConfiguredBeamUpdatePeriodSlots = beamUpdate;
    rows(i).ConfiguredTrafficModel = trafficModel;
    rows(i).ConfiguredTrafficTransport = trafficTransport;
    rows(i).ConfiguredTrafficFlowDirection = trafficFlowDirection;
    rows(i).ConfiguredTrafficTargetRate_Mbps = trafficTargetRate;
    rows(i).TrafficFlowSource = char(string(sixgr.util.structGet(cfg, "traffic.flowSource", "")));
    rows(i).TrafficFlowDerivationMode = char(string(sixgr.util.structGet(cfg, "traffic.flowDerivationMode", "")));
    rows(i).TrafficFlowResolvedFlag = logical(sixgr.util.structGet(cfg, "traffic.flowResolvedFlag", false));
    rows(i).CoupledGrantExecutionMode = char(phyProfile.CoupledGrantExecutionMode);
    rows(i).ExecutionBackend = char(phyProfile.ExecutionBackend);
    rows(i).PHYMode = char(phyProfile.PHYMode);
    rows(i).WaveformBacked = logical(phyProfile.WaveformBacked);
    rows(i).WaveformPHYActive = logical(phyProfile.WaveformPHYActive);
    rows(i).ProxyPHYActive = logical(phyProfile.ProxyPHYActive);
    rows(i).FallbackUsed = logical(phyProfile.FallbackUsed);
end
T = struct2table(rows, "AsArray", true);
end

function T = localBuildSystemWaveformScaleProfileTable(cfg, scfg, details, systemOut, dlRaw, ulRaw, dlGrantT, ulGrantT)
s = scfg.toStruct();
layoutDetails = sixgr.util.structGet(details, "Layout", struct());
numCells = size(sixgr.util.structGet(layoutDetails, "bs.pos_m", zeros(0, 3)), 1);
if numCells <= 0
    numCells = double(sixgr.util.structGet(s, "deployment_topology.num_cells", NaN));
end
numUEs = size(sixgr.util.structGet(details, "UEFinal.pos_m", zeros(0, 3)), 1);
if numUEs <= 0
    numUEs = double(sixgr.util.structGet(s, "deployment_topology.num_ues", NaN));
end
totalSlots = double(sixgr.util.structGet(cfg, "run.totalSlots", sixgr.util.structGet(cfg, "run.numTTI", NaN)));
if ~isfinite(totalSlots)
    totalSlots = max(localTableHeight(dlRaw), localTableHeight(ulRaw));
end
numSites = double(sixgr.util.structGet(s, "deployment_topology.num_sites", NaN));
sectorsPerSite = double(sixgr.util.structGet(s, "deployment_topology.num_sectors_per_site", NaN));
profileName = string(sixgr.util.structGet(s, "scenario.scale_profile", ""));
if strlength(strtrim(profileName)) == 0
    profileName = string(sixgr.util.structGet(s, "run_control.scale_profile", ""));
end
if strlength(strtrim(profileName)) == 0
    profileName = localDerivedScaleProfileName(numCells, numUEs, totalSlots);
end
scaleCategory = localScaleCategory(numCells, numUEs, totalSlots);
validationScope = localScaleValidationScope(scaleCategory);
productionClaimStatus = localProductionTruthClaimStatus(scaleCategory);
runtimeSummary = sixgr.util.structGet(systemOut, "RuntimeSummary", struct());
elapsed_s = double(sixgr.util.structGet(runtimeSummary, "ElapsedSeconds", NaN));
phyProfile = localSystemPHYTruthProfile(cfg, details);

T = table( ...
    profileName, ...
    scaleCategory, ...
    validationScope, ...
    productionClaimStatus, ...
    string(sixgr.util.structGet(s, "meta.scenario_id", "")), ...
    double(sixgr.util.structGet(cfg, "phy.fc_Hz", NaN)), ...
    double(sixgr.util.structGet(cfg, "channel.bandwidth_Hz", NaN)), ...
    string(sixgr.util.structGet(cfg, "phy.duplex.mode", "")), ...
    double(sixgr.util.structGet(cfg, "phy.numerology.scs_kHz", NaN)), ...
    double(sixgr.util.structGet(cfg, "phy.numerology.slotDuration_ms", NaN)), ...
    double(sixgr.util.structGet(cfg, "phy.numerology.configuredGridNumRBs", NaN)), ...
    numSites, sectorsPerSite, double(numCells), double(numUEs), totalSlots, ...
    double(localTableHeight(dlGrantT)), double(localTableHeight(ulGrantT)), ...
    double(localTableHeight(dlRaw)), double(localTableHeight(ulRaw)), ...
    string(sixgr.util.structGet(cfg, "system.scheduler.type", sixgr.util.structGet(cfg, "mac.scheduler.type", ""))), ...
    string(sixgr.util.structGet(cfg, "traffic.model", "")), ...
    string(localConfiguredInterferenceMode(cfg)), ...
    string(phyProfile.ExecutionBackend), string(phyProfile.PHYMode), ...
    logical(phyProfile.WaveformPHYActive), logical(phyProfile.ProxyPHYActive), logical(phyProfile.FallbackUsed), ...
    elapsed_s, ...
    string("system_runner_runtime_summary"), ...
    'VariableNames', {'ScaleProfileName','ScaleCategory','ValidationScope','ProductionTruthClaimStatus', ...
    'ScenarioID','CenterFrequency_Hz','Bandwidth_Hz','DuplexMode','SCS_kHz','SlotDuration_ms','ConfiguredGridNumRBs', ...
    'NumSites','SectorsPerSite','NumCells','NumUEs','TotalSlots','DLGrantRows','ULGrantRows','DLRawTrialRows','ULRawTrialRows', ...
    'SchedulerType','TrafficModel','InterferenceMode','ExecutionBackend','PHYMode','WaveformPHYActive','ProxyPHYActive','FallbackUsed', ...
    'SystemRunnerElapsed_s','RuntimeEvidenceSource'});
end

function T = localBuildSystemWaveformRuntimeProfileTable(cfg, scfg, details, systemOut, dlRaw, ulRaw, dlGrantT, ulGrantT)
s = scfg.toStruct();
runtimeSummary = sixgr.util.structGet(systemOut, "RuntimeSummary", struct());
elapsed_s = double(sixgr.util.structGet(runtimeSummary, "ElapsedSeconds", NaN));
totalSlots = double(sixgr.util.structGet(cfg, "run.totalSlots", sixgr.util.structGet(cfg, "run.numTTI", NaN)));
grantRows = localTableHeight(dlGrantT) + localTableHeight(ulGrantT);
rawRows = localTableHeight(dlRaw) + localTableHeight(ulRaw);
if isfinite(elapsed_s) && elapsed_s > 0
    slotsPerSecond = totalSlots / elapsed_s;
    grantsPerSecond = grantRows / elapsed_s;
else
    slotsPerSecond = NaN;
    grantsPerSecond = NaN;
end
detailsErrors = string(sixgr.util.structGet(systemOut, "Errors", strings(0, 1)));
detailsErrors = detailsErrors(strlength(strtrim(detailsErrors)) > 0);
phyProfile = localSystemPHYTruthProfile(cfg, details);

T = table( ...
    string(sixgr.util.structGet(s, "meta.scenario_id", "")), ...
    string(localDerivedScaleProfileName( ...
        double(sixgr.util.structGet(s, "deployment_topology.num_cells", NaN)), ...
        double(sixgr.util.structGet(s, "deployment_topology.num_ues", NaN)), ...
        totalSlots)), ...
    totalSlots, double(grantRows), double(rawRows), ...
    elapsed_s, slotsPerSecond, grantsPerSecond, ...
    logical(sixgr.util.structGet(s, "output.profiler_enabled", false)), ...
    double(sixgr.util.structGet(s, "output.profiler_top_functions", NaN)), ...
    double(sixgr.util.structGet(s, "output.profiler_top_edges", NaN)), ...
    string("requested_export_after_run_completion"), ...
    string("tic_toc_system_level_runner"), ...
    string("matlab_profile_tables_when_enabled"), ...
    string("strict_waveform_only"), ...
    string("primary_truth_artifact_scan_required"), ...
    string(phyProfile.ExecutionBackend), string(phyProfile.PHYMode), ...
    logical(phyProfile.WaveformPHYActive), logical(phyProfile.ProxyPHYActive), logical(phyProfile.FallbackUsed), ...
    double(sixgr.util.structGet(details, "DecodeOK", NaN)), ...
    double(sixgr.util.structGet(details, "DecodeFail", NaN)), ...
    double(sixgr.util.structGet(details, "DecodeUnavailableDL", NaN)) + double(sixgr.util.structGet(details, "DecodeUnavailableUL", NaN)), ...
    double(numel(detailsErrors)), ...
    string(strjoin(cellstr(detailsErrors), "; ")), ...
    'VariableNames', {'ScenarioID','DerivedScaleProfileName','TotalSlots','GrantRows','RawTrialRows', ...
    'SystemRunnerElapsed_s','SlotsPerSecond','GrantsPerSecond','MATLABProfilerRequested', ...
    'ProfilerTopFunctionsRequested','ProfilerTopEdgesRequested','ProfilerArtifactStatus', ...
    'RuntimeClockSource','ProfilerSource','TruthModePolicy','ArtifactScanPolicy', ...
    'ExecutionBackend','PHYMode','WaveformPHYActive','ProxyPHYActive','FallbackUsed', ...
    'DecodeOK','DecodeFail','DecodeUnavailable','SystemRunnerErrorCount','SystemRunnerErrors'});
end

function T = localBuildDeploymentLayoutReferenceTable(cfg, scfg, details)
layoutDetails = sixgr.util.structGet(details, "Layout", struct());
numCells = size(sixgr.util.structGet(layoutDetails, "bs.pos_m", zeros(0, 3)), 1);
numUEs = size(sixgr.util.structGet(details, "UEFinal.pos_m", zeros(0, 3)), 1);
if numCells <= 0
    numCells = double(sixgr.util.structGet(scfg.toStruct(), "deployment_topology.num_cells", NaN));
end
if numUEs <= 0
    numUEs = double(sixgr.util.structGet(scfg.toStruct(), "deployment_topology.num_ues", NaN));
end
numSites = double(sixgr.util.structGet(scfg.toStruct(), "deployment_topology.num_sites", NaN));
sectorsPerSite = double(sixgr.util.structGet(scfg.toStruct(), "deployment_topology.num_sectors_per_site", NaN));
layoutType = string(sixgr.util.structGet(cfg, "scenario.geometry.deployment", ...
    sixgr.util.structGet(scfg.toStruct(), "deployment_topology.layout_type", "")));
T = table( ...
    layoutType, ...
    numSites, sectorsPerSite, numCells, ...
    double(sixgr.util.structGet(scfg.toStruct(), "deployment_topology.inter_site_distance", NaN)), ...
    numUEs, double(sixgr.util.structGet(scfg.toStruct(), "deployment_topology.num_trps", numCells)), ...
    logical(sixgr.util.structGet(cfg, "scenario.mobility.enable", false)), ...
    string(sixgr.util.structGet(cfg, "scenario.mobility.model", "")), ...
    localResolvedMobilitySpeed(cfg), localResolvedMobilitySpeed(cfg), ...
    true, double(sixgr.util.structGet(cfg, "scenario.nUE", NaN)), ...
    string(sixgr.util.structGet(scfg.toStruct(), "users.execution_model", "slot_coupled_truth")), ...
    'VariableNames', {'LayoutType','NumSites','SectorsPerSite','NumCells','InterSiteDistance_m','NumUEs','NumTRPs', ...
    'MobilityEnabled','MobilityModel','MobilitySpeedMin_kmh','MobilitySpeedMax_kmh', ...
    'MultiUserEnabled','ConfiguredUsers','UserExecutionModel'});
end

function name = localDerivedScaleProfileName(numCells, numUEs, totalSlots)
category = localScaleCategory(numCells, numUEs, totalSlots);
switch category
    case "bounded_multicell"
        name = "bounded_multicell_waveform_truth_validation";
    case "large_topology_short_duration"
        name = "large_topology_waveform_truth_scale_probe";
    otherwise
        name = "single_or_microcell_waveform_truth_smoke";
end
end

function category = localScaleCategory(numCells, numUEs, totalSlots)
numCells = double(numCells);
numUEs = double(numUEs);
totalSlots = double(totalSlots);
if isfinite(numCells) && isfinite(numUEs) && isfinite(totalSlots) && ...
        numCells >= 19 && numUEs >= 100 && totalSlots >= 20
    category = "large_topology_short_duration";
elseif isfinite(numCells) && numCells >= 2
    category = "bounded_multicell";
else
    category = "single_or_microcell";
end
end

function scope = localScaleValidationScope(scaleCategory)
switch string(scaleCategory)
    case "large_topology_short_duration"
        scope = "scale_probe_not_long_duration_production_claim";
    case "bounded_multicell"
        scope = "bounded_multicell_waveform_truth_with_runtime_profile_and_artifact_scan";
    otherwise
        scope = "smoke_scale_only";
end
end

function status = localProductionTruthClaimStatus(scaleCategory)
switch string(scaleCategory)
    case "large_topology_short_duration"
        status = "not_claimed_until_long_duration_artifact_review_passes";
    case "bounded_multicell"
        status = "bounded_validation_pass_can_gate_larger_runs";
    otherwise
        status = "not_a_multicell_scale_validation";
end
end

function n = localTableHeight(T)
if istable(T)
    n = height(T);
else
    n = 0;
end
end

function T = localBuildCQITableReferenceTable(cfg)
rows = repmat(struct("Direction", "", "CQITable", "", "CQI", NaN, "Modulation", "", ...
    "TargetCodeRate", NaN, "SpectralEfficiency", NaN), 0, 1);
for direction = ["DL", "UL"]
    tableToken = string(sixgr.link.resolveConfiguredCQITable(cfg, direction));
    for idx = 0:15
        profile = sixgr.link.resolveCQIProfile(tableToken, idx);
        rows(end + 1, 1) = struct( ... %#ok<AGROW>
            "Direction", char(direction), ...
            "CQITable", char(tableToken), ...
            "CQI", double(idx), ...
            "Modulation", char(string(profile.Modulation)), ...
            "TargetCodeRate", double(profile.TargetCodeRate), ...
            "SpectralEfficiency", double(profile.SpectralEfficiency));
    end
end
T = struct2table(rows, "AsArray", true);
end

function T = localBuildMCSTableReferenceTable(cfg)
rows = repmat(struct("Direction", "", "MCSTable", "", "MCSIndex", NaN, "Modulation", "", ...
    "TargetCodeRate", NaN, "SpectralEfficiency", NaN), 0, 1);
for direction = ["DL", "UL"]
    tableToken = string(sixgr.link.resolveConfiguredMCSTable(cfg, direction));
    for idx = 0:31
        profile = sixgr.link.resolveMCSProfile(tableToken, idx);
        if ~logical(profile.Valid)
            continue;
        end
        rows(end + 1, 1) = struct( ... %#ok<AGROW>
            "Direction", char(direction), ...
            "MCSTable", char(tableToken), ...
            "MCSIndex", double(idx), ...
            "Modulation", char(string(profile.Modulation)), ...
            "TargetCodeRate", double(profile.TargetCodeRate), ...
            "SpectralEfficiency", double(profile.SpectralEfficiency));
    end
end
T = struct2table(rows, "AsArray", true);
end

function T = localBuildControlGatingSummaryTable(cfg, dlRaw, ulRaw)
phyProfile = localSystemPHYTruthProfile(cfg, struct());
T = table( ...
    string(phyProfile.ControlIntegrationMode), ...
    false, false, false, false, false, ...
    0, 0, 0, 0, 0, ...
    0, 0, 0, 0, 0, ...
    "unavailable_system_level_no_runtime_control_reference_signal_rows", ...
    "none_system_level_no_coupled_control_state", ...
    string(sprintf("dl_trials=%d; ul_trials=%d; system_level_control_signal_rows_missing_not_fabricated", height(dlRaw), height(ulRaw))), ...
    'VariableNames', {'ControlIntegrationMode','PBCHGatingActive','PRACHGatingActive','PDCCHGatingActive', ...
    'SRSGatingActive','TRSGatingActive','PBCHFailureCount','PRACHFailureCount','ControlDecodeFailureCount', ...
    'SRSInvalidEventCount','GrantsBlockedByGating','UsersAcquired','UsersAccessReady','UsersWithValidSRS', ...
    'UsersControlEligible','UsersSchedulingEligible','ValueStatus','RuntimeConsumer','Notes'});
end

function T = localEmptyControlGatingStateTable()
T = table( ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), string.empty(0, 1), string.empty(0, 1), ...
    string.empty(0, 1), string.empty(0, 1), string.empty(0, 1), false(0, 1), false(0, 1), ...
    false(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), string.empty(0, 1), ...
    string.empty(0, 1), string.empty(0, 1), ...
    'VariableNames', {'UEIndex','RNTI','ServingCell','CellAcquisitionState','AccessState','LastPDCCHStatus', ...
    'SRSValidityState','CSIValidityState','SchedulingEligibility','ControlEligibility','SRSValid','SRSAgeSlots', ...
    'LastSuccessfulPBCHSlot','LastSuccessfulPRACHSlot','LastSuccessfulPDCCHSlot','LastSuccessfulSRSSlot', ...
    'PBCHFailureCount','PRACHFailureCount','ControlDecodeFailureCount','SRSInvalidEventCount','GrantsBlockedByGating', ...
    'ValueStatus','RuntimeConsumer','NAReason'});
end

function T = localBuildStageStatusTable(cfg, systemOut, dlRaw, ulRaw, dlGrantT, ulGrantT, slotsPerFrame)
details = sixgr.util.structGet(systemOut, "Details", struct());
phyProfile = localSystemPHYTruthProfile(cfg, details);
ttiCount = max([ ...
    max(localNumericColumn(dlGrantT, "TTI", NaN), [], "omitnan"), ...
    max(localNumericColumn(ulGrantT, "TTI", NaN), [], "omitnan"), ...
    size(double(sixgr.util.structGet(details, "SlotDirection", strings(0, 1))), 1), ...
    1], [], "omitnan");
completedFrames = ceil(ttiCount / max(double(slotsPerFrame), 1));
configuredUsers = double(sixgr.util.structGet(cfg, "scenario.nUE", NaN));
row = struct( ...
    'Stage', "system_level_completed", ...
    'CurrentDirection', "", ...
    'CurrentSNR_dB', double(sixgr.util.structGet(cfg, "channel.snr_dB", NaN)), ...
    'SweepPointIndex', 1, ...
    'SweepPointCount', 1, ...
    'CurrentUEIndex', NaN, ...
    'TotalUsers', configuredUsers, ...
    'CurrentSlot', NaN, ...
    'DLCompletedFrames', completedFrames, ...
    'ULCompletedFrames', completedFrames, ...
    'CompletedFrames', completedFrames, ...
    'TotalFrames', completedFrames, ...
    'DLTrialRows', height(dlRaw), ...
    'ULTrialRows', height(ulRaw), ...
    'DLUniqueUsersPublished', numel(unique(localNumericColumn(dlRaw, "UEIndex", NaN))), ...
    'ULUniqueUsersPublished', numel(unique(localNumericColumn(ulRaw, "UEIndex", NaN))), ...
    'DLSummaryUsersPublished', numel(unique(localNumericColumn(dlRaw, "UEIndex", NaN))), ...
    'ULSummaryUsersPublished', numel(unique(localNumericColumn(ulRaw, "UEIndex", NaN))), ...
    'DLGrantCount', height(dlGrantT), ...
    'ULGrantCount', height(ulGrantT), ...
    'DLActiveUsers', numel(unique(localNumericColumn(dlGrantT, "UEID", NaN))), ...
    'ULActiveUsers', numel(unique(localNumericColumn(ulGrantT, "UEID", NaN))), ...
    'DLGrantedUsers', numel(unique(localNumericColumn(dlGrantT, "UEID", NaN))), ...
    'ULGrantedUsers', numel(unique(localNumericColumn(ulGrantT, "UEID", NaN))), ...
    'DLQueueBits', sum(localNumericColumn(dlRaw, "BitsCompared", NaN), "omitnan"), ...
    'ULQueueBits', sum(localNumericColumn(ulRaw, "BitsCompared", NaN), "omitnan"), ...
    'DLUserProgressFraction', localFraction(numel(unique(localNumericColumn(dlRaw, "UEIndex", NaN))), configuredUsers), ...
    'ULUserProgressFraction', localFraction(numel(unique(localNumericColumn(ulRaw, "UEIndex", NaN))), configuredUsers), ...
    'BidirectionalInterleavingEnabled', true, ...
    'AnchorKPIsReady', true, ...
    'DLTrialsReady', height(dlRaw) > 0, ...
    'ULTrialsReady', height(ulRaw) > 0, ...
    'ControlReady', true, ...
    'HARQReady', true, ...
    'BeamReady', true, ...
    'RFReady', true, ...
    'SweepReady', true, ...
    'FinalBundleReady', true, ...
    'Notes', string(phyProfile.ControlIntegrationMode) + "; canonical adapter published grant-backed DL/UL trials and reports");
T = struct2table(row, "AsArray", true);
end

function T = localBuildServingRSRPTraceTable(details, cfg, slotsPerFrame, tti_s)
rsrp = double(sixgr.util.structGet(details, "RSRP_dBm", []));
serving = double(sixgr.util.structGet(details, "ServingCell", []));
if isempty(rsrp) || isempty(serving)
    T = table();
    return;
end
ttiCount = size(rsrp, 1);
ueCount = size(rsrp, 2);
time_s = ((1:ttiCount).' - 1) * tti_s;
rows = repmat(struct( ...
    "TTI", NaN, "Time_s", NaN, "Frame", NaN, "Slot", NaN, "UEID", NaN, "UEIndex", NaN, "RNTI", NaN, ...
    "ServingCell", NaN, "BaseStationID", NaN, "ServingRSRP_dBm", NaN, "ServingDistance_m", NaN, ...
    "SelectedBeamIndex", NaN, "SelectedBeamGain_dB", NaN, "UEPosX_m", NaN, "UEPosY_m", NaN, "UEPosZ_m", NaN, ...
    "UEHeading_deg", NaN, "MeasurementSource", ""), 0, 1);
    for t = 1:ttiCount
        [frameIdx, slotIdx] = localFrameSlotFromTTI(t, slotsPerFrame);
        for u = 1:ueCount
            if ~isfinite(rsrp(t, u))
                continue;
            end
            rows(end + 1, 1) = struct( ... %#ok<AGROW>
                "TTI", double(t), ...
                "Time_s", double(time_s(t)), ...
                "Frame", double(frameIdx), ...
                "Slot", double(slotIdx), ...
                "UEID", double(u), ...
                "UEIndex", double(u), ...
                "RNTI", double(u), ...
                "ServingCell", double(localMatrixValue(serving, t, u)), ...
                "BaseStationID", double(localMatrixValue(serving, t, u)), ...
                "ServingRSRP_dBm", double(rsrp(t, u)), ...
                "ServingDistance_m", double(localMatrixValue(double(sixgr.util.structGet(details, "ServingDistance_m", [])), t, u)), ...
                "SelectedBeamIndex", double(localMatrixValue(double(sixgr.util.structGet(details, "ServingBeamIndex", [])), t, u)), ...
                "SelectedBeamGain_dB", double(localMatrixValue(double(sixgr.util.structGet(details, "ServingBeamGain_dB", [])), t, u)), ...
                "UEPosX_m", double(localMatrixValue(double(sixgr.util.structGet(details, "UEPosX_m", [])), t, u)), ...
                "UEPosY_m", double(localMatrixValue(double(sixgr.util.structGet(details, "UEPosY_m", [])), t, u)), ...
                "UEPosZ_m", double(localMatrixValue(double(sixgr.util.structGet(details, "UEPosZ_m", [])), t, u)), ...
                "UEHeading_deg", double(localMatrixValue(double(sixgr.util.structGet(details, "UEHeading_deg", [])), t, u)), ...
                "MeasurementSource", "system_level_serving_cell_trace");
        end
    end
if isempty(rows)
    T = table();
else
    T = struct2table(rows, "AsArray", true);
end
end

function ctx = localConfiguredMultiUserContext(cfg, scfg)
ctx = struct();
ctx.Enabled = true;
ctx.NumUsers = double(sixgr.util.structGet(cfg, "scenario.nUE", NaN));
ctx.ExecutionModel = char(string(sixgr.util.structGet(scfg.toStruct(), "users.execution_model", "slot_coupled_truth")));
end

function T = localEmptySchedulerGrantTable()
T = table('Size', [0 50], ...
    'VariableTypes', {'string','double','double','double','double','double','double','double','double','double', ...
    'string','double','double','double','double','double','double','double','double','string', ...
    'double','double','double','double','logical','double','double','double','logical','string', ...
    'double','double','double','string','string','string','string','string','string','string','string','string','string', ...
    'string','string','string','string','logical','logical','string'}, ...
    'VariableNames', {'Direction','TTI','Time_s','Frame','Slot','CellID','BaseStationID','UE','UEID','RNTI', ...
    'SlotDirection','PRBStart','PRBCount','SymbolStart','NumSymbols','TBSBits','TBSBytes','CQIUsed','MCSIndex','Modulation', ...
    'NumLayers','TargetCodeRate','SINR_dB','BLER','Ack','HarqID','RV','NDI','IsRetransmission','GrantReason', ...
    'HeadOfLineDelay_ms','BufferBytesBefore','BufferBytesAfter','GrantContextId','LinkAdaptationMode', ...
    'SchedulerGrantMCSSelectionMode','MCSSelectionSource','MCSValueStatus','RequestedOperatingPointSource','AppliedOperatingPointSource','ActualMCSSelectionMode', ...
    'InterferenceMode','Status','PHYDecisionRole','PHYDecisionStatus','PHYDecisionSource','PHYDecisionReason', ...
    'WaveformReplayExecuted','WaveformReplayReused','WaveformReplayKey'});
end

function T = localEmptyPUCCHGrantTable()
T = table( ...
    string.empty(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    string.empty(0, 1), string.empty(0, 1), string.empty(0, 1), string.empty(0, 1), ...
    'VariableNames', {'Direction','TTI','Frame','Slot','CellID','UEID','RNTI','PUCCHGrantId','PUCCHResourceId', ...
    'UCIType','Status'});
end

function T = localBuildSystemPDCCHTrialTable(dlGrantT, ulGrantT, slotDuration_ms)
grantT = localVertcatTables(dlGrantT, ulGrantT);
if isempty(grantT)
    T = localEmptyControlTrialTable("PDCCH");
    return;
end
n = height(grantT);
status = repmat("PASS", n, 1);
phyStatus = upper(strtrim(localStringColumn(grantT, "PHYDecisionStatus", "")));
runtimeStatus = repmat("system_level_scheduler_grant_available", n, 1);
runtimeStatus(phyStatus == "NOT_AVAILABLE") = "system_level_grant_without_separate_control_decode_observation";
status(phyStatus == "CRASH") = "CRASH";
status(phyStatus == "FAIL") = "FAIL";
status(phyStatus == "BLOCKED") = "FAIL";
decodeSuccess = true(n, 1);
decodeSuccess(status == "CRASH" | status == "FAIL") = false;
failureFlag = ~decodeSuccess;
T = table();
T.Status = status;
T.Frame = localNumericColumn(grantT, "Frame", NaN);
T.Slot = localNumericColumn(grantT, "Slot", NaN);
T.UEIndex = localNumericColumn(grantT, "UEID", NaN);
T.RNTI = localNumericColumn(grantT, "RNTI", NaN);
T.ControlStage = repmat("PDCCH_CONTROL", n, 1);
T.RuntimeStatus = runtimeStatus;
T.SignalFamily = repmat("PDCCH", n, 1);
T.SourceClassification = repmat("active_but_simplified", n, 1);
T.RuntimeMaterializationStatus = repmat("system_level_scheduler_grant_control_abstraction", n, 1);
T.ControlGatingEffect = repmat("scheduler_grant_row_implies_control_resource_assignment", n, 1);
T.DecodeSuccess = decodeSuccess;
T.SuccessFlag = decodeSuccess;
T.FailureFlag = failureFlag;
T.ControlObservationAvailable = true(n, 1);
T.ValueSource = repmat("system_level_scheduler_grant_trace", n, 1);
T.ValueRole = repmat("control_reference_signal_runtime_evidence", n, 1);
T.ValueStatus = repmat("available_runtime_abstraction", n, 1);
T.ValueDefinition = repmat("canonical system-level PDCCH control row derived from an actual scheduler-grant observation; control RE/DMRS mapping is not separately waveform-materialized in this path", n, 1);
T.FinalizedFlag = true(n, 1);
T.PlaceholderFlag = false(n, 1);
T.FallbackFlag = false(n, 1);
T.NAReason = repmat("", n, 1);
T.Direction = localStringColumn(grantT, "Direction", "DL");
T.TTI = localNumericColumn(grantT, "TTI", NaN);
T.CellID = localNumericColumn(grantT, "CellID", NaN);
T.BaseStationID = localNumericColumn(grantT, "BaseStationID", NaN);
T.GrantContextId = localStringColumn(grantT, "GrantContextId", "");
T.GrantReason = localStringColumn(grantT, "GrantReason", "");
T.FalseAlarmFlag = false(n, 1);
T.BlockingFlag = false(n, 1);
T.BlindDecodeCount = ones(n, 1);
T.AggregationLevel = nan(n, 1);
T.DCISize_bits = nan(n, 1);
T.NonOverlappedCCEUsage = nan(n, 1);
T.ControlCapacityUtilization = nan(n, 1);
T.CORESETUtilization = nan(n, 1);
T.ControlLatency_ms = nan(n, 1);
T.ComputeLatency_ms = nan(n, 1);
T.AirInterfaceTTI_ms = repmat(double(slotDuration_ms), n, 1);
T.RuntimeConsumer = repmat("SystemLevelRunner.schedulerGrantTrace", n, 1);
end

function T = localBuildSystemPUCCHGrantTable(dlGrantT, slotDuration_ms)
if isempty(dlGrantT)
    T = localEmptyPUCCHGrantTable();
    return;
end
n = height(dlGrantT);
ackFlag = localLogicalColumn(dlGrantT, "Ack", false);
status = repmat("OBSERVED_ABSTRACTION", n, 1);
T = table();
T.Direction = repmat("DL", n, 1);
T.TTI = localNumericColumn(dlGrantT, "TTI", NaN);
T.Frame = localNumericColumn(dlGrantT, "Frame", NaN);
T.Slot = localNumericColumn(dlGrantT, "Slot", NaN);
T.CellID = localNumericColumn(dlGrantT, "CellID", NaN);
T.UEID = localNumericColumn(dlGrantT, "UEID", NaN);
T.RNTI = localNumericColumn(dlGrantT, "RNTI", NaN);
T.PUCCHGrantId = "pucch_feedback_" + string(T.Frame) + "_" + string(T.Slot) + "_" + string(T.CellID) + "_" + string(T.UEID);
T.PUCCHResourceId = repmat("system_level_feedback_resource", n, 1);
T.UCIType = repmat("harq_ack", n, 1);
T.Status = status;
T.RequestedFormat = nan(n, 1);
T.ResolvedFormat = nan(n, 1);
T.UCIBitCount = repmat(1, n, 1);
T.PUCCHPRBStart = nan(n, 1);
T.PUCCHPRBCount = nan(n, 1);
T.PUCCHSymbolStart = nan(n, 1);
T.PUCCHNumSymbols = nan(n, 1);
T.BaseStationID = localNumericColumn(dlGrantT, "BaseStationID", NaN);
T.InterferenceMode = localStringColumn(dlGrantT, "InterferenceMode", "");
T.SignalFamily = repmat("PUCCH", n, 1);
T.SourceClassification = repmat("active_but_simplified", n, 1);
T.RuntimeMaterializationStatus = repmat("system_level_harq_feedback_abstraction_without_waveform_resource_mapping", n, 1);
T.ControlGatingEffect = repmat("dl_harq_ack_feedback_required", n, 1);
T.RuntimeStateConsumer = repmat("SystemLevelRunner.harq_feedback_state", n, 1);
T.RuntimeConsumer = repmat("SystemLevelRunner.harq_feedback_state", n, 1);
T.DecodeSuccess = true(n, 1);
T.SuccessFlag = true(n, 1);
T.FailureFlag = false(n, 1);
T.PUCCHDecodeOk = true(n, 1);
T.GrantScheduledFlag = true(n, 1);
T.GrantExecutedFlag = true(n, 1);
T.StateChangeApplied = true(n, 1);
T.ControlObservationAvailable = true(n, 1);
T.ValueSource = repmat("system_level_dl_grant_ack_state", n, 1);
T.ValueRole = repmat("explicit_pucch_grant_and_feedback_runtime_state", n, 1);
T.ValueStatus = repmat("available_runtime_abstraction", n, 1);
T.ValueDefinition = repmat("canonical system-level PUCCH feedback row derived from actual DL grant/HARQ state; explicit waveform format/resource mapping is not materialized in this path", n, 1);
T.FinalizedFlag = true(n, 1);
T.PlaceholderFlag = false(n, 1);
T.FallbackFlag = false(n, 1);
T.NAReason = repmat("pucch_format_and_re_mapping_not_materialized_by_system_level_runner", n, 1);
T.ExpectedAck = ackFlag;
T.ObservedAck = ackFlag;
T.AirInterfaceTTI_ms = repmat(double(slotDuration_ms), n, 1);
end

function T = localBuildSystemPUCCHTrialTable(grantT, slotDuration_ms)
if isempty(grantT)
    T = localEmptyControlTrialTable("PUCCH");
    return;
end
n = height(grantT);
T = table();
T.Status = repmat("PASS", n, 1);
T.Frame = localNumericColumn(grantT, "Frame", NaN);
T.Slot = localNumericColumn(grantT, "Slot", NaN);
T.UEIndex = localNumericColumn(grantT, "UEID", NaN);
T.RNTI = localNumericColumn(grantT, "RNTI", NaN);
T.ControlStage = repmat("PUCCH_CONTROL", n, 1);
T.RuntimeStatus = repmat("system_level_feedback_state_available", n, 1);
T.SignalFamily = repmat("PUCCH", n, 1);
T.SourceClassification = localStringColumn(grantT, "SourceClassification", "active_but_simplified");
T.RuntimeMaterializationStatus = localStringColumn(grantT, "RuntimeMaterializationStatus", "system_level_harq_feedback_abstraction_without_waveform_resource_mapping");
T.ControlGatingEffect = localStringColumn(grantT, "ControlGatingEffect", "dl_harq_ack_feedback_required");
T.DecodeSuccess = localLogicalColumn(grantT, "DecodeSuccess", true);
T.SuccessFlag = localLogicalColumn(grantT, "SuccessFlag", true);
T.FailureFlag = localLogicalColumn(grantT, "FailureFlag", false);
T.ControlObservationAvailable = localLogicalColumn(grantT, "ControlObservationAvailable", true);
T.ValueSource = localStringColumn(grantT, "ValueSource", "system_level_dl_grant_ack_state");
T.ValueRole = localStringColumn(grantT, "ValueRole", "explicit_pucch_grant_and_feedback_runtime_state");
T.ValueStatus = localStringColumn(grantT, "ValueStatus", "available_runtime_abstraction");
T.ValueDefinition = localStringColumn(grantT, "ValueDefinition", "canonical system-level PUCCH trial row derived from the actual DL grant/HARQ state");
T.FinalizedFlag = localLogicalColumn(grantT, "FinalizedFlag", true);
T.PlaceholderFlag = localLogicalColumn(grantT, "PlaceholderFlag", false);
T.FallbackFlag = localLogicalColumn(grantT, "FallbackFlag", false);
T.NAReason = localStringColumn(grantT, "NAReason", "pucch_format_and_re_mapping_not_materialized_by_system_level_runner");
T.Direction = localStringColumn(grantT, "Direction", "DL");
T.TTI = localNumericColumn(grantT, "TTI", NaN);
T.CellID = localNumericColumn(grantT, "CellID", NaN);
T.BaseStationID = localNumericColumn(grantT, "BaseStationID", NaN);
T.GrantContextId = localStringColumn(grantT, "PUCCHGrantId", "");
T.UCIType = localStringColumn(grantT, "UCIType", "harq_ack");
T.CRCPass = double(localLogicalColumn(grantT, "DecodeSuccess", true));
T.BitsCompared = localNumericColumn(grantT, "UCIBitCount", 1);
T.ComputeLatency_ms = nan(n, 1);
T.AirInterfaceTTI_ms = repmat(double(slotDuration_ms), n, 1);
T.RequestedFormat = localNumericColumn(grantT, "RequestedFormat", NaN);
T.ResolvedFormat = localNumericColumn(grantT, "ResolvedFormat", NaN);
T.PUCCHGrantId = localStringColumn(grantT, "PUCCHGrantId", "");
T.PUCCHResourceId = localStringColumn(grantT, "PUCCHResourceId", "");
T.RuntimeConsumer = localStringColumn(grantT, "RuntimeConsumer", "SystemLevelRunner.harq_feedback_state");
T.InterferenceMode = localStringColumn(grantT, "InterferenceMode", "");
T.ObservedAck = localLogicalColumn(grantT, "ObservedAck", false);
T.ExpectedAck = localLogicalColumn(grantT, "ExpectedAck", false);
end

function T = localEmptyControlTrialTable(controlStage)
T = table( ...
    string.empty(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), string.empty(0, 1), string.empty(0, 1), ...
    string.empty(0, 1), string.empty(0, 1), string.empty(0, 1), string.empty(0, 1), false(0, 1), false(0, 1), false(0, 1), ...
    'VariableNames', {'Status','Frame','Slot','UEIndex','RNTI','ControlStage','RuntimeStatus', ...
    'SignalFamily','SourceClassification','RuntimeMaterializationStatus','ControlGatingEffect', ...
    'DecodeSuccess','SuccessFlag','FailureFlag'});
if nargin >= 1
    T.ControlStage = repmat(string(controlStage), 0, 1);
    T.SignalFamily = repmat(string(controlStage), 0, 1);
end
end

function T = localEmptyRawTrialTable()
T = table();
T.Direction = string.empty(0, 1);
T.Frame = zeros(0, 1);
T.Slot = zeros(0, 1);
T.UEIndex = zeros(0, 1);
T.RNTI = zeros(0, 1);
T.BitsCompared = zeros(0, 1);
T.Goodput_Mbps = zeros(0, 1);
T.MCSIndex = zeros(0, 1);
T.Modulation = string.empty(0, 1);
T.TargetCodeRate = zeros(0, 1);
T.AllocatedPRBCount = zeros(0, 1);
T.SchedulerGrantMCSSelectionMode = string.empty(0, 1);
T.MCSSelectionSource = string.empty(0, 1);
T.MCSValueStatus = string.empty(0, 1);
T = sixgr.link.appendMeasuredPHYEvidenceColumns(T, {});
end

function row = localEmptyMultiUserSummaryRow()
row = struct( ...
    "UEIndex", NaN, "RNTI", NaN, "Direction", "", "ConfiguredLayers", NaN, ...
    "ConfiguredTxAntennas", NaN, "ConfiguredRxAntennas", NaN, "BeamformingApplied", false, ...
    "BeamSelectionStrategy", "", "BeamIndexSet", "", "ExecutionModel", "", "Throughput_Mbps", NaN, ...
    "ObservedRowCount", NaN, "BLER", NaN, "BER", NaN, "PassRate", NaN, ...
    "MeanMeasuredSINR_dB", NaN, "MeanChannelGain_dB", NaN, "SummaryRowValid", false, ...
    "RuntimeDataPresent", false, "UserHadAnySuccessfulTx", false, "UserHadAnySuccessfulRx", false, ...
    "PartialSuccess", false, "AllObservedRowsSuccessful", false, "SummaryStatus", "", ...
    "Ok", false, "OkDefinition", "compatibility_alias_of_summary_row_valid");
end

function directionT = localFilterDirection(T, direction)
directionT = table();
if ~(istable(T) && ~isempty(T))
    return;
end
if ~ismember("Direction", string(T.Properties.VariableNames))
    return;
end
mask = strcmpi(strtrim(string(T.Direction)), char(string(direction)));
directionT = T(mask, :);
end

function values = localNumericColumn(T, varName, defaultValue)
if nargin < 3
    defaultValue = NaN;
end
if ~(istable(T) && ismember(varName, string(T.Properties.VariableNames)))
    values = localDefaultColumn(defaultValue, height(T), "double");
    return;
end
values = double(T.(char(varName)));
end

function values = localLogicalColumn(T, varName, defaultValue)
if nargin < 3
    defaultValue = false;
end
if ~(istable(T) && ismember(varName, string(T.Properties.VariableNames)))
    values = localDefaultColumn(defaultValue, height(T), "logical");
    return;
end
raw = T.(char(varName));
if islogical(raw)
    values = logical(raw);
else
    values = isfinite(double(raw)) & logical(double(raw));
end
end

function values = localStringColumn(T, varName, defaultValue)
if nargin < 3
    defaultValue = "";
end
if ~(istable(T) && ismember(varName, string(T.Properties.VariableNames)))
    values = localDefaultColumn(defaultValue, height(T), "string");
    return;
end
values = string(T.(char(varName)));
end

function values = localDefaultColumn(defaultValue, n, kind)
if nargin < 3
    kind = "string";
end
n = max(0, round(double(n)));
switch string(kind)
    case "double"
        v = double(defaultValue);
        fillValue = NaN;
    case "logical"
        v = logical(defaultValue);
        fillValue = false;
    otherwise
        v = string(defaultValue);
        fillValue = "";
end
v = v(:);
if numel(v) == n
    values = v;
elseif isscalar(v)
    values = repmat(v, n, 1);
else
    values = repmat(fillValue, n, 1);
    count = min(n, numel(v));
    if count > 0
        values(1:count) = v(1:count);
    end
end
end

function source = localMCSSelectionSourceFromMode(modeValues)
mode = lower(strtrim(string(modeValues)));
source = repmat("configured_runtime_policy", size(mode));
source(mode == "cqi_table") = "runtime_cqi_table";
source(mode == "bootstrap_cqi_conservative") = "bootstrap_cqi_conservative_lab_default";
source(mode == "fixed_mcs") = "configured_fixed_mcs";
source(mode == "fixed_modulation") = "configured_modulation_code_rate";
end

function status = localMCSValueStatusFromMode(modeValues)
mode = lower(strtrim(string(modeValues)));
status = repmat("configured_runtime_policy", size(mode));
status(mode == "cqi_table") = "measured_cqi_mapped";
status(mode == "bootstrap_cqi_conservative") = "bootstrap_not_measured_cqi";
status(mode == "fixed_mcs" | mode == "fixed_modulation") = "configured";
end

function T = localQuarantineDecoderTruthProxy(T)
if ~istable(T) || ~ismember("DecoderTruthProxySINR_dB", string(T.Properties.VariableNames))
    return;
end
n = height(T);
if ~ismember("DecoderTruthProxySINRSource", string(T.Properties.VariableNames))
    T.DecoderTruthProxySINRSource = repmat("unavailable_system_level_no_decoder_truth_proxy", n, 1);
end
if ~ismember("DecoderTruthProxySINRValueRole", string(T.Properties.VariableNames))
    T.DecoderTruthProxySINRValueRole = repmat("unavailable", n, 1);
end
if ~ismember("DecoderTruthProxySINRValueStatus", string(T.Properties.VariableNames))
    T.DecoderTruthProxySINRValueStatus = repmat("unavailable", n, 1);
end
if ~ismember("DecoderTruthProxySINRNAReason", string(T.Properties.VariableNames))
    T.DecoderTruthProxySINRNAReason = repmat("system_level_sinr_budget_is_not_decoder_truth_proxy", n, 1);
end
decoderProxy = double(T.DecoderTruthProxySINR_dB);
source = strtrim(string(T.DecoderTruthProxySINRSource));
role = strtrim(string(T.DecoderTruthProxySINRValueRole));
proxyLike = isfinite(decoderProxy) | contains(lower(source), "proxy") | contains(lower(role), "proxy");
if any(proxyLike)
    decoderProxy(proxyLike) = NaN;
    source(proxyLike) = "evm_proxy_quarantined_not_decoder_truth";
    role(proxyLike) = "unavailable";
    T.DecoderTruthProxySINRValueStatus(proxyLike) = "unavailable";
    T.DecoderTruthProxySINRNAReason(proxyLike) = "decoder_truth_sinr_requires_receiver_or_decoder_evidence_not_evm_proxy";
end
blankSource = strlength(source) == 0;
source(blankSource) = "unavailable_system_level_no_decoder_truth_proxy";
blankRole = strlength(role) == 0;
role(blankRole) = "unavailable";
blankStatus = strlength(strtrim(string(T.DecoderTruthProxySINRValueStatus))) == 0;
T.DecoderTruthProxySINRValueStatus(blankStatus) = "unavailable";
blankReason = strlength(strtrim(string(T.DecoderTruthProxySINRNAReason))) == 0;
T.DecoderTruthProxySINRNAReason(blankReason) = "system_level_sinr_budget_is_not_decoder_truth_proxy";
T.DecoderTruthProxySINR_dB = decoderProxy;
T.DecoderTruthProxySINRSource = source;
T.DecoderTruthProxySINRValueRole = role;
end

function values = localTimingAvailabilityFromFlag(timingUsed)
timingUsed = logical(timingUsed(:));
values = repmat("missing", numel(timingUsed), 1);
values(timingUsed) = "available";
end

function values = localTimingErrorDefinitionFromFlag(timingUsed)
timingUsed = logical(timingUsed(:));
values = repmat("not_available_without_timing_estimate", numel(timingUsed), 1);
values(timingUsed) = "not_available_without_injected_timing_reference";
end

function values = localCFOAvailabilityFromEstimate(cfoHz)
cfoHz = double(cfoHz(:));
values = repmat("missing", numel(cfoHz), 1);
values(isfinite(cfoHz)) = "available";
end

function values = localCFOErrorDefinitionFromEstimate(cfoHz)
cfoHz = double(cfoHz(:));
values = repmat("not_available_without_cfo_estimate", numel(cfoHz), 1);
values(isfinite(cfoHz)) = "estimated_cfo_hz_no_injected_cfo_reference_in_system_replay";
end

function values = localValueStatusFromFinite(x)
x = double(x(:));
values = repmat("NOT_AVAILABLE", numel(x), 1);
values(isfinite(x)) = "OK";
end

function T = localAppendSystemGrantReplayEvidence(T, sourceT)
numericDefaults = struct( ...
    "ReceiverHestSINR_dB", NaN, ...
    "BitErrors", NaN, ...
    "BitsCompared", NaN, ...
    "RawBER", NaN, ...
    "PostEqSINR_dB", NaN, ...
    "DecoderTruthProxySINR_dB", NaN, ...
    "DecoderIterations", NaN, ...
    "RawTimingEstimate_samples", NaN, ...
    "AppliedTimingCorrection_samples", NaN, ...
    "InjectedTimingOffset_samples", NaN, ...
    "TrueTimingOffset_samples", NaN, ...
    "EstimatedTimingOffset_PreCorrection_samples", NaN, ...
    "TimingError_samples", NaN, ...
    "InjectedCFO_Hz", NaN, ...
    "TrueCFO_Hz", NaN, ...
    "EstimatedCFO_PreCorrection_Hz", NaN, ...
    "ResidualCFO_PostCorrection_Hz", NaN, ...
    "CFOError_Hz", NaN, ...
    "EstimatedCFO_Hz", NaN, ...
    "AppliedPathloss_dB", NaN, ...
    "AppliedShadowFading_dB", NaN, ...
    "AppliedLargeScaleGain_dB", NaN, ...
    "AppliedO2I_dB", NaN, ...
    "ServingRxPower_dBm", NaN, ...
    "ThermalNoisePower_dBm", NaN, ...
    "PhaseNoiseRMS_rad", NaN, ...
    "IQImbalanceImageRejection_dB", NaN, ...
    "RequestedPrecoderPMI", NaN, ...
    "AppliedPrecoderPMI", NaN, ...
    "PrecodingNumPorts", NaN, ...
    "PrecodingNumLayers", NaN, ...
    "PrecodingMatrixRows", NaN, ...
    "PrecodingMatrixCols", NaN);
logicalDefaults = struct( ...
    "PrecodingActive", false, ...
    "ExplicitBeamWeightsApplied", false, ...
    "TransformPrecodingApplied", false, ...
    "BeamformingApplied", false, ...
    "ChannelEstimateAvailable", false, ...
    "EqualizationAvailable", false, ...
    "DecodeAttempted", false, ...
    "DecodeAvailable", false, ...
    "LLRAvailable", false, ...
    "LLRFinite", false, ...
    "TimingEstimateUsed", false, ...
    "TimingEstimateWasClipped", false, ...
    "CFOEstimateAvailable", false, ...
    "PhaseNoiseConfigured", false, ...
    "PhaseNoiseApplied", false, ...
    "IQImbalanceConfigured", false, ...
    "IQImbalanceApplied", false);
stringDefaults = struct( ...
    "ReceiverHestSINRSource", "unavailable_system_level_no_receiver_hest_grid", ...
    "ReceiverHestSINRValueRole", "unavailable", ...
    "ReceiverHestSINRValueStatus", "unavailable", ...
    "ReceiverHestSINRNAReason", "system_level_adapter_does_not_export_receiver_hest_or_csi_grid", ...
    "PostEqSINRSource", "unavailable_system_level_no_post_equalizer_measurement", ...
    "PostEqSINRValueRole", "unavailable", ...
    "PostEqSINRValueStatus", "unavailable", ...
    "PostEqSINRNAReason", "system_level_adapter_does_not_export_post_equalizer_measurement", ...
    "PostEqSINRPerLayer_dB", "", ...
    "TimingEstimateApplicationPolicy", "", ...
    "TimingEstimateStatus", "", ...
    "TimingEstimateAvailability", "missing", ...
    "TimingErrorDefinition", "not_available_without_timing_estimate", ...
    "TimingValueStatus", "NOT_AVAILABLE", ...
    "CFOEstimateAvailability", "missing", ...
    "CFOErrorDefinition", "not_available_without_cfo_estimate", ...
    "CFOValueStatus", "NOT_AVAILABLE", ...
    "NoisePowerSource", "", ...
    "IQImbalanceMeasurementStatus", "", ...
    "DecoderTruthProxySINRSource", "unavailable_system_level_no_decoder_truth_proxy", ...
    "DecoderTruthProxySINRValueRole", "unavailable", ...
    "DecoderTruthProxySINRValueStatus", "unavailable", ...
    "DecoderTruthProxySINRNAReason", "system_level_sinr_budget_is_not_decoder_truth_proxy", ...
    "PrecoderSource", "system_level_beam_state_reference", ...
    "RequestedPrecoderSource", "system_level_beam_state_reference", ...
    "AppliedPrecoderSource", "not_materialized_in_system_level_lls", ...
    "PrecodingMode", "system_level_codebook_reference_no_explicit_replay_matrix", ...
    "PrecodingApplicationStage", "scheduler_link_state_only", ...
    "AppliedBeamIndexSet", "", ...
    "AppliedPrecoderValueRole", "unavailable", ...
    "AppliedPrecoderValueStatus", "not_materialized", ...
    "AppliedPrecoderNAReason", "system_level_grant_replay_does_not_materialize_precoder_matrix_or_pmi", ...
    "ExplicitPrecoderReplayStatus", "not_materialized", ...
    "ExplicitPrecoderReplayBlocker", "sixgr.system.WaveformPHY.replayGrant_receives_grant_operating_point_not_explicit_precoder_matrix", ...
    "AppliedPrecoderPMIType", "", ...
    "AppliedPrecoderCodebookMode", "");

names = fieldnames(numericDefaults);
for i = 1:numel(names)
    name = names{i};
    T.(name) = localNumericColumn(sourceT, name, numericDefaults.(name));
end
names = fieldnames(logicalDefaults);
for i = 1:numel(names)
    name = names{i};
    T.(name) = localLogicalColumn(sourceT, name, logicalDefaults.(name));
end
names = fieldnames(stringDefaults);
for i = 1:numel(names)
    name = names{i};
    T.(name) = localStringColumn(sourceT, name, stringDefaults.(name));
end
T = localAttachMeasuredPHYEvidenceColumnsFromGrant(T, sourceT);
end

function T = localAttachMeasuredPHYEvidenceColumnsFromGrant(T, sourceT)
defaults = sixgr.link.emptyMeasuredPHYEvidenceRow();
names = fieldnames(defaults);
for i = 1:numel(names)
    name = names{i};
    if isstring(defaults.(name)) || ischar(defaults.(name))
        T.(name) = localStringColumn(sourceT, name, "");
    else
        T.(name) = localNumericColumn(sourceT, name, NaN);
    end
end
end

function [frameIdx, slotIdx] = localFrameSlotFromTTI(tti, slotsPerFrame)
tti = double(tti(:));
slotsPerFrame = max(1, round(double(slotsPerFrame)));
frameIdx = floor(max(tti - 1, 0) ./ slotsPerFrame) + 1;
slotIdx = mod(max(tti - 1, 0), slotsPerFrame) + 1;
end

function ids = localSyntheticGrantId(direction, tti, cellId, ueIdx)
ids = strings(numel(tti), 1);
for i = 1:numel(tti)
    ids(i) = "sysgrant:dir=" + string(direction) + ":tti=" + string(localTokenNumber(tti(i))) + ...
        ":cell=" + string(localTokenNumber(cellId(i))) + ":ue=" + string(localTokenNumber(ueIdx(i)));
end
end

function [modulation, targetCodeRate] = localGrantOperatingPointColumns(cfg, direction, mcsIndex, targetCodeRateIn)
modulation = strings(numel(mcsIndex), 1);
targetCodeRate = double(targetCodeRateIn(:));
mcsTable = string(sixgr.link.resolveConfiguredMCSTable(cfg, direction));
for i = 1:numel(mcsIndex)
    profile = sixgr.link.resolveMCSProfile(mcsTable, mcsIndex(i));
    modulation(i) = string(profile.Modulation);
    if ~(isfinite(targetCodeRate(i)) && targetCodeRate(i) > 0)
        targetCodeRate(i) = double(profile.TargetCodeRate);
    end
end
end

function [mcsOut, modOut, rateOut] = localCQIDerivedOperatingPoint(cfg, direction, cqiIn)
cqiTable = string(sixgr.link.resolveConfiguredCQITable(cfg, direction));
mcsTable = string(sixgr.link.resolveConfiguredMCSTable(cfg, direction));
n = numel(cqiIn);
mcsOut = nan(n, 1);
modOut = strings(n, 1);
rateOut = nan(n, 1);
for i = 1:n
    amc = sixgr.link.resolveMCSFromCQI(cqiIn(i), mcsTable, cqiTable);
    mcsOut(i) = double(sixgr.util.structGet(amc, "MCSIndex", NaN));
    modOut(i) = string(sixgr.util.structGet(amc, "Modulation", ""));
    rateOut(i) = double(sixgr.util.structGet(amc, "TargetCodeRate", NaN));
end
end

function value = localConfiguredLinkMode(cfg)
value = lower(string(sixgr.util.structGet(cfg, "phy.linkAdaptation.mode", "fixed")));
if strlength(value) == 0
    value = "fixed";
end
end

function value = localConfiguredMCSSelectionPolicy(cfg)
mode = localConfiguredLinkMode(cfg);
value = "configured_fixed";
if mode ~= "fixed"
    value = "cqi_driven";
end
end

function value = localConfiguredSchedulerGrantMode(cfg)
mode = localConfiguredLinkMode(cfg);
if mode == "fixed"
    value = "configured_fixed";
else
    value = "cqi_driven";
end
end

function value = localRequestedOperatingPointSource(mode)
if string(mode) == "fixed"
    value = "configured_fixed_mcs";
else
    value = "cqi_link_adaptation";
end
end

function value = localConfiguredInterferenceMode(cfg)
value = string(sixgr.util.structGet(cfg, "run.interferenceMode", ...
        sixgr.util.structGet(cfg, "run.interferenceExecutionMode", ...
        sixgr.util.structGet(cfg, "channel.interferenceMode", ...
        sixgr.util.structGet(cfg, "system.interference.mode", "")))));
if strlength(value) == 0
    value = "not_configured";
end
end

function value = localResolvedChannelToken(cfg)
value = string(sixgr.util.structGet(cfg, "channel.delayProfile", sixgr.util.structGet(cfg, "channel.model", "")));
if strlength(value) == 0
    value = string(sixgr.util.structGet(cfg, "channel.model", "TDL"));
end
end

function profile = localSystemPHYTruthProfile(cfg, details)
if nargin < 2 || ~isstruct(details)
    details = struct();
end
profile = struct();
profile.WaveformBacked = logical(sixgr.util.structGet(details, "WaveformBacked", ...
    strcmpi(char(string(sixgr.util.structGet(cfg, "system.phyBackend", "waveform"))), "waveform")));
profile.ExecutionBackend = string(sixgr.util.structGet(details, "ExecutionBackend", ""));
profile.PHYMode = string(sixgr.util.structGet(details, "PHYMode", ""));
profile.WaveformPHYActive = logical(sixgr.util.structGet(details, "WaveformPHYActive", profile.WaveformBacked));
profile.ProxyPHYActive = logical(sixgr.util.structGet(details, "ProxyPHYActive", ~profile.WaveformBacked));
profile.FallbackUsed = logical(sixgr.util.structGet(details, "FallbackUsed", profile.ProxyPHYActive));

if profile.WaveformBacked
    profile.WaveformPHYActive = true;
    profile.ProxyPHYActive = false;
    profile.FallbackUsed = false;
    if strlength(profile.ExecutionBackend) == 0
        profile.ExecutionBackend = "WAVEFORM_SYSTEM_PHY";
    end
    if strlength(profile.PHYMode) == 0
        profile.PHYMode = "GRANT_CRC_WAVEFORM_REPLAY_EXPERIMENTAL";
    end
    profile.AppliedAWGNSNRAvailable = true;
    profile.AppliedAWGNSNRSource = "grant_level_waveform_replay_awgn_snr";
    profile.GrantControlState = "scheduler_grant_waveform_replay";
    profile.ChannelArrayModel = "system_level_large_scale_interference_budget_plus_grant_waveform_replay";
    profile.ChannelObjectSource = "sixgr.system.WaveformPHY.replayGrant";
    profile.ChannelObjectClass = "grant_crc_waveform_replay_experimental";
    profile.ChannelArrayHandlingStatus = "config_array_shape_no_runtime_object_pose";
    profile.ChannelArrayHandlingBlocker = "system_level_grant_replay_uses_configured_mimo_dimensions_not_runtime_phased_array_objects";
    profile.InterferenceChannelObjectSource = "system_level_interference_budget_without_explicit_interferer_waveform_objects";
    profile.InterferenceChannelObjectClass = "system_level_interference_budget";
    profile.InterferenceChannelArrayHandlingStatus = "large_scale_interference_budget_no_runtime_interferer_channel_object";
    profile.InterferenceChannelArrayHandlingBlocker = "system_level_interference_budget_does_not_materialize_interferer_channel_objects";
    profile.ControlIntegrationMode = "system_level_scheduler_waveform_phy_no_coupled_signal_gating";
    profile.CoupledGrantExecutionMode = "system_level_scheduler_with_grant_waveform_replay";
else
    profile.WaveformPHYActive = false;
    profile.ProxyPHYActive = true;
    profile.FallbackUsed = true;
    if strlength(profile.ExecutionBackend) == 0
        profile.ExecutionBackend = "NON_WAVEFORM_SYSTEM_PHY_BLOCKED";
    end
    if strlength(profile.PHYMode) == 0
        profile.PHYMode = "BLOCKED_NON_WAVEFORM_BACKEND";
    end
    profile.AppliedAWGNSNRAvailable = false;
    profile.AppliedAWGNSNRSource = "not_applied_non_waveform_backend_blocked";
    profile.GrantControlState = "scheduler_grant_decode_blocked_non_waveform_backend";
    profile.ChannelArrayModel = "non_waveform_backend_blocked_no_channel_truth";
    profile.ChannelObjectSource = "sixgr.system.WaveformPHY.required";
    profile.ChannelObjectClass = "blocked_non_waveform_backend";
    profile.ChannelArrayHandlingStatus = "blocked_no_runtime_waveform_channel_object";
    profile.ChannelArrayHandlingBlocker = "system_phy_backend_must_be_waveform_for_no_proxy_lls_runtime";
    profile.InterferenceChannelObjectSource = "system_level_interference_budget_without_explicit_interferer_waveform_objects";
    profile.InterferenceChannelObjectClass = "system_level_interference_budget";
    profile.InterferenceChannelArrayHandlingStatus = "large_scale_interference_budget_no_runtime_interferer_channel_object";
    profile.InterferenceChannelArrayHandlingBlocker = "system_level_interference_budget_does_not_materialize_interferer_channel_objects";
    profile.ControlIntegrationMode = "blocked_non_waveform_phy_no_coupled_signal_gating";
    profile.CoupledGrantExecutionMode = "blocked_non_waveform_phy";
end
end

function tf = localConfiguredTransformPrecoding(cfg)
tf = logical(sixgr.util.structGet(cfg, "phy.waveform.transformPrecodingEnabled", false)) || ...
    strcmpi(char(string(sixgr.util.structGet(cfg, "phy.waveform.ul", ""))), "DFT-s-OFDM");
end

function value = localResolvedMobilitySpeed(cfg)
speed = double(sixgr.util.structGet(cfg, "scenario.mobility.speed_kmh", NaN));
if numel(speed) > 1
    speed = speed(1);
end
value = speed;
end

function value = localResolvedTrafficTargetRate(scfg)
value = double(sixgr.util.structGet(scfg.toStruct(), "traffic.target_rate_mbps", NaN));
if ~isfinite(value)
    value = double(sixgr.util.structGet(scfg.toStruct(), "traffic.offered_load_mbps", NaN));
end
end

function value = localDominantStringValue(T, varName, defaultValue)
if nargin < 3
    defaultValue = "";
end
value = string(defaultValue);
if ~(istable(T) && ismember(varName, string(T.Properties.VariableNames)) && ~isempty(T))
    return;
end
vals = strtrim(string(T.(char(varName))));
vals = vals(strlength(vals) > 0);
if isempty(vals)
    return;
end
[u, ~, idx] = unique(vals, "stable");
counts = accumarray(idx, 1);
[~, best] = max(counts);
value = u(best);
end

function value = localDirectionalMetric(details, direction, dlField, ulField, tti, ue)
fieldName = dlField;
if upper(string(direction)) == "UL"
    fieldName = ulField;
end
matrix = double(sixgr.util.structGet(details, fieldName, []));
value = nan(numel(tti), 1);
for i = 1:numel(tti)
    value(i) = localMatrixValue(matrix, tti(i), ue(i));
end
end

function value = localMatrixValue(matrix, rowIdx, colIdx)
value = NaN;
if isempty(matrix) || ~ismatrix(matrix)
    return;
end
if ~(isfinite(rowIdx) && isfinite(colIdx))
    return;
end
rowIdx = round(double(rowIdx));
colIdx = round(double(colIdx));
if rowIdx < 1 || colIdx < 1 || rowIdx > size(matrix, 1) || colIdx > size(matrix, 2)
    return;
end
value = double(matrix(rowIdx, colIdx));
end

function value = localNoiseVarianceFromdBm(noise_dBm)
value = nan(size(noise_dBm));
mask = isfinite(noise_dBm);
value(mask) = 10.^(double(noise_dBm(mask)) / 10) ./ 1e3;
end

function values = localOptionalTrialColumn(T, varName, defaultValue)
if ismember(varName, string(T.Properties.VariableNames))
    values = T.(char(varName));
else
    if islogical(defaultValue)
        values = repmat(logical(defaultValue), height(T), 1);
    elseif isstring(defaultValue) || ischar(defaultValue)
        values = repmat(string(defaultValue), height(T), 1);
    else
        values = repmat(defaultValue, height(T), 1);
    end
end
end

function value = localSafeMean(values)
values = double(values);
values = values(isfinite(values));
if isempty(values)
    value = NaN;
else
    value = mean(values);
end
end

function frac = localFraction(a, b)
if ~(isfinite(a) && isfinite(b) && b > 0)
    frac = NaN;
else
    frac = double(a) / double(b);
end
end

function T = localVertcatTables(varargin)
parts = varargin(cellfun(@(x) istable(x) && ~isempty(x), varargin));
if isempty(parts)
    T = table();
else
    T = vertcat(parts{:});
end
end

function token = localTokenNumber(value)
if ~isfinite(value)
    token = "nan";
elseif abs(value - round(value)) < 1e-9
    token = string(round(value));
else
    token = string(value);
end
end

function value = localFiniteOrDefault(value, defaultValue)
if ~(isfinite(value) && ~isempty(value))
    value = defaultValue;
end
end

function numerology = localCanonicalNumerology(cfg)
scsKHz = double(sixgr.util.structGet(cfg, ...
    "phy.carrier.SubcarrierSpacing", ...
    sixgr.util.structGet(cfg, "phy.carrier.SubcarrierSpacing_kHz", ...
    sixgr.util.structGet(cfg, "phy.numerology.scs_kHz", NaN))));
cp = string(sixgr.util.structGet(cfg, "phy.carrier.CyclicPrefix", "normal"));
numerology = sixgr.phy.frame.NumerologyCatalog.resolve( ...
    scsKHz, cp, "generic_waveform_test", "");
end
