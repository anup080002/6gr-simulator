function ok=testRLCApplicationRecovery()
% Declared private-bridge boundary fixtures, not RF/decode qualification.
bytes=uint8(1:12);
owner=struct('Direction',"UL",'UEID',"1",'BearerID',"b1",'ConfigurationEpoch',2, ...
    'PacketID',"original_packet",'RLCFullCount',4097,'PayloadBytes',numel(bytes), ...
    'PayloadSHA256',sixgr.protocol.ProtocolHash.bytes(bytes));
% Initial middle TB was lost. Only actual successful contributors are input;
% two differently segmented new TBs recover it. Original failed TB stays absent.
c=[contributor(owner,"initial_head",0,bytes(1:4)) ...
   contributor(owner,"retx_middle_a",4,bytes(5:6)) ...
   contributor(owner,"retx_middle_b",6,bytes(7:8)) ...
   contributor(owner,"initial_tail",8,bytes(9:12))];
old=c;r=sixgr.truth.validateRLCApplicationRecovery(bytes,owner,c);
assert(r.UniqueCoveredApplicationBytes==12&&r.ContributedApplicationBytes==12&& ...
    r.OverlappingApplicationBytes==0&&~r.FailedOriginalTBSuccessChanged&&~r.ApplicationGoodputCredited&&isequaln(c,old));
overlap=contributor(owner,"decoded_overlap",2,bytes(3:8));
header=contributor(owner,"header_only",0,uint8([]));
r=sixgr.truth.validateRLCApplicationRecovery(bytes,owner,[c overlap header]);
assert(r.UniqueCoveredApplicationBytes==12&&r.ContributedApplicationBytes==18&& ...
    r.OverlappingApplicationBytes==6&&r.HeaderOnlyContributorCount==1);
% Gap cannot be rescued by equal aggregate byte count elsewhere.
reject(@()sixgr.truth.validateRLCApplicationRecovery(bytes,owner,[c([1 2 4]) contributor(owner,"repeated_head_otherTB",0,bytes(1:2))]));
reject(@()sixgr.truth.validateRLCApplicationRecovery(bytes,owner,[c c(1)]));
for field={'PacketID','BearerID','UEID','Direction'}
    bad=c;bad(2).(field{1})="foreign";reject(@()sixgr.truth.validateRLCApplicationRecovery(bytes,owner,bad));
end
bad=c;bad(2).RLCFullCount=4098;reject(@()sixgr.truth.validateRLCApplicationRecovery(bytes,owner,bad));
bad=c;bad(2).ConfigurationEpoch=3;reject(@()sixgr.truth.validateRLCApplicationRecovery(bytes,owner,bad));
bad=overlap;bad.ApplicationBytes(1)=99;
bad.OriginalApplicationFragmentSHA256=sixgr.protocol.ProtocolHash.bytes(bad.ApplicationBytes);
reject(@()sixgr.truth.validateRLCApplicationRecovery(bytes,owner,[c bad]));
bad=c;bad(2).DecodedMACSHA256=sixgr.protocol.ProtocolHash.bytes(uint8(99));
reject(@()sixgr.truth.validateRLCApplicationRecovery(bytes,owner,bad));
bad=c;bad(2).DecodedRLCSHA256=sixgr.protocol.ProtocolHash.bytes(uint8(99));
reject(@()sixgr.truth.validateRLCApplicationRecovery(bytes,owner,bad));
bad=c;bad(2).DecodedBitExact=1;reject(@()sixgr.truth.validateRLCApplicationRecovery(bytes,owner,bad));
bad=c;bad(2).ReleasedAfterPDCP=false;reject(@()sixgr.truth.validateRLCApplicationRecovery(bytes,owner,bad));
bad=c;bad(2).DeliveryTime_s=0;reject(@()sixgr.truth.validateRLCApplicationRecovery(bytes,owner,bad));
badOwner=owner;badOwner.PayloadSHA256=sixgr.protocol.ProtocolHash.bytes(uint8(0));
reject(@()sixgr.truth.validateRLCApplicationRecovery(bytes,badOwner,c));
checkConservation(bytes,owner,c);
ok=true;
end
function checkConservation(bytes,owner,c)
r=sixgr.truth.validateRLCApplicationRecovery(bytes,owner,c);
p=struct('Direction',owner.Direction,'UEIndex',1,'PacketId',owner.PacketID,'ApplicationPacketId',owner.PacketID, ...
    'OfferedBits',96,'ScheduledBits',96,'RemainingBits',0,'DeliveredBits',96,'DeliverySuccess',true, ...
    'OriginalApplicationPayloadSHA256',owner.PayloadSHA256, ...
    'RLCApplicationRecoveryEvidenceJSON',string(jsonencode(r)),'RLCApplicationRecoveryEvidenceSHA256',r.SHA256);
lost=contributor(owner,"lost_initial_middle",4,bytes(5:8));
header=contributor(owner,"initial_header",0,uint8([]));
initial=[ledger(header,1,false);ledger(c(1),2,true);ledger(lost,3,false);ledger(c(4),4,true)];
recovery=[ledger(c(2),1,true);ledger(c(3),2,true)];
state=struct('PacketDeliveryLedgerTable',struct2table(p),'PacketSDULedgerTable',initial, ...
    'RLCRecoveryTransportLedgerTable',recovery);
actual=sixgr.truth.reconcilePacketBitConservation(state);
assert(actual.PacketDeliveryLedgerTable.CompletedApplicationBits==96 && ...
    actual.PacketDeliveryLedgerTable.BitConservationErrorBits==0 && ...
    actual.PacketSDULedgerTable.RecoveredViaRLC(3) && ...
    ~actual.PacketSDULedgerTable.DeliverySuccess(3) && ...
    isequal(actual.PacketSDULedgerTable.ProtocolDecodedBitExact,initial.ProtocolDecodedBitExact));
bad=state;bad.RLCRecoveryTransportLedgerTable(1,:)=[];rejectConservation(@()sixgr.truth.reconcilePacketBitConservation(bad));
bad=state;bad.RLCRecoveryTransportLedgerTable.ProtocolRLCFullCount(1)=99;rejectConservation(@()sixgr.truth.reconcilePacketBitConservation(bad));
bad=state;bad.PacketDeliveryLedgerTable.RLCApplicationRecoveryEvidenceSHA256="changed";rejectConservation(@()sixgr.truth.reconcilePacketBitConservation(bad));
bad=state;bad.PacketSDULedgerTable.ProtocolPayloadSameWaveformTruth(1)=false;rejectConservation(@()sixgr.truth.reconcilePacketBitConservation(bad));
end
function T=ledger(c,index,success)
r=struct('Direction',c.Direction,'UEIndex',1,'PacketId',c.PacketID,'ApplicationPacketId',c.PacketID, ...
    'SegmentIndex',index,'PayloadBits',8*numel(c.ApplicationBytes),'DeliverySuccess',success,'TransportBlockId',c.TransportBlockID, ...
    'RNTI',321,'HARQProcessId',0,'NDIEpoch',1,'ScheduleSlot',1, ...
    'ProtocolRLCFullCount',c.RLCFullCount,'ProtocolBearerID',c.BearerID,'ProtocolUEID',c.UEID, ...
    'ProtocolConfigurationEpoch',c.ConfigurationEpoch,'ProtocolPayloadOffsetBits',8*c.ApplicationOffsetBytes, ...
    'ProtocolPayloadSameWaveformTruth',true,'ProtocolDecodedBitExact',logical(success), ...
    'ProtocolDecodedBitCount',80,'ProtocolMACPDUBytes',10,'ProtocolMACSHA256',c.OriginalMACSHA256, ...
    'ProtocolDecodedMACSHA256',c.DecodedMACSHA256,'ProtocolEncodedRLC_SHA256',c.OriginalRLCSHA256, ...
    'ProtocolDecodedRLC_SHA256',c.DecodedRLCSHA256,'ProtocolPayloadSHA256',c.OriginalApplicationFragmentSHA256, ...
    'ProtocolDecodedPayloadSHA256',c.OriginalApplicationFragmentSHA256, ...
    'ProtocolReceiverEvidenceSource',c.DecoderEvidenceSource,'ProtocolDeliveryStatus',"delivered_after_exact_phy_decode");
if ~success
    r.ProtocolDecodedMACSHA256="";r.ProtocolDecodedRLC_SHA256="";r.ProtocolDecodedPayloadSHA256="";
    r.ProtocolDecodedBitCount=NaN;r.ProtocolDeliveryStatus="not_received";
end
T=struct2table(r);
end
function rejectConservation(fn)
try,fn();catch e,assert(startsWith(string(e.identifier),"sixgr:protocol:"));return;end
error('test:MissingConservationGuard','Expected original recovery join rejection.');
end
function c=contributor(owner,id,offset,bytes)
c=rmfield(owner,{'PayloadBytes','PayloadSHA256'});c.TransportBlockID=id;
c.ApplicationOffsetBytes=offset;c.ApplicationBytes=bytes;
c.OriginalApplicationFragmentSHA256=sixgr.protocol.ProtocolHash.bytes(bytes);
c.OriginalMACSHA256=sixgr.protocol.ProtocolHash.bytes(uint8([1 2 3]));c.DecodedMACSHA256=c.OriginalMACSHA256;
c.OriginalRLCSHA256=sixgr.protocol.ProtocolHash.bytes(uint8([4 5]));c.DecodedRLCSHA256=c.OriginalRLCSHA256;
c.DecodedBitExact=true;c.ReleasedAfterPDCP=true;
c.DecoderEvidenceSource="actual_phy_decoder_bits_demuxed_through_strict_mac_rlc_pdcp_sdap";
c.DecodedTime_s=0.01;c.DeliveryTime_s=0.02;
end
function reject(fn)
try,fn();catch e,assert(strcmp(e.identifier,'sixgr:protocol:InvalidRLCApplicationRecovery'));return;end
error('test:MissingRecoveryGuard','Expected original byte/owner/decoder evidence rejection.');
end
