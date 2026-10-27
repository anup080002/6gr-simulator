function transaction=prepareULMACControlTransaction(phr,bsr,power,postLCPBytes,slot,policy,authority,availableBytes)
% UE-owned final MAC assembly transaction, never a scheduler preview.
assert(isa(phr,'sixgr.l2.mac.PHRStateMachine')&&isa(bsr,'sixgr.l2.mac.BSRStateMachine'), ...
    'sixgr:mac:UEControlOwnersRequired','Original UE trigger owners required.');
assert(isequal(power.Enabled,true)&&isfinite(power.RequestedPower_dBm)&& ...
    isfinite(power.Pcmax_dBm)&&isfinite(power.PowerHeadroom_dB)&& ...
    abs(power.PowerHeadroom_dB-(power.Pcmax_dBm-power.RequestedPower_dBm))<1e-10, ...
    'sixgr:mac:OriginalAllocationPHRequired','PH must be original uncapped allocation power difference.');
assert(string(authority.Stage)=="original_received_DCI_before_first_TX" && authority.IsNewData, ...
    'sixgr:mac:MACFinalizationAuthority','Original received new-data grant required.');
validateattributes(postLCPBytes,{'numeric'},{'vector','real','finite','integer','nonnegative'});
assert(numel(postLCPBytes)==numel(bsr.Buffers),'sixgr:mac:LCGQueueMismatch','Installed LCG scope differs.');
if nargin<8, availableBytes=5; end % Existing bounded single-LCG reservation contract.
validateattributes(availableBytes,{'numeric'},{'scalar','real','finite','integer','nonnegative','<=',authority.TBSBits/8});
pendingPH=phr.buildReport(struct('PH_dB',power.PowerHeadroom_dB,'PCMAX_dBm',power.Pcmax_dBm),slot,policy.PHRProhibitSlots);
ph=pendingPH;
% Current supported transport has one LCG; its full BSR is two octets incl header.
% Regular/periodic BSR precedes PHR; padding BSR follows it (38.321 5.4.3.1.3).
remaining=availableBytes;
if bsr.PendingTrigger=="padding"
    if ph.Transmit&&remaining>=3, remaining=remaining-3;
    elseif ph.Transmit, ph=struct('Transmit',false,'Reason',"insufficient_original_CE_space"); end
    br=bsr.previewReport(postLCPBytes,min(2,remaining),slot);
else
    br=bsr.previewReport(postLCPBytes,min(2,remaining),slot);
    if br.Transmit, remaining=remaining-br.MACSubPDUBytes; end
    if ph.Transmit&&remaining<3, ph=struct('Transmit',false,'Reason',"insufficient_original_CE_space"); end
end
items=repmat(struct('LCID',0,'Payload',uint8.empty(1,0),'OwnerID',""),0,1);
if ph.Transmit
    assert(isfield(authority,'PowerManagementBackoffApplied')&& ...
        islogical(authority.PowerManagementBackoffApplied)&&isscalar(authority.PowerManagementBackoffApplied), ...
        'sixgr:mac:PHRPowerBackoffAuthority','PHR P bit needs explicit power-management authority.');
    bytes=sixgr.l2.mac.BSR_PHR.encodeSingleEntryPHR(power.PowerHeadroom_dB,power.Pcmax_dBm, ...
        authority.PowerManagementBackoffApplied);
    items(end+1,1)=struct('LCID',57,'Payload',reshape(bytes,1,[]),'OwnerID',"PHR-"+ph.ReportSHA256);
end
if br.Transmit
    items(end+1,1)=struct('LCID',br.LCID,'Payload',reshape(br.Payload,1,[]),'OwnerID',"BSR-"+br.ReportID);
end
transaction=struct('Authority',authority,'PHRReport',ph,'BSRReport',br, ...
    'PendingPHRPreview',pendingPH,'AvailableControlBytes',availableBytes, ...
    'PowerControl',power,'PostLCGBufferBytes',postLCPBytes,'ControlSubPDUs',items);
transaction.SHA256=sixgr.l2.mac.MACHash.of(transaction);
end
