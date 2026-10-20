function evidence=receivedWaveformEvidence(observation)
%RECEIVEDWAVEFORMEVIDENCE Provenance of actual decoder-input samples.
% No success flag, transmitter samples or configured duration can establish
% reception. Hash the completed input before timing/frequency compensation.
evidence=struct('ObservationStartSample',NaN, ...
    'ObservationEndSampleExclusive',NaN,'ObservationSampleRateHz',NaN, ...
    'ObservationCompletionTime_s',NaN,'ObservationCoverageSource',"", ...
    'RuntimeStageWaveformsUsed',false,'ReceiverObservationSHA256',"", ...
    'ReceiverObservationHashPlane',"",'ReceiverObservationHashSerialization',"");
if nargin==0, return; end
assert(isa(observation,'sixgr.phy.waveform.WaveformObservationBuffer') && ...
    isscalar(observation),'sixgr:link:ReceivedObservationRequired', ...
    'Waveform evidence requires the actual received buffer.');
digest=observation.sampleHash(); % Reject gaps; hash immutable received samples once.
evidence.ObservationStartSample=observation.StartSample;
evidence.ObservationEndSampleExclusive=observation.EndSampleExclusive;
evidence.ObservationSampleRateHz=observation.SampleRateHz;
evidence.ObservationCompletionTime_s=observation.EndSampleExclusive/observation.SampleRateHz;
evidence.ObservationCoverageSource="complete_contiguous_received_sample_buffer";
evidence.RuntimeStageWaveformsUsed=true;
evidence.ReceiverObservationSHA256=digest;
evidence.ReceiverObservationHashPlane="actual_receiver_input_before_synchronization";
evidence.ReceiverObservationHashSerialization="WaveformHash.runtimeArray_class_dimensions_real_imag_double";
end
