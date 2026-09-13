function ok=testType2HARQACKLayout()
% Literal TS 38.213 9.1.3.1 scalar-TB cases; no waveform PASS is implied.
setup6GRSimToolkit('Verbose',false);
e=events([1 2 3 4 1 2 3 4],["ACK" "NACK" "DTX" "ACK" "NACK" "DTX" "ACK" "NACK"]);
original=e;
s=build(e([1 5 2 6 3 7 4 8]));
assert(join(s.BitTokens,"")=="10D10D10");
assert(isequal(s.EventOrder,"P"+string((0:7).')));
assert(~any(s.MissingAssignmentMask) && isequal(s.SourceEventIndex,(1:8).'));
assert(isequal(e,original),'Input events must remain immutable.');
% Leading and interior missing DCIs produce protocol NACK, not fake events.
e=events([3 1],["ACK" "DTX"]); s=build(e);
assert(isequal(s.Bits,int8([0;0;1;0;0])));
assert(isequal(s.SourceEventIndex,[0;0;1;0;2]));
assert(isequal(s.MissingAssignmentMask,[true;true;false;true;false]));
assert(isequal(s.DTXMask,[false;false;false;false;true]));
assert(numel(s.Events)==2 && all(s.EventOrder(s.MissingAssignmentMask)==""));
% A repeated counter indicates at least one observed wrap, not sorting ties.
s=build(events([1 1],["ACK" "NACK"]));
assert(isequal(s.Bits,int8([1;0;0;0;0])) && numel(s.Events)==2);
% Total DAI in final monitoring occasion exposes trailing missing positions.
e=events([1 2],["ACK" "ACK"]);
e(1).MonitoringOccasionIndex=7; e(2).MonitoringOccasionIndex=7;
e(2).ServingCell=1; e(1).TotalDAI=3; e(2).TotalDAI=[];
s=build(e([2 1])); assert(isequal(s.Bits,int8([1;1;0])));
% Total-DAI wrap past last received counter.
e=events([3 4],["ACK" "NACK"]);
e(1).TotalDAI=[]; e(2).TotalDAI=1;
s=build(e); assert(isequal(s.Bits,int8([0;0;1;0;0])));
% Monitoring occasion before serving cell; never cell-first across time.
e=events([2 1 3],["NACK" "ACK" "ACK"]);
e(1).EventIndex=21; e(1).MonitoringOccasionIndex=10; e(1).ServingCell=1;
e(2).EventIndex=20; e(2).MonitoringOccasionIndex=10; e(2).ServingCell=0;
e(3).EventIndex=22; e(3).MonitoringOccasionIndex=11; e(3).ServingCell=0;
s=build(e); assert(isequal(s.Bits,int8([1;0;1])));
assert(isequal(s.EventOrder,["P1";"P0";"P2"]));
% Empty received set has no scheduler-authority rescue bits.
s=build(struct([])); assert(isempty(s.Bits) && isempty(s.Events));
% Changed received evidence must change immutable codebook identity.
e=events(1,"ACK"); a=build(e); e(1).EventIndex=10; b=build(e);
assert(a.Digest~=b.Digest && isequal(a.Bits,b.Bits));
% All 4^4 four-event DAI patterns, including observable gaps/wraps, checked
% against an independent ordinal-search oracle and literal source states.
for packed=0:255
    dai=mod(floor(packed./(4.^(0:3))),4)+1;
    e=events(dai,["ACK" "DTX" "NACK" "ACK"]);
    a=build(e([3 1 4 2]));
    b=sixgr.phy.pucch.oracle.HARQACKCodebookSpec.resolve('TYPE2_DYNAMIC',jsonencode(e));
    assert(isequal(a.Bits,b.Bits) && isequal(a.DTXMask,b.DTXMask));
    assert(nnz(~a.MissingAssignmentMask)==4 && numel(a.Events)==4);
end
% Input guards: NaN/fractional DAI, mixed priority, epoch/occasion mismatch.
for bad={NaN,Inf,0,5,1.5,1+1i,'1'}
    e=events(1,"ACK"); e.DAI=bad{1};
    rejects(@()build(e),'sixgr:phy:pucch:InvalidHARQEvent');
end
e=events([1 2],["ACK" "ACK"]); e(2).Priority=1;
rejects(@()build(e),'sixgr:phy:pucch:MixedHARQPriority');
e=events(1,"ACK"); e.ConfigurationEpoch=3;
rejects(@()build(e),'sixgr:phy:pucch:StaleConfiguration');
e=events([1 2],["ACK" "ACK"]); e(1).TargetSlot=4; e(2).TargetSlot=9;
rejects(@()build(e),'sixgr:phy:pucch:MixedHARQContext');
e=events([1 2],["ACK" "ACK"]);
e(1).MonitoringOccasionIndex=0; e(2).MonitoringOccasionIndex=0;
e(1).TotalDAI=2; e(2).TotalDAI=3;
rejects(@()build(e),'sixgr:phy:pucch:InconsistentTotalDAI');
e=events(1,"ACK"); e.NumCodewords=2;
rejects(@()build(e),'sixgr:phy:pucch:UnsupportedHARQCodebook');
e=events(1,"ACK"); e.CounterDAIBits=1;
rejects(@()build(e),'sixgr:phy:pucch:UnsupportedHARQCodebook');
% Serializer consumes codebook positions, not merely the received-event list.
codebook=build(events(3,"ACK"));
report=sixgr.phy.pucch.UCIReport(struct('ReportID','DAI-gap-test', ...
    'RNTI',1,'ServingCell',0,'ComponentCarrier',0,'ULBWP',0, ...
    'ConfigurationEpoch',2,'TargetSlot',9,'PriorityIndex',0, ...
    'HARQACKReport',codebook,'SchedulingRequestReports',struct([]), ...
    'CSIReports',struct([]),'ReportSource','independent_procedure_test', ...
    'TriggeringEventIDs',"received-DCI-3"));
serialized=sixgr.phy.pucch.UCIReportSerializer.serialize(report);
assert(isequal(serialized.Sequence1.Bits,int8([0;0;1])));
assert(height(serialized.Layout)==3 && all(serialized.Layout.BitOwner=="HARQ_ACK"));
fprintf('TYPE2_HARQ_ACK_LAYOUT_PASS: literal gaps/wraps, 256 DAI sequences, guards and serialization\n');
% Retain every existing scalar-event vector; corrected Type-2 expectations
% follow chronological ordinals instead of sorting wrapped DAI values.
v=readtable('tests/vectors/pucch/pucch_harq_codebook_test_vectors.csv','TextType','string');
expected=readtable('tests/vectors/pucch/expected_pucch_harq_codebook.csv', ...
    'TextType','string','VariableNamingRule','preserve');
for k=1:height(v)
    a=sixgr.phy.pucch.HARQACKCodebookBuilder.buildVector(v(k,:));
    row=expected(expected.CaseID==v.CaseID(k),:);
    assert(height(row)==1 && join(a.BitTokens,"")==string(row.ExpectedBitTokens) && ...
        numel(a.BitTokens)==row.ExpectedBitCount && join(a.EventOrder,"|")==row.ExpectedEventOrder && ...
        nnz(a.DTXMask)==row.DTXCount);
end
fprintf('HARQ_LEGACY_VECTOR_REGRESSION_PASS: %d vectors\n',height(v));
ok=true;
end

function e=events(dai,states)
e=repmat(struct('DAI',1,'EventIndex',0,'PDSCHID',"",'Priority',0, ...
    'ServingCell',0,'State',"ACK",'ConfigurationEpoch',2),numel(dai),1);
for k=1:numel(dai)
    e(k).DAI=dai(k); e(k).EventIndex=k-1; e(k).PDSCHID="P"+(k-1); e(k).State=states(k);
end
end

function s=build(e)
s=sixgr.phy.pucch.HARQACKCodebookBuilder.build('TYPE2_DYNAMIC',e,2);
end

function rejects(action,id)
caught=false;
try, action(); catch cause, caught=strcmp(cause.identifier,id); if ~caught, rethrow(cause); end; end
assert(caught,'test:MissingHARQGuard','Expected rejection %s.',id);
end
