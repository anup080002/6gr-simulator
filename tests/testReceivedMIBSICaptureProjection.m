function ok=testReceivedMIBSICaptureProjection()
% Declared arithmetic/buffer fixtures ONLY. No original MIB, SI reception,
% shared owner, transmission, decoder outcome or execution authority claim.
setup6GRSimToolkit('Verbose',false);
before=rng; groups=0;
for mode=1:4
    scs=[15 30 60 60]; cp="normal"; if mode==4, cp="extended"; end
    geometry=struct('SubcarrierSpacing',scs(mode),'CyclicPrefix',cp);
    spec=sixgr.phy.frame.NumerologyCatalog.resolve(scs(mode),cp,'generic_waveform_test','');
    fs=30.72e6; frame=1023;
    for phase=[-11 7]
        data=struct('ReceiverGeometry',geometry,'SampleRateHz',fs,'NumReceiveAntennas',2, ...
            'AbsoluteFrameNumber',frame,'ReceivedFrameOriginSample',frame*fs/100+phase);
        slot=1024*spec.SlotsPerFrame+1;
        relative=slot-frame*spec.SlotsPerFrame;
        first=data.ReceivedFrameOriginSample+sixgr.phy.frame.slotStartSample(geometry,relative,fs);
        stop=data.ReceivedFrameOriginSample+sixgr.phy.frame.slotStartSample(geometry,relative+1,fs);
        % Independent global-boundary relation across the SFN rollover.
        assert(first==sixgr.phy.frame.slotStartSample(geometry,slot,fs)+phase && ...
            stop==sixgr.phy.frame.slotStartSample(geometry,slot+1,fs)+phase);
        prefix=37; tail=19; n=stop-first;
        x=complex(reshape(sin((1:2*(n+prefix+tail))/17),[],2), ...
            reshape(cos((1:2*(n+prefix+tail))/23),[],2));
        observation=buffer(x,first-prefix,fs);
        r=struct('SIB1ReceptionAttempted',true,'SIB1ObservationComplete',true, ...
            'SIB1CaptureStartSample',observation.StartSample,'SIB1AvailableCaptureSamples',size(x,1), ...
            'SIB1AbsoluteSlot',slot,'SIB1ObservationStartSample',prefix, ...
            'SIB1ObservationEndSampleExclusive',prefix+n, ...
            'SIB1ObservationSampleDomain',"relative_to_original_received_capture_start_zero_based", ...
            'SIB1InputSampleSHA256',sixgr.phy.waveform.WaveformHash.runtimeArray(x(prefix+(1:n),:)));
        original=observation.sampleHash();
        [matched,status]=sixgr.truth.ReceivedMIBDelivery.validateSICaptureProjection(data,r,observation);
        assert(matched && status=="original_SI_slot_projection_matched" && original~=r.SIB1InputSampleSHA256);
        % Exact one-slot legacy capture remains the same numerical contract.
        exact=buffer(x(prefix+(1:n),:),first,fs); e=r;
        e.SIB1CaptureStartSample=first; e.SIB1AvailableCaptureSamples=n;
        e.SIB1ObservationStartSample=0; e.SIB1ObservationEndSampleExclusive=n;
        assert(sixgr.truth.ReceivedMIBDelivery.validateSICaptureProjection(data,e,exact));
        for defect=["whole_hash","start","stop","slot","domain","input_hash","attempt_type","complete_type"]
            bad=r;
            switch defect
                case "whole_hash", bad.SIB1InputSampleSHA256=original;
                case "start", bad.SIB1ObservationStartSample=prefix+1;
                case "stop", bad.SIB1ObservationEndSampleExclusive=prefix+n-1;
                case "slot", bad.SIB1AbsoluteSlot=slot+1;
                case "domain", bad.SIB1ObservationSampleDomain="absolute_samples";
                case "input_hash", bad.SIB1InputSampleSHA256="changed";
                case "attempt_type", bad.SIB1ReceptionAttempted=1;
                case "complete_type", bad.SIB1ObservationComplete=1;
            end
            reject(@()sixgr.truth.ReceivedMIBDelivery.validateSICaptureProjection(data,bad,observation));
        end
        changed=data; changed.ReceivedFrameOriginSample=changed.ReceivedFrameOriginSample+1;
        reject(@()sixgr.truth.ReceivedMIBDelivery.validateSICaptureProjection(changed,r,observation));
        y=x; y(prefix+1,1)=y(prefix+1,1)+1;
        reject(@()sixgr.truth.ReceivedMIBDelivery.validateSICaptureProjection(data,r,buffer(y,first-prefix,fs)));
        % Altered prefix is not part of the receiver's SI hash. This PURE
        % projection intentionally accepts it; the original owner separately
        % authenticates the entire capture before this method is called.
        y=x; y(1,1)=y(1,1)+1;
        assert(sixgr.truth.ReceivedMIBDelivery.validateSICaptureProjection(data,r,buffer(y,first-prefix,fs)));
        missing=rmfield(r,{'SIB1AbsoluteSlot','SIB1ObservationStartSample', ...
            'SIB1ObservationEndSampleExclusive','SIB1ObservationSampleDomain','SIB1InputSampleSHA256'});
        missing.SIB1ReceptionAttempted=false; missing.SIB1ObservationComplete=false;
        [matched,status]=sixgr.truth.ReceivedMIBDelivery.validateSICaptureProjection(data,missing,observation);
        assert(~matched && status=="SI_reception_not_attempted");
        missing.SIB1ObservationComplete=true;
        reject(@()sixgr.truth.ReceivedMIBDelivery.validateSICaptureProjection(data,missing,observation));
        assert(observation.sampleHash()==original); groups=groups+1;
    end
end
assert(isequal(before,rng));
fprintf('RECEIVED_MIB_SI_CAPTURE_PROJECTION_PASS groups=%d declared_operand_fixtures=1 physical_execution=0\n',groups);
ok=true;
end
function out=buffer(x,first,fs)
out=sixgr.phy.waveform.WaveformObservationBuffer(first,first+size(x,1),fs,size(x,2));
out.append(sixgr.phy.waveform.WaveformChunk(x,first),fs);
end
function reject(fn)
try, fn(); catch ex
    assert(strcmp(ex.identifier,'sixgr:truth:ReceivedMIBSICaptureMismatch'), ...
        'Unexpected error %s: %s',ex.identifier,ex.message); return;
end
error('test:ExpectedSICaptureProjectionFailure','Expected strict original crop rejection.');
end
