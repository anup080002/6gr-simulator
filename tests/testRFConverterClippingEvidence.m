function ok=testRFConverterClippingEvidence()
% Clipping evidence must describe the executed quantizer population, not a
% hypothetical full-scale comparison on the input of a disabled device.
setup6GRSimToolkit('Verbose',false);
x=complex([0 .3;1 1.2;-.1 -1],[0 1.2;0 -.2;1 -1.1]);
fs=122.88e6;
off=sixgr.rf.applyRFImpairmentChain(10*x,struct(),'SampleRateHz',fs, ...
    'Endpoint','txrx','UseLegacyGlobalConfig',false,'StrictMutationRequired',false);
assert(isequal(off.Waveform,10*x));
assert(isnan(off.Replay.ADCClippingRatio) && isnan(off.Replay.DACClippingRatio), ...
    'sixgr:test:DisabledConverterClaimsClipping','A disabled converter did not measure a clipping ratio.');
assert(~off.Replay.ADCQuantizationExecuted && ~off.Replay.DACQuantizationExecuted);
assert(off.Replay.ADCClippingStatus=="not_executed" && off.Replay.DACClippingStatus=="not_executed");
cfg=struct(); cfg.rf.adc.enable=true; cfg.rf.adcBits=4; cfg.rf.adc.fullScale=1;
for input={x,real(x),zeros(4,2),complex([1;-1],[0;0])}
    a=input{1};
    expected=sixgr.rf.runtime.ADCModel.quantize(a,struct('Bits',4,'FullScale',1,'Convention','signed_midtread'));
    actual=sixgr.rf.applyRFImpairmentChain(a,cfg,'SampleRateHz',fs, ...
        'Endpoint','rx','UseLegacyGlobalConfig',false,'StrictMutationRequired',false);
    localCheck(actual,expected,'ADC');
end
rxActual=actual;
cfg=struct();
cfg.rf.frontend.dac=struct('enabled',true,'profile_id','clipping_component', ...
    'version','1','bits',4,'full_scale',1,'convention','signed_midrise', ...
    'dither_enabled',true,'dither_rms',.3,'aperture_jitter_seconds',0);
profile=struct('ProfileID','clipping_component','Version','1','Bits',4, ...
    'FullScale',1,'Convention','signed_midrise','DitherRMS',.3,'ApertureJitter_s',0);
expected=sixgr.rf.runtime.DACModel.convert(x,profile,fs,1);
actual=sixgr.rf.applyRFImpairmentChain(x,cfg,'SampleRateHz',fs, ...
    'Endpoint','tx','UseLegacyGlobalConfig',false,'StrictMutationRequired',false);
localCheck(actual,expected,'DAC');
% The production DL/UL row binder must take DAC evidence from the TX owner,
% not the receiver replay. Preserve applicability and population in CSV.
folder=tempname; mkdir(folder);
cleanup=onCleanup(@()rmdir(folder,'s')); %#ok<NASGU>
for direction=["DL","UL"]
    row=sixgr.report.bindConverterEvidence(struct('Direction',direction),rxActual.Replay,actual.Replay);
    assert(row.ADCClippingRatio==rxActual.Replay.ADCClippingRatio && ...
        row.DACClippingRatio==actual.Replay.DACClippingRatio);
    offRow=sixgr.report.bindConverterEvidence(struct('Direction',direction),off.Replay,off.Replay);
    missingRow=sixgr.report.bindConverterEvidence(struct('Direction',direction),struct(),struct());
    path=fullfile(folder,direction+"_converter.csv");
    writetable(struct2table([row;offRow;missingRow]),path);
    reread=sixgr.util.csvReadTable(path);
    assert(reread.ADCClippedSampleCount(1)==rxActual.Replay.ADCClippedSampleCount && ...
        reread.DACClippedSampleCount(1)==actual.Replay.DACClippedSampleCount);
    assert(all(isnan(reread.ADCClippingRatio(2:3))) && all(isnan(reread.DACClippingRatio(2:3))));
    assert(string(reread.ADCClippingStatus(2))=="not_executed" && ...
        string(reread.ADCClippingStatus(3))=="unavailable_no_converter_execution_evidence");
end
% Actual DL/UL front-end wrappers must retain disabled applicability.
for direction=["DL","UL"]
    [y,r]=sixgr.link.applyCompositeReceiverFrontEnd(10*x,struct(),fs,struct(), ...
        'Direction',direction,'UseLegacyGlobalConfig',false);
    assert(isequal(y,10*x) && isnan(r.ADCClippingRatio) && r.ADCClippingStatus=="not_executed");
end
fprintf('RF_CONVERTER_CLIPPING_EVIDENCE_PASS disabled_identity=1 actual_mask_population=1\n');
ok=true;
end

function localCheck(actual,expected,prefix)
assert(isequal(actual.Waveform,expected.Output));
assert(actual.Replay.(prefix+"QuantizationExecuted"));
assert(actual.Replay.(prefix+"ClippingRatio")==mean(double(expected.Clipped(:))));
assert(actual.Replay.(prefix+"ClippedSampleCount")==nnz(expected.Clipped));
assert(actual.Replay.(prefix+"ClippingSampleCount")==numel(expected.Clipped));
assert(actual.Replay.(prefix+"ClippingStatus")=="measured");
assert(actual.Replay.(prefix+"ClippingSource")=="executed_converter_clipped_mask");
assert(actual.Row.(prefix+"ClippingRatio")==actual.Replay.(prefix+"ClippingRatio"));
end
