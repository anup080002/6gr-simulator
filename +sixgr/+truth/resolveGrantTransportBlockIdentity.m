function tbId=resolveGrantTransportBlockIdentity(grant,allowUnbound)
% Resolve an already bound logical TB, never an SDU or transmission attempt.
% Only the new-data preparation boundary may tolerate an unbound result.
if nargin<2, allowUnbound=false; end
assert(isstruct(grant) && isscalar(grant) && islogical(allowUnbound) && isscalar(allowUnbound), ...
    'sixgr:truth:InvalidTransportIdentityInput','Use one grant and an explicit binding policy.');
tbId="";
for field=["TransportBlockId","TBId","TBIdentity","HARQTBContext.TBId"]
    raw=strtrim(string(sixgr.util.structGet(grant,char(field),"")));
    raw=raw(:);
    raw=raw(~ismissing(raw) & strlength(raw)>0 & lower(raw)~="nan");
    ids=unique(raw,'stable');
    assert(numel(ids)<=1,'sixgr:truth:AmbiguousGrantTransportBlockIdentity', ...
        'Grant field %s contains multiple logical transport-block identities.',field);
    if isempty(ids), continue; end
    assert(strlength(tbId)==0 || tbId==ids(1), ...
        'sixgr:truth:ConflictingGrantTransportBlockIdentity', ...
        'Logical TB aliases disagree at %s; do not select the first alias.',field);
    tbId=ids(1);
end
assert(allowUnbound || strlength(tbId)>0, ...
    'sixgr:truth:MissingRuntimeTransportBlockIdentity', ...
    'An executed grant requires its retained logical TB identity; attempt/MAC identifiers are not substitutes.');
end
