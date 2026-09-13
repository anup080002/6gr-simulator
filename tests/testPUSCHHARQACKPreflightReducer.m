function ok=testPUSCHHARQACKPreflightReducer
% Exact production reducer + real HARQ handles and UCI coding fixture.
% Declared MAC reservations / ideal LLRs are NOT shared-waveform evidence.
rnti=811; harq=sixgr.l2.mac.HARQEntityDL(struct());
for k=1:2
    txp=harq.allocate(rnti,k,8,'NewData',true);
    grant=struct('Direction','DL','RNTI',rnti,'TBSBits',64,'TBSBytes',8, ...
        'HARQ',txp.HARQ,'HARQTBContext',struct('TBId',sprintf('unit-%d',k),'TBSBits',64), ...
        'Modulation','QPSK','NumLayers',1,'TargetCodeRate',.3);
    grant.CodingLayout=sixgr.phy.phycode.resolveCodingLayout('Direction','DL', ...
        'TransportBlockSize',64,'TargetCodeRate',.3,'RV',double(txp.HARQ.RV), ...
        'Modulation','QPSK','NumLayers',1,'RateMatchedBitCount',2*ceil((64+24)/.3/2));
    harq.onTx(rnti,double(txp.HARQ.HarqID),zeros(64,1,'uint8'),grant,k);
end
pending=table(["a";"b"],false(2,1),["DL";"DL"],[1;1],[rnti;rnti], ...
    [0;1],[1;2],[5;5],logical([1;0]),["ul5";"ul5"],["";""], ...
    'VariableNames',{'PUCCHGrantId','Processed','Direction','UEIndex','RNTI', ...
    'HarqID','SourceSlot','DueSlot','Ack','PUSCHGrantContextId','FeedbackOutcome'});
trace=table(["a";"b"],true(2,1),false(2,1), ...
    'VariableNames',{'PUCCHGrantId','MultiplexedOnPUSCH','GrantExecutedFlag'});
for field=["ObservedAck","DecodedAck","FalseAck","FalseNack","MissedFeedback", ...
        "PUSCHUCIDecodeOk","PUCCHDecodeOk","CurrentDecodeOK","CombinedDecodeOK", ...
        "UCIContentMatch","RuntimeStateUpdated","ControlStateChanged","StateChangeApplied"]
    trace.(field)=false(2,1);
end
for field=["FeedbackOutcome","FeedbackOutcomeReason","RuntimeStateConsumer","Status","PUCCHGrantState","Notes"]
    trace.(field)=strings(2,1);
end
trace.BitsCompared=nan(2,1); trace.BitErrors=nan(2,1);
state=struct('CurrentSlot',5,'DLHarq',harq,'DLCombinedLLR',{{ones(8,1),ones(8,1)}}, ...
    'PendingFeedbackTable',pending,'PUCCHGrantTraceTable',trace,'HARQTimelineTable',table());
pusch=struct('Direction','UL','UEIndex',1,'RNTI',rnti,'GrantContextId',"ul5", ...
    'UCIOnPUSCHFeedbackGrantIds',"a|b",'UCIOnPUSCHFeedbackSourceSlots',[1;2], ...
    'UCIOnPUSCHFeedbackHARQIds',[0;1],'ExpectedUCIBits',int8([1;0]));
bits=int8([1;1]); coded=nrUCIEncode(bits,480,'QPSK');
[decoded,e]=sixgr.phy.ul.pusch.decodeUCIWithEvidence(50*(1-2*double(coded)),2,'QPSK');
assert(isequal(decoded,bits) && e.DecodeUsable);
out=struct('GrantSnapshot',pusch,'ExpectedHARQACKBits',int8([1;0]), ...
    'DecodedHARQACKBits',decoded,'HARQACKDecodeStatus',"decoded_mismatch", ...
    'HARQACKContentMatch',false,'UCIReceiverEvidence',struct('HARQACK',e));
stats=harq.Stats; processes=harq.UEProcs; buffers=state.DLCombinedLLR;
bad=state; bad.PendingFeedbackTable.DueSlot(2)=6;
localReject(@()sixgr.truth.CoupledTruthRuntime.applyDecodedPUSCHHARQACKRuntime(bad,out), ...
    'sixgr:truth:InvalidPUSCHHARQACKRuntimeBinding');
assert(isequaln(harq.Stats,stats) && isequaln(harq.UEProcs,processes));
bad=state; bad.HARQTimelineTable=table("DL",rnti,0,1, ...
    'VariableNames',{'Direction','RNTI','HarqID','Slot'});
localReject(@()sixgr.truth.CoupledTruthRuntime.applyDecodedPUSCHHARQACKRuntime(bad,out), ...
    'sixgr:truth:InvalidPUSCHHARQACKTimelineBinding');
assert(isequaln(harq.Stats,stats) && isequaln(harq.UEProcs,processes));
bad=state; invalid=out;
bad.PendingFeedbackTable.HarqID(2)=harq.NumProcesses;
invalid.GrantSnapshot.UCIOnPUSCHFeedbackHARQIds(2)=harq.NumProcesses;
localReject(@()sixgr.truth.CoupledTruthRuntime.applyDecodedPUSCHHARQACKRuntime(bad,invalid), ...
    'sixgr:HARQEntity:BadHarqId');
assert(isequaln(harq.Stats,stats) && isequaln(harq.UEProcs,processes));
for field=["ExpectedHARQACKBits","DecodedHARQACKBits"]
    invalid=out; invalid.(field)=[1;.2];
    localReject(@()sixgr.truth.CoupledTruthRuntime.applyDecodedPUSCHHARQACKRuntime(state,invalid), ...
        'sixgr:truth:InvalidPUSCHHARQACKEvidence');
end
assert(isequaln(harq.Stats,stats) && isequaln(harq.UEProcs,processes) && ...
    isequaln(state.DLCombinedLLR,buffers));
state=sixgr.truth.CoupledTruthRuntime.applyDecodedPUSCHHARQACKRuntime(state,out);
assert(harq.Stats.Ack==2 && harq.Stats.Nack==0 && all(state.PendingFeedbackTable.Processed));
t=state.PUCCHGrantTraceTable;
assert(all(t.PUSCHUCIDecodeOk) && all(t.CombinedDecodeOK) && all(t.CurrentDecodeOK));
assert(isequal(t.UCIContentMatch,[true;false]) && isequal(t.FalseAck,[false;true]) && ...
    isequal(string(t.Status),["PASS";"FAIL"]));
assert(~any(t.GrantExecutedFlag) && ~any(t.PUCCHDecodeOk) && all(cellfun(@isempty,state.DLCombinedLLR)));
fprintf('PUSCH_HARQ_ACK_PREFLIGHT_REDUCER_PASS late-failure no-mutation guards and usable false-ACK semantics\n');
ok=true;
end

function localReject(fn,id)
try
    fn();
catch cause
    assert(strcmp(cause.identifier,id),'Expected %s; got %s: %s',id,cause.identifier,cause.message);
    return;
end
error('test:MissingRejection','Expected %s',id);
end
