function ok=testSharedRejectedULReceiveOnly()
% Physical component: known-candidate UL DCI is actually decoded/rejected,
% then the normal receive-only reducers capture/decode without UE PUSCH.
% Two explicitly resolved endpoint fixtures: UE known-candidate control and
% gNB installed connected-UL schema. Not acquired/blind or full coordinator.
setup6GRSimToolkit('Verbose',false);
root=fileparts(fileparts(mfilename('fullpath')));
output=tempname(fullfile(root,'logs')); mkdir(output);
folder=fullfile(root,'simulator','configs','scenarios');
s=sixgr.lls6g.config.loadScenarioConfig(fullfile(folder,'lls_rejected_ul_receive_only_fixture.yaml'));
controlScenario=sixgr.lls6g.config.loadScenarioConfig(fullfile(folder,'lls_rejected_ul_control_fixture.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(s,output);
controlCfg=sixgr.lls6g.buildInternalConfig(controlScenario,output);
assert(cfg.channel.snr_dB==controlCfg.channel.snr_dB && ~controlCfg.phy.pdcch.blindSearch);
saved=load(fullfile(root,'docs','lls','evidence_20260913','scheduled_ul_dai_03','scheduled_ul_dai_0.mat'),'fixed');
grant=saved.fixed;
prior=rng; cleanup=onCleanup(@()rng(prior));
rng(double(cfg.run.seed),'twister');
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,output,multi,struct(),grant.Slot+1);
state.CurrentSlot=1; state.CurrentServingIdx(:)=1;
[state,owner]=sixgr.truth.CoupledWaveformStream.initialize(state,cfg,{cfg});
[dl,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(controlCfg,state,grant.UEIndex,'DL');
controlSlot=double(grant.TimingDecision.ControlAbsoluteSlot)+1;
dl=sixgr.phy.grid.applyRuntimeCarrierTimeline(dl,controlSlot);
carrier=sixgr.phy.grid.makeCarrier(dl);
dl.lls6g.userContext.RuntimeSlotStartTime_s= ...
    sixgr.phy.frame.slotStartSample(carrier,controlSlot-1,owner.SampleRateHz)/owner.SampleRateHz;
% Actual scheduled bits, not an invented failure flag. Known-candidate
% metadata is explicitly a component input, never connected receiver proof.
p=sixgr.link.prepareSharedPDCCHTransmission(dl,'DCIBits',grant.DCI.Bits, ...
    'RNTI',grant.RNTI,'K',numel(grant.DCI.Bits));
owner.queuePDCCH(grant.UEIndex,p,struct('Grant',grant,'GNBConfig',cfg));
reject(@()owner.readTransmittedULControls(grant.UEIndex,double(grant.Slot)), ...
    'sixgr:truth:ScheduledULControlNotTransmitted');
for slot=1:double(grant.Slot)+1
    state.CurrentSlot=slot;
    [state,~]=owner.advanceSlot(state,cfg,@receive);
end
assert(isfield(state,'SharedRejectedULReceiveResults') && isscalar(state.SharedRejectedULReceiveResults));
result=state.SharedRejectedULReceiveResults{1};
assert(~state.TestControlReceiver.CausalGrantDecodeOk && ~result.PreparedTransmitterConsumed && ...
    ~result.OraclePayloadBitsUsed && ~result.HARQStateCommitted && ~result.TransmittedTBScored && ...
    isempty(owner.DataTransmissions) && state.ULHarq.Stats.Tx==0 && state.DLHarq.Stats.Tx==0 && ...
    isempty(state.PendingFeedbackTable) && ~owner.hasPending('PUSCHReceiveOnly',1));
reject(@()sixgr.truth.completeSharedPUSCHAfterRejectedControl(state,result.ObservationID), ...
    'sixgr:truth:DuplicateRejectedULReceiveCompletion');
audit=state.SharedRejectedULReceiveAuditTable;
csv=fullfile(output,'rejected_ul_receive_only_audit.csv');
sixgr.util.csvWriteTable(csv,audit,'PreserveSchema',true);
roundtrip=sixgr.util.csvReadTable(csv,'TextType','string');
assert(height(roundtrip)==1 && roundtrip.ObservationID==audit.ObservationID && ...
    roundtrip.ObservationEndSampleExclusive==audit.ObservationEndSampleExclusive && ...
    roundtrip.AvailableAtSample>=roundtrip.ObservationEndSampleExclusive && ...
    ~roundtrip.TransmittedTBScored && ~roundtrip.UETransmissionExecuted && ~roundtrip.HARQStateCommitted);
resolvedScenario=s.Data; resolvedControlScenario=controlScenario.Data; runtimeVersion=version;
controlReceiver=state.TestControlReceiver; controlInfo=state.TestControlInfo;
controlObservation=state.SharedReceivedGrantControls{1}.RejectedControlObservation;
gnbControlEvidence=state.TestGNBControls;
save(fullfile(output,'rejected_ul_receive_only.mat'),'result','audit','controlReceiver','controlInfo', ...
    'controlObservation','gnbControlEvidence','cfg','controlCfg','resolvedScenario','resolvedControlScenario','runtimeVersion','-v7.3');
fprintf('SHARED_REJECTED_UL_RECEIVE_ONLY_PASS physical_control_rejections=1 gNB_receive_only=1 UE_TX=0 HARQ_commits=0 root=%s\n',output);
ok=true;
end

function state=receive(state,items)
for item=items
    if item.Kind=="PUSCHReceiveOnly"
        state=sixgr.truth.completeSharedPUSCHAfterRejectedControl(state,item.Context.ObservationID);
        continue;
    end
    assert(item.Kind=="PDCCH");
    p=item.Context.Prepared;
    grant=item.Context.Grant;
    scheduled=state.SharedWaveformStream.readTransmittedULControls(item.UE,double(grant.Slot));
    assert(isscalar(scheduled) && isequaln(scheduled{1}.Binding.Grant,grant) && ...
        scheduled{1}.AvailableAtSample<=state.SharedWaveformStream.Events.NextSampleIndex && ...
        scheduled{1}.TransmitObservation.isComplete());
    reject(@()sixgr.truth.assertNoScheduledPUSCHOverlap(state,item.Context.GNBConfig,item.UE, ...
        double(grant.Slot),grant.SymbolAllocation), ...
        'sixgr:truth:UnresolvedScheduledPUSCHReceiveHypothesis');
    [post,~,~,~,receiver]=sixgr.truth.sharedObservationEvidence(item.Planes,p);
    [rx,info]=sixgr.link.completePDCCHReception(p,receiver);
    timing=info.TimingEstimate;
    window=timing.SearchWindowSamples;
    [~,peak]=max(timing.SearchMetric);
    assert(isequal(window,[0 receiver.EndSampleExclusive-receiver.StartSample-p.MinimumReceiveSamples]) && ...
        timing.AppliedCorrection_samples==window(1)+peak-1 && ~info.ReceivePaddingApplied, ...
        'The selected offset must maximize actual correlation inside the complete-symbol window, without padding.');
    assert(timing.UnboundedEstimate_samples>window(2), ...
        'test:TimingRegressionNotExercised','This retained stimulus must reproduce the original out-of-window noise peak.');
    reject(@()sixgr.phy.dl.PDCCH_Rx(receiver.readComplete(),p.ReceiverConfig, ...
        'Carrier',p.Tx.Carrier,'PDCCH',p.Tx.PDCCH,'K',numel(p.Tx.DCIBits), ...
        'TimingSearchWindowSamples',[0 window(2)+1]), ...
        'sixgr:phy:pdcch:InvalidReceivedTimingSearch');
    assert(~rx.CausalGrantDecodeOk && ~rx.Ok, ...
        'test:NegativeControlStimulusNotRejected','Retain actual control rejection; never manufacture it to finish the test.');
    raw=struct('Crash',false,'DecodeAttempted',true,'PDCCHCausalGrantDecodeOk',logical(rx.CausalGrantDecodeOk), ...
        'PDCCHObservationStartSample',info.ObservationStartSample, ...
        'PDCCHObservationEndSampleExclusive',info.ObservationEndSampleExclusive);
    control=struct('Key',"actual_component_ul_command",'Allowed',logical(rx.CausalGrantDecodeOk), ...
        'Grant',item.Context.Grant,'ReceiverTrial',raw,'RejectedControlObservation',post, ...
        'AvailableAtSample',post.EndSampleExclusive,'ReceivedAssignment',struct());
    state.SharedReceivedGrantControls={control};
    assert(isequaln(scheduled,state.SharedWaveformStream.readTransmittedULControls(item.UE,double(grant.Slot))), ...
        'Actual UE rejection must not erase the gNB transmitted UL-command hypothesis.');
    % Explicit negative mutations must fail before any observation is armed.
    bad=control; bad.AvailableAtSample=bad.AvailableAtSample+1;
    broken=state; broken.SharedReceivedGrantControls={bad};
    reject(@()sixgr.truth.queueSharedPUSCHAfterRejectedControl(broken,item.Context.GNBConfig,bad), ...
        'sixgr:truth:InvalidSharedULRejectedControlClock');
    bad=control; bad.ReceivedAssignment=struct('InjectedAllocation',true);
    broken=state; broken.SharedReceivedGrantControls={bad};
    reject(@()sixgr.truth.queueSharedPUSCHAfterRejectedControl(broken,item.Context.GNBConfig,bad), ...
        'sixgr:truth:RejectedULHasReceivedAssignment');
    assert(isempty(state.SharedWaveformStream.PUSCHReceiveOnlyRegistrations));
    bad=control; bad.Grant.TBSBits=bad.Grant.TBSBits+8;
    broken=state; broken.SharedReceivedGrantControls={bad};
    reject(@()sixgr.truth.queueSharedPUSCHAfterRejectedControl(broken,item.Context.GNBConfig,bad), ...
        'sixgr:truth:RejectedULScheduledGrantMismatch');
    [state,~]=sixgr.truth.queueSharedPUSCHAfterRejectedControl(state,item.Context.GNBConfig,control);
    reject(@()sixgr.truth.queueSharedPUSCHAfterRejectedControl(state,item.Context.GNBConfig,control), ...
        'sixgr:truth:DuplicateRejectedULReceiveWindow');
    assert(isempty(state.SharedWaveformStream.DataTransmissions));
    state.TestControlReceiver=rx; state.TestControlInfo=info;
    state.TestGNBControls=scheduled;
end
end

function reject(fn,id)
try, fn(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s; got %s: %s',id,cause.identifier,cause.message); return;
end
error('test:MissingRejection','Expected %s.',id);
end
