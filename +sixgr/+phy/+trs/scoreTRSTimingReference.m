function timing=scoreTRSTimingReference(timing,reception)
% Post-reception timing accuracy, never timing acquisition or compensation.
% Compare with the correlation peak of the SAME executed desired link. A
% fading channel's arrival includes propagation/filter delay, unlike the
% separately reported injected RF timing offset. No new channel execution.
p=reception.Prepared;
reference=reception.DesiredReferenceObservation;
assert(isa(reference,'sixgr.phy.waveform.WaveformObservationBuffer') && ...
    reference.isComplete() && reference.StartSample==reception.Observation.StartSample && ...
    reference.EndSampleExclusive==reception.Observation.EndSampleExclusive && ...
    reference.SampleRateHz==p.SampleRateHz, ...
    'sixgr:phy:trs:TimingScoringClockMismatch');
wave=reference.readComplete();
alreadyAligned=isfinite(double(sixgr.util.structGet( ...
    reception,'RecordedReceiverTimingOffset_samples',NaN)));
delay=0;
if ~alreadyAligned
    % The shared desired-link plane includes TX timing but precedes RX RF.
    % Only the actually executed RX delay belongs in this clock conversion.
    replay=reception.Replay;
    segments=replay.ReceiveStreamExecutionSegments;
    delays=nan(numel(segments),1);
    for k=1:numel(segments)
        endpoints=segments{k}.Execution.RX;
        e=endpoints(string({endpoints.ID})==string(replay.ReceiverID));
        assert(isscalar(e),'sixgr:phy:trs:TimingScoringReceiverIdentity');
        if isequal(e.Replay.TimingOffsetApplied,false)
            delays(k)=0;
        else
            delays(k)=double(e.Replay.InjectedTimingOffset_samples);
        end
    end
    assert(~isempty(delays) && all(isfinite(delays)) && all(delays==delays(1)), ...
        'sixgr:phy:trs:TimingScoringRXTransition', ...
        'Time-varying RX delay requires a retained sample mapping, not a scalar correction.');
    delay=delays(1);
end
source="same_executed_desired_link_TRS_correlation_peak_plus_recorded_RX_clock_delay_scoring_only";
for k=1:height(timing.Table)
    index=find([p.Tx.SlotResources.Slot]==timing.Table.Slot(k));
    assert(isscalar(index),'sixgr:phy:trs:TimingScoringResourceIdentity');
    resource=p.Tx.SlotResources(index);
    a=double(p.Tx.SlotTable.StartSample1Based(index));
    b=double(p.Tx.SlotTable.EndSample1Based(index));
    assert(a>=1 && b<=size(wave,1),'sixgr:phy:trs:IncompleteTimingScoringCapture');
    ideal=double(nrTimingEstimate(resource.Carrier,wave(a:b,:), ...
        resource.Indices,resource.Symbols,'SampleRate',p.SampleRateHz,'Nfft',p.Tx.OFDM.Nfft));
    timing.Table.TrueTimingOffset_samples(k)=ideal+delay;
    timing.Table.TimingScoringReferenceSource(k)=source;
    timing.Table.TimingTruthReceiverEstimatorInput(k)=false;
    timing.Table.TimingError_samples(k)=NaN;
    if timing.Table.TRSTimingEstimateAvailable(k)
        timing.Table.TimingError_samples(k)= ...
            timing.Table.EstimatedTimingOffset_samples(k)-(ideal+delay);
    end
end
timing.TrueTimingOffset_samples=median(timing.Table.TrueTimingOffset_samples,'omitnan');
timing.TimingError_samples=median(timing.Table.TimingError_samples,'omitnan');
timing.TimingScoringReferenceSource=source;
end
