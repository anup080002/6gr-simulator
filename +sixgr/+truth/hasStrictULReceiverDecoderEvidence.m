function [ok, reason] = hasStrictULReceiverDecoderEvidence(row)
%HASSTRICTULRECEIVERDECODEREVIDENCE Verify a decoded UL row is waveform truth.
% A negative post-equalization SINR is not itself an inconsistency.  A
% low-rate code can decode below 0 dB.  Such a success is accepted only when
% the same persisted row proves the complete receiver/decoder path and
% explicitly excludes fallback, placeholder, proxy, and crash states.

if istable(row)
    if height(row) ~= 1
        ok = false;
        reason = "receiver_evidence_requires_exactly_one_row";
        return;
    end
elseif ~(isstruct(row) && isscalar(row))
    ok = false;
    reason = "receiver_evidence_row_type_invalid";
    return;
end

requiredTrue = [ ...
    "StrictReceiverEvidenceOk"
    "ReceiverUsable"
    "DecodeAttempted"
    "DecodeUsable"
    "ChannelEstimateAttempted"
    "ChannelEstimateAvailable"
    "ResourceExtractionAttempted"
    "ResourceExtractionAvailable"
    "EqualizationAttempted"
    "EqualizationAvailable"
    "ULSCHDecodeAttempted"
    "ULSCHDecodeAvailable"
    "LLRAvailable"
    "LLRFinite"
    "PostEqSINRAvailable"
    "PostEqSINRReceiverDerived"];
for name = requiredTrue.'
    if ~localHas(row, name) || ~localLogical(localValue(row, name, false))
        ok = false;
        reason = "missing_or_false_" + lower(name);
        return;
    end
end

for name = ["FallbackFlag", "FallbackUsed", "PlaceholderFlag", "Crash"]
    if localHas(row, name) && localLogical(localValue(row, name, false))
        ok = false;
        reason = "forbidden_" + lower(name);
        return;
    end
end

truthStatus = lower(strtrim(string(localValue(row, "TruthStatus", ""))));
if truthStatus ~= "real_lls_evidence"
    ok = false;
    reason = "truth_status_not_real_lls_evidence";
    return;
end

source = lower(strtrim(string(localValue(row, "SourceArtifact", ""))));
if ~contains(replace(source, "\\", "/"), "ul_pusch_trials.csv")
    ok = false;
    reason = "source_not_ul_pusch_runtime_trial";
    return;
end

bitsCompared = localNumeric(localValue(row, "BitsCompared", NaN));
bitErrors = localNumeric(localValue(row, "BitErrors", NaN));
if ~(isfinite(bitsCompared) && bitsCompared > 0 && isfinite(bitErrors) && bitErrors == 0)
    ok = false;
    reason = "decoded_bit_comparison_not_clean";
    return;
end

valueStatus = upper(strtrim(string(localValue(row, "PostEqSINRValueStatus", ""))));
if ~(valueStatus == "OK" || startsWith(valueStatus, "OK_"))
    ok = false;
    reason = "posteq_sinr_value_status_not_ok";
    return;
end

ok = true;
reason = "strict_waveform_receiver_decoder_evidence_complete";
end

function tf = localHas(row, name)
if istable(row)
    tf = ismember(string(name), string(row.Properties.VariableNames));
else
    tf = isfield(row, char(name));
end
end

function value = localValue(row, name, defaultValue)
if ~localHas(row, name)
    value = defaultValue;
elseif istable(row)
    value = row.(char(name))(1);
else
    value = row.(char(name));
end
end

function value = localLogical(raw)
if islogical(raw)
    value = logical(raw(1));
elseif isnumeric(raw)
    value = isfinite(double(raw(1))) && double(raw(1)) ~= 0;
else
    token = lower(strtrim(string(raw(1))));
    value = any(token == ["1", "true", "yes", "on", "pass", "ok"]);
end
end

function value = localNumeric(raw)
if isnumeric(raw) || islogical(raw)
    value = double(raw(1));
else
    value = str2double(string(raw(1)));
end
end
