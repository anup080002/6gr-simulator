function ok=testCheckpointSchedule()
slots=40:60;
due=arrayfun(@(s)sixgr.runtime.CheckpointSchedule.due(s,3,49),slots);
assert(isequal(slots(due),[49 52 55 58]));
legacy=arrayfun(@(s)sixgr.runtime.CheckpointSchedule.due(s,3,0),slots);
assert(isequal(slots(legacy),[42 45 48 51 54 57 60]));
assert(sixgr.runtime.CheckpointSchedule.due(46,1,0));
assert(~sixgr.runtime.CheckpointSchedule.due(48,3,49));
slots=1:65;
due=arrayfun(@(s)sixgr.runtime.CheckpointSchedule.due(s,60,60),slots);
assert(isequal(slots(due),60), 'The 65-slot horizon must checkpoint only completed slot60.');
ok=true; disp('CHECKPOINT_SCHEDULE_PASS');
end
