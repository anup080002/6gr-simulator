function ok=testReferenceSignalSINREvidence()
% Struct fixtures verify evidence binding only, not waveform performance.
for channel=["SRS","TRS"]
    prefix="MeasuredTrialSINR";
    if channel=="SRS", prefix="SINR"; end
    receiver=struct('ChannelEstimateAvailable',true, ...
        'SINRMeasurementDomain',"fixture_pilot_RE_residual", ...
        'PowerReferencePlane',"fixture_received_grid");
    receiver.(prefix+"_dB")=12.2599459730789;
    receiver.(prefix+"Source")="fixture_actual_receiver_output";
    receiver.(prefix+"ValueStatus")="OK";
    initial=struct('DetectionSuccess',false,'StrictOk',false, ...
        'PUSCHSchedulingSINRAnchor_dB',NaN,'ReceiverHestSINRApplicable',false);
    row=sixgr.truth.bindReferenceSignalSINREvidence(initial,receiver,channel);
    assert(row.ReceiverHestSINRApplicable && ...
        row.ReceiverHestSINR_dB==receiver.(prefix+"_dB") && ...
        row.MeasuredTrialSINR_dB==row.ReceiverHestSINR_dB && ...
        row.ReceiverHestSINRSource==receiver.(prefix+"Source") && ...
        row.ReceiverHestSINRValueStatus=="OK");
    assert(~row.DetectionSuccess && ~row.StrictOk && isnan(row.PUSCHSchedulingSINRAnchor_dB));
    receiver.ChannelEstimateAvailable=false;
    row=sixgr.truth.bindReferenceSignalSINREvidence(initial,receiver,channel);
    assert(~row.ReceiverHestSINRApplicable && isfinite(row.ReceiverHestSINR_dB));
    receiver.ChannelEstimateAvailable=true;
    receiver.(prefix+"ValueStatus")="NOT_AVAILABLE";
    row=sixgr.truth.bindReferenceSignalSINREvidence(initial,receiver,channel);
    assert(~row.ReceiverHestSINRApplicable && row.ReceiverHestSINRValueStatus=="NOT_AVAILABLE");
    receiver=rmfield(receiver,prefix+"_dB");
    row=sixgr.truth.bindReferenceSignalSINREvidence(initial,receiver,channel);
    assert(~row.ReceiverHestSINRApplicable && isnan(row.ReceiverHestSINR_dB));
end
ok=true;
end
