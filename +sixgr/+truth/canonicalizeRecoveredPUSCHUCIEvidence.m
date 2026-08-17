function T = canonicalizeRecoveredPUSCHUCIEvidence(T)
%CANONICALIZERECOVEREDPUSCHUCIEVIDENCE Repair one legacy provenance token.
%
% The affected producer persisted the grant-reservation source after the
% same row had already received exact PUSCH receiver outputs.  Recovery is
% allowed only when every receiver fact proves a successful in-waveform UCI
% demultiplex/decode.  No bits, CRC outcomes, or measurements are changed.

if ~(istable(T) && ~isempty(T))
    return;
end
required = ["UCIOnPUSCHApplied","UCIOnPUSCHFeedbackBitCount", ...
    "ExpectedHARQACKBits","DecodedHARQACKBits","HARQACKContentMatch", ...
    "HARQACKDecodeStatus","UCIOnPUSCHEvidenceSource"];
if ~all(ismember(required, string(T.Properties.VariableNames)))
    return;
end
crcProof = localCRCProof(T);

source = lower(strtrim(string(T.UCIOnPUSCHEvidenceSource)));
legacy = source == "pending_feedback_table_reserved_after_pdcch_grant_binding";
expected = strtrim(string(T.ExpectedHARQACKBits));
decoded = strtrim(string(T.DecodedHARQACKBits));
receiverProof = localBool(T.UCIOnPUSCHApplied) & ...
    double(T.UCIOnPUSCHFeedbackBitCount) > 0 & ...
    strlength(expected) > 0 & expected == decoded & ...
    localBool(T.HARQACKContentMatch) & ...
    lower(strtrim(string(T.HARQACKDecodeStatus))) == "decoded_match" & ...
    crcProof;
repair = legacy & receiverProof;

T.UCIOnPUSCHEvidenceRecoveryApplied = false(height(T),1);
T.UCIOnPUSCHEvidenceRecoveryVersion = repmat( ...
    "canonicalizeRecoveredPUSCHUCIEvidence/v1",height(T),1);
if any(repair)
    T.UCIOnPUSCHEvidenceSource(repair) = ...
        "same_waveform_pusch_rx_uci_demultiplexer_recovered_from_persisted_receiver_columns";
    T.UCIOnPUSCHEvidenceRecoveryApplied(repair) = true;
end
end

function proof = localCRCProof(T)
vars = string(T.Properties.VariableNames);
n = height(T);
if ismember("CRCPass", vars)
    if ismember("CRCApplicable", vars)
        applicable = localBool(T.CRCApplicable);
    else
        applicable = true(n, 1);
    end
    proof = ~applicable | localBool(T.CRCPass);
elseif ismember("CRCError", vars)
    proof = ~localBool(T.CRCError);
else
    proof = false(n, 1);
end
proof = logical(proof(:));
end

function value = localBool(raw)
if islogical(raw)
    value = raw(:);
elseif isnumeric(raw)
    value = isfinite(double(raw(:))) & double(raw(:)) ~= 0;
else
    token = lower(strtrim(string(raw(:))));
    value = ismember(token,["1","true","yes","on","pass","passed"]);
end
end
