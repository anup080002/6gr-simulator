function ok=testSharedPUCCHCodebookBinding
% Declared protocol/unit fixtures only: no waveform or received-DCI claim.
e=localEvent(1,1,0,1); e(2)=localEvent(3,3,2,3);
book=sixgr.phy.pucch.HARQACKCodebookBuilder.build('TYPE2_DYNAMIC',e,0);
assert(isequal(book.Bits,int8([1;0;1])) && numel(book.Events)==2);
assert(isequal(book.MissingAssignmentMask,[false;true;false]));
rows=table([1;1],[321;321],[4;2],[2;0],[10;10],logical([0;0]), ...
    'VariableNames',{'UEIndex','RNTI','SourceSlot','HarqID','ScheduledAbsoluteSlot','Ack'});
b=sixgr.truth.bindReceivedPUCCHCodebookRows(book,rows);
assert(isequal(b.EventRowIndices,[2;1]) && b.LastRowIndex==1 && b.BitCount==3);
% Contradictory scoring bits cannot alter the transmitted codebook or binding.
other=rows; other.Ack=~other.Ack;
assert(isequaln(b,sixgr.truth.bindReceivedPUCCHCodebookRows(book,other)));
report=sixgr.phy.pucch.UCIReport(struct('ReportID',"declared-binding-unit", ...
    'RNTI',321,'ServingCell',1,'ComponentCarrier',0,'ULBWP',0, ...
    'ConfigurationEpoch',0,'TargetSlot',10,'PriorityIndex',0, ...
    'HARQACKReport',book,'SchedulingRequestReports',struct([]),'CSIReports',struct([]), ...
    'ReportSource',"declared_unit_fixture_not_PHY_evidence",'TriggeringEventIDs',"unit"));
wire=sixgr.phy.pucch.UCIReportSerializer.serialize(report);
assert(isequal(wire.Sequence1.Bits,int8([1;0;1])) && isempty(wire.Sequence2.Bits));
% The gNB mapping has three obligations; only two have a UE producer row.
r=struct('UEIndex',1,'RNTI',321,'SourceSlot',2,'HARQProcess',0,'TargetSlot',10,'BitIndex',1);
r(2)=r; r(2).SourceSlot=3; r(2).HARQProcess=1; r(2).BitIndex=2;
r(3)=r(1); r(3).SourceSlot=4; r(3).HARQProcess=2; r(3).BitIndex=3;
mapping=struct('Records',r);
assert(isequal(sixgr.truth.bindScheduledPUCCHFeedbackRows(mapping,rows),[3;1]));
assert(isequal(sixgr.truth.bindScheduledPUCCHFeedbackRows(mapping,other),[3;1]));
assert(height(rows)==2 && numel(mapping.Records)==3); % No invented gap row.
localReject(@()sixgr.truth.bindReceivedPUCCHCodebookRows(book,rows([1 1],:)), ...
    'sixgr:truth:ReceivedPUCCHProducerMismatch');
localReject(@()sixgr.truth.bindReceivedPUCCHCodebookRows(book,rows(1,:)), ...
    'sixgr:truth:ReceivedPUCCHProducerMismatch');
localReject(@()sixgr.truth.bindScheduledPUCCHFeedbackRows(mapping,rows([1 1],:)), ...
    'sixgr:truth:ScheduledPUCCHProducerMismatch');
for name=["UEIndex","RNTI","SourceSlot","HarqID","ScheduledAbsoluteSlot"]
    wrong=rows; wrong.(name)(1)=wrong.(name)(1)+0.5;
    localReject(@()sixgr.truth.bindReceivedPUCCHCodebookRows(book,wrong), ...
        'sixgr:truth:ReceivedPUCCHProducerMismatch');
    localReject(@()sixgr.truth.bindScheduledPUCCHFeedbackRows(mapping,wrong), ...
        'sixgr:truth:ScheduledPUCCHProducerMismatch');
end
wrong=rows; wrong.SourceSlot(1)=9;
localReject(@()sixgr.truth.bindReceivedPUCCHCodebookRows(book,wrong), ...
    'sixgr:truth:ReceivedPUCCHProducerMismatch');
localReject(@()sixgr.truth.bindScheduledPUCCHFeedbackRows(mapping,wrong), ...
    'sixgr:truth:ScheduledPUCCHProducerMismatch');
bad=mapping; bad.Records(3).BitIndex=2;
localReject(@()sixgr.truth.bindScheduledPUCCHFeedbackRows(bad,rows), ...
    'sixgr:truth:ScheduledPUCCHProducerMismatch');
% Wrap after DAI=4 retains the fifth bit even when producer table is shuffled.
for k=1:5, wrap(k)=localEvent(mod(k-1,4)+1,k,k-1,k); end %#ok<AGROW>
wrapBook=sixgr.phy.pucch.HARQACKCodebookBuilder.build('TYPE2_DYNAMIC',wrap,0);
wrapRows=table(ones(5,1),321*ones(5,1),(2:6).',(0:4).',10*ones(5,1), ...
    'VariableNames',{'UEIndex','RNTI','SourceSlot','HarqID','ScheduledAbsoluteSlot'});
shuffle=[5 2 4 1 3]; wrapRows=wrapRows(shuffle,:);
bound=sixgr.truth.bindReceivedPUCCHCodebookRows(wrapBook,wrapRows);
assert(bound.LastRowIndex==1 && bound.BitCount==5 && ...
    isequal(bound.EventRowIndices,[4;2;5;3;1]) && all(wrapBook.Bits==1));
fprintf('SHARED_PUCCH_CODEBOOK_BINDING_UNIT_PASS gaps, wrap, reordered identities, scoring independence, negative guards\n');
ok=true;
end

function e=localEvent(dai,index,pid,dataSlot)
e=struct('DAI',dai,'EventIndex',index,'PDSCHID',"declared-"+index, ...
    'Priority',0,'ServingCell',1,'State',"ACK",'ConfigurationEpoch',0, ...
    'UEId',1,'RNTI',321,'DataAbsoluteSlot',dataSlot,'HARQProcess',pid, ...
    'TargetSlot',10,'PUCCHResourceIndicator',0);
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
