function ok = testCoupledFeedbackAgePropagation()
% Exercise the production UE-state builder, not hand-written scheduler ages.
setup6GRSimToolkit('Verbose',false);
scfg=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios','lls_tdd_5mhz_rank2_shared_awgn_20db.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(scfg,tempname);
cfg.phy.linkAdaptation.maxCSIAgeSlots=5;
cfg.phy.linkAdaptation.dlMaxCSIAgeSlots=5;
cfg.phy.linkAdaptation.ulMaxCSIAgeSlots=5;
cfg.phy.linkAdaptation.bootstrapCQIMode='measured_only';
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1, ...
    'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,tempname,multi,struct(),20);
state.CurrentSlot=30; state.CurrentCanonicalSlot=30;
state.CurrentServingIdx(:)=1;
% Isolate the AMC boundary from initial access; retain a fresh SRS spatial
% observation independently from the older data-quality feedback below.
state.ControlGating.Enabled=false;
state.LastSuccessfulSRSSlotByUE(:)=30;
state.ControlGating.SRSMaxAgeSlots=5;
fb=sixgr.truth.CoupledTruthRuntime.emptyLatestFeedbackRowRuntime();
fb.Valid=true; fb.CQI=11; fb.RI=1; fb.PMI=0;
fb.Slot=25; fb.SourceSlot=25; fb.DueSlot=29; fb.DeliveredSlot=29;
fb.SINR_dB=20; fb.MCSIndex=20; fb.Modulation='64QAM'; fb.TargetCodeRate=0.5;
for direction=["DL","UL"]
    name="Latest"+direction+"Feedback";
    fb.Direction=char(direction); state.(name)(1)=fb;
    [~,ue]=sixgr.truth.CoupledTruthRuntime.buildSchedulerUEStateRuntime( ...
        state,cfg,1,direction,1);
    assert(isfield(ue,'FeedbackAgeSlots') && ue.FeedbackAgeSlots==5, ...
        'sixgr:test:MissingProductionFeedbackAge', ...
        'Production %s scheduler input must retain source age, not delivery age.',direction);
    assert(ue.FeedbackSourceSlot==25 && ue.FeedbackDeliveredSlot==29 && ...
        ue.FeedbackKnownAtSlot==30 && abs(ue.FeedbackAgeSeconds-5*state.SlotDuration_s)<eps);
    sched=sixgr.l2.mac.SchedulerPF(cfg,'Direction',direction);
    [~,~,~,amc]=sched.selectAMC(ue);
    assert(amc.CausalFeedbackUsable, ...
        'The inclusive %s age boundary must remain usable: %s (runtime %s).', ...
        direction,string(amc.CausalFeedbackStatus),string(ue.CausalFeedbackStatus));
    expired=state; expired.CurrentSlot=31; expired.CurrentCanonicalSlot=31;
    [~,ue]=sixgr.truth.CoupledTruthRuntime.buildSchedulerUEStateRuntime( ...
        expired,cfg,1,direction,1);
    [~,~,~,amc]=sched.selectAMC(ue);
    assert(~amc.CausalFeedbackUsable && contains(string(amc.CausalFeedbackStatus),'stale_csi'));
    conservative=cfg; conservative.phy.linkAdaptation.bootstrapCQIMode='conservative';
    bootSched=sixgr.l2.mac.SchedulerPF(conservative,'Direction',direction);
    [~,~,~,blocked]=bootSched.selectAMC(ue);
    assert(string(blocked.MCSSelectionSource)=="blocked_missing_runtime_cqi", ...
        'Expired measured feedback must not reopen first-report bootstrap.');
    for delivered=[NaN,31]
        future=state; future.(name)(1).DeliveredSlot=delivered;
        [~,ue]=sixgr.truth.CoupledTruthRuntime.buildSchedulerUEStateRuntime( ...
            future,cfg,1,direction,1);
        [~,~,~,amc]=sched.selectAMC(ue);
        assert(~amc.CausalFeedbackUsable,'Missing/future delivery cannot authorize AMC.');
    end
    future=state; future.(name)(1).SourceSlot=31;
    [~,ue]=sixgr.truth.CoupledTruthRuntime.buildSchedulerUEStateRuntime( ...
        future,cfg,1,direction,1);
    assert(~ue.CausalFeedbackUsable && ue.FeedbackAgeSlots==-1);
end
% Resource freshness uses the future grant slot; availability uses the
% actual decision clock, even if a report is present in a poisoned snapshot.
plan=state; plan.CurrentSlot=35; plan.PlanningDecisionSlot=30;
plan.RuntimeViewMode='future_ul_grant_planning';
plan.LatestULFeedback(1).SourceSlot=30;
plan.LatestULFeedback(1).DeliveredSlot=31;
[~,ue]=sixgr.truth.CoupledTruthRuntime.buildSchedulerUEStateRuntime(plan,cfg,1,'UL',1);
assert(ue.FeedbackAgeSlots==5 && ue.FeedbackKnownAtSlot==30 && ~ue.CausalFeedbackUsable);
plan.LatestULFeedback(1).DeliveredSlot=30;
[~,ue]=sixgr.truth.CoupledTruthRuntime.buildSchedulerUEStateRuntime(plan,cfg,1,'UL',1);
assert(ue.CausalFeedbackUsable && ue.FeedbackAgeSlots==5);
% No measured report retains the explicit bootstrap policy, not a fake age.
state.LatestULFeedback(1).Valid=false;
[~,ue]=sixgr.truth.CoupledTruthRuntime.buildSchedulerUEStateRuntime(state,cfg,1,'UL',1);
assert(~ue.FeedbackValid && isnan(ue.FeedbackAgeSlots));
% Re-alignment may not revive a stale decision after scheduler admission.
grant=struct('Slot',31,'IsRetransmission',false,'RV',0,'MCSIndex',0, ...
    'Modulation','QPSK','TargetCodeRate',0.1,'NumLayers',1);
same=sixgr.truth.CoupledTruthRuntime.realignGrantAMCFromMeasuredFeedbackRuntime( ...
    grant,fb,[],cfg,'UL');
assert(isequaln(same,grant),'Stale CQI must not rewrite a later grant.');
grant.IsRetransmission=true; grant.RV=2; grant.NDI=0; grant.TBSBits=1024;
same=sixgr.truth.CoupledTruthRuntime.realignGrantAMCFromMeasuredFeedbackRuntime( ...
    grant,fb,[],cfg,'UL');
assert(isequaln(same,grant),'Age enforcement must not mutate an in-flight TB.');
fprintf('COUPLED_FEEDBACK_AGE_PROPAGATION_PASS\n');
ok=true;
end
