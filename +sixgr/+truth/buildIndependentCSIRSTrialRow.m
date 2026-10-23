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
resourceEvidence=sixgr.truth.executedResourceIntervals();
for field=string(fieldnames(resourceEvidence)).'
    row.(field)=sixgr.util.structGet(prepared, ...
        "ResourceIntervalEvidence."+field,resourceEvidence.(field));
end

row.Direction = "DL";
row.SignalFamily = "CSI-RS";
row.SNR_dB = double(sixgr.util.structGet(context,"SNR",prepared.RequestedSNR_dB));
% SFN belongs to the executed carrier, not the one-based reporting frame.
% Keep the unwrapped runtime frame independently across the 1024-frame wrap.
row.SFN = mod(double(prepared.Carrier.NFrame),1024);
row.Frame = double(sixgr.util.structGet(context,"Frame",prepared.Timeline.FrameIndexOneBased));
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
        "CSIMeasurementStateAvailable","MeasurementPowerReferenceNormalized"]
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
receiptFields=["PhysicalMeasurementDemodulationReceiptAvailable", ...
    "PhysicalMeasurementDemodulationReceiptStatus", ...
    "PhysicalMeasurementDemodulationReceiptJSON", ...
    "PhysicalMeasurementDemodulationReceiptSHA256"];
if any(isfield(reception,cellstr(receiptFields)))
    % Validate BEFORE generic sync projection can dereference an orphan or
    % malformed original source. An intact token cannot replace its owner.
    localAssertDemodulationSources(reception,receiptFields);
end
for prefix=["Receiver","PhysicalMeasurement"]
    timingName="ReceiveTiming"; trackingName="ReceiverTrackingCorrection";
    sourceName="ReceiverReferenceSource";
    if prefix=="PhysicalMeasurement"
        timingName="PhysicalMeasurementReceiveTiming";
        trackingName="PhysicalMeasurementTrackingCorrection";
        sourceName="PhysicalMeasurementSynchronizationSource";
    end
    timing=sixgr.util.structGet(reception,timingName,struct());
    tracking=sixgr.util.structGet(reception,trackingName,struct());
    row.(prefix+"TimingOffset_samples")=double(sixgr.util.structGet(timing,"TimingOffsetSamples",NaN));
    row.(prefix+"TimingCorrection_samples")=double(sixgr.util.structGet(timing,"AppliedTimingCorrectionSamples",NaN));
    row.(prefix+"DemodulatedSampleCount")=double(sixgr.util.structGet(timing,"DemodulatedSampleCount",NaN));
    row.(prefix+"TimingSource")=string(sixgr.util.structGet(timing,"TimingSource",""));
    row.(prefix+"EstimatedCFO_Hz")=double(sixgr.util.structGet(tracking,"EstimatedCFO_Hz",NaN));
    row.(prefix+"AppliedCFO_Hz")=double(sixgr.util.structGet(tracking,"CFOCorrectionApplied_Hz",NaN));
    row.(prefix+"CFOEstimateAvailable")=logical(sixgr.util.structGet(tracking,"CFOEstimateAvailable",false));
    row.(prefix+"CFOCorrectionApplied")=logical(sixgr.util.structGet(tracking,"CFOCorrectionApplied",false));
    row.(prefix+"CFOStatus")=string(sixgr.util.structGet(tracking,"Status","not_recorded"));
    row.(prefix+"CFOSource")=string(sixgr.util.structGet(tracking,"Source",""));
    row.(prefix+"SynchronizationSource")=string(sixgr.util.structGet(reception,sourceName,""));
    if ~isempty(fieldnames(timing)) || ~isempty(fieldnames(tracking))
        row.(prefix+"SynchronizationSampleDomain")="relative_to_observation_capture_start_zero_based";
        row.(prefix+"SynchronizationJSON")=string(jsonencode( ...
            struct('Timing',timing,'Frequency',tracking)));
    end
end

% Lossless projection of the original practical pre-RF operator. It does
% not establish an independently isolated power reference or an absolute
% sample clock; the completed observation owner retains those separately.
row.PhysicalMeasurementDemodulationReceiptAvailable=false;
row.PhysicalMeasurementDemodulationReceiptStatus="unavailable_original_demodulation_receipt";
row.PhysicalMeasurementDemodulationReceiptJSON="";
row.PhysicalMeasurementDemodulationReceiptSHA256="";
if any(isfield(reception,cellstr(receiptFields)))
    id='sixgr:truth:CSIPhysicalDemodulationReceiptMismatch';
    assert(all(isfield(reception,cellstr(receiptFields))),id, ...
        'A supplied original demodulation receipt must retain all four projection fields.');
    available=reception.PhysicalMeasurementDemodulationReceiptAvailable;
    assert(islogical(available)&&isscalar(available)&&available,id, ...
        'Only an actually retained receipt can be projected as available.');
    token=string(reception.PhysicalMeasurementDemodulationReceiptJSON);
    digest=string(reception.PhysicalMeasurementDemodulationReceiptSHA256);
    status=string(reception.PhysicalMeasurementDemodulationReceiptStatus);
    assert(isscalar(token)&&~ismissing(token)&&strlength(token)>0&& ...
        isscalar(digest)&&~ismissing(digest)&& ...
        sixgr.util.sha256Hex(char(token))==digest&&isscalar(status)&&~ismissing(status),id, ...
        'Do not rewrite or transplant the retained original JSON token.');
    receipt=jsondecode(token);
    carrier=prepared.Carrier;
    assert(isstruct(receipt)&&isscalar(receipt)&& ...
        string(receipt.ContractVersion)=="sixgr.csirs.physical_demodulation/v1"&& ...
        string(receipt.Status)==status&& ...
        status=="retained_practical_preRF_demodulation_not_independent_reference"&& ...
        string(receipt.Source)=="original_CSI_RS_physical_measurement_demodulation"&& ...
        string(receipt.InputPlane)=="supplied_pre_composite_receiver_front_end_capture"&& ...
        receipt.Carrier.NCellID==carrier.NCellID&&receipt.Carrier.NSizeGrid==carrier.NSizeGrid&& ...
        receipt.Carrier.NStartGrid==carrier.NStartGrid&& ...
        receipt.Carrier.SubcarrierSpacing_kHz==carrier.SubcarrierSpacing&& ...
        string(receipt.Carrier.CyclicPrefix)==string(carrier.CyclicPrefix)&& ...
        receipt.Carrier.NFrame==carrier.NFrame&&receipt.Carrier.NSlot==carrier.NSlot&& ...
        receipt.InputSize(1)==reception.PhysicalMeasurementReceiveTiming.InputSampleCount&& ...
        receipt.NumReceiveChannels==size(reception.RxGrid,3)&& ...
        receipt.Timing.AppliedTimingCorrectionSamples== ...
            reception.PhysicalMeasurementReceiveTiming.AppliedTimingCorrectionSamples&& ...
        ~receipt.AbsoluteObservationIdentityBound&&~receipt.ReceiveBranchLayoutQualified&& ...
        ~receipt.IndependentPowerReferenceAvailable&&~receipt.RSRPAccuracyQualified,id, ...
        'The practical receipt must match this carrier/timing/channel count without expanding its authority.');
    for field=receiptFields
        row.(field)=reception.(field);
    end
end

numericObservationFields = [ ...
    "ChannelEstimateNoiseVariance","ChannelEstimationLatency_ms", ...
    "ReceiverPipelineLatency_ms","PilotRECount","PilotResidualPower", ...
    "PilotResidualNMSE_dB","HestRxPorts","HestTxPorts", ...
    "CSIMeasurementSlot","CSIMeasurementNoiseVariance", ...
    "NumConfiguredResources","NumMeasuredResources", ...
    "MeasurementRSRP_dB","MeasurementRelativeRSRP_dB", ...
    "MeasurementRSRP_dBm","MeasurementRSSI_dBm","MeasurementRSRQ_dB", ...
    "MeasurementRSRP_dB_re_UnitOccupiedRE_Es", ...
    "MeasurementRSSI_dB_re_UnitOccupiedRE_Es", ...
    "MeasurementRSRQReceiveAntennaIndex1Based", ...
    "MeasurementRSRQNumeratorRSRP_dBm","MeasurementRSRQDenominatorRSSI_dBm", ...
    "MeasurementRSRQNumeratorRSRP_dB_re_UnitOccupiedRE_Es", ...
    "MeasurementRSRQDenominatorRSSI_dB_re_UnitOccupiedRE_Es", ...
    "MeasurementReceiveAntennaIndex1Based","MeasurementNumRB", ...
    "MeasurementFirstPRB0Based","MeasurementSubcarrierSpacing_kHz", ...
    "MeasurementBandwidth_Hz","MeasurementSelectedResourceOrdinal", ...
    "MeasurementFFTSize","MeasurementGridScaleToSqrtW", ...
    "MeasurementReceiverGainCorrection_dB","MeasurementPowerReferenceOffset_dB"];
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
publication=sixgr.link.csiReferenceSINRPublication(obs,row.SNR_dB);
for name=string(fieldnames(publication)).'
    row.(name)=publication.(name);
end
% The shared physical receiver owns these audit values. Never rebuild them
% from the requested operating point or use them as measured CSI SINR.
executed=sixgr.util.structGet(reception,"NoiseExecutionEvidence",struct());
for name=["AppliedAWGNSNR_dB","ReferenceAWGNGridNoiseVariance", ...
        "ReferenceAWGNSampleNoiseVariance","SignalEnergyPerOccupiedRE", ...
        "SampleToGridNoiseVarianceGain"]
    row.(name)=double(sixgr.util.structGet(executed,name,NaN));
end
for name=["NoiseOperatingMode","AppliedAWGNSNRSource","AppliedAWGNSNRValueRole", ...
        "AWGNReferenceEnergySource","SharedNoiseCalibrationSource"]
    row.(name)=string(sixgr.util.structGet(executed,name,""));
end
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
row.SINRValueDefinition = string(sixgr.util.structGet(csi,"SINRValueDefinition",""));
row.SINRMeasurementDomain = string(sixgr.util.structGet(csi,"SINRMeasurementDomain",""));
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

function localAssertDemodulationSources(reception,receiptFields)
id='sixgr:truth:CSIPhysicalDemodulationReceiptMismatch';
sources=["PhysicalMeasurementReceiveTiming","PhysicalMeasurementTrackingCorrection", ...
    "PhysicalMeasurementSynchronizationSource","RxGrid"];
assert(all(isfield(reception,cellstr([receiptFields sources]))),id, ...
    'An original demodulation receipt requires its complete original timing, frequency and grid sources.');
timing=reception.PhysicalMeasurementReceiveTiming;
tracking=reception.PhysicalMeasurementTrackingCorrection;
timingNumbers=["InputSampleCount","TimingOffsetSamples", ...
    "AppliedTimingCorrectionSamples","DemodulatedSampleCount"];
trackingNumbers=["EstimatedCFO_Hz","CFOCorrectionApplied_Hz"];
trackingFlags=["CFOEstimateAvailable","CFOCorrectionApplied"];
assert(isstruct(timing)&&isscalar(timing)&& ...
    all(isfield(timing,cellstr([timingNumbers "TimingSource"])))&& ...
    isstruct(tracking)&&isscalar(tracking)&& ...
    all(isfield(tracking,cellstr([trackingNumbers trackingFlags "Source" "Status"]))),id, ...
    'Original timing and frequency sources must be scalar structures with their retained fields.');
for name=timingNumbers
    value=timing.(name);
    assert(isnumeric(value)&&isreal(value)&&isscalar(value)&&isfinite(value)&& ...
        value>=0&&value==fix(value),id,'Original timing/count fields must be scalar nonnegative integers.');
end
assert(timing.InputSampleCount>0&&timing.DemodulatedSampleCount>0&& ...
    timing.AppliedTimingCorrectionSamples+timing.DemodulatedSampleCount<=timing.InputSampleCount,id, ...
    'The original demodulated interval must be contained in the received capture.');
for name=trackingNumbers
    value=tracking.(name);
    assert(isnumeric(value)&&isreal(value)&&isscalar(value)&&~isinf(value),id, ...
        'Original frequency fields must be scalar numeric values; unavailable remains NaN.');
end
for name=trackingFlags
    assert(islogical(tracking.(name))&&isscalar(tracking.(name)),id, ...
        'Original frequency applicability fields must retain scalar logical values.');
end
texts={timing.TimingSource,tracking.Source,tracking.Status, ...
    reception.PhysicalMeasurementSynchronizationSource};
for k=1:numel(texts)
    value=texts{k};
    assert(((ischar(value)&&isrow(value))||(isstring(value)&&isscalar(value)))&& ...
        ~ismissing(string(value))&&strlength(strtrim(string(value)))>0,id, ...
        'Original synchronization source/status fields must be nonempty scalar text.');
end
assert(isnumeric(reception.RxGrid)&&~isempty(reception.RxGrid)&&ndims(reception.RxGrid)<=3,id, ...
    'Retain the original received resource grid and its receive-column dimension.');
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
