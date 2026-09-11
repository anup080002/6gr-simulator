function ok=testConnectedULTransmissionTiming()
% Analytic initial-TAG boundary fixtures, NOT received waveform qualification.
% No run profile, channel, RF object, transmitter or receiver is executed.
for mode=["TDD","FDD"]
    for fs=[7.68e6 15.36e6 30.72e6]
        for scs=[15 30]
            for command=[0 3]
                cfg=localFixture(mode,fs,scs,command);
                count=round(fs*.001); nominal=.02;
                t=sixgr.link.resolveConnectedULTransmissionTiming(cfg,nominal,fs,count);
                tickRate=double(sixgr.phy.frame.AbsoluteTime.TicksPerSecond);
                nta=command*1024/(scs/15);
                offset=double(cfg.SharedULTimingContext.Offset.NTAOffset_Tc);
                expected=round(nominal*fs)+6-(nta+offset)*fs/tickRate;
                assert(t.TransmitStartSample==expected && t.TotalAdvanceTicks==int64(nta+offset));
                assert(t.TransmitEndSampleExclusive-t.TransmitStartSample==count && ...
                    t.OriginsResolved && ~t.WaveformTimingApplied && ~t.FiniteWaveformCropped);
                assert(t.ReceiveStartSample==round(nominal*fs)-offset*fs/tickRate-32);
                changed=cfg; changed.SharedULTimingContext.DLReference.DLPhaseOffsetSamples=9;
                shifted=sixgr.link.resolveConnectedULTransmissionTiming(changed,nominal,fs,count);
                assert(shifted.TransmitStartSample==t.TransmitStartSample+3 && ...
                    shifted.ReceiveStartSample==t.ReceiveStartSample);
                changed=cfg; changed.SharedULTimingContext.TimeAlignmentExpirySampleExclusive=t.TransmitEndSampleExclusive;
                exact=sixgr.link.resolveConnectedULTransmissionTiming(changed,nominal,fs,count);
                assert(exact.TransmitEndSampleExclusive==exact.TimeAlignmentExpirySampleExclusive);
                changed.SharedULTimingContext.TimeAlignmentExpirySampleExclusive=t.TransmitEndSampleExclusive-1;
                localReject(@()sixgr.link.resolveConnectedULTransmissionTiming(changed,nominal,fs,count), ...
                    'sixgr:link:ConnectedULAfterTAExpiry');
                changed=cfg; changed.SharedULTimingContext.TimingAdvanceAvailableAtSample=t.TransmitStartSample+1;
                changed.SharedULTimingContext.TimingAdvanceEffectiveAtSample=t.TransmitStartSample+1;
                localReject(@()sixgr.link.resolveConnectedULTransmissionTiming(changed,nominal,fs,count), ...
                    'sixgr:link:ConnectedULBeforeReceivedTA');
                changed=cfg; changed.SharedULTimingContext.TimingAdvanceEffectiveAtSample=t.TransmitStartSample+1;
                localReject(@()sixgr.link.resolveConnectedULTransmissionTiming(changed,nominal,fs,count), ...
                    'sixgr:link:ConnectedULBeforeTAApplication');
                changed=cfg; changed.SharedULTimingContext.ReceivedRARTiming.Samples=taintedSamples(cfg);
                localReject(@()sixgr.link.resolveConnectedULTransmissionTiming(changed,nominal,fs,count), ...
                    'sixgr:link:ConnectedULTimingAuthorityMismatch');
                changed=cfg; changed.SharedULTimingContext.Offset.NTAOffset_Tc=int64(0);
                localReject(@()sixgr.link.resolveConnectedULTransmissionTiming(changed,nominal,fs,count), ...
                    'sixgr:link:ConnectedULOffsetAuthorityMismatch');
            end
        end
    end
end
% Received optional IE changes are not inferred from duplex mode. FR2 uses
% its normative range rule, with a sample clock that represents that offset.
for mode=["TDD","FDD"]
    for ie=["n0","n25600","n39936"]
        cfg=localFixture(mode,7.68e6,15,3);
        common=struct('Source',"decoded_sib1",'TimingAdvanceOffsetPresent',true,'TimingAdvanceOffset',ie);
        cfg.SharedULTimingContext.Offset=sixgr.phy.frame.resolveULTimingAdvanceOffset(common,'FR1');
        t=sixgr.link.resolveConnectedULTransmissionTiming(cfg,.02,7.68e6,7680);
        expectedTicks=int64(3*1024)+cfg.SharedULTimingContext.Offset.NTAOffset_Tc;
        assert(t.TotalAdvanceTicks==expectedTicks && ...
            t.TransmitStartSample==153600+6-double(expectedTicks)/256);
    end
end
cfg=localFixture("TDD",245.76e6,120,3);
common=struct('Source',"decoded_sib1",'TimingAdvanceOffsetPresent',false,'TimingAdvanceOffset',"");
cfg.SharedULTimingContext.Offset=sixgr.phy.frame.resolveULTimingAdvanceOffset(common,'FR2-1');
t=sixgr.link.resolveConnectedULTransmissionTiming(cfg,.02,245.76e6,30720);
assert(t.TotalAdvanceTicks==int64(13792+3*128));
offClock=localFixture("TDD",7.68e6,15,0);
offClock.SharedULTimingContext.Offset=sixgr.phy.frame.resolveULTimingAdvanceOffset(common,'FR2-1');
localReject(@()sixgr.link.resolveConnectedULTransmissionTiming(offClock,.02,7.68e6,7680), ...
    'sixgr:phy:ra:SharedULOriginOffSampleClock');
missing=rmfield(cfg,'SharedULTimingContext');
localReject(@()sixgr.link.resolveConnectedULTransmissionTiming(missing,.02,245.76e6,30720), ...
    'sixgr:link:MissingConnectedULTiming');
ok=true;
disp('CONNECTED_UL_TRANSMISSION_TIMING_PASS: analytic TAG authority only; no main-run claim.');
end

function cfg=localFixture(mode,fs,scs,command)
cfg=struct('phy',struct('duplex',struct('mode',mode), ...
    'synchronization',struct('maxTimingUncertaintySamples',32)));
common=struct('Source',"decoded_sib1",'TimingAdvanceOffsetPresent',false,'TimingAdvanceOffset',"");
reference=struct('Source',"received_SSB_timing_and_decoded_BCH", ...
    'SampleRateHz',fs,'DLPhaseOffsetSamples',6,'AvailableAtSample',1000);
cfg.SharedULTimingContext=struct('DLReference',reference, ...
    'Offset',sixgr.phy.frame.resolveULTimingAdvanceOffset(common,'FR1'), ...
    'ReceivedRARTiming',sixgr.phy.ra.resolveRARTimingAdvance(command,scs,fs), ...
    'TimingAdvanceAvailableAtSample',1000,'TimingAdvanceEffectiveAtSample',2000, ...
    'TimeAlignmentExpirySampleExclusive',Inf);
end

function value=taintedSamples(cfg)
value=cfg.SharedULTimingContext.ReceivedRARTiming.Samples+1;
end

function localReject(fn,id)
try, fn(); catch cause, assert(strcmp(cause.identifier,id),cause.message); return; end
error('test:ExpectedFailure','Expected %s.',id);
end
