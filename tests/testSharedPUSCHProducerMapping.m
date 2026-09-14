function ok=testSharedPUSCHProducerMapping()
% Declared association contracts, not newly transmitted/received PHY rows.
pending=table(["a";"b"],false(2,1),["DL";"DL"],[1;1],[811;811], ...
    [4;5],[5;6],[9;9],logical([1;0]),["ul9";"ul9"], ...
    'VariableNames',{'PUCCHGrantId','Processed','Direction','UEIndex','RNTI', ...
    'HarqID','SourceSlot','DueSlot','Ack','PUSCHGrantContextId'});
trace=table(["b";"a"],true(2,1),false(2,1), ...
    'VariableNames',{'PUCCHGrantId','MultiplexedOnPUSCH','GrantExecutedFlag'});
timeline=table(["DL";"DL"],[811;811],[5;4],[6;5], ...
    'VariableNames',{'Direction','RNTI','HarqID','Slot'});
records=struct('UEIndex',1,'RNTI',811,'SourceSlot',1,'HARQProcess',0,'TargetSlot',9,'BitIndex',1);
records=repmat(records,6,1);
for k=1:6
    records(k).SourceSlot=k; records(k).HARQProcess=k-1; records(k).BitIndex=k;
end
mapping=struct('BaseMapping',struct('Records',records));
g=struct('UCIOnPUSCHFeedbackGrantIds',"a|b", ...
    'UCIOnPUSCHFeedbackSourceSlots',[5 6],'UCIOnPUSCHFeedbackHARQIds',[4 5], ...
    'UCIOnPUSCHFeedbackBitIndices',[1 2],'ExpectedUCIBits',int8([1;0]), ...
    'PHYGrant',struct('GrantContextId',"ul9"),'UEIndex',1,'RNTI',811);
before={g,pending,trace,timeline,mapping};
bound=sixgr.truth.bindSharedPUSCHProducerRows(g,pending,trace,timeline,mapping,9,10);
assert(isequal(bound.TransmittedBitIndices,[1;2]) && ...
    isequal(bound.ScheduledBitIndices,[5;6]) && ...
    isequal([bound.Rows.TraceIndex],[2 1]) && isequal([bound.Rows.TimelineIndex],[2 1]));
% Explicit TX gaps, producer reordering, and gNB association are independent.
withGaps=g; withGaps.ExpectedUCIBits=int8([0;1;0;0;0;0]);
withGaps.UCIOnPUSCHFeedbackBitIndices=[2 6];
same=sixgr.truth.bindSharedPUSCHProducerRows(withGaps,pending,trace,timeline,mapping,9,10);
assert(isequal(same.ScheduledBitIndices,[5;6]) && isequal(same.TransmittedBitIndices,[2;6]));
reordered=g; reordered.UCIOnPUSCHFeedbackGrantIds="b|a";
reordered.UCIOnPUSCHFeedbackSourceSlots=[6 5]; reordered.UCIOnPUSCHFeedbackHARQIds=[5 4];
reordered.UCIOnPUSCHFeedbackBitIndices=[2 1];
swapped=sixgr.truth.bindSharedPUSCHProducerRows(reordered,pending,trace,timeline,mapping,9,10);
assert(isequal(swapped.ScheduledBitIndices,[6;5]) && isequal(swapped.TransmittedBitIndices,[2;1]));
for positions={[1 1],[1 3],[1 NaN],[1 .5],[],[1;2;3]}
    bad=g; bad.UCIOnPUSCHFeedbackBitIndices=positions{1};
    localReject(@()sixgr.truth.bindSharedPUSCHProducerRows(bad,pending,trace,timeline,mapping,9,10), ...
        'sixgr:truth:InvalidSharedPUSCHProducerBinding');
end
bad=pending; bad.HarqID(2)=6;
localReject(@()sixgr.truth.bindSharedPUSCHProducerRows(g,bad,trace,timeline,mapping,9,10), ...
    'sixgr:truth:InvalidPUSCHHARQACKRuntimeBinding');
bad=mapping; bad.BaseMapping.Records(6).SourceSlot=99;
localReject(@()sixgr.truth.bindSharedPUSCHProducerRows(g,pending,trace,timeline,bad,9,10), ...
    'sixgr:truth:ScheduledPUCCHProducerMismatch');
localReject(@()sixgr.truth.bindSharedPUSCHProducerRows(g,pending,trace,timeline,struct([]),9,10), ...
    'sixgr:truth:MissingSharedPUSCHScheduledMapping');
% Gap-only and omitted TX codebooks create no producer or fake schedule row.
empty=g; empty.UCIOnPUSCHFeedbackGrantIds="";
empty.UCIOnPUSCHFeedbackSourceSlots=[]; empty.UCIOnPUSCHFeedbackHARQIds=[];
empty.UCIOnPUSCHFeedbackBitIndices=[];
for n=0:3
    empty.ExpectedUCIBits=zeros(n,1,'int8');
    noRows=sixgr.truth.bindSharedPUSCHProducerRows(empty,table(),table(),table(),mapping,9,10);
    assert(isempty(noRows.Rows) && isempty(noRows.ScheduledBitIndices) && ...
        isempty(noRows.TransmittedBitIndices));
end
assert(isequaln(before,{g,pending,trace,timeline,mapping}));
fprintf('SHARED_PUSCH_PRODUCER_MAPPING_PASS independent_TX_and_gNB_positions no_RF_claim\n');
ok=true;
end

function localReject(fn,id)
try, fn(); catch err
    assert(strcmp(err.identifier,id),'Expected %s; got %s: %s',id,err.identifier,err.message);
    return;
end
error('test:ExpectedRejection','Expected %s',id);
end
