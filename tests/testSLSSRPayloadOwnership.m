function ok=testSLSSRPayloadOwnership()
% Uses owned modeled MAC events, never claims physical SR detector success.
r=sixgr.config.loadSimulationRequest('simulator/configs/scenarios/sls_nr_tdd_21cell_connected.yaml');
cfg=r.Config; cfg.phy.csi.reportCSI=false;
frameIdentity=cfg.phy.frame.DefaultIdentity;
ue=struct('UEID',1,'RNTI',4660,'ServingCell',1,'PUCCHCell',1, ...
    'ComponentCarrier',frameIdentity.ScheduledCCID,'ActiveULBWP',frameIdentity.ULBWPID);
unbound=sixgr.system.SLSDynamicPUCCH(cfg); unbound.configureUEIdentities(4660);
unbound.configureServingCells(1,0);
missing=unbound.srProcedureStatesAtSlotStart(ue,9);
assert(~missing.Available && isempty(missing.States),'Missing ownership is not negative SR.');
unbound.completeSlot(9,1,struct([]),{},struct([]));
assert(~isempty(unbound.CompletionTrace) && all(~unbound.CompletionTrace.SRPayloadKnown) && ...
    all(~unbound.CompletionTrace.SRDeliveryClaimed));
assert(all(unbound.CompletionTrace.SRDisposition=="unmodeled_SR_no_delivery_claim"));

ledger=sixgr.system.SLSDynamicPUCCH(cfg); ledger.configureUEIdentities(4660);
id=struct('UEIndex',1,'RNTI',4660,'CellID',1,'SchedulingRequestID',0);
p=sixgr.system.SLSSchedulingRequestProcedure(id,struct('ProhibitTimerSlots',4,'MaxTransmissions',2));
% A duplicate late in a bulk install must not retain the earlier entry.
reject(@()ledger.installSRProcedures({p,p}),'sixgr:system:DuplicateSRProcedure');
badID=id; badID.RNTI=4661;
bad=sixgr.system.SLSSchedulingRequestProcedure(badID,p.Policy);
reject(@()ledger.installSRProcedures({p,bad}),'sixgr:system:UCIIdentityMismatch');
% This successful retry proves the rejected batches did not install p.
ledger.installSRProcedure(p);
due=ledger.snapshot(8,9,1,struct([])); assert(isscalar(due));
assert(isequal(due.SchedulingRequestIDs,0));
payload=ledger.srPayloadAtSlotStart(due,9);
assert(payload.Available && isempty(payload.PositiveSchedulingRequestIDs));
assert(isscalar(payload.ProcedureStates) && ~payload.ProcedureStates.Data.Transmit && ...
    payload.ProcedureStates.Data.RNTI==4660 && payload.ProcedureStates.Data.AbsoluteSlot==9);
negative=ledger.preparePUCCHAtSlotStart(due,9,struct());
assert(negative.Available && negative.Status=="negative_SR_no_transmission" && ...
    isempty(negative.TransmitterPlan) && ~negative.NativeWaveformExecuted);
[silent,emission,tx]=ledger.generatePUCCHAtSlotStart(due,9,struct());
assert(silent.Available && ~silent.NativeWaveformExecuted && isempty(emission) && ...
    isempty(fieldnames(tx)),'A negative standalone SR must not create an emitter or request power.');
off=ledger.srProcedureStatesAtSlotStart(ue,8);
assert(off.Available && isempty(off.States),'No off-calendar SR symbols may be invented.');
ledger.completeSlot(9,1,struct([]),{},struct([]));
assert(~p.Pending && p.Counter==0 && all(ledger.CompletionTrace.SRPayloadKnown) && ...
    all(~ledger.CompletionTrace.SRDeliveryClaimed));
p.trigger(10,'owned_regular_bsr_trigger');
due=ledger.snapshot(28,29,1,struct([]));
payload=ledger.srPayloadAtSlotStart(due,29);
assert(payload.Available && isequal(payload.PositiveSchedulingRequestIDs,0));
assert(isscalar(payload.ProcedureStates) && payload.ProcedureStates.Data.Transmit);
% Feed the actual owned state into the existing canonical PHY planner. No
% receiver bits/layout supply the transmit SR; no power/PHY success is claimed.
plan=sixgr.phy.pucch.PUCCHConfigBuilder.planSR(cfg,ue,payload.ProcedureStates,struct('TargetSlot',30));
wire=sixgr.phy.pucch.UCIReportSerializer.serialize(plan.Report);
assert(wire.InformationBitCount==1 && isequal(wire.Sequence1.Bits,int8(1)) && ...
    all(wire.Layout.BitOwner=="SR"));
positive=ledger.preparePUCCHAtSlotStart(due,29,struct());
assert(positive.Available && ~positive.NativeWaveformExecuted && ...
    ~isfield(positive.TransmitterPlan,'ReceiverContext'));
reject(@()ledger.generatePUCCHAtSlotStart(due,29,struct()), ...
    'sixgr:abstraction:PUCCHEmissionSpatialBinding');
composed=sixgr.phy.pucch.UCIReportSerializer.serialize(positive.TransmitterPlan.Report);
assert(isequal(composed.Sequence1.Bits,wire.Sequence1.Bits));
reject(@()ledger.preparePUCCHAtSlotStart(due,30,struct()),'sixgr:system:SLSUCIPreparationClock');
assert(p.Counter==0,'Payload preparation must not count as transmission.');
ledger.completeSlot(29,1,struct([]),{},struct([]));
assert(p.Pending && p.Counter==1 && p.ProhibitUntilSlot0==33);
% This retains a pending request without falsely treating prohibit as a
% cancellation. Projecting the next occasion must not count a transmission.
next=ledger.srProcedureStatesAtSlotStart(ue,49);
assert(next.Available && next.States.Data.PendingPositiveSR && next.States.Data.Transmit && p.Counter==1);
row=ledger.CompletionTrace(end,:);
assert(row.SRPayloadKnown && row.PositiveSRCount==1 && row.SRDeliveryClaimed && ~row.WaveformBacked);
before=p.Trace;
reject(@()ledger.completeSlot(29,1,struct([]),{},struct([])), ...
    'sixgr:system:SLSUCIDuplicateCompletion');
assert(isequaln(before,p.Trace),'Duplicate completion must not mutate the MAC owner.');
assert(isequaln(p.Trace,ledger.schedulingRequestTrace()));
reject(@()ledger.configureServingCells(2,30), ...
    'sixgr:system:SRProcedureHandoverRequiresReconfiguration');
fprintf('SLS_SR_PAYLOAD_OWNERSHIP_PASS unmodeled_negative_positive_duplicate_handover=1\n');
ok=true;
end
function reject(fn,id)
try, fn(); catch ME, assert(strcmp(ME.identifier,id),'Expected %s, got %s',id,ME.identifier); return; end
error('test:MissingRejection','Expected %s',id);
end
