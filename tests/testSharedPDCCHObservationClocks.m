function ok=testSharedPDCCHObservationClocks()
% Analytical received-clock capsule, actual queued control IQ/physical owner.
% This checks capture clocks, not successful SSB acquisition or DCI decode.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios','lls_pdcch_shared_queue_fixture.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,tempname,multi,struct(),2);
state.CurrentSlot=1; state.CurrentServingIdx(:)=1;
[state,owner]=sixgr.truth.CoupledWaveformStream.initialize(state,cfg,{cfg});
[dl,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'DL');
dl=sixgr.phy.grid.applyRuntimeCarrierTimeline(dl,2);
carrier=sixgr.phy.grid.makeCarrier(dl);
first=sixgr.phy.frame.slotStartSample(carrier,1,owner.SampleRateHz);
dl=sixgr.util.structSet(dl,'lls6g.userContext.RuntimeSlotStartTime_s',first/owner.SampleRateHz);
bits=int8(mod((0:dl.phy.pdcch.configuredPayloadBits-1).',2));
p=sixgr.link.prepareSharedPDCCHTransmission(dl,'DCIBits',bits,'RNTI',1);
ch=owner.directionalChannelState(1,'DL');
reference=struct('Source',"received_SSB_timing_and_decoded_BCH", ...
    'SampleRateHz',owner.SampleRateHz,'AvailableAtSample',0, ...
    'DLPhaseOffsetSamples',17,'NCellID',carrier.NCellID, ...
    'ImplementationFilterDelay_samples',ch.ChannelTrimSamples,'SearchGuardSamples',32);
owner.queuePDCCH(1,p,struct('ReceivedDLTimingReference',reference, ...
    'Purpose',"analytical_clock_capture_test_not_acquisition"));
[state,~]=owner.advanceSlot(state,cfg,@localReceive);
state.CurrentSlot=2;
[state,~]=owner.advanceSlot(state,cfg,@localReceive);
assert(state.TestSeparatedPDCCHClocks && ~owner.hasPending('PDCCH',1));
ok=true; disp('SHARED_PDCCH_OBSERVATION_CLOCKS_PASS');
end

function state=localReceive(state,items)
for item=items
    p=item.Context.Prepared;
    [post,~,tx]=sixgr.truth.sharedObservationEvidence(item.Planes,p);
    assert(tx.StartSample==p.RuntimeStartSample && post.StartSample==p.ReceivedTimingAlignment.ReceiveStartSample);
    assert(post.StartSample~=tx.StartSample && ...
        tx.EndSampleExclusive==p.RuntimeStartSample+p.MinimumReceiveSamples);
    assert(tx.isComplete() && post.isComplete());
    state.TestSeparatedPDCCHClocks=true;
end
end
