function ok=testConfiguredCSIReceivedClock()
% Actual shared SRS and independently scheduled PUCCH, not injected timing.
for mode=["present","remove_after_tx","absent"]
    [passed,state]=testSharedPeriodicCSIProducer(mode,true);
    assert(passed);
    if mode=="present", checkPriorEligibility(state); end
end
fprintf('CONFIGURED_CSI_RECEIVED_CLOCK_PASS producer_modes=3 injected_timing=0\n');
ok=true;
end

function checkPriorEligibility(state)
item=state.TestReceivedPUCCHItem; c=item.Context; h=c.GNBReception;
id="gnb_"+h.ServingCell+"_rx";
plane=item.Planes(string({item.Planes.ReceiverID})==id+":post_rf");
observation=sixgr.phy.rx.compensateReceivedAGC(plane.Observation,plane.Segments,id);
prior=state.ReceivedULTimingReferences{item.UE};
without=sixgr.link.receivePUCCHObservation(c.Config,h.Assignment,h.Context,observation);
assert(~without.ReceiveTiming.PriorClockProvided && ~without.ReceiveTiming.PriorClockApplied);
for reason=["StaleULTimingReference","ULTimingReferenceIdentityMismatch"]
    cfg=c.Config;
    if reason=="StaleULTimingReference"
        cfg.phy.synchronization.maxReceivedULTimingAgeSlots=3; % Actual prior age is four slots.
    else
        cfg.phy.frame.DefaultIdentity.ULBWPID=cfg.phy.frame.DefaultIdentity.ULBWPID+1;
    end
    rx=sixgr.link.receivePUCCHObservation(cfg,h.Assignment,h.Context,observation,prior);
    assert(rx.ReceiveTiming.PriorClockProvided && ~rx.ReceiveTiming.PriorClockApplied && ...
        rx.ReceiveTiming.PriorClockRejectionReason=="sixgr:phy:sync:"+reason);
    assert(rx.ReceiveTiming.TimingSource=="received_reference_correlation_bounded_search" && ...
        ~rx.ReceiveTiming.OracleTimingUsed && ~rx.ReceiveTiming.ReceiverZeroPaddingUsed);
    for field=["DecodedSequence1","DecodedSequence2","GridNoiseVariance","DetectionMetric","DTX"]
        assert(isequaln(rx.(field),without.(field)), ...
            'test:RejectedClockChangedReceiver','An inapplicable clock must not alter received-pilot acquisition.');
    end
end
badPrior=false;
try, sixgr.link.receivePUCCHObservation(c.Config,h.Assignment,h.Context,observation,struct());
catch cause
    assert(strcmp(cause.identifier,'sixgr:link:InvalidPUCCHTimingPrior')); badPrior=true;
end
assert(badPrior,'Malformed priors must not be treated as absent clocks.');
badConfig=c.Config; badConfig.phy.synchronization.maxReceivedULTimingAgeSlots=NaN;
rejected=false;
try, sixgr.link.receivePUCCHObservation(badConfig,h.Assignment,h.Context,observation,prior);
catch, rejected=true;
end
assert(rejected,'Malformed freshness configuration must not trigger another receiver path.');
% Keep actual captured samples, but omit the tail needed by the positive
% received-clock offset. The DM-RS receiver may process only what remains.
raw=observation.readComplete();
count=state.SharedGNBUCIReceptions{1}.Receiver.ReceiveTiming.DemodulatedSampleCount;
short=sixgr.phy.waveform.WaveformObservationBuffer(observation.StartSample, ...
    observation.StartSample+count,observation.SampleRateHz,size(raw,2));
short.append(sixgr.phy.waveform.WaveformChunk(raw(1:count,:),short.StartSample),short.SampleRateHz);
rx=sixgr.link.receivePUCCHObservation(c.Config,h.Assignment,h.Context,short,prior);
assert(~rx.ReceiveTiming.PriorClockApplied && ...
    rx.ReceiveTiming.PriorClockRejectionReason=="sixgr:phy:sync:IncompletePriorAlignedULObservation" && ...
    ~rx.ReceiveTiming.ReceiverZeroPaddingUsed && rx.ReceiveTiming.DemodulatedSampleCount==count);
fprintf('PUCCH_CLOCK_ELIGIBILITY_PASS no_prior_stale_BWP_malformed_short_capture=6 oracle=0 padding=0\n');
end
