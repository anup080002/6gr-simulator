function ok=testPHRPreviewCommit()
% Component declared actual-commit boundary, no air-interface claim.
st=sixgr.l2.mac.PHRStateMachine(1); st.trigger('activation',4);
entry=struct('PH_dB',0,'PCMAX_dBm',23);
a=st.buildReport(entry,4,5); b=st.buildReport(entry,4,5);
assert(isequaln(a,b) && st.PendingTrigger=="activation" && isinf(st.ProhibitUntilSlot));
tx=struct('Executed',false,'IsNewData',true,'UEID',1,'Slot',5, ...
    'TransmissionID',"tx1",'PHRReportSHA256',a.ReportSHA256);
rejects(@()st.recordTransmission(a,tx)); assert(st.PendingTrigger=="activation");
tx.Executed=true; wrong=tx; wrong.IsNewData=false; rejects(@()st.recordTransmission(a,wrong));
st.recordTransmission(a,tx); assert(st.PendingTrigger=="none" && st.ProhibitUntilSlot==10);
st.recordTransmission(a,tx); assert(numel(st.CommittedTransmissionIDs)==1);
wrong=tx; wrong.TransmissionID="tx2"; rejects(@()st.recordTransmission(a,wrong));
st.trigger('periodic',10); pending=st.buildReport(entry,10,5);
st.trigger('pathlosschange',11); tx.Slot=11; tx.TransmissionID="tx3";
tx.PHRReportSHA256=pending.ReportSHA256; st.recordTransmission(pending,tx);
assert(st.PendingTrigger=="pathlosschange");
% A trigger already admitted before the older commit remains pending.
assert(st.buildReport(entry,12,5).Transmit);
% Prohibit gates new pathloss/backoff triggers, not periodic/configuration.
q=sixgr.l2.mac.PHRStateMachine(2,20); q.receivedNewDataGrant(1);
assert(q.PeriodicDueSlot==21); q.trigger('configuration',1);
r=q.buildReport(entry,1,10); commit=struct('Executed',true,'IsNewData',true, ...
    'UEID',2,'Slot',1,'TransmissionID',"q1",'PHRReportSHA256',r.ReportSHA256);
q.recordTransmission(r,commit); q.trigger('pathlosschange',2); assert(q.PendingTrigger=="none");
q.trigger('periodic',2); assert(q.buildReport(entry,2,10).Transmit);
path=[tempname '.mat']; cleanup=onCleanup(@()delete(path)); save(path,'st');
loaded=load(path,'st'); assert(loaded.st.PendingTrigger=="pathlosschange");
assert(isequal(loaded.st.CommittedTransmissionIDs,st.CommittedTransmissionIDs));
ok=true;
end
function rejects(f)
thrown=false; try, f(); catch, thrown=true; end
assert(thrown,'Expected strict PHR commit rejection.');
end
