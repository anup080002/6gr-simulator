function [rx,info] = completePDCCHReception(prepared,observation,options)
%COMPLETEPDCCHRECEPTION Decode already-received samples; no TX/RF/channel.
arguments
    prepared (1,1) struct
    observation (1,1) sixgr.phy.waveform.WaveformObservationBuffer
    options.NoiseVariance = []
    options.NoiseOnlyWaveform = []
end
required = ["ExecutionStage","Tx","TxInfo","ReceiverConfig","SampleRateHz","NumSamples","RuntimeStartSample","MinimumReceiveSamples"];
if ~all(isfield(prepared,required))|| ...
        prepared.ExecutionStage~="pdcch_waveform_prepared_not_received"
    error('sixgr:link:InvalidPDCCHPreparation','PDCCH completion requires its retained transmitter preparation.');
end
if ~observation.isComplete()
    error('WAVEFORM:IncompleteObservation','PDCCH decoding requires the entire actual received window.');
end
if observation.SampleRateHz~=prepared.SampleRateHz|| ...
        prepared.NumSamples~=size(prepared.Tx.Waveform,1)|| ...
        observation.EndSampleExclusive-observation.StartSample<prepared.MinimumReceiveSamples
    error('sixgr:link:PDCCHObservationLayoutMismatch', ...
        'PDCCH reception requires the actual monitored symbols at the prepared sample rate.');
end
if isfinite(prepared.RuntimeStartSample) && observation.StartSample~=prepared.RuntimeStartSample
    error('sixgr:link:PDCCHObservationOriginMismatch', ...
        'Received PDCCH samples must retain the scheduled control-slot origin.');
end
if ~isempty(options.NoiseVariance)
    validateattributes(options.NoiseVariance,{'numeric'},{'real','scalar','finite','nonnegative'});
end
samples = observation.readComplete();
if ~isempty(options.NoiseOnlyWaveform)
    validateattributes(options.NoiseOnlyWaveform,{'single','double'},{'2d','finite','size',size(samples)});
end
cfg = prepared.ReceiverConfig;
listLength = sixgr.util.structGet(cfg,'phy.pdcch.listLength',[]);
if ~isempty(listLength)
    validateattributes(listLength,{'numeric'},{'real','scalar','finite','integer','positive'});
end
tx = prepared.Tx;
txInfo = prepared.TxInfo;
[rx,info] = sixgr.phy.dl.PDCCH_Rx(samples,cfg, ...
    'Carrier',tx.Carrier,'PDCCH',tx.PDCCH,'K',numel(tx.DCIBits), ...
    'RNTI',txInfo.RNTI,'PDCCHScramblingRNTI',txInfo.PDCCHScramblingRNTI, ...
    'ExpectedDCIBits',tx.DCIBits,'SampleRate_Hz',prepared.SampleRateHz, ...
    'ListLength',listLength,'NoiseVar',options.NoiseVariance, ...
    'NoiseOnlyWaveform',options.NoiseOnlyWaveform);
info.ObservationStartSample = observation.StartSample;
info.ObservationEndSampleExclusive = observation.EndSampleExclusive;
info.ObservationSampleRateHz = observation.SampleRateHz;
info.ObservationCompletionTime_s = observation.EndSampleExclusive/observation.SampleRateHz;
info.ObservationCoverageSource = "complete_contiguous_received_sample_buffer";
end
