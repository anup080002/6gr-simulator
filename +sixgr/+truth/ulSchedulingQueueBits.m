function bits=ulSchedulingQueueBits(state)
% Scheduler view is received demand only when explicit MAC transport is active.
p=sixgr.util.structGet(state,'ULMACPolicy',struct('Enabled',false));
if ~p.Enabled
    bits=double(state.ULQueueBits); return;
end
bits=zeros(size(state.ULQueueBits));
if ~isfield(state,'SharedGNBBufferStates'), return; end
now=state.SharedWaveformStream.Events.NextSampleIndex;
for u=1:numel(bits)
    if numel(state.SharedGNBBufferStates)<u || isempty(state.SharedGNBBufferStates{u}), continue; end
    owner=state.SharedGNBBufferStates{u}; scope=owner.Scope;
    cellID=double(state.CurrentServingIdx(u));
    if cellID~=scope.CellID || sixgr.truth.CoupledRadioIdentity.resolve(state,u,cellID)~=scope.RNTI || ...
            double(sixgr.util.structGet(state.CfgMobility,'protocol.configuration_epoch',NaN))~=scope.ConfigurationEpoch
        continue; % Never carry an old received backlog into a new radio identity.
    end
    estimate=owner.estimate(scope,now,floor(p.ReceivedReportMaxAge_s*scope.SampleRateHz),p.SRProbeBytes);
    bits(u)=8*estimate.BudgetBytes;
end
end
