function evidence=harqObservationEvidence(context,rx)
% Receiver-owned HARQ evidence, not a transmitted-payload comparison.
% TS 38.212 6.3.1.1 distinguishes HARQ-ACK, SR and CSI. A leading CSI/SR
% bit is not an ACK. A scalar ACK is meaningful only for a one-bit HARQ
% hypothesis; multi-bit codebooks retain every bit for DCI/DAI mapping.
arguments
    context (1,1) sixgr.phy.pucch.UCIReportContext
    rx (1,1) struct
end
id='sixgr:link:InvalidPUCCHHARQObservation';
required=["ReceiverUsable","DTX","CRCApplicable","CRCPassed","DecodedFields"];
assert(all(isfield(rx,required)) && isstruct(rx.DecodedFields) && ...
    isscalar(rx.DecodedFields) && isfield(rx.DecodedFields,'HARQACK'),id, ...
    'Completed receiver decisions and the decoded HARQ field are required.');
for name=required(1:4)
    v=rx.(name);
    assert((isnumeric(v)||islogical(v)) && isreal(v) && isscalar(v) && ...
        isfinite(v) && any(v==[0 1]),id,'Receiver decisions must be scalar binary values.');
end
bits=rx.DecodedFields.HARQACK;
assert((isnumeric(bits)||islogical(bits)) && isreal(bits) && ...
    (isempty(bits)||isvector(bits)) && all(isfinite(bits(:))) && ...
    all(bits(:)==0 | bits(:)==1),id,'Decoded HARQ bits must be finite binary values.');
bits=int8(bits(:)); count=double(context.HARQACKBits);
assert(count>0 || isempty(bits),id,'A no-HARQ receiver schema cannot contain decoded HARQ bits.');
evidence=struct('ReceiverExpectedHARQBitCount',count, ...
    'DecodedHARQBitCount',double(numel(bits)), ...
    'DecodedHARQBitVector',sixgr.phy.pucch.PUCCHUtil.bitString(bits), ...
    'HARQObservationApplicable',count>0,'HARQObservationValid',false, ...
    'ObservedHARQACKBitCount',NaN,'ObservedHARQNACKBitCount',NaN, ...
    'AckObserved',false,'AckObservedValid',false, ...
    'HARQObservationStatus',"not_applicable_no_harq", ...
    'HARQObservationSource',"receiver_schema_and_decoded_HARQ_field_not_payload_prefix");
if count==0, return; end
if rx.DTX
    evidence.HARQObservationStatus="receiver_dtx";
elseif ~rx.ReceiverUsable
    evidence.HARQObservationStatus="receiver_unusable";
elseif rx.CRCApplicable && ~rx.CRCPassed
    evidence.HARQObservationStatus="crc_failed";
elseif numel(bits)~=count
    evidence.HARQObservationStatus="incomplete_harq_field";
else
    % No transmitted bit or content-match flag is consulted: an incorrectly
    % decoded ACK must remain observable by independent false-ACK scoring.
    evidence.HARQObservationValid=true;
    evidence.ObservedHARQACKBitCount=double(nnz(bits));
    evidence.ObservedHARQNACKBitCount=double(nnz(~bits));
    evidence.HARQObservationStatus="decoded_multi_bit_codebook";
    if count==1
        evidence.AckObservedValid=true;
        evidence.AckObserved=logical(bits);
        evidence.HARQObservationStatus="decoded_single_harq_bit";
    end
end
end
