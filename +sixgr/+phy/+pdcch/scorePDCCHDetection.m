function score = scorePDCCHDetection(det, tx, strictCfg, varargin)
%SCOREPDCCHDETECTION Score positive and negative strict PDCCH trials.

p = inputParser;
addRequired(p, "det", @isstruct);
addRequired(p, "tx", @(x) isstruct(x) || isempty(x));
addRequired(p, "strictCfg", @isstruct);
addParameter(p, "TrialType", "positive_dci_1_0", @(x) ischar(x) || isstring(x));
addParameter(p, "NegativeExpected", false, @(x) islogical(x) || isnumeric(x));
addParameter(p, "GrantMustBeValid", true, @(x) islogical(x) || isnumeric(x));
parse(p, det, tx, strictCfg, varargin{:});
opt = p.Results;

trialType = string(opt.TrialType);
negativeExpected = logical(opt.NegativeExpected);
rxOk = logical(sixgr.util.structGet(det.Rx, "Ok", false));
payloadMatch = false;
grantValid = false;
grant = struct();
fieldEqualRows = table();
if rxOk
    [grant, validation] = sixgr.phy.pdcch.validateDecodedDCIGrant(det.DecodedDCI, strictCfg);
    grantValid = logical(validation.Valid);
end
if rxOk && isstruct(tx) && isfield(tx, "DCI")
    payloadMatch = string(tx.DCI.PayloadHash) == string(det.DecodedDCI.PayloadHash);
    fieldEqualRows = localFieldEquality(tx.DCI, det.DecodedDCI, strictCfg, trialType);
end
[controlResourceValid, controlResourceReason] = localControlResourceValidity(strictCfg, det);
cand = det.Candidates;
metrics = double(cand.Metric);
metrics = metrics(isfinite(metrics));
best = NaN; second = NaN; margin = NaN;
if ~isempty(metrics)
    sorted = sort(metrics, "descend");
    best = sorted(1);
    if numel(sorted) >= 2
        second = sorted(2);
    else
        second = 0;
    end
    margin = best - second;
end
falseCandidates = sum(logical(cand.CrcPass) & ~logical(cand.SelectedCandidate));
strictOk = ~negativeExpected && rxOk && payloadMatch && grantValid && falseCandidates == 0 && ...
    controlResourceValid && ...
    strlength(string(det.UsedOracleFields)) == 0 && ~logical(det.ProxyUsed) && ...
    ~logical(det.Skipped) && ~logical(det.ToolboxMissing);
formatMismatch = rxOk && isstruct(tx) && isfield(tx, "DCI") && ...
    string(det.DCIFormatAttempted) ~= string(tx.DCI.Format);
invalidGrantExpected = contains(lower(trialType), "invalid_grant");
negativeOk = negativeExpected && falseCandidates == 0 && ...
    (~rxOk || formatMismatch || (invalidGrantExpected && rxOk && ~grantValid));
if strictOk
    status = "strict_pdcch_positive_pass";
    failure = "";
elseif negativeOk
    status = "strict_pdcch_negative_rejected";
    failure = "";
elseif negativeExpected
    status = "strict_pdcch_negative_failed";
    failure = "negative_trial_produced_valid_decode_or_false_candidate";
else
    status = "strict_pdcch_positive_failed";
    failure = "crc_payload_or_grant_validation_failed";
end

score = struct();
score.TrialType = trialType;
score.StrictOk = strictOk;
score.NegativeExpectedOk = negativeOk;
score.PayloadMatch = payloadMatch;
score.GrantValid = grantValid;
score.Grant = grant;
score.FieldEquality = fieldEqualRows;
score.ControlResourceValidity = logical(controlResourceValid);
score.ControlResourceFailureReason = string(controlResourceReason);
score.CandidatesAttempted = height(cand);
score.CandidatesDecoded = sum(logical(cand.CrcPass));
score.FalseCandidateCount = double(falseCandidates);
score.BestCandidateMetric = double(best);
score.SecondBestCandidateMetric = double(second);
score.MetricMargin = double(margin);
score.DetectionMetric = double(best);
score.Status = status;
score.FailureReason = failure;
if ~score.StrictOk && strlength(score.ControlResourceFailureReason) > 0 && ~negativeExpected
    parts = [string(score.FailureReason); string(score.ControlResourceFailureReason)];
    parts = parts(strlength(strtrim(parts)) > 0);
    score.FailureReason = strjoin(parts, "|");
end
end

function [valid, reason] = localControlResourceValidity(strictCfg, det)
reasons = strings(0, 1);
nCellID = double(sixgr.util.structGet(strictCfg, "NCellID", NaN));
if ~(isscalar(nCellID) && isfinite(nCellID) && nCellID >= 0 && nCellID <= 1007)
    reasons(end + 1, 1) = "invalid_ncellid"; %#ok<AGROW>
end
if ~(isfinite(double(sixgr.util.structGet(strictCfg, "NSizeGrid", NaN))) && double(strictCfg.NSizeGrid) > 0)
    reasons(end + 1, 1) = "invalid_carrier_grid"; %#ok<AGROW>
end
if ~(isfinite(double(sixgr.util.structGet(strictCfg, "CORESETDurationSymbols", NaN))) && ...
        double(strictCfg.CORESETDurationSymbols) >= 1 && double(strictCfg.CORESETDurationSymbols) <= 3)
    reasons(end + 1, 1) = "invalid_coreset_duration"; %#ok<AGROW>
end
freqResources = double(sixgr.util.structGet(strictCfg, "CORESETFrequencyDomainResources", []));
if isempty(freqResources) || ~any(freqResources(:) > 0)
    reasons(end + 1, 1) = "coreset_frequency_resources_missing"; %#ok<AGROW>
end
aggregationLevel = double(sixgr.util.structGet(strictCfg, "AggregationLevel", NaN));
if ~ismember(aggregationLevel, [1 2 4 8 16])
    reasons(end + 1, 1) = "invalid_aggregation_level"; %#ok<AGROW>
end
candidateIndex = double(sixgr.util.structGet(strictCfg, "CandidateIndex", NaN));
if ~(isfinite(candidateIndex) && candidateIndex >= 1)
    reasons(end + 1, 1) = "invalid_candidate_index"; %#ok<AGROW>
end
txCCEIndex = double(sixgr.util.structGet(strictCfg, "CandidateCCEIndex", NaN));
if isfinite(txCCEIndex) && isfinite(aggregationLevel) && aggregationLevel > 0 && mod(txCCEIndex, aggregationLevel) ~= 0
    reasons(end + 1, 1) = "cce_start_not_aligned_to_aggregation_level"; %#ok<AGROW>
end
dciBits = double(sixgr.util.structGet(strictCfg, "DCIPayloadSizeBits", NaN));
if ~(isfinite(dciBits) && dciBits >= 12 && dciBits <= 140)
    reasons(end + 1, 1) = "invalid_dci_payload_size"; %#ok<AGROW>
end
strictValidation = sixgr.util.structGet(strictCfg, "StrictValidation", struct());
if isstruct(strictValidation) && isfield(strictValidation, "StrictValid") && ~logical(strictValidation.StrictValid)
    raw = string(sixgr.util.structGet(strictValidation, "StrictUnsupportedReason", "strict_config_invalid"));
    raw = raw(strlength(raw) > 0);
    if isempty(raw)
        raw = "strict_config_invalid";
    end
    reasons(end + 1, 1) = raw; %#ok<AGROW>
end
if isstruct(det) && isfield(det, "Tx") && isstruct(det.Tx)
    txNCellID = double(sixgr.util.structGet(det.Tx, "NCellID", nCellID));
    if isfinite(txNCellID) && isfinite(nCellID) && txNCellID ~= nCellID
        reasons(end + 1, 1) = "ncellid_mismatch"; %#ok<AGROW>
    end
end
valid = isempty(reasons);
reason = strjoin(unique(reasons(:), "stable"), "|");
end

function T = localFieldEquality(txDci, rxDci, strictCfg, trialType)
txT = txDci.FieldTable;
rxT = rxDci.FieldTable;
names = string(txT.FieldName);
rows = repmat(struct("RunId", "", "TrialId", NaN, "Direction", "", ...
    "DCIFormat", "", "RNTIType", "", "FieldName", "", "TxValue", "", ...
    "RxValue", "", "Equal", false, "BitOffsetStart", NaN, "BitOffsetEnd", NaN, ...
    "Status", ""), numel(names), 1);
for ii = 1:numel(names)
    rxIdx = find(string(rxT.FieldName) == names(ii), 1);
    txVal = string(txT.Value(ii));
    rxVal = "";
    eq = false;
    if ~isempty(rxIdx)
        rxVal = string(rxT.Value(rxIdx));
        eq = txVal == rxVal;
    end
    rows(ii).RunId = string(strictCfg.RunId);
    rows(ii).TrialId = NaN;
    rows(ii).Direction = string(txDci.Direction);
    rows(ii).DCIFormat = string(txDci.Format);
    rows(ii).RNTIType = string(strictCfg.RNTIType);
    rows(ii).FieldName = names(ii);
    rows(ii).TxValue = txVal;
    rows(ii).RxValue = rxVal;
    rows(ii).Equal = eq;
    rows(ii).BitOffsetStart = double(txT.BitOffsetStart(ii));
    rows(ii).BitOffsetEnd = double(txT.BitOffsetEnd(ii));
    rows(ii).Status = string(ternary(eq, "equal", "mismatch")) + "_" + trialType;
end
T = struct2table(rows, "AsArray", true);
end

function out = ternary(cond, a, b)
if cond
    out = a;
else
    out = b;
end
end
