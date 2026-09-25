function row = buildIndependentCSIRSTrialRow(cfg, prepared, reception, csi, context)
%BUILDINDEPENDENTCSIRSTRIALROW Canonical actual CSI-RS receiver evidence.
arguments
    cfg (1,1) struct
    prepared (1,1) struct
    reception (1,1) struct
    csi (1,1) struct
    context (1,1) struct
end
assert(string(sixgr.util.structGet(prepared,"ExecutionStage","")) == ...
    "csirs_waveform_prepared_not_received", ...
    'sixgr:truth:InvalidIndependentCSIRSPreparation', ...
    'Build CSI-RS evidence only from the retained independent preparation.');
event = prepared.Tx.CSIRSRuntimeEvent;
obs = reception.CSIRSObservation;
row = localCanonicalRow();

row.Direction = "DL";
row.SignalFamily = "CSI-RS";
row.SNR_dB = double(sixgr.util.structGet(context,"SNR",prepared.RequestedSNR_dB));
row.SFN = double(sixgr.util.structGet(context,"Frame",prepared.Timeline.FrameIndexOneBased));
row.Frame = row.SFN;
row.Slot = double(sixgr.util.structGet(context,"Slot",prepared.RuntimeSlot));
row.Time_s = double(sixgr.util.structGet(context,"Time_s",NaN));
row.CellID = double(sixgr.util.structGet(context,"ServingCell", ...
    sixgr.util.structGet(cfg,"lls6g.userContext.RuntimeServingCell",NaN)));
row.BWPID = double(sixgr.util.structGet(cfg,"phy.csirs.bwpID",0));
row.UEIndex = double(sixgr.util.structGet(context,"UEIndex",NaN));
row.RNTI = double(sixgr.util.structGet(context,"RNTI", ...
    sixgr.util.structGet(cfg,"phy.rnti",NaN)));
row.ResourceID = double(sixgr.util.structGet(obs,"ResourceID",event.ResourceID));
row.ResourceSetID = double(event.ResourceSetID);
row.CSIRSType = string(sixgr.util.structGet(event,"CSIRSType","nzp"));
row.NumPorts = double(sixgr.util.structGet(event,"NumPorts", ...
    sixgr.util.structGet(obs,"NumPorts",NaN)));
row.RowNumber = double(sixgr.util.structGet(event,"RowNumber", ...
    sixgr.util.structGet(obs,"RowNumber",NaN)));
row.Density = string(sixgr.util.structGet(event,"Density",""));
row.Periodicity = string(event.Periodicity);
row.SymbolLocations = string(event.SymbolLocations);
row.SubcarrierLocations = string(event.SubcarrierLocations);
row.RBOffset = double(event.RBOffset);
row.NumRB = double(event.NumRB);
row.NRE = double(event.NRE);
row.Scheduled = logical(event.Scheduled);
row.Transmitted = logical(event.Transmitted);
row.Observed = logical(sixgr.util.structGet(obs,"Observed",false));
row.Consumed = logical(sixgr.util.structGet(obs,"Consumed",false));
row.Consumer = string(sixgr.util.structGet(obs,"Consumer",""));
for name = ["ResourceExtractionAttempted","ResourceExtractionAvailable", ...
        "ChannelEstimationAttempted","ChannelEstimateAvailable", ...
        "CSIMeasurementStateAvailable"]
    row.(name) = logical(sixgr.util.structGet(obs,name,false));
end
row.CSIMeasurementAvailable = row.CSIMeasurementStateAvailable;
for name = ["ChannelEstimateSource","ChannelEstimator", ...
        "ChannelInterpolationMethod","ChannelEstimateConvention", ...
        "ReceiverStageLatencySource","CSIMeasurementStatus", ...
        "CRISelectionSource","SINRMeasurementDomain","PowerReferencePlane", ...
        "MeasurementSource","RuntimeMaterializationStatus", ...
        "UpdateOutcome","RuntimeEvidenceSource"]
    row.(name) = string(sixgr.util.structGet(obs,name,row.(name)));
end
row.TxRuntimeMaterializationStatus = string(event.RuntimeMaterializationStatus);
row.RxRuntimeObservationStatus = string(obs.RuntimeMaterializationStatus);
row.RuntimeBlocker = string(sixgr.util.structGet(obs,"Blocker",""));
row.RuntimeEventObserved = row.Scheduled || row.Transmitted || row.Observed;

numericObservationFields = [ ...
    "ChannelEstimateNoiseVariance","ChannelEstimationLatency_ms", ...
    "ReceiverPipelineLatency_ms","PilotRECount","PilotResidualPower", ...
    "PilotResidualNMSE_dB","HestRxPorts","HestTxPorts", ...
    "CSIMeasurementSlot","CSIMeasurementNoiseVariance", ...
    "NumConfiguredResources","NumMeasuredResources", ...
    "MeasurementRSRP_dB","MeasurementRelativeRSRP_dB", ...
    "MeasurementRSRP_dBm","MeasurementRSSI_dBm","MeasurementRSRQ_dB", ...
    "MeasurementRSSI_dB_re_UnitOccupiedRE_Es", ...
    "MeasurementRSRQReceiveAntennaIndex1Based", ...
    "MeasurementRSRQNumeratorRSRP_dBm","MeasurementRSRQDenominatorRSSI_dBm", ...
    "MeasurementRSRQNumeratorRSRP_dB_re_UnitOccupiedRE_Es", ...
    "MeasurementRSRQDenominatorRSSI_dB_re_UnitOccupiedRE_Es", ...
    "MeasurementReceiveAntennaIndex1Based","MeasurementNumRB", ...
    "MeasurementFirstPRB0Based","MeasurementSubcarrierSpacing_kHz", ...
    "MeasurementBandwidth_Hz","MeasurementSelectedResourceOrdinal", ...
    "MeasurementFFTSize","MeasurementGridScaleToSqrtW", ...
    "MeasurementReceiverGainCorrection_dB"];
for name = numericObservationFields
    row.(name) = double(sixgr.util.structGet(obs,name,NaN));
end
for name = ["HestDimensions","CSIMeasurementID","CSIMeasurementDigest", ...
        "CSIMeasurementProvenance","ResourceObjectiveValues", ...
        "MeasurementRelativeSource", ...
        "MeasurementRSRPPerReceiveAntenna_dB_re_UnitOccupiedRE_Es", ...
        "MeasurementRSRPPerResource_dB_re_UnitOccupiedRE_Es", ...
        "MeasurementRSSIPerReceiveAntenna_dB_re_UnitOccupiedRE_Es", ...
        "MeasurementRSRQAntennaAggregation", ...
        "MeasurementRSSIPerReceiveAntenna_dBm", ...
        "MeasurementRSRQPerReceiveAntenna_dB", ...
        "MeasurementRSSIAntennaAggregation","MeasurementRSSIStatus", ...
        "MeasurementSymbolIndices0Based","MeasurementPhysicalResourcesJSON", ...
        "MeasurementRSRPPerReceiveAntenna_dBm", ...
        "MeasurementRSRPPerResource_dBm","MeasurementResourceIDs", ...
        "MeasurementAntennaAggregation","PhysicalMeasurementWaveformStatus", ...
        "PhysicalMeasurementWaveformSource","PhysicalMeasurementStatus", ...
        "PhysicalMeasurementStandard","MeasurementReceiverGainCorrectionSource"]
    row.(name) = string(sixgr.util.structGet(obs,name,""));
end
row.ReferenceMeasuredSINR_dB = double(sixgr.util.structGet( ...
    obs,"ReferenceMeasuredSINR_dB",NaN));
row.ReferenceMeasuredSINRSource = string(sixgr.util.structGet( ...
    obs,"ReferenceMeasuredSINRSource",""));
row.ReferenceMeasuredSINRStatus = string(sixgr.util.structGet( ...
    obs,"ReferenceMeasuredSINRStatus","not_attempted"));
row.ReferenceMeasuredSINRDomain = string(sixgr.util.structGet( ...
    obs,"SINRMeasurementDomain",""));
row.ReferenceSINRMeasurementJSON = string(sixgr.util.structGet( ...
    obs,"ReferenceSINRMeasurementJSON",""));
row.ChannelEstimateDiagnosticSINR_dB = double(sixgr.util.structGet( ...
    obs,"ChannelEstimateDiagnosticSINR_dB",NaN));
row.ChannelEstimateDiagnosticSINRSource = string(sixgr.util.structGet( ...
    obs,"ChannelEstimateDiagnosticSINRSource",""));
row.ChannelEstimateCDMType = string(sixgr.util.structGet(obs,"ChannelEstimateCDMType",""));
row.ChannelEstimateCDMLengths = string(sixgr.util.structGet(obs,"ChannelEstimateCDMLengths",""));

for name = ["CQI","RI","PMI","LI","CRI","PMI_I11","PMI_I12","PMI_I13","PMI_I2"]
    row.(name) = double(sixgr.util.structGet(csi,name,NaN));
end
row.CQISource = "independent_received_csirs_report_engine";
row.CSIReportConfigID = string(sixgr.util.structGet(csi,"CSIReportConfigID",""));
row.CSIConfigurationEpoch = double(sixgr.util.structGet(csi,"CSIConfigurationEpoch",NaN));
row.CSIUCIChannel = string(sixgr.util.structGet(csi,"CSIUCIChannel",""));
row.CSIPart1BitsToken = string(sixgr.util.structGet(csi,"CSIPart1BitsToken",""));
row.CSIPart2BitsToken = string(sixgr.util.structGet(csi,"CSIPart2BitsToken",""));
row.CSIReportMode = string(sixgr.util.structGet(csi,"ChannelStateInformationMode",""));
row.CSIPayloadBitLength = double(sixgr.util.structGet(csi,"CSIPayloadBitLength",NaN));
row.CSIPayloadHex = string(sixgr.util.structGet(csi,"CSIPayloadHex",""));
row.CSIComputationStatus = "runtime_measured_csi_complete";
row.CSIMeasurementID = string(sixgr.util.structGet(csi,"CSIMeasurementID",row.CSIMeasurementID));
row.CSIMeasurementDigest = string(sixgr.util.structGet(csi,"CSIMeasurementDigest",row.CSIMeasurementDigest));
row.CSIMeasurementProvenance = string(sixgr.util.structGet(csi,"CSIMeasurementProvenance",row.CSIMeasurementProvenance));
row.PMIType = string(sixgr.util.structGet(csi,"PMIType",""));
row.PMICodebookMode = string(sixgr.util.structGet(csi,"PMICodebookMode",""));
row.SINR_dB = double(sixgr.util.structGet(csi,"SINR_dB",NaN));
row.SINRSource = string(sixgr.util.structGet(csi,"SINRSource",""));
row.SINRValueRole = string(sixgr.util.structGet(csi,"SINRValueRole",""));
row.SINRValueStatus = string(sixgr.util.structGet(csi,"SINRValueStatus",""));
row.CQIEffectiveSINR_dB = double(sixgr.util.structGet(csi,"WidebandSINR_dB",row.SINR_dB));
row.CQIEffectiveSINRSource = row.SINRSource;

row.NumConfiguredResources = double(sixgr.util.structGet(obs,"NumConfiguredResources",event.NumResources));
row.ConfiguredResourceIDs = string(event.ResourceIDs);
row.CSIRSPhysicalPortCount = double(event.PhysicalPortCount);
row.CSIRSWaveformPortCount = double(event.WaveformPortCount);
row.CSIRSPrecoderSource = string(event.PrecoderSource);
row.CSIRSPrecoderDigests = strjoin(string(event.PrecoderDigests),"|");
row.CSIRSWaveformPrecoderDigests = strjoin(string(event.WaveformPrecoderDigests),"|");
row.CSIRSPortToElementMatrixDigests = strjoin(string(event.PortToElementMatrixDigests),"|");
row.CSIRSPortProjectionSource = string(event.PortProjectionSource);
row.CSIRSPortProjectionResidualMax = double(event.PortProjectionResidualMax);

power = prepared.PowerContext;
row.PowerNormalizationPolicy = string(sixgr.util.structGet(power,"PowerNormalizationPolicy",""));
row.PowerNormalizationSource = string(sixgr.util.structGet(power,"PowerNormalizationSource",""));
row.PowerNormalizationGridSource = string(sixgr.util.structGet(power,"NormalizationGridSource",""));
row.PowerNormalizationGridSubcarrierCount = double(sixgr.util.structGet(power,"NormalizationGridSubcarrierCount",NaN));
row.PowerNormalizationGridActiveSymbolCount = double(sixgr.util.structGet(power,"NormalizationGridActiveSymbolCount",NaN));
row.PowerNormalizationGridMeanEnergyPerRE = double(sixgr.util.structGet(power,"NormalizationGridMeanEnergyPerRE",NaN));
row.FullBWPActivityFactor = double(sixgr.util.structGet(power,"FullBWPActivityFactor",NaN));
row = sixgr.report.bindTransmitPowerEvidence(row,power);
row.ActualEmittedPowerBackoffFromBudget_dB = double(sixgr.util.structGet(power,"ActualEmittedPowerBackoffFromBudget_dB",NaN));
row.PowerClosureError_dB = double(sixgr.util.structGet(power,"PowerClosureError_dB",NaN));
row.PowerConversionEquation = string(sixgr.util.structGet(power,"ConversionEquation",""));
row.SourceArtifact = "air_interface/csv/csi_rs_trials.csv";
row.SourceTable = row.SourceArtifact;
row.RuntimeTransportMode = "shared_physical_stream_independent_CSIRS_received_completion";
end

function row = localCanonicalRow()
schema = sixgr.truth.emptyCSIRSTrialTable();
names = string(schema.Properties.VariableNames);
template = struct();
for name = names
    column = schema.(name);
    if isstring(column)
        template.(name) = "";
    elseif islogical(column)
        template.(name) = false;
    elseif isnumeric(column)
        template.(name) = NaN;
    else
        error("sixgr:truth:UnsupportedCSIRSSchemaType", ...
            "Unsupported canonical CSI-RS column type for %s.",name);
    end
end
row = template;
end
