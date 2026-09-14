function tf = isAcceptableSINRStatus(statusStr)
%ISACCEPTABLESINRSTATUS Single source of truth for usable measured SINR.
%   OK and OK_<estimator variant> are candidate measured-SINR statuses.
%   Explicit unavailable/rejected/bound/approximation labels remain excluded
%   even when prefixed with OK. This status filter does not replace checks
%   of receiver evidence, source provenance or approximation flags.

s = strtrim(string(statusStr));
tf = false(size(s));
valid = ~ismissing(s) & strlength(s) > 0;
tokens=upper(s(valid));
accepted=tokens=="OK" | startsWith(tokens,"OK_");
% Preserve real variants such as dynamic_range_limited and
% decision_residual_bounded; do not equate them with a noise-floor bound.
excluded='(^|[^A-Z0-9])(PROXY|LUT|LOGISTIC|SYNTHETIC|FALLBACK|QUARANTINED|REJECTED|UNAVAILABLE|NOT_AVAILABLE|LOWER_BOUND_NOISE_FLOOR)([^A-Z0-9]|$)';
rejected=~cellfun('isempty',regexp(cellstr(tokens),excluded,'once'));
tf(valid)=accepted & ~reshape(rejected,size(accepted));
end
