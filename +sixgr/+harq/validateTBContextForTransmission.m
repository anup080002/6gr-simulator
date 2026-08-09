function [ctx, status] = validateTBContextForTransmission(meta)
%VALIDATETBCONTEXTFORTRANSMISSION Enforce HARQ TB-context invariants.
% Keep this file ASCII-only.

if nargin < 1 || ~isstruct(meta)
    error("sixgr:harq:BadValidationMeta", ...
        "validateTBContextForTransmission requires a meta struct.");
end

previous = localContextStruct(sixgr.util.structGet(meta, "PreviousContext", ...
    sixgr.util.structGet(meta, "TransportBlockContext", struct())));
ctx = sixgr.harq.createTBContext(meta);
hasPrevious = ~isempty(fieldnames(previous));
isRetxFlag = localFirstLogical( ...
    sixgr.util.structGet(meta, "IsRetransmission", []), ...
    sixgr.util.structGet(meta, "Grant.IsRetransmission", []), ...
    false);
ndiToggled = hasPrevious && localComparableLogical(previous, "NDI") && ...
    localComparableLogical(ctx, "NDI") && ...
    logical(previous.NDI) ~= logical(ctx.NDI);
isNewTransmission = ~hasPrevious || ndiToggled || ~isRetxFlag;

status = struct();
status.ContractVersion = "HARQTBContextStatus/v1";
status.IsRetransmission = logical(~isNewTransmission);
status.ShortIRRetx = false;
status.OriginalTBSBits = double(ctx.TBSBits);
status.CurrentTBSBits = double(ctx.TBSBits);
status.OriginalRateMatchedBits = double(ctx.OriginalRateMatchedBitsTotal);
status.CurrentRateMatchedBits = double(ctx.CurrentRateMatchedBitsTotal);
status.EffectiveInitialCodeRate = double(ctx.EffectiveInitialCodeRate);
status.EffectiveCurrentTxCodeRate = double(ctx.EffectiveCurrentTxCodeRate);
status.CodeBlockLayoutHash = char(string(ctx.CodeBlockLayoutHash));
status.HARQContextHash = char(string(ctx.HARQContextHash));
status.HARQContextStatus = "not_validated";

expectedTBS = localFirstFiniteScalar( ...
    sixgr.util.structGet(meta, "ExpectedTBSBits", NaN), ...
    sixgr.util.structGet(meta, "ComputedTBSBits", NaN), ...
    NaN);
if isfinite(expectedTBS) && round(double(expectedTBS)) ~= round(double(ctx.TBSBits))
    error("sixgr:harq:TBSMismatch", ...
        "HARQ TB context TBSBits=%d does not match expected TBS=%d.", ...
        round(double(ctx.TBSBits)), round(double(expectedTBS)));
end

if ~(isfinite(double(status.EffectiveInitialCodeRate)) && ...
        double(status.EffectiveInitialCodeRate) > 0 && ...
        double(status.EffectiveInitialCodeRate) <= 0.95)
    error("sixgr:harq:BadInitialCodeRate", ...
        ['HARQ TB context initial effective code rate %.6f must be in ' ...
         '(0, 0.95] (TBSBits=%d, rateMatchedBits=%d, MCS=%g, ' ...
         'modulation=%s, layers=%g, targetCodeRate=%.6f).'], ...
        double(status.EffectiveInitialCodeRate), round(double(ctx.TBSBits)), ...
        round(double(ctx.OriginalRateMatchedBitsTotal)), ...
        double(ctx.OriginalMCS), char(string(ctx.OriginalModulation)), ...
        double(ctx.OriginalNumLayers), double(ctx.OriginalTargetCodeRate));
end
if ~(isfinite(double(status.CurrentRateMatchedBits)) && double(status.CurrentRateMatchedBits) > 0)
    error("sixgr:harq:MissingCurrentRateMatchBudget", ...
        "HARQ transmission requires a positive current rate-matched bit budget.");
end
if strlength(string(ctx.CodeBlockLayoutHash)) < 1
    error("sixgr:harq:MissingCodeBlockLayoutHash", ...
        "HARQ transmission requires a non-empty code-block layout hash.");
end

if isNewTransmission
    status.HARQContextStatus = "new_tx_validated";
    if hasPrevious && ndiToggled
        status.HARQContextStatus = "new_tx_ndi_toggle_validated";
    end
    ctx.ShortIRRetx = false;
    ctx.HARQContextHash = char(status.HARQContextHash);
    return;
end

localAssertSameValue(previous, ctx, "Direction", "HARQ direction");
localAssertSameValue(previous, ctx, "CellId", "CellId");
localAssertSameValue(previous, ctx, "UeId", "UeId");
localAssertSameValue(previous, ctx, "RNTI", "RNTI");
localAssertSameValue(previous, ctx, "HARQProcessId", "HARQProcessId");
localAssertSameValue(previous, ctx, "NDIEpoch", "NDIEpoch");
localAssertSameValue(previous, ctx, "TBId", "TBId");
localAssertSameValue(previous, ctx, "CodewordId", "CodewordId");
if logical(previous.NDI) ~= logical(ctx.NDI)
    error("sixgr:harq:NDIToggledOnRetransmission", ...
        "HARQ retransmission toggled NDI from %d to %d.", ...
        logical(previous.NDI), logical(ctx.NDI));
end
if round(double(previous.TBSBits)) ~= round(double(ctx.TBSBits))
    error("sixgr:harq:RetransmissionTBSMismatch", ...
        "HARQ retransmission TBSBits=%d does not match original TBSBits=%d.", ...
        round(double(ctx.TBSBits)), round(double(previous.TBSBits)));
end
if string(previous.CodeBlockLayoutHash) ~= string(ctx.CodeBlockLayoutHash)
    error("sixgr:harq:CodeBlockLayoutMismatch", ...
        "HARQ retransmission code-block layout hash '%s' does not match original '%s'.", ...
        char(string(ctx.CodeBlockLayoutHash)), char(string(previous.CodeBlockLayoutHash)));
end

rvSequence = localNumericRow(localFirstNonEmpty( ...
    sixgr.util.structGet(meta, "RVSequence", []), ...
    sixgr.util.structGet(previous, "RVSequence", [])));
currentRV = localFirstFiniteScalar( ...
    sixgr.util.structGet(meta, "RV", NaN), ...
    sixgr.util.structGet(ctx, "LastObservedRV", NaN), NaN);
previousRV = localFirstFiniteScalar( ...
    sixgr.util.structGet(meta, "PreviousRV", NaN), ...
    sixgr.util.structGet(previous, "LastObservedRV", NaN), NaN);
if ~isempty(rvSequence) && isfinite(previousRV) && isfinite(currentRV)
    localAssertRVSequence(rvSequence, previousRV, currentRV);
end

status.ShortIRRetx = double(status.CurrentRateMatchedBits) < double(ctx.TBSBits);
ctx.ShortIRRetx = logical(status.ShortIRRetx);
softCombiningEvidence = localFirstLogical( ...
    sixgr.util.structGet(meta, "SoftCombiningEvidenceAvailable", []), ...
    sixgr.util.structGet(meta, "PreviousCombinedLLRAvailable", []), ...
    false);
if status.ShortIRRetx && ~softCombiningEvidence
    error("sixgr:harq:ShortIRRequiresSoftCombiningEvidence", ...
        "HARQ retransmission current E=%d is smaller than TBSBits=%d without soft-combining evidence.", ...
        round(double(status.CurrentRateMatchedBits)), round(double(ctx.TBSBits)));
end

status.HARQContextStatus = "retransmission_validated";
if status.ShortIRRetx
    status.HARQContextStatus = "retransmission_validated_short_ir";
end
ctx.HARQContextHash = char(status.HARQContextHash);
end

function ctx = localContextStruct(value)
if isstruct(value)
    ctx = value;
else
    ctx = struct();
end
end

function tf = localComparableLogical(s, fieldName)
tf = isstruct(s) && isfield(s, fieldName) && isscalar(s.(fieldName)) && ...
    (islogical(s.(fieldName)) || isnumeric(s.(fieldName)));
end

function value = localFirstFiniteScalar(varargin)
value = NaN;
for i = 1:nargin
    raw = varargin{i};
    if isempty(raw)
        continue;
    end
    if islogical(raw)
        raw = double(raw);
    elseif ~isnumeric(raw)
        continue;
    end
    raw = double(raw(:));
    raw = raw(isfinite(raw));
    if ~isempty(raw)
        value = raw(1);
        return;
    end
end
end

function tf = localFirstLogical(varargin)
tf = false;
for i = 1:nargin
    raw = varargin{i};
    if isempty(raw)
        continue;
    end
    if islogical(raw)
        tf = logical(raw(1));
        return;
    end
    if isnumeric(raw)
        raw = double(raw(:));
        raw = raw(isfinite(raw));
        if ~isempty(raw)
            tf = logical(raw(1));
            return;
        end
    end
end
end

function value = localFirstNonEmpty(varargin)
value = [];
for i = 1:nargin
    raw = varargin{i};
    if isstring(raw)
        if any(strlength(strtrim(raw)) > 0)
            value = raw;
            return;
        end
    elseif ischar(raw)
        if strlength(strtrim(string(raw))) > 0
            value = raw;
            return;
        end
    elseif isnumeric(raw) || islogical(raw)
        if ~isempty(raw)
            value = raw;
            return;
        end
    elseif iscell(raw) || isstruct(raw)
        if ~isempty(raw)
            value = raw;
            return;
        end
    end
end
end

function row = localNumericRow(raw)
if isempty(raw)
    row = zeros(1, 0);
    return;
end
row = double(raw(:).');
row = row(isfinite(row));
end

function localAssertSameValue(previous, current, fieldName, label)
prevValue = sixgr.util.structGet(previous, fieldName, []);
curValue = sixgr.util.structGet(current, fieldName, []);
if isnumeric(prevValue) || islogical(prevValue) || isnumeric(curValue) || islogical(curValue)
    prevNum = localFirstFiniteScalar(prevValue, NaN);
    curNum = localFirstFiniteScalar(curValue, NaN);
    if isfinite(prevNum) && isfinite(curNum) && abs(prevNum - curNum) > 1e-9
        error("sixgr:harq:RetransmissionContextMismatch", ...
            "HARQ retransmission %s changed from %s to %s.", ...
            char(string(label)), mat2str(prevNum), mat2str(curNum));
    end
    return;
end
prevText = strtrim(string(prevValue));
curText = strtrim(string(curValue));
if numel(prevText) > 1
    prevText = prevText(1);
end
if numel(curText) > 1
    curText = curText(1);
end
prevToken = char(prevText);
curToken = char(curText);
if ~isempty(prevToken) && ~isempty(curToken) && ~strcmp(prevToken, curToken)
    error("sixgr:harq:RetransmissionContextMismatch", ...
        "HARQ retransmission %s changed from '%s' to '%s'.", ...
        char(string(label)), prevToken, curToken);
end
end

function localAssertRVSequence(sequence, previousRV, currentRV)
sequence = round(double(sequence(:).'));
if isempty(sequence)
    return;
end
previousRV = round(double(previousRV));
currentRV = round(double(currentRV));
idx = find(sequence == previousRV, 1, "last");
if isempty(idx)
    error("sixgr:harq:RVSequenceMismatch", ...
        "Previous HARQ RV %d is not present in the configured RV sequence.", previousRV);
end
nextIdx = min(idx + 1, numel(sequence));
expectedRV = sequence(nextIdx);
if currentRV ~= expectedRV
    error("sixgr:harq:RVSequenceMismatch", ...
        "HARQ retransmission RV %d does not follow configured RV sequence after RV %d (expected %d).", ...
        currentRV, previousRV, expectedRV);
end
end
