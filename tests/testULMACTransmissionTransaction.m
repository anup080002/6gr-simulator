function ok=testULMACTransmissionTransaction()
% Authored actual-TX callback boundary; no waveform/CRC claim.
c=struct('enabled',true,'strict',true,'configuration_epoch',1);
c.rlc=struct('sn_bits',18,'poll_pdu',16,'poll_byte',65536,'max_retx_threshold',8);
c.pdcp=struct('sn_bits',18,'cipher_algorithm','NEA0','integrity_algorithm','NIA0','t_reordering_ms',50);
c.sdap=struct('pdu_session_id',1,'qfi_to_drb',struct('qfi',9,'drb_id',1));
c.mac=struct('lcid',4); c.traffic.sessions=struct('flow_id','f','pdu_session_id',1,'qfi',9,'direction','BIDIR');
b=sixgr.protocol.WaveformProtocolBridge(c,1);
b.enqueuePacket(1,'UL','original',uint8(1:35),0);
p=struct('LCGID',0,'PHRProhibitSlots',2);
s=struct('RunID',"run",'ExecutionID',"exec",'ConfigHash',"cfg",'UEID',1, ...
    'CellID',1,'RNTI',4660,'ConfigurationEpoch',1,'SampleRateHz',1000);
ph=sixgr.l2.mac.PHRStateMachine(1,20); ph.trigger('configuration',0);
bs=sixgr.l2.mac.BSRStateMachine(1,1,10,80); bs.arrival(0,39);
state=struct('ProtocolBridge',b,'ULMACPolicy',p,'SharedUEMACScopes',{{s}}, ...
    'SharedUEPHRStates',{{ph}},'SharedUEBSRStates',{{bs}});
[~,e]=b.prepareQueuedSegment(1,'UL','tb1',256,.001,5);
post=39-e.SegmentPayloadBytes;
power=struct('Enabled',true,'RequestedPower_dBm',25,'Pcmax_dBm',23,'PowerHeadroom_dB',-2);
authority=struct('Stage',"original_received_DCI_before_first_TX",'IsNewData',true, ...
    'AssignmentDigest',repmat('a',1,64),'OriginalGrantContextID',repmat('b',1,64), ...
    'TBSBits',256,'PowerManagementBackoffApplied',false);
t=sixgr.l2.mac.prepareULMACControlTransaction(ph,bs,power,post,1,p,authority);
[bits,receipt]=b.finalizeULControl('tb1',t.ControlSubPDUs,authority);
g=struct('ProtocolPayloadSameWaveformTruth',true,'TransportBlockId',"tb1", ...
    'ProtocolRLCSegmentPayloadBytes',e.SegmentPayloadBytes,'MACControlTransaction',t, ...
    'MACFinalizationReceipt',receipt,'MACOwnerScope',s,'ProtocolMACSHA256',receipt.MACSHA256);
identity=struct('SampleRateHz',1000,'RNTI',4660,'TransmissionID',"tx1");
% Pure validate and corrupt actual-byte rejection leave every owner intact.
sixgr.truth.sharedMACTransmissionTransaction('validate',state,g,bits,1,"UL",identity,2,2);
assert(b.pendingTransmitBytes(1,'UL').TotalBSRBytes==39&&ph.PendingTrigger=="configuration"&&bs.PendingTrigger=="regular");
bad=bits; bad(1)=1-bad(1);
rejects(@()sixgr.truth.sharedMACTransmissionTransaction('commit',state,g,bad,1,"UL",identity,2,2));
assert(b.pendingTransmitBytes(1,'UL').TotalBSRBytes==39&&isempty(ph.CommittedTransmissionIDs));
% An original tail arrival remains queued; it cannot alter the encoded BSR.
b.enqueuePacket(1,'UL','tail',uint8(51:60),.0015); bs.arrival(0,14);
sixgr.truth.sharedMACTransmissionTransaction('commit',state,g,bits,1,"UL",identity,2,2);
assert(b.pendingTransmitBytes(1,'UL').TotalBSRBytes==post+14&&bs.Buffers==post+14);
assert(ph.PendingTrigger=="none"&&numel(ph.CommittedTransmissionIDs)==1);
rejects(@()sixgr.truth.sharedMACTransmissionTransaction('commit',state,g,bits,1,"UL",identity,2,2));
% Explicit HARQ retry carries original bytes without new queue/report commits.
g.IsRetransmission=true; identity.TransmissionID="retry";
sixgr.truth.sharedMACTransmissionTransaction('commit',state,g,bits,1,"UL",identity,4,4);
assert(b.pendingTransmitBytes(1,'UL').TotalBSRBytes==post+14&&numel(ph.CommittedTransmissionIDs)==1);
ok=true;
end
function rejects(f)
failed=false; try, f(); catch, failed=true; end; assert(failed,'Expected original TX transaction rejection.');
end
