function ok=testPacketHARQRLCRecovery()
% Actual native coded PDSCH + production bridge/ledger recovery.
% First original TX's receive event is deliberately withheld (NOT false CRC).
% Reverse STATUS is an explicitly declared original MAC/codec transport
% boundary; no PUSCH waveform or shared RF/access qualification is claimed.
setup6GRSimToolkit('Verbose',false);
cfg=localPHYConfig();bridge=sixgr.protocol.WaveformProtocolBridge(localProtocolConfig(),1);
probe=sixgr.phy.dl.PDSCH_Tx(cfg);tbs=double(probe.TransportBlockSize);
n=bridge.maximumPayloadBytes(tbs);payload=uint8(mod(0:2*n-1,251));
state=localState(8*numel(payload));state.ProtocolBridge=bridge;
state.HARQTimelineTable=table();
state.PacketDeliveryLedgerTable.OriginalApplicationPayloadSHA256=sixgr.protocol.ProtocolHash.bytes(payload);
bridge.enqueuePacket(1,'DL','packet-1',payload,0);
originals=0;decodedCount=0;lostProof=table();
while bridge.pendingTransmitBytes(1,'DL').RLCPayloadBytes>0
    originals=originals+1;assert(originals<=4);
    slot=originals;id="initial-"+slot;
    [bits,e]=bridge.prepareQueuedSegment(1,'DL',id,tbs,(slot-1)*.001,0);
    g=grant(e,id,tbs,slot,originals);
    state=sixgr.truth.CoupledTruthRuntime.commitGrantExecution(state,1,'DL',g);
    tx=sixgr.phy.dl.PDSCH_Tx(cfg,'TransportBlockBits',bits);
    bridge.commitPreparedTransportBlock(id,(slot-1)*.001);
    if originals==1
        % No receiver invocation, CRC outcome, or fabricated failed decode.
        lostProof=state.PacketSDULedgerTable(1,{'DeliverySuccess','TBCrcPass','FirstSuccessDelivery','ProtocolDecodedBitExact','ProtocolDecodedMACSHA256','ProtocolDecodedRLC_SHA256'});
    else
        rx=decode(tx,cfg,bits);state=receive(state,g,rx.TransportBlock,slot);decodedCount=decodedCount+1;
    end
end
assert(originals>=2&&state.DLQueueBits==0&&state.PacketDeliveryLedgerTable.RemainingBits==0&& ...
    state.PacketDeliveryLedgerTable.ScheduledBits==8*numel(payload));
initialDebit=state.PacketDeliveryLedgerTable.ScheduledBits;wireBefore=state.DLTransmittedBits;
assert(~state.PacketDeliveryLedgerTable.DeliverySuccess);
assert(isempty(bridge.advance(.006)));
assert(bridge.pendingReverseStatusBytes(1,'UL')>0&&bridge.pendingTransmitBytes(1,'DL').AMRetransmissionBytes==0);
[statusBits,statusEvidence]=bridge.prepareReverseStatusTransportBlock(1,'UL','reverse-status-codec-boundary',256,.006);
assert(statusEvidence.ControlOnly&&statusEvidence.PayloadBits==0);
bridge.validatePreparedTransportBlock('reverse-status-codec-boundary',.006,statusBits);
bridge.commitPreparedTransportBlock('reverse-status-codec-boundary',.006);
% Explicit component-codec received boundary, not an asserted physical CRC.
status=bridge.receiveReverseStatusDecoded('reverse-status-codec-boundary',statusBits,true,.007);
assert(status.Status=="original_crc_confirmed_reverse_STATUS");
assert(bridge.pendingTransmitBytes(1,'DL').AMRetransmissionBytes>0);
small=cfg;small.phy.pdsch.prbSet=0:2;
smallProbe=sixgr.phy.dl.PDSCH_Tx(small);smallTBS=double(smallProbe.TransportBlockSize);
assert(smallTBS<tbs);
% A prepared but withheld recovery TB cannot consume bytes or debit arrivals.
[~,~]=bridge.prepareQueuedSegment(1,'DL','withheld-retx',smallTBS,.007,0);
before=bridge.pendingTransmitBytes(1,'DL');bridge.cancelPreparedTransportBlock('withheld-retx');
assert(isequaln(before,bridge.pendingTransmitBytes(1,'DL')));
retries=0;
while bridge.pendingTransmitBytes(1,'DL').AMRetransmissionBytes>0
    retries=retries+1;assert(retries<=6);slot=7+retries;id="retx-"+retries;
    [bits,e]=bridge.prepareQueuedSegment(1,'DL',id,smallTBS,(slot-1)*.001,0);
    private=bridge.originalTransportApplicationBinding(id);assert(private.IsRLCRetransmission&&private.RLCFullCount==0);
    g=grant(e,id,smallTBS,slot,originals+retries);
    state=sixgr.truth.CoupledTruthRuntime.commitGrantExecution(state,1,'DL',g);
    assert(state.DLQueueBits==0&&state.PacketDeliveryLedgerTable.ScheduledBits==initialDebit&& ...
        height(state.PacketSDULedgerTable)==originals);
    tx=sixgr.phy.dl.PDSCH_Tx(small,'TransportBlockBits',bits);
    bridge.commitPreparedTransportBlock(id,(slot-1)*.001);
    rx=decode(tx,small,bits);state=receive(state,g,rx.TransportBlock,slot);decodedCount=decodedCount+1;
end
assert(retries>=2&&state.DLTransmittedBits==wireBefore+retries*smallTBS);
state=sixgr.truth.refreshApplicationPacketDeliveries(state);
P=state.PacketDeliveryLedgerTable;S=state.PacketSDULedgerTable;
assert(P.DeliverySuccess&&P.DeliveredBits==8*numel(payload)&&P.CompletedApplicationBits==P.OfferedBits&& ...
    P.DecodedApplicationPayloadSHA256==sixgr.protocol.ProtocolHash.bytes(payload)&&P.BitConservationErrorBits==0);
assert(isequaln(S(1,lostProof.Properties.VariableNames),lostProof)&&S.RecoveredViaRLC(1)&& ...
    height(state.RLCRecoveryTransportLedgerTable)==retries&&all(state.RLCRecoveryTransportLedgerTable.DeliverySuccess));
assert(P.HARQAttemptCount==decodedCount&&S.HARQAttemptCount(1)==0);
r=jsondecode(P.RLCApplicationRecoveryEvidenceJSON);
assert(~any(string(r.ContributorTransportBlockIDs)=="initial-1")&&r.UniqueCoveredApplicationBytes==numel(payload));
again=sixgr.truth.refreshApplicationPacketDeliveries(state);assert(isequaln(again,state));
% Do not deliver the receiver's final STATUS. The original transmitter's
% t-PollRetransmit then legitimately selects retained bytes after the
% application has already completed. Decode a new native PDSCH carrying
% those bytes: RLC must discard it, not report indefinite reordering or
% credit another application completion.
assert(isempty(bridge.advance(.060))&&bridge.pendingTransmitBytes(1,'DL').AMRetransmissionBytes>0);
slot=61;id="late-retx-after-application-release";
[bits,e]=bridge.prepareQueuedSegment(1,'DL',id,smallTBS,.060,0);
private=bridge.originalTransportApplicationBinding(id);assert(private.IsRLCRetransmission);
g=grant(e,id,smallTBS,slot,originals+retries+1);
state=sixgr.truth.CoupledTruthRuntime.commitGrantExecution(state,1,'DL',g);
tx=sixgr.phy.dl.PDSCH_Tx(small,'TransportBlockBits',bits);
bridge.commitPreparedTransportBlock(id,.060);
rx=decode(tx,small,bits);state=receive(state,g,rx.TransportBlock,slot);
late=state.RLCRecoveryTransportLedgerTable(end,:);
assert(late.TransportBlockId==id&&late.TBCrcPass&&late.ProtocolDecodedBitExact&& ...
    ~late.DeliverySuccess&&~late.ApplicationDeliveryFlag&& ...
    late.ProtocolDeliveryStatus=="original_RLC_outside_window_discarded"&& ...
    late.Status=="phy_decode_pass_original_RLC_outside_window_discarded");
immutable={'DeliverySuccess','DeliveredBits','CompletedApplicationBits','ScheduledBits', ...
    'DeliveryTime_s','DecodedApplicationPayloadSHA256','RLCApplicationRecoveryEvidenceJSON', ...
    'RLCApplicationRecoveryEvidenceSHA256'};
assert(isequaln(state.PacketDeliveryLedgerTable(:,immutable),P(:,immutable))&& ...
    state.PacketDeliveryLedgerTable.HARQAttemptCount==decodedCount+1&& ...
    state.PacketDeliveryLedgerTable.BitConservationErrorBits==0&&state.DLQueueBits==0&& ...
    state.DLTransmittedBits==wireBefore+(retries+1)*smallTBS&& ...
    isequaln(state.PacketSDULedgerTable(1,lostProof.Properties.VariableNames),lostProof));
% Repeated completion callbacks retain the real discard disposition.
[delivered,lateEvidence]=bridge.deliverDecoded(id,rx.TransportBlock,.062);
assert(~delivered&&lateEvidence.Status=="original_RLC_outside_window_discarded"&& ...
    isempty(lateEvidence.CompletedTransportBlocks));
fprintf('PACKET_HARQ_RLC_RECOVERY_PASS initial_TX=%d withheld_original_RX=1 decoded_data_TBs=%d resegmented_TX=%d late_original_retx_discard=1 reverse_STATUS_component_codec_boundary=1\n',originals,decodedCount+1,retries);
ok=true;
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
    'ProtocolPacketId',"packet-1",'ProtocolSegmentIndex',index,'ProtocolPayloadOffsetBits',8*e.ApplicationOffsetBytes, ...
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
function state=localState(offered)
p=struct('Direction',"DL",'UEIndex',1,'RNTI',1001,'PacketId',"packet-1", ...
    'ApplicationPacketId',"packet-1",'OfferedBits',offered,'RemainingBits',offered, ...
    'ScheduledBits',0,'SegmentCount',0,'FirstGrantSlot',NaN,'FirstGrantTime_s',NaN, ...
    'DeliverySuccess',false,'Status',"queued",'EnqueueTime_s',0,'DeliveredBits',0);
state=struct('NumUsers',1,'ProtocolWaveformEnabled',true, ...
    'PacketDeliveryLedgerTable',struct2table(p),'PacketSDULedgerTable',table(), ...
    'DLQueueBits',offered,'DLTransmittedBits',0,'MultiUser',struct('RNTIStart',1001), ...
    'CurrentSlot',1,'CurrentFrame',1,'SlotDuration_s',.001, ...
    'DLGrantTraceTable',table(),'ULGrantTraceTable',table());
end

function expectError(f,id)
try, f(); catch ex, assert(string(ex.identifier)==id,ex.message); return; end
error('sixgr:test:MissingReassemblyRejection','Expected %s.',id);
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
cfg.pdcp=struct('sn_bits',18,'cipher_algorithm',"NEA0",'integrity_algorithm',"NIA0");
cfg.sdap=struct('pdu_session_id',1,'qfi_to_drb',struct('qfi',9,'drb_id',1));
cfg.mac=struct('lcid',4);
cfg.traffic.sessions=struct('flow_id',"data-1",'pdu_session_id',1,'qfi',9,'direction',"BIDIR");
end
