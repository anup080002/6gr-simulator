function bit = resolveReceivedHARQBit(observed, position, expectedAck)
% Interpret received UCI, never the scoring-side expected payload.
% DTX here means no usable ACK/NACK at this position, not proof of no TX.
arguments
    observed (1,1) struct
    position (1,1) double {mustBeInteger,mustBePositive}
    expectedAck (1,1) logical
end
usable = logical(sixgr.util.structGet(observed,'DecodeOk',false));
dtx = logical(sixgr.util.structGet(observed,'DTXFlag',false));
decoded = sixgr.util.structGet(observed,'DecodedBits',int8([]));
assert(isscalar(usable) && isscalar(dtx), ...
    'sixgr:truth:InvalidReceivedHARQObservation','Receiver validity must be scalar.');
hasBit = usable && ~dtx && position<=numel(decoded);
if hasBit
    value = double(decoded(position));
    assert(isreal(value) && isfinite(value) && any(value==[0 1]), ...
        'sixgr:truth:InvalidReceivedHARQBit','A usable decoded ACK/NACK must be binary.');
end
ack = hasBit && logical(decoded(position));
outcome = "DTX"; reason = "receiver_feedback_unusable";
if hasBit
    outcome = "NACK";
    if ack, outcome = "ACK"; end
    reason = "decoded_uci_bit";
elseif dtx
    reason = "receiver_reported_dtx";
elseif usable
    reason = "decoded_bit_unavailable";
end
bit = observed;
bit.ExpectedAck = expectedAck;
bit.DecodeOk = hasBit;
bit.ObservedAck = ack;
bit.DecodedAck = ack;
bit.FalseAck = hasBit && ~expectedAck && ack;
bit.FalseNack = hasBit && expectedAck && ~ack;
bit.MissedFeedback = ~hasBit;
bit.FeedbackOutcome = outcome;
bit.FeedbackOutcomeReason = reason;
end
