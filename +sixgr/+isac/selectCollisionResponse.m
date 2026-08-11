function [selected,evaluation] = selectCollisionResponse(candidates,budget,measurement)
%SELECTCOLLISIONRESPONSE Transparent coherency-budget feasibility selector.

arguments
    candidates struct
    budget (1,1) struct
    measurement (1,1) string
end
if isempty(candidates)
    error("sixgr:isac:NoCollisionCandidates","No collision responses were supplied.");
end
measurement = lower(strtrim(measurement));
names = strings(numel(candidates),1);
segments = zeros(numel(candidates),1);
minLength = zeros(numel(candidates),1);
phaseResidual = zeros(numel(candidates),1);
timingResidual = zeros(numel(candidates),1);
frequencyResidual = zeros(numel(candidates),1);
cost = zeros(numel(candidates),1);
relationClass=strings(numel(candidates),1);
feasible = false(numel(candidates),1);
reason = strings(numel(candidates),1);
for i = 1:numel(candidates)
    c = candidates(i);
    names(i) = string(c.Name);
    segments(i) = double(c.CoherentSegmentCount);
    minLength(i) = double(c.MinimumSegmentLength);
    phaseResidual(i) = double(c.ResidualPhaseDeg);
    timingResidual(i) = double(c.ResidualTimingBins);
    frequencyResidual(i) = double(c.ResidualFrequencyHz);
    cost(i) = double(c.Cost);
    if isfield(c,"RelationClass")
        relationClass(i)=lower(string(c.RelationClass));
    else
        relationClass(i)="preserved";
    end
    checks = [segments(i) <= double(budget.MaxCoherentSegments), ...
        minLength(i) >= double(budget.MinimumSegmentLength), ...
        phaseResidual(i) <= double(budget.MaximumResidualPhaseDeg), ...
        timingResidual(i) <= double(budget.MaximumResidualTimingBins)];
    if isfield(budget,"RequiredRelationClass")
        checks(end+1)=localRelationRank(relationClass(i)) <= ...
            localRelationRank(string(budget.RequiredRelationClass)); %#ok<AGROW>
    end
    if contains(measurement,"doppler")
        checks(end+1) = frequencyResidual(i) <= double(budget.MaximumResidualFrequencyHz); %#ok<AGROW>
    end
    if contains(measurement,"angle")
        checks(end+1) = logical(c.CrossPortRelationAvailable); %#ok<AGROW>
    end
    feasible(i) = all(checks);
    if feasible(i)
        reason(i) = "all_measurement_specific_budget_checks_pass";
    else
        reason(i) = "one_or_more_measurement_specific_budget_checks_fail";
    end
end
evaluation = table(names,relationClass,segments,minLength,phaseResidual,timingResidual, ...
    frequencyResidual,cost,feasible,reason,repmat(measurement,numel(candidates),1), ...
    'VariableNames',{'Response','RelationClass','CoherentSegments','MinimumSegmentLength', ...
    'ResidualPhaseDeg','ResidualTimingBins','ResidualFrequencyHz','Cost', ...
    'Feasible','Reason','Measurement'});
eligible = find(feasible);
if isempty(eligible)
    fallback="";
    if isfield(budget,"FallbackResponseOrder")
        order=string(budget.FallbackResponseOrder(:));
        fallback=order(find(ismember(order,names),1));
    end
    selected = struct("Name",fallback,"Feasible",false,"FallbackRequired",true, ...
        "Measurement",measurement);
else
    [~,relative] = min(cost(eligible));
    index = eligible(relative);
    selected = struct("Name",names(index),"Feasible",true, ...
        "FallbackRequired",false,"Measurement",measurement);
end
end

function rank=localRelationRank(value)
classes=["preserved","known_transform","estimated_transform", ...
    "bounded_residual","unknown_unavailable"];
rank=find(classes==lower(strtrim(value)),1)-1;
if isempty(rank)
    error("sixgr:isac:UnknownRelationClass","Unknown relation class %s.",value);
end
end
