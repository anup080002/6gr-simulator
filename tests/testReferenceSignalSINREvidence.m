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
    if channel=="TRS"
        receiver.SignedPilotSINRLinear=10^(receiver.(prefix+"_dB")/10);
        receiver.PilotPowerEvidenceJSON=string(jsonencode(struct( ...
            'Scope',"publication_contract_fixture",'SignedSINR',receiver.SignedPilotSINRLinear)));
    end
    initial=struct('DetectionSuccess',false,'StrictOk',false, ...
        'PUSCHSchedulingSINRAnchor_dB',NaN,'ReceiverHestSINRApplicable',false);
    row=sixgr.truth.bindReferenceSignalSINREvidence(initial,receiver,channel);
    assert(row.ReceiverHestSINRApplicable && ...
        row.ReceiverHestSINR_dB==receiver.(prefix+"_dB") && ...
        row.MeasuredTrialSINR_dB==row.ReceiverHestSINR_dB && ...
        row.ReceiverHestSINRSource==receiver.(prefix+"Source") && ...
        row.ReceiverHestSINRValueStatus=="OK");
    assert(~row.DetectionSuccess && ~row.StrictOk && isnan(row.PUSCHSchedulingSINRAnchor_dB));
    if channel=="TRS"
        assert(row.SignedPilotSINRLinear==receiver.SignedPilotSINRLinear && ...
            row.PilotPowerEvidenceJSON==receiver.PilotPowerEvidenceJSON);
    end
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
    if channel=="TRS"
        receiver.SignedPilotSINRLinear=-.1;
        receiver.PilotPowerEvidenceJSON='{"SignedSINR":-0.1}';
        row=sixgr.truth.bindReferenceSignalSINREvidence(initial,receiver,channel);
        signedEvidence=jsondecode(row.PilotPowerEvidenceJSON);
        assert(isnan(row.MeasuredTrialSINR_dB) && row.SignedPilotSINRLinear==-.1 && ...
            signedEvidence.SignedSINR==-.1);
    end
end
ok=true;
end
