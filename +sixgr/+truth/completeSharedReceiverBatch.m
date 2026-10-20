function state=completeSharedReceiverBatch(state,received,onCompleted)
% Commit one already-completed physical event batch before re-arming UCI.
% The stream removes ALL captures at this sample from Pending before the
% callback. A PUSCH completion must not inspect that partial pending view
% while a coincident PUCCH completion still awaits reduction in this batch.
% Keep pilot-before-PUCCH dependencies; never advance the sample clock,
% reopen an encoded occasion, or suppress a genuinely late-feedback error.
received=sixgr.truth.orderSharedReceiverCompletions(reshape(received,1,[]));
for item=received
    receiverScope=sixgr.runtime.ExecutionStageProfiler.scope("receiver_pipeline",string(item.Kind));
    state=onCompleted(state,item);
    clear receiverScope
end
if any(ismember(string({received.Kind}),["PDSCH","PUSCH"]))
    state=sixgr.truth.CoupledTruthRuntime.armSharedPUCCHFeedbackRuntime(state);
end
end
