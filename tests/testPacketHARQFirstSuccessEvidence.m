function ok=testPacketHARQFirstSuccessEvidence(options)
% Actual coded PDSCH bytes -> production protocol/SDU delivery reducer.
% Noiseless component check, not a BLER or complete shared-runtime campaign.
arguments
    options.OutOfOrder (1,1) logical=false
    options.Queued (1,1) logical=false
    options.LateAfterReordering (1,1) logical=false
end
setup6GRSimToolkit('Verbose',false);
cfg=localPHYConfig();
protocol=localProtocolConfig();
if options.LateAfterReordering,protocol.pdcp.t_reordering_ms=1;end
bridge=sixgr.protocol.WaveformProtocolBridge(protocol,1);
probe=sixgr.phy.dl.PDSCH_Tx(cfg);
tbs=double(probe.TransportBlockSize);
nbytes=bridge.maximumPayloadBytes(tbs);
savedRNG=rng; cleanup=onCleanup(@()rng(savedRNG)); %#ok<NASGU>
rng(73819,'twister'); payload=uint8(randi([0 255],2*nbytes,1));
state=localState(numel(payload)*8);
state.ProtocolBridge=bridge;
state.PacketDeliveryLedgerTable.OriginalApplicationPayloadSHA256=sixgr.protocol.ProtocolHash.bytes(payload);
if options.Queued
    assert(options.OutOfOrder,'Queued test also verifies reordered segment delivery.');
    bridge.enqueuePacket(1,'DL','packet-1',payload,0);
end
bits=cell(2,1); grants=cell(2,1); received=cell(2,1);
for k=1:2
    id="decoded-tb-"+k;
    part=payload((k-1)*nbytes+(1:nbytes));
    if options.Queued
        [bits{k},evidence]=bridge.prepareQueuedSegment(1,'DL',id,tbs,(k-1)*.001,0);
        assert(evidence.PayloadBits==nbytes*8 && evidence.ApplicationOffsetBytes==(k-1)*nbytes);
    else
        [bits{k},evidence]=bridge.encodeFragment(1,'DL',id, ...
            "runtime-DL-UE-001-packet-1-fragment-"+k,part,tbs,(k-1)*.001);
    end
    grant=struct('TBSBits',tbs,'RNTI',1001,'UEIndex',1,'Slot',k,'Frame',1, ...
        'ServingCell',1,'TransportBlockId',id,'TBId',id,'GrantContextId',"attempt-"+k, ...
        'ProtocolPayloadSameWaveformTruth',true,'ProtocolPacketId',"packet-1", ...
        'ProtocolSegmentIndex',k,'ProtocolPayloadOffsetBits',(k-1)*nbytes*8, ...
        'HARQ',struct('IsRetransmission',false,'HarqID',k-1,'NDI',1,'NDIEpoch',1,'RV',0));
    names=["PayloadBits","PayloadSHA256","SDAPHeaderHex","PDCPHeaderHex", ...
        "RLCHeaderHex","EncodedRLC_SHA256","MACSHA256","MACPDUBytes", ...
        "MACPaddingBytes","EvidenceSource"];
    for name=names, grant.("Protocol"+name)=evidence.(name); end
    grant.ProtocolFragmentId=evidence.ProtocolFragmentId;
    state=sixgr.truth.CoupledTruthRuntime.commitGrantExecution(state,1,'DL',grant);
    tx=sixgr.phy.dl.PDSCH_Tx(cfg,'TransportBlockBits',bits{k});
    if options.Queued,bridge.commitPreparedTransportBlock(id,(k-1)*.001);end
    rx=sixgr.phy.dl.PDSCH_Rx(tx.Waveform,cfg,'Carrier',tx.Carrier, ...
        'PDSCH',tx.PDSCH,'PDSCHIndices',tx.PDSCHIndices, ...
        'TransportBlockSize',tx.TransportBlockSize,'TargetCodeRate',tx.TargetCodeRate, ...
        'RV',tx.RV,'CodingPlan',tx.CodingPlans);
    assert(rx.Ok && isequal(int8(rx.TransportBlock(:)),int8(bits{k}(:))), ...
        'Require actual decoder output, not a substituted transmitted vector.');
    grants{k}=grant; received{k}=rx.TransportBlock;
end
T=state.PacketSDULedgerTable;
if options.OutOfOrder
    % Two real coded/decoded TBs, with explicitly arranged delivery order.
    % This checks the production reducer, not shared RF timing qualification.
    second=sixgr.truth.matchPacketTransportBlock(T,grants{2},'DL',1);
    h=struct('Slot',2,'FeedbackDueSlot',5,'RV',0,'CombinedDecodeOK',true);
    clock=sixgr.truth.CoupledTruthRuntime.decodedTBDeliveryTimingRuntime(state,2,5);
    T=sixgr.truth.applyPacketHARQReception(T,second,h,received{2},clock,true,bridge);
    assert(~any(T.DeliverySuccess) && T.ProtocolDecodedBitExact(2));
    proof=T.ProtocolDecodedMACSHA256(2);
    if options.LateAfterReordering
        % Exact original timer releases only the actually received second
        % PDCP PDU. The first actual coded TB arrives below RX_DELIV later.
        completed=bridge.advance(.004);
        clock=sixgr.truth.CoupledTruthRuntime.decodedTBDeliveryTimingRuntime(state,4,7);
        T=sixgr.truth.applyProtocolPacketCompletions(T,completed,clock);
        assert(T.DeliverySuccess(2)&&~T.DeliverySuccess(1)&&T.ProtocolDecodedMACSHA256(2)==proof);
        first=sixgr.truth.matchPacketTransportBlock(T,grants{1},'DL',1);
        h.Slot=5;h.FeedbackDueSlot=8;
        clock=sixgr.truth.CoupledTruthRuntime.decodedTBDeliveryTimingRuntime(state,5,8);
        T=sixgr.truth.applyPacketHARQReception(T,first,h,received{1},clock,true,bridge);
        assert(~T.DeliverySuccess(1)&&T.TBCrcPass(1)&&T.ProtocolDecodedBitExact(1)&& ...
            T.ProtocolDeliveryStatus(1)=="original_PDCP_duplicate_or_below_RX_DELIV_discarded"&& ...
            T.Status(1)=="phy_decode_pass_original_PDCP_duplicate_or_below_RX_DELIV_discarded");
        state.PacketSDULedgerTable=T;
        state=sixgr.truth.refreshApplicationPacketDeliveries(state);
        assert(~state.PacketDeliveryLedgerTable.DeliverySuccess&&state.PacketDeliveryLedgerTable.DeliveredBits==0&& ...
            state.PacketDeliveryLedgerTable.BitConservationErrorBits==0);
        assert(isempty(bridge.advance(.02)));
        ok=true;return;
    end
    first=sixgr.truth.matchPacketTransportBlock(T,grants{1},'DL',1);
    h.Slot=3;
    clock=sixgr.truth.CoupledTruthRuntime.decodedTBDeliveryTimingRuntime(state,3,5);
    T=sixgr.truth.applyPacketHARQReception(T,first,h,received{1},clock,true,bridge);
    assert(all(T.DeliverySuccess) && all(T.HARQAttemptCount==1) && ...
        all(T.DeliveryTime_s==clock.DeliveryTime_s) && T.ProtocolDecodedMACSHA256(2)==proof);
    state.PacketSDULedgerTable=T;
    state=sixgr.truth.refreshApplicationPacketDeliveries(state);
    assert(state.PacketDeliveryLedgerTable.DeliverySuccess && ...
        state.PacketDeliveryLedgerTable.DecodedApplicationPayloadSHA256==sixgr.protocol.ProtocolHash.bytes(payload));
    ok=true; return;
end
first=sixgr.truth.matchPacketTransportBlock(T,grants{1},'DL',1);
h=struct('Slot',1,'FeedbackDueSlot',4,'RV',0,'CombinedDecodeOK',true);
clock=sixgr.truth.CoupledTruthRuntime.decodedTBDeliveryTimingRuntime(state,1,4);
T=sixgr.truth.applyPacketHARQReception(T,first,h,received{1},clock,true,bridge);
assert(T.DeliverySuccess(1) && T.ProtocolDecodedBitExact(1) && ...
    T.ProtocolDecodedBitCount(1)==tbs && T.TimingStatus(1)=="canonical_timing_ok");
partial=state; partial.PacketSDULedgerTable=T;
partial=sixgr.truth.refreshApplicationPacketDeliveries(partial);
assert(partial.PacketDeliveryLedgerTable.BitVerifiedPendingReassemblyBits==nbytes*8 && ...
    partial.PacketDeliveryLedgerTable.CompletedApplicationBits==0 && ...
    partial.PacketDeliveryLedgerTable.UnresolvedReservedBits==nbytes*8 && ...
    partial.PacketDeliveryLedgerTable.BitConservationErrorBits==0, ...
    'One actual decoded fragment is not the complete application packet.');
proofNames=["ProtocolDecodedBitCount","ProtocolDecodedBitExact", ...
    "ProtocolDecodedMACSHA256","ProtocolDecodedRLC_SHA256","ProtocolReceiverEvidenceSource", ...
    "ProtocolDeliveryStatus","DeliverySuccess","FirstSuccessDelivery","FirstSuccessSlot", ...
    "DeliveryCanonicalSlot","DeliveryTime_s","DeliveryTimingAuthority","DeliveryLatency_ms","Status"];
proof=T(1,proofNames);
% ACK-loss-style duplicate delivery callback. These callbacks are declared
% injected events, not extra waveform attempts or calibration samples.
h.Slot=3; h.RV=2;
clock=sixgr.truth.CoupledTruthRuntime.decodedTBDeliveryTimingRuntime(state,3,4);
T=sixgr.truth.applyPacketHARQReception(T,first,h,received{1},clock,true,bridge);
assert(isequaln(T(1,proofNames),proof),'sixgr:test:FirstSuccessEvidenceOverwritten', ...
    'A duplicate callback erased the first actual decoded-payload proof.');
assert(T.HARQAttemptCount(1)==2 && T.LastAttemptSlot(1)==3 && ...
    T.LastAttemptProtocolDeliveryStatus(1)=="duplicate_harq_delivery_rejected");
assert(~T.LastAttemptProtocolDecodedBitExact(1) && isnan(T.LastAttemptProtocolDecodedBitCount(1)), ...
    'Duplicate rejection must not claim a fresh byte comparison.');
h.Slot=4; h.FeedbackDueSlot=6; h.CombinedDecodeOK=false; h.RV=3;
clock=sixgr.truth.CoupledTruthRuntime.decodedTBDeliveryTimingRuntime(state,4,6);
T=sixgr.truth.applyPacketHARQReception(T,first,h,[],clock,true,bridge);
assert(isequaln(T(1,proofNames),proof) && T.HARQAttemptCount(1)==3 && ~T.TBCrcPass(1));
assert(T.LastAttemptProtocolDeliveryStatus(1)=="not_attempted_crc_failed");
second=sixgr.truth.matchPacketTransportBlock(T,grants{2},'DL',1);
h.Slot=5; h.FeedbackDueSlot=8; h.CombinedDecodeOK=true; h.RV=0;
clock=sixgr.truth.CoupledTruthRuntime.decodedTBDeliveryTimingRuntime(state,5,8);
T=sixgr.truth.applyPacketHARQReception(T,second,h,received{2},clock,true,bridge);
assert(all(T.DeliverySuccess & T.ProtocolDecodedBitExact) && ...
    all(T.ProtocolDeliveryStatus=="delivered_after_exact_phy_decode") && ...
    sum(T.PayloadBits(T.FirstSuccessDelivery))==numel(payload)*8);
assert(T.ProtocolDecodedMACSHA256(1)~=T.ProtocolDecodedMACSHA256(2), ...
    'Distinct nonrepeating fragments must not use the same source bytes.');
state.PacketSDULedgerTable=T;
complete=sixgr.truth.refreshApplicationPacketDeliveries(state);
assert(complete.PacketDeliveryLedgerTable.DeliverySuccess && ...
    complete.PacketDeliveryLedgerTable.DecodedApplicationPayloadSHA256==sixgr.protocol.ProtocolHash.bytes(payload) && ...
    complete.PacketDeliveryLedgerTable.DecodedApplicationBytes==numel(payload) && ...
    complete.PacketDeliveryLedgerTable.DeliveredBits==numel(payload)*8 && ...
    complete.PacketDeliveryLedgerTable.DeliveryTime_s==clock.DeliveryTime_s && ...
    all(complete.PacketSDULedgerTable.ApplicationDeliveryFlag));
assert(complete.PacketDeliveryLedgerTable.CompletedApplicationBits==numel(payload)*8 && ...
    complete.PacketDeliveryLedgerTable.BitVerifiedPendingReassemblyBits==0 && ...
    complete.PacketDeliveryLedgerTable.CRCConfirmedMappedBits==0 && ...
    complete.PacketDeliveryLedgerTable.UnresolvedReservedBits==0 && ...
    complete.PacketDeliveryLedgerTable.BitConservationErrorBits==0 && ...
    isequal(complete.PacketSDULedgerTable.ApplicationRangeStartBit,[0;nbytes*8]) && ...
    isequal(complete.PacketSDULedgerTable.ApplicationRangeEndBitExclusive,[nbytes*8;nbytes*16]));
again=sixgr.truth.refreshApplicationPacketDeliveries(complete);
assert(isequaln(again,complete),'Reconciliation must not double-credit delivery.');
% A same-labelled application in another UE must never inherit this proof.
% The strengthened accounting guard rejects orphan SDUs instead of silently
% dropping their attempts from the application's conservation view.
foreign=state; foreign.PacketDeliveryLedgerTable.UEIndex=2;
expectError(@()sixgr.truth.refreshApplicationPacketDeliveries(foreign), ...
    'sixgr:protocol:UnownedPacketSegment');
% Equal byte totals are insufficient when fragment coverage overlaps/gaps.
bad=state; bad.PacketSDULedgerTable.ProtocolPayloadOffsetBits(2)=0;
expectError(@()sixgr.truth.refreshApplicationPacketDeliveries(bad), ...
    'sixgr:protocol:InvalidApplicationFragmentCoverage');
bad=state; bad.PacketSDULedgerTable.ProtocolDecodedMACSHA256(2)="altered";
expectError(@()sixgr.truth.refreshApplicationPacketDeliveries(bad), ...
    'sixgr:protocol:InvalidApplicationDeliveryEvidence');
ok=true;
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
cfg=struct('enabled',true,'strict',true,'configuration_epoch',1);
cfg.rlc=struct('sn_bits',18,'poll_pdu',16,'poll_byte',65536,'max_retx_threshold',8);
cfg.pdcp=struct('sn_bits',18,'cipher_algorithm',"NEA0",'integrity_algorithm',"NIA0");
cfg.sdap=struct('pdu_session_id',1,'qfi_to_drb',struct('qfi',9,'drb_id',1));
cfg.mac=struct('lcid',4);
cfg.traffic.sessions=struct('flow_id',"data-1",'pdu_session_id',1,'qfi',9,'direction',"BIDIR");
end
