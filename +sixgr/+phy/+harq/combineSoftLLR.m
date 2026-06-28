function [combinedLLR, info] = combineSoftLLR(currentLLR, priorLLR, varargin)
%COMBINESOFTLLR Position-aware HARQ soft combining in mother-code domain.
%   The current and prior observations must refer to the same LDPC mother
%   code layout. Redundancy-version differences are allowed because the
%   explicit rate-match position maps identify which mother-code positions
%   each observation updated.

ip = inputParser;
ip.addParameter("CurrentLayout", struct(), @(x) isempty(x) || isstruct(x));
ip.addParameter("PriorLayout", struct(), @(x) isempty(x) || isstruct(x) || iscell(x));
ip.addParameter("HARQKey", "", @(x) ischar(x) || isstring(x));
ip.addParameter("CodewordIndex", 1, @(x) isnumeric(x) && isscalar(x));
ip.parse(varargin{:});
opt = ip.Results;

current = localEnsureLLRMatrix(currentLLR);
priorEmpty = localIsEmptyPrior(priorLLR);
info = localDefaultInfo(current, priorLLR, opt);
combinedLLR = current;

if isempty(current)
    info.Reason = "current_llr_empty";
    if ~priorEmpty
        [priorBuffer, priorStatus] = localResolvePriorBuffer(priorLLR, opt.PriorLayout, opt);
        if priorStatus.Valid
            combinedLLR = localMaterializeBuffer(priorBuffer);
            info.PriorNumel = double(numel(combinedLLR));
            info.PriorPositionCount = double(nnz(priorBuffer.ObservationWeight(:) > 0));
            info.SoftBuffer = priorBuffer;
        end
    end
    return;
end

[currentBuffer, currentStatus] = localBuildSoftBuffer(current, opt.CurrentLayout, opt, "current");
if ~currentStatus.Valid
    info.Reason = currentStatus.Reason;
    return;
end
info.CurrentPositionCount = double(nnz(currentBuffer.ObservationWeight(:) > 0));
info.CurrentCombineSignature = currentBuffer.CombineSignature;
info.CurrentRateMatchSignature = currentBuffer.RateMatchSignature;
info.CodingLayoutHash = currentBuffer.CodingLayoutHash;
info.SoftBuffer = currentBuffer;

if priorEmpty
    info.Reason = "no_prior_harq_soft_buffer";
    combinedLLR = current;
    return;
end

[priorBuffer, priorStatus] = localResolvePriorBuffer(priorLLR, opt.PriorLayout, opt);
if ~priorStatus.Valid
    info.Reason = priorStatus.Reason;
    info.ResetPrior = true;
    combinedLLR = current;
    return;
end
info.PriorNumel = double(numel(priorBuffer.LLRSum));
info.PriorPositionCount = double(nnz(priorBuffer.ObservationWeight(:) > 0));
info.PriorCombineSignature = priorBuffer.CombineSignature;
info.PriorRateMatchSignature = priorBuffer.RateMatchSignature;

[compatible, reason] = localBuffersCompatible(currentBuffer, priorBuffer);
if ~compatible
    info.Reason = reason;
    info.ResetPrior = true;
    combinedLLR = current;
    info.SoftBuffer = currentBuffer;
    return;
end

merged = localMergeBuffers(currentBuffer, priorBuffer, opt);
combinedLLR = localMaterializeBuffer(merged);

info.Applied = true;
info.PositionAware = true;
info.Reason = "position_aware_harq_soft_buffer_accumulated";
info.CombinedNumel = double(numel(combinedLLR));
info.CombinedPositionCount = double(nnz(merged.ObservationWeight(:) > 0));
info.OverlapPositionCount = double(nnz(currentBuffer.ObservationWeight(:) > 0 & ...
    priorBuffer.ObservationWeight(:) > 0));
info.SoftBuffer = merged;
info.LLRCombiningGain_dB = localCombiningGain(current, combinedLLR);
end

function info = localDefaultInfo(current, prior, opt)
priorCount = NaN;
if isnumeric(prior) || islogical(prior)
    priorCount = double(numel(prior));
elseif isstruct(prior)
    soft = localStructGet(prior, "SoftBuffer", struct());
    if isstruct(soft) && isfield(soft, "LLRSum")
        priorCount = double(numel(soft.LLRSum));
    else
        v = localStructGet(prior, "LLR", localStructGet(prior, "RateRecoveredLLR", []));
        if isnumeric(v) || islogical(v)
            priorCount = double(numel(v));
        end
    end
end
info = struct( ...
    "ContractVersion", "HARQSoftCombineInfo/v1", ...
    "Applied", false, ...
    "PositionAware", false, ...
    "Reason", "not_evaluated", ...
    "ResetPrior", false, ...
    "CurrentNumel", double(numel(current)), ...
    "PriorNumel", priorCount, ...
    "CombinedNumel", double(numel(current)), ...
    "CurrentPositionCount", NaN, ...
    "PriorPositionCount", NaN, ...
    "CombinedPositionCount", NaN, ...
    "OverlapPositionCount", NaN, ...
    "CurrentCombineSignature", "", ...
    "PriorCombineSignature", "", ...
    "CurrentRateMatchSignature", "", ...
    "PriorRateMatchSignature", "", ...
    "CodingLayoutHash", "", ...
    "HARQKey", char(string(opt.HARQKey)), ...
    "CodewordIndex", double(opt.CodewordIndex), ...
    "LLRCombiningGain_dB", NaN, ...
    "SoftBuffer", struct());
end

function [buffer, status] = localResolvePriorBuffer(prior, priorLayout, opt)
status = struct("Valid", false, "Reason", "prior_harq_soft_buffer_unavailable");
buffer = struct();
if localIsEmptyPrior(prior)
    return;
end
if iscell(prior)
    idx = max(1, round(double(opt.CodewordIndex)));
    if numel(prior) < idx || isempty(prior{idx})
        return;
    end
    prior = prior{idx};
end
if iscell(priorLayout)
    idx = max(1, round(double(opt.CodewordIndex)));
    if numel(priorLayout) >= idx
        priorLayout = priorLayout{idx};
    else
        priorLayout = struct();
    end
end
if isstruct(prior)
    soft = localStructGet(prior, "SoftBuffer", struct());
    if isstruct(soft) && isfield(soft, "LLRSum") && isfield(soft, "ObservationWeight")
        buffer = localNormalizeSoftBuffer(soft);
        status.Valid = true;
        status.Reason = "";
        return;
    end
    if isfield(prior, "LLRSum") && isfield(prior, "ObservationWeight")
        buffer = localNormalizeSoftBuffer(prior);
        status.Valid = true;
        status.Reason = "";
        return;
    end
    if ~(isstruct(priorLayout) && ~isempty(fieldnames(priorLayout)))
        priorLayout = localStructGet(prior, "CodingLayout", struct());
    end
    prior = localStructGet(prior, "LLR", localStructGet(prior, "RateRecoveredLLR", []));
end
[buffer, status] = localBuildSoftBuffer(localEnsureLLRMatrix(prior), priorLayout, opt, "prior");
end

function [buffer, status] = localBuildSoftBuffer(llr, layout, opt, source)
buffer = struct();
status = struct("Valid", false, "Reason", "harq_soft_buffer_layout_missing");
if isempty(llr)
    status.Reason = source + "_llr_empty";
    return;
end
llr = localEnsureLLRMatrix(llr);
if ~(isstruct(layout) && ~isempty(fieldnames(layout)))
    return;
end
[layoutHash, combineSignature, rateMatchSignature] = localLayoutHashes(layout);
if strlength(string(layoutHash)) == 0
    status.Reason = "harq_soft_buffer_coding_layout_hash_missing";
    return;
end
[idx, rawIdx] = localObservedIndices(layout, numel(llr));
if isempty(idx)
    status.Reason = "harq_soft_buffer_position_map_missing";
    return;
end

llrVec = double(llr(:));
counts = accumarray(double(idx(:)), 1, [numel(llrVec), 1], @sum, 0);
observed = counts > 0;
finiteObserved = observed & isfinite(llrVec);
llrSum = zeros(size(llr), "double");
weight = zeros(size(llr), "double");
sumVec = llrSum(:);
weightVec = weight(:);
sumVec(finiteObserved) = llrVec(finiteObserved);
weightVec(observed) = counts(observed);
llrSum = reshape(sumVec, size(llr));
weight = reshape(weightVec, size(llr));
fillerMask = isinf(llr);

buffer = struct( ...
    "ContractVersion", "HARQSoftBuffer/v1", ...
    "Domain", "mother_code_llr_by_code_block", ...
    "LLRSum", llrSum, ...
    "ObservationWeight", weight, ...
    "LLR", localMaterializeArrays(llrSum, weight, fillerMask), ...
    "RateRecoveredLLR", localMaterializeArrays(llrSum, weight, fillerMask), ...
    "CodingLayout", layout, ...
    "CodingLayoutHash", char(string(layoutHash)), ...
    "CombineSignature", char(string(combineSignature)), ...
    "RateMatchSignature", char(string(rateMatchSignature)), ...
    "PositionMap", localStructGet(layout, "RateMatchPositionMap", struct()), ...
    "ObservedLinearIndex", uint32(find(observed)), ...
    "RateMatchLinearIndex", uint32(rawIdx(:)), ...
    "MotherCodeShape", uint32(size(llr)), ...
    "FillerMask", logical(fillerMask), ...
    "HARQKey", char(string(opt.HARQKey)), ...
    "CodewordIndex", double(opt.CodewordIndex), ...
    "ObservationSource", char(string(source)));
status.Valid = true;
status.Reason = "";
end

function buffer = localNormalizeSoftBuffer(buffer)
buffer.LLRSum = double(buffer.LLRSum);
buffer.ObservationWeight = double(buffer.ObservationWeight);
if ~isfield(buffer, "FillerMask") || isempty(buffer.FillerMask)
    buffer.FillerMask = isinf(buffer.LLRSum);
else
    buffer.FillerMask = logical(buffer.FillerMask);
end
if ~isfield(buffer, "LLR") || isempty(buffer.LLR)
    buffer.LLR = localMaterializeBuffer(buffer);
end
if ~isfield(buffer, "RateRecoveredLLR") || isempty(buffer.RateRecoveredLLR)
    buffer.RateRecoveredLLR = buffer.LLR;
end
if ~isfield(buffer, "CodingLayoutHash") || strlength(string(buffer.CodingLayoutHash)) == 0
    layout = localStructGet(buffer, "CodingLayout", struct());
    [hash, combineSignature, rateMatchSignature] = localLayoutHashes(layout);
    buffer.CodingLayoutHash = char(string(hash));
    buffer.CombineSignature = char(string(combineSignature));
    buffer.RateMatchSignature = char(string(rateMatchSignature));
end
end

function [compatible, reason] = localBuffersCompatible(current, prior)
compatible = false;
reason = "coding_layout_mismatch_soft_combine_rejected";
if ~isequal(size(current.LLRSum), size(prior.LLRSum)) || ...
        ~isequal(size(current.ObservationWeight), size(prior.ObservationWeight))
    reason = "mother_code_shape_mismatch_soft_combine_rejected";
    return;
end
if strlength(string(current.CodingLayoutHash)) == 0 || strlength(string(prior.CodingLayoutHash)) == 0
    reason = "coding_layout_hash_missing_soft_combine_rejected";
    return;
end
if string(current.CodingLayoutHash) ~= string(prior.CodingLayoutHash)
    return;
end
compatible = true;
reason = "";
end

function merged = localMergeBuffers(current, prior, opt)
merged = current;
merged.LLRSum = double(prior.LLRSum) + double(current.LLRSum);
merged.ObservationWeight = double(prior.ObservationWeight) + double(current.ObservationWeight);
merged.FillerMask = logical(localStructGet(prior, "FillerMask", false(size(current.LLRSum)))) | ...
    logical(localStructGet(current, "FillerMask", false(size(current.LLRSum))));
merged.LLR = localMaterializeBuffer(merged);
merged.RateRecoveredLLR = merged.LLR;
merged.ObservedLinearIndex = uint32(find(merged.ObservationWeight(:) > 0));
merged.HARQKey = char(string(opt.HARQKey));
merged.CodewordIndex = double(opt.CodewordIndex);
merged.ObservationSource = "combined_harq_soft_buffer";
end

function X = localMaterializeBuffer(buffer)
X = localMaterializeArrays(buffer.LLRSum, buffer.ObservationWeight, ...
    localStructGet(buffer, "FillerMask", false(size(buffer.LLRSum))));
end

function X = localMaterializeArrays(llrSum, weight, fillerMask)
X = double(llrSum);
X(double(weight) <= 0) = 0;
if ~isempty(fillerMask)
    mask = logical(fillerMask);
    if isequal(size(mask), size(X))
        X(mask) = Inf;
    end
end
end

function [idx, rawIdx] = localObservedIndices(layout, n)
idx = [];
rawIdx = [];
positionMap = localStructGet(layout, "RateMatchPositionMap", struct());
if isempty(positionMap) || ~(isstruct(positionMap) && isfield(positionMap, "MotherCodeLinearIndex"))
    positionMap = localStructGet(layout, "CircularBufferPositionMap", struct());
end
if isstruct(positionMap) && isfield(positionMap, "MotherCodeLinearIndex")
    rawIdx = double(positionMap.MotherCodeLinearIndex(:));
    rawIdx = rawIdx(isfinite(rawIdx));
    idx = round(rawIdx);
    idx = idx(idx >= 1 & idx <= n);
end
end

function [layoutHash, combineSignature, rateMatchSignature] = localLayoutHashes(layout)
layoutHash = "";
combineSignature = "";
rateMatchSignature = "";
if ~(isstruct(layout) && ~isempty(fieldnames(layout)))
    return;
end
combineSignature = string(localStructGet(layout, "CombineSignature", ""));
layoutHash = string(localStructGet(layout, "CodingLayoutHash", combineSignature));
rateMatchSignature = string(localStructGet(layout, "RateMatchSignature", ""));
end

function X = localEnsureLLRMatrix(v)
if isempty(v)
    X = [];
    return;
end
if isstruct(v)
    v = localStructGet(v, "LLR", localStructGet(v, "RateRecoveredLLR", []));
end
X = double(v);
if isvector(X)
    X = X(:);
end
end

function tf = localIsEmptyPrior(prior)
tf = isempty(prior);
if tf
    return;
end
if iscell(prior)
    tf = all(cellfun(@isempty, prior));
    return;
end
if ~isstruct(prior)
    return;
end
if isfield(prior, "LLRSum") || isfield(prior, "SoftBuffer")
    tf = false;
    return;
end
v = localStructGet(prior, "LLR", localStructGet(prior, "RateRecoveredLLR", []));
tf = isempty(v);
end

function g = localCombiningGain(current, combined)
g = NaN;
try
    a = double(current(:));
    b = double(combined(:));
    a = a(isfinite(a));
    b = b(isfinite(b));
    ea = mean(abs(a).^2, "omitnan");
    eb = mean(abs(b).^2, "omitnan");
    if isfinite(ea) && ea > 0 && isfinite(eb) && eb > 0
        g = 10 * log10(eb / ea);
    end
catch
end
end

function value = localStructGet(s, field, fallback)
value = fallback;
if isstruct(s) && isfield(s, field)
    value = s.(field);
end
end
