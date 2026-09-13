function rows=mapScheduledHARQFeedback(mapping,observed)
% Associate normalized receiver bits with independent gNB schedule identities.
% Pure association only: the owning receiver must build/validate mapping from
% actual transmitted scheduling evidence and bind the physical receive window.
% This helper neither proves PHY execution nor mutates HARQ or scoring state.
arguments
    mapping (1,1) struct
    observed (1,1) struct
end
required=["Records","BitCount","UEIndex","RNTI","TargetSlot", ...
    "ConfigurationEpoch","ContextDigest","LastGrant","Source","Digest"];
assert(all(isfield(mapping,required)),'sixgr:truth:InvalidScheduledFeedbackMapping', ...
    'Retain the complete independent gNB mapping.');
digest=sixgr.phy.pucch.PUCCHUtil.hash(rmfield(mapping,{'LastGrant','Digest'}));
assert(isequal(string(mapping.Digest),string(digest)), ...
    'sixgr:truth:ChangedScheduledFeedbackMapping','The bound mapping identity changed.');
n=mapping.BitCount;
validateattributes(n,{'numeric'},{'scalar','real','finite','integer','positive'});
records=mapping.Records;
fields=["BitIndex","TransmissionID","PHYGrantContextId","UEIndex","RNTI", ...
    "HARQProcess","NDI","SourceSlot","TargetSlot","ConfigurationEpoch"];
assert(isstruct(records) && numel(records)==n && all(isfield(records,fields)), ...
    'sixgr:truth:InvalidScheduledFeedbackMapping','Retain every gNB bit identity.');
assert(isequal([records.BitIndex],1:n) && ...
    numel(unique(string({records.TransmissionID})))==n && ...
    all(strlength(string({records.TransmissionID}))>0) && ...
    all(strlength(string({records.PHYGrantContextId}))>0), ...
    'sixgr:truth:InvalidScheduledFeedbackMapping','Bit ordinals and transmission identities must be unique.');
for k=1:n
    r=records(k);
    validateattributes(r.HARQProcess,{'numeric'},{'scalar','real','finite','integer','nonnegative'});
    validateattributes(r.SourceSlot,{'numeric'},{'scalar','real','finite','integer','positive'});
    localFlag(r.NDI);
    assert(r.UEIndex==mapping.UEIndex && r.RNTI==mapping.RNTI && ...
        r.TargetSlot==mapping.TargetSlot && r.ConfigurationEpoch==mapping.ConfigurationEpoch, ...
        'sixgr:truth:InvalidScheduledFeedbackMapping','Do not mix gNB feedback contexts.');
end
assert(all(isfield(observed,["MappingDigest","UEIndex","RNTI","TargetSlot", ...
    "DecodedBits","DecodeOk","DTXFlag","Transport"])), ...
    'sixgr:truth:MissingScheduledFeedbackBinding','Bind normalized receiver output to its gNB hypothesis.');
assert(isequal(string(observed.MappingDigest),string(mapping.Digest)) && ...
    isequal(observed.UEIndex,mapping.UEIndex) && isequal(observed.RNTI,mapping.RNTI) && ...
    isequal(observed.TargetSlot,mapping.TargetSlot), ...
    'sixgr:truth:ScheduledFeedbackContextMismatch','Receiver and scheduling hypothesis identities differ.');
transport=string(observed.Transport);
assert(isscalar(transport) && any(transport==["PUCCH","PUSCH"]), ...
    'sixgr:truth:InvalidScheduledFeedbackTransport','Use one explicit UCI transport.');
decodeOK=localFlag(observed.DecodeOk); dtx=localFlag(observed.DTXFlag);
bits=observed.DecodedBits;
assert((isnumeric(bits)||islogical(bits)) && isreal(bits) && ...
    (isvector(bits)||isempty(bits)) && all(isfinite(bits(:))) && ...
    all(bits(:)==0 | bits(:)==1), ...
    'sixgr:truth:InvalidReceivedHARQBit','Validate receiver bits before any conversion or state update.');
lengthOK=numel(bits)==n;
usable=decodeOK && ~dtx && lengthOK;
rows=records;
for k=1:n
    outcome="DTX"; reason="receiver_feedback_unusable";
    if usable
        outcome="NACK"; if bits(k)==1, outcome="ACK"; end
        reason="decoded_uci_bit";
    elseif dtx
        reason="receiver_reported_dtx";
    elseif decodeOK && ~lengthOK
        reason="receiver_vector_length_mismatch";
    end
    rows(k).FeedbackOutcome=outcome;
    rows(k).FeedbackOutcomeReason=reason;
    rows(k).ObservedAck=outcome=="ACK";
    rows(k).ReceiverUsable=usable;
    rows(k).ReceiverVectorLengthMatches=lengthOK;
    rows(k).MappingDigest=string(mapping.Digest);
    rows(k).UCITransport=transport;
    rows(k).AssociationRole="gNB_bit_identity_association_not_PHY_execution_proof";
end
end

function flag=localFlag(value)
assert((isnumeric(value)||islogical(value)) && isreal(value) && ...
    isscalar(value) && isfinite(value) && any(value==[0 1]), ...
    'sixgr:truth:InvalidScheduledFeedbackFlag','Validity and NDI flags must be scalar binary values.');
flag=logical(value);
end
