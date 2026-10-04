function grant = bindExecutedDataIdentity(grant, tx, cfg, direction)
%BINDEXECUTEDDATAIDENTITY Retain actual TX identity without authorizing RX.
% This is transmitter/export metadata, not decoded control or UE feedback.
direction = upper(string(direction));
assert(isscalar(direction) && any(direction == ["DL","UL"]), ...
    'sixgr:link:InvalidDataIdentityDirection','Expected DL or UL.');
channel = "PDSCH";
if direction == "UL", channel = "PUSCH"; end
actual = tx.(channel);
rnti = double(actual.RNTI);
assert(isscalar(rnti) && isfinite(rnti) && rnti == fix(rnti) && ...
    rnti >= 0 && rnti <= 65535, ...
    'sixgr:link:InvalidExecutedRNTI','Executed transmitter has invalid RNTI.');
localMatch(sixgr.util.structGet(grant,'RNTI',NaN),rnti,'RNTI');
localMatch(sixgr.util.structGet(tx,'PHYGrant.ChannelStateKey.RNTI',NaN),rnti,'RNTI');
grant.RNTI = rnti;
grant.RNTISource = "executed_" + lower(channel) + "_configuration";

% Keep absent identity absent. In particular RNTI is not a UE-index map,
% and a component lacking a UE binding must not be assigned a guessed UE.
ue = NaN;
source = "unavailable_no_executed_ue_binding";
assignment = sixgr.util.structGet(tx,'Assignment',[]);
if direction == "DL" && isa(assignment,'sixgr.pdsch.PDSCHSchedulingAssignment')
    localMatch(assignment.get('RNTI'),rnti,'RNTI');
    ue = double(assignment.get('UEId'));
    source = "executed_pdsch_assignment";
end
candidates = {sixgr.util.structGet(tx,'PHYGrant.ChannelStateKey.UEIndex',NaN), ...
    sixgr.util.structGet(grant,'UEIndex',NaN), ...
    sixgr.util.structGet(cfg,'lls6g.userContext.UEIndex',NaN)};
sources = ["executed_phy_grant","executed_grant","configured_user_context"];
for k = 1:numel(candidates)
    value = candidates{k};
    if isempty(value) || (isnumeric(value) && isscalar(value) && isnan(value))
        continue;
    end
    assert(isnumeric(value) && isscalar(value) && isfinite(value) && ...
        value >= 1 && value == fix(value), ...
        'sixgr:link:InvalidExecutedUEIdentity','UEIndex must be a positive integer.');
    if isfinite(ue)
        localMatch(value,ue,'UEIndex');
    else
        ue = double(value);
        source = sources(k);
    end
end
grant.UEIndex = ue;
grant.UEIdentitySource = source;
end

function localMatch(expected, actual, name)
if isempty(expected) || (isnumeric(expected) && isscalar(expected) && isnan(expected))
    return;
end
assert(isnumeric(expected) && isscalar(expected) && isfinite(expected) && ...
    double(expected) == actual, ...
    'sixgr:link:ExecutedDataIdentityMismatch', ...
    'Executed transmitter %s disagrees with its bound grant/context.',name);
end
