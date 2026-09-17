function ok=testSharedRejectedULCSI()
% Actual missed UL command, scheduled CSI receiver and no prepared UE PUSCH.
% One physical negative episode, not statistical detector qualification.
[ok,result]=testSharedRejectedULReceiveOnly(false,true);
assert(~isempty(result.IndependentCSIObservation) && ~result.TransmittedTBScored && ...
    ~result.PreparedTransmitterConsumed && ~result.ULHARQStateCommitted);
fprintf('SHARED_REJECTED_UL_CSI_PASS physical_episodes=1 detector_qualified=0\n');
end
