function [cfg,admitted,status] = bindReceivedPRACHAssociation(cfg,state,ue,slot)
% Bind a NEW shared CBRA attempt to received SIB1/SSB authority before mutation.
% TS 38.213 V18.8.0 8.1 owns association; one-slot preparation is simulator policy.
admitted=false; status="no_current_received_MIB";
if isfield(cfg,'SharedReceivedPRACHSelection'), cfg=rmfield(cfg,'SharedReceivedPRACHSelection'); end
[available,~,binding]=sixgr.truth.ReceivedMIBDelivery.current(state,ue);
if ~available, return; end
recovery=state.DecodedSIB1RecoveryByUE{ue};
required={'SIB1RxTree','SIB1RxTreeHash','ReceivedMIBGenerationID','ReceivedMIBBinding', ...
    'ReceivedSIB1AvailableAtSample'};
if ~isstruct(recovery) || ~all(isfield(recovery,required))
    status="no_original_received_SIB1_association_authority"; return;
end
if string(recovery.ReceivedMIBGenerationID)~=binding.GenerationID || ...
        ~isequaln(recovery.ReceivedMIBBinding,binding)
    status="received_SIB1_belongs_to_another_acquisition"; return;
end
timing=cfg.SharedRATimingBinding;
[timingAvailable,~,currentTiming]=sixgr.truth.ReceivedSSBTimingDelivery.current( ...
    state,ue,cfg,cfg.random_access.associated_ssb_index);
if ~timingAvailable || ~isequaln(timing,currentTiming) || ...
        state.SelectedSSBIndexByUE(ue)~=timing.SSBIndex
    status="selected_SSB_timing_changed_before_association"; return;
end
assert(timing.AcquisitionGenerationID==binding.GenerationID && ...
    timing.OriginalBCHBinding.ServingCell==binding.ServingCell, ...
    'sixgr:truth:ReceivedPRACHAssociationIdentity','Selected beam and received common SI must share acquisition/cell authority.');
tree=recovery.SIB1RxTree;
[~,digest]=sixgr.rrc.asn1.compareSIB1Trees(tree,tree);
assert(string(digest.RxTreeHash)==string(recovery.SIB1RxTreeHash), ...
    'sixgr:truth:ReceivedPRACHAssociationIdentity','Original decoded SI tree changed after delivery.');
% Cache only immutable decoded-input arithmetic, not admission or UE state.
% A new MIB context or SI tree necessarily obtains a new native calendar.
persistent cachedKey cachedNative cachedValidity
key=string(binding.ContextSHA256)+":"+string(digest.RxTreeHash);
if isempty(cachedKey) || cachedKey~=key
    [cachedValidity,cachedNative]=sixgr.mac.ra.resolveReceivedPRACHValidity(tree,binding.Context,[]);
    cachedKey=key;
end
native=cachedNative; validity=cachedValidity;
cfg.phy.prach.timing=native;
now=state.SharedWaveformStream.Events.NextSampleIndex;
d=binding.Context.Data;
ticksPerSample=double(sixgr.phy.frame.AbsoluteTime.TicksPerSecond)/d.SampleRateHz;
assert(ticksPerSample==fix(ticksPerSample),'sixgr:truth:ReceivedPRACHAssociationClock','Use an exact original sample clock.');
radioNow=int64(now)*int64(ticksPerSample)-int64(d.ReceivedFrameOriginSample- ...
    d.AbsoluteFrameNumber*d.SampleRateHz/100)*int64(ticksPerSample);
spec=sixgr.phy.frame.AbsoluteTime.resolveNumerology(struct( ...
    'SCSKHz',native.CarrierSubcarrierSpacingKHz,'CyclicPrefix',cfg.phy.carrier.CyclicPrefix));
% Search one full maximum association period beyond the current clock. This
% is the normative 160-ms association domain, not a forced attach deadline.
last=radioNow+int64(16)*sixgr.phy.frame.AbsoluteTime.TicksPerFrame;
rach=tree.message.c1.systemInformationBlockType1.servingCellConfigCommon.uplinkConfigCommon.initialUplinkBWP.rach_ConfigCommon;
cb=str2double(erase(string(rach.cbPreamblesPerSSB),"n"));
assert(isfinite(cb) && cb>=1 && cb==fix(cb),'sixgr:truth:ReceivedPRACHAssociationIdentity','Invalid received CB partition.');
% Resolve the explicit LLS/test policy within the RECEIVED partition.
% Fixed offsets are not a claim of normative uniform-random CBRA selection.
preambleChoice=sixgr.mac.ra.resolveCBPreambleOffset(cfg.random_access,ue,cb);
q=struct('MIBContextSHA256',binding.ContextSHA256,'SIB1TreeSHA256',string(digest.RxTreeHash), ...
    'SelectedSSBIndex0',timing.SSBIndex,'CBPreambleOffset0',preambleChoice.Offset0, ...
    'KnowledgeSample',now,'SIB1AvailableAtSample',recovery.ReceivedSIB1AvailableAtSample, ...
    'SelectedSSBAvailableAtSample',timing.DeliveredAvailableSample, ...
    'SelectedSSBReferenceSHA256',timing.BindingSHA256, ...
    'EarliestRadioTicks',max(int64(0),radioNow),'EndRadioTicks',last);
while q.EarliestRadioTicks<last
    selected=sixgr.mac.ra.resolveReceivedSSBPRACHSelection(tree,binding.Context,native,validity,q);
    if ~selected.Available, status=selected.Status; return; end
    origin=selected.SelectedNativeOccasion.PRACHWaveformStartTicks+ ...
        int64(selected.NativePeriodIndex0*native.BasePeriodFrames)*sixgr.phy.frame.AbsoluteTime.TicksPerFrame;
    t=sixgr.phy.frame.AbsoluteTime(origin); [~,f,s]=t.floorToSlot(spec);
    preparationSlot=double(f)*spec.SlotsPerFrame+double(s);
    if preparationSlot>=slot, break; end
    % A long-preamble buffer may begin before its active support. Never
    % select a still-future active preamble whose enqueue boundary was missed.
    q.EarliestRadioTicks=selected.ActiveEndTicksExclusive;
end
status="waiting_for_received_SSB_associated_RO";
if ~exist('preparationSlot','var') || preparationSlot~=slot, return; end
receipt=struct('ContractVersion',"received_prach_attempt/v1", ...
    'UEIndex',ue,'ServingCell',binding.ServingCell,'AcquisitionGenerationID',binding.GenerationID, ...
    'SelectedSSBTimingBindingSHA256',timing.BindingSHA256,'SIB1TreeSHA256',string(digest.RxTreeHash), ...
    'PreparationSlot',slot,'NativeResolution',native,'Validity',validity,'Selection',selected, ...
    'CBPreambleChoice',preambleChoice);
receipt.SHA256=sixgr.rrc.asn1.asn1SHA256Hex(uint8(unicode2native(jsonencode(receipt),'UTF-8')));
cfg.SharedReceivedPRACHSelection=receipt;
admitted=true; status="received_SSB_associated_RO_admitted";
end
