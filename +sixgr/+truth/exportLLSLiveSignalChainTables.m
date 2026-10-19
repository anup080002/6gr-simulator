function artifacts = exportLLSLiveSignalChainTables(runFolder, trialT, constellationT, meta)
%EXPORTLLSLIVESIGNALCHAINTABLES Publish compact live signal-chain preview tables.

if nargin < 2 || ~istable(trialT)
    trialT = table();
end
if nargin < 3 || ~istable(constellationT)
    constellationT = table();
end
if nargin < 4 || ~isstruct(meta)
    meta = struct();
end

layout = sixgr.report.resultLayout(runFolder);
artifacts = struct();
artifacts.WaveformPreviewPath = fullfile(layout.ReportCSVDir, "live_waveform_preview.csv");
artifacts.ModulationTracePath = fullfile(layout.ReportCSVDir, "live_modulation_demodulation_trace.csv");
artifacts.ChannelEstimationTracePath = fullfile(layout.ReportCSVDir, "live_channel_estimation_tti.csv");
artifacts.ChannelStateTracePath = fullfile(layout.ReportCSVDir, "live_channel_state_tti.csv");
artifacts.StageTracePath = fullfile(layout.ReportCSVDir, "live_tx_rx_stage_trace.csv");

waveformT = sixgr.util.structGet(meta, "WaveformPreviewTable", table());
% Live previews are bounded; a final snapshot must not silently discard
% earlier sweep points or users. This retains measured rows, never fills gaps.
if ~logical(sixgr.util.structGet(meta, "FinalSnapshot", false))
    waveformT = localTailTable(waveformT, 4096);
    trialT = localTailTable(trialT, 2048);
    constellationT = localTailTable(constellationT, 4096);
end
moddemT = localBuildModulationDemodTable(trialT, constellationT);
channelEstT = localBuildChannelEstimationTable(trialT);
channelStateT = localBuildChannelStateTable(trialT);
stageTraceT = localBuildTxRxStageTraceTable(trialT);

% Compact receiver tables follow raw-trial publication, independently of
% expensive waveform/figure refreshes. Do not erase the previous waveform
% preview when this call is only updating the measured receiver tables.
if logical(sixgr.util.structGet(meta,"WriteWaveformPreview",true))
    sixgr.util.csvWriteTable(artifacts.WaveformPreviewPath, waveformT, ...
        'PreserveSchema',true,'RoundTripNumericText',true);
end
sixgr.util.csvWriteTable(artifacts.ModulationTracePath, moddemT);
sixgr.util.csvWriteTable(artifacts.ChannelEstimationTracePath, channelEstT, ...
    'PreserveSchema',true,'RoundTripNumericText',true);
sixgr.util.csvWriteTable(artifacts.ChannelStateTracePath, channelStateT);
sixgr.util.csvWriteTable(artifacts.StageTracePath, stageTraceT);

artifacts.WaveformPreview = waveformT;
artifacts.ModulationTrace = moddemT;
artifacts.ChannelEstimationTrace = channelEstT;
artifacts.ChannelStateTrace = channelStateT;
artifacts.StageTrace = stageTraceT;
end

function T = localBuildModulationDemodTable(trialT, constellationT)
fields = [ ...
    "Direction","SFN","ConfiguredSNR_dB","ConfiguredSNRSource","SNRValueRole","SNR_dB", ...
    "SystemLevelSINR_dB","SystemLevelSINRSource","SystemLevelSINRValueRole","SystemLevelSINRValueStatus", ...
    "ReceiverHestSINR_dB","ReceiverHestSINRSource","ReceiverHestSINRValueRole","ReceiverHestSINRValueStatus","ReceiverHestSINRNAReason", ...
    "PostEqSINR_dB","PostEqSINRSource","PostEqSINRValueRole","PostEqSINRValueStatus","PostEqSINRNAReason","PostEqSINRPerLayer_dB", ...
    "EVMProxySINR_dB","EVMProxySINRSource","EVMProxySINRValueRole","EVMProxySINRValueStatus","EVMProxySINRNAReason", ...
    "DecoderTruthProxySINR_dB","DecoderTruthProxySINRSource","DecoderTruthProxySINRValueRole","DecoderTruthProxySINRValueStatus","DecoderTruthProxySINRNAReason", ...
    "SINRValueRole","SINRSource","SINRValueStatus","SINRValueDefinition", ...
    "MeasuredTrialSINR_dB","MeasuredTrialSINRSource","MeasuredTrialSINRValueRole","MeasuredTrialSINRValueStatus","MeasuredTrialSINRNAReason","SINRMeasurementDomain","PowerReferencePlane", ...
    "DopplerHz","DopplerSourceMode","DopplerValueRole","UEID","UEIndex","RNTI","BaseStationID","Frame","Slot","AllocatedPRBCount","PRBStart", ...
    "Modulation","MCS","MCSIndex","TargetCodeRate","Layers","Rank","WidebandCQI","CQIDerivedMCS", ...
    "CQIDerivedModulation","CQIDerivedTargetCodeRate","MCSAuthority","ModulationAuthority","GrantOperatingPointSource","AppliedOperatingPointSource","BitErrors","BitsCompared", ...
    "SymbolErrors","SymbolsCompared","SymbolErrorRate","EVM_rms","LLRMeanAbs", ...
    "LLRStdAbs","LLRImbalance","Status"];
T = localProjectTable(trialT, fields);
if ~isempty(T)
    [T.ConstellationSamples,T.ConstellationSampleCountStatus] = ...
        localConstellationCounts(trialT,constellationT);
    T.ConstellationSampleCountScope = repmat( ...
        "retained_input_rows_not_full_capture_coverage",height(T),1);
end
T = localEnsureNonEmpty(T, [fields "ConstellationSamples"]);
if isempty(T)
    T.ConstellationSampleCountStatus = strings(0,1);
    T.ConstellationSampleCountScope = strings(0,1);
end
T = sixgr.truth.canonicalizeLLSLiveSignalChainTable("modulation_demodulation", T);
end

function [counts,status] = localConstellationCounts(trials,samples)
% Count the supplied rows, never infer the complete archive population from
% a bounded live preview. The original producer tables own join identities;
% projected NaN/default columns must not manufacture a match.
counts=nan(height(trials),1);
status=repmat("unavailable_constellation_identity",height(trials),1);
if isempty(samples)
    counts(:)=0; status(:)="no_retained_constellation_input_rows"; return;
end
tn=string(trials.Properties.VariableNames); sn=string(samples.Properties.VariableNames);
common=intersect(tn,sn);
ue=["UEIndex","UEID","RNTI"]; ue=ue(ismember(ue,common));
snr=["ConfiguredSNR_dB","SNR_dB"]; snr=snr(ismember(snr,common));
if isempty(ue) || isempty(snr) || ~all(ismember(["Direction","Frame","Slot"],common))
    return;
end
required=["Direction","Frame","Slot",ue(1),snr(1)];
optional=["SweepPointIndex","SourceRunID","RealizationIndex","Seed", ...
    "TransmissionAttemptID","LogicalTBID","SessionEpoch","ConfigurationEpoch"];
for i=1:height(trials)
    keys=required; valid=true;
    for key=required
        valid=valid && sixgr.truth.measurementValuePresent(trials.(key)(i,:));
    end
    if ~valid, continue; end
    for key=optional
        if ismember(key,tn) && sixgr.truth.measurementValuePresent(trials.(key)(i,:))
            if ~ismember(key,sn), valid=false; break; end
            keys(end+1)=key; %#ok<AGROW>
        end
    end
    if ~valid, continue; end
    mask=true(height(samples),1); owners=true(height(trials),1);
    for key=keys
        value=trials.(key)(i,:);
        if ~ismember(key,required) && any(mask & ~sixgr.truth.measurementValuePresent(samples.(key)))
            valid=false; break;
        end
        mask=mask & localIdentityMatch(samples.(key),value);
        owners=owners & localIdentityMatch(trials.(key),value);
    end
    if ~valid, continue; end
    if sum(owners)~=1
        status(i)="ambiguous_trial_identity"; continue;
    end
    % A source-only key spanning multiple values cannot be collapsed into a
    % trial with no such identity, even if there is just one trial row.
    for key=optional(~ismember(optional,keys))
        if ismember(key,sn) && any(mask)
            values=samples.(key)(mask,:);
            present=sixgr.truth.measurementValuePresent(values);
            if any(present) && (~all(present) || size(unique(values(present,:),'rows'),1)>1)
                valid=false; break;
            end
        end
    end
    if ~valid
        status(i)="ambiguous_constellation_identity"; continue;
    end
    counts(i)=sum(mask); status(i)="counted_retained_rows_for_unique_trial";
end
end

function mask = localIdentityMatch(column,value)
if isnumeric(column) && isnumeric(value)
    mask=all(double(column)==double(value),2);
else
    mask=all(string(column)==string(value),2);
end
mask=mask & sixgr.truth.measurementValuePresent(column);
end

function T = localBuildChannelEstimationTable(trialT)
fields = [ ...
    "ScenarioID","ConfigHash","RunnerProfile","Direction","SFN","ConfiguredSNR_dB","SNR_dB", ...
    "ReceiverHestSINR_dB","ReceiverHestSINRSource","PostEqSINR_dB","PostEqSINRSource", ...
    "MeasuredTrialSINR_dB","MeasuredTrialSINRSource","SINRMeasurementDomain","PowerReferencePlane","DopplerHz","UEID","UEIndex","RNTI", ...
    "BaseStationID","Frame","Slot","AllocatedPRBCount","PRBStart","MCSIndex","Layers","Rank", ...
    "NMSE_dB","NMSESource","ChannelEstimateCaptureStatus","ChannelEstimateReferencePlane", ...
    "ChannelEstimateObservationID", ...
    "ChannelEstimateReferenceUsedByReceiver","ChannelEstimateComparedValues", ...
    "ChannelEstimateResourcesCSV","ChannelEstimateResourcesCSVSHA256", ...
    "ChannelEstimateMATFile","ChannelEstimateMATFileSHA256", ...
    "PilotReconstructionResidualRatio_dB", ...
    "DetectionMetric","ChannelGain_dB","NoiseVariance","TimingOffset_samples","TimingEstimateUsed","UseIdealTimingSync","RankEstimate","ConditionNumber_dB", ...
    "EstimatedDopplerHz","PhaseTrackingError_deg","QCLAccuracy","Status"];
T = localEnsureNonEmpty(localProjectTable(trialT, fields), fields);
if isempty(T)
    T.NMSEDefinition = strings(0, 1);
    T.NMSEInterpretation = strings(0, 1);
    return;
end
% A pilot-reconstruction residual is not independent channel-estimate NMSE.
% Preserve the receiver/scorer's reference identity instead of relabeling
% every numeric value using the old residual definition.
T.NMSEDefinition = repmat("unavailable_reference_definition_not_recorded", height(T), 1);
T.NMSEInterpretation = repmat("unavailable_independent_channel_reference", height(T), 1);
nmse = nan(height(T), 1);
try
    nmse = double(T.NMSE_dB);
catch
end
observed = isfinite(nmse) | (isinf(nmse) & nmse < 0);
T.NMSEInterpretation(observed) = "unverified_channel_reference_provenance";
scored = observed & string(T.ChannelEstimateCaptureStatus)=="measured_and_independently_scored_after_reception" & ...
    ~ismissing(string(T.NMSESource)) & strlength(string(T.NMSESource))>0 & string(T.NMSESource)~="NaN" & ...
    ~ismissing(string(T.ChannelEstimateReferencePlane)) & strlength(string(T.ChannelEstimateReferencePlane))>0 & ...
    string(T.ChannelEstimateReferencePlane)~="NaN" & ...
    double(T.ChannelEstimateReferenceUsedByReceiver)==0 & double(T.ChannelEstimateComparedValues)>0;
T.NMSEDefinition(scored) = "10log10(sum_abs_Hest_minus_Href_squared_over_sum_abs_Href_squared)";
T.NMSEInterpretation(scored) = "independent_post_decode_channel_error_on_retained_reference_resources_not_pilot_reconstruction_residual";
T = sixgr.truth.canonicalizeLLSLiveSignalChainTable("channel_estimation", T);
end

function T = localBuildChannelStateTable(trialT)
fields = [ ...
    "Direction","SFN","ConfiguredSNR_dB","ConfiguredSNRSource","SNRValueRole","AppliedAWGNSNR_dB","SNR_dB","UEID","UEIndex","RNTI","BaseStationID","Frame","Slot","AllocatedPRBCount","PRBStart","MCSIndex","Layers","Rank","ChannelModel","DopplerHz","DopplerSourceMode","DopplerValueRole", ...
    "InjectedCFO_Hz","EstimatedCFO_Hz","CFOError_Hz","CFOEstimateAvailability","CFOErrorDefinition","CFOValueStatus","InjectedTimingOffset_samples", ...
    "CFOCorrectionApplied","CFOCorrectionApplied_Hz","ResidualCFO_PostCorrection_Hz", ...
    "ResidualCFO_EstimatedPostCorrection_Hz","ResidualCFOEstimateSource","ResidualCFOEstimateAvailable", ...
    "ResidualCFOEstimateRole","ResidualCFOReusesAcquisitionObservation","ResidualCFOEstimatorConsistency_Hz", ...
    "ResidualCFOEstimateDomain","ResidualCFOReferenceDefinition", ...
    "RawTimingEstimate_samples","AppliedTimingCorrection_samples","TimingEstimateApplicationPolicy","TimingEstimateStatus","TimingEstimateWasClipped", ...
    "TimingError_samples","TimingEstimateUsed","UseIdealTimingSync","TimingEstimateAvailability","TimingErrorDefinition","TimingValueStatus","TimingReferenceSource","TimingMetricRole", ...
    "IQImbalanceConfigured","IQImbalanceApplied","IQImbalanceModel","ConfiguredIQGainImbalance_dB","ConfiguredIQPhaseImbalance_deg", ...
    "IQImbalanceMirrorPowerRatio_dB","IQImbalanceImageRejection_dB","IQImbalanceIQPowerRatio_dB","IQImbalanceIQCorrelation", ...
    "IQImbalanceEstimatedAlphaAbs","IQImbalanceEstimatedBetaAbs","IQImbalanceMeasurementSource","IQImbalanceMeasurementStatus", ...
    "SystemLevelSINR_dB","SystemLevelSINRSource","SystemLevelSINRValueRole","SystemLevelSINRValueStatus","SystemLevelSINRDefinition", ...
    "ReceiverHestSINR_dB","ReceiverHestSINRSource","ReceiverHestSINRValueRole","ReceiverHestSINRValueStatus","ReceiverHestSINRNAReason", ...
    "PostEqSINR_dB","PostEqSINRSource","PostEqSINRValueRole","PostEqSINRValueStatus","PostEqSINRNAReason","PostEqSINRPerLayer_dB", ...
    "EVMProxySINR_dB","EVMProxySINRSource","EVMProxySINRValueRole","EVMProxySINRValueStatus","EVMProxySINRNAReason", ...
    "DecoderTruthProxySINR_dB","DecoderTruthProxySINRSource","DecoderTruthProxySINRValueRole","DecoderTruthProxySINRValueStatus","DecoderTruthProxySINRNAReason", ...
    "SINRValueRole","SINRSource","SINRValueStatus","SINRValueDefinition","MeasuredTrialSINR_dB","MeasuredTrialSINRSource","MeasuredTrialSINRValueRole","MeasuredTrialSINRValueStatus","MeasuredTrialSINRNAReason","SINRMeasurementDomain","PowerReferencePlane", ...
    "LargeScaleSINR_dB","LargeScaleSINRSource","LargeScaleSINRValueRole","LargeScaleSINRValueStatus","LargeScaleSINRFinalizedFlag","LargeScaleSINRNAReason","PrimaryTruthValueStatus","SecondaryFieldGapFlag","SecondaryFieldGapCount","SecondaryFieldGapReason","ServingRSRP_dBm","ServingRSRPSource","CSI_RSRP_dB","CSI_RSRPSource","AppliedLargeScaleGain_dB","AppliedLargeScaleGainSource","InterferenceMode","ResidualInterferencePower_dB", ...
    "InterferenceContributorCount","InterferenceAggregatedRxPower_dBm","InterferencePowerSource","InterferencePowerReferencePlane","FullInterfererChannelTruthUsed", ...
    "ReferenceTxPower_dBm","ReferenceTxPowerSource","ServingRxPower_dBm","ServingRxPowerSource", ...
    "ThermalNoisePower_dBm","NoisePowerSource","NoiseFigure_dB","NoiseBandwidth_Hz", ...
    "PowerContextTotalTxPower_dBm","PowerContextTxGain_dB","PowerContextRxGain_dB","PowerContextAdditionalLoss_dB", ...
    "AbsolutePowerReferencePlane","SamplePowerReferencePlane", ...
    "ConfiguredBeamSelectionStrategy","BeamSelectionStrategy","BeamSelectionAuthority","BeamSelectionPolicyType","BeamSelectionPolicyFixed","SelectedBeamValueRole","SelectedBeamValueStatus","SelectedBeamNAReason","RequestedBeamIndexSet","RequestedBeamValueRole","RequestedBeamValueStatus","RequestedBeamNAReason","PrecoderSource","RequestedPrecoderSource","AppliedPrecoderSource","RequestedPrecoderPMI","PrecodingMode","PrecodingApplicationStage","PrecodingActive","ExplicitBeamWeightsApplied","TransformPrecodingApplied","BeamformingApplied","AppliedBeamIndexSet","AppliedBeamValueRole","AppliedBeamValueStatus","AppliedBeamNAReason","AppliedPrecoderPMI","AppliedPrecoderValueRole","AppliedPrecoderValueStatus","AppliedPrecoderNAReason","ExplicitPrecoderReplayStatus","ExplicitPrecoderReplayBlocker","AppliedPrecoderPMIType","AppliedPrecoderCodebookMode","RequestedVsAppliedPrecoderPMIMatchStatus","PrecodingNumPorts","PrecodingNumLayers","PrecodingMatrixRows","PrecodingMatrixCols", ...
    "InterfererBeamformingAppliedCount","InterfererExplicitBeamWeightCount","InterfererTransformPrecodingCount","InterfererPrecoderSourceSet","InterfererPrecodingModeSet","InterfererBeamIndexSetSummary", ...
    "BSAntennaArrayClass","BSAntennaElementClass","BSAntennaArrayType","BSAntennaRows","BSAntennaCols","BSAntennaElements","BSAntennaPolarization","BSAntennaAzimuth_deg","BSAntennaNumPorts", ...
    "UEAntennaArrayClass","UEAntennaElementClass","UEAntennaArrayType","UEAntennaRows","UEAntennaCols","UEAntennaElements","UEAntennaPolarization","UEAntennaHeading_deg","UEAntennaNumPorts", ...
    "AntennaConfigSource","RuntimeAntennaObjectSource","AntennaRuntimeObjectCreated","AntennaRuntimeObjectValueRole","AntennaRuntimeObjectValueStatus","AntennaRuntimeObjectNAReason","ChannelArrayModel","ChannelObjectSource","ChannelObjectClass","ChannelArrayHandlingStatus","ChannelArrayHandlingBlocker","ChannelGeometryCouplingLevel","GeometryAdapterType","GeometryAdapterSource","GeometryAdapterLimitation","GeometryAdapterPortMapping","ChannelArrayValueRole","ChannelArrayValueStatus","ChannelUsesCountOnlyAntennaModel","ChannelUsesSameRuntimeAntennaAssumptions","InterferenceChannelObjectSource","InterferenceChannelObjectClass","InterferenceChannelArrayHandlingStatus","InterferenceChannelArrayHandlingBlocker","InterferenceChannelArrayValueRole","InterferenceChannelArrayValueStatus","InterferenceUsesSameRuntimeAntennaAssumptions","InterferencePathUsesSameArrayAssumptions", ...
    "PropagationDistance_m","GeometricPropagationDelay_s","DominantPathDelay_s","ChannelFilterDelay_s","PropagationDelay_s","ToD_s","ToA_s","ToAEstimate_s", ...
    "ToDSource","ToASource","ToAEstimateSource","ChannelDelaySource","AntennaGeometrySource","AntennaEvidenceSource","SameFlowEvidenceSource","RuntimeTraceSource", ...
    "ChannelAgingLoss_dB","InterpolationLoss_dB","MismatchSensitivity_dB","RowLifecycleState","PartialRowFlag","FinalizedFlag","FallbackFlag","PlaceholderFlag","NAReason","RunUUID","RunTag","ScenarioID","RunnerProfile","ConfigHash","SourceArtifact","SourceTable","ArtifactClass","SemanticState","CountsTowardCoverage","MachineReadable","HumanReadable","Status"];
T = localEnsureNonEmpty(localProjectTable(trialT, fields), fields);
T = sixgr.truth.canonicalizeLLSLiveSignalChainTable("channel_state", T);
end

function T = localBuildTxRxStageTraceTable(trialT)
fields = [ ...
    "Direction","SFN","ConfiguredSNR_dB","ConfiguredSNRSource","SNRValueRole", ...
    "SystemLevelSINR_dB","SystemLevelSINRSource","SystemLevelSINRValueRole","SystemLevelSINRValueStatus","SystemLevelSINRDefinition", ...
    "ReceiverHestSINR_dB","ReceiverHestSINRSource","ReceiverHestSINRValueRole","ReceiverHestSINRValueStatus","ReceiverHestSINRNAReason", ...
    "PostEqSINR_dB","PostEqSINRSource","PostEqSINRValueRole","PostEqSINRValueStatus","PostEqSINRNAReason","PostEqSINRPerLayer_dB", ...
    "EVMProxySINR_dB","EVMProxySINRSource","EVMProxySINRValueRole","EVMProxySINRValueStatus","EVMProxySINRNAReason", ...
    "DecoderTruthProxySINR_dB","DecoderTruthProxySINRSource","DecoderTruthProxySINRValueRole","DecoderTruthProxySINRValueStatus","DecoderTruthProxySINRNAReason","SINRValueRole","SINRSource","SINRValueStatus","SINRValueDefinition","MeasuredTrialSINR_dB","MeasuredTrialSINRSource","MeasuredTrialSINRValueRole","MeasuredTrialSINRValueStatus","MeasuredTrialSINRNAReason","SINRMeasurementDomain","PowerReferencePlane", ...
    "DopplerHz","DopplerSourceMode","DopplerValueRole","UEID","UEIndex","RNTI","BaseStationID","Frame","Slot","AllocatedPRBCount","PRBStart", ...
    "InjectedCFO_Hz","EstimatedCFO_Hz","CFOError_Hz","InjectedTimingOffset_samples","RawTimingEstimate_samples","AppliedTimingCorrection_samples", ...
    "CFOCorrectionApplied","CFOCorrectionApplied_Hz","ResidualCFO_PostCorrection_Hz", ...
    "ResidualCFO_EstimatedPostCorrection_Hz","ResidualCFOEstimateSource","ResidualCFOEstimateAvailable", ...
    "ResidualCFOEstimateRole","ResidualCFOReusesAcquisitionObservation","ResidualCFOEstimatorConsistency_Hz", ...
    "ResidualCFOEstimateDomain","ResidualCFOReferenceDefinition", ...
    "TimingEstimateApplicationPolicy","TimingEstimateStatus","TimingEstimateWasClipped","TimingError_samples", ...
    "IQImbalanceConfigured","IQImbalanceApplied","IQImbalanceModel","ConfiguredIQGainImbalance_dB","ConfiguredIQPhaseImbalance_deg", ...
    "IQImbalanceMirrorPowerRatio_dB","IQImbalanceImageRejection_dB","IQImbalanceIQPowerRatio_dB","IQImbalanceIQCorrelation", ...
    "IQImbalanceEstimatedAlphaAbs","IQImbalanceEstimatedBetaAbs","IQImbalanceMeasurementSource","IQImbalanceMeasurementStatus", ...
    "ChannelModel","TBSize_bits","TBCRCLength_bits","TBLengthWithCRC_bits","NumCodeBlocks","CodeBlockLength_bits", ...
    "SegmentationOccurred","SegmentationPaddingBits","BaseGraph","EncodedBits","RateMatchedBits","RateMatchPunctureBits","RateMatchRepetitionBits", ...
    "CBCRCBits","CodeBlockInputBits","SegmentationOverheadBits","InherentLDPCPuncturedBits", ...
    "RateMatchEligibleBits","RateMatchUniqueSelectedBits","CodingAccountingVersion","RateMatchAccountingJSON", ...
    "BitErrors","BitsCompared","SymbolErrors","SymbolsCompared","EVM_rms","DataRECount","DMRSRECount","PTRSRECount", ...
    "Layers","PMI","CRI","BeamformingApplied","TimingEstimateUsed","UseIdealTimingSync","NMSE_dB","ConditionNumber_dB", ...
    "ConfiguredBeamSelectionStrategy","BeamSelectionStrategy","BeamSelectionAuthority","BeamSelectionPolicyType","BeamSelectionPolicyFixed","SelectedBeamValueRole","SelectedBeamValueStatus","SelectedBeamNAReason","RequestedBeamIndexSet","RequestedBeamValueRole","RequestedBeamValueStatus","RequestedBeamNAReason","PrecoderSource","RequestedPrecoderSource","AppliedPrecoderSource","RequestedPrecoderPMI","PrecodingMode","PrecodingApplicationStage","PrecodingActive","ExplicitBeamWeightsApplied","TransformPrecodingApplied","AppliedBeamIndexSet","AppliedBeamValueRole","AppliedBeamValueStatus","AppliedBeamNAReason","AppliedPrecoderPMI","AppliedPrecoderValueRole","AppliedPrecoderValueStatus","AppliedPrecoderNAReason","ExplicitPrecoderReplayStatus","ExplicitPrecoderReplayBlocker","AppliedPrecoderPMIType","AppliedPrecoderCodebookMode","RequestedVsAppliedPrecoderPMIMatchStatus","PrecodingNumPorts","PrecodingNumLayers","PrecodingMatrixRows","PrecodingMatrixCols", ...
    "LLRMeanAbs","LLRStdAbs","LLRImbalance","DecoderIterations","CRCPass", ...
    "InterferenceMode","InterferenceContributorCount","InterferenceAggregatedRxPower_dBm","InterferencePowerSource","InterferencePowerReferencePlane","FullInterfererChannelTruthUsed", ...
    "ReferenceTxPower_dBm","ReferenceTxPowerSource","ServingRxPower_dBm","ServingRxPowerSource", ...
    "ThermalNoisePower_dBm","NoisePowerSource","NoiseFigure_dB","NoiseBandwidth_Hz", ...
    "PowerContextTotalTxPower_dBm","PowerContextTxGain_dB","PowerContextRxGain_dB","PowerContextAdditionalLoss_dB", ...
    "AbsolutePowerReferencePlane","SamplePowerReferencePlane", ...
    "InterfererBeamformingAppliedCount","InterfererExplicitBeamWeightCount","InterfererTransformPrecodingCount","InterfererPrecoderSourceSet","InterfererPrecodingModeSet","InterfererBeamIndexSetSummary", ...
    "BSAntennaArrayClass","BSAntennaElementClass","BSAntennaArrayType","BSAntennaRows","BSAntennaCols","BSAntennaElements","BSAntennaPolarization","BSAntennaAzimuth_deg","BSAntennaNumPorts", ...
    "UEAntennaArrayClass","UEAntennaElementClass","UEAntennaArrayType","UEAntennaRows","UEAntennaCols","UEAntennaElements","UEAntennaPolarization","UEAntennaHeading_deg","UEAntennaNumPorts", ...
    "AntennaConfigSource","RuntimeAntennaObjectSource","AntennaRuntimeObjectCreated","AntennaRuntimeObjectValueRole","AntennaRuntimeObjectValueStatus","AntennaRuntimeObjectNAReason","ChannelArrayModel","ChannelObjectSource","ChannelObjectClass","ChannelArrayHandlingStatus","ChannelArrayHandlingBlocker","ChannelGeometryCouplingLevel","GeometryAdapterType","GeometryAdapterSource","GeometryAdapterLimitation","GeometryAdapterPortMapping","ChannelArrayValueRole","ChannelArrayValueStatus","ChannelUsesCountOnlyAntennaModel","ChannelUsesSameRuntimeAntennaAssumptions","InterferenceChannelObjectSource","InterferenceChannelObjectClass","InterferenceChannelArrayHandlingStatus","InterferenceChannelArrayHandlingBlocker","InterferenceChannelArrayValueRole","InterferenceChannelArrayValueStatus","InterferenceUsesSameRuntimeAntennaAssumptions","InterferencePathUsesSameArrayAssumptions", ...
    "PropagationDistance_m","GeometricPropagationDelay_s","DominantPathDelay_s","ChannelFilterDelay_s","PropagationDelay_s","ToD_s","ToA_s","ToAEstimate_s", ...
    "ToDSource","ToASource","ToAEstimateSource","ChannelDelaySource","AntennaGeometrySource","AntennaEvidenceSource","SameFlowEvidenceSource","RuntimeTraceSource", ...
    "GrantContextId","GrantWorkerSafe","GrantSharedStateCommitMode", ...
    "ControlEligible","ControlDecodeOk","GrantControlState","MCSAuthority","ModulationAuthority","GrantOperatingPointSource","AppliedOperatingPointSource","CFOEstimateAvailability","CFOErrorDefinition","CFOValueStatus","TimingEstimateAvailability","TimingErrorDefinition","TimingValueStatus","LargeScaleSINRValueStatus","LargeScaleSINRFinalizedFlag","LargeScaleSINRNAReason","PrimaryTruthValueStatus","SecondaryFieldGapFlag","SecondaryFieldGapCount","SecondaryFieldGapReason","RowLifecycleState","PartialRowFlag","FinalizedFlag","FallbackFlag","PlaceholderFlag","NAReason","RunUUID","RunTag","ScenarioID","RunnerProfile","ConfigHash","SourceArtifact","SourceTable","ArtifactClass","SemanticState","CountsTowardCoverage","MachineReadable","HumanReadable","Status"];
T = localEnsureNonEmpty(localProjectTable(trialT, fields), fields);
if isempty(T)
    T.TxChainKernel = strings(0, 1);
    T.RxChainKernel = strings(0, 1);
    T.StageEvidenceSource = strings(0, 1);
    T.RawTrialTraceSource = strings(0, 1);
    return;
end
txKernel = strings(height(T), 1);
rxKernel = strings(height(T), 1);
traceSource = strings(height(T), 1);
dlMask = upper(strtrim(string(T.Direction))) == "DL";
txKernel(dlMask) = "sixgr.phy.dl.PDSCH_Tx";
rxKernel(dlMask) = "sixgr.phy.dl.PDSCH_Rx";
traceSource(dlMask) = "air_interface/csv/dl_pdsch_trials.csv";
txKernel(~dlMask) = "sixgr.phy.ul.PUSCH_Tx";
rxKernel(~dlMask) = "sixgr.phy.ul.PUSCH_Rx";
traceSource(~dlMask) = "air_interface/csv/ul_pusch_trials.csv";
T.TxChainKernel = txKernel;
T.RxChainKernel = rxKernel;
T.StageEvidenceSource = repmat("derived_from_active_raw_trial_columns", height(T), 1);
T.RawTrialTraceSource = traceSource;
T = sixgr.truth.canonicalizeLLSLiveSignalChainTable("tx_rx_stage_trace", T);
end

function T = localProjectTable(sourceT, fields)
fields = string(fields(:)).';
% Versioned compact diagnostics are propagated only when the producer emitted
% them; no legacy value is converted into newly claimed measured evidence.
extra=[string(fieldnames(sixgr.link.codingAccountingExport())); ...
    string(fieldnames(sixgr.link.modulationDiagnosticsExport())); ...
    "SweepPointIndex";"SourceRunID";"RealizationIndex";"Seed"; ...
    "BSAntennaPanelRows";"BSAntennaPanelCols";"BSAntennaPanelCount"; ...
    "BSAntennaPolarizationAngles_deg"; ...
    "UEAntennaPanelRows";"UEAntennaPanelCols";"UEAntennaPanelCount"; ...
    "UEAntennaPolarizationAngles_deg"; ...
    "TransmissionAttemptID";"LogicalTBID";"SessionEpoch";"ConfigurationEpoch"];
if istable(sourceT)
    extra=extra(ismember(extra,string(sourceT.Properties.VariableNames)));
    fields=unique([fields extra.'],'stable');
end
if ~(istable(sourceT) && ~isempty(sourceT))
    T = table();
    return;
end
vars = string(sourceT.Properties.VariableNames);
for f = fields
    if ~ismember(f, vars)
        sourceT.(char(f)) = localDefaultColumn(height(sourceT), f);
    end
end
T = sourceT(:, cellstr(fields));
end

function T = localEnsureNonEmpty(T, fields)
fields = string(fields(:)).';
if istable(T) && ~isempty(T)
    return;
end
T = table();
for f = fields
    T.(char(f)) = localDefaultColumn(0, f);
end
end

function T = localFinalizeProjectedTraceTable(T, scopeToken)
if ~(istable(T) && ~isempty(T))
    return;
end
scopeToken = lower(regexprep(char(string(scopeToken)), "[^a-z0-9]+", "_"));
T = sixgr.truth.normalizeDisabledInterferenceIdentity(T, string(scopeToken));
names = string(T.Properties.VariableNames);
for i = 1:numel(names)
    fieldName = char(names(i));
    rawCol = T.(fieldName);
    if ~localIsStringLikeColumn(rawCol)
        continue;
    end
    values = string(rawCol);
    blankMask = strlength(strtrim(values)) == 0;
    if ~any(blankMask)
        continue;
    end
    companionMask = localCompanionAvailabilityMask(T, fieldName);
    fillValues = localSemanticFillValues(fieldName, scopeToken, companionMask);
    assignMask = blankMask & strlength(fillValues) > 0;
    if any(assignMask)
        values(assignMask) = fillValues(assignMask);
        T.(fieldName) = values;
    end
end
end

function tf = localIsStringLikeColumn(col)
tf = isstring(col) || ischar(col) || iscell(col) || iscategorical(col);
end

function mask = localCompanionAvailabilityMask(T, fieldName)
nRows = height(T);
mask = false(nRows, 1);
if strcmpi(fieldName, "InterferencePowerSource")
    names = string(T.Properties.VariableNames);
    powerName = names(strcmpi(names, "InterferenceAggregatedRxPower_dBm"));
    if ~isempty(powerName)
        mask = localColumnAvailabilityMask(T.(char(powerName(1))));
    end
    return;
end
base = regexprep(lower(char(string(fieldName))), "(source|valuerole|valuestatus|nareason|definition)$", "");
if strlength(string(base)) == 0
    return;
end
names = string(T.Properties.VariableNames);
for i = 1:numel(names)
    candidate = char(names(i));
    candidateLower = lower(candidate);
    if strcmpi(candidate, fieldName)
        continue;
    end
    if ~strcmp(candidateLower, base) && ~startsWith(candidateLower, base)
        continue;
    end
    if ~isempty(regexp(candidateLower, "(source|valuerole|valuestatus|nareason|definition)$", "once"))
        continue;
    end
    mask = mask | localColumnAvailabilityMask(T.(candidate));
end
end

function mask = localColumnAvailabilityMask(col)
if isnumeric(col)
    mask = isfinite(double(col));
    return;
end
if islogical(col)
    mask = true(numel(col), 1);
    return;
end
try
    vals = string(col);
    mask = strlength(strtrim(vals)) > 0;
catch
    mask = false(numel(col), 1);
end
mask = reshape(logical(mask), [], 1);
end

function fill = localSemanticFillValues(fieldName, scopeToken, companionMask)
nRows = numel(companionMask);
fieldName = lower(char(string(fieldName)));
scope = string(scopeToken);
fill = strings(nRows, 1);
if endsWith(fieldName, "source")
    fill(companionMask) = "active_" + scope + "_runtime_table";
    fill(~companionMask) = "not_emitted_by_active_" + scope + "_runtime";
elseif endsWith(fieldName, "valuerole")
    fill(companionMask) = "runtime_observation";
    fill(~companionMask) = "not_available";
elseif endsWith(fieldName, "valuestatus")
    fill(companionMask) = "available";
    fill(~companionMask) = "not_emitted_by_active_" + scope + "_runtime";
elseif endsWith(fieldName, "nareason") || strcmp(fieldName, "nareason")
    % A reason is producer evidence, not a categorical filler.
    return;
elseif endsWith(fieldName, "definition")
    fill(companionMask) = "derived_from_active_" + scope + "_runtime_table";
    fill(~companionMask) = "not_emitted_by_active_" + scope + "_runtime";
elseif contains(fieldName, "blocker")
    fill(:) = "not_blocked_in_active_" + scope + "_runtime";
elseif contains(fieldName, "limitation")
    fill(:) = "no_additional_" + scope + "_limitation_recorded";
elseif contains(fieldName, "beam") || contains(fieldName, "precoder") || ...
        contains(fieldName, "interferer") || contains(fieldName, "antenna") || ...
        contains(fieldName, "channelarray") || contains(fieldName, "geometryadapter") || ...
        contains(fieldName, "authority") || contains(fieldName, "interference")
    fill(:) = "not_recorded_by_active_" + scope + "_runtime";
end
end

function col = localDefaultColumn(nRows, fieldName)
name = lower(char(string(fieldName)));
if any(strcmp(name,["codingaccountingversion","ratematchaccountingjson"]))
    col=strings(nRows,1); return;
end
if any(strcmp(name,["nmsesource","channelestimatecapturestatus", ...
        "channelestimatereferenceplane","channelestimateresourcescsv", ...
        "channelestimateresourcescsvsha256","channelestimatematfile", ...
        "channelestimatematfilesha256"]))
    col = strings(nRows,1);
    return;
end
    if any(strcmp(name, ["posteqsinrsource","posteqsinrvaluerole","posteqsinrvaluestatus","posteqsinrnareason","posteqsinrperlayer_db","evmproxysinrsource","evmproxysinrvaluerole","evmproxysinrvaluestatus","evmproxysinrnareason"]))
        col = strings(nRows, 1);
    elseif any(strcmp(name, ["direction","modulation","cqiderivedmodulation","status","channelmodel","nmsedefinition","nmseinterpretation","interferencemode","interferencepowersource","configuredsnrsource","snrvaluerole","systemlevelsinrsource","systemlevelsinrvaluerole","systemlevelsinrvaluestatus","systemlevelsinrdefinition","receiverhestsinrsource","receiverhestsinrvaluerole","receiverhestsinrvaluestatus","receiverhestsinrnareason","decodertruthproxysinrsource","decodertruthproxysinrvaluerole","decodertruthproxysinrvaluestatus","decodertruthproxysinrnareason","sinrvaluerole","sinrsource","sinrvaluestatus","sinrvaluedefinition","dopplersourcemode","dopplervaluerole","measuredtrialsinrsource","measuredtrialsinrvaluerole","measuredtrialsinrvaluestatus","measuredtrialsinrnareason","largescalesinrsource","largescalesinrvaluerole","servingrsrpsource","csi_rsrpsource","appliedlargescalegainsource","iqimbalancemodel","iqimbalancemeasurementsource","iqimbalancemeasurementstatus","txchainkernel","rxchainkernel","stageevidencesource","grantcontrolstate","rawtrialtracesource","configuredbeamselectionstrategy","beamselectionstrategy","beamselectionauthority","beamselectionpolicytype","selectedbeamvaluerole","selectedbeamvaluestatus","selectedbeamnareason","requestedbeamindexset","requestedbeamvaluerole","requestedbeamvaluestatus","requestedbeamnareason","precodersource","requestedprecodersource","appliedprecodersource","precodingmode","precodingapplicationstage","appliedbeamindexset","appliedbeamvaluerole","appliedbeamvaluestatus","appliedbeamnareason","appliedprecodervaluerole","appliedprecodervaluestatus","appliedprecodernareason","explicitprecoderreplaystatus","explicitprecoderreplayblocker","appliedprecoderpmitype","appliedprecodercodebookmode","requestedvsappliedprecoderpmimatchstatus","interfererprecodersourceset","interfererprecodingmodeset","interfererbeamindexsetsummary","grantcontextid","grantsharedstatecommitmode","mcsauthority","modulationauthority","grantoperatingpointsource","appliedoperatingpointsource","cfoestimateavailability","cfoerrordefinition","cfovaluestatus","timingestimateavailability","timingerrordefinition","timingvaluestatus","timingestimateapplicationpolicy","timingestimatestatus","largescalesinrvaluestatus","largescalesinrnareason","primarytruthvaluestatus","secondaryfieldgapreason","rowlifecyclestate","nareason","runuuid","runtag","scenarioid","runnerprofile","confighash","sourceartifact","sourcetable","artifactclass","semanticstate","bsantennaarrayclass","bsantennaelementclass","bsantennaarraytype","bsantennapolarization","ueantennaarrayclass","ueantennaelementclass","ueantennaarraytype","ueantennapolarization","antennaconfigsource","runtimeantennaobjectsource","antennaruntimeobjectvaluerole","antennaruntimeobjectvaluestatus","antennaruntimeobjectnareason","channelarraymodel","channelobjectsource","channelobjectclass","channelarrayhandlingstatus","channelarrayhandlingblocker","channelgeometrycouplinglevel","geometryadaptertype","geometryadaptersource","geometryadapterlimitation","geometryadapterportmapping","channelarrayvaluerole","channelarrayvaluestatus","interferencechannelobjectsource","interferencechannelobjectclass","interferencechannelarrayhandlingstatus","interferencechannelarrayhandlingblocker","interferencechannelarrayvaluerole","interferencechannelarrayvaluestatus","todsource","toasource","toaestimatesource","channeldelaysource","antennageometrysource","antennaevidencesource","sameflowevidencesource","runtimetracesource"]))
        col = strings(nRows, 1);
    elseif any(strcmp(name, ["fullinterfererchanneltruthused","controleligible","controldecodeok","precodingactive","explicitbeamweightsapplied","transformprecodingapplied","beamformingapplied","grantworkersafe","antennaruntimeobjectcreated","channelusescountonlyantennamodel","channelusessameruntimeantennaassumptions","interferenceusessameruntimeantennaassumptions","interferencepathusessamearrayassumptions","beamselectionpolicyfixed","iqimbalanceconfigured","iqimbalanceapplied","largescalesinrfinalizedflag","secondaryfieldgapflag","partialrowflag","finalizedflag","fallbackflag","placeholderflag","countstowardcoverage","machinereadable","humanreadable","timingestimatewasclipped"]))
        col = false(nRows, 1);
    else
        col = nan(nRows, 1);
    end
end

function T = localTailTable(T, maxRows)
if ~(istable(T) && ~isempty(T))
    return;
end
maxRows = max(1, round(double(maxRows)));
if height(T) > maxRows
    T = T(end-maxRows+1:end, :);
end
end
