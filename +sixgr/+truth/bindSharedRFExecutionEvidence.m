function T=bindSharedRFExecutionEvidence(T,planes,metadataOnly)
% Post-decode export of actual retained RF executions and captured IQ.
% Segment manifest hashes and waveform-content hashes have separate fields.
if nargin<3, metadataOnly=false; end
assert(istable(T) && (height(T)==1 || (metadataOnly && height(T)>0)),'sixgr:truth:RFTrialScope', ...
    'Bind one completed shared PHY attempt at a time.');
n=height(T);
ids=string({planes.ReceiverID});
itx=find(endsWith(ids,':tx')); ipre=find(endsWith(ids,':pre_rf')); ipost=find(endsWith(ids,':post_rf'));
assert(isscalar(itx) && isscalar(ipre) && isscalar(ipost), ...
    'sixgr:truth:RFObservationPlanes','One physical TX, pre-RF RX and post-RF RX capture are required.');
tx=planes(itx).Observation; pre=planes(ipre).Observation; post=planes(ipost).Observation;
assert(tx.isComplete() && pre.isComplete() && post.isComplete() && ...
    pre.StartSample==post.StartSample && pre.EndSampleExclusive==post.EndSampleExclusive && ...
    pre.SampleRateHz==post.SampleRateHz && tx.SampleRateHz==post.SampleRateHz, ...
    'sixgr:truth:RFObservationClock','RX before/after RF must share the actual capture clock.');
txRecords=localRecords(planes(itx),extractBefore(ids(itx),':tx'),'TX');
rxRecords=localRecords(planes(ipost),extractBefore(ids(ipost),':post_rf'),'RX');
[txMetadata,txAudit]=sixgr.truth.summarizeSharedRFEndpoint(planes(itx),"TX");
[rxMetadata,rxAudit]=sixgr.truth.summarizeSharedRFEndpoint(planes(ipost),"RX");
T.TxRFEndpointMetadataJSON=repmat(string(jsonencode(txMetadata)),n,1);
T.RxRFEndpointMetadataJSON=repmat(string(jsonencode(rxMetadata)),n,1);
T.TxRFEndpointMetadataAuditJSON=repmat(string(jsonencode(txAudit)),n,1);
T.RxRFEndpointMetadataAuditJSON=repmat(string(jsonencode(rxAudit)),n,1);
T.RFMetadataAppliedFlagScope=repmat(rxAudit.AppliedFlagScope,n,1);
% Metadata-only consumers (PBCH/CSI/control) need the same actual counts as
% data consumers. Unknown/time-varying counts remain NaN, never default zero.
for endpoint=["Tx","Rx"]
    if endpoint=="Tx", metadata=txMetadata; else, metadata=rxMetadata; end
    for countName=["RFConfiguredStageCount","RFExecutedStageCount","RFAppliedStageCount"]
        value=double(sixgr.util.structGet(metadata,countName,NaN));
        T.(endpoint+countName)=repmat(value,n,1);
    end
    T.(endpoint+"RFStageCountScope")=repmat("per_execution_segment_not_sum_across_segments",n,1);
end
% These legacy flat columns have explicit endpoint owners. Never copy
% preparation-time placeholders or a different UE's RF replay into them.
for field=["CFOApplied","TimingOffsetApplied","PhaseNoiseConfigured", ...
        "PhaseNoiseApplied","IQImbalanceConfigured","IQImbalanceApplied", ...
        "ConfiguredIQGainImbalance_dB","ConfiguredIQPhaseImbalance_deg", ...
        "SampleClockOffsetEnabled","SampleClockOffsetApplied","AGCEnabled", ...
        "AGCApplied","ADCQuantizationApplied","ADCBits","ADCFullScale", ...
        "ADCQuantizationExecuted","ADCClippingRatio","ADCClippedSampleCount", ...
        "ADCClippingSampleCount","ADCDitherRMSConfigured", ...
        "ADCApertureJitterSecondsConfigured","ADCINLLSBConfigured", ...
        "ADCDNLLSBConfigured","ADCSeedConfigured", ...
        "AGCExecuted","AGCDecisionCausal","AGCGain_dB","AGCGainMin_dB", ...
        "AGCGainMax_dB","AGCGainIsTimeVarying","AGCGainSampleCount", ...
        "AGCTargetRMS","AGCOverloadGuardEnabled","AGCOverloadGuardGainStep_dB", ...
        "AGCOverloadGuardHoldSamples","AGCOverloadGuardFeedbackLatencySamples", ...
        "AGCOverloadGuardTriggerCount", ...
        "ADCErrorSampleCount","ADCInputEnergy","ADCErrorEnergy","ADCErrorMeanSquare"]
    T.(field)=repmat(double(sixgr.util.structGet(rxMetadata,field,NaN)),n,1);
end
for field=["PAEnabled","PAApplied","PABackoff_dB","DACBits", ...
        "DACQuantizationApplied","DACQuantizationExecuted", ...
        "DACClippingRatio","DACClippedSampleCount","DACClippingSampleCount", ...
        "DACFullScale","DACConfiguredFullScale","DACReferenceRMS", ...
        "DACReferenceHeadroom_dB","DACReferenceREEnergy","DACReferenceNfft", ...
        "DACReferenceSubcarriers","DACReferenceTxPorts","DACReferencePayloadDependent", ...
        "DACErrorSampleCount","DACInputEnergy","DACErrorEnergy","DACErrorMeanSquare"]
    T.(field)=repmat(double(sixgr.util.structGet(txMetadata,field,NaN)),n,1);
end
for field=["ADCClippingPopulation","ADCClippingSource","ADCClippingThresholdRule", ...
        "ADCClippingStatus","ADCConventionConfigured","IQImbalanceModel","ConfiguredIQImbalanceSource", ...
        "PhaseNoiseAvailableBackend","PhaseNoiseTruthClassification","PhaseNoiseApproximationReason", ...
        "AGCControlModel","AGCExecutionStatus","AGCGainEvidenceSource", ...
        "AGCOverloadGuardObservationPlane", ...
        "ADCErrorMeasurementStatus","ADCErrorDefinition","ADCErrorDomain"]
    T.(field)=repmat(string(sixgr.util.structGet(rxMetadata,field,"unavailable")),n,1);
end
for field=["PAModel","DACClippingPopulation","DACClippingSource", ...
        "DACClippingThresholdRule","DACClippingStatus","DACReferenceDomain","DACReferenceSource", ...
        "DACErrorMeasurementStatus","DACErrorDefinition","DACErrorDomain"]
    T.(field)=repmat(string(sixgr.util.structGet(txMetadata,field,"unavailable")),n,1);
end
T.TxRFExecutionStatus=repmat(txMetadata.RFExecutionStatus,n,1);
T.RxRFExecutionStatus=repmat(rxMetadata.RFExecutionStatus,n,1);
% Compatibility field has one explicit owner. Never sum TX and RX counts
% (different captures/port populations), or infer clipping from CFR policy.
T.PeakClippingEvents=T.DACClippedSampleCount;
T.PeakClippingEventsSource=repmat("actual_TX_DAC_clipped_complex_samples",n,1);
T.PeakClippingEventsPopulation=T.DACClippingPopulation;
T.PeakClippingEventsStatus=T.DACClippingStatus;
% The same completed RX capture owns its noise calibration. Control/RA
% reducers must retain it too, without treating injection metadata as SINR.
T=sixgr.truth.bindSharedNoiseReferenceEvidence(T,planes);
% Control/reference rows share a capture. Bind its actual endpoint metadata
% once, without rereading/hashing gigabytes of IQ per beam or RS row. This
% mode makes no whole-capture sample-statistic or waveform-hash claim.
if metadataOnly, return; end
T.RxRFInputWaveformSHA256=string(sixgr.rf.waveformSHA256(pre.readComplete()));
T.RxRFOutputWaveformSHA256=string(sixgr.rf.waveformSHA256(post.readComplete()));
T.TxRFOutputWaveformSHA256=string(sixgr.rf.waveformSHA256(tx.readComplete()));
txEvidence=struct('NodeID',extractBefore(ids(itx),':tx'), ...
    'CaptureStartSample',tx.StartSample,'CaptureEndSampleExclusive',tx.EndSampleExclusive, ...
    'OutputWaveformSHA256',T.TxRFOutputWaveformSHA256,'ExecutedSegments',txRecords);
rxEvidence=struct('NodeID',extractBefore(ids(ipost),':post_rf'), ...
    'CaptureStartSample',post.StartSample,'CaptureEndSampleExclusive',post.EndSampleExclusive, ...
    'InputWaveformSHA256',T.RxRFInputWaveformSHA256, ...
    'OutputWaveformSHA256',T.RxRFOutputWaveformSHA256,'ExecutedSegments',rxRecords);
manifest=struct('Contract',"actual_shared_rf_observation/v1", ...
    'SampleRateHz',post.SampleRateHz,'TX',txEvidence,'RX',rxEvidence);
T.RFExecutionManifestJSON=string(jsonencode(manifest));
T.RFExecutionManifestSHA256=localHash(T.RFExecutionManifestJSON);
T.RFImpairmentChainId="rfpath_"+T.RFExecutionManifestSHA256;
T.RxRFImpairmentChainId="rfobs_"+localHash(jsonencode(rxEvidence));
T.RFStrictOk=all([txRecords.RFStrictOk]) && all([rxRecords.RFStrictOk]);
T.RFExecutionEvidenceSource="actual_captured_IQ_and_ordered_retained_RF_execution_segments";
T.RxRFStreamStartSample=post.StartSample;
T.RxRFStreamEndSampleExclusive=post.EndSampleExclusive;
T.TxRFStreamStartSample=tx.StartSample;
T.TxRFStreamEndSampleExclusive=tx.EndSampleExclusive;
for endpoint=["Tx","Rx"]
    if endpoint=="Tx", records=txRecords; else, records=rxRecords; end
    for field=["RFStageOrder","RFConfiguredStageCount","RFExecutedStageCount"]
        values={records.(field)};
        assert(all(cellfun(@(v)isequaln(v,values{1}),values)), ...
            'sixgr:truth:RFConfigurationChangedWithinCapture', ...
            'Do not flatten different RF configuration epochs within one capture.');
        T.(endpoint+field)=values{1};
    end
    changedCounts=[records.RFAppliedStageCount];
    T.(endpoint+"RFAppliedStageCount")=NaN;
    T.(endpoint+"RFAppliedStageCountStatus")="time_varying_per_execution_segment";
    if all(changedCounts==changedCounts(1))
        T.(endpoint+"RFAppliedStageCount")=changedCounts(1);
        T.(endpoint+"RFAppliedStageCountStatus")="stationary_per_execution_segment";
    end
end
end

function records=localRecords(plane,nodeID,endpoint)
segments=plane.Segments; observation=plane.Observation;
assert(~isempty(segments),'sixgr:truth:MissingRFExecution','RF execution segments are required.');
records=struct([]); intervals=zeros(numel(segments),2);
fields={'RFStreamStartSample','RFStreamEndSampleExclusive','RFConfigurationEpoch', ...
    'RFProcessingMode','RFImpairmentChainId','RFInputWaveformSHA256','RFOutputWaveformSHA256', ...
    'RFStageOrder','RFConfiguredStageCount','RFAppliedStageCount','RFExecutedStageCount','RFStrictOk','RFFailureReason'};
for k=1:numel(segments)
    e=segments{k}.Execution; nodes=e.(endpoint);
    node=nodes(string({nodes.ID})==nodeID);
    assert(isscalar(node) && all(isfield(node.Replay,fields)), ...
        'sixgr:truth:MissingRFExecution','Each interval must retain the actual endpoint RF result.');
    r=struct();
    for f=fields, r.(f{1})=node.Replay.(f{1}); end
    assert(string(r.RFProcessingMode)=="retained_sample_stream" && ...
        r.RFStreamStartSample==e.StartSample && r.RFStreamEndSampleExclusive==e.EndSampleExclusive && ...
        localIsHash(r.RFInputWaveformSHA256) && localIsHash(r.RFOutputWaveformSHA256), ...
        'sixgr:truth:RFExecutionClockMismatch','RF hashes must describe the executed physical interval.');
    intervals(k,:)=[r.RFStreamStartSample r.RFStreamEndSampleExclusive];
    if k==1, records=r; else, records(k)=r; end %#ok<AGROW>
end
assert(intervals(1,1)<=observation.StartSample && intervals(end,2)>=observation.EndSampleExclusive && ...
    all(intervals(2:end,1)==intervals(1:end-1,2)), ...
    'sixgr:truth:RFExecutionCoverageGap','No missing, reordered or overlapping RF processor intervals are permitted.');
end

function yes=localIsHash(value)
yes=isscalar(string(value)) && ~isempty(regexp(char(string(value)),'^[0-9a-fA-F]{64}$','once'));
end
function hash=localHash(value)
hash=string(sixgr.util.sha256Hex(uint8(unicode2native(char(value),'UTF-8'))));
end
