function [observation,evidence]=compensateReceivedAGC(raw,segments,receiverID)
% Digital calibration AFTER the actual ADC. The receiver knows its applied
% analogue gain controls, not the channel or wanted noiseless waveform.
% Division does not undo clipping, quantization, jitter, noise or fading.
x=raw.readComplete(); first=raw.StartSample; stop=raw.EndSampleExclusive;
gain=nan(size(x,1),1); coverage=false(size(gain)); enabled=false;
gainOnlyRF=true;
for k=1:numel(segments)
    segment=segments{k}; a=max(first,segment.StartSample); b=min(stop,segment.EndSampleExclusive);
    if b<=a, continue; end
    e=segment.Execution;
    i=find(string({e.RX.ID})==string(receiverID),1);
    if isempty(i), error('sixgr:phy:rx:AGCReceiverIdentity','Actual RF execution does not identify this receiver.'); end
    r=e.RX(i).Replay;
    % A recorded inverse AGC gain preserves the original noise law only
    % when no other configured/applied RX stage can distort those samples.
    fields={'RFConfiguredStageCount','RFAppliedStageCount','AGCEnabled','AGCApplied'};
    gainOnlyRF=gainOnlyRF && all(isfield(r,fields)) && ...
        r.RFConfiguredStageCount==double(r.AGCEnabled) && ...
        r.RFAppliedStageCount==double(r.AGCApplied);
    if string(r.AGCControlModel)=="disabled"
        g=zeros(b-a,1);
    else
        enabled=true;
        trace=sixgr.util.structGet(r,'AGCStreamTrace',struct());
        if ~all(isfield(trace,{'AppliedGain_dB','StartSample','EndSampleExclusive'})) || ...
                trace.StartSample~=segment.StartSample || trace.EndSampleExclusive~=segment.EndSampleExclusive || ...
                numel(trace.AppliedGain_dB)~=segment.EndSampleExclusive-segment.StartSample
            error('sixgr:phy:rx:ActualAGCTraceRequired','Gain compensation needs the per-sample APPLIED gain, never the next decision or a block RMS guess.');
        end
        g=double(trace.AppliedGain_dB(a-segment.StartSample+(1:b-a)));
        g=g(:);
    end
    index=a-first+(1:b-a);
    if any(coverage(index)) || any(~isfinite(g))
        error('sixgr:phy:rx:InvalidAGCTraceCoverage','Gain evidence must cover every actual receive sample exactly once.');
    end
    gain(index)=g; coverage(index)=true;
end
if ~all(coverage)
    error('sixgr:phy:rx:IncompleteAGCTraceCoverage','Unobserved gain cannot be replaced by unity.');
end
linear=10.^(gain/20);
if any(~isfinite(linear)|linear<=0)
    error('sixgr:phy:rx:InvalidAppliedAGCScale','Applied analogue gain must have a finite positive voltage scale.');
end
y=x./cast(linear,'like',x);
dispatcher=sixgr.phy.waveform.WaveformReceiveDispatcher(raw.SampleRateHz,size(y,2),first);
dispatcher.register('digital_gain_compensated',first,stop);
done=dispatcher.dispatch(sixgr.phy.waveform.WaveformChunk(y,first),raw.SampleRateHz);
observation=done.Observation;
evidence=struct('Applied',enabled,'Source',"actual_receiver_applied_analog_gain_trace_after_ADC", ...
    'GainOnlyRFExecuted',gainOnlyRF, ...
    'InputPlane',"actual_post_rx_rf_post_adc_samples", ...
    'OutputPlane',"digital_gain_compensated_received_samples_before_fft", ...
    'StartSample',first,'EndSampleExclusive',stop, ...
    'ClippingReconstructed',false,'QuantizationRemoved',false, ...
    'AppliedGainMin_dB',min(gain),'AppliedGainMax_dB',max(gain));
end
