function [bound,fields] = bindReceivedPDCCHGrantEvidence(prepared,received)
% Bind actual received control evidence without mutating transmitted data.
arguments
    prepared (1,1) struct
    received (1,1) struct
end
identities = {'GrantContextId','UEIndex','RNTI','Direction','Slot','Frame', ...
    'ControlSlot','ControlAbsoluteSlot'};
for k = 1:numel(identities)
    name = identities{k};
    if isfield(prepared,name)
        assert(isfield(received,name) && isequaln(prepared.(name),received.(name)), ...
            'sixgr:truth:ReceivedPDCCHGrantIdentityMismatch', ...
            'Received PDCCH evidence differs from the prepared grant identity: %s.',name);
    end
end
required = {'ControlDecodeOk','DCICrcPass','PDCCHPayloadMatch', ...
    'PDCCHCausalGrantDecodeOk','PDCCHGrantBindingRequired','PDCCHGrantBindingOk'};
for k = 1:numel(required)
    value = sixgr.util.structGet(received,required{k},[]);
    assert((islogical(value) || isnumeric(value)) && isscalar(value) && ...
        isfinite(double(value)) && double(value)==1, ...
        'sixgr:truth:IncompleteReceivedPDCCHGrantEvidence', ...
        'Accepted shared data requires actual successful received evidence: %s.',required{k});
end
dciHash = string(sixgr.util.structGet(received,'PDCCHGrantDCIFieldsHash',""));
grantHash = string(sixgr.util.structGet(received,'PDCCHGrantFieldsHash',""));
assert(isscalar(dciHash) && isscalar(grantHash) && ...
    strlength(strtrim(dciHash))>0 && dciHash==grantHash, ...
    'sixgr:truth:IncompleteReceivedPDCCHGrantEvidence', ...
    'Received DCI and grant field hashes must be present and equal.');
fields = sixgr.truth.receivedPDCCHGrantEvidenceFields();
fields = fields(isfield(received,fields));
bound = prepared;
for k = 1:numel(fields)
    bound.(fields{k}) = received.(fields{k});
end
end
