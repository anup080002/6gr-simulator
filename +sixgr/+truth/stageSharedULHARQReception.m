function state=stageSharedULHARQReception(state,cfg,grant,observation,decision)
% Value-state preflight/commit. Does not call onTx or modify any TX, delivery,
% scheduler, BER, BLER or throughput ledger.
[fresh,~]=sixgr.truth.prepareSharedULHARQReception(state,cfg,grant,observation);
assert(isequaln(decision.ReceiverAttempt,fresh), ...
    'sixgr:truth:ChangedULHARQReceiverState','The retained decoder attempt no longer matches the scheduled receiver state.');
state.SharedGNBULHARQReceivers=sixgr.truth.resolveULHARQReceiverState( ...
    sixgr.util.structGet(state,'SharedGNBULHARQReceivers',{}),fresh.Attempt,decision);
end
