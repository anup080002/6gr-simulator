function ok=testCompositeNoiseVarianceAuthority()
setup6GRSimToolkit('Verbose',false);
pre=3e-12;
r=struct('InjectedNoiseVariance',pre,'NoiseVarianceSource','test_absolute_thermal', ...
    'AGCApplied',true,'AGCGain_dB',20,'ADCQuantizationApplied',false);
out=sixgr.link.applyCompositeFrontEndVarianceReplay(r);
assert(abs(out.InjectedNoiseVariance-100*pre)<1e-12*pre);
assert(out.InjectedNoiseVariancePreCompositeFrontEnd==pre);
assert(~out.CompositeReceiverNoiseVarianceAssumesUncorrelatedADCError);
r.AGCGain_dB=NaN;
localError(@()sixgr.link.applyCompositeFrontEndVarianceReplay(r),'RF:MissingAppliedAGCGain');
r.AGCGainIsTimeVarying=true;
localError(@()sixgr.link.applyCompositeFrontEndVarianceReplay(r),'RF:NonstationaryNoiseRequiresReceivedEstimation');
r.AGCGainIsTimeVarying=false; r.AGCGain_dB=20;
r.ADCQuantizationApplied=true; r.ADCQuantizationErrorVariance=1e-10;
out=sixgr.link.applyCompositeFrontEndVarianceReplay(r);
assert(out.CompositeReceiverNoiseVarianceAssumesUncorrelatedADCError && ...
    contains(out.CompositeReceiverNoiseVarianceMethod,'uncorrelated_estimate'));
assert(out.InjectedNoiseVariance==100*pre+r.ADCQuantizationErrorVariance);
ok=true;
disp('COMPOSITE_NOISE_AUTHORITY_PASS: no unity gain rescue; quantization variance assumption disclosed.');
end
function localError(fn,id)
try, fn(); catch cause
    assert(string(cause.identifier)==id); return;
end
error('test:ExpectedError','Expected %s.',id);
end
