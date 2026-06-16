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
score.CandidatesAttempted = height(cand);
score.CandidatesDecoded = sum(logical(cand.CrcPass));
score.FalseCandidateCount = double(falseCandidates);
score.BestCandidateMetric = double(best);
score.SecondBestCandidateMetric = double(second);
score.MetricMargin = double(margin);
score.DetectionMetric = double(best);
score.Status = status;
score.FailureReason = failure;
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
