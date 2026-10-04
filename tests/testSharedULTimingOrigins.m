function ok=testSharedULTimingOrigins()
% Analytic physical-clock contract, independent from waveform decoding tests.
for mode=["TDD","FDD"]
    cfg=struct('phy',struct('duplex',struct('mode',mode), ...
        'synchronization',struct('maxTimingUncertaintySamples',32)));
    reference=struct('Source',"received_SSB_timing_and_decoded_BCH", ...
        'SampleRateHz',7.68e6,'DLPhaseOffsetSamples',7,'AvailableAtSample',1000);
    common=struct('Source',"decoded_sib1",'TimingAdvanceOffsetPresent',false,'TimingAdvanceOffset',"");
    offset=sixgr.phy.frame.resolveULTimingAdvanceOffset(common,'FR1');
    cfg.SharedULTimingContext=struct('DLReference',reference,'Offset',offset);
    for nta=[0 3072 6144]
        t=sixgr.phy.ra.sharedULStageTiming(cfg,.02,7.68e6,7680,nta);
        assert(t.TransmitStartSample==153600+7-100-nta/256);
        assert(t.TransmitEndSampleExclusive-t.TransmitStartSample==7680 && ~t.FiniteWaveformCropped);
        assert(t.ReceiveStartSample==153600-100-32 && t.ReceiveEndWithoutChannelTail==153600-100+7680+32);
        assert(t.WaveformTimingApplied && t.NTAOffset_Tc==25600);
    end
    changed=cfg; changed.SharedULTimingContext.DLReference.DLPhaseOffsetSamples=19;
    a=sixgr.phy.ra.sharedULStageTiming(cfg,.02,7.68e6,7680,3072);
    b=sixgr.phy.ra.sharedULStageTiming(changed,.02,7.68e6,7680,3072);
    assert(b.TransmitStartSample-a.TransmitStartSample==12 && b.ReceiveStartSample==a.ReceiveStartSample, ...
        'A gNB observation window must not track an oracle UE transmit phase.');
    localReject(@()sixgr.phy.ra.sharedULStageTiming(cfg,.02,7.68e6,7680,1), ...
        'sixgr:phy:ra:SharedULOriginOffSampleClock');
    % Full-slot Msg4 reception ends at the next nominal slot boundary.
    % The common UL advance must not move its dependent SRB1 transmission
    % before those control samples exist (the retained failure was 100 samples).
    dependent=cfg;
    dependent.SharedULTimingContext.DLReference.DLPhaseOffsetSamples=0;
    dependent.SharedULTimingContext.ControlAvailableAtTicks=int64(153600)*int64(256);
    dependent.SharedULTimingContext.ControlAvailabilitySource="received_RRCSetup_observation_completion";
    localReject(@()sixgr.phy.ra.sharedULStageTiming(dependent,.02,7.68e6,7680,0), ...
        'sixgr:phy:ra:ULBeforeControlAvailability');
    causal=sixgr.phy.ra.sharedULStageTiming(dependent,.021,7.68e6,7680,0);
    assert(causal.TransmitStartSample==161180 && ...
        causal.ControlAvailableAtTicks==dependent.SharedULTimingContext.ControlAvailableAtTicks);
end
ok=true; disp('SHARED_UL_TIMING_ORIGINS_PASS: distinct TX/RX clocks, received offset/TA, no cropped samples.');
end
function localReject(fn,id)
try, fn(); catch cause, assert(strcmp(cause.identifier,id),cause.message); return; end
error('test:ExpectedFailure','Expected %s.',id);
end
