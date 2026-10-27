function [state,plan]=prepareSharedULMAC(state,plan)
% Final UE MAC bytes are constructed only after its actual received assignment.
cfg=plan.Cfg; p=cfg.phy.mac.uplinkControl;
if ~p.Enabled || sixgr.truth.GrantPreparation.grantIsRetransmission(plan.GrantSnapshot), return; end
ue=plan.UEIndex; a=cfg.phy.pusch.receivedDCIAssignment;
cellID=double(sixgr.util.structGet(cfg,'lls6g.userContext.RuntimeServingCell',NaN));
[state,scope]=sixgr.truth.ensureULMACOwners(state,cfg,ue,cellID);
decisionSlot=state.CurrentSlot;
sixgr.truth.refreshUEMACQueue(state,ue,p,decisionSlot);
state.SharedUEPHRStates{ue}.receivedNewDataGrant(decisionSlot);
state.SharedUEBSRStates{ue}.receivedNewDataGrant(decisionSlot);
allocation=sixgr.phy.pdcch.connectedDataAllocation(cfg,a);
fs=scope.SampleRateHz; ofdm=nrOFDMInfo(allocation.Carrier,'SampleRate',fs);
ns=double(allocation.Carrier.SymbolsPerSlot);
offset=mod(double(allocation.Carrier.NSlot),double(allocation.Carrier.SlotsPerSubframe))*ns;
count=sum(double(ofdm.SymbolLengths(offset+(1:ns))));
geometry=struct('Carrier',allocation.Carrier,'PUSCH',allocation.ChannelConfig,'NumSamples',count);
owner=cfg.phy.pusch.receivedPowerControlState;
[pc,powerCfg,powerState,next]=owner.previewPUSCHAllocation(cfg,a,geometry,cfg.phy.pusch.receivedTPCObservation);
assert(allocation.NominalTBSBits==numel(plan.TrialContext.TransportBlockBits), ...
    'sixgr:mac:ReceivedMACSizeMismatch','MAC TBS must be derived independently from original received DCI.');
authority=struct('Stage',"original_received_DCI_before_first_TX", ...
    'AssignmentDigest',string(a.AssignmentDigest),'OriginalGrantContextID',string(plan.GrantSnapshot.PHYGrantContextId), ...
    'TBSBits',allocation.NominalTBSBits,'IsNewData',true, ...
    'PowerManagementBackoffApplied',p.PHRPowerManagementBackoff);
volume=state.ProtocolBridge.pendingTransmitBytes(ue,'UL');
selected=plan.GrantSnapshot.ProtocolRLCSegmentPayloadBytes;
validateattributes(selected,{'numeric'},{'scalar','finite','integer','nonnegative','<=',volume.TotalBSRBytes});
post=zeros(1,p.LCGID+1); post(p.LCGID+1)=volume.TotalBSRBytes-selected;
transaction=sixgr.l2.mac.prepareULMACControlTransaction(state.SharedUEPHRStates{ue}, ...
    state.SharedUEBSRStates{ue},pc,post,decisionSlot,p,authority, ...
    plan.GrantSnapshot.ProtocolMACControlReservationBytes);
[bits,receipt]=state.ProtocolBridge.finalizeULControl(plan.GrantSnapshot.TransportBlockId,transaction.ControlSubPDUs,authority);
grant=plan.GrantSnapshot;
grant.ProtocolMACSHA256=char(receipt.MACSHA256); grant.ProtocolMACPaddingBytes=receipt.MACPaddingBytes;
grant.MACControlTransaction=transaction; grant.MACFinalizationReceipt=receipt;
grant.MACOwnerScope=scope;
plan.GrantSnapshot=grant; plan.TrialContext.GrantSnapshot=grant; plan.TrialContext.TransportBlockBits=bits;
preview=struct('AssignmentDigest',string(a.AssignmentDigest),'Geometry',geometry, ...
    'PowerControl',pc,'Config',powerCfg,'State',powerState,'NextOwner',next);
plan.Cfg.phy.pusch.receivedAllocationPowerPreview=preview;
end
