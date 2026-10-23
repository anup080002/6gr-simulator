function [state, row, reception, csi] = completeSharedCSIRSReception(state, item)
%COMPLETESHAREDCSIRSRECEPTION Receive one independently scheduled CSI-RS.
arguments
    state (1,1) struct
    item (1,1) struct
end
assert(string(item.Kind) == "CSIRS" && ...
    isfield(state,"SharedWaveformStream") && ...
    isa(state.SharedWaveformStream,"sixgr.truth.CoupledWaveformStream"), ...
    'sixgr:truth:InvalidSharedCSIRSCompletion', ...
    'CSI-RS completion belongs to the shared physical owner.');
assert(isfield(item,'ID') && isscalar(string(item.ID)) && ...
    ~ismissing(string(item.ID)) && strlength(strtrim(string(item.ID)))>0, ...
    'sixgr:truth:InvalidSharedCSIRSCompletion', ...
    'A completed CSI-RS reception must retain its actual parent receive-window ID.');
context = item.Context;
prepared = context.Prepared;
assert(string(sixgr.util.structGet(prepared,"ExecutionStage","")) == ...
    "csirs_waveform_prepared_not_received", ...
    'sixgr:truth:InvalidSharedCSIRSPreparation', ...
    'Receive only the retained independent CSI-RS preparation.');

[post,pre,transmitted,replay,receiverObservation] = ...
    sixgr.truth.sharedObservationEvidence(item.Planes,prepared);
receiverInput = receiverObservation.readComplete();
physicalInput = pre.readComplete();
assert(isequal(size(receiverInput),size(physicalInput)), ...
    'sixgr:truth:CSIRSReceiverPlaneDimensions', ...
    'CSI-RS post-front-end and physical receive planes must share one window.');
searchWindow = [0 max(0,size(receiverInput,1)-prepared.NumSamples)];
reception = sixgr.phy.refsig.receiveCSIRSWaveform( ...
    prepared.Carrier,prepared.ReceiverConfig,receiverInput,physicalInput, ...
    searchWindow,replay);
[csi,reportInfo] = sixgr.phy.refsig.computeCSIRSFeedback( ...
    prepared.Carrier,prepared.ReceiverConfig,reception);
assert(~reportInfo.PDSCHDecodeAttempted && ...
    ~reportInfo.PDSCHResourceAllocationAttempted && ...
    ~reportInfo.DCIConsumed && ~reportInfo.HARQStateConsumed, ...
    'sixgr:truth:IndependentCSIRSReportConsumedDataState', ...
    'Independent CSI-RS reporting cannot consume data/control decoder state.');

context.UEIndex = double(item.UE);
trialStruct = sixgr.truth.buildIndependentCSIRSTrialRow( ...
    prepared.ReceiverConfig,prepared,reception,csi,context);
row = struct2table(trialStruct,"AsArray",true);
% The completed parent owns the receive-window identity. Its planes need not
% carry an ID, and a measurement digest is not a substitute for this window.
% Retain it even when private selection-quality scoring is disabled.
row.ReceiverWindowID = string(item.ID);
row=sixgr.truth.bindSharedRFExecutionEvidence(row,item.Planes,true);
receivedEvidence=sixgr.link.receivedWaveformEvidence(receiverObservation);
for name=string(fieldnames(receivedEvidence)).'
    row.(name)=receivedEvidence.(name);
end
row.PhysicalMeasurementObservationSHA256=pre.sampleHash();
row.PhysicalMeasurementObservationHashPlane="receiver_antenna_connector_pre_composite_front_end";
% Execute only after practical CSI reception/report calculation. This
% measures the actual transmitter chain; it never claims RX-pilot EVM.
paired=sixgr.phy.refsig.pairCSIRSTransmitterSymbols(prepared,transmitted);
% state.RunFolder belongs to air_interface in a full bundle. Paired sample
% references are relative to the canonical RUN root, including control/CSV
% mirrors; never add air_interface twice or search outside this run.
storageRoot=string(sixgr.util.structGet(prepared.ReceiverConfig,'run.rootRunFolder',''));
assert(isscalar(storageRoot) && ~ismissing(storageRoot) && strlength(strtrim(storageRoot))>0, ...
    'sixgr:truth:MissingCSIRSArtifactRunRoot', ...
    'Completed CSI-RS sample storage requires the configured run.rootRunFolder.');
% EVM pairs and a channel-estimate MAT do not retain the receiver's input.
% When raw IQ capture is enabled, keep both actual synchronization planes
% losslessly for independent receiver replay. This runs after CSI selection
% and cannot supply an injected delay/CFO or noiseless channel to the UE.
if sixgr.util.persistenceEnabled() && ...
        logical(sixgr.util.structGet(prepared.ReceiverConfig,'outputs.rawIQCaptureEnabled',false)) && ...
        logical(sixgr.util.structGet(prepared.ReceiverConfig,'outputs.saveRawWaveforms',false))
    for prefix=["Receiver","PhysicalMeasurement"]
        samples=receiverInput;
        if prefix=="PhysicalMeasurement", samples=physicalInput; end
        receipt=sixgr.phy.waveform.CompletedSampleArchive.write(storageRoot,samples);
        assert(receipt.Manifest.SampleSHA256==row.(prefix+"ObservationSHA256"), ...
            'sixgr:truth:CSIRSObservationArchiveIdentity', ...
            'The immutable CSI-RS archive must match the exact received plane.');
        row.(prefix+"ObservationArchiveFile")=string(receipt.RelativePath);
        row.(prefix+"ObservationArchiveFileSHA256")=string(receipt.FileSHA256);
        row.(prefix+"ObservationArchiveReceiptJSON")=string(jsonencode(receipt));
    end
end
[desired,channelSource,channelCaptures]=sixgr.truth.sharedLinkScoringObservation( ...
    item.Planes,prepared,context.DesiredReferencePlane);
row = sixgr.truth.bindIndependentCSIRSClock( ...
    row,prepared,post,state.SharedWaveformStream.Events.NextSampleIndex, ...
    state.SharedWaveformStream.Physical.ConfigurationEpoch);
if isfield(context,'PopulationIdentity')
    % Bind the queue's frozen population to an actual completed transmission,
    % before either channel/selection archive becomes immutable. Later live
    % sweep/configuration state is not the identity of this observation.
    records=state.SharedWaveformStream.CSIRSTransmissions;
    hit=find(string({records.ComponentID})==string(context.ComponentID));
    assert(isscalar(hit),'sixgr:truth:CSIObservationPopulationReceipt', ...
        'A completed CSI observation must match exactly one actual TX receipt.');
    row=sixgr.truth.bindCSIObservationPopulation( ...
        row,context.PopulationIdentity,records(hit),string(context.ComponentID));
end
% Independent prerequisite only, after practical measurement/reporting. A
% completed desired LINK is not automatically an isolated CSI port. Keep
% multiport/resource and finite-memory contamination explicitly unsupported;
% this does not provide a power oracle or change any UE recommendation.
try
    isolation=sixgr.truth.sharedCSIRSComponentIsolation( ...
        item,reception,desired,channelSource,replay,state.SharedWaveformStream);
catch cause
    isolation=sixgr.truth.sharedCSIRSComponentIsolation();
    isolation.Status="unavailable_original_CSI_reference_isolation_proof_failed";
    isolation.ErrorIdentifier=string(cause.identifier);
end
row.CSIRSReferenceIsolationAvailable=isolation.Available;
row.CSIRSReferenceIsolationStatus=string(isolation.Status);
row.CSIRSReferenceIsolationEvidenceJSON=string(jsonencode(isolation));
row.CSIRSReferenceIsolationEvidenceSHA256=sixgr.util.sha256Hex(char(row.CSIRSReferenceIsolationEvidenceJSON));
row.CSIRSReferenceIsolationErrorIdentifier=string(isolation.ErrorIdentifier);
if logical(sixgr.util.structGet(prepared.ReceiverConfig,'measurements.csiSelectionQuality.Enabled',false))
    [row,selectionReference]=sixgr.truth.exportSharedCSIRSChannelEstimate( ...
        storageRoot,row,prepared,reception,channelSource,channelCaptures);
    row=sixgr.truth.bindSharedCSISelectionQuality( ...
        storageRoot,row,prepared,reception,csi,item.Planes,selectionReference,item.ID);
else
    row=sixgr.truth.exportSharedCSIRSChannelEstimate( ...
        storageRoot,row,prepared,reception,channelSource,channelCaptures);
end
row=sixgr.report.retainControlEVMPairs(storageRoot,row,paired);
state = sixgr.truth.CoupledTruthRuntime.applyCSIRSTrial(state,item.UE,row);
end
