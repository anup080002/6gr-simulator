function evidence=compareUCIBitEvidence(reference,decoded)
% Paired bit comparison is defined only for a complete equal-width payload.
% Absent bits are erasures, not measured bit substitutions. In particular,
% Type-2 missing-DCI hypotheses must never be compared by a blind prefix.
for bits={reference,decoded}
    validateattributes(bits{1},{'numeric','logical'},{'real','finite'});
    assert(isempty(bits{1}) || isvector(bits{1}), ...
        'sixgr:link:InvalidUCIBitEvidence','Bit evidence must be a vector.');
    assert(all(bits{1}(:)==0 | bits{1}(:)==1), ...
        'sixgr:link:InvalidUCIBitEvidence','Expected binary bit evidence.');
end
reference=int8(reference(:)); decoded=int8(decoded(:));
evidence=struct('BitErrors',NaN,'BitsCompared',0, ...
    'ContentMismatch',numel(reference)~=numel(decoded), ...
    'UCIBitErrorVector',"",'BitComparisonStatus',"unavailable_no_transmitted_bits");
if isempty(reference), return; end
if isempty(decoded)
    evidence.BitComparisonStatus="unavailable_no_decoded_bits";
    return;
end
if numel(reference)~=numel(decoded)
    evidence.BitComparisonStatus="unavailable_payload_width_mismatch";
    return;
end
errors=reference~=decoded;
evidence.BitsCompared=numel(reference);
evidence.BitErrors=nnz(errors);
evidence.ContentMismatch=any(errors);
evidence.UCIBitErrorVector=sixgr.phy.pucch.PUCCHUtil.bitString(int8(errors));
evidence.BitComparisonStatus="complete_equal_width_bit_comparison";
end
