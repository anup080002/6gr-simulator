function ok=testReceivedDLTimingReference()
% Declared decoded-metadata contract fixtures on native OFDM sample clocks.
% Zero-valued completed buffers are not a PBCH decoding/RF qualification.
setup6GRSimToolkit('Verbose',false);
groups={@nativeClocks,@wrapAndAvailability,@identityGuards,@malformedClocks,@observationGuards};
names=["native_clocks_and_halves","SFN_wrap_and_delayed_availability", ...
    "received_identity_guards","malformed_clock_fields","original_observation_guards"];
for k=1:numel(groups)
    groups{k}();
    fprintf('RECEIVED_DL_TIMING_REFERENCE_PASS %s\n',names(k));
end
fprintf('RECEIVED_DL_TIMING_REFERENCE_SCOPE declared_metadata_native_clock_only BCH_decodes=0 RF_executions=0\n');
ok=true;
end

function nativeClocks()
for scs=[15 30]
    for half=[0 1]
        for frame=[0 17]
            for phase=[-4 4]
                f=fixture(scs,frame,half,phase,0);
                old=f.Recovered;
                samples=f.Observation.readComplete();
                r=call(f);
                assert(r.AbsoluteFrameNumber==frame && r.ReceivedSFN==mod(frame,1024));
                assert(r.ReceivedHalfFrame==half && r.DLPhaseOffsetSamples==phase);
                assert(r.ReceivedFrameOriginSample==frame*f.FrameSamples+phase);
                assert(r.ObservationStartSample==f.Observation.StartSample && ...
                    r.AvailableAtSample==f.Observation.EndSampleExclusive);
                assert(r.RawSSBTiming_samples==old.TimingOffset && ...
                    r.ImplementationFilterDelay_samples==f.FilterDelay && ~r.WaveformTimingApplied);
                assert(isequaln(old,f.Recovered) && isequal(samples,f.Observation.readComplete()));
            end
        end
    end
end
end

function wrapAndAvailability()
for frame=[1023 1024 2048]
    for half=[0 1]
        immediate=fixture(30,frame,half,3,0);
        delayed=fixture(30,frame,half,3,2);
        r=call(immediate); later=call(delayed);
        assert(r.AbsoluteFrameNumber==frame && r.ReceivedSFN==mod(frame,1024));
        assert(later.AvailableAtSample-r.AvailableAtSample==2*immediate.FrameSamples);
        assert(isequaln(rmfield(r,'AvailableAtSample'),rmfield(later,'AvailableAtSample')), ...
            'Capture completion must not select a newer SFN or change original received phase.');
        % Runtime metadata/configured candidate is not a substitute for the
        % decoded candidate, half-frame and original received sample origin.
        changed=delayed;
        changed.Config.phy.carrier.NFrame=777;
        changed.Config.phy.ssb.SSBIndex=1;
        changed.Config.phy.ssb.halfFrameIndex=1-half;
        assert(isequaln(later,call(changed)));
    end
end
end

function identityGuards()
f=fixture(30,1024,1,0,0);
bad=f; bad.Recovered.MIBSystemFrameNumber=1023;
expect(@()call(bad),'sixgr:phy:frame:ReceivedSFNClockMismatch');
bad=f; bad.Recovered.MIBSystemFrameNumber=1;
expect(@()call(bad),'sixgr:phy:frame:ReceivedSFNClockMismatch');
bad=f; bad.Recovered.MIBHalfFrameBit=0;
expect(@()call(bad),'sixgr:phy:frame:UnresolvedDLReferenceEpoch');
bad=f; bad.Recovered.SSBIndex=1;
expect(@()call(bad),'sixgr:phy:frame:InconsistentReceivedSSBTiming');
bad=f; bad.Recovered.SampleRateHz=f.Recovered.SampleRateHz*2;
expect(@()call(bad),'sixgr:phy:frame:InconsistentReceivedSSBTiming');
bad=fixture(15,7,0,9,0);
expect(@()call(bad),'sixgr:phy:frame:UnresolvedDLReferenceEpoch');
bad=f; bad.Config.phy.synchronization.maxTimingUncertaintySamples=f.FrameSamples/2;
expect(@()call(bad),'sixgr:phy:frame:UnresolvedDLReferenceEpoch');
end

function malformedClocks()
f=fixture(15,3,0,0,0);
for field=["MIBSystemFrameNumber","MIBHalfFrameBit","TimingOffset", ...
        "MIBSSBIndex","SSBIndex","NCellID","SampleRateHz"]
    for value={NaN,Inf,-Inf,-1,1+1i,[],[0 1],'0',"0",true}
        bad=f; bad.Recovered.(field)=value{1};
        expect(@()call(bad),'sixgr:phy:frame:InvalidReceivedDLTiming');
    end
end
for field=["MIBSystemFrameNumber","MIBHalfFrameBit","TimingOffset","MIBSSBIndex","SSBIndex","NCellID"]
    bad=f; bad.Recovered.(field)=0.5;
    expect(@()call(bad),'sixgr:phy:frame:InvalidReceivedDLTiming');
end
for pair={ {'MIBSystemFrameNumber',1024}, {'MIBHalfFrameBit',2}, ...
        {'MIBSSBIndex',64}, {'SSBIndex',64}, {'NCellID',1008}, {'SampleRateHz',0} }
    entry=pair{1}; bad=f; bad.Recovered.(entry{1})=entry{2};
    expect(@()call(bad),'sixgr:phy:frame:InvalidReceivedDLTiming');
end
for value={NaN,Inf,-1,0.5,[],[0 1],'0',"0",true,1+1i}
    bad=f; bad.FilterDelay=value{1};
    expect(@()call(bad),'sixgr:phy:frame:InvalidReceivedDLTiming');
end
bad=f; bad.Recovered=rmfield(bad.Recovered,'MIBSystemFrameNumber');
expect(@()call(bad),'sixgr:phy:frame:InvalidReceivedDLTiming');
for flag=["BCHCrcPass","MIBDecoded"]
    for value={false,1,'1',[true true]}
        bad=f; bad.Recovered.(flag)=value{1};
        expect(@()call(bad),'sixgr:phy:frame:UndecodedDLTiming');
    end
end
end

function observationGuards()
f=fixture(15,0,0,0,0);
bad=f; bad.Observation=struct('StartSample',f.Observation.StartSample);
expect(@()call(bad),'sixgr:phy:frame:InvalidReceivedDLTiming');
bad=f; bad.Observation=sixgr.phy.waveform.WaveformObservationBuffer( ...
    f.Observation.StartSample,f.Observation.EndSampleExclusive,f.Recovered.SampleRateHz,1);
expect(@()call(bad),'WAVEFORM:IncompleteObservation');
bad=f; bad.Recovered.TimingOffset=f.Observation.EndSampleExclusive-f.Observation.StartSample;
expect(@()call(bad),'sixgr:phy:frame:InvalidReceivedDLTiming');
bad=f; bad.Observation=buffer(0,64,1e6); bad.Recovered.SampleRateHz=1e6;
expect(@()call(bad),'sixgr:phy:frame:DLReferenceOffSampleClock');
% An apparently integral double beyond the exact sample domain must not
% silently produce a rounded epoch. This small buffer allocates four rows.
bad=f; bad.Observation=buffer(flintmax,flintmax+4,f.Recovered.SampleRateHz);
bad.Recovered.TimingOffset=0;
expect(@()call(bad),'sixgr:phy:frame:InvalidReceivedDLTiming');
end

function f=fixture(scs,frame,half,phase,completionDelayFrames)
carrier=nrCarrierConfig('SubcarrierSpacing',scs,'NSizeGrid',25,'NCellID',17);
info=nrOFDMInfo(carrier);
pattern="Case A"; if scs==30, pattern="Case C"; end
cfg=struct();
cfg.phy.carrier=struct('NCellID',17,'centerFrequency_Hz',2e9, ...
    'SubcarrierSpacing_kHz',scs,'NStartGrid',0,'NSizeGrid',25);
cfg.phy.frequencyRange="FR1";
cfg.phy.ssb=struct('blockPattern',pattern,'scs_kHz',scs,'Lmax',4,'periodicity_ms',5);
cfg.phy.synchronization.maxTimingUncertaintySamples=8;
frameSamples=info.SampleRate*0.010;
assert(frameSamples==fix(frameSamples));
% The first Case A/C candidate begins at symbol2. Native CP-aware lengths
% independently establish its sample coordinate, including half-frame1.
within=half*frameSamples/2+sum(double(info.SymbolLengths(1:2)));
filterDelay=7;
detection=frame*frameSamples+within+filterDelay+phase;
start=detection-31;
stop=detection+33+completionDelayFrames*frameSamples;
recovered=struct('BCHCrcPass',true,'MIBDecoded',true,'TimingOffset',31, ...
    'SampleRateHz',info.SampleRate,'MIBSystemFrameNumber',mod(frame,1024), ...
    'MIBHalfFrameBit',half,'MIBSSBIndex',0,'SSBIndex',0,'NCellID',17);
f=struct('Config',cfg,'Recovered',recovered,'Observation',buffer(start,stop,info.SampleRate), ...
    'FilterDelay',filterDelay,'FrameSamples',frameSamples);
end

function out=buffer(start,stop,fs)
out=sixgr.phy.waveform.WaveformObservationBuffer(start,stop,fs,1);
out.append(sixgr.phy.waveform.WaveformChunk(complex(zeros(stop-start,1)),start),fs);
end

function out=call(f)
out=sixgr.phy.frame.receivedDLTimingReference(f.Config,f.Recovered,f.Observation,f.FilterDelay);
end

function expect(f,id)
try
    f();
catch e
    assert(string(e.identifier)==string(id),'Expected %s; got %s: %s',id,e.identifier,e.message);
    return;
end
error('sixgr:test:MissingGuard','Expected %s.',id);
end
