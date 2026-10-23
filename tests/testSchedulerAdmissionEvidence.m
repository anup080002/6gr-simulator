function ok=testSchedulerAdmissionEvidence()
% Exercise production admission/export, not PHY or statistical qualification.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
source=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_pdcch_shared_queue_fixture.yaml');
cfg=sixgr.lls6g.buildInternalConfig(source,tempname);
cfg.phy.pusch.transmissionScheme='codebook';
cfg.validation.strictWaveformTruthRequired=true;
cfg.phy.pdsch.qclTCI.enabled=false;
cfg.mac.harq.enable=true;
cfg.mac.harq.numProcesses=2;
cfg.mac.harq.maxRetx=3;
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
out=tempname; mkdir(out);
cleanup=onCleanup(@()rmdir(out,'s')); %#ok<NASGU> this test owns out
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,out,multi,struct(),10);
state=sixgr.truth.CoupledTruthRuntime.advanceFrame(state,cfg,multi,1,20);
state=sixgr.truth.CoupledTruthRuntime.startSlot(state,cfg,'DL',1,1,1,10,20);
state.ControlGating.PBCHRequired=false;
state.ControlGating.PRACHRequired=false;
state.ControlGating.TRSRequired=false;
state.ControlGating.SRSRequired=false;
state.Traffic.FlowDirection="BIDIR";
state.ULQueueBits(:)=0;
state.DLQueueBits(:)=80;
state.Traffic.OfferedBitsUL(5,:)=1e6;
plan=sixgr.truth.CoupledTruthRuntime.futureULPlanningView(state,5);
[plan,ue]=sixgr.truth.CoupledTruthRuntime.buildSchedulerUEStateRuntime(plan,cfg,1,'UL',1);
before=plan.ULHarq.Stats; beforeProcs=plan.ULHarq.UEProcs;
row=sixgr.truth.schedulerAdmissionEvidence(plan,cfg,ue,'UL');
assert(row.QueueBytes==0 && row.SchedulerBufferBytes==0 && ~row.HasTrafficDemand);
assert(row.ControlSlot==1 && row.ScheduledDataSlot==5 && ...
    row.SchedulingKnowledgeSlot==1 && row.TrafficKnowledgeThroughSlot==1);
assert(row.AdmissionReason=="no_queued_bytes_or_pending_retransmission");
assert(row.SRSRequired && ~row.SRSCausalUsable && ~row.ReferenceEligible);
assert(row.HARQNewDataProcessAvailable==1 && row.CandidateGrantCount==0);
assert(isequaln(before,plan.ULHarq.Stats) && isequaln(beforeProcs,plan.ULHarq.UEProcs));
assert(~contains(row.EvidenceRole,"successful"));

% Inactive UEs must survive the actual scheduling boundary (no waveform).
[scheduled,grants,info]=sixgr.truth.CoupledTruthRuntime.scheduleDirection(plan,cfg,'UL');
assert(isempty(grants) && height(info.AdmissionTable)==1 && ...
    height(scheduled.SchedulerAdmissionTable)==1);
assert(info.NoGrantReason=="no_active_eligible_users" && ...
    contains(info.NoGrantDetails,"no_queued_bytes_or_pending_retransmission"));
assert(isequaln(before,scheduled.ULHarq.Stats) && ...
    isequaln(beforeProcs,scheduled.ULHarq.UEProcs));

% Queued UL with no causal SRS is a different blocker from an empty queue.
plan.ULQueueBits(:)=800;
[queued,ue]=sixgr.truth.CoupledTruthRuntime.buildSchedulerUEStateRuntime(plan,cfg,1,'UL',1);
row=sixgr.truth.schedulerAdmissionEvidence(queued,cfg,ue,'UL');
assert(row.QueueBytes==100 && row.HasTrafficDemand && ~row.ActiveAtSchedulerInput);
assert(startsWith(row.AdmissionReason,"srs_") && ~row.SRSCausalUsable);
% Future SRS cannot make a control-time grant eligible.
plan.ReferenceSignalMeasurementTable=table("SRS","UE",1,1,4,true,"future", ...
    'VariableNames',{'SignalType','TargetType','TargetId','ProducerSlot', ...
    'AvailableSlot','Valid','MeasurementId'});
[future,ue]=sixgr.truth.CoupledTruthRuntime.buildSchedulerUEStateRuntime(plan,cfg,1,'UL',1);
row=sixgr.truth.schedulerAdmissionEvidence(future,cfg,ue,'UL');
assert(~row.SRSCausalUsable && contains(row.SRSCausalStatus,"future"));

% Disabled traffic policy is separate from actually queued/retx demand.
plan.Traffic.FlowDirection="DL"; plan.ULQueueBits(:)=0;
[~,ue]=sixgr.truth.CoupledTruthRuntime.buildSchedulerUEStateRuntime(plan,cfg,1,'UL',1);
row=sixgr.truth.schedulerAdmissionEvidence(plan,cfg,ue,'UL');
assert(row.TrafficDirectionConfigured==0 && ...
    row.AdmissionReason=="traffic_direction_not_configured_and_no_pending_demand");
plan.ULQueueBits(:)=800;
[~,ue]=sixgr.truth.CoupledTruthRuntime.buildSchedulerUEStateRuntime(plan,cfg,1,'UL',1);
row=sixgr.truth.schedulerAdmissionEvidence(plan,cfg,ue,'UL');
assert(row.HasTrafficDemand && startsWith(row.AdmissionReason,"srs_"));

% Exhaust real HARQ processes. Diagnostics must neither release nor allocate.
[state,dl]=sixgr.truth.CoupledTruthRuntime.buildSchedulerUEStateRuntime(state,cfg,1,'DL',1);
for p=1:state.DLHarq.NumProcesses
    txp=state.DLHarq.allocate(dl.RNTI,0,100,'NewData',true);
    layout=sixgr.phy.phycode.resolveCodingLayout('Direction','DL', ...
        'TransportBlockSize',800,'TargetCodeRate',0.3,'RV',0, ...
        'Modulation','QPSK','NumLayers',1,'RateMatchedBitCount',2748);
    grant=struct('TBSBits',800,'Direction','DL','Modulation','QPSK', ...
        'NumLayers',1,'TargetCodeRate',0.3,'CodingLayout',layout);
    state.DLHarq.onTx(dl.RNTI,txp.HARQ.HarqID,uint8(ones(800,1)),grant,0);
end
before=state.DLHarq.Stats; beforeProcs=state.DLHarq.UEProcs;
row=sixgr.truth.schedulerAdmissionEvidence(state,cfg,dl,'DL');
assert(row.ActiveAtSchedulerInput && row.HARQNewDataProcessAvailable==0);
assert(row.AdmissionReason=="passed_traffic_and_reference_admission");
assert(isequaln(before,state.DLHarq.Stats) && isequaln(beforeProcs,state.DLHarq.UEProcs));
% A real negative feedback event creates retransmission demand even with
% no queued new payload. Keep real QueueBytes=0 distinct from scheduler=1.
state.DLHarq.onFeedback(dl.RNTI,txp.HARQ.HarqID,false,'SourceSlot',0);
state.DLQueueBits(:)=0;
[state,dl]=sixgr.truth.CoupledTruthRuntime.buildSchedulerUEStateRuntime(state,cfg,1,'DL',1);
row=sixgr.truth.schedulerAdmissionEvidence(state,cfg,dl,'DL');
assert(row.HasPendingRetransmission && row.HasTrafficDemand && ...
    row.QueueBytes==0 && row.SchedulerBufferBytes==1 && row.ActiveAtSchedulerInput);
assert(row.HARQNewDataProcessAvailable==0);

% A configured DL SRS prerequisite must not publish 'not applicable'.
state.ControlGating.SRSRequired=true;
[state,dl]=sixgr.truth.CoupledTruthRuntime.buildSchedulerUEStateRuntime(state,cfg,1,'DL',1);
row=sixgr.truth.schedulerAdmissionEvidence(state,cfg,dl,'DL');
assert(row.SRSRequired && ~row.SRSCausalUsable && ...
    row.SRSCausalStatus~="not_applicable_for_dl_scheduler");

% The actual live production writer must retain zeros and empty reason
% columns, without converting the observed input into a successful grant.
state.SchedulerAdmissionTable=scheduled.SchedulerAdmissionTable;
probe=struct('Direction','UL','ControlAbsoluteSlot',state.CurrentSlot-1, ...
    'ControlSymbolAllocation',cfg.phy.pdcch.symbolAllocation, ...
    'SymbolAllocation',cfg.phy.pusch.symbolAllocation,'HARQProcess',0);
d=sixgr.phy.frame.TimingRelationEngine.resolveProductionGrant(cfg,probe);
[state,opportunity]=sixgr.truth.evaluateULPlanningOpportunity(state,cfg,d,struct([]),1,10);
state=sixgr.truth.CoupledTruthRuntime.writeLiveStateTables(state,out);
csv=fullfile(out,'packet_flow','csv','scheduler_admission_trace.csv');
assert(isfile(csv));
published=sixgr.util.csvReadTable(csv);
assert(height(published)==1 && published.QueueBytes==0 && published.CandidateGrantCount==0);
assert(all(ismember({'SchedulerDecisionReasons','RankAuthority','SRSRequired', ...
    'ControlSlot','ScheduledDataSlot','SweepPointIndex'},published.Properties.VariableNames)));
assert(published.ControlSlot==1 && published.ScheduledDataSlot==5);
timing=sixgr.util.csvReadTable(fullfile(out,'packet_flow','csv','ul_scheduler_timing.csv'));
candidates=sixgr.util.csvReadTable(fullfile(out,'packet_flow','csv','ul_scheduler_timing_candidates.csv'));
assert(height(timing)==1 && timing.EligibleForUEScheduling==opportunity.EligibleForUEScheduling);
assert(height(candidates)==numel(d.DataAttempts) && ...
    isequal(double(candidates.K2),reshape(double([d.DataAttempts.K2]),[],1)));

% The future-resource copy must be copied back even when it has no grants.
code=fileread(which('sixgr.truth.runWaveformLinkBundle'));
planner=fileread(which('sixgr.truth.planFutureULGrants'));
assert(isscalar(strfind(code,'sixgr.truth.planFutureULGrants(')), ...
    'The production coordinator must delegate to the extracted planner exactly once.');
admission=strfind(planner, ...
    'sixgr.util.structGet(state,"SchedulerAdmissionTable",table()),scheduleInfo.AdmissionTable)');
emptyGrant=strfind(planner,'if isempty(grants)');
assert(isscalar(admission) && ~isempty(emptyGrant) && admission<emptyGrant(1), ...
    'The extracted producer must copy admission evidence before its no-grant return.');
testSchedulerEligibilityAfterAccess;
ok=true;
fprintf('SCHEDULER_ADMISSION_EVIDENCE_PASS\n');
end
