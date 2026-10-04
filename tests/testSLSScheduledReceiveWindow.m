function ok=testSLSScheduledReceiveWindow()
% Modeled schedule history only: no waveform or calibrated BLER is invented.
h=sixgr.system.abstraction.ScheduledSlotHistory(1,1);
s=struct('TTI',1,'GrantsDL',struct([]),'GrantsUL',struct([]), ...
    'GrantCellsDL',[],'GrantCellsUL',[],'LargeScaleState',struct('Pathloss_dB',80));
h.append(s);
reject(@()h.receiveWindow(1,1),'sixgr:abstraction:ReceiveWindowNotAvailable');
s.TTI=2; s.GrantsDL=struct('RNTI',1,'PRBSet',0:2); s.GrantCellsDL=1;
h.append(s);
[rows,e]=h.receiveWindow(1,1);
assert(isequal(e.TTIs,[1 2]) && e.ObservationTTI==1 && ...
    e.RequiredCommittedThroughTTI==2 && e.ReadAtCommittedTTI==2 && ...
    e.RequiredFollowingSlots==1 && isempty(rows{1}.GrantsDL) && ...
    ~isempty(rows{2}.GrantsDL) && ~e.WaveformMeasured);
reject(@()h.receiveWindow(2,1),'sixgr:abstraction:ReceiveWindowNotAvailable');
s.TTI=3; s.GrantsDL=struct([]); s.GrantCellsDL=[]; h.append(s);
[~,e]=h.receiveWindow(2,1);
assert(isequal(e.TTIs,[1 2 3]) && e.CommittedSlotCount==3 && e.ExplicitIdleSlotCount==2);
[~,current]=h.window(3);
assert(isequal(current.TTIs,[2 3]),'Current-slot callers must not accidentally consume the larger delayed window.');
s.TTI=4; h.append(s);
reject(@()h.receiveWindow(2,1),'sixgr:abstraction:IncompleteSlotHistory');
[~,e]=h.receiveWindow(3,1);
assert(isequal(e.TTIs,[2 3 4]) && e.RequiredCommittedThroughTTI==4);
reject(@()h.receiveWindow(3,2),'sixgr:abstraction:ReceiveWindowRetention');
% The last transmission is NOT decoded using an invented idle flush slot.
reject(@()h.receiveWindow(4,1),'sixgr:abstraction:ReceiveWindowNotAvailable');
noLookahead=sixgr.system.abstraction.ScheduledSlotHistory(1);
s.TTI=1; noLookahead.append(s);
reject(@()noLookahead.receiveWindow(1,1),'sixgr:abstraction:ReceiveWindowRetention');
fprintf('SLS_SCHEDULED_RECEIVE_WINDOW_PASS following_slot_causal=1 expired_rejected=1 no_synthetic_flush=1\n');
ok=true;
end
function reject(fn,id)
try
    fn();
catch cause
    assert(strcmp(cause.identifier,id),'Expected %s; got %s: %s',id,cause.identifier,cause.message);
    return;
end
error('test:MissingRejection','Expected %s',id);
end
