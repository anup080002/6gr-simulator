function ok=testFTP3FileLedger()
% First-success file semantics must survive HARQ reordering and duplicate ACKs.
a=table(["file1";"file2";"file3"],[1;1;2],[0.1;0.2;1.2],[1;1;2], ...
    repmat("UL",3,1),[100;100;100], ...
    'VariableNames',{'ArrivalID','ArrivalTTI','ArrivalTime_s','UEID','Direction','OfferedBits'});
L=sixgr.system.FTP3FileLedger(a,1,2);
L.advance(1);
assert(L.queuedBits(1,"UL")==200 && L.queuedBits(2,"UL")==0);
A=L.bind("immutable-A",1,"UL",60,1,false);
B=L.bind("immutable-B",1,"UL",100,1,false);
assert(A.PayloadBits==60 && B.PayloadBits==100);
assert(L.unallocatedBits(1,"UL")==40 && L.queuedBits(1,"UL")==200, ...
    "New-data backlog excludes in-flight ownership while total queue retains it.");
assert(isequal(B.Mapping,[1 60 40;2 0 60]), ...
    "Each first TX must freeze its exact FIFO file ranges.");
assert(L.complete("immutable-B",2)==100);
s=L.snapshot(2);
assert(~any(s.Files.Completed) && s.Files.DeliveredBits(1)==40 && s.Files.DeliveredBits(2)==60, ...
    "Out-of-order TB success must not falsely finish the oldest file.");
retx=L.bind("immutable-A",1,"UL",60,3,true);
assert(isequal(retx.Mapping,A.Mapping));
assert(L.complete("immutable-A",3)==60);
assert(L.complete("immutable-A",3)==0,"Duplicate ACK must add no payload.");
C=L.bind("immutable-C",1,"UL",80,3,false);
assert(C.PayloadBits==40 && C.PaddingBits==40);
assert(L.complete("immutable-C",4)==40);
L.dropTail(2,"UL",30,4);
D=L.bind("immutable-D",2,"UL",40,4,false);
assert(D.PayloadBits==40);
assert(L.abandon("immutable-D",5)==40);
assert(L.complete("immutable-D",5)==0,"Late ACK after explicit drop must not add bits.");
s=L.snapshot(5);
f=s.Files;
assert(isequal(f.DeliveredBits,[100;100;0]) && isequal(f.DroppedBits,[0;0;70]));
assert(isequal(f.RemainingBits,[0;0;30]) && isequal(f.CompletionTTI(1:2),[3;4]));
assert(f.Status(3)=="dropped_payload_incomplete_file" && f.RightCensored(3));
u=s.UserSummary(s.UserSummary.UEID==1,:);
assert(abs(u.MeanCompletedFileUPT_bps-mean([100/2.9,100/3.8]))<1e-12);
assert(abs(u.PooledCompletedFileUPT_bps-200/6.7)<1e-12 && u.WallClockGoodput_bps==40);
assert(isnan(s.UserSummary.MeanCompletedFileUPT_bps(s.UserSummary.UEID==2)));
assert(all(f.OfferedBits==f.DeliveredBits+f.DroppedBits+f.RemainingBits));
localThrows(@() L.bind("immutable-A",1,"UL",61,5,true),"sixgr:traffic:FTP3TBMutation");
localThrows(@() L.bind("unknown",1,"UL",60,5,true),"sixgr:traffic:FTP3UnknownRetransmission");
localThrows(@() L.advance(4),"sixgr:traffic:FTP3ClockBackwards");
empty=sixgr.system.FTP3FileLedger(a([],:),1,2);
none=empty.snapshot(1);
assert(isempty(none.Files) && isempty(none.UserSummary) && ...
    ismember("MeanCompletedFileUPT_bps",string(none.UserSummary.Properties.VariableNames)));
% In-flight payload cannot be silently removed by a queue-size clamp.
Q=sixgr.system.FTP3FileLedger(a(1,:),1,2);
Q.bind("reserved",1,"UL",100,1,false);
localThrows(@() Q.dropTail(1,"UL",1,1),"sixgr:traffic:FTP3DropInflight");
ok=true;
end

function localThrows(f,id)
try
    f();
catch ME
    assert(string(ME.identifier)==id,"Unexpected error: %s",ME.message);
    return
end
error("Expected exception %s",id);
end
