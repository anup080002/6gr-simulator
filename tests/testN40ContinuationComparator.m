function ok=testN40ContinuationComparator()
% Declared comparator-only fixture: never claims a checkpoint or PHY replay.
a=struct('CompletedSlot',65,'ConfigHash',"declared_fixture",'RNG',rng, ...
    'PendingULGrants',struct('GrantID',7),'DLTrials',table(1,'VariableNames',{'CRC'}), ...
    'ULTrials',table(0,'VariableNames',{'CRC'}), ...
    'SlotTraceTable',table((61:65).','VariableNames',{'CanonicalSlot'}), ...
    'SchedulerDecisionTable',table(1,'VariableNames',{'UE'}), ...
    'DLGrantTraceTable',table(100,'VariableNames',{'TBSBits'}), ...
    'ULGrantTraceTable',table(200,'VariableNames',{'TBSBits'}), ...
    'HARQTimelineTable',table(0,'VariableNames',{'RV'}), ...
    'PhysicalClock',struct('NextSampleIndex',100), ...
    'PhysicalExecutionTrace',{{struct('SHA256',"declared_fixture")}}, ...
    'RFExecutionLedger',struct('Intervals',1));
checks=sixgr.validation.compareN40ContinuationProjections(a,a);
assert(all(checks.Passed));
for field=string(fieldnames(a)).'
    missing=rmfield(a,field);
    checks=sixgr.validation.compareN40ContinuationProjections(a,missing);
    assert(~all(checks.Passed),'Missing evidence %s must fail.',field);
    changed=a; changed.(field)=[];
    checks=sixgr.validation.compareN40ContinuationProjections(a,changed);
    assert(~all(checks.Passed),'Changed evidence %s must fail.',field);
end
empty=a; empty.SlotTraceTable=empty.SlotTraceTable([],:);
checks=sixgr.validation.compareN40ContinuationProjections(empty,empty);
assert(~all(checks.Passed),'Two empty populations do not establish continuation.');
changed=a; changed.ULTrials.CRC=1;
checks=sixgr.validation.compareN40ContinuationProjections(a,changed);
assert(~checks.Passed(checks.CheckID=="ULTrials"));
changed=a; changed.CompletedSlot=64;
checks=sixgr.validation.compareN40ContinuationProjections(changed,changed);
assert(~all(checks.Passed));
ok=true;
fprintf('N40_CONTINUATION_COMPARATOR_PASS declared_fixture_only=1\n');
end
