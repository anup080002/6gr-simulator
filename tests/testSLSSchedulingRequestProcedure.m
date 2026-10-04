function ok=testSLSSchedulingRequestProcedure()
% State-machine evidence only; no detector qualification or waveform claim.
id=struct('UEIndex',1,'RNTI',4660,'CellID',1,'SchedulingRequestID',0);
policy=struct('ProhibitTimerSlots',4,'MaxTransmissions',2);
p=sixgr.system.SLSSchedulingRequestProcedure(id,policy);
assert(~p.project(0).MayTransmit);
p.trigger(1,'arrival_1'); before=p.Trace;
a=p.project(2); assert(a.MayTransmit);
assert(isequaln(a,p.project(2)) && isequaln(before,p.Trace));
p.project(50); assert(p.CurrentSlot0==1,'Planning must not advance the event clock.');
p.commitTransmission(a,'sr_tx_2');
assert(p.Pending && p.Counter==1 && ~p.project(5).MayTransmit && p.project(6).MayTransmit);
reject(@()p.commitTransmission(a,'duplicate'),'sixgr:system:StaleSRTransmission');
p.trigger(3,'arrival_2'); assert(p.Counter==1,'Retriggering pending SR must not reset its counter.');
before=p.Trace;
reject(@()p.cancelForGrant(4,10,11,'small_grant'),'sixgr:system:SRGrantDoesNotCoverPendingData');
reject(@()p.cancelForTransmittedBSR(4,1,'short','old_bsr'),'sixgr:system:SRBSRDoesNotCoverTrigger');
reject(@()p.cancelForTransmittedBSR(4,2,'truncated','partial_bsr'),'sixgr:system:SRBSRDoesNotCoverTrigger');
assert(isequaln(before,p.Trace) && p.Pending && p.CurrentSlot0==3);
p.cancelForTransmittedBSR(4,2,'short','transmitted_bsr');
assert(~p.Pending && p.ProhibitUntilSlot0==4);
p.trigger(5,'arrival_3'); assert(p.Counter==0);
p.cancelForGrant(5,12,12,'covering_grant'); assert(~p.Pending);
p.trigger(6,'arrival_4'); p.commitTransmission(p.project(6),'sr_tx_6');
p.commitTransmission(p.project(10),'sr_tx_10');
assert(~p.project(13).RequiresRandomAccess && p.project(14).RequiresRandomAccess);
p.requireRecovery(14); assert(p.RequiresRandomAccess && ~p.Pending);
reject(@()p.trigger(15,'late_arrival'),'sixgr:system:SRRandomAccessRequired');
assert(all(~p.Trace.WaveformBacked));
% Independent UE and SR IDs have independent counters and timer histories.
id.UEIndex=2; id.RNTI=4661; id.SchedulingRequestID=1;
q=sixgr.system.SLSSchedulingRequestProcedure(id,policy);
q.trigger(0,'other_ue'); assert(q.project(0).MayTransmit && q.Counter==0);
fprintf('SLS_SR_PROCEDURE_PASS planning_timers_counter_qualified_cancellation_recovery_identity=1\n');
ok=true;
end
function reject(fn,id)
try, fn(); catch ME, assert(strcmp(ME.identifier,id),'Expected %s, got %s',id,ME.identifier); return; end
error('test:MissingRejection','Expected %s',id);
end
