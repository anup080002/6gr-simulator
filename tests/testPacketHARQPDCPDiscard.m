function ok=testPacketHARQPDCPDiscard()
% Native coded PDSCH + actual protocol owners, with declared callback times.
% No shared RF/calendar or full access qualification is claimed.
setup6GRSimToolkit('Verbose',false);
cfg=localPHYConfig();probe=sixgr.phy.dl.PDSCH_Tx(cfg);tbs=double(probe.TransportBlockSize);
protocol=localProtocolConfig();info=nrOFDMInfo(probe.Carrier);protocol.sample_rate_hz=info.SampleRate;
bridge=sixgr.protocol.WaveformProtocolBridge(protocol,1);
state=struct('NumUsers',1,'ProtocolWaveformEnabled',true,'ProtocolBridge',bridge, ...
 'PacketDeliveryLedgerTable',table(),'PacketSDULedgerTable',table(),'HARQTimelineTable',table(), ...
 'DLQueueBits',0,'DLTransmittedBits',0,'MultiUser',struct('RNTIStart',1001), ...
 'CurrentSlot',1,'CurrentFrame',1,'SlotDuration_s',.001,'DLGrantTraceTable',table(),'ULGrantTraceTable',table());
payload=uint8(1:16);
state=arrival(state,'a',payload,0);state=arrival(state,'b',payload+1,.001);
[bitsA,eA]=bridge.prepareQueuedSegment(1,'DL','tb-a',tbs,.002,0);
assert(abs(bridge.nextTimerExpiry()-.010)<1e-12);
assert(isempty(bridge.advance(.010)));
events=bridge.takeDiscardEvents();assert(numel(events)==1&&events.PacketID=="a"&&events.ApplicationBytesDropped==0);
firstExpiry=events;
assert(isempty(bridge.advance(.011)));
events=bridge.takeDiscardEvents();assert(numel(events)==1&&events.PacketID=="b"&&events.ApplicationBytesDropped==numel(payload));
% Delayed ledger ingestion retains each original expiry/observation sample.
% Enqueue C after both actual PDCP expiries, before publishing their receipts.
state=arrival(state,'c',payload+2,.012);
state=sixgr.truth.applyProtocolPacketDiscards(state,firstExpiry);
state=sixgr.truth.applyProtocolPacketDiscards(state,events);
assert(state.DLQueueBits==16*numel(payload)&&state.PacketDeliveryLedgerTable.DiscardedUnscheduledBits(2)==8*numel(payload));
expectError(@()sixgr.truth.applyProtocolPacketDiscards(state,events),'sixgr:protocol:DuplicateDiscardReceipt');
bad=events;bad.ApplicationBytesDropped=0;
expectError(@()sixgr.truth.applyProtocolPacketDiscards(state,bad),'sixgr:protocol:DiscardIdentity');
gA=grant(eA,'tb-a',tbs,21,1);state=sixgr.truth.CoupledTruthRuntime.commitGrantExecution(state,1,'DL',gA);
txA=sixgr.phy.dl.PDSCH_Tx(cfg,'TransportBlockBits',bitsA);bridge.commitPreparedTransportBlock('tb-a',.020);
[bitsC,eC]=bridge.prepareQueuedSegment(1,'DL','tb-c',tbs,.020,0);
p=bridge.originalTransportApplicationBinding('tb-c');
assert(p.RLCFullCount==1,'Discard must not introduce an RLC SN gap.');
gC=grant(eC,'tb-c',tbs,22,1);state=sixgr.truth.CoupledTruthRuntime.commitGrantExecution(state,1,'DL',gC);
txC=sixgr.phy.dl.PDSCH_Tx(cfg,'TransportBlockBits',bitsC);bridge.commitPreparedTransportBlock('tb-c',.021);
assert(isempty(bridge.advance(.022)));
events=bridge.takeDiscardEvents();assert(numel(events)==1&&events.PacketID=="c"&&events.ApplicationBytesDropped==0);
state=sixgr.truth.applyProtocolPacketDiscards(state,events);
rx=decode(txA,cfg,bitsA);state=receive(state,gA,rx.TransportBlock,24);
rx=decode(txC,cfg,bitsC);state=receive(state,gC,rx.TransportBlock,25);
P=state.PacketDeliveryLedgerTable;
assert(P.DeliverySuccess(1)&&~P.DeliverySuccess(2)&&~P.DeliverySuccess(3));
assert(isempty(bridge.advance(.026)));
completed=bridge.advance(.027);assert(numel(completed)==1&&completed.PacketId=="c"&&completed.PDCPCount==2);
clock=sixgr.truth.CoupledTruthRuntime.decodedTBDeliveryTimingRuntime(state,27,30);
[T,n]=sixgr.truth.combinePacketTransportLedgers(state);
T=sixgr.truth.applyProtocolPacketCompletions(T,completed,clock);
state=sixgr.truth.publishPacketTransportLedgers(state,T,n);state=sixgr.truth.refreshApplicationPacketDeliveries(state);
P=state.PacketDeliveryLedgerTable;
assert(isequal(P.DeliverySuccess,[true;false;true])&&sum(P.CompletedApplicationBits)==16*numel(payload)&& ...
 all(P.BitConservationErrorBits==0)&&state.DLQueueBits==0&& ...
 P.DiscardedUnscheduledBits(2)==8*numel(payload)&&P.ScheduledBits(2)==0&&P.HARQAttemptCount(2)==0);
assert(~any(string(state.PacketSDULedgerTable.PacketId)=="b")&& ...
 P.DecodedApplicationPayloadSHA256(1)==sixgr.protocol.ProtocolHash.bytes(payload)&& ...
 P.DecodedApplicationPayloadSHA256(3)==sixgr.protocol.ProtocolHash.bytes(payload+2));
assert(isempty(bridge.takeDiscardEvents()));
fprintf('PACKET_PDCP_DISCARD_PASS unsent_drop=1 prepared_or_submitted_retained=2 actual_PDSCH_decodes=2 original_PDCP_COUNT_gap_timer_release=1 shared_RF=0\n');
ok=true;
end
function state=arrival(state,id,payload,time)
r=struct('ScheduledBits',0,'SegmentCount',0,'FirstGrantSlot',NaN,'FirstGrantTime_s',NaN, ...
 'DeliverySuccess',false,'DeliveredBits',0,'HARQAttemptCount',0, ...
 'DiscardedUnscheduledBits',0,'DiscardReceiptID',"", ...
 'ProtocolUEID',"",'ProtocolBearerID',"",'ProtocolConfigurationEpoch',NaN);
r.Direction="DL";r.UEIndex=1;r.RNTI=1001;r.PacketId=string(id);r.ApplicationPacketId=string(id);
r.OfferedBits=8*numel(payload);r.RemainingBits=r.OfferedBits;r.EnqueueTime_s=time;r.Status="queued";
r.OriginalApplicationPayloadSHA256=sixgr.protocol.ProtocolHash.bytes(payload);
p=state.ProtocolBridge.enqueuePacket(1,'DL',string(id),payload,time);
r.ProtocolUEID=p.UEID;r.ProtocolBearerID=p.BearerID;r.ProtocolConfigurationEpoch=p.ConfigurationEpoch;
if isempty(state.PacketDeliveryLedgerTable),state.PacketDeliveryLedgerTable=struct2table(r);
else,state.PacketDeliveryLedgerTable=[state.PacketDeliveryLedgerTable;struct2table(r)];end
state.DLQueueBits=state.DLQueueBits+r.OfferedBits;
end
function expectError(f,id)
try,f();catch ex,assert(string(ex.identifier)==id,ex.message);return;end
error('sixgr:test:MissingDiscardRejection','Expected %s.',id);
end
function rx=decode(tx,cfg,bits)
rx=sixgr.phy.dl.PDSCH_Rx(tx.Waveform,cfg,'Carrier',tx.Carrier,'PDSCH',tx.PDSCH, ...
    'PDSCHIndices',tx.PDSCHIndices,'TransportBlockSize',tx.TransportBlockSize, ...
    'TargetCodeRate',tx.TargetCodeRate,'RV',tx.RV,'CodingPlan',tx.CodingPlans);
assert(rx.Ok&&isequal(int8(rx.TransportBlock(:)),int8(bits(:))),'test:OriginalRecoveryDecode','Actual original coded PDSCH must decode exactly.');
end
function g=grant(e,id,tbs,slot,index)
g=struct('TBSBits',tbs,'RNTI',1001,'UEIndex',1,'Slot',slot,'Frame',1,'ServingCell',1, ...
    'TransportBlockId',id,'TBId',id,'GrantContextId',"attempt-"+id,'ProtocolPayloadSameWaveformTruth',true, ...
    'ProtocolPacketId',e.PacketID,'ProtocolSegmentIndex',index,'ProtocolPayloadOffsetBits',8*e.ApplicationOffsetBytes, ...
    'HARQ',struct('IsRetransmission',false,'HarqID',mod(slot-1,16),'NDI',1,'NDIEpoch',1,'RV',0));
for name=["PayloadBits","PayloadSHA256","SDAPHeaderHex","PDCPHeaderHex","RLCHeaderHex", ...
        "EncodedRLC_SHA256","MACSHA256","MACPDUBytes","MACPaddingBytes","EvidenceSource"]
    g.("Protocol"+name)=e.(name);
end
g.ProtocolFragmentId=e.ProtocolFragmentId;
end
function state=receive(state,g,bits,slot)
[T,n]=sixgr.truth.combinePacketTransportLedgers(state);
mask=sixgr.truth.matchPacketTransportBlock(T,g,'DL',1);
h=struct('Slot',slot,'FeedbackDueSlot',slot+3,'RV',0,'CombinedDecodeOK',true);
clock=sixgr.truth.CoupledTruthRuntime.decodedTBDeliveryTimingRuntime(state,slot,slot+3);
T=sixgr.truth.applyPacketHARQReception(T,mask,h,bits,clock,true,state.ProtocolBridge);
state=sixgr.truth.publishPacketTransportLedgers(state,T,n);
e=struct('Direction',"DL",'UEIndex',1,'RNTI',1001,'HarqID',g.HARQ.HarqID, ...
    'NDIEpoch',1,'TBId',g.TBId,'PHYGrantContextId',g.GrantContextId,'Slot',slot,'CombinedDecodeOK',true);
if isempty(state.HARQTimelineTable),state.HARQTimelineTable=struct2table(e);else,state.HARQTimelineTable=[state.HARQTimelineTable;struct2table(e)];end
state=sixgr.truth.refreshApplicationPacketDeliveries(state);
end
function cfg=localPHYConfig()
cfg=sixgr.config.defaultConfig();
cfg.phy.ssb.enable=false; cfg.run.shortRun=true;
cfg.outputs.saveCSV=false; cfg.outputs.saveMAT=false; cfg.outputs.saveFigures=false;
cfg.run.pdschExecutionProfile="phy_calibration";
cfg.phy.carrier.NSizeGrid=12;
cfg.phy.pdsch.prbSet=0:5; cfg.phy.pdsch.symbolAllocation=[0 10];
cfg.phy.pdsch.modulation='QPSK'; cfg.phy.pdsch.codeRate=.3;
cfg.phy.pdsch.mcsTable="calibration_explicit"; cfg.phy.pdsch.mcsIndex=0;
cfg.phy.pdsch.mcsContext=struct('UECapability1024QAM',false,'RRCEnabled1024QAM',false, ...
    'DCIEnabled1024QAM',false,'DeploymentAllows1024QAM',false,'FrequencyRange',"FR1", ...
    'OperatingBand',"n78",'DeploymentClass',"controlled_test", ...
    'FrequencyRangeAllows1024QAM',false,'BandAllows1024QAM',false);
cfg.phy.pdsch.nLayers=1; cfg.phy.pdsch.numLayers=1;
cfg.phy.pdsch.enablePTRS=false; cfg.phy.csirs.enable=false;
end

function cfg=localProtocolConfig()
cfg=struct('enabled',true,'strict',true,'configuration_epoch',1,'sample_rate_hz',1000,'clock_epoch',1);
cfg.rlc=struct('sn_bits',18,'poll_pdu',16,'poll_byte',65536,'max_retx_threshold',8, ...
    'arq_enabled',true,'t_poll_retransmit_ms',45,'t_reassembly_ms',2,'t_status_prohibit_ms',0);
cfg.pdcp=struct('sn_bits',18,'cipher_algorithm',"NEA0",'integrity_algorithm',"NIA0",'discard_timer_ms',10,'t_reordering_ms',2);
cfg.sdap=struct('pdu_session_id',1,'qfi_to_drb',struct('qfi',9,'drb_id',1));
cfg.mac=struct('lcid',4);
cfg.traffic.sessions=struct('flow_id',"data-1",'pdu_session_id',1,'qfi',9,'direction',"BIDIR");
end
