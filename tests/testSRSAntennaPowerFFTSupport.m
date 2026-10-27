function ok=testSRSAntennaPowerFFTSupport()
% Native demodulator dependency/arithmetic component, not a shared SRS run.
% Timing/support below are DECLARED fixture inputs. Native impulse influence
% independently tests the implementation's actual FFT support and scale.
setup6GRSimToolkit('Verbose',false);
cases={15,'normal',0;30,'normal',1;60,'extended',3};
checks=0;
for n=1:size(cases,1)
    carrier=nrCarrierConfig('NSizeGrid',24,'SubcarrierSpacing',cases{n,1}, ...
        'CyclicPrefix',cases{n,2},'NSlot',cases{n,3});
    native=nrOFDMInfo(carrier); L=double(carrier.SymbolsPerSlot);
    slot=mod(double(carrier.NSlot),double(carrier.SlotsPerSubframe));
    lengths=native.SymbolLengths(slot*L+(1:L)); count=sum(lengths);
    first=10000; offset=23; stop=first+offset+count+31;
    timing=struct('AppliedTimingCorrectionSamples',offset,'DemodulatedSampleCount',count, ...
        'OracleTimingUsed',false,'ReceiverZeroPaddingUsed',false);
    symbol=L-2; support=[0 symbol;12 symbol;24 symbol];
    for fraction=[0 .5 1]
        wave=complex(zeros(count,3));
        [base,info]=sixgr.phy.waveform.ofdmDemodulate(carrier,wave, ...
            'CyclicPrefixFraction',fraction,'Windowing',0);
        e=sixgr.phy.srs.srsAntennaPowerFFTSupport(carrier,info,timing,first,stop,support);
        assert(e.NativeFFTCapability.Available && ...
            e.NativeFFTCapability.Signature.MATLABRelease==string(version('-release')) && ...
            e.NativeFFTCapability.ProbeDemodulationsToEstablishCapability==1 && ...
            ~e.NativeFFTCapability.OriginalCaptureConsumed);
        sixgr.phy.waveform.validateNativeOFDMFFTCapability(e.NativeFFTCapability,carrier, ...
            info.Nfft,info.SampleRate,fraction,L,0);
        assert(e.FFTIntervals(1,1)==first+offset+sum(lengths(1:symbol))+ ...
            fix(native.CyclicPrefixLengths(slot*L+symbol+1)*fraction));
        a=e.FFTIntervals(1,1)-first-offset+1;
        b=e.FFTIntervals(1,2)-first-offset+1;
        for position=[a-1 a b-1 b]
            if position<1 || position>count, continue; end
            perturbed=wave; perturbed(position,1)=1;
            changed=sixgr.phy.waveform.ofdmDemodulate(carrier,perturbed, ...
                'CyclicPrefixFraction',fraction,'Windowing',0);
            values=changed(:,symbol+1,1)-base(:,symbol+1,1);
            if position>=a && position<b
                assert(max(abs(abs(values)-1))<1e-12, ...
                    'test:SRSFFTScale','One actual time impulse must have unit raw FFT magnitude.');
            else
                assert(~any(values~=0),'test:SRSFFTSupport','Outside samples cannot influence this FFT.');
            end
            checks=checks+1;
        end
        % Independent nonunit physical power and DIFFERENT selected branch.
        % Actual native FFT magnitude is known from the time impulse, not
        % reconstructed by the scorer's own formula on both operands.
        referenceW=[4 1 0]*1e-9; measuredW=[2 5 0]*1e-9;
        wave(a,:)=sqrt(referenceW*1000)*native.Nfft;
        grid=sixgr.phy.waveform.ofdmDemodulate(carrier,wave, ...
            'CyclicPrefixFraction',fraction,'Windowing',0);
        result=sixgr.phy.srs.compareSRSAntennaPower(grid,support,native.Nfft,measuredW);
        assert(norm(result.ReferencePerBranch_W-referenceW)<1e-12*norm(referenceW) && ...
            result.MeasuredSelectedBranch0==1 && result.ReferenceSelectedBranch0==0 && ...
            abs(result.ReferenceAtMeasuredSelectedBranch_W-referenceW(2))<1e-20 && ...
            abs(result.ReportedError_dB-10*log10(5/4))<1e-12 && ...
            abs(result.PerBranchError_dB(1)-10*log10(.5))<1e-12 && ...
            abs(result.PerBranchError_dB(2)-10*log10(5))<1e-12 && ...
            isnan(result.PerBranchError_dB(3)) && ~result.PerBranchErrorDefined(3));
        zero=sixgr.phy.srs.compareSRSAntennaPower(zeros(size(grid)),support,native.Nfft,measuredW);
        assert(isnan(zero.ReferencePower_dBm)&&isnan(zero.ReportedError_dB));
        mustReject(@()sixgr.phy.srs.compareSRSAntennaPower(grid,[support;support(1,:)], ...
            native.Nfft,measuredW),'sixgr:srs:ReferencePowerOperands');
    end
    wrong=info; wrong.SampleRate=info.SampleRate*2;
    mustReject(@()sixgr.phy.srs.srsAntennaPowerFFTSupport(carrier,wrong,timing,first,stop,support), ...
        'sixgr:srs:AntennaPowerFFTSupport');
    wrong=info; wrong.EngineUsed="unqualified_demodulator";
    mustReject(@()sixgr.phy.srs.srsAntennaPowerFFTSupport(carrier,wrong,timing,first,stop,support), ...
        'sixgr:srs:AntennaPowerFFTSupport');
    wrongTiming=timing; wrongTiming.ReceiverZeroPaddingUsed=true;
    mustReject(@()sixgr.phy.srs.srsAntennaPowerFFTSupport(carrier,info,wrongTiming,first,stop,support), ...
        'sixgr:srs:AntennaPowerFFTSupport');
    mustReject(@()sixgr.phy.srs.srsAntennaPowerFFTSupport(carrier,info,timing,first,stop-40,support), ...
        'sixgr:srs:AntennaPowerFFTSupport');
end
fprintf('SRS_FFT_SUPPORT_PASS native_impulse_checks=%d shared_runtime=0 decoded_SRS=0\n',checks);
ok=true;
end

function mustReject(action,id)
try
    action();
catch failure
    assert(strcmp(failure.identifier,id),'test:SRSFFTWrongError','Unexpected %s',failure.identifier);
    return;
end
error('test:SRSFFTMissingError','Expected %s.',id);
end
