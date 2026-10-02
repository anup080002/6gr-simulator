function commitFile(source,target)
% Bounded retry for transient Windows reader/sync locks; never drop evidence.
message=''; identifier='';
for attempt=1:12
    [ok,message,identifier]=movefile(source,target,'f');
    if ok, return; end
    pause(min(0.05*attempt,0.5));
end
error('sixgr:calibration:FileCommit', ...
    'Cannot commit %s to %s; staging file retained. %s: %s', ...
    source,target,identifier,message);
end
