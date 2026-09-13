function ok=testRetainedDLACKFeedbackQueue(outputRoot)
% Queue boundary test: real archived UE/DCI lineage, an advanced shared
% physical clock, and explicitly declared binding inputs. No new DL data
% or UCI waveform is claimed by this test; production callback still needs
% a started-TX ledger and actual received-control record before this call.
if nargin<1, outputRoot=tempname; end
assert(~isfolder(outputRoot),'test:EvidenceAlreadyExists','Preserve earlier evidence.');
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_causal_access_to_data_wiring_tdd_short_continuous_iq.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
% Production binds this at the runner front door; this direct component
% invocation must retain an equally explicit continuous-IQ output root.
cfg.run.rootRunFolder=fullfile(outputRoot,'physical_clock_capture');
saved=load('docs/lls/evidence_20260913/received_dl_harq/attempt_3.mat'); a=saved.a;
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,tempname,multi,struct(),a.DataAbsoluteSlot+2);
state.CurrentSlot=1; state.CurrentFrame=1; state.CurrentCanonicalSlot=1;
state.CurrentServingIdx(:)=1;
[state,owner]=sixgr.truth.CoupledWaveformStream.initialize(state,cfg,{cfg});
for slot=1:a.DataAbsoluteSlot+1
    state.CurrentSlot=slot; state.CurrentCanonicalSlot=slot;
    state.CurrentFrame=floor((slot-1)/state.SlotsPerFrame)+1;
    [state,~]=owner.advanceSlot(state,cfg);
    if mod(slot,10)==0, fprintf('RETAINED_ACK_EMPTY_CLOCK_ADVANCE slot=%d sample=%d\n',slot,owner.Events.NextSampleIndex); end
end
now=owner.Events.NextSampleIndex;
current=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,a.ControlAbsoluteSlot+1);
grant=struct('RNTI',a.RNTI,'Slot',a.DataAbsoluteSlot+1, ...
    'HARQ',struct('HarqID',a.HARQProcess,'NDI',a.NDI), ...
    'K1',a.K1Slots,'HARQFeedbackAbsoluteSlot',a.HARQFeedbackAbsoluteSlot, ...
    'PUCCHResourceIndicator',a.PUCCHResourceIndicator, ...
    'PDCCHGrantFirstCCE',0,'PDCCHGrantNumCCE',4);
control=struct('Key',"archived_control_declared_binding_fixture",'Grant',grant, ...
    'Allowed',true,'ReceivedAssignment',a,'AvailableAtSample',now);
state.SharedReceivedGrantControls={control}; state.SharedUEDLHARQEntities={saved.before};
before=state;
[state,protocol]=sixgr.truth.CoupledTruthRuntime.queueRetainedDLACKRuntime(state,current,1,control,now);
assert(height(state.PendingFeedbackTable)==1 && height(state.PUCCHGrantTraceTable)==1 && ...
    height(state.SharedDLProtocolDecisionTable)==1 && ...
    height(state.HARQTimelineTable)==height(before.HARQTimelineTable));
assert(isequaln(state.PacketDeliveryLedgerTable,before.PacketDeliveryLedgerTable) && ...
    state.DLHarq.Stats.Ack==before.DLHarq.Stats.Ack && ...
    state.DLHarq.Stats.Nack==before.DLHarq.Stats.Nack);
assert(state.PendingFeedbackTable.Ack && ~state.PendingFeedbackTable.Processed && ...
    ~state.PendingFeedbackTable.CurrentDecodeOK && ~state.PendingFeedbackTable.CombinedDecodeOK && ...
    ~state.PUCCHGrantTraceTable.GrantExecutedFlag && ...
    state.PUCCHGrantTraceTable.PRIValue==a.PUCCHResourceIndicator && ...
    state.PUCCHGrantTraceTable.ScheduledAbsoluteSlot==a.HARQFeedbackAbsoluteSlot+1);
assert(state.PUCCHGrantTraceTable.IsRetransmission && ...
    state.PUCCHGrantTraceTable.NDI==a.NDI && state.PUCCHGrantTraceTable.RV==a.RV, ...
    'Retained ACK must not be presented to link adaptation as first-transmission feedback.');
sixgr.truth.assertHARQFeedbackAvailable(state.PendingFeedbackTable,now,owner.SampleRateHz);
sixgr.truth.assertHARQFeedbackAvailable(state.PUCCHGrantTraceTable,now,owner.SampleRateHz);
localReject(@()sixgr.truth.CoupledTruthRuntime.queueRetainedDLACKRuntime( ...
    state,current,1,control,now),'sixgr:link:ReceivedDLHARQNoncausalAssignment');
localReject(@()sixgr.truth.CoupledTruthRuntime.queueRetainedDLACKRuntime( ...
    before,current,1,control,now+1),'sixgr:truth:RetainedACKSharedClockRequired');
bad=control; bad.Allowed=false;
localReject(@()sixgr.truth.CoupledTruthRuntime.queueRetainedDLACKRuntime( ...
    before,current,1,bad,now),'sixgr:truth:RetainedACKReceivedControlRequired');
bad=control; bad.Grant.K1=bad.Grant.K1+1; wrong=before; wrong.SharedReceivedGrantControls={bad};
localReject(@()sixgr.truth.CoupledTruthRuntime.queueRetainedDLACKRuntime( ...
    wrong,current,1,bad,now),'sixgr:truth:RetainedACKFeedbackAuthorityMismatch');
bad=control; bad.AvailableAtSample=0; wrong=before; wrong.SharedReceivedGrantControls={bad};
localReject(@()sixgr.truth.CoupledTruthRuntime.queueRetainedDLACKRuntime( ...
    wrong,current,1,bad,now),'sixgr:truth:RetainedACKClockSlotMismatch');
mkdir(outputRoot);
sixgr.util.csvWriteTable(fullfile(outputRoot,'protocol_decisions.csv'),struct2table(protocol),'PreserveSchema',true);
sixgr.util.csvWriteTable(fullfile(outputRoot,'pending_feedback.csv'),state.PendingFeedbackTable,'PreserveSchema',true);
sixgr.util.csvWriteTable(fullfile(outputRoot,'pucch_reservations.csv'),state.PUCCHGrantTraceTable,'PreserveSchema',true);
fprintf('RETAINED_DL_ACK_QUEUE_PASS guards=5 protocol_rows=1 new_decode_rows=0 gNB_feedback_updates=0 no_UCI_execution_claim=1 folder=%s\n',outputRoot);
ok=true;
end

function localReject(fn,id)
try, fn(); catch ME, assert(strcmp(ME.identifier,id),'Expected %s, got %s: %s',id,ME.identifier,ME.message); return; end
error('test:MissingRejection','Expected %s.',id);
end
