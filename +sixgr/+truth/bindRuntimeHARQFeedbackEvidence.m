function P=bindRuntimeHARQFeedbackEvidence(P,F)
% Join executed data attempts to independently received logical UCI bits.
% No join by payload, TB prefix, CRC result, row order or energy score.
n=height(P);
P.ACK=nan(n,1); P.NACK=nan(n,1); P.DTX=nan(n,1);
P.FeedbackBits=nan(n,1); % Coded air-interface overhead is not one bit/attempt.
P.FeedbackObservationAvailable=false(n,1);
P.FeedbackObservationID=strings(n,1);
P.FeedbackEvidenceStatus=repmat("unavailable_no_associated_received_UCI",n,1);
P.FeedbackTransport=strings(n,1);
P.FeedbackApplied=nan(n,1); P.FeedbackStaleIgnored=nan(n,1);
P.DecodedHARQInformationBits=nan(n,1);
P.FeedbackBitIndex=nan(n,1);
P.FeedbackAvailableAtSample=nan(n,1);
P.FeedbackSampleRateHz=nan(n,1);
P.RTT_ms=nan(n,1); P.RTT_slots=nan(n,1);
P.FeedbackDispositionLatency_ms=nan(n,1);
P.RTTStatus=repmat("unavailable_no_associated_usable_feedback",n,1);
P.RTTDefinition=repmat("executed_data_symbol_TX_start_to_usable_feedback_result_available",n,1);
P.FeedbackEvidenceStatus(string(P.Direction)=="UL")="not_applicable_DL_HARQ_UCI_for_UL_data";
if isempty(F), return; end
required=["SweepPointIndex","PHYGrantContextId","UEIndex","RNTI", ...
    "SourceSlot","HarqID","FeedbackForDirection","FeedbackOutcome", ...
    "ObservedAck","ReceiverUsable","ObservationID","UCITransport", ...
    "HARQFeedbackApplied","StaleFeedbackIgnored","BitIndex", ...
    "AvailableAtSample","ObservationEndSampleExclusive","ObservationSampleRateHz"];
assert(istable(F) && all(ismember(required,string(F.Properties.VariableNames))), ...
    'sixgr:truth:HARQFeedbackObservationSchema', ...
    'Feedback publication requires complete independently received identities and clocks.');
used=false(height(F),1);
for i=1:n
    if string(P.Direction(i))~="DL", continue; end
    context=string(P.PHYGrantContextId(i));
    if strlength(context)==0 || ismissing(context) || ~isfinite(P.SweepPointIndex(i))
        P.FeedbackEvidenceStatus(i)="unavailable_data_attempt_identity";
        continue;
    end
    match=string(F.FeedbackForDirection)=="DL" & ...
        F.SweepPointIndex==P.SweepPointIndex(i) & ...
        string(F.PHYGrantContextId)==context & F.UEIndex==P.UEIndex(i) & ...
        F.RNTI==P.RNTI(i) & F.SourceSlot==P.Slot(i) & F.HarqID==P.HARQProcess(i);
    indices=find(match);
    assert(numel(indices)<=1,'sixgr:truth:AmbiguousHARQFeedbackObservation', ...
        'Multiple receive observations match the same exact data attempt.');
    if isempty(indices), continue; end
    assert(~used(indices),'sixgr:truth:DuplicateHARQAttemptObservation', ...
        'One independently received bit cannot populate duplicate data-attempt rows.');
    used(indices)=true;
    r=F(indices,:); outcome=string(r.FeedbackOutcome);
    assert(isscalar(outcome) && any(outcome==["ACK","NACK","DTX"]), ...
        'sixgr:truth:InvalidHARQFeedbackOutcome','Expected explicit receiver ACK/NACK/DTX.');
    flags=double([r.ReceiverUsable,r.ObservedAck,r.HARQFeedbackApplied,r.StaleFeedbackIgnored]);
    assert(all(isfinite(flags) & (flags==0 | flags==1)) && ...
        logical(r.ReceiverUsable)==(outcome~="DTX") && ...
        logical(r.ObservedAck)==(outcome=="ACK") && ...
        logical(r.HARQFeedbackApplied)~=logical(r.StaleFeedbackIgnored), ...
        'sixgr:truth:ContradictoryHARQFeedbackObservation', ...
        'Do not infer a usable bit from a CRC or reinterpret a missing reception as NACK.');
    assert(isfinite(r.AvailableAtSample) && isfinite(r.ObservationEndSampleExclusive) && ...
        r.AvailableAtSample>=r.ObservationEndSampleExclusive && ...
        isfinite(r.ObservationSampleRateHz) && r.ObservationSampleRateHz>0 && ...
        isfinite(r.BitIndex) && r.BitIndex>=1 && r.BitIndex==fix(r.BitIndex) && ...
        strlength(string(r.ObservationID))>0 && ...
        any(string(r.UCITransport)==["PUCCH","PUSCH"]), ...
        'sixgr:truth:InvalidHARQFeedbackClock','Require actual completed UCI observation evidence.');
    P.ACK(i)=double(outcome=="ACK"); P.NACK(i)=double(outcome=="NACK");
    P.DTX(i)=double(outcome=="DTX");
    P.FeedbackObservationAvailable(i)=true;
    P.FeedbackObservationID(i)=string(r.ObservationID);
    P.FeedbackEvidenceStatus(i)="independently_received_scheduled_HARQ_bit_disposition";
    P.FeedbackTransport(i)=string(r.UCITransport);
    P.FeedbackApplied(i)=double(r.HARQFeedbackApplied);
    P.FeedbackStaleIgnored(i)=double(r.StaleFeedbackIgnored);
    P.DecodedHARQInformationBits(i)=double(r.ReceiverUsable);
    P.FeedbackBitIndex(i)=double(r.BitIndex);
    P.FeedbackAvailableAtSample(i)=double(r.AvailableAtSample);
    P.FeedbackSampleRateHz(i)=double(r.ObservationSampleRateHz);
    clockFields=["DataTransmitSymbolStartSample","DataTransmitSymbolEndSampleExclusive", ...
        "DataTransmitSampleRateHz","RTTSlotDuration_ms"];
    if ~all(ismember(clockFields,string(P.Properties.VariableNames))) || ...
            ~all(isfinite(P{i,cellstr(clockFields)}))
        P.RTTStatus(i)="unavailable_transmitted_symbol_clock";
        continue;
    end
    first=P.DataTransmitSymbolStartSample(i); last=P.DataTransmitSymbolEndSampleExclusive(i);
    fs=P.DataTransmitSampleRateHz(i);
    assert(first>=0 && first==fix(first) && last>first && last==fix(last) && ...
        fs==r.ObservationSampleRateHz && P.RTTSlotDuration_ms(i)>0 && r.AvailableAtSample>=last && ...
        P.DataTransmitTimingSource(i)=="executed_prepared_waveform_origin_and_OFDM_symbol_lengths", ...
        'sixgr:truth:HARQRoundTripClockMismatch','RTT requires exact TX and received-feedback intervals on one executed sample clock.');
    P.FeedbackDispositionLatency_ms(i)=1000*(double(r.AvailableAtSample)-first)/fs;
    if outcome=="DTX"
        P.RTTStatus(i)="unavailable_DTX_disposition_not_usable_feedback";
    else
        P.RTT_ms(i)=P.FeedbackDispositionLatency_ms(i);
        P.RTT_slots(i)=P.RTT_ms(i)/P.RTTSlotDuration_ms(i);
        P.RTTStatus(i)="measured_independent_usable_feedback_completion";
    end
end
end
