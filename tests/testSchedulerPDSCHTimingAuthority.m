function ok = testSchedulerPDSCHTimingAuthority()
% The adapter must preserve K0 and absolute control time, including wrap.
for control = [0 19 10239]
    for k0 = [0 1 3]
        data = control + k0;
        grant = struct('ControlAbsoluteSlot',control,'ScheduledAbsoluteSlot',data, ...
            'K0',k0,'ControlSlot',control+1);
        grant.TimingDecision = struct('Valid',true,'IndexConvention',"zero_based", ...
            'ControlAbsoluteSlot',int64(control),'DataAbsoluteSlot',int64(data),'K0',k0);
        timing = sixgr.pdsch.resolveSchedulerPDSCHTiming(grant,data);
        assert(timing.PDCCHAbsoluteSlot == control && timing.K0 == k0 && ...
            timing.PDSCHAbsoluteSlot == data);
        fromK = sixgr.pdsch.resolveSchedulerPDSCHTiming(struct('K0',k0),data);
        fromControl = sixgr.pdsch.resolveSchedulerPDSCHTiming(struct('ControlSlot',control+1),data);
        assert(fromK.PDCCHAbsoluteSlot == control && fromControl.K0 == k0);
        conflict = grant;
        conflict.ControlSlot = control+2;
        localReject(@() sixgr.pdsch.resolveSchedulerPDSCHTiming(conflict,data), ...
            'sixgr:pdsch:SchedulerTimingMismatch');
        localReject(@() sixgr.pdsch.resolveSchedulerPDSCHTiming(grant,data+1), ...
            'sixgr:pdsch:SchedulerTimingMismatch');
    end
end
localReject(@() sixgr.pdsch.resolveSchedulerPDSCHTiming(struct('Slot',1),0), ...
    'sixgr:pdsch:MissingSchedulerControlTiming');
localReject(@() sixgr.pdsch.resolveSchedulerPDSCHTiming(struct('K0',2),1), ...
    'sixgr:pdsch:SchedulerTimingMismatch');
localReject(@() sixgr.pdsch.resolveSchedulerPDSCHTiming(struct('K0',[0 1]),1), ...
    'sixgr:pdsch:InvalidSchedulerTiming');
bad = struct('TimingDecision',struct('Valid',false,'IndexConvention',"zero_based"));
localReject(@() sixgr.pdsch.resolveSchedulerPDSCHTiming(bad,0), ...
    'sixgr:pdsch:InvalidSchedulerTiming');
bad.TimingDecision.Valid = true;
bad.TimingDecision.IndexConvention = "one_based";
localReject(@() sixgr.pdsch.resolveSchedulerPDSCHTiming(bad,0), ...
    'sixgr:pdsch:InvalidSchedulerTiming');
source = fileread(fullfile('+sixgr','+pdsch','PDSCHCalibrationFacadeAdapter.m'));
assert(contains(source,'sixgr.pdsch.resolveSchedulerPDSCHTiming(grant, absoluteSlot)') && ...
    ~contains(source,'request.K0 = 0;'), 'The active adapter must not recreate a hardcoded K0.');
ok = true;
fprintf('PASS testSchedulerPDSCHTimingAuthority: exact slot/K0 consistency, no same-slot fallback.\n');
end

function localReject(call, identifier)
try
    call();
catch exception
    assert(strcmp(exception.identifier,identifier),'Expected %s, received %s.',identifier,exception.identifier);
    return;
end
error('testSchedulerPDSCHTimingAuthority:MissingRejection','Expected %s.',identifier);
end
