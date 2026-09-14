function evidence=assertNoScheduledPUSCHOverlap(state,cfg,ue,targetSlot,symbolAllocation)
% Absence proof from actual gNB control TX, not UE acceptance.
[overlapping,evidence]=sixgr.truth.findScheduledPUSCHOverlap(state,cfg,ue,targetSlot,symbolAllocation);
assert(isempty(overlapping),'sixgr:truth:UnresolvedScheduledPUSCHReceiveHypothesis', ...
    'An overlapping scheduled PUSCH requires its own independent UCI receiver.');
end
