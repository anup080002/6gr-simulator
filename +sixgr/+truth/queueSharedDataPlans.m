function state=queueSharedDataPlans(state,cfg,multiUser,userCfg,grants,direction,snr,frame,laStates)
plans=sixgr.truth.GrantPreparation.prepareCoupledGrantBatch(state,cfg,multiUser,userCfg,grants,direction,snr,frame,laStates,grants,0,struct([]));
assert(numel(plans)==numel(grants) && all([plans.Valid]), ...
    'sixgr:truth:SharedGrantPreparationIncomplete','Every admitted grant requires an actual transmit preparation.');
for plan=reshape(plans,1,[])
    state=sixgr.truth.queuePreparedSharedDataPlan(state,cfg,multiUser,plan,direction,snr);
end
end
