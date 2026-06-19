function [combinedLLR, info] = combineSoftLLR(currentLLR, priorLLR)
%COMBINESOFTLLR HARQ soft combining for rate-recovered LLRs.
%
% The inputs must already be in the same rate-recovered LDPC code-block
% domain. Combining is an LLR sum, equivalent to multiplying independent
% likelihoods before LDPC decoding.

combinedLLR = currentLLR;
info = struct( ...
    "Applied", false, ...
    "Reason", "", ...
    "CurrentNumel", double(numel(currentLLR)), ...
    "PriorNumel", double(numel(priorLLR)), ...
    "CombinedNumel", double(numel(currentLLR)));

if isempty(priorLLR)
    info.Reason = "no_prior_harq_soft_buffer";
    return;
end
if isempty(currentLLR)
    info.Reason = "current_llr_empty";
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
info.Reason = "llr_sum_same_rate_recovered_ldpc_domain";
info.CombinedNumel = double(numel(combinedLLR));
end
