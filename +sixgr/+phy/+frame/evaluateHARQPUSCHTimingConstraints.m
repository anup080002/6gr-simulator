function [valid,reason,evidence]=evaluateHARQPUSCHTimingConstraints(feedback,constraints)
% Apply 38.213 9.2.5 to each physically overlapping scheduled interval.
% Do not move an issued PUSCH/PUCCH, encode UCI, or infer receiver success.
valid=true; reason=""; evidence=struct([]);
if isempty(constraints), return; end
for k=1:numel(constraints)
    c=constraints(k);
    ticks=[c.ULTargetTick c.ULTargetEndTick c.ULWaveformPlacementTick ...
        c.PDSCHEndTick c.PDCCHEndTick c.PDSCHProcessingTicks c.PDCCHProcessingTicks];
    assert(isa(ticks,'int64') && all(ticks>=0) && ...
        c.ULTargetEndTick>c.ULTargetTick && c.ULWaveformPlacementTick<=c.ULTargetTick && ...
        c.PDSCHProcessingTicks>0 && c.PDCCHProcessingTicks>0 && ...
        c.PDSCHProcessingTicks==c.Budget.PDSCHTicks && c.PDCCHProcessingTicks==c.Budget.PDCCHTicks && ...
        feedback.SourceEndTick==c.PDSCHEndTick && feedback.TargetMu==c.FeedbackMu && ...
        string(feedback.ScheduledCCID)==c.ScheduledCCID, ...
        'sixgr:phy:frame:InvalidHARQPUSCHTimingConstraint', ...
        'Joint processing evidence must match this exact PDSCH endpoint, feedback grid and carrier.');
end
% An overlapping group is transitive: a second PUSCH can extend the group
% even if it does not directly overlap the original PUCCH interval.
group=false(size(constraints)); lo=feedback.TargetTick; hi=feedback.TargetEndTick;
while true
    next=[constraints.ULTargetTick]<hi & lo<[constraints.ULTargetEndTick];
    if isequal(next,group), break; end
    group=next;
    lo=min([lo constraints(group).ULTargetTick]);
    hi=max([hi constraints(group).ULTargetEndTick]);
end
first=min([feedback.WaveformPlacementTick constraints(group).ULWaveformPlacementTick]);
for k=reshape(find(group),1,[])
    c=constraints(k);
    n1Ready=c.PDSCHEndTick+c.PDSCHProcessingTicks;
    n2Ready=c.PDCCHEndTick+c.PDCCHProcessingTicks;
    thisValid=first>=n1Ready && first>=n2Ready;
    row=struct('ULGrantContextID',c.ULGrantContextID, ...
        'EarliestAdvancedULStartTick',first,'PDSCHReadyTick',n1Ready, ...
        'PDCCHReadyTick',n2Ready,'Valid',thisValid,'Budget',c.Budget);
    if isempty(evidence), evidence=row; else, evidence(end+1)=row; end %#ok<AGROW>
    if ~thisValid
        valid=false;
        if first<n1Ready, reason="insufficient_harq_pusch_n1_multiplexing_time";
        else, reason="insufficient_harq_pusch_n2_multiplexing_time"; end
    end
end
end
