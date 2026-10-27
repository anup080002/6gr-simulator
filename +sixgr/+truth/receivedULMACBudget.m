function [state,budget]=receivedULMACBudget(state,cfg,ue,cellID)
[state,scope]=sixgr.truth.ensureULMACOwners(state,cfg,ue,cellID);
p=cfg.phy.mac.uplinkControl;
now=state.SharedWaveformStream.Events.NextSampleIndex;
budget=state.SharedGNBBufferStates{ue}.estimate(scope,now, ...
    floor(p.ReceivedReportMaxAge_s*scope.SampleRateHz),p.SRProbeBytes);
end
