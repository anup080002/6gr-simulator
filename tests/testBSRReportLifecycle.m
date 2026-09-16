function ok=testBSRReportLifecycle()
% Declared MAC events: no normal coordinator, waveform or RF claim.
setup6GRSimToolkit('Verbose',false);
machine=sixgr.l2.mac.BSRStateMachine(1,8,20,40);
machine.arrival(0,1000);
report=machine.buildReport(2,7);
assert(report.Transmit && report.TableID=="5bit" && report.Indices==15);
assert(report.LCID==61 && report.MACSubPDUBytes==2);
assert(machine.PendingTrigger=="regular" && isnan(machine.LastReportSlot));
assert(machine.PeriodicExpirySlot==27 && machine.RetxExpirySlot==47);
% A later triggering event must survive an older report's transmission.
machine.trigger("periodic");
machine.recordTransmission(report,8);
assert(machine.PendingTrigger=="periodic" && machine.LastReportSlot==8);
reject(@()machine.recordTransmission(report,8),'sixgr:mac:UnknownBSRPreparation');
assert(machine.PendingTrigger=="periodic" && machine.LastReportSlot==8);
next=machine.buildReport(2,8);
changed=next; changed.Payload=uint8(0);
reject(@()machine.recordTransmission(changed,9),'sixgr:mac:BSRPreparationMismatch');
other=sixgr.l2.mac.BSRStateMachine(2,8,20,40);
reject(@()other.recordTransmission(next,9),'sixgr:mac:UnknownBSRPreparation');
machine.discardReport(next);
assert(machine.PendingTrigger=="periodic" && machine.LastReportSlot==8);
reject(@()machine.recordTransmission(next,9),'sixgr:mac:UnknownBSRPreparation');
next=machine.buildReport(2,9); machine.recordTransmission(next,9);
assert(machine.PendingTrigger=="none");
assert(~machine.buildReport(20,10).Transmit);

% Regular BSR with two active LCGs requires five bytes, not four.
machine=sixgr.l2.mac.BSRStateMachine(3,8,20,5);
machine.arrival(0,100); machine.arrival(1,200); machine.trigger("padding");
assert(machine.PendingTrigger=="regular");
assert(~machine.buildReport(4,0).Transmit);
assert(isnan(machine.PeriodicExpirySlot) && isnan(machine.LastReportSlot));
report=machine.buildReport(5,0);
assert(report.LCID==62 && report.TableID=="8bit" && isequal(report.Indices,[37 48]));
wire=sixgr.l2.mac.MACPDUAssembler.assemble('UL', ...
    struct('LCID',report.LCID,'Payload',report.Payload,'OwnerID',"declared_BSR_lifecycle"),5);
assert(numel(wire.Bytes)==report.MACSubPDUBytes);
machine.recordTransmission(report,0); assert(machine.PendingTrigger=="none");
p=struct('HighestPriorityWithData',[1 2 8 8 8 8 8 8], ...
    'HighestPriorityConfigured',[2 1 8 8 8 8 8 8]);
machine.trigger("padding"); truncated=machine.buildReport(4,1,p);
assert(truncated.Truncated && truncated.LCID==60 && isequal(truncated.LCGIDs,1));
assert(machine.PeriodicExpirySlot==20 && machine.RetxExpirySlot==6);
machine.recordTransmission(truncated,1);
assert(machine.PendingTrigger=="padding");
full=machine.buildReport(5,2); machine.recordTransmission(full,2);
assert(machine.PendingTrigger=="none");

% Timer expiry is now exercised on the state object, not just a CSV vector.
machine=sixgr.l2.mac.BSRStateMachine(4,1,2,4);
machine.arrival(0,10); report=machine.buildReport(2,0); machine.recordTransmission(report,0);
machine.advanceTo(1); assert(machine.PendingTrigger=="none");
machine.advanceTo(2); assert(machine.PendingTrigger=="periodic");
report=machine.buildReport(2,2); machine.recordTransmission(report,2);
machine.dequeue(0,10); machine.advanceTo(4);
report=machine.buildReport(2,4);
assert(report.Transmit && report.Indices==0 && report.LCID==61);
machine.recordTransmission(report,4); machine.advanceTo(8);
assert(machine.PendingTrigger=="periodic"); % Empty queue does not trigger retx BSR.

machine=sixgr.l2.mac.BSRStateMachine(5,1,20,4);
machine.arrival(0,10); report=machine.buildReport(2,0); machine.recordTransmission(report,0);
machine.receivedNewDataGrant(3);
assert(machine.RetxExpirySlot==7 && machine.PendingTrigger=="none");
machine.advanceTo(4); assert(machine.PendingTrigger=="none");
machine.advanceTo(7); assert(machine.PendingTrigger=="regular");
% Same-kind triggers after assembly also remain pending.
report=machine.buildReport(2,7); machine.trigger("regular");
machine.recordTransmission(report,8); assert(machine.PendingTrigger=="regular");
reject(@()machine.advanceTo(7));
reject(@()machine.dequeue(0,11),'sixgr:mac:BSRBufferUnderflow');
assert(machine.Buffers==10);
reject(@()machine.buildReport(NaN,8));
reject(@()machine.arrival(0,Inf));
reject(@()machine.trigger(["regular","padding"]),'sixgr:mac:InvalidBSRTrigger');
reject(@()sixgr.l2.mac.BSRStateMachine(1,9,20,40),'sixgr:mac:InvalidLCGBufferMap');
% Integer-typed events must not saturate buffer or timer arithmetic.
machine=sixgr.l2.mac.BSRStateMachine(6,1,20,40);
machine.arrival(uint8(0),uint8(200)); machine.arrival(uint8(0),uint8(100));
assert(machine.Buffers==300);
machine.dequeue(uint8(0),uint8(10)); assert(machine.Buffers==290);
report=machine.buildReport(uint8(2),uint8(250));
assert(machine.PeriodicExpirySlot==270 && machine.RetxExpirySlot==290);
machine.recordTransmission(report,uint8(250)); machine.receivedNewDataGrant(uint8(251));
assert(machine.RetxExpirySlot==291);
% Equal-content preparations must not alias: abandoning one MAC PDU cannot
% erase a different prepared PDU. Each declared TX callback is single-use.
machine=sixgr.l2.mac.BSRStateMachine(7,1,20,40);
machine.arrival(0,1000);
assert(~machine.buildReport(1,3).Transmit);
first=machine.buildReport(2,3); second=machine.buildReport(2,3);
assert(first.PreparationSequence==1 && second.PreparationSequence==2);
assert(first.ReportID~=second.ReportID && isequal(first.Payload,second.Payload));
assert(first.CoveredTriggerSequence==second.CoveredTriggerSequence);
machine.discardReport(first);
assert(machine.PendingTrigger=="regular" && isnan(machine.LastReportSlot));
machine.recordTransmission(second,3);
assert(machine.PendingTrigger=="none" && machine.LastReportSlot==3);
reject(@()machine.recordTransmission(first,3),'sixgr:mac:UnknownBSRPreparation');
reject(@()machine.recordTransmission(second,3),'sixgr:mac:UnknownBSRPreparation');
machine.trigger("regular");
first=machine.buildReport(2,4); second=machine.buildReport(2,4);
altered=second; altered.PreparationSequence=first.PreparationSequence;
reject(@()machine.recordTransmission(altered,4),'sixgr:mac:BSRPreparationMismatch');
machine.recordTransmission(second,4);
machine.trigger("regular");
machine.recordTransmission(first,4);
assert(machine.PendingTrigger=="regular" && machine.LastReportSlot==4);
reject(@()machine.recordTransmission(first,4),'sixgr:mac:UnknownBSRPreparation');
fprintf('BSR_REPORT_LIFECYCLE_PASS exact_tables=1 wire_budget=1 prepare_does_not_cancel=1 late_trigger_preserved=1 timer_expiry=1 independent_preparation_identity=1 duplicate_and_altered_rejected=1 RF_executions=0 normal_SR_integration=0\n');
ok=true;
end

function reject(fn,id)
try, fn(); catch cause
    if nargin>1, assert(strcmp(cause.identifier,id),'Expected %s; got %s.',id,cause.identifier); end
    return;
end
error('test:MissingBSRLifecycleRejection','Invalid BSR lifecycle transition was accepted.');
end
