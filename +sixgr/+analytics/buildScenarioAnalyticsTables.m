function report = buildScenarioAnalyticsTables(runDir, trialData, scenarioCfg)
%BUILDSCENARIOANALYTICSTABLES Build derived analysis CSVs for a completed run.
%
% These are post-run analysis artifacts. They aggregate existing runtime rows
% and preserve NaN/blank values when a measurement is absent.

arguments
    runDir {mustBeTextScalar}
    trialData = []
    scenarioCfg = struct()
end

if isempty(trialData)
    trialData = sixgr.analytics.loadAllTrialData(runDir);
end
layout = sixgr.report.resultLayout(runDir);
sixgr.util.ensureFolder(layout.ReportCSVDir);
sixgr.util.ensureFolder(layout.AirInterfaceCSVDir);

perSlot = localBuildPerSlotKPI(trialData);
perUE = localBuildPerUESlotKPI(trialData);
physics = localBuildPhysicsTimeline(trialData);
control = localBuildControlPlaneTimeline(trialData);
nmse = localBuildNMSEVsMeasuredSINR(trialData);
energy = localBuildEnergyVsThroughput(trialData);
tbs = localBuildTBSReferenceComparison(trialData);
shannon = localBuildShannonCapacityGap(trialData, scenarioCfg);
trs = localBuildTRSDopplerErrorTrace(trialData);
measured = sixgr.analytics.generateMeasuredSINRCurves(runDir, "", ...
    "TrialData", trialData, ...
    "ScenarioConfig", scenarioCfg, ...
    "WriteKPISummary", true);
measuredPlots = sixgr.analytics.generateMeasuredSINRPlots(runDir, "");

paths = struct();
paths.PerSlotKPI = fullfile(layout.ReportCSVDir, "per_slot_kpi_table.csv");
paths.PerUESlotKPI = fullfile(layout.ReportCSVDir, "per_ue_slot_kpi_table.csv");
paths.FullPhysicsTimeline = fullfile(layout.ReportCSVDir, "full_physics_timeline.csv");
paths.ControlPlaneTimeline = fullfile(layout.ReportCSVDir, "control_plane_timeline.csv");
paths.MeasuredSINRSummary = fullfile(layout.AirInterfaceCSVDir, "lls_measured_sinr_summary.csv");
paths.MeasuredSINRPlots = measuredPlots.Plots;
paths.MeasuredSINRPlotLineage = measuredPlots.LineageCSV;
paths.NMSEVsMeasuredSINR = fullfile(layout.ReportCSVDir, "nmse_vs_measured_sinr.csv");
paths.EnergyVsThroughput = fullfile(layout.ReportCSVDir, "energy_vs_throughput.csv");
paths.TBSReferenceComparison = fullfile(layout.ReportCSVDir, "tbs_reference_comparison.csv");
paths.ShannonCapacityGap = fullfile(layout.ReportCSVDir, "shannon_capacity_gap.csv");
paths.TRSDopplerErrorTrace = fullfile(layout.ReportCSVDir, "trs_doppler_error_trace.csv");
paths.MeasuredSINRCurves = measured.Paths;

sixgr.analytics.writeAnalysisTable(paths.PerSlotKPI, perSlot);
sixgr.analytics.writeAnalysisTable(paths.PerUESlotKPI, perUE);
sixgr.analytics.writeAnalysisTable(paths.FullPhysicsTimeline, physics);
sixgr.analytics.writeAnalysisTable(paths.ControlPlaneTimeline, control);
sixgr.analytics.writeAnalysisTable(paths.NMSEVsMeasuredSINR, nmse);
sixgr.analytics.writeAnalysisTable(paths.EnergyVsThroughput, energy);
sixgr.analytics.writeAnalysisTable(paths.TBSReferenceComparison, tbs);
sixgr.analytics.writeAnalysisTable(paths.ShannonCapacityGap, shannon);
sixgr.analytics.writeAnalysisTable(paths.TRSDopplerErrorTrace, trs);

summary = table( ...
    ["per_slot_kpi_table";"per_ue_slot_kpi_table";"full_physics_timeline";"control_plane_timeline";"lls_measured_sinr_summary";"nmse_vs_measured_sinr";"energy_vs_throughput";"tbs_reference_comparison";"shannon_capacity_gap";"trs_doppler_error_trace"], ...
    [height(perSlot);height(perUE);height(physics);height(control);height(measured.Tables.Summary);height(nmse);height(energy);height(tbs);height(shannon);height(trs)], ...
    ["RUNTIME_DERIVED";"RUNTIME_DERIVED";"RUNTIME_DERIVED";"RUNTIME_DERIVED";"MEASURED_SINR_GEOMETRY";"RUNTIME_DERIVED";"RUNTIME_DERIVED";"RUNTIME_DERIVED";"RUNTIME_DERIVED";"RUNTIME_DERIVED"], ...
    'VariableNames', {'ArtifactName','RowCount','EvidenceClass'});
sixgr.analytics.writeAnalysisTable(fullfile(layout.ReportCSVDir, "analysis_generation_summary.csv"), summary);

report = struct("Paths", paths, "Summary", summary);
end

function T = localBuildPerSlotKPI(trialData)
dl = trialData.dl;
ul = trialData.ul;
slots = unique([localColumn(dl, "Slot"); localColumn(ul, "Slot")]);
slots = slots(isfinite(slots));
rows = cell(0, 1);
for i = 1:numel(slots)
    slot = slots(i);
    d = localRowsBySlot(dl, slot);
    u = localRowsBySlot(ul, slot);
    frame = localFirstFinite([localColumn(d, "Frame"); localColumn(u, "Frame")], floor(slot / 20));
    r = struct();
    r.Slot = slot;
    r.Frame = frame;
    r.Timestamp_ms = slot * localSlotDurationMs(trialData);
    r.TDDPattern = "";
    r.DLActive = height(d) > 0;
    r.ULActive = height(u) > 0;
    r.SpecialSlotActive = false;
    r.DL_GrantCount = height(d);
    r.UL_GrantCount = height(u);
    r.DL_TotalPRBs = localSum(d, ["AllocatedPRBCount","PRBs","PRBCount"]);
    r.UL_TotalPRBs = localSum(u, ["AllocatedPRBCount","PRBs","PRBCount"]);
    r.DL_TotalTBSBits = localSum(d, ["TBSize_bits","TBSBits","TBS"]);
    r.UL_TotalTBSBits = localSum(u, ["TBSize_bits","TBSBits","TBS"]);
    r.DL_SuccessCount = localPassCount(d);
    r.DL_FailCount = localFailCount(d);
    r.DL_BLER = localSafeDivide(r.DL_FailCount, r.DL_GrantCount);
    r.UL_BLER = localSafeDivide(localFailCount(u), r.UL_GrantCount);
    r.DL_Goodput_Mbps = localGoodputMbps(d);
    r.UL_Goodput_Mbps = localGoodputMbps(u);
    r.DL_MeanMCS = localMean(d, ["MCS","MCSIndex"]);
    r.UL_MeanMCS = localMean(u, ["MCS","MCSIndex"]);
    r.DL_MeanLayers = localMean(d, ["Layers","Rank"]);
    r.UL_MeanLayers = localMean(u, ["Layers","Rank"]);
    r.DL_MeanPostEqSINR_dB = localMean(d, ["PostEqSINR_dB","PostEqSINRWidebanddB","MeasuredSINR_dB"]);
    r.UL_MeanPostEqSINR_dB = localMean(u, ["PostEqSINR_dB","PostEqSINRWidebanddB","MeasuredSINR_dB"]);
    r.DL_PRBEfficiency = localSafeDivide(r.DL_TotalTBSBits, r.DL_TotalPRBs);
    r.UL_PRBEfficiency = localSafeDivide(r.UL_TotalTBSBits, r.UL_TotalPRBs);
    r.HARQ_FeedbackDue = false;
    r.HARQ_ACK_Received = NaN;
    r.HARQ_NACK_Received = NaN;
    r.Beamforming_Applied = localAnyTrue(d, "BeamformingApplied") || localAnyTrue(u, "BeamformingApplied");
    r.BeamSwitchEvent = false;
    r.SRS_Measured = localHasSlot(trialData.srs, slot);
    r.TRS_Updated = localHasSlot(trialData.trs, slot);
    r.CFO_Residual_Hz = localFirstFinite([localMean(d, ["ResidualCFO_PostCorrection_Hz","ResidualCFO_Hz"]); localMean(u, ["ResidualCFO_PostCorrection_Hz","ResidualCFO_Hz"])], NaN);
    r.TimingError_samples = localFirstFinite([localMean(d, ["TimingError_samples","ResidualTimingError_PostCorrection_samples"]); localMean(u, ["TimingError_samples","ResidualTimingError_PostCorrection_samples"])], NaN);
    rows{end+1, 1} = r; %#ok<AGROW>
end
T = localStructRowsToTable(rows, localPerSlotVars());
end

function T = localBuildPerUESlotKPI(trialData)
rows = cell(0, 1);
rows = [rows; localPerUEDirectionRows(trialData.dl, "DL")]; %#ok<AGROW>
rows = [rows; localPerUEDirectionRows(trialData.ul, "UL")]; %#ok<AGROW>
T = localStructRowsToTable(rows, localPerUEVars());
end

function rows = localPerUEDirectionRows(Tin, direction)
rows = cell(0, 1);
for i = 1:height(Tin)
    r0 = Tin(i, :);
    r = struct();
    r.UEIndex = localValue(r0, ["UEIndex","UEID","UEId"], NaN);
    r.RNTI = localValue(r0, "RNTI", NaN);
    r.Slot = localValue(r0, "Slot", NaN);
    r.Frame = localValue(r0, "Frame", NaN);
    r.Direction = string(direction);
    r.MCS = localValue(r0, ["MCS","MCSIndex"], NaN);
    r.PRBs = localValue(r0, ["AllocatedPRBCount","PRBs","PRBCount"], NaN);
    r.TBSBits = localValue(r0, ["TBSize_bits","TBSBits","TBS"], NaN);
    r.Layers = localValue(r0, ["Layers","Rank"], NaN);
    r.Modulation = string(localValue(r0, "Modulation", ""));
    r.CodeRate = localValue(r0, ["TargetCodeRate","CodeRate"], NaN);
    r.BLER = double(localFailCount(r0) > 0);
    r.BER = localValue(r0, "RawBER", NaN);
    r.Goodput_Mbps = localValue(r0, "Goodput_Mbps", NaN);
    r.Throughput_Mbps = localValue(r0, "OfferedThroughput_Mbps", NaN);
    r.PostEqSINR_dB = localValue(r0, ["PostEqSINR_dB","PostEqSINRWidebanddB"], NaN);
    r.ChannelGain_dB = localValue(r0, "ChannelGain_dB", NaN);
    r.MeasuredSINR_dB = localValue(r0, "MeasuredSINR_dB", NaN);
    r.WidebandCQI = localValue(r0, "WidebandCQI", NaN);
    r.PMI = localValue(r0, "PMI", NaN);
    r.RankIndicator = localValue(r0, "RankIndicator", NaN);
    r.SelectedBeamIndex = localValue(r0, "SelectedBeamIndex", NaN);
    r.BestBeamIndex = localValue(r0, "BestBeamIndex", NaN);
    r.BeamHit = localValue(r0, "BeamHit", NaN);
    r.BeamGainGap_dB = localValue(r0, "BeamGainGap_dB", NaN);
    r.ConditionNumber_dB = localValue(r0, "ConditionNumber_dB", NaN);
    r.PAPR_dB = localValue(r0, "PAPR_dB", NaN);
    r.EVM_rms = localValue(r0, "EVM_rms", NaN);
    r.NMSE_dB = localValue(r0, "NMSE_dB", NaN);
    r.DecoderIterations = localValue(r0, "DecoderIterations", NaN);
    r.DecoderComplexity = localValue(r0, "DecoderComplexityUnits", NaN);
    r.DecodeLatency_ms = localValue(r0, "DecodeLatency_ms", NaN);
    r.InjectedDoppler_Hz = localValue(r0, "InjectedDoppler_Hz", NaN);
    r.EstimatedDoppler_Hz = localValue(r0, "EstimatedDopplerHz", NaN);
    r.DopplerError_Hz = localValue(r0, "DopplerError_Hz", NaN);
    r.TimingOffset_samples = localValue(r0, "TimingOffset_samples", NaN);
    r.TimingError_samples = localValue(r0, "TimingError_samples", NaN);
    r.ResidualCFO_Hz = localValue(r0, ["ResidualCFO_PostCorrection_Hz","ResidualCFO_Hz"], NaN);
    r.IQImbalanceGain_dB = localValue(r0, "ConfiguredIQGainImbalance_dB", NaN);
    r.IQImbalancePhase_deg = localValue(r0, "ConfiguredIQPhaseImbalance_deg", NaN);
    r.ImageRejection_dB = localValue(r0, "IQImbalanceImageRejection_dB", NaN);
    r.OLLADeltaDb = localValue(r0, ["OLLADeltaDb","OLLADeltaMCS"], NaN);
    r.OLLADeltaMCS = localValue(r0, "OLLADeltaMCS", NaN);
    r.OLLAAdjustedMCSBeforeCQICeiling = localValue(r0, "OLLAAdjustedMCSBeforeCQICeiling", NaN);
    r.OLLABaseRequiredSINR_dB = localValue(r0, "OLLABaseRequiredSINR_dB", NaN);
    r.OLLATargetRequiredSINR_dB = localValue(r0, "OLLATargetRequiredSINR_dB", NaN);
    r.OLLAThresholdSource = string(localValue(r0, "OLLAThresholdSource", ""));
    r.OLLAState = string(localValue(r0, "OLLAState", ""));
    r.OuterLoopApplied = localValue(r0, "OuterLoopApplied", NaN);
    r.InnerLoopApplied = localValue(r0, "InnerLoopApplied", NaN);
    r.HARQ_ID = localValue(r0, ["HARQ_ID","HARQProcessID","HARQProcess"], NaN);
    r.HARQ_RV = localValue(r0, ["RV","HARQ_RV","RedundancyVersion"], NaN);
    r.IsRetransmission = localValue(r0, "IsRetransmission", NaN);
    r.CombiningEnabled = localValue(r0, "CombiningEnabled", NaN);
    r.TBSize_DUT = r.TBSBits;
    r.TBSize_Reference = NaN;
    r.TBSize_Delta = NaN;
    r.TBSMatch = NaN;
    r.StrictOk = localValue(r0, "StrictOk", NaN);
    r.TruthStatus = string(localValue(r0, "TruthStatus", ""));
    rows{end+1, 1} = r; %#ok<AGROW>
end
end

function T = localBuildPhysicsTimeline(trialData)
rows = cell(0, 1);
rows = [rows; localPhysicsRows(trialData.dl, "DL")]; %#ok<AGROW>
rows = [rows; localPhysicsRows(trialData.ul, "UL")]; %#ok<AGROW>
T = localStructRowsToTable(rows, localPhysicsVars());
end

function rows = localPhysicsRows(Tin, direction)
rows = cell(0, 1);
for i = 1:height(Tin)
    r0 = Tin(i, :);
    r = struct();
    r.TrialIndex = i;
    r.Frame = localValue(r0, "Frame", NaN);
    r.Slot = localValue(r0, "Slot", NaN);
    r.Timestamp_ms = localValue(r0, "Slot", NaN) * 0.5;
    r.UEIndex = localValue(r0, ["UEIndex","UEID"], NaN);
    r.Direction = string(direction);
    r.PropagationDistance_m = localValue(r0, "PropagationDistance_m", NaN);
    r.PathLoss_dB = localValue(r0, ["AppliedPathloss_dB","AppliedLargeScaleLoss_dB"], NaN);
    r.ShadowFading_dB = localValue(r0, "AppliedShadowFading_dB", NaN);
    r.O2I_dB = localValue(r0, "AppliedO2I_dB", NaN);
    r.LargeScaleGain_dB = localValue(r0, "AppliedLargeScaleGain_dB", NaN);
    r.SmallScaleGain_dB_perSC = NaN;
    r.TxPower_dBm = localValue(r0, ["TxPower_dBm","PreambleTxPower_dBm","Msg3TxPower_dBm"], NaN);
    r.RxPower_dBm = localValue(r0, "RxPower_dBm", NaN);
    r.NoisePower_dBm = NaN;
    r.SNR_configured_dB = localValue(r0, ["ConfiguredSNR_dB","SNR_dB"], NaN);
    r.SNR_applied_dB = localValue(r0, ["AppliedAWGNSNR_dB","SNR_dB"], NaN);
    r.NoiseVariance = localValue(r0, "NoiseVariance", NaN);
    r.DopplerHz_injected = localValue(r0, ["InjectedDoppler_Hz","DopplerHz"], NaN);
    r.DopplerHz_estimated = localValue(r0, "EstimatedDopplerHz", NaN);
    r.DopplerHz_error = localValue(r0, "DopplerError_Hz", NaN);
    r.TimingOffset_samples_injected = localValue(r0, "InjectedTimingOffset_samples", NaN);
    r.TimingOffset_samples_estimated = localValue(r0, "EstimatedTimingOffset_PreCorrection_samples", NaN);
    r.TimingError_samples = localValue(r0, "TimingError_samples", NaN);
    r.CFO_Hz_injected = localValue(r0, "InjectedCFO_Hz", NaN);
    r.CFO_Hz_estimated = localValue(r0, "EstimatedCFO_Hz", NaN);
    r.ResidualCFO_Hz = localValue(r0, ["ResidualCFO_PostCorrection_Hz","ResidualCFO_Hz"], NaN);
    r.ICI_Power_dB_approx = NaN;
    r.IQGainImbalance_dB = localValue(r0, "ConfiguredIQGainImbalance_dB", NaN);
    r.IQPhaseImbalance_deg = localValue(r0, "ConfiguredIQPhaseImbalance_deg", NaN);
    r.ImageRejection_dB = localValue(r0, "IQImbalanceImageRejection_dB", NaN);
    r.ChannelConditionNumber_dB = localValue(r0, "ConditionNumber_dB", NaN);
    r.ChannelFrobenius_norm = NaN;
    r.PostEqSINR_dB = localValue(r0, ["PostEqSINR_dB","PostEqSINRWidebanddB"], NaN);
    r.MMSE_gain_dB = NaN;
    r.ChannelCoherence_slots = NaN;
    r.ChannelFading_Applied = localValue(r0, "ChannelFadingApplied", NaN);
    rows{end+1, 1} = r; %#ok<AGROW>
end
end

function T = localBuildControlPlaneTimeline(trialData)
rows = cell(0, 1);
idx = 0;
% PDCCH rows
for i = 1:height(trialData.pdcch)
    idx = idx + 1;
    rows{end+1, 1} = localControlRow(idx, trialData.pdcch(i,:), "PDCCH"); %#ok<AGROW>
end
for i = 1:height(trialData.pucch)
    idx = idx + 1;
    rows{end+1, 1} = localControlRow(idx, trialData.pucch(i,:), "PUCCH"); %#ok<AGROW>
end
for i = 1:height(trialData.prach)
    idx = idx + 1;
    rows{end+1, 1} = localControlRow(idx, trialData.prach(i,:), "PRACH_RACH"); %#ok<AGROW>
end
T = localStructRowsToTable(rows, localControlVars());
end

function r = localControlRow(idx, r0, eventType)
r = struct();
r.EventIndex = idx;
r.Frame = localValue(r0, "Frame", NaN);
r.Slot = localValue(r0, "Slot", NaN);
r.Timestamp_ms = localValue(r0, "Slot", NaN) * 0.5;
r.EventType = string(eventType);
r.UEIndex = localValue(r0, ["UEIndex","UEID","UEId"], NaN);
r.RNTI = localValue(r0, "RNTI", NaN);
r.Direction = string(localValue(r0, ["Direction","TrialDirection","LinkDirection"], ""));
r.Status = string(localValue(r0, ["Status","CRCOutcome","DetectionOutcome"], ""));
r.Payload_bits = localValue(r0, ["Payload_bits","ExpectedBitCount","TBSBits","Msg3TBS"], NaN);
r.MCS = localValue(r0, ["MCS","MCSIndex","Msg3MCS"], NaN);
r.PRBStart = localValue(r0, ["PRBStart","Msg3PUSCHPRBStart"], NaN);
r.PRBCount = localValue(r0, ["PRBCount","AllocatedPRBCount","Msg3PUSCHNumPRB"], NaN);
r.Layers = localValue(r0, ["Layers","Rank"], NaN);
r.TBSBits = localValue(r0, ["TBSize_bits","TBSBits","Msg3TBS"], NaN);
r.HARQ_ID = localValue(r0, ["HARQ_ID","HARQProcessID"], NaN);
r.NDI = localValue(r0, "NDI", NaN);
r.RV = localValue(r0, ["RV","HARQ_RV"], NaN);
r.DCI_Format = string(localValue(r0, ["DCI_Format","Msg2DCIFormat"], ""));
r.AggregationLevel = localValue(r0, "AggregationLevel", NaN);
r.CCE_Index = localValue(r0, "CCE_Index", NaN);
r.CandidateCount = localValue(r0, ["CandidateCount","Msg2PDCCHCandidatesAttempted"], NaN);
r.PUCCH_Format = string(localValue(r0, ["PUCCHFormat","ResolvedFormat"], ""));
r.UCI_ACK = localValue(r0, ["ObservedAck","ExpectedAck"], NaN);
r.UCI_CQI = localValue(r0, "UCI_CQI", NaN);
r.UCI_PMI = localValue(r0, "UCI_PMI", NaN);
r.UCI_RI = localValue(r0, "UCI_RI", NaN);
r.PRACH_RootSeq = localValue(r0, "PRACHRootSequenceIndex", NaN);
r.PRACH_ZeroCorr = localValue(r0, "PRACHZeroCorrelationZone", NaN);
r.PreambleDetected = localValue(r0, "PreambleDetected", NaN);
r.TimingAdvance_us = localValue(r0, "TimingAdvance_us", NaN);
r.RA_Stage = string(localValue(r0, "RAStage", ""));
r.RAR_Decoded = localValue(r0, "RAPIDDecoded", NaN);
r.Msg3_Pass = localValue(r0, "Msg3PUSCHCrcPass", NaN);
r.Msg4_Pass = localValue(r0, "Msg4PDSCHCrcPass", NaN);
r.BeamIndex = localValue(r0, ["SelectedBeamIndex","BeamIndex"], NaN);
r.BeamSwitchFlag = NaN;
r.SRS_NMSE_dB = localValue(r0, "SRS_NMSE_dB", NaN);
r.TRS_TrackingState = string(localValue(r0, "TRSValidityState", ""));
end

function T = localBuildNMSEVsMeasuredSINR(trialData)
rows = [localMetricVsMeasuredSINRRows(trialData.dl, "DL", "NMSE_dB"); localMetricVsMeasuredSINRRows(trialData.ul, "UL", "NMSE_dB")];
T = localStructRowsToTable(rows, ["Direction","PostEqSINR_dB","MetricName","MetricValue","SampleCount","EvidenceClass","SourceArtifact"]);
end

function rows = localMetricVsMeasuredSINRRows(Tin, direction, metric)
rows = cell(0, 1);
if isempty(Tin) || height(Tin) == 0 || ~any(string(Tin.Properties.VariableNames) == metric)
    return;
end
sinrVals = localColumnFirstAvailable(Tin, ["PostEqSINR_dB","MeasuredSINR_dB","MeasuredTrialSINR_dB"]);
sinrVals = round(double(sinrVals), 1);
uniqueSINR = unique(sinrVals(isfinite(sinrVals)));
for i = 1:numel(uniqueSINR)
    sub = Tin(sinrVals == uniqueSINR(i), :);
    r = struct("Direction", string(direction), "PostEqSINR_dB", uniqueSINR(i), "MetricName", string(metric), ...
        "MetricValue", localMean(sub, metric), "SampleCount", height(sub), ...
        "EvidenceClass", "RUNTIME_DERIVED", "SourceArtifact", string(direction) + "_trial_rows");
    rows{end+1, 1} = r; %#ok<AGROW>
end
end

function T = localBuildEnergyVsThroughput(trialData)
goodBits = localSum(trialData.dl, "GoodBits") + localSum(trialData.ul, "GoodBits");
energyJ = localSum(trialData.power, ["Energy_J","TotalEnergy_J","CumulativeEnergy_J"]);
if energyJ == 0
    energyJ = NaN;
end
dlGoodput = localMean(trialData.dl, "Goodput_Mbps");
ulGoodput = localMean(trialData.ul, "Goodput_Mbps");
goodputMbps = localFiniteSum([dlGoodput; ulGoodput]);
postEqSINRDb = localFirstFinite([localMean(trialData.dl, ["PostEqSINR_dB","MeasuredSINR_dB","MeasuredTrialSINR_dB"]); ...
    localMean(trialData.ul, ["PostEqSINR_dB","MeasuredSINR_dB","MeasuredTrialSINR_dB"])], NaN);
energyPerBit = localSafeDivide(energyJ, goodBits);
r = struct("GoodBits", goodBits, "Energy_J", energyJ, ...
    "EnergyPerBit_J", energyPerBit, ...
    "Goodput_Mbps", goodputMbps, ...
    "PostEqSINR_dB", postEqSINRDb, ...
    "Direction", "DL+UL", ...
    "goodput_mbps", goodputMbps, ...
    "energy_per_bit_j", energyPerBit, ...
    "energy_j", energyJ, ...
    "successful_bits", goodBits, ...
    "EvidenceClass", "RUNTIME_DERIVED", ...
    "Status", string(localAvailabilityStatus(isfinite(energyJ), "energy_runtime_source_missing")));
T = struct2table(r, "AsArray", true);
end

function T = localBuildTBSReferenceComparison(trialData)
rows = [localTBSRows(trialData.dl, "DL"); localTBSRows(trialData.ul, "UL")];
T = localStructRowsToTable(rows, ["Direction","Frame","Slot","UEIndex","RNTI","MCS","PRBs","Layers","Modulation","TBSize_DUT","TBSize_Reference","TBSize_Delta","TBSMatch","RateMatchedBits_DUT","RateMatchedBits_Reference","RateMatchedBits_Delta","EvidenceClass","Status"]);
end

function rows = localTBSRows(Tin, direction)
rows = cell(0, 1);
qm = containers.Map(["BPSK","QPSK","16QAM","64QAM","256QAM"], [1,2,4,6,8]);
for i = 1:height(Tin)
    r0 = Tin(i, :);
    modName = upper(string(localValue(r0, "Modulation", "")));
    if isKey(qm, modName)
        q = qm(modName);
    else
        q = NaN;
    end
    dataRE = localValue(r0, "DataRECountPerLayer", NaN);
    if ~isfinite(dataRE)
        dataRE = localValue(r0, "DataRECount", NaN);
    end
    layers = localValue(r0, ["Layers","Rank"], NaN);
    rmRef = localValue(r0, "ComputedE_TS38212", NaN);
    if ~isfinite(rmRef)
        rmRef = dataRE * q * layers;
    end
    rmDut = localValue(r0, "RateMatchedBits", NaN);
    r = struct();
    r.Direction = string(direction);
    r.Frame = localValue(r0, "Frame", NaN);
    r.Slot = localValue(r0, "Slot", NaN);
    r.UEIndex = localValue(r0, ["UEIndex","UEID"], NaN);
    r.RNTI = localValue(r0, "RNTI", NaN);
    r.MCS = localValue(r0, ["MCS","MCSIndex"], NaN);
    r.PRBs = localValue(r0, ["AllocatedPRBCount","PRBs"], NaN);
    r.Layers = layers;
    r.Modulation = string(modName);
    r.TBSize_DUT = localValue(r0, ["TBSize_bits","TBSBits"], NaN);
    r.TBSize_Reference = NaN;
    r.TBSize_Delta = NaN;
    r.TBSMatch = NaN;
    r.RateMatchedBits_DUT = rmDut;
    r.RateMatchedBits_Reference = rmRef;
    r.RateMatchedBits_Delta = rmDut - rmRef;
    r.EvidenceClass = "RUNTIME_DERIVED";
    r.Status = "rate_matched_reference_only_nrTBS_not_recomputed";
    rows{end+1, 1} = r; %#ok<AGROW>
end
end

function T = localBuildShannonCapacityGap(trialData, scenarioCfg)
bandwidthHz = localCfgValue(scenarioCfg, ["global_radio_scope.channel_bandwidth_hz","frequency.bandwidthHz","carrier.bandwidth_hz"], 100e6);
layers = localFirstFinite([localMean(trialData.dl, ["Layers","Rank"]); 1], 1);
postEqSINRDb = localFirstFinite([localMean(trialData.dl, ["PostEqSINR_dB","MeasuredSINR_dB","MeasuredTrialSINR_dB"]); localMean(trialData.ul, ["PostEqSINR_dB","MeasuredSINR_dB","MeasuredTrialSINR_dB"])], NaN);
if isfinite(postEqSINRDb)
    shannonMbps = layers * log2(1 + 10^(postEqSINRDb/10)) * bandwidthHz / 1e6;
else
    shannonMbps = NaN;
end
dlGoodput = localMean(trialData.dl, "Goodput_Mbps");
r = struct("Direction", "DL", "PostEqSINR_dB", postEqSINRDb, "Layers", layers, ...
    "Bandwidth_Hz", bandwidthHz, "ShannonCapacity_Mbps", shannonMbps, ...
    "AchievedGoodput_Mbps", dlGoodput, "Gap_Mbps", shannonMbps - dlGoodput, ...
    "EvidenceClass", "RUNTIME_DERIVED", "Status", "reference_capacity_not_conformance_claim");
T = struct2table(r, "AsArray", true);
end

function T = localBuildTRSDopplerErrorTrace(trialData)
if ~isempty(trialData.trs) && height(trialData.trs) > 0
    src = trialData.trs;
    sourceArtifact = "trs_trials";
    rows = localDopplerRows(src, sourceArtifact);
else
    rows = [localDopplerRows(trialData.dl, "dl_pdsch_trials"); localDopplerRows(trialData.ul, "ul_pusch_trials")];
end
T = localStructRowsToTable(rows, ["Frame","Slot","UEIndex","InjectedDoppler_Hz","EstimatedDoppler_Hz","DopplerError_Hz","EvidenceClass","SourceArtifact"]);
end

function rows = localDopplerRows(src, sourceArtifact)
rows = cell(0, 1);
for i = 1:height(src)
    r0 = src(i, :);
    r = struct();
    r.Frame = localValue(r0, "Frame", NaN);
    r.Slot = localValue(r0, "Slot", NaN);
    r.UEIndex = localValue(r0, ["UEIndex","UEID"], NaN);
    r.InjectedDoppler_Hz = localValue(r0, ["InjectedDoppler_Hz","DopplerHz"], NaN);
    r.EstimatedDoppler_Hz = localValue(r0, "EstimatedDopplerHz", NaN);
    r.DopplerError_Hz = localValue(r0, "DopplerError_Hz", NaN);
    r.EvidenceClass = "RUNTIME_DERIVED";
    r.SourceArtifact = string(sourceArtifact);
    rows{end+1, 1} = r; %#ok<AGROW>
end
end

function T = localStructRowsToTable(rows, vars)
vars = cellstr(string(vars));
if isempty(rows)
    T = cell2table(cell(0, numel(vars)), "VariableNames", vars);
    return;
end
S = vertcat(rows{:});
T = struct2table(S, "AsArray", true);
for i = 1:numel(vars)
    if ~any(string(T.Properties.VariableNames) == string(vars{i}))
        T.(vars{i}) = repmat(missing, height(T), 1);
    end
end
T = T(:, vars);
end

function T = localRowsBySlot(Tin, slot)
T = Tin;
if isempty(Tin) || height(Tin) == 0 || ~any(string(Tin.Properties.VariableNames) == "Slot")
    return;
end
x = localToDouble(Tin.Slot);
T = Tin(x == slot, :);
end

function tf = localHasSlot(Tin, slot)
tf = false;
if isempty(Tin) || height(Tin) == 0 || ~any(string(Tin.Properties.VariableNames) == "Slot")
    return;
end
tf = any(localToDouble(Tin.Slot) == slot);
end

function x = localColumn(T, name)
if isempty(T) || height(T) == 0 || ~any(string(T.Properties.VariableNames) == string(name))
    x = zeros(0, 1);
else
    x = localToDouble(T.(name));
end
end

function x = localColumnFirstAvailable(T, names)
x = NaN(height(T), 1);
for name = string(names)
    if any(string(T.Properties.VariableNames) == name)
        xi = localToDouble(T.(name));
        mask = ~isfinite(x) & isfinite(xi);
        x(mask) = xi(mask);
    end
end
end

function value = localValue(T, names, defaultValue)
value = defaultValue;
if isempty(T) || height(T) == 0
    return;
end
for name = string(names)
    if any(string(T.Properties.VariableNames) == name)
        v = T.(name);
        if iscell(v)
            v = v{1};
        else
            v = v(1);
        end
        if isnumeric(v) || islogical(v)
            value = double(v);
        elseif isstring(v) || ischar(v)
            s = string(v);
            x = str2double(s);
            if isfinite(x)
                value = x;
            else
                value = s;
            end
        else
            value = v;
        end
        return;
    end
end
end

function value = localMean(T, names)
value = NaN;
if isempty(T) || height(T) == 0
    return;
end
for name = string(names)
    if any(string(T.Properties.VariableNames) == name)
        x = localToDouble(T.(name));
        x = x(isfinite(x));
        if ~isempty(x)
            value = mean(x);
            return;
        end
    end
end
end

function value = localSum(T, names)
value = 0;
if isempty(T) || height(T) == 0
    return;
end
found = false;
for name = string(names)
    if any(string(T.Properties.VariableNames) == name)
        x = localToDouble(T.(name));
        value = sum(x(isfinite(x)));
        found = true;
        return;
    end
end
if ~found
    value = 0;
end
end

function value = localFirstFinite(values, defaultValue)
value = defaultValue;
for i = 1:numel(values)
    if isfinite(values(i))
        value = values(i);
        return;
    end
end
end

function value = localFiniteSum(values)
values = values(isfinite(values));
if isempty(values)
    value = NaN;
else
    value = sum(values);
end
end

function y = localSafeDivide(a, b)
if ~isfinite(a) || ~isfinite(b) || b == 0
    y = NaN;
else
    y = a ./ b;
end
end

function n = localPassCount(T)
n = 0;
if isempty(T) || height(T) == 0 || ~any(string(T.Properties.VariableNames) == "CRCPass")
    return;
end
s = lower(strtrim(string(T.CRCPass)));
n = sum(s == "1" | s == "true" | s == "pass");
end

function n = localFailCount(T)
n = 0;
if isempty(T) || height(T) == 0 || ~any(string(T.Properties.VariableNames) == "CRCPass")
    return;
end
s = lower(strtrim(string(T.CRCPass)));
n = sum(s == "0" | s == "false" | s == "fail");
end

function tf = localAnyTrue(T, name)
tf = false;
if isempty(T) || height(T) == 0 || ~any(string(T.Properties.VariableNames) == string(name))
    return;
end
s = lower(strtrim(string(T.(name))));
tf = any(s == "1" | s == "true" | s == "yes" | s == "pass");
end

function mbps = localGoodputMbps(T)
if isempty(T) || height(T) == 0
    mbps = NaN;
    return;
end
mbps = localMean(T, "Goodput_Mbps");
end

function dt = localSlotDurationMs(trialData)
dt = NaN;
if isfield(trialData, "scenario_summary") && ~isempty(trialData.scenario_summary) && height(trialData.scenario_summary) > 0
    dt = localValue(trialData.scenario_summary(1,:), "SlotDuration_ms", NaN);
end
if ~isfinite(dt)
    dt = 0.5;
end
end

function x = localToDouble(v)
if isnumeric(v) || islogical(v)
    x = double(v);
elseif iscell(v)
    x = str2double(string(v));
else
    x = str2double(string(v));
end
x = x(:);
end

function value = localCfgValue(cfg, paths, defaultValue)
value = defaultValue;
for p = string(paths)
    try
        v = sixgr.util.structGet(cfg, p, NaN);
        x = str2double(string(v));
        if isnumeric(v) && isscalar(v)
            x = double(v);
        end
        if isfinite(x)
            value = x;
            return;
        end
    catch
    end
end
end

function [lo, hi] = localWilsonCI(fails, total)
if ~isfinite(total) || total <= 0
    lo = NaN;
    hi = NaN;
    return;
end
z = 1.96;
p = localSafeDivide(fails, total);
den = 1 + z^2 / total;
center = (p + z^2 / (2 * total)) / den;
half = z * sqrt((p * (1 - p) / total) + (z^2 / (4 * total^2))) / den;
lo = max(0, center - half);
hi = min(1, center + half);
end

function status = localAvailabilityStatus(tf, missingReason)
if tf
    status = "derived_from_runtime_rows";
else
    status = string(missingReason);
end
end

function vars = localPerSlotVars()
vars = ["Slot","Frame","Timestamp_ms","TDDPattern","DLActive","ULActive","SpecialSlotActive", ...
    "DL_GrantCount","UL_GrantCount","DL_TotalPRBs","UL_TotalPRBs","DL_TotalTBSBits","UL_TotalTBSBits", ...
    "DL_SuccessCount","DL_FailCount","DL_BLER","UL_BLER","DL_Goodput_Mbps","UL_Goodput_Mbps", ...
    "DL_MeanMCS","UL_MeanMCS","DL_MeanLayers","UL_MeanLayers","DL_MeanPostEqSINR_dB","UL_MeanPostEqSINR_dB", ...
    "DL_PRBEfficiency","UL_PRBEfficiency","HARQ_FeedbackDue","HARQ_ACK_Received","HARQ_NACK_Received", ...
    "Beamforming_Applied","BeamSwitchEvent","SRS_Measured","TRS_Updated","CFO_Residual_Hz","TimingError_samples"];
end

function vars = localPerUEVars()
vars = ["UEIndex","RNTI","Slot","Frame","Direction","MCS","PRBs","TBSBits","Layers","Modulation","CodeRate", ...
    "BLER","BER","Goodput_Mbps","Throughput_Mbps","PostEqSINR_dB","ChannelGain_dB","MeasuredSINR_dB", ...
    "WidebandCQI","PMI","RankIndicator","SelectedBeamIndex","BestBeamIndex","BeamHit","BeamGainGap_dB","ConditionNumber_dB", ...
    "PAPR_dB","EVM_rms","NMSE_dB","DecoderIterations","DecoderComplexity","DecodeLatency_ms", ...
    "InjectedDoppler_Hz","EstimatedDoppler_Hz","DopplerError_Hz","TimingOffset_samples","TimingError_samples","ResidualCFO_Hz", ...
    "IQImbalanceGain_dB","IQImbalancePhase_deg","ImageRejection_dB","OLLADeltaDb","OLLADeltaMCS", ...
    "OLLAAdjustedMCSBeforeCQICeiling","OLLABaseRequiredSINR_dB","OLLATargetRequiredSINR_dB","OLLAThresholdSource", ...
    "OLLAState","OuterLoopApplied","InnerLoopApplied", ...
    "HARQ_ID","HARQ_RV","IsRetransmission","CombiningEnabled","TBSize_DUT","TBSize_Reference","TBSize_Delta","TBSMatch","StrictOk","TruthStatus"];
end

function vars = localPhysicsVars()
vars = ["TrialIndex","Frame","Slot","Timestamp_ms","UEIndex","Direction","PropagationDistance_m","PathLoss_dB","ShadowFading_dB","O2I_dB", ...
    "LargeScaleGain_dB","SmallScaleGain_dB_perSC","TxPower_dBm","RxPower_dBm","NoisePower_dBm","SNR_configured_dB","SNR_applied_dB","NoiseVariance", ...
    "DopplerHz_injected","DopplerHz_estimated","DopplerHz_error","TimingOffset_samples_injected","TimingOffset_samples_estimated","TimingError_samples", ...
    "CFO_Hz_injected","CFO_Hz_estimated","ResidualCFO_Hz","ICI_Power_dB_approx","IQGainImbalance_dB","IQPhaseImbalance_deg","ImageRejection_dB", ...
    "ChannelConditionNumber_dB","ChannelFrobenius_norm","PostEqSINR_dB","MMSE_gain_dB","ChannelCoherence_slots","ChannelFading_Applied"];
end

function vars = localControlVars()
vars = ["EventIndex","Frame","Slot","Timestamp_ms","EventType","UEIndex","RNTI","Direction","Status","Payload_bits", ...
    "MCS","PRBStart","PRBCount","Layers","TBSBits","HARQ_ID","NDI","RV","DCI_Format","AggregationLevel","CCE_Index","CandidateCount", ...
    "PUCCH_Format","UCI_ACK","UCI_CQI","UCI_PMI","UCI_RI","PRACH_RootSeq","PRACH_ZeroCorr","PreambleDetected","TimingAdvance_us", ...
    "RA_Stage","RAR_Decoded","Msg3_Pass","Msg4_Pass","BeamIndex","BeamSwitchFlag","SRS_NMSE_dB","TRS_TrackingState"];
end

function mustBeTextScalar(x)
if ~(ischar(x) || (isstring(x) && isscalar(x)))
    error("sixgr:analytics:buildScenarioAnalyticsTables:BadRunDir", "runDir must be a char vector or string scalar.");
end
end
