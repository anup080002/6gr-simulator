function ok=testReceivedWaveformEvidence()
% Provenance-only fixture; no CRC or performance qualification is asserted.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
x=complex(reshape(1:32,16,2),reshape(33:64,16,2))/64;
b=sixgr.phy.waveform.WaveformObservationBuffer(19,35,7.68e6,2);
b.append(sixgr.phy.waveform.WaveformChunk(x(1:7,:),19),b.SampleRateHz);
try
    sixgr.link.receivedWaveformEvidence(b);
    error('test:IncompleteCaptureAccepted','Incomplete capture must not have waveform evidence.');
catch cause
    assert(strcmp(cause.identifier,'WAVEFORM:IncompleteObservation'));
end
b.append(sixgr.phy.waveform.WaveformChunk(x(8:end,:),26),b.SampleRateHz);
before=rng;
e=sixgr.link.receivedWaveformEvidence(b);
assert(isequal(before,rng) && e.RuntimeStageWaveformsUsed && ...
    e.ObservationStartSample==19 && e.ObservationEndSampleExclusive==35 && ...
    e.ObservationSampleRateHz==7.68e6 && e.ObservationCompletionTime_s==35/7.68e6 && ...
    e.ReceiverObservationSHA256==sixgr.phy.waveform.WaveformHash.runtimeArray(x));
assert(~isfield(e,'Status') && ~isfield(e,'EVM_rms') && ~isfield(e,'CRCPass'));
defaults=sixgr.link.receivedWaveformEvidence();
assert(~defaults.RuntimeStageWaveformsUsed && defaults.ReceiverObservationSHA256=="" && ...
    isnan(defaults.ObservationStartSample));
fprintf('RECEIVED_WAVEFORM_EVIDENCE_PASS complete_capture_only=1 no_decode_inference=1\n');
ok=true;
end
