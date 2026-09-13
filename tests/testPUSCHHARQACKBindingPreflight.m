function ok=testPUSCHHARQACKBindingPreflight
% Declared reservation fixtures, not physical waveform evidence.
pending=table(["a";"b"],false(2,1),["DL";"DL"],[1;1],[811;811], ...
    [0;1],[1;2],[5;5],logical([1;0]),["ul5";"ul5"], ...
    'VariableNames',{'PUCCHGrantId','Processed','Direction','UEIndex','RNTI', ...
    'HarqID','SourceSlot','DueSlot','Ack','PUSCHGrantContextId'});
trace=table(["b";"a"],true(2,1),false(2,1), ...
    'VariableNames',{'PUCCHGrantId','MultiplexedOnPUSCH','GrantExecutedFlag'});
timeline=table(["DL";"DL"],[811;811],[1;0],[2;1], ...
    'VariableNames',{'Direction','RNTI','HarqID','Slot'});
c=struct('GrantIDs',["a";"b"],'SourceSlots',[1;2],'HARQIDs',[0;1], ...
    'ExpectedBits',int8([1;0]),'TransmissionSlot',5,'DeliverySlot',6, ...
    'GrantContextID',"ul5",'UEIndex',1,'RNTI',811);
before={pending,trace,timeline,c};
b=sixgr.truth.preparePUSCHHARQACKBindings(pending,trace,timeline,c);
assert(isequal([b.PendingIndex],[1 2]) && isequal([b.TraceIndex],[2 1]) && ...
    isequal([b.TimelineIndex],[2 1]) && isequal([b.ExpectedAck],[true false]));
assert(isequaln(before,{pending,trace,timeline,c}));
for field=["SourceSlot","HarqID","DueSlot","UEIndex","RNTI"]
    bad=pending; bad.(field)(2)=bad.(field)(2)+1;
    localReject(@()sixgr.truth.preparePUSCHHARQACKBindings(bad,trace,timeline,c), ...
        'sixgr:truth:InvalidPUSCHHARQACKRuntimeBinding');
end
bad=pending; bad.PUSCHGrantContextId(2)="wrong";
localReject(@()sixgr.truth.preparePUSCHHARQACKBindings(bad,trace,timeline,c), ...
    'sixgr:truth:InvalidPUSCHHARQACKRuntimeBinding');
bad=pending; bad.Processed(2)=true;
localReject(@()sixgr.truth.preparePUSCHHARQACKBindings(bad,trace,timeline,c), ...
    'sixgr:truth:InvalidPUSCHHARQACKRuntimeRows');
localReject(@()sixgr.truth.preparePUSCHHARQACKBindings(pending,trace,timeline(2,:),c), ...
    'sixgr:truth:InvalidPUSCHHARQACKTimelineBinding');
localReject(@()sixgr.truth.preparePUSCHHARQACKBindings(pending,trace([1 1 2],:),timeline,c), ...
    'sixgr:truth:InvalidPUSCHHARQACKRuntimeRows');
bad=pending; bad.Ack=[1;.2];
localReject(@()sixgr.truth.preparePUSCHHARQACKBindings(bad,trace,timeline,c), ...
    'sixgr:truth:InvalidPUSCHHARQACKEvidence');
bad=c; bad.SourceSlots=[1;2.2];
localReject(@()sixgr.truth.preparePUSCHHARQACKBindings(pending,trace,timeline,bad), ...
    'sixgr:truth:InvalidPUSCHHARQACKRuntimeBinding');
bad=c; bad.ExpectedBits=[1;.2];
localReject(@()sixgr.truth.preparePUSCHHARQACKBindings(pending,trace,timeline,bad), ...
    'sixgr:truth:InvalidPUSCHHARQACKEvidence');
bad=c; bad.DeliverySlot=4;
localReject(@()sixgr.truth.preparePUSCHHARQACKBindings(pending,trace,timeline,bad), ...
    'sixgr:truth:InvalidPUSCHHARQACKRuntimeBinding');
b=sixgr.truth.preparePUSCHHARQACKBindings(pending,trace,table(),c);
assert(all(isnan([b.TimelineIndex]))); % No fake timeline in a component fixture.
assert(isequaln(before,{pending,trace,timeline,c}));
fprintf('PUSCH_HARQ_ACK_PREFLIGHT_UNIT_PASS reordered rows, later invalid binding, timeline, owner, binary and clock guards\n');
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
