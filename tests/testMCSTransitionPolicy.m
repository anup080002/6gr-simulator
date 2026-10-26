function ok=testMCSTransitionPolicy()
% Declared actual-TX/delivered-feedback boundaries; no RF or decoder claim.
setup6GRSimToolkit('Verbose',false);
cfg=sixgr.config.defaultConfig();
cfg.phy.linkAdaptation.bootstrapMCSIndex=1;
cfg.phy.linkAdaptation.mcsTransition=struct('enabled',true,'maxUpStep',1, ...
    'maxDownStep',2,'increaseAckCount',2);
s=struct('Entries',{{}});
for direction=["DL","UL"]
    g=grant(direction,1,1); [s,~]=sixgr.link.mcsTransition('commit',cfg,s,g);
    target=grant(direction,24,9);
    before=s;
    for k=1:4
        [unchanged,p]=sixgr.link.mcsTransition('preview',cfg,s,target);
        assert(isequaln(s,unchanged)&&p.AppliedMCS==1&&p.RawTargetMCS==24);
    end
    % A future/unsent transmission cannot mint ACK credit.
    [s,~]=sixgr.link.mcsTransition('feedback',cfg,s,event(direction,2,3,'ACK'));
    assert(isequaln(before,s));
    future=event(direction,1,9,'ACK'); future.CurrentSlot=8;
    [s,~]=sixgr.link.mcsTransition('feedback',cfg,s,future);
    assert(isequaln(before,s));
    ack=event(direction,1,2,'ACK');
    [s,~]=sixgr.link.mcsTransition('feedback',cfg,s,ack);
    once=s; [s,~]=sixgr.link.mcsTransition('feedback',cfg,s,ack);
    assert(isequaln(once,s));
    [~,p]=sixgr.link.mcsTransition('preview',cfg,s,target); assert(p.AppliedMCS==1);
    [s,~]=sixgr.link.mcsTransition('commit',cfg,s,grant(direction,1,3));
    [s,~]=sixgr.link.mcsTransition('feedback',cfg,s,event(direction,3,4,'ACK'));
    oldControl=target; oldControl.ControlAbsoluteSlot=3; oldControl.ScheduledAbsoluteSlot=9;
    [~,clockReceipt]=sixgr.link.mcsTransition('preview',cfg,s,oldControl);
    assert(clockReceipt.ACKCount==1 && numel(clockReceipt.ACKIdentities)==1, ...
        'Receipts cannot cite ACKs delivered after the control decision.');
    [~,p]=sixgr.link.mcsTransition('preview',cfg,s,target);
    assert(p.AppliedMCS==2 && p.ACKCount==2 && p.Reason=="received_ACK_confirmed_up_step");
    % Uncommitted previews do not spend evidence or move the anchor.
    [~,again]=sixgr.link.mcsTransition('preview',cfg,s,target); assert(isequaln(p,again));
    [s,~]=sixgr.link.mcsTransition('commit',cfg,s,grant(direction,2,5));
    [~,p]=sixgr.link.mcsTransition('preview',cfg,s,target); assert(p.AppliedMCS==2&&p.ACKCount==0);
    [s,~]=sixgr.link.mcsTransition('feedback',cfg,s,event(direction,5,6,'NACK'));
    [~,p]=sixgr.link.mcsTransition('preview',cfg,s,target);
    assert(p.AppliedMCS==0 && p.Reason=="received_NACK_down_step");
    [s,~]=sixgr.link.mcsTransition('commit',cfg,s,grant(direction,0,7));
    changed=target; changed.PMI=1; changed.TPMI=1;
    [~,p]=sixgr.link.mcsTransition('preview',cfg,s,changed);
    assert(p.AppliedMCS==0 && p.ACKCount==0);
    old=event(direction,3,8,'NACK'); [s,reason]=sixgr.link.mcsTransition('feedback',cfg,s,old);
    assert(reason.Reason=="duplicate_feedback");
    retx=grant(direction,17,8); retx.IsRetransmission=true;
    prior=s; [s,~]=sixgr.link.mcsTransition('commit',cfg,s,retx); assert(isequaln(s,prior));
end
assert(numel(s.Entries)==2,'DL/UL state must remain independent.');
% A separate declared boundary proves quality/outage safety is never raised
% to satisfy the maximum ordinary downward step.
[high,~]=sixgr.link.mcsTransition('commit',cfg,[],grant("DL",20,1));
low=grant("DL",3,2);
[~,p]=sixgr.link.mcsTransition('preview',cfg,high,low);
assert(p.AppliedMCS==3&&p.Reason=="resolved_AMC_ceiling_overrides_down_step");
custom=grant("DL",1,1); custom.PMI=NaN; custom.TPMI=NaN; custom.CRI=NaN;
custom.PrecodingMatrix=[1;0];
[explicit,~]=sixgr.link.mcsTransition('commit',cfg,[],custom);
[explicit,~]=sixgr.link.mcsTransition('feedback',cfg,explicit,event("DL",1,2,'ACK'));
custom.Slot=3; custom.HARQ.HarqID=3;
[explicit,~]=sixgr.link.mcsTransition('commit',cfg,explicit,custom);
[explicit,~]=sixgr.link.mcsTransition('feedback',cfg,explicit,event("DL",3,4,'ACK'));
custom.MCSIndex=24; custom.Slot=5;
[~,sameOperator]=sixgr.link.mcsTransition('preview',cfg,explicit,custom);
custom.PrecodingMatrix=[0;1];
[~,newOperator]=sixgr.link.mcsTransition('preview',cfg,explicit,custom);
assert(sameOperator.AppliedMCS==2 && newOperator.AppliedMCS==1 && newOperator.ACKCount==0, ...
    'Unindexed explicit matrices need their own operator-scoped ACK evidence.');
% Serialize the exact policy state used by the scheduler/checkpoint owner.
path=[tempname '.mat']; cleanup=onCleanup(@()delete(path)); %#ok<NASGU>
save(path,'s'); loaded=load(path,'s'); assert(isequaln(s,loaded.s));
[~,a]=sixgr.link.mcsTransition('preview',cfg,s,grant("DL",24,9));
[~,b]=sixgr.link.mcsTransition('preview',cfg,loaded.s,grant("DL",24,9)); assert(isequaln(a,b));
sch=sixgr.l2.mac.SchedulerPF(cfg,'Direction','DL');
g=grant("DL",1,1); sch.commitMCSTransition(g);
sch.observeMCSTransitionFeedback(event("DL",1,2,'ACK'));
sch.commitMCSTransition(grant("DL",1,3));
sch.observeMCSTransitionFeedback(event("DL",3,4,'ACK'));
stateBefore=sch.getMCSTransitionState();
bounded=sch.previewMCSTransition(grant("DL",24,5));
repeated=sch.previewMCSTransition(bounded);
assert(bounded.MCSIndex==2 && repeated.MCSTransitionRawTarget==24 && ...
    isequaln(stateBefore,sch.getMCSTransitionState()));
% Actual native object serialization, including protected scheduler fields.
save(path,'sch','-v7.3'); restored=load(path,'sch');
assert(isequaln(sch.getMCSTransitionState(),restored.sch.getMCSTransitionState()));
issued=bounded; issued.PDCCHGrantBindingOk=true;
sch.commitMCSTransition(grant("DL",2,5));
sch.observeMCSTransitionFeedback(event("DL",5,6,'NACK'));
preserved=sch.previewMCSTransition(issued);
assert(isequaln(issued,preserved),'Received DCI cannot be rewritten using later feedback.');
for kind=["PF","RR"]
    localScheduler(cfg,kind);
end
ok=true;
end

function localScheduler(cfg,kind)
cfg=withCanonicalSchedulerTiming(cfg);
cfg.phy.linkAdaptation.mode='amc'; cfg.phy.linkAdaptation.dlPolicy='cqi_driven';
cfg.phy.pdsch.mcsIndex=NaN; cfg.phy.pdsch.mcsPolicy='cqi_driven';
cfg.phy.pdsch.symbolAllocation=[2 12];
cfg.phy.pdsch.timeDomainAllocations=[0 2 12 1];
cfg.mac.scheduler.maxUEPerSlot=1; cfg.mac.scheduler.maxUEPerSlotDL=1;
cfg.mac.scheduler.muMimoEnabled=false;
if kind=="PF", sch=sixgr.l2.mac.SchedulerPF(cfg,'Direction','DL');
else, sch=sixgr.l2.mac.SchedulerRR(cfg,'Direction','DL'); end
ue=struct('RNTI',101,'UEIndex',1,'ServingCell',1,'DLBufferBytes',20000, ...
    'CQI',15,'RI',1,'PMI',NaN,'CRI',NaN,'HeadOfLineDelay_ms',1, ...
    'ControlEligible',true,'GrantControlState','ok');
budget=struct('PRBSet',0:23,'ControlSymbolAllocation',[0 2],'SymbolAllocation',[2 12]);
g=sch.schedule(0,ue,budget); assert(numel(g)==1 && g.MCSIndex<=1);
uncommitted=sch.getMCSTransitionState();
assert(isempty(uncommitted.Entries),'Scheduling alone cannot commit an MCS anchor.');
% Runtime AMC must reapply the cap after receiving a higher target.
feedback=struct('Valid',true,'CQI',15,'RI',1,'PMI',NaN,'CRI',NaN, ...
    'SourceSlot',0,'DeliveredSlot',0,'MCSIndex',28,'LinkAdaptationMCSIndex',28, ...
    'CQIBasedMCS',28,'InstantaneousCQIMCS',28);
aligned=sixgr.truth.CoupledTruthRuntime.applyMeasuredFeedbackAMCToGrantRuntime( ...
    g,feedback,sch,cfg,'DL');
assert(aligned.MCSIndex<=1 && aligned.ExactPHYFeasible, ...
    'Final runtime AMC must retain the cap and recompute a feasible grant.');
assert(aligned.LinkAdaptationFeedbackApplied && aligned.MCSTransitionRawTarget>aligned.MCSIndex);
evidence=sixgr.truth.projectMCSTransitionEvidence(aligned);
assert(strlength(evidence.MCSTransitionReceiptSHA256)==64 && ...
    evidence.MCSTransitionAppliedMCS==aligned.MCSIndex && ...
    string(sixgr.util.sha256Hex(evidence.MCSTransitionReceiptJSON))==evidence.MCSTransitionReceiptSHA256);
end

function g=grant(direction,mcs,slot)
g=struct('Direction',direction,'RNTI',101,'ServingCell',1,'NumLayers',1, ...
    'PMI',0,'TPMI',0,'CRI',0,'Slot',slot,'MCSIndex',mcs, ...
    'HARQ',struct('HarqID',mod(slot,4),'IsRetransmission',false));
end

function e=event(direction,source,delivered,outcome)
e=struct('Direction',direction,'RNTI',101,'ServingCell',1, ...
    'SourceSlot',source,'DeliveredSlot',delivered,'CurrentSlot',delivered, ...
    'HarqID',mod(source,4),'Outcome',outcome,'IsRetransmission',false);
end
