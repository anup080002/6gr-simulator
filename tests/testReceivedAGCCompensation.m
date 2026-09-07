function ok=testReceivedAGCCompensation()
% Controlled receiver calibration arithmetic, explicitly a unit fixture.
% Quantization/clipping damage is deliberately retained in the output.
first=113; fs=7.68e6;
original=complex([.1;2;.25;.5],[.2;.1;.1;.2]);
g=[0;6;12;3]; amplified=original.*10.^(g/20);
adc=complex(min(max(real(amplified),-1),1),min(max(imag(amplified),-1),1));
adc=round(real(adc)*128)/128+1j*round(imag(adc)*128)/128;
raw=sixgr.phy.waveform.WaveformObservationBuffer(first,first+4,fs,1);
raw.append(sixgr.phy.waveform.WaveformChunk(adc,first),fs);
trace=struct('AppliedGain_dB',g,'StartSample',first,'EndSampleExclusive',first+4);
r=struct('AGCControlModel','causal_windowed_joint_rms_attack_hold_release','AGCStreamTrace',trace);
segment=struct('StartSample',first,'EndSampleExclusive',first+4, ...
    'Execution',struct('RX',struct('ID',"rx",'Replay',r)));
[corrected,e]=sixgr.phy.rx.compensateReceivedAGC(raw,{segment},"rx");
assert(isequal(corrected.readComplete(),adc./10.^(g/20)));
assert(norm(corrected.readComplete()-original)>1 && ...
    ~e.ClippingReconstructed && ~e.QuantizationRemoved);
assert(isequal(raw.readComplete(),adc),'Digital compensation mutated the recorded ADC output.');
bad=segment; bad.Execution.RX.Replay.AGCStreamTrace.AppliedGain_dB=3;
localError(@()sixgr.phy.rx.compensateReceivedAGC(raw,{bad},"rx"),'sixgr:phy:rx:ActualAGCTraceRequired');
localError(@()sixgr.phy.rx.compensateReceivedAGC(raw,{segment},"wrong"),'sixgr:phy:rx:AGCReceiverIdentity');
localError(@()sixgr.phy.rx.compensateReceivedAGC(raw,{segment,segment},"rx"),'sixgr:phy:rx:InvalidAGCTraceCoverage');
localError(@()sixgr.phy.rx.compensateReceivedAGC(raw,{},"rx"),'sixgr:phy:rx:IncompleteAGCTraceCoverage');
ok=true; disp('RECEIVED_AGC_COMPENSATION_PASS');
end
function localError(fn,id)
try, fn(); catch e, assert(strcmp(e.identifier,id),'Unexpected %s',e.identifier); return; end
error('TEST:ExpectedFailure','Expected %s.',id);
end
