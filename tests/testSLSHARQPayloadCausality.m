function ok=testSLSHARQPayloadCausality()
% Ledger contract only. Decisions below are explicit test fixtures, not CRCs.
request=sixgr.config.loadSimulationRequest('simulator/configs/scenarios/sls_nr_tdd_21cell_connected.yaml');
cfg=request.Config; cfg.phy.csi.reportCSI=false;
ledger=sixgr.system.SLSDynamicPUCCH(cfg); ledger.configureUEIdentities(4660);
context=sixgr.phy.pdcch.DCIContext.fromLegacy(struct( ...
    'NSizeGrid',cfg.phy.carrier.NSizeGrid,'RNTIValue',4660),"1_0");
schema=sixgr.phy.pdcch.DCISchemaEngine.resolve(context); fields=struct();
for def=schema.Definitions(:).', fields.(def.Name)=def.ValueMin; end
fields.pucch_resource_indicator=0;
dci=sixgr.phy.pdcch.DCIPacker.pack(fields,context); dci.ContextData=context.Data;
g=struct('UEIndex',1,'RNTI',4660,'ControlAbsoluteSlot',5, ...
    'ScheduledAbsoluteSlot',5,'HARQFeedbackAbsoluteSlot',9,'DCI',dci, ...
    'PHYGrant',struct('IsFrozen',true,'CodingLayout',struct('NumCodewords',1)));
g.HARQ=struct('HarqID',0,'RV',0,'NDI',1,'IsRetransmission',false);
h=g; h.ControlAbsoluteSlot=6; h.ScheduledAbsoluteSlot=6;
ledger.appendDL([h g],[1 1],6); % Intentionally not in source-slot order.
due=ledger.snapshot(8,9,1,struct([])); due=due([due.HARQBits]>0);
assert(isscalar(due) && due.HARQBits==2);
empty=ledger.harqPayloadAtSlotStart(due,8);
assert(~empty.Available && isempty(empty.HARQACKBits) && isempty(ledger.HARQDecisionTrace));
unprepared=ledger.preparePUCCHAtSlotStart(due,9,struct());
assert(~unprepared.Available && unprepared.Status=="missing_causal_HARQ_payload" && ...
    isempty(unprepared.TransmitterPlan) && ~unprepared.NativeWaveformExecuted);
[c1,r1]=decision(g,5,true,"first_tb");
ledger.recordHARQDecision(c1,r1);
partial=ledger.harqPayloadAtSlotStart(due,8);
assert(~partial.Available && isempty(partial.HARQACKBits),'Missing decisions must not turn into NACKs or prefixes.');
[c2,r2]=decision(h,8,false,"second_tb");
ledger.recordHARQDecision(c2,r2);
sameSlot=ledger.harqPayloadAtSlotStart(due,8);
assert(~sameSlot.Available && isempty(sameSlot.HARQACKBits), ...
    'End-of-slot decode cannot supply a beginning-of-slot waveform.');
ready=ledger.harqPayloadAtSlotStart(due,9);
assert(ready.Available && isequal(ready.HARQACKBits,int8([1;0])) && ...
    isequal(ready.DecisionRows.TransmissionAbsoluteSlot0,[5;6]) && ...
    ~ready.WaveformBacked && ~ready.PhysicalDecodeQualified && ...
    ~any(ready.DecisionRows.CalibrationQualified));
before=ledger.HARQDecisionTrace;
ledger.recordHARQDecision(c2,r2); assert(isequaln(before,ledger.HARQDecisionTrace));
bad=r2; bad.Ok=true;
reject(@()ledger.recordHARQDecision(c2,bad),'sixgr:system:SLSHARQDecisionMutation');
bad=r2; bad.TransportBlockIdentity="other_tb";
reject(@()ledger.recordHARQDecision(c2,bad),'sixgr:system:SLSHARQDecisionClock');
bad=r2; bad.ReceiveCompletionAbsoluteSlot0=4;
reject(@()ledger.recordHARQDecision(c2,bad),'sixgr:system:SLSHARQDecisionClock');
bad=r2; bad.ReceiveCompletionAbsoluteSlot0=10;
reject(@()ledger.recordHARQDecision(c2,bad),'sixgr:system:SLSHARQDecisionClock');
bad=r2; bad.CalibrationQualified=true;
reject(@()ledger.recordHARQDecision(c2,bad),'sixgr:system:SLSHARQDecisionEvidence');
bad=r2; bad.WaveformReplayExecuted=true;
reject(@()ledger.recordHARQDecision(c2,bad),'sixgr:system:SLSHARQDecisionEvidence');
wrong=c2; wrong.Grant.DCI.Bits(1)=1-wrong.Grant.DCI.Bits(1);
reject(@()ledger.recordHARQDecision(wrong,r2),'sixgr:system:SLSHARQDecisionIdentity');
wrong=c2; wrong.ServingCellID=2;
reject(@()ledger.recordHARQDecision(wrong,r2),'sixgr:system:SLSHARQDecisionIdentity');
wrong=due; wrong.HARQSourceGrantSHA256=strjoin(flip(split(due.HARQSourceGrantSHA256,"|")),"|");
reject(@()ledger.harqPayloadAtSlotStart(wrong,9),'sixgr:system:SLSHARQPayloadIdentity');
reject(@()ledger.harqPayloadAtSlotStart(due,10),'sixgr:system:SLSHARQPayloadClock');
assert(isequaln(before,ledger.HARQDecisionTrace) && isempty(ledger.CompletionTrace));
feedback=struct('RNTI',4660,'SourceSlot',5,'Ack',true);
feedback.HarqID=0; feedback.RV=0; feedback.NDI=1; feedback.IsRetransmission=false;
reject(@()ledger.requireHARQCompletion(feedback,1,9),'sixgr:system:SLSUCINotCompleted');
ledger.completeSlot(9,1,struct([]),{},struct([]));
ledger.requireHARQCompletion(feedback,1,9);
changed=feedback; changed.Ack=false;
reject(@()ledger.requireHARQCompletion(changed,1,9),'sixgr:system:SLSUCIHARQDecisionMismatch');
for field=["HarqID","RV","NDI","IsRetransmission"]
    changed=feedback; changed.(field)=1-double(changed.(field));
    reject(@()ledger.requireHARQCompletion(changed,1,9),'sixgr:system:SLSUCIHARQDecisionMismatch');
end
changed=feedback; changed.Ack=NaN;
reject(@()ledger.requireHARQCompletion(changed,1,9),'sixgr:system:SLSUCIHARQDecisionMissing');
noDecision=sixgr.system.SLSDynamicPUCCH(cfg); noDecision.configureUEIdentities(4660);
noDecision.appendDL(g,1,5); noDecision.completeSlot(9,1,struct([]),{},struct([]));
assert(~isempty(noDecision.Trace) && isempty(noDecision.CompletionTrace), ...
    'A reserved HARQ occasion without its decision must remain unresolved.');
reject(@()noDecision.requireHARQCompletion(feedback,1,9),'sixgr:system:SLSUCIHARQDecisionMissing');
reject(@()noDecision.configureServingCells(2,10),'sixgr:system:UCIHandoverOutstanding');
% A combined obligation must not complete only its known prefix. Retain the
% original source-cell ownership even after its scheduled occasion elapsed.
partialLedger=sixgr.system.SLSDynamicPUCCH(cfg); partialLedger.configureUEIdentities(4660);
partialLedger.appendDL([g h],[1 1],6);
partialLedger.recordHARQDecision(c1,r1);
partialLedger.completeSlot(9,1,struct([]),{},struct([]));
assert(isempty(partialLedger.CompletionTrace));
reject(@()partialLedger.configureServingCells(2,10),'sixgr:system:UCIHandoverOutstanding');
% Same-slot completion may support the declared ideal delayed-control
% model, but it is explicitly not ready for a slot-start waveform emission.
late=sixgr.system.SLSDynamicPUCCH(cfg); late.configureUEIdentities(4660);
late.appendDL(g,1,5); o=late.snapshot(8,9,1,struct([])); o=o([o.HARQBits]>0);
[ctx,r]=decision(g,9,true,"late_completion_fixture"); late.recordHARQDecision(ctx,r);
p=late.harqPayloadAtSlotStart(o,9); assert(~p.Available && isempty(p.HARQACKBits));
late.completeSlot(9,1,struct([]),{},struct([]));
late.requireHARQCompletion(feedback,1,9);
assert(~isempty(late.CompletionTrace) && ~any(late.CompletionTrace.WaveformBacked));
folder=tempname(fullfile(pwd,'logs')); mkdir(folder);
file=fullfile(folder,'modeled_harq_decisions_fixture.csv');
sixgr.util.csvWriteTable(file,before,'PreserveSchema',true); persisted=readtable(file);
assert(isequal(double(persisted.ACK),double(before.ACK)) && ...
    isequal(persisted.ReceiveCompletionAbsoluteSlot0,before.ReceiveCompletionAbsoluteSlot0) && ...
    all(string(persisted.SourceClassification)=="development_fixture_not_study_result") && ...
    ~any(persisted.WaveformBacked));
fprintf('SLS_HARQ_PAYLOAD_CAUSALITY_PASS exact_order=1 no_missing_NACK=1 no_future_decision=1 evidence=%s\n',folder);
ok=true;
end
function [ctx,replay]=decision(g,completion,ack,tb)
ctx=struct('Direction',"DL",'Grant',g,'ServingCellID',1,'TransportBlockIdentity',tb);
ctx.Grant.TransportBlockIdentity=tb;
replay=struct('Ok',ack,'TransportBlockIdentity',tb, ...
    'TransmissionAbsoluteSlot0',g.ScheduledAbsoluteSlot,'ReceiveCompletionAbsoluteSlot0',completion, ...
    'SourceClassification',"development_fixture_not_study_result",'CalibrationQualified',false, ...
    'CalibrationSHA256',repmat('a',1,64),'CalibrationCurveID',"fixture_only", ...
    'CalibrationKeySHA256',repmat('b',1,64),'WaveformReplayExecuted',false,'PHYDecisionStatus',"OK");
end
function reject(fn,id)
try
    fn();
catch cause
    assert(strcmp(cause.identifier,id),'Expected %s, got %s: %s',id,cause.identifier,cause.message); return;
end
error('test:MissingRejection','Expected %s',id);
end
