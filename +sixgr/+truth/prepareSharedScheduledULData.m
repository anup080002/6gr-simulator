function state=prepareSharedScheduledULData(state,item)
c=item.Context; slot=c.Grant.Slot;
pending=sixgr.util.structGet(state,'SharedPendingULGrants',repmat(struct(),0,1));
keys=arrayfun(@(g)sixgr.truth.GrantPreparation.sharedGrantControlKey(g,'UL'),pending);
hit=find(keys==c.Key);
assert(numel(hit)==1,'sixgr:truth:MissingSharedULGrant','The received UL grant must remain uniquely owned until preparation.');
grant=pending(hit);
if sixgr.truth.isPUSCHUCIAvailable(c.PreparationConfig)
    [state,grant]=sixgr.truth.CoupledTruthRuntime.multiplexDueHARQACKOnPUSCHRuntime(state,grant,slot);
end
[grant,blocked]=sixgr.truth.CoupledTruthRuntime.excludeULGrantsCollidingWithPUCCHRuntime(state,grant,slot);
assert(isempty(blocked) && numel(grant)==1, ...
    'sixgr:truth:SharedULControlCollisionUnresolved', ...
    'A received PUSCH grant cannot be emitted over standalone PUCCH; resolve physical UCI ownership before transmission.');
la=sixgr.util.structGet(state,'SharedULLinkAdaptationStates',repmat({struct()},numel(c.UserCfg),1));
state=sixgr.truth.queueSharedDataPlans(state,c.PreparationConfig,state.MultiUser,c.UserCfg,grant, ...
    'UL',c.SNR,grant.Frame,la);
% Keep the admitted calendar entry until the source slot, so SRS/scheduling
% and the due-slot trace see it. The waveform is now immutable.
[pending,grant]=sixgr.truth.GrantPreparation.harmonizeStructArrays(pending,grant);
pending(hit)=grant;
state.SharedPendingULGrants=pending;
end
