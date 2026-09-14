function [rows,mapping,obligationDigest]=mapScheduledHARQTransportFeedback(base,cfg,observed,ulGrant)
% Transport-specific receive width, common physical DL obligation identity.
% The caller must obtain base from its actual shared DL transmission ledger
% and separately bind the UL grant to the completed physical observation.
if nargin<4, ulGrant=struct(); end
assert(isstruct(observed) && isscalar(observed) && isfield(observed,'Transport'), ...
    'sixgr:truth:MissingScheduledFeedbackTransport','Retain the actual UCI transport.');
transport=string(observed.Transport);
assert(isscalar(transport) && ~ismissing(transport) && any(transport==["PUCCH","PUSCH"]), ...
    'sixgr:truth:InvalidScheduledFeedbackTransport','Use the exact PUCCH or PUSCH transport.');
assert(isstruct(ulGrant) && isscalar(ulGrant), ...
    'sixgr:truth:InvalidScheduledFeedbackULGrant','Retain a scalar scheduled UL grant.');
if transport=="PUSCH"
    assert(~isempty(fieldnames(ulGrant)), ...
        'sixgr:truth:MissingScheduledPUSCHHARQAuthority', ...
        'PUSCH HARQ disposition requires its scheduled UL total-DAI grant.');
    mapping=sixgr.truth.bindScheduledPUSCHHARQMapping(base,cfg,ulGrant);
    rows=sixgr.truth.mapScheduledPUSCHHARQFeedback(mapping,observed);
else
    assert(isempty(fieldnames(ulGrant)), ...
        'sixgr:truth:ConflictingScheduledFeedbackTransport', ...
        'A PUCCH observation cannot borrow PUSCH scheduling authority.');
    mapping=base;
    rows=sixgr.truth.mapScheduledHARQFeedback(mapping,observed);
end
% A transport extension changes the receive mapping hash, not which DL
% process attempts are being acknowledged. This key forbids cross-transport
% duplicate application while retaining the full transport mapping in rows.
obligationDigest=base.Digest;
for k=1:numel(rows)
    rows(k).ObligationMappingDigest=obligationDigest;
end
end
