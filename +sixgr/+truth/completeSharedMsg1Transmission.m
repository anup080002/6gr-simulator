function [state,observed]=completeSharedMsg1Transmission(state,item)
% UE-only completion: no gNB detector, TA, cell response or receiver row.
assert(isstruct(item) && isscalar(item) && item.Kind=="Msg1TX", ...
    'sixgr:truth:InvalidMsg1TXCompletion','Require the original Msg1 TX callback.');
ue=item.UE;
assert(isfield(state,'PendingRAAttempts') && numel(state.PendingRAAttempts)>=ue && ...
    ~isempty(state.PendingRAAttempts{ue}) && isfield(state,'RARetryByUE') && ...
    numel(state.RARetryByUE)>=ue && ~isempty(state.RARetryByUE{ue}), ...
    'sixgr:truth:MissingMsg1TXAttempt','The original UE attempt and retry owner must still exist.');
done=string(sixgr.util.structGet(state,'CompletedMsg1TransmissionIDs',strings(0,1)));
assert(~any(done==string(item.ID)),'sixgr:truth:DuplicateMsg1Transmission', ...
    'Consume an original TX completion only once.');
attempt=state.PendingRAAttempts{ue}; cp=attempt.Continuation;
assert(isempty(sixgr.util.structGet(attempt,'Received',[])), ...
    'sixgr:truth:UndeliveredRAStage','Do not replace original undelivered receiver evidence.');
[result,next]=sixgr.phy.ra.runFourStepRA(attempt.Config,'Continuation',cp, ...
    'StageAction','complete_msg1_transmission','Msg1TransmissionOwner',state.SharedWaveformStream, ...
    'Msg1TransmissionCompletion',item);
retry=state.RARetryByUE{ue}.transmitted(result.Msg1TransmissionCompletion.ActiveEndTicksExclusive);
assert(isequaln(next.RAConfig,cp.RAConfig) && isequaln(next.RARReceiver,cp.RARReceiver) && ...
    isempty(fieldnames(next.Detection)) && isempty(fieldnames(next.TimingAdvance)), ...
    'sixgr:truth:Msg1TXChangedReceiverState','Emission cannot manufacture gNB or received-RAR state.');
attempt.Continuation=next;
attempt.Msg1TransmissionCompletion=result.Msg1TransmissionCompletion;
% Do not set attempt.Received: this is a physical TX receipt, not a receiver
% result for the legacy control-trial publication path.
state.PendingRAAttempts{ue}=attempt;
state.RARetryByUE{ue}=retry;
state.CompletedMsg1TransmissionIDs=[done(:);string(item.ID)];
proof=result.Msg1TransmissionCompletion;
tx=cp.Msg1Tx;p=item.Context.Prepared;
tx.TransmitPortResourceGrid=p.TransmitPortResourceGrid;
tx.TransmitProjectionMatrix=p.TransmitProjectionMatrix;
tx.TransmitProjectionMatrixSHA256=p.TransmitProjectionMatrixSHA256;
tx.WaveformStartSample=proof.TransmitStartSample;
observed=sixgr.truth.buildObservedREAllocation(tx,'Channel','PRACH','Direction','UL', ...
    'AbsoluteSlot',cp.RAConfig.PRACHAbsoluteSlot,'CellID',cp.RAConfig.ServingCell, ...
    'UEID',ue,'AllocationID',string(item.ID));
observed.observation_start_sample=repmat(proof.TransmitStartSample,height(observed),1);
observed.observation_end_sample_exclusive=repmat(proof.ActiveEndSample,height(observed),1);
observed.observation_sample_rate_hz=repmat(proof.SampleRateHz,height(observed),1);
root=attempt.Config.run.rootRunFolder;
folder=fullfile(root,'control','ue_msg1_transmissions');sixgr.util.ensureFolder(folder);
sixgr.util.jsonWrite(fullfile(folder,string(item.ID)+'.json'),proof);
end
