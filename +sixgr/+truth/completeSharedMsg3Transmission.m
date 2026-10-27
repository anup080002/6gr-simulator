function [state,observed]=completeSharedMsg3Transmission(state,item)
% UE transmission is not a gNB PUSCH decision.
ue=item.UE;attempt=state.PendingRAAttempts{ue};cp=attempt.Continuation;
proof=sixgr.truth.validateMsg3TransmissionCompletion(state.SharedWaveformStream,item,cp);
done=string(sixgr.util.structGet(state,'CompletedMsg3TransmissionIDs',strings(0,1)));
assert(~any(done==string(item.ID))&&isempty(attempt.Received), ...
    'sixgr:truth:DuplicateMsg3Transmission','Complete this original TX once without replacing a receiver result.');
attempt.Msg3TransmissionCompletion=proof;
cp.Result.Msg3TransmissionCompletion=proof;
cp.Result.Msg3TransmissionCompleted=true;
cp.Result.Msg3ReceiverExecuted=false;
% Keep the UE checkpoint prepared. Its independent contention observer may
% receive a real Msg4 before/after the separate cell Msg3 result is published.
attempt.Continuation=cp;state.PendingRAAttempts{ue}=attempt;
state.CompletedMsg3TransmissionIDs=[done(:);string(item.ID)];
tx=cp.Msg3Tx;p=item.Context.Prepared;
observed=sixgr.truth.buildObservedREAllocation(tx,'Channel','PUSCH','Direction','UL', ...
    'AbsoluteSlot',cp.RAConfig.Msg3Slot,'CellID',cp.RAConfig.ServingCell, ...
    'UEID',ue,'AllocationID',string(item.ID));
observed.observation_start_sample=repmat(proof.TransmitStartSample,height(observed),1);
observed.observation_end_sample_exclusive=repmat(proof.ActiveEndSample,height(observed),1);
observed.observation_sample_rate_hz=repmat(proof.SampleRateHz,height(observed),1);
folder=fullfile(attempt.Config.run.rootRunFolder,'control','ue_msg3_transmissions');
sixgr.util.ensureFolder(folder);sixgr.util.jsonWrite(fullfile(folder,string(item.ID)+'.json'),proof);
end
