function ok=testADCContinuousState()
% Actual converter outputs, including stochastic errors, are partition invariant.
p=struct("Bits",12,"FullScale",1,"Convention","signed_midtread", ...
    "DitherRMS",0.002,"ApertureJitter_s",4e-9,"SampleRate_Hz",1e6, ...
    "INL_LSB",0.3,"DNL_LSB",0.2,"Seed",17);
n=(0:1023).';
for complexInput=[false true]
    x=[0.2*cos(.03*n),0.1*sin(.07*n)];
    if complexInput
        x=complex(x,[0.17*sin(.03*n),0.08*cos(.07*n)]);
    end
    [expected,whole]=sixgr.rf.runtime.ADCModel.quantize(x,p);
    state=struct();
    actual=zeros(size(x),'like',expected.Output);
    dither=zeros(size(x),'like',expected.Dither);
    aperture=zeros(size(x),'like',expected.ApertureError);
    first=1;
    for last=[1 3 17 521 1024]
        [part,state]=sixgr.rf.runtime.ADCModel.quantize(x(first:last,:),p,state);
        actual(first:last,:)=part.Output;
        dither(first:last,:)=part.Dither;
        aperture(first:last,:)=part.ApertureError;
        assert(part.StartSample==first-1 && part.EndSampleExclusive==last);
        first=last+1;
    end
    assert(isequal(actual,expected.Output));
    assert(isequal(dither,expected.Dither) && isequal(aperture,expected.ApertureError));
    assert(state.SamplesProcessed==size(x,1) && isequal(state.PreviousInput,whole.PreviousInput));
    assert(isequal(state.DitherStream.State,whole.DitherStream.State));
    assert(isequal(state.JitterStream.State,whole.JitterStream.State));
    bad=p; bad.FullScale=2;
    before=state.DitherStream.State;
    try
        sixgr.rf.runtime.ADCModel.quantize(x,bad,state);
        error("TEST:MissingError","Changed profile was accepted.");
    catch ME
        assert(string(ME.identifier)=="RF:ADCStateMismatch");
    end
    assert(isequal(state.DitherStream.State,before));
    badState=state; badState.SamplesProcessed=-1;
    try
        sixgr.rf.runtime.ADCModel.quantize(x,p,badState);
        error("TEST:MissingError","Invalid sample clock was accepted.");
    catch ME
        assert(string(ME.identifier)=="RF:ADCStateMismatch");
    end
    assert(isequal(state.DitherStream.State,before));
end
% INL/DNL are separate I and Q converter transfer errors, not a complex
% sine of both codes or an I-only DNL adjustment.
p.DitherRMS=0; p.ApertureJitter_s=0;
for convention=["signed_midtread","signed_midrise"]
    p.Convention=convention;
    x=complex(linspace(-.9,.9,100).',linspace(.6,-.7,100).');
    both=sixgr.rf.runtime.ADCModel.quantize(x,p);
    i=sixgr.rf.runtime.ADCModel.quantize(real(x),p);
    q=sixgr.rf.runtime.ADCModel.quantize(imag(x),p);
    assert(isequal(real(both.Output),i.Output) && isequal(imag(both.Output),q.Output));
end
fprintf('ADC_CONTINUOUS_STATE_PASS: real/complex multi-channel dither, jitter and I/Q transfer errors.\n');
ok=true;
end
