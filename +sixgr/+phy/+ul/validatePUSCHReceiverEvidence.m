function evidence = validatePUSCHReceiverEvidence(rx, varargin)
%VALIDATEPUSCHRECEIVEREVIDENCE Gate strict UL PUSCH receiver evidence.
%   This validator intentionally checks receiver-stage evidence only. CRC
%   success is scored separately; low-SNR CRC failures can still be real
%   receiver evidence, but missing/proxy/configured SINR cannot.

ip = inputParser;
ip.addParameter("StrictMode", false, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
ip.parse(varargin{:});

strictMode = logical(ip.Results.StrictMode);

evidence = struct( ...
    "StrictReceiverEvidenceOk", false, ...
    "StrictOk", false, ...
    "TruthStatus", "invalid", ...
    "FailureReason", "", ...
    "ChannelEstimateAttempted", localBool(rx, "ChannelEstimateAttempted", false), ...
    "ChannelEstimateAvailable", false, ...
    "ChannelEstimateSource", string(localGet(rx, "ChannelEstimateSource", "")), ...
    "ResourceExtractionAttempted", localBool(rx, "ResourceExtractionAttempted", false), ...
    "ResourceExtractionAvailable", false, ...
    "EqualizationAttempted", localBool(rx, "EqualizationAttempted", false), ...
    "EqualizationAvailable", false, ...
    "ULSCHDecodeAttempted", localBool(rx, "ULSCHDecodeAttempted", localBool(rx, "DecodeAttempted", false)), ...
    "ULSCHDecodeAvailable", false, ...
    "LLRAvailable", localBool(rx, "LLRAvailable", false), ...
    "LLRFinite", false, ...
    "PostEqSINRAvailable", false, ...
    "PostEqSINRFinite", false, ...
    "PostEqSINRReceiverDerived", false, ...
    "PostEqSINRWidebanddB", NaN, ...
    "SINRValidationStatus", "fail", ...
    "SINRValidationReason", "", ...
    "SINRComputationMethod", string(localGet(rx, "SINRComputationMethod", "")), ...
    "ConfiguredSNRLikeSourceRejected", false);

Hest = localGet(rx, "ChannelEstimate", []);
evidence.ChannelEstimateAvailable = localBool(rx, "ChannelEstimateAvailable", false) || ...
    (~isempty(Hest) && isnumeric(Hest) && ...
    any(isfinite(real(Hest(:))) | isfinite(imag(Hest(:)))));

rxSym = localGet(rx, "PUSCHRxSymbolsForEvidence", []);
eqSym = localGet(rx, "EqualizedSymbolsForEvidence", []);
evidence.ResourceExtractionAvailable = ~isempty(rxSym) && isnumeric(rxSym);
evidence.EqualizationAvailable = ~isempty(eqSym) && isnumeric(eqSym) && ...
    any(isfinite(real(eqSym(:))) | isfinite(imag(eqSym(:))));

cwLLR = localGet(rx, "ULSCHCodewordLLR", localGet(rx, "CodewordLLR", []));
evidence.LLRAvailable = logical(evidence.LLRAvailable) || (~isempty(cwLLR) && isnumeric(cwLLR));
if ~isempty(cwLLR) && isnumeric(cwLLR)
    finiteMask = isfinite(double(cwLLR(:)));
    evidence.LLRFinite = any(finiteMask) && all(finiteMask);
else
    evidence.LLRFinite = localBool(rx, "LLRFinite", false);
end

tb = localGet(rx, "TransportBlock", []);
cb = localGet(rx, "DecodedCodeBlocks", []);
rateRecovered = localGet(rx, "RateRecoveredLLR", localGet(rx, "RecLLR", []));
evidence.ULSCHDecodeAvailable = (~isempty(tb) || ~isempty(cb) || ~isempty(rateRecovered)) && ...
    localBool(rx, "DecodeAttempted", false);

postEq = double(localGet(rx, "PostEqSINR_dB", NaN));
evidence.PostEqSINRWidebanddB = postEq;
evidence.PostEqSINRFinite = isscalar(postEq) && isfinite(postEq);

source = lower(strtrim(string(localGet(rx, "PostEqSINRSource", ""))));
role = lower(strtrim(string(localGet(rx, "PostEqSINRValueRole", ""))));
status = lower(strtrim(string(localGet(rx, "PostEqSINRValueStatus", ""))));
method = lower(strtrim(string(evidence.SINRComputationMethod)));
blocked = ["configured", "reference_snr", "cqi", "mcs", "oracle", "perfect", ...
    "proxy", "fallback", "evm", "sweep", "receiver_hest", "hest"];
blockedHit = any(contains(source, blocked)) || any(contains(role, blocked)) || any(contains(method, blocked));
evidence.ConfiguredSNRLikeSourceRejected = blockedHit;
evidence.PostEqSINRReceiverDerived = contains(source, "post_equalization") && ...
    contains(role, "measured_post_equalization") && ~blockedHit;
evidence.PostEqSINRAvailable = evidence.PostEqSINRFinite && ...
    evidence.PostEqSINRReceiverDerived && (status == "ok" || startsWith(status, "ok_"));

required = [
    evidence.ChannelEstimateAttempted
    evidence.ChannelEstimateAvailable
    evidence.ResourceExtractionAttempted
    evidence.ResourceExtractionAvailable
    evidence.EqualizationAttempted
    evidence.EqualizationAvailable
    evidence.ULSCHDecodeAttempted
    evidence.ULSCHDecodeAvailable
    evidence.LLRAvailable
    evidence.LLRFinite
    evidence.PostEqSINRAvailable
    ];

if all(required)
    evidence.StrictReceiverEvidenceOk = true;
    evidence.TruthStatus = "real_lls_evidence";
    evidence.SINRValidationStatus = "pass";
    evidence.SINRValidationReason = "";
    evidence.StrictOk = localBool(rx, "Ok", false) && ~localBool(rx, "CRCError", false);
    if ~evidence.StrictOk
        evidence.FailureReason = "tb_crc_failed";
    end
    return;
end

reasons = strings(0, 1);
if ~evidence.ChannelEstimateAttempted, reasons(end+1,1) = "channel_estimate_not_attempted"; end %#ok<AGROW>
if ~evidence.ChannelEstimateAvailable, reasons(end+1,1) = "channel_estimate_unavailable"; end %#ok<AGROW>
if ~evidence.ResourceExtractionAttempted, reasons(end+1,1) = "pusch_resource_extraction_not_attempted"; end %#ok<AGROW>
if ~evidence.ResourceExtractionAvailable, reasons(end+1,1) = "pusch_resource_extraction_unavailable"; end %#ok<AGROW>
if ~evidence.EqualizationAttempted, reasons(end+1,1) = "equalization_not_attempted"; end %#ok<AGROW>
if ~evidence.EqualizationAvailable, reasons(end+1,1) = "equalization_unavailable"; end %#ok<AGROW>
if ~evidence.ULSCHDecodeAttempted, reasons(end+1,1) = "ulsch_decode_not_attempted"; end %#ok<AGROW>
if ~evidence.ULSCHDecodeAvailable, reasons(end+1,1) = "ulsch_decode_evidence_unavailable"; end %#ok<AGROW>
if ~evidence.LLRAvailable, reasons(end+1,1) = "llr_unavailable"; end %#ok<AGROW>
if ~evidence.LLRFinite, reasons(end+1,1) = "llr_nonfinite"; end %#ok<AGROW>
if ~evidence.PostEqSINRFinite, reasons(end+1,1) = "posteq_sinr_nonfinite"; end %#ok<AGROW>
if evidence.ConfiguredSNRLikeSourceRejected, reasons(end+1,1) = "posteq_sinr_forbidden_source"; end %#ok<AGROW>
if ~evidence.PostEqSINRReceiverDerived, reasons(end+1,1) = "posteq_sinr_not_receiver_derived"; end %#ok<AGROW>
if ~evidence.PostEqSINRAvailable, reasons(end+1,1) = "posteq_sinr_unavailable"; end %#ok<AGROW>
if isempty(reasons)
    reasons = "strict_receiver_evidence_incomplete";
end

evidence.FailureReason = strjoin(unique(reasons, "stable"), "|");
evidence.SINRValidationReason = evidence.FailureReason;
if strictMode
    evidence.TruthStatus = "strict_receiver_evidence_failed";
else
    evidence.TruthStatus = "diagnostic_only";
end
end

function value = localGet(s, name, defaultValue)
if nargin < 3
    defaultValue = [];
end
value = defaultValue;
if isstruct(s) && isfield(s, char(name))
    value = s.(char(name));
end
end

function value = localBool(s, name, defaultValue)
raw = localGet(s, name, defaultValue);
if islogical(raw) && isscalar(raw)
    value = logical(raw);
elseif isnumeric(raw) && isscalar(raw) && isfinite(raw)
    value = raw ~= 0;
elseif isstring(raw) || ischar(raw)
    value = any(strcmpi(strtrim(char(string(raw))), {'true','1','yes','ok','pass'}));
else
    value = logical(defaultValue);
end
end
