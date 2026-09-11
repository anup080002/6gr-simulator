function identity=preparedDataTransmissionIdentity(prepared,ue)
% Identity of an authored coded contribution, NOT proof of transmission.
% Distinguish HARQ attempts and allow adjacent same-UE receive windows to
% coexist. Receiver results and mutable control decisions are not key data.
assert(isa(prepared,'sixgr.link.PreparedDataTransmission') && isscalar(prepared), ...
    'sixgr:truth:PreparedDataIdentityRequired','Retain the actual coded data preparation.');
validateattributes(ue,{'numeric'},{'scalar','real','finite','integer','positive'});
grant=prepared.RequestBinding.Grant;
phy=prepared.RequestBinding.PHYGrant;
id=string(sixgr.util.structGet(phy,'GrantContextId',''));
assert(isscalar(id) && strlength(strtrim(id))>0 && phy.IsFrozen, ...
    'sixgr:truth:PreparedDataFrozenIdentityRequired','A data contribution requires its immutable PHY grant identity.');
rnti=sixgr.util.structGet(grant,'RNTI',NaN);
validateattributes(rnti,{'numeric'},{'scalar','real','finite','integer','positive'});
owner=sixgr.util.structGet(grant,'UEIndex',ue);
assert(isequal(double(owner),double(ue)), ...
    'sixgr:truth:PreparedDataUEIdentityMismatch','The contribution belongs to a different scheduler UE.');
identity=struct('Direction',prepared.Direction,'UEIndex',double(ue), ...
    'RNTI',double(rnti),'PHYGrantContextId',id, ...
    'StartSample',prepared.StartSample,'EndSampleExclusive',prepared.EndSampleExclusive, ...
    'SampleRateHz',prepared.SampleRateHz);
identity.TransmissionID=string(sixgr.util.sha256Hex(uint8(unicode2native( ...
    jsonencode(orderfields(identity)),'UTF-8'))));
end
