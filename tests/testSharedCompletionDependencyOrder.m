function ok=testSharedCompletionDependencyOrder()
% Pure dependency ordering, not an RF or timing-estimator qualification.
kinds=["PUCCH","PUSCH","SRS","PDSCH","PUCCHTX","DataTX","PUCCHReceiveOnly"];
items=struct('Kind',cellstr(kinds),'Identity',num2cell(1:numel(kinds)));
ordered=sixgr.truth.orderSharedReceiverCompletions(items);
assert(isequal([ordered.Identity],[5 6 3 2 1 4 7]));
assert(isequaln(ordered,items([5 6 3 2 1 4 7])));
assert(isequaln(ordered,sixgr.truth.orderSharedReceiverCompletions(ordered)));
assert(isequaln(items([]),sixgr.truth.orderSharedReceiverCompletions(items([]))));
% Without a completed PUSCH, ordering cannot create one or synthesize a clock.
onlyPUCCH=items(1);
assert(isequaln(onlyPUCCH,sixgr.truth.orderSharedReceiverCompletions(onlyPUCCH)));
% Same-clock control reception must be reduced before SRS power binding.
extra=struct('Kind',{'BindSRSPower','PDCCH','PrepareULData'},'Identity',{8,9,10});
ordered=sixgr.truth.orderSharedReceiverCompletions([extra items]);
assert(isequal([ordered.Identity],[5 6 3 2 9 10 1 4 7 8]));
fprintf('SHARED_COMPLETION_DEPENDENCY_ORDER_PASS identity_preserved=1 no_future_observation_added=1\n');
ok=true;
end
