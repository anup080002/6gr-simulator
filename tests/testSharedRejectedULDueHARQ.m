function ok=testSharedRejectedULDueHARQ()
% Actual DL TX + actual UL control rejection + scheduled PUSCH UCI RX.
% UE DL decoding intentionally unexecuted; not a missed-DCI-rate campaign.
[ok,result]=testSharedRejectedULReceiveOnly(true);
% Strengthened regression after the preserved cc35e774 false-ACK observation.
% The raw MAT/CSV are already written before these assertions. One physical
% episode is a regression, not false-ACK/missed-ACK campaign qualification.
e=result.Receiver.UCIReceiverEvidence.HARQACK;
assert(e.ShortConfidenceApplicable && ~e.ShortConfidence.Accepted && ~e.DecodeUsable && ...
    e.ShortConfidence.PolicySource=="explicit_receiver_policy", ...
    'test:PUSCHShortUCIFalseACK','The actual no-UE-PUSCH capture must not produce usable HARQ bits.');
assert(~result.IndependentHARQObservation.DecodeOk && result.IndependentHARQObservation.DTXFlag, ...
    'test:PUSCHShortUCIRejectionNotApplied','The normal feedback reducer must preserve the receiver erasure.');
fprintf('SHARED_REJECTED_UL_SHORT_UCI_ERASURE_PASS physical_episodes=1 detector_qualified=0\n');
end
