function [ok,result]=testSharedRejectedULReceiveOnly(withHARQ)
% Physical component: known-candidate UL DCI is actually decoded/rejected,
% then the normal receive-only reducers capture/decode without UE PUSCH.
% Two explicitly resolved endpoint fixtures: UE known-candidate control and
% gNB installed connected-UL schema. Not acquired/blind or full coordinator.
setup6GRSimToolkit('Verbose',false);
if nargin<1, withHARQ=false; end
root=fileparts(fileparts(mfilename('fullpath')));
output=tempname(fullfile(root,'logs')); mkdir(output);
folder=fullfile(root,'simulator','configs','scenarios');
fixture='lls_rejected_ul_receive_only_fixture.yaml';
if withHARQ, fixture='lls_rejected_ul_due_harq_fixture.yaml'; end
s=sixgr.lls6g.config.loadScenarioConfig(fullfile(folder,fixture));
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
state.TestWithHARQ=withHARQ; state.TestEvidenceRoot=output;
if withHARQ
    % Explicit connected-clock component input, not simulated random access.
    carrier=sixgr.phy.grid.makeCarrier(cfg); fs=owner.SampleRateHz;
    reference=struct('Source',"received_SSB_timing_and_decoded_BCH", ...
        'NCellID',carrier.NCellID,'SampleRateHz',fs,'DLPhaseOffsetSamples',6,'AvailableAtSample',0);
    common=struct('Source',"decoded_sib1",'TimingAdvanceOffsetPresent',false,'TimingAdvanceOffset',"");
    state.ConnectedULTimingByUE={struct('DLReference',reference, ...
        'Offset',sixgr.phy.frame.resolveULTimingAdvanceOffset(common,'FR1'), ...
        'ReceivedRARTiming',sixgr.phy.ra.resolveRARTimingAdvance(0,carrier.SubcarrierSpacing,fs), ...
        'TimingAdvanceAvailableAtSample',0,'TimingAdvanceEffectiveAtSample',0, ...
        'TimeAlignmentExpirySampleExclusive',round(.02*fs))};
    state.UECommonCellConfigurationByUE={decodedSSBPowerCodecFixture(cfg,0,1,1)};
    state.UECommonCellConfigurationByUE{1}.InitialULBWP.SubcarrierSpacing_kHz=carrier.SubcarrierSpacing;
    [state,dlLedger]=queueDL(state,cfg);
    % The retained allocation is a declared component input, not a current
    % SRS measurement. Rebuild the control context BEFORE TX under the new
    % installed K1 list, preserving the declared frozen UL physical allocation.
    old=sixgr.phy.pdcch.decodeDCIPayload(grant.DCI.Bits,'0_1',grant.DCI.ContextData);
    [rank,tpmi]=sixgr.phy.pdcch.ULPrecodingField.decode(grant.DCI.ContextData, ...
        old.Fields.precoding_information_and_number_of_layers);
    assert(rank==grant.NumLayers && tpmi==grant.PHYGrant.PrecodingState.TPMI);
    grant.TPMI=tpmi;
    scheduler=sixgr.l2.mac.SchedulerPF(cfg,'Direction','UL');
    grant.DCI=scheduler.buildDCIBitfield(grant);
    grant=sixgr.truth.prepareScheduledULDAI(dlLedger,cfg,grant);
    assert(grant.ULTotalDAIAuthority.ScheduledDLAssignmentCount==1);
end
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
    ~result.OraclePayloadBitsUsed && result.HARQStateCommitted==withHARQ && ~result.TransmittedTBScored && ...
    numel(owner.DataTransmissions)==double(withHARQ) && state.ULHarq.Stats.Tx==0 && state.DLHarq.Stats.Tx==double(withHARQ) && ...
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
    ~roundtrip.TransmittedTBScored && ~roundtrip.UETransmissionExecuted && roundtrip.HARQStateCommitted==withHARQ);
if withHARQ
    assert(height(state.SharedGNBUCIHARQTable)==1 && state.SharedGNBUCIHARQTable.UCITransport=="PUSCH" && ...
        state.SharedGNBUCIHARQTable.HARQFeedbackApplied && isempty(state.ControlTrials.PUCCH) && ...
        numel(state.SharedUnselectedPUCCHObservations)==1 && isempty(owner.ControlObservationDispositions));
    d=state.SharedGNBUCIHARQTable;
    assert(d.TBSBits==state.SharedDataTXLedger{1}.Grant.TBSBits && ...
        d.AvailableAtSample==result.ReceiverInvokedAtSample && ...
        d.ObservationStartSample==result.Observation.StartSample && ...
        d.ObservationEndSampleExclusive==result.Observation.EndSampleExclusive);
    actual=result.IndependentHARQObservation;
    normalized=struct('MappingDigest',result.HARQMapping.Digest,'UEIndex',1,'RNTI',grant.RNTI, ...
        'TargetSlot',double(grant.Slot),'DecodedBits',actual.DecodedBits,'DecodeOk',actual.DecodeOk, ...
        'DTXFlag',actual.DTXFlag,'Transport',"PUSCH");
    reject(@()sixgr.truth.CoupledTruthRuntime.commitScheduledHARQFeedbackRuntime( ...
        state,cfg,1,double(grant.Slot),normalized,result.Observation,result.Binding.ObservationID,grant), ...
        'sixgr:truth:DuplicateScheduledHARQFeedback');
    normalized.Transport="PUCCH"; normalized.MappingDigest=result.HARQMapping.BaseMapping.Digest;
    reject(@()sixgr.truth.CoupledTruthRuntime.commitScheduledHARQFeedbackRuntime( ...
        state,cfg,1,double(grant.Slot),normalized,result.Observation,"duplicate-other-transport"), ...
        'sixgr:truth:DuplicateScheduledHARQFeedback');
    stats=state.DLHarq.Stats; outcome=string(d.FeedbackOutcome);
    assert(stats.Ack==double(outcome=="ACK") && stats.Nack==double(outcome=="NACK") && stats.Dtx==double(outcome=="DTX"));
    writetable(d,fullfile(output,'independent_pusch_harq_feedback.csv'));
    decisions=state.SharedPUSCHHARQDecisionAuditTable;
    assert(height(decisions)==1 && decisions.ObservationID==result.UCIReceiveContext.Data.ObservationID && ...
        decisions.ReceiverUsable==actual.DecodeOk && decisions.ReceiverErasure==actual.DTXFlag && ...
        decisions.AvailableAtSample==result.ReceiverInvokedAtSample);
    sixgr.util.csvWriteTable(fullfile(output,'pusch_harq_receiver_decisions.csv'),decisions, ...
        'PreserveSchema',true,'RoundTripNumericText',true);
    unselected=state.SharedUnselectedPUCCHObservations;
    save(fullfile(output,'unselected_pucch_observation.mat'),'unselected','-v7.3');
end
resolvedScenario=s.Data; resolvedControlScenario=controlScenario.Data; runtimeVersion=version;
controlReceiver=state.TestControlReceiver; controlInfo=state.TestControlInfo;
controlObservation=state.SharedReceivedGrantControls{1}.RejectedControlObservation;
gnbControlEvidence=state.TestGNBControls;
save(fullfile(output,'rejected_ul_receive_only.mat'),'result','audit','controlReceiver','controlInfo', ...
    'controlObservation','gnbControlEvidence','cfg','controlCfg','resolvedScenario','resolvedControlScenario','runtimeVersion','-v7.3');
fprintf('SHARED_REJECTED_UL_RECEIVE_ONLY_PASS physical_control_rejections=1 gNB_receive_only=1 UE_UL_TX=0 DL_HARQ_commits=%d root=%s\n',withHARQ,output);
ok=true;
end

function state=receive(state,items)
for item=items
    if item.Kind=="DataTX"
        state=sixgr.truth.commitSharedDataTransmission(state,item);
        state=sixgr.truth.CoupledTruthRuntime.armSharedDLHARQOccasionFromGrantRuntime(state,state.SharedDataTXLedger{end}.Grant,item.UE);
        continue;
    elseif item.Kind=="PDSCH"
        % Deliberately unexecuted UE decoder: no fabricated received event.
        save(fullfile(state.TestEvidenceRoot,'unconsumed_ue_pdsch.mat'),'item','-v7.3');
        continue;
    elseif item.Kind=="PreparePUCCH"
        assert(isempty(state.PendingFeedbackTable) && isempty(state.PUCCHGrantTraceTable));
        state=sixgr.truth.CoupledTruthRuntime.prepareSharedPUCCHFeedbackRuntime(state,item);
        assert(state.SharedWaveformStream.hasPending('PUCCHNotSelected',item.UE));
        continue;
    elseif item.Kind=="PUCCHNotSelected"
        state=sixgr.truth.completeUnselectedPUCCHObservation(state,item);
        continue;
    end
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
    if ~state.TestWithHARQ
        assert(timing.UnboundedEstimate_samples>window(2), ...
            'test:TimingRegressionNotExercised','The original retained stimulus must reproduce its out-of-window noise peak.');
    end
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
    actual=state.SharedWaveformStream.DataTransmissions;
    assert(numel(actual)==double(state.TestWithHARQ) && all(arrayfun(@(x)x.Identity.Direction=="DL",actual)));
    state.TestControlReceiver=rx; state.TestControlInfo=info;
    state.TestGNBControls=scheduled;
end
end

function [state,ledger]=queueDL(state,cfg)
% Physical slot-6 DL; installed K1=4 points to the ordinary slot-10 UL grant.
owner=state.SharedWaveformStream;
[dl,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'DL');
dl=sixgr.phy.grid.applyRuntimeCarrierTimeline(dl,6);
dl=sixgr.truth.bindSharedDataOccasion(dl,6,1,owner.SampleRateHz);
g=sixgr.link.resolveWaveformGrant(dl,'DL',1,'Slot',6,'SFN',0,'ControlAbsoluteSlot',5);
allocated=state.DLHarq.allocate(g.RNTI,6,g.TBSBytes,'NewData',true);
g=sixgr.link.resolveWaveformGrant(dl,'DL',1,'Slot',6,'SFN',0,'ControlAbsoluteSlot',5,'HARQProcess',allocated.HARQ.HarqID);
g.ServingCell=double(dl.lls6g.userContext.RuntimeServingCell);
scheduler=sixgr.l2.mac.SchedulerPF(dl,'Direction','DL');
g=scheduler.attachPUCCHResourceAuthorityToGrant(g); g.DCI=scheduler.buildDCIBitfield(g);
g.PHYGrant=sixgr.phy.grant.freezePHYGrant(dl,'DL',g,'Slot',g.Slot,'Frame',g.Frame,'HARQContext',g.HARQ);
g.PHYGrantContextId=char(string(g.PHYGrant.GrantContextId));
[g,ledger]=sixgr.truth.prepareScheduledDLDAI(struct(),dl,g);
assert(g.TimingDecision.FeedbackAbsoluteSlot==9 && allocated.HARQ.NDI==g.HARQ.NDI);
job=sixgr.truth.buildGrantPHYJob(dl,'DL',cfg.channel.snr_dB,1,[], ...
    struct('GrantSnapshot',g,'PHYGrant',g.PHYGrant,'PrepareOnly',true));
job.StartSlotIndex=6;
prepared=sixgr.truth.executeGrantPHYJob(job);
owner.queueData(1,prepared.Result.PreparedTransmission,struct('Purpose',"unreceived_UE_control_component"));
state.DLQueueBits(1)=state.DLQueueBits(1)+g.TBSBits;
end

function reject(fn,id)
try, fn(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s; got %s: %s',id,cause.identifier,cause.message); return;
end
error('test:MissingRejection','Expected %s.',id);
end
