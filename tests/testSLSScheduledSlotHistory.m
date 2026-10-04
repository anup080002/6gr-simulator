function ok=testSLSScheduledSlotHistory()
history=sixgr.system.abstraction.ScheduledSlotHistory(1);
s=struct('TTI',1,'GrantsDL',struct([]),'GrantsUL',struct([]), ...
    'GrantCellsDL',[],'GrantCellsUL',[],'LargeScaleState',struct('Pathloss_dB',80));
history.append(s); history.append(s); % Idempotent publication, no duplicate.
[rows,e]=history.window(1);
assert(numel(rows)==1 && e.InitialSimulationBoundaryIncluded && e.ExplicitIdleTTIs==1);
assert(e.CommittedSlotCount==1 && e.ExplicitIdleSlotCount==1, ...
    'Idempotent publication must not double-count a physical slot.');
s.TTI=2; s.GrantsDL=struct('RNTI',1,'PRBSet',0:2); s.GrantCellsDL=1;
history.append(s); [rows,e]=history.window(2);
assert(numel(rows)==2 && isempty(rows{1}.GrantsDL) && isequal(e.TTIs,[1 2]));
bad=s; bad.GrantsDL.PRBSet=3:5;
reject(@()history.append(bad),'sixgr:abstraction:SlotHistoryMutation');
bad=s; bad.TTI=4;
reject(@()history.append(bad),'sixgr:abstraction:SlotHistoryClock');
bad=s; bad.GrantCellsDL=[];
reject(@()history.append(bad),'sixgr:abstraction:SlotHistoryPopulation');
s.TTI=3; s.GrantsDL=struct([]); s.GrantCellsDL=[];
history.append(s); [rows,e]=history.window(3);
assert(isequal(e.TTIs,[2 3]) && ~e.InitialSimulationBoundaryIncluded && e.ExplicitIdleTTIs==3);
assert(~isempty(rows{1}.GrantsDL) && isempty(rows{2}.GrantsDL));
assert(e.CommittedSlotCount==3 && e.ExplicitIdleSlotCount==2, ...
    'Evicting old samples must not erase execution-population accounting.');
% Caller mutations cannot modify an already committed value snapshot.
s.LargeScaleState.Pathloss_dB=0;
[rows,~]=history.window(3); assert(rows{2}.LargeScaleState.Pathloss_dB==80);
unknown=sixgr.system.abstraction.ScheduledSlotHistory(1); s.TTI=8;
unknown.append(s);
reject(@()unknown.window(8),'sixgr:abstraction:IncompleteSlotHistory');
s.TTI=9; unknown.append(s); [~,e]=unknown.window(9);
assert(isequal(e.TTIs,[8 9]) && ~e.WaveformMeasured && ~e.ControlRSInterferenceIncluded);
% Reject contradictory clocks before storing state, including idle slots
% and configurations with CSI/SRS feedback disabled. Control slots may be
% earlier; only the issued transmission clock belongs to this population.
clocks=sixgr.system.abstraction.ScheduledSlotHistory(1);
first=struct('TTI',1,'AbsoluteSlot0',0,'GrantsDL',struct([]), ...
    'GrantsUL',struct([]),'GrantCellsDL',[],'GrantCellsUL',[], ...
    'LargeScaleState',struct('Pathloss_dB',80));
for wrong={1,-1,NaN,[],[0 1],'0'}
    bad=first; bad.AbsoluteSlot0=wrong{1};
    reject(@()clocks.append(bad),'sixgr:abstraction:SlotHistoryClock');
    assert(clocks.CommittedSlotCount==0 && clocks.CommittedThroughTTI==0);
end
clocks.append(first);
next=first; next.TTI=2; next.AbsoluteSlot0=1;
next.GrantsUL=struct('RNTI',1,'PRBSet',0:2,'Direction','UL', ...
    'ScheduledAbsoluteSlot',1,'ControlAbsoluteSlot',0);
next.GrantCellsUL=1;
for wrong={0,2,NaN,[],[1 2],'1'}
    bad=next; bad.GrantsUL.ScheduledAbsoluteSlot=wrong{1};
    reject(@()clocks.append(bad),'sixgr:abstraction:SlotHistoryGrantClock');
    assert(clocks.CommittedSlotCount==1 && clocks.CommittedThroughTTI==1);
end
bad=next; bad.GrantsUL.Direction='DL';
reject(@()clocks.append(bad),'sixgr:abstraction:SlotHistoryGrantDirection');
assert(isequaln(clocks.scheduledState(1),first));
clocks.append(next); clocks.append(next);
[rows,e]=clocks.window(2);
assert(e.CommittedSlotCount==2 && e.ExplicitIdleSlotCount==1 && ...
    isequaln(rows{2},next), ...
    'Rejected populations must not advance history or prevent the valid retry.');
fprintf('SLS_SCHEDULED_SLOT_HISTORY_PASS idle_retained=1 mutation_rejected=1 missing_history_rejected=1\n');
ok=true;
end
function reject(fn,id)
try, fn(); catch cause, assert(strcmp(cause.identifier,id),'%s',cause.message); return; end
error('test:MissingRejection','Expected %s',id);
end
