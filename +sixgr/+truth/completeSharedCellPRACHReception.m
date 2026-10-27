function [state,receipt]=completeSharedCellPRACHReception(state,item)
% Actual cell-owned shared capture -> detector -> original cell evidence.
% No UE attempt/prepared waveform, transmitted preamble, or success oracle.
owner=state.SharedWaveformStream;
owner.validateCellPRACHCompletion(item);
prior=sixgr.util.structGet(state,'CellPRACHReceiveReceipts',{});
assert(~any(cellfun(@(r)r.ObservationID==string(item.ID),prior)), ...
    'sixgr:truth:DuplicateCellPRACHCompletion','Execute each original cell receive window once.');
c=item.Context.Calendar; p=item.Context.Plan; cfg=item.Context.Config;
ids=string({item.Planes.ReceiverID});
pre=item.Planes(endsWith(ids,':pre_rf')).Observation;
post=item.Planes(endsWith(ids,':post_rf')).Observation;
native=c.Native; row=p.OriginalNativeRow;
carrier=sixgr.phy.grid.makeCarrier(cfg);
absoluteSlot=double(row.AbsoluteSlot)+p.NativePeriodIndex0*native.PeriodCarrierSlots;
carrier.NFrame=floor(absoluteSlot/carrier.SlotsPerFrame); carrier.NSlot=mod(absoluteSlot,carrier.SlotsPerFrame);
pc=c.PRACHConfig;
prach=nrPRACHConfig('FrequencyRange',char(native.ToolboxFrequencyRange), ...
    'DuplexMode',char(native.DuplexMode),'ConfigurationIndex',pc.PRACHConfigurationIndex, ...
    'SubcarrierSpacing',pc.PRACHSubcarrierSpacing,'SequenceIndex',pc.SequenceIndex, ...
    'PreambleIndex',0,'RestrictedSet',char(pc.RestrictedSet),'ZeroCorrelationZone',pc.ZeroCorrelationZone, ...
    'FrequencyStart',pc.FrequencyStart,'NPRACHSlot',p.PRACHSlotIndex0, ...
    'ActivePRACHSlot',row.ActivePRACHSlot,'TimeIndex',row.TimeIndex,'FrequencyIndex',row.FrequencyIndex);
occasion=struct('Carrier',carrier,'PRACH',prach,'SlotIndex0',absoluteSlot, ...
    'PRACHSlotIndex0',p.PRACHSlotIndex0,'TimeIndex',row.TimeIndex, ...
    'ActivePRACHSlot',row.ActivePRACHSlot,'FrequencyIndex',row.FrequencyIndex, ...
    'RARNTISymbolIndex',row.RARNTISymbolIndex,'RARNTISlotIndex',row.RARNTISlotIndex);
cfg.lls6g.receiverSync.ReceivedWaveformTimingPlane="untrimmed_shared_physical_receive_stream";
cfg.lls6g.receiverSync.ChannelFilterDelay_samples=c.FilterDelaySamples;
cfg.lls6g.receiverSync.ULObservationSearchGuard_samples=p.SearchGuardSamples;
det=sixgr.phy.ra.detectConfiguredPRACH(post.readComplete(),cfg,pc,occasion);
assert(isequal(det.CandidatePreambles,(0:63).') && ~isfield(det,'RAPIDMatchesTx'), ...
    'sixgr:truth:CellPRACHCandidateScope','Actual detector must search all64 candidates without a UE TX identity.');
detections=struct([]);
if det.Detected
    detections=sixgr.util.structGet(det,'Detections',det);
end
% Receiver decision and CB admission are different facts. A detected RAPID
% outside the configured RO/SSB CB partition cannot create a RAR response.
admitted=cell(0,1); association=c.Association; map=association.Mapping;
periodRO=height(native.Occasions)*association.AssociationPeriodConfigurationCount;
ordinal=mod(p.OccasionOrdinal1-1,periodRO)+1;
for k=1:numel(detections)
    d=detections(k); rapid=d.DetectedPreambleIndex;
    match=map.Ordinal==ordinal & rapid>=map.CBPreambleStart0 & rapid<map.CBPreambleStart0+map.CBPreambleCount;
    assert(nnz(match)<=1,'sixgr:truth:AmbiguousCellPRACHAssociation','A detected RAPID has at most one original SSB association.');
    if ~any(match), continue; end
    d.ServingCell=c.CellID; d.CellId=c.PhysicalCellID; d.PRACHAbsoluteSlot=absoluteSlot;
    d.PRACHOccasionSymbol=row.RARNTISymbolIndex; d.PRACHFrequencyIndex=row.FrequencyIndex;
    d.RARNTI=p.ExpectedRARNTI; d.SampleRateHz=post.SampleRateHz;
    d.AssociatedSSBIndex0=map.SSBIndex0(match);
    admitted{end+1,1}=d; %#ok<AGROW>
end
if isempty(admitted), admitted=struct([]); else, admitted=vertcat(admitted{:}); end
root=string(sixgr.util.structGet(cfg,'run.rootRunFolder',''));
assert(strlength(root)>0,'sixgr:truth:CellPRACHEvidenceRootRequired','Retain actual cell receiver evidence in its original run.');
receipt=struct('ContractVersion',"completed_cell_PRACH_receiver/v1", ...
    'ObservationID',string(item.ID),'ServingCell',c.CellID,'PhysicalCellID',c.PhysicalCellID, ...
    'CellCalendarSHA256',c.SHA256,'Plan',p,'OriginalDetectorResult',det, ...
    'AdmittedDetections',admitted,'ReceiverExecuted',true,'UETransmissionRequired',false, ...
    'ArmedAtSample',item.Context.ArmedAtSample,'CompletedAtSample',owner.Events.NextSampleIndex, ...
    'PreRFObservationSHA256',pre.sampleHash(),'PostRFObservationSHA256',post.sampleHash(), ...
    'OriginalPreRFArchive',pre.archiveCompleted(root),'OriginalPostRFArchive',post.archiveCompleted(root), ...
    'Source',"cell_common_calendar_original_shared_gNB_post_RX_samples", ...
    'Scope',"actual_PRACH_receiver_and_CB_partition_admission_not_RAR_or_access_completion");
receipt.SHA256=string(sixgr.util.sha256Hex(jsonencode(sixgr.util.jsonSafeValue(receipt))));
prior{end+1,1}=receipt; state.CellPRACHReceiveReceipts=prior;
folder=fullfile(root,'control','cell_prach'); sixgr.util.ensureFolder(folder);
sixgr.util.jsonWrite(fullfile(folder,string(item.ID)+".json"),receipt);
row=table(string(item.ID),c.CellID,c.PhysicalCellID,absoluteSlot+1,p.OccasionOrdinal1, ...
    p.ExpectedRARNTI,p.ReceiveStartSample,p.ReceiveEndSampleExclusive,p.SampleRateHz, ...
    receipt.ArmedAtSample,receipt.CompletedAtSample,true,det.Detected,det.DetectedPreambleIndex, ...
    numel(admitted),det.PropagationTimingOffsetSamples,string(det.DetectorBackend), ...
    det.Threshold,c.SHA256,receipt.PostRFObservationSHA256,receipt.SHA256, ...
    'VariableNames',{'ObservationID','ServingCell','PhysicalCellID','Slot','OccasionOrdinal1', ...
    'RARNTI','ObservationStartSample','ObservationEndSampleExclusive','ObservationSampleRateHz', ...
    'ArmedAtSample','CompletedAtSample','ReceiverExecuted','PreambleDetected','DetectedPreambleIndex', ...
    'AdmittedCBPreambleCount','PropagationTimingOffsetSamples','DetectorBackend','DetectionThreshold', ...
    'CellCalendarSHA256','PostRFObservationSHA256','ReceiptSHA256'});
row=sixgr.truth.bindCoupledExecutionIdentity(row,cfg,'cell_PRACH_receiver',true);
tables=sixgr.util.structGet(state,'ControlTrials.RAEvidenceTables',struct());
old=sixgr.util.structGet(tables,'cell_prach_receiver_observations',table());
if isempty(old), old=row; else, old=[old;row]; end
state.ControlTrials.RAEvidenceTables.cell_prach_receiver_observations=old;
sixgr.util.csvWriteTable(fullfile(root,'control','csv','cell_prach_receiver_observations.csv'),old);
[state,response]=sixgr.truth.prepareReceivedCellRARResponse(state,item,receipt);
responses=sixgr.util.structGet(state,'CellRARResponseDecisions',{});
responses{end+1,1}=response;state.CellRARResponseDecisions=responses;
% This is an admission/enqueue record; no executed or decoded success is added.
decision=rmfield(response,'Prepared');
sixgr.util.jsonWrite(fullfile(folder,string(item.ID)+"_response_decision.json"),decision);
end
