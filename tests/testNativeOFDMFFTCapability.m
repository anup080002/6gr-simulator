function ok=testNativeOFDMFFTCapability()
% Isolated public-API probes only: not RF execution or receiver qualification.
setup6GRSimToolkit('Verbose',false);
before=rng; cases={15,'normal',0;30,'normal',3;60,'extended',2}; checks=0;
for row=1:size(cases,1)
    c=nrCarrierConfig('NSizeGrid',6,'SubcarrierSpacing',cases{row,1}, ...
        'CyclicPrefix',cases{row,2},'NSlot',cases{row,3});
    nfft=256; fs=nfft*c.SubcarrierSpacing*1000; L=double(c.SymbolsPerSlot);
    for fraction=[0 .25 .5 1]
        [e,a]=sixgr.phy.waveform.nativeOFDMFFTCapability(c,nfft,fs,fraction,L,2.35e9);
        assert(e.Available && e.Signature.MATLABRelease==string(version('-release')) && ...
            e.ProbeDemodulationsToEstablishCapability==1 && ~e.OriginalCaptureConsumed && ...
            e.OriginalCaptureDemodulations==0 && e.RFExecutions==0 && e.ChannelExecutions==0 && ...
            isequal(rng,before) && any(a.IsolatedProbeDemodulationsThisCall==[0 1]));
        assert(sum(e.ProbeExpectedIncluded)==2*L && ...
            all(e.ProbeMaximumMagnitude(~e.ProbeExpectedIncluded)<=e.ArithmeticTolerance));
        [again,cached]=sixgr.phy.waveform.nativeOFDMFFTCapability(c,nfft,fs,fraction,L,2.35e9);
        assert(isequaln(e,again)&&cached.CacheHit&&cached.IsolatedProbeDemodulationsThisCall==0);
        actual=sixgr.phy.waveform.validateNativeOFDMFFTCapability( ...
            jsondecode(jsonencode(e)),c,nfft,fs,fraction,L,2.35e9);
        assert(actual.CacheHit&&actual.IsolatedProbeDemodulationsThisCall==0);
        bad=e; bad.Signature.MATLABRelease="not_the_original_runtime";
        reject(@()sixgr.phy.waveform.validateNativeOFDMFFTCapability(bad,c,nfft,fs,fraction,L,2.35e9));
        bad=e; bad.FFTIntervals(1,1)=bad.FFTIntervals(1,1)+1;
        bad.EvidenceSHA256=sixgr.util.sha256Hex(char(jsonencode(rmfield(bad,'EvidenceSHA256'))));
        reject(@()sixgr.phy.waveform.validateNativeOFDMFFTCapability(bad,c,nfft,fs,fraction,L,2.35e9));
        bad=e; bad.Available=1;
        reject(@()sixgr.phy.waveform.validateNativeOFDMFFTCapability(bad,c,nfft,fs,fraction,L,2.35e9));
        bad=e; bad.OriginalCaptureConsumed=0;
        reject(@()sixgr.phy.waveform.validateNativeOFDMFFTCapability(bad,c,nfft,fs,fraction,L,2.35e9));
        bad=e; bad.ProbeMaximumMagnitude(1)=0;
        reject(@()sixgr.phy.waveform.validateNativeOFDMFFTCapability(bad,c,nfft,fs,fraction,L,2.35e9));
        reject(@()sixgr.phy.waveform.validateNativeOFDMFFTCapability(struct(),c,nfft,fs,fraction,L,2.35e9));
        checks=checks+1;
    end
end
% Declared legacy-shaped operator fixture: no historical receipt rewritten.
legacy=struct('RuntimeMATLABRelease',"2026a",'EngineUsed',"canonical_nrOFDMDemodulate");
if string(version('-release'))=="2026a"
    a=sixgr.phy.waveform.validateRecordedOFDMFFTAuthority(legacy,c,nfft,fs,.5,L,0,true);
    assert(a.IsolatedProbeDemodulationsThisCall==0 && contains(a.AuthorityScope,"legacy_v1"));
else
    rejectAuthority(@()sixgr.phy.waveform.validateRecordedOFDMFFTAuthority(legacy,c,nfft,fs,.5,L,0,true));
end
bad=legacy; bad.RuntimeMATLABRelease="not_original";
rejectAuthority(@()sixgr.phy.waveform.validateRecordedOFDMFFTAuthority(bad,c,nfft,fs,.5,L,0,true));
% v2 must never fall back to a legacy-shaped operator lacking capability.
legacy.RuntimeMATLABRelease=string(version('-release'));
rejectAuthority(@()sixgr.phy.waveform.validateRecordedOFDMFFTAuthority(legacy,c,nfft,fs,.5,L,0,false));
[cap,~]=sixgr.phy.waveform.nativeOFDMFFTCapability(c,nfft,fs,.5,L,0);
new=legacy; new.NativeFFTCapability=cap;
a=sixgr.phy.waveform.validateRecordedOFDMFFTAuthority(new,c,nfft,fs,.5,L,0,false);
assert(a.IsolatedProbeDemodulationsThisCall==0 && a.AuthorityScope=="v2_original_runtime_capability_validated");
rejectAuthority(@()sixgr.phy.waveform.validateRecordedOFDMFFTAuthority(new,c,nfft,fs,.5,L,0,true));
rejected=false;
try, sixgr.phy.waveform.nativeOFDMFFTCapability(c,nfft,fs*2,.5,L,0);
catch failure, rejected=strcmp(failure.identifier,'sixgr:waveform:NativeFFTCapability'); end
assert(rejected&&isequal(rng,before));
fprintf('NATIVE_FFT_CAPABILITY_PASS cases=%d runtime=%s original_capture_demodulations=0 isolated_probes_separate=1\n', ...
    checks,version('-release'));
ok=true;
end
function reject(fn)
try, fn(); catch failure
    assert(strcmp(failure.identifier,'sixgr:waveform:NativeFFTCapabilityBinding')); return;
end
error('test:NativeFFTCapabilityGuard','Malformed or mismatched operator evidence was accepted.');
end

function rejectAuthority(fn)
try, fn(); catch failure
    assert(strcmp(failure.identifier,'sixgr:waveform:RecordedFFTAuthority')); return;
end
error('test:NativeFFTLegacyGuard','Invalid legacy/v2 authority was accepted.');
end
