function hypothesis=buildScheduledPUCCHHARQReception(state,cfg,ue,targetSlot,observationID)
% Require the selected gNB transport to be PUCCH, never ignore UL scheduling.
hypothesis=sixgr.truth.buildScheduledHARQTransportReception(state,cfg,ue,targetSlot,observationID);
assert(hypothesis.SelectedTransport=="PUCCH", ...
    'sixgr:truth:UnresolvedScheduledPUSCHReceiveHypothesis', ...
    'The gNB scheduled overlapping PUSCH; this PUCCH-only receiver cannot consume the feedback.');
end
