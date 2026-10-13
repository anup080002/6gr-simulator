function pending=awaitingUnselectedPUCCHDisposition(state,rows,key)
% A completed, unselected PUCCH capture can precede the selected PUSCH's
% guarded receive-window end. Its already transmitted producer must wait
% for that receiver, not be re-armed or falsely marked decoded/executed.
pending=false;
completed=sixgr.util.structGet(state,'SharedUnselectedPUCCHObservations',{});
hit=find(cellfun(@(item)isfield(item.Context,'Key') && ...
    string(item.Context.Key)==string(key),completed));
if ~isscalar(hit) || isempty(rows), return; end
c=completed{hit}.Context;
if ~isfield(c,'Prepared') || ~isfield(c,'FeedbackRows') || ...
        ~isfield(c,'TransportSelection'), return; end
if ~all(ismember(string(rows.PUCCHGrantId),string(c.FeedbackRows.PUCCHGrantId)))
    return; % A new late obligation cannot join the frozen transmitted UCI.
end
selection=c.TransportSelection;
owner=state.SharedWaveformStream;
observations=owner.Pending;
matches=false(numel(observations),1);
for k=1:numel(observations)
    p=observations(k);
    if ~any(p.Kind==["PUSCH","PUSCHReceiveOnly"]) || ~isfield(p.Context,'Grant')
        continue;
    end
    grant=p.Context.Grant;
    matches(k)=p.UE==selection.UEIndex && grant.UEIndex==selection.UEIndex && ...
        double(grant.Slot)==selection.TargetSlot && ...
        string(grant.PHYGrant.GrantContextId)==selection.ULGrantContextID && ...
        all(double(rows.RNTI)==double(grant.RNTI)) && ...
        double(sixgr.util.structGet(p.Context,'ReceiveEndSampleExclusive',NaN))> ...
        owner.Events.NextSampleIndex;
end
selected=find(matches);
if ~isscalar(selected), return; end
[bound,producer]=owner.readUnselectedPUCCHForPUSCH(observations(selected).Context.Grant);
if ~isequaln(bound,selection) || ~isfield(producer,'FeedbackRows') || ...
        ~isequaln(producer.FeedbackRows,c.FeedbackRows), return; end
% No scheduled intent or preparation-only record can satisfy this boundary.
identity=sixgr.truth.validateUnselectedPUCCHTransmission(state,bound,producer);
pending=~isempty(fieldnames(identity));
end
