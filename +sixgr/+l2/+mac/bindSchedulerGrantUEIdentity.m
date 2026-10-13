function grant = bindSchedulerGrantUEIdentity(grant, ue)
% Bind the selected scheduler owner before PHY/PUCCH/DCI finalization.
% Logical UE/cell identity is independent of received CSI availability and
% of the scheduler's array ordering. Never derive it from a protocol RNTI.
arguments
    grant (1,1) struct
    ue (1,1) struct
end
radio=localIdentity(ue,'RNTI');
assert(isfinite(radio) && radio<=65535 && ...
    isequal(localIdentity(grant,'RNTI'),radio), ...
    'sixgr:l2:mac:SchedulerGrantOwnerMismatch', ...
    'The grant and selected scheduler state must have the same valid RNTI.');
frozen=sixgr.util.structGet(grant,'PHYGrant',struct());
isFrozen=isstruct(frozen) && isscalar(frozen) && ...
    logical(sixgr.util.structGet(frozen,'IsFrozen',false));
if isFrozen
    % PHYGrant/v1 stores owner identity in its canonical keys, not as
    % top-level aliases. Read both radio keys without modifying the snapshot.
    frozenOwner=sixgr.util.structGet(frozen,'ChannelStateKey',struct());
    frozenHARQ=sixgr.util.structGet(frozen,'HARQProcessKey',struct());
    assert(isequal(localIdentity(frozenOwner,'RNTI'),radio) && ...
        isequal(localIdentity(frozenHARQ,'RNTI'),radio), ...
        'sixgr:l2:mac:SchedulerGrantOwnerMismatch', ...
        'A retained PHY grant cannot be reassigned to another radio identity.');
end
for field=["UEIndex","ServingCell"]
    selected=localIdentity(ue,field);
    if isnan(selected)
        % Low-level single-link callers may omit these optional identities.
        % Keep existing grant authority, if any. The configured multi-user
        % PRI resolver still rejects a missing required UE ordinal.
        continue;
    end
    previous=localIdentity(grant,field);
    assert(isnan(previous) || previous==selected, ...
        'sixgr:l2:mac:SchedulerGrantOwnerMismatch', ...
        'A retained grant cannot change its %s owner.',field);
    if isFrozen
        original=localIdentity(frozenOwner,field);
        assert(isnan(original) || original==selected, ...
            'sixgr:l2:mac:SchedulerGrantOwnerMismatch', ...
            'A retained PHY grant cannot change its %s owner.',field);
    end
    grant.(char(field))=selected;
end
end

function value=localIdentity(owner,field)
value=sixgr.util.structGet(owner,field,NaN);
if isempty(value), value=NaN; end
assert(isnumeric(value) && isreal(value) && isscalar(value) && ...
    (isnan(value) || (isfinite(value) && value>=1 && value==fix(value))), ...
    'sixgr:l2:mac:InvalidSchedulerIdentity', ...
    '%s must be a positive integer identity, or absent/NaN when not supplied.',field);
value=double(value);
end
