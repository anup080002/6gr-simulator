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

waveformT = localTailTable(sixgr.util.structGet(meta, "WaveformPreviewTable", table()), 4096);
moddemT = localBuildModulationDemodTable(localTailTable(trialT, 2048), localTailTable(constellationT, 4096));
channelEstT = localBuildChannelEstimationTable(localTailTable(trialT, 2048));
channelStateT = localBuildChannelStateTable(localTailTable(trialT, 2048));
stageTraceT = localBuildTxRxStageTraceTable(localTailTable(trialT, 2048));

sixgr.util.csvWriteTable(artifacts.WaveformPreviewPath, waveformT);
sixgr.util.csvWriteTable(artifacts.ModulationTracePath, moddemT);
sixgr.util.csvWriteTable(artifacts.ChannelEstimationTracePath, channelEstT);
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
    "MeasuredTrialSINR_dB","MeasuredTrialSINRSource","MeasuredTrialSINRValueRole","MeasuredTrialSINRValueStatus","MeasuredTrialSINRNAReason", ...
    "DopplerHz","DopplerSourceMode","DopplerValueRole","UEID","UEIndex","RNTI","BaseStationID","Frame","Slot","AllocatedPRBCount","PRBStart", ...
    "Modulation","MCS","MCSIndex","TargetCodeRate","Layers","Rank","WidebandCQI","CQIDerivedMCS", ...
    "CQIDerivedModulation","CQIDerivedTargetCodeRate","MCSAuthority","ModulationAuthority","GrantOperatingPointSource","AppliedOperatingPointSource","BitErrors","BitsCompared", ...
    "SymbolErrors","SymbolsCompared","SymbolErrorRate","EVM_rms","LLRMeanAbs", ...
    "LLRStdAbs","LLRImbalance","Status"];
T = localProjectTable(trialT, fields);
if ~isempty(T)
    T.ConstellationSamples = zeros(height(T), 1);
    if istable(constellationT) && ~isempty(constellationT) && ...
            all(ismember(["Direction","SNR_dB","Frame","Slot"], string(constellationT.Properties.VariableNames)))
        groups = unique(localKeyTable(constellationT(:, {'Direction','SNR_dB','Frame','Slot'})), 'rows', 'stable');
        for i = 1:height(T)
            mask = strcmp(string(groups.Direction), string(T.Direction(i))) & ...
                abs(double(groups.SNR_dB) - double(T.SNR_dB(i))) < 1e-9 & ...
                abs(double(groups.Frame) - double(T.Frame(i))) < 1e-9 & ...
                abs(double(groups.Slot) - double(T.Slot(i))) < 1e-9;
            if any(mask)
                gMask = strcmp(string(constellationT.Direction), string(T.Direction(i))) & ...
                    abs(double(constellationT.SNR_dB) - double(T.SNR_dB(i))) < 1e-9 & ...
                    abs(double(constellationT.Frame) - double(T.Frame(i))) < 1e-9 & ...
                    abs(double(constellationT.Slot) - double(T.Slot(i))) < 1e-9;
                T.ConstellationSamples(i) = sum(gMask);
            end
        end
    end
end
T = localEnsureNonEmpty(T, [fields "ConstellationSamples"]);
T = sixgr.truth.canonicalizeLLSLiveSignalChainTable("modulation_demodulation", T);
end

function T = localBuildChannelEstimationTable(trialT)
fields = [ ...
    "Direction","SFN","ConfiguredSNR_dB","ConfiguredSNRSource","SNRValueRole","SNR_dB", ...
    "SystemLevelSINR_dB","SystemLevelSINRSource","SystemLevelSINRValueRole","SystemLevelSINRValueStatus", ...
    "ReceiverHestSINR_dB","ReceiverHestSINRSource","ReceiverHestSINRValueRole","ReceiverHestSINRValueStatus","ReceiverHestSINRNAReason", ...
    "PostEqSINR_dB","PostEqSINRSource","PostEqSINRValueRole","PostEqSINRValueStatus","PostEqSINRNAReason","PostEqSINRPerLayer_dB", ...
    "EVMProxySINR_dB","EVMProxySINRSource","EVMProxySINRValueRole","EVMProxySINRValueStatus","EVMProxySINRNAReason", ...
    "DecoderTruthProxySINR_dB","DecoderTruthProxySINRSource","DecoderTruthProxySINRValueRole","DecoderTruthProxySINRValueStatus","DecoderTruthProxySINRNAReason", ...
    "SINRValueRole","SINRSource","SINRValueStatus","SINRValueDefinition", ...
    "MeasuredTrialSINR_dB","MeasuredTrialSINRSource","MeasuredTrialSINRValueRole","MeasuredTrialSINRValueStatus","MeasuredTrialSINRNAReason", ...
    "DopplerHz","DopplerSourceMode","DopplerValueRole","UEID","UEIndex","RNTI","BaseStationID","Frame","Slot","AllocatedPRBCount","PRBStart","MCSIndex","Layers","Rank", ...
    "NMSE_dB","DetectionMetric","ChannelGain_dB","NoiseVariance","TimingOffset_samples","TimingEstimateUsed","UseIdealTimingSync","RankEstimate","ConditionNumber_dB", ...
    "EstimatedDopplerHz","PhaseTrackingError_deg","QCLAccuracy","Status"];
T = localEnsureNonEmpty(localProjectTable(trialT, fields), fields);
if isempty(T)
    T.NMSEDefinition = strings(0, 1);
    T.NMSEInterpretation = strings(0, 1);
    return;
end
T.NMSEDefinition = repmat("pilot_residual_over_aligned_pilot_power", height(T), 1);
T.NMSEInterpretation = repmat("nmse_db_is_10log10(error_power/reference_pilot_power)", height(T), 1);
nmse = nan(height(T), 1);
try
    nmse = double(T.NMSE_dB);
catch
end
posMask = isfinite(nmse) & nmse > 0;
negMask = isfinite(nmse) & nmse <= 0;
T.NMSEInterpretation(posMask) = "positive_nmse_db_can_occur_when_estimation_error_exceeds_reference_pilot_power";
T.NMSEInterpretation(negMask) = "negative_nmse_db_means_estimation_error_is_below_reference_pilot_power";
T = sixgr.truth.canonicalizeLLSLiveSignalChainTable("channel_estimation", T);
end

function T = localBuildChannelStateTable(trialT)
fields = [ ...
    "Direction","SFN","ConfiguredSNR_dB","ConfiguredSNRSource","SNRValueRole","AppliedAWGNSNR_dB","SNR_dB","UEID","UEIndex","RNTI","BaseStationID","Frame","Slot","AllocatedPRBCount","PRBStart","MCSIndex","Layers","Rank","ChannelModel","DopplerHz","DopplerSourceMode","DopplerValueRole", ...
    "InjectedCFO_Hz","EstimatedCFO_Hz","CFOError_Hz","CFOEstimateAvailability","CFOErrorDefinition","CFOValueStatus","InjectedTimingOffset_samples", ...
    "RawTimingEstimate_samples","AppliedTimingCorrection_samples","TimingEstimateApplicationPolicy","TimingEstimateStatus","TimingEstimateWasClipped", ...
    "TimingError_samples","TimingEstimateUsed","UseIdealTimingSync","TimingEstimateAvailability","TimingErrorDefinition","TimingValueStatus", ...
    "IQImbalanceConfigured","IQImbalanceApplied","IQImbalanceModel","ConfiguredIQGainImbalance_dB","ConfiguredIQPhaseImbalance_deg", ...
    "IQImbalanceMirrorPowerRatio_dB","IQImbalanceImageRejection_dB","IQImbalanceIQPowerRatio_dB","IQImbalanceIQCorrelation", ...
    "IQImbalanceEstimatedAlphaAbs","IQImbalanceEstimatedBetaAbs","IQImbalanceMeasurementSource","IQImbalanceMeasurementStatus", ...
    "SystemLevelSINR_dB","SystemLevelSINRSource","SystemLevelSINRValueRole","SystemLevelSINRValueStatus","SystemLevelSINRDefinition", ...
    "ReceiverHestSINR_dB","ReceiverHestSINRSource","ReceiverHestSINRValueRole","ReceiverHestSINRValueStatus","ReceiverHestSINRNAReason", ...
    "PostEqSINR_dB","PostEqSINRSource","PostEqSINRValueRole","PostEqSINRValueStatus","PostEqSINRNAReason","PostEqSINRPerLayer_dB", ...
    "EVMProxySINR_dB","EVMProxySINRSource","EVMProxySINRValueRole","EVMProxySINRValueStatus","EVMProxySINRNAReason", ...
    "DecoderTruthProxySINR_dB","DecoderTruthProxySINRSource","DecoderTruthProxySINRValueRole","DecoderTruthProxySINRValueStatus","DecoderTruthProxySINRNAReason", ...
    "SINRValueRole","SINRSource","SINRValueStatus","SINRValueDefinition","MeasuredTrialSINR_dB","MeasuredTrialSINRSource","MeasuredTrialSINRValueRole","MeasuredTrialSINRValueStatus","MeasuredTrialSINRNAReason", ...
    "LargeScaleSINR_dB","LargeScaleSINRSource","LargeScaleSINRValueRole","LargeScaleSINRValueStatus","LargeScaleSINRFinalizedFlag","LargeScaleSINRNAReason","PrimaryTruthValueStatus","SecondaryFieldGapFlag","SecondaryFieldGapCount","SecondaryFieldGapReason","ServingRSRP_dBm","ServingRSRPSource","CSI_RSRP_dB","CSI_RSRPSource","AppliedLargeScaleGain_dB","AppliedLargeScaleGainSource","InterferenceMode","ResidualInterferencePower_dB", ...
    "InterferenceContributorCount","InterferenceAggregatedRxPower_dBm","InterferencePowerSource","FullInterfererChannelTruthUsed", ...
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
    "DecoderTruthProxySINR_dB","DecoderTruthProxySINRSource","DecoderTruthProxySINRValueRole","DecoderTruthProxySINRValueStatus","DecoderTruthProxySINRNAReason","SINRValueRole","SINRSource","SINRValueStatus","SINRValueDefinition","MeasuredTrialSINR_dB","MeasuredTrialSINRSource","MeasuredTrialSINRValueRole","MeasuredTrialSINRValueStatus","MeasuredTrialSINRNAReason", ...
    "DopplerHz","DopplerSourceMode","DopplerValueRole","UEID","UEIndex","RNTI","BaseStationID","Frame","Slot","AllocatedPRBCount","PRBStart", ...
    "InjectedCFO_Hz","EstimatedCFO_Hz","CFOError_Hz","InjectedTimingOffset_samples","RawTimingEstimate_samples","AppliedTimingCorrection_samples", ...
    "TimingEstimateApplicationPolicy","TimingEstimateStatus","TimingEstimateWasClipped","TimingError_samples", ...
    "IQImbalanceConfigured","IQImbalanceApplied","IQImbalanceModel","ConfiguredIQGainImbalance_dB","ConfiguredIQPhaseImbalance_deg", ...
    "IQImbalanceMirrorPowerRatio_dB","IQImbalanceImageRejection_dB","IQImbalanceIQPowerRatio_dB","IQImbalanceIQCorrelation", ...
    "IQImbalanceEstimatedAlphaAbs","IQImbalanceEstimatedBetaAbs","IQImbalanceMeasurementSource","IQImbalanceMeasurementStatus", ...
    "ChannelModel","TBSize_bits","TBCRCLength_bits","TBLengthWithCRC_bits","NumCodeBlocks","CodeBlockLength_bits", ...
    "SegmentationOccurred","SegmentationPaddingBits","BaseGraph","EncodedBits","RateMatchedBits","RateMatchPunctureBits","RateMatchRepetitionBits", ...
    "BitErrors","BitsCompared","SymbolErrors","SymbolsCompared","EVM_rms","DataRECount","DMRSRECount","PTRSRECount", ...
    "Layers","PMI","CRI","BeamformingApplied","TimingEstimateUsed","UseIdealTimingSync","NMSE_dB","ConditionNumber_dB", ...
    "ConfiguredBeamSelectionStrategy","BeamSelectionStrategy","BeamSelectionAuthority","BeamSelectionPolicyType","BeamSelectionPolicyFixed","SelectedBeamValueRole","SelectedBeamValueStatus","SelectedBeamNAReason","RequestedBeamIndexSet","RequestedBeamValueRole","RequestedBeamValueStatus","RequestedBeamNAReason","PrecoderSource","RequestedPrecoderSource","AppliedPrecoderSource","RequestedPrecoderPMI","PrecodingMode","PrecodingApplicationStage","PrecodingActive","ExplicitBeamWeightsApplied","TransformPrecodingApplied","AppliedBeamIndexSet","AppliedBeamValueRole","AppliedBeamValueStatus","AppliedBeamNAReason","AppliedPrecoderPMI","AppliedPrecoderValueRole","AppliedPrecoderValueStatus","AppliedPrecoderNAReason","ExplicitPrecoderReplayStatus","ExplicitPrecoderReplayBlocker","AppliedPrecoderPMIType","AppliedPrecoderCodebookMode","RequestedVsAppliedPrecoderPMIMatchStatus","PrecodingNumPorts","PrecodingNumLayers","PrecodingMatrixRows","PrecodingMatrixCols", ...
    "LLRMeanAbs","LLRStdAbs","LLRImbalance","DecoderIterations","CRCPass", ...
    "InterferenceMode","InterferenceContributorCount","InterferenceAggregatedRxPower_dBm","InterferencePowerSource","FullInterfererChannelTruthUsed", ...
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
    fill(companionMask) = "not_required_when_metric_present";
    fill(~companionMask) = "field_not_emitted_by_active_" + scope + "_runtime";
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

function T = localKeyTable(T)
if ~ismember("Direction", string(T.Properties.VariableNames))
    T.Direction = strings(height(T), 1);
end
end
