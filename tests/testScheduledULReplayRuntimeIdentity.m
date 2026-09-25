function ok=testScheduledULReplayRuntimeIdentity()
% MAC/runtime replay boundary, not an on-air qualification campaign.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_received_ul_harq_shared_fixture.yaml');
root=tempname;
cfg=sixgr.lls6g.buildInternalConfig(s,root);
saved=load(fullfile('docs','lls','evidence_20260913','scheduled_ul_dai_03', ...
    'scheduled_ul_dai_0.mat'),'fixed');
g=saved.fixed;
if isfield(g,'HARQTBContext'), g=rmfield(g,'HARQTBContext'); end
% Declared SRS metadata for this MAC-boundary fixture, not a measurement.
g.SRSValid=true; g.SRSCausalUsable=true;
g.SRSCausalMeasurementId="declared_srs_identity_fixture";
g.LastSuccessfulSRSSlot=g.Slot-1;
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',g.RNTI, ...
    'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,root,multi,struct(),10);
state.CurrentServingIdx(:)=1;
state.CurrentSlot=g.Slot; state.CurrentFrame=g.Frame;
state.CurrentCanonicalSlot=g.Slot;
a=state.ULHarq.allocate(g.RNTI,g.Slot,g.TBSBytes);
g.HARQ=a.HARQ;
scheduler=sixgr.l2.mac.SchedulerPF(cfg,'Direction','UL');
g=scheduler.freezePHYGrantForGrant(g,'TimingAlreadySelected',true);
g=localCurrentEmptyDAI(cfg,g);
assert(string(g.GrantContextId)==string(g.PHYGrant.GrantContextId));
bits=uint8(mod((1:g.TBSBits)',2));
state.ULHarq.onScheduledULGrant(g,"declared_first");
state.ULHarq.onTx(g.RNTI,g.HARQ.HarqID,bits,g,g.Slot);
assert(state.ULHarq.onFeedback(g.RNTI,g.HARQ.HarqID,"NACK", ...
    'SourceSlot',g.Slot,'FeedbackSlot',g.Slot+1));
r=state.ULHarq.peekRetx(g.RNTI);
g2=g; g2.Slot=g.Slot+10; g2.Frame=g.Frame+1;
g2.HARQ=r.HARQ; g2.IsRetransmission=true;
g2.HARQTBContext=r.TBContext;
g2.ControlAbsoluteSlot=g.ControlAbsoluteSlot+10;
g2=scheduler.freezePHYGrantForGrant(g2);
assert(g2.ExactPHYFeasible && ...
    string(g2.PHYGrant.GrantContextId)~=string(g.PHYGrant.GrantContextId) && ...
    string(g2.GrantContextId)==string(g2.PHYGrant.GrantContextId), ...
    'A new scheduled attempt must have one new frozen identity before DCI.');
same=scheduler.freezePHYGrantForGrant(g2,'TimingAlreadySelected',true);
assert(string(same.PHYGrant.GrantContextId)==string(g2.PHYGrant.GrantContextId), ...
    'Refinalizing the same selected occasion must retain its identity.');
g2=localCurrentEmptyDAI(cfg,g2);
assert(g.ULTotalDAIAuthority.ScheduledDLAssignmentCount==0 && ...
    g2.ULTotalDAIAuthority.ScheduledDLAssignmentCount==0 && ...
    g.ULTotalDAIAuthority.Digest~=g2.ULTotalDAIAuthority.Digest, ...
    'Equal empty payload widths do not make different UL occasions interchangeable.');
missing=rmfield(g2,{'DAI','ULTotalDAIAuthority'});
merged=sixgr.truth.CoupledTruthRuntime.mergeReplayCurrentGrantAuthorityRuntime(g,missing);
assert(~isfield(merged,'DAI') && ~isfield(merged,'ULTotalDAIAuthority'), ...
    'A missing current authority must not resurrect the first occasion.');
% Reproduce scheduleDirection: the physical command is already frozen,
% then its outer alias is independently composed using another ID grammar.
g2.GrantContextId="declared_runtime_retry_alias";
state.ULHarq.onScheduledULGrant(g2,"declared_second");
state.SharedGNBULHARQCommands={struct('CommandObservationID',"declared_second")};
state.CurrentSlot=g2.Slot; state.CurrentCanonicalSlot=g2.Slot; state.CurrentFrame=g2.Frame;
foreign=g2; foreign.PHYGrant.GrantContextId="foreign_frozen_command";
before=state.ULHarq.UEProcs;
try
    state.ULHarq.scheduledULReplay(foreign);
    error('test:MissingRejection','A foreign frozen command was accepted.');
catch cause
    assert(strcmp(cause.identifier,'sixgr:mac:ScheduledULProcessMismatch'),cause.message);
end
assert(isequaln(before,state.ULHarq.UEProcs));
[~,context]=sixgr.truth.CoupledTruthRuntime.buildTrialContextFromGrant(state,cfg,1,'UL',g2);
actual=context.GrantSnapshot;
assert(isequaln(actual.ULTotalDAIAuthority,g2.ULTotalDAIAuthority) && ...
    isequal(actual.DCI.Bits,g2.DCI.Bits) && actual.DAI==g2.DAI, ...
    'test:StaleReplayULDAI', ...
    'Replay kept UL authority for slot %d instead of the current slot %d.', ...
    actual.ULTotalDAIAuthority.PUSCHAbsoluteSlot,g2.ULTotalDAIAuthority.PUSCHAbsoluteSlot);
% Independent empty physical-owner fixture, initialized on its first slot.
% Do not reset a later live owner merely to construct a receive schema.
receiveState=sixgr.truth.CoupledTruthRuntime.initialize(cfg,root,multi,struct(),10);
receiveState.CurrentSlot=1; receiveState.CurrentServingIdx(:)=1;
[receiveState,~]=sixgr.truth.CoupledWaveformStream.initialize(receiveState,cfg,{cfg});
current=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,g2.TimingDecision.ControlAbsoluteSlot+1);
emptyCSI=struct('ReportConfigID',"",'ConfigurationEpoch',NaN);
[receiveContext,mapping]=sixgr.truth.buildSharedPUSCHUCIReceiveContext( ...
    receiveState,current,actual,"declared_retransmission_receiver",emptyCSI);
assert(isempty(mapping) && receiveContext.Data.HARQACKBitCount==0);
job=sixgr.truth.buildGrantPHYJob(cfg,'UL',20,g2.Frame,struct(),context);
assert(string(job.PHYGrant.GrantContextId)==string(g2.PHYGrant.GrantContextId) && ...
    isequal(uint8(job.TransportBlockBits(:)),bits));
p=state.ULHarq.UEProcs{1}(g.HARQ.HarqID+1);
fprintf('REPLAY_IDENTITY expected=%s actual=%s slot=%g/%g epoch=%g/%g rv=%g/%g tbs=%g/%g\n', ...
    string(p.LastScheduledGrant.PHYGrant.GrantContextId),string(actual.PHYGrant.GrantContextId), ...
    p.LastScheduledSlot,actual.Slot,p.NDIEpoch,actual.HARQ.NDIEpoch, ...
    p.RV,actual.HARQ.RV,8*p.TBSBytes,numel(context.TransportBlockBits));
state.ULHarq.onTx(g.RNTI,g.HARQ.HarqID,uint8(context.TransportBlockBits),actual,actual.Slot);
assert(state.ULHarq.Stats.Tx==2 && state.ULHarq.Stats.Retx==1);
ok=true;
disp('SCHEDULED_UL_REPLAY_RUNTIME_IDENTITY_PASS declared_MAC_runtime_only=1');
end

function grant=localCurrentEmptyDAI(cfg,grant)
current=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,grant.TimingDecision.ControlAbsoluteSlot+1);
scheduler=sixgr.l2.mac.SchedulerPF(current,'Direction','UL');
grant.TPMI=grant.PHYGrant.PrecodingState.TPMI;
grant.DCI=scheduler.buildDCIBitfield(grant);
grant=sixgr.truth.prepareScheduledULDAI(struct(),current,grant);
end
