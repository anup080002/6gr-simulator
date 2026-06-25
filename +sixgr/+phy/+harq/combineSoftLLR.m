function [combinedLLR, info] = combineSoftLLR(currentLLR, priorLLR, varargin)
%COMBINESOFTLLR HARQ soft combining for rate-recovered LLRs.
%
% The inputs must already be in the same rate-recovered LDPC code-block
% domain. Combining is an LLR sum, equivalent to multiplying independent
% likelihoods before LDPC decoding.

opt = localParseOpts(varargin{:});
[priorLLR, priorLayoutFromBuffer] = localUnwrapSoftBuffer(priorLLR);
if isempty(opt.PriorLayout)
    opt.PriorLayout = priorLayoutFromBuffer;
end

combinedLLR = currentLLR;
info = struct( ...
    "Applied", false, ...
    "Reason", "", ...
    "CurrentNumel", double(numel(currentLLR)), ...
    "PriorNumel", double(numel(priorLLR)), ...
    "CombinedNumel", double(numel(currentLLR)), ...
    "CurrentCombineSignature", "", ...
    "PriorCombineSignature", "");

if isempty(priorLLR)
    info.Reason = "no_prior_harq_soft_buffer";
    return;
end
if isempty(currentLLR)
    info.Reason = "current_llr_empty";
    return;
end
if localLayoutMissing(opt.CurrentLayout) || localLayoutMissing(opt.PriorLayout)
    info.Reason = "missing_coding_layout_soft_combine_rejected";
    return;
end
[compatible, currentSig, priorSig] = localCompatibleLayouts(opt.CurrentLayout, opt.PriorLayout);
info.CurrentCombineSignature = currentSig;
info.PriorCombineSignature = priorSig;
if ~compatible
    info.Reason = "coding_layout_mismatch_soft_combine_rejected";
    return;
end
if numel(currentLLR) ~= numel(priorLLR)
    info.Reason = "soft_buffer_size_mismatch";
    return;
end

cur = double(currentLLR);
prior = double(reshape(priorLLR, size(currentLLR)));
mask = isfinite(cur) & isfinite(prior);
if ~any(mask(:))
    info.Reason = "no_finite_llr_overlap";
    return;
end

combined = cur;
combined(mask) = cur(mask) + prior(mask);
combined(~isfinite(combined)) = cur(~isfinite(combined));
combinedLLR = combined;
info.Applied = true;
info.Reason = "llr_sum_same_coding_layout_mother_code_domain";
info.CombinedNumel = double(numel(combinedLLR));
end

function opt = localParseOpts(varargin)
opt = struct("CurrentLayout", [], "PriorLayout", []);
if isempty(varargin)
    return;
end
if mod(numel(varargin), 2) ~= 0
    error("sixgr:phy:harq:BadCombineSoftLLRNV", ...
        "Name-value arguments must come in pairs.");
end
for i = 1:2:numel(varargin)
    key = lower(string(varargin{i}));
    switch key
        case "currentlayout"
            opt.CurrentLayout = varargin{i + 1};
        case "priorlayout"
            opt.PriorLayout = varargin{i + 1};
        otherwise
            error("sixgr:phy:harq:BadCombineSoftLLRNV", ...
                "Unknown option '%s'.", char(key));
    end
end
end

function [llr, layout] = localUnwrapSoftBuffer(value)
layout = [];
llr = value;
if isstruct(value)
    layout = sixgr.util.structGet(value, "CodingLayout", []);
    llr = sixgr.util.structGet(value, "LLR", sixgr.util.structGet(value, "RateRecoveredLLR", []));
end
end

function [tf, currentSig, priorSig] = localCompatibleLayouts(currentLayout, priorLayout)
currentSig = char(string(sixgr.util.structGet(currentLayout, "CombineSignature", "")));
priorSig = char(string(sixgr.util.structGet(priorLayout, "CombineSignature", "")));
tf = strlength(string(currentSig)) > 0 && strcmp(currentSig, priorSig);
end

function tf = localLayoutMissing(layout)
tf = ~(isstruct(layout) && ~isempty(fieldnames(layout)));
end
