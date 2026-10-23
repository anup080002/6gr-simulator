function T=collectAdaptationApplicationEvidence(trials,direction)
%COLLECTADAPTATIONAPPLICATIONEVIDENCE Follow scheduled decisions across trials.
% The after-TB scheduled decision is NOT the before-TB applied decision on the
% same row. Missing future execution is censored, not an adaptation failure.
% An unapplied decision within retained data is 'not observed', not proof of
% scheduler loss (cancellation/supersession requires a separate event trace).
arguments
    trials table
    direction (1,1) string
end
p=struct('Direction',direction,'PopulationIdentity',"",'DecisionIdentity',"",'ScheduledRow',NaN, ...
    'UEIndex',NaN,'RNTI',NaN,'SweepPointIndex',NaN,'ConfiguredSNR_dB',NaN, ...
    'ExecutionID',"",'ScheduledFeedbackSourceSlot',NaN, ...
    'ScheduledAtSlot',NaN,'DueSlot',NaN,'FirstAppliedRow',NaN, ...
    'FirstAppliedSlot',NaN,'RetainedHorizonSlot',NaN, ...
    'ApplicationObserved',false,'RightCensored',false,'JoinAvailable',false, ...
    'ApplicationStatus',"missing_decision_identity");
T=struct2table(repmat(p,0,1));
names=string(trials.Properties.VariableNames);
required=["Slot","LinkAdaptationScheduled","LinkAdaptationApplied", ...
    "LinkAdaptationScheduledFeedbackSourceSlot","LinkAdaptationScheduledApplySlot", ...
    "LinkAdaptationAppliedFeedbackSourceSlot"];
if isempty(trials) || ~all(ismember(required,names)), return; end
scheduled=flag(trials.LinkAdaptationScheduled);
applied=flag(trials.LinkAdaptationApplied);
source=sixgr.truth.numericMeasurementColumn(trials.LinkAdaptationScheduledFeedbackSourceSlot,'scheduled source');
due=sixgr.truth.numericMeasurementColumn(trials.LinkAdaptationScheduledApplySlot,'scheduled apply slot');
used=sixgr.truth.numericMeasurementColumn(trials.LinkAdaptationAppliedFeedbackSourceSlot,'applied source');
slots=sixgr.truth.numericMeasurementColumn(trials.Slot,'Slot');
% Per-trial Seed changes within one execution. It is deliberately not a join
% key. ExecutionID/config/point and the receiver identity delimit a timeline.
keys=intersect(["UEIndex","RNTI","ServingCell","SweepPointIndex", ...
    "ConfiguredSNR_dB","ExecutionID","ConfigHash","SeedBase"],names,'stable');
for k=find(scheduled==1).'
    row=p; row.ScheduledRow=k;
    for field=["UEIndex","RNTI","SweepPointIndex","ConfiguredSNR_dB","ExecutionID"]
        if ismember(field,names), row.(field)=trials.(field)(k); end
    end
    row.ScheduledFeedbackSourceSlot=source(k); row.DueSlot=due(k);
    row.ScheduledAtSlot=slots(k);
    scope=true(height(trials),1); identity=direction;
    for field=keys
        value=trials.(field)(k);
        scope=scope & trials.(field)==value;
        identity=identity+"@"+field+"="+string(value);
    end
    row.PopulationIdentity=identity;
    row.DecisionIdentity=identity+"@Source="+string(source(k))+"@Due="+string(due(k));
    if ~any(scope) || any(~isfinite([source(k),due(k),slots(k)]))
        T=[T;struct2table(row)]; continue; %#ok<AGROW>
    end
    assert(all([source(k),due(k),slots(k)]==fix([source(k),due(k),slots(k)])) && ...
        source(k)>=1 && source(k)<=slots(k) && slots(k)<due(k), ...
        'sixgr:report:AdaptationNoncausalDecision','Invalid source/scheduling/application slot ordering.');
    assert(sum(scope & scheduled==1 & source==source(k))==1, ...
        'sixgr:report:AdaptationAmbiguousDecision', ...
        'One source decision per execution/receiver; duplicate sources require explicit decision identities.');
    assert(~any(scope & applied==1 & used==source(k) & slots<due(k)), ...
        'sixgr:report:AdaptationAppliedBeforeDue','A matched decision was applied before its due slot.');
    row.JoinAvailable=true;
    row.RetainedHorizonSlot=max(slots(scope & isfinite(slots)));
    hits=find(scope & applied==1 & used==source(k) & slots>=due(k));
    if ~isempty(hits)
        [row.FirstAppliedSlot,j]=min(slots(hits)); row.FirstAppliedRow=hits(j);
        row.ApplicationObserved=true; row.ApplicationStatus="observed_in_later_data_trial";
    elseif due(k)>row.RetainedHorizonSlot
        row.RightCensored=true; row.ApplicationStatus="right_censored_before_due_slot";
    else
        row.ApplicationStatus="not_observed_by_retained_horizon_not_proven_scheduler_loss";
    end
    T=[T;struct2table(row)]; %#ok<AGROW>
end
end

function values=flag(raw)
values=sixgr.truth.numericMeasurementColumn(raw,'adaptation flag');
assert(all(isnan(values) | values==0 | values==1), ...
    'sixgr:report:InvalidAdaptationFlag','Adaptation flags must be 0, 1 or unrecorded NaN.');
end
