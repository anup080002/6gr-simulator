function ok = testPDCCHControlSlotAuthority()
% Control time must survive scheduler -> waveform -> observed-RE boundaries.
for direction = ["DL","UL"]
    for control0 = [0 19 20 10239 10240]
        grant = struct('Direction',direction,'ControlAbsoluteSlot',int64(control0), ...
            'Slot',control0+8,'ScheduledAbsoluteSlot',control0+7);
        assert(sixgr.truth.resolvePDCCHControlSlot(grant) == control0+1);
        grant.ControlSlot = control0+1;
        grant.TimingDecision = struct('Valid',true,'IndexConvention',"zero_based", ...
            'ControlAbsoluteSlot',int64(control0),'DataAbsoluteSlot',control0+7);
        assert(sixgr.truth.resolvePDCCHControlSlot(grant,control0+1) == control0+1);
        localReject(@() sixgr.truth.resolvePDCCHControlSlot(grant,control0+2), ...
            'sixgr:truth:PDCCHControlSlotMismatch');
        conflict = grant; conflict.ControlSlot = control0+2;
        localReject(@() sixgr.truth.resolvePDCCHControlSlot(conflict), ...
            'sixgr:truth:PDCCHControlSlotMismatch');
        conflict = grant; conflict.TimingDecision.ControlAbsoluteSlot = control0+1;
        localReject(@() sixgr.truth.resolvePDCCHControlSlot(conflict), ...
            'sixgr:truth:PDCCHControlSlotMismatch');
    end
end
assert(sixgr.truth.resolvePDCCHControlSlot(struct(),5) == 5);
assert(sixgr.truth.resolvePDCCHControlSlot(struct('ControlSlot',5)) == 5);
decision = struct('Valid',true,'IndexConvention',"zero_based",'ControlAbsoluteSlot',4);
assert(sixgr.truth.resolvePDCCHControlSlot(struct('TimingDecision',decision)) == 5);
localReject(@() sixgr.truth.resolvePDCCHControlSlot(struct('Slot',5)), ...
    'sixgr:truth:MissingPDCCHControlSlot');
for bad = {0,-1,1.5,Inf,[1 2],"1"}
    localReject(@() sixgr.truth.resolvePDCCHControlSlot(struct('ControlSlot',bad{1})), ...
        'sixgr:truth:InvalidPDCCHControlSlot');
end
decision.Valid = false;
localReject(@() sixgr.truth.resolvePDCCHControlSlot(struct('TimingDecision',decision)), ...
    'sixgr:truth:InvalidPDCCHControlSlot');
decision.Valid = true; decision.IndexConvention = "one_based";
localReject(@() sixgr.truth.resolvePDCCHControlSlot(struct('TimingDecision',decision)), ...
    'sixgr:truth:InvalidPDCCHControlSlot');
source = fileread(fullfile('+sixgr','+truth','runWaveformLinkBundle.m'));
assert(contains(source,'controlSlotIdx = sixgr.truth.resolvePDCCHControlSlot(grant,') && ...
    contains(source,'grant.ControlSlot = controlSlotIdx;') && ...
    contains(source,'controlSlot = sixgr.truth.resolvePDCCHControlSlot(grantContext,'), ...
    'Both integrated admission and waveform construction must bind the same control slot.');
ok = true;
fprintf('PASS testPDCCHControlSlotAuthority: canonical control time, aliases, wrap and mismatch rejection.\n');
end

function localReject(call,identifier)
try
    call();
catch exception
    assert(strcmp(exception.identifier,identifier), ...
        'Expected %s, received %s: %s',identifier,exception.identifier,exception.message);
    return;
end
error('testPDCCHControlSlotAuthority:MissingRejection','Expected %s.',identifier);
end
