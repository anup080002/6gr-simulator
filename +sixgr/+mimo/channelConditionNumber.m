function [cond_dB, status, rankEstimate, singularValues] = channelConditionNumber(H, varargin)
%CHANNELCONDITIONNUMBER Rank-safe channel condition-number diagnostic.
%
% The condition number is only meaningful for an effective matrix with at
% least two supported singular modes. Rank-1 vectors and rank-deficient
% matrices return NaN instead of zero, Inf, or an arbitrary clipped value.

ip = inputParser;
ip.addParameter("RankTolerance", 1e-8, @(x) isnumeric(x) && isscalar(x));
ip.addParameter("MaxConditionNumber_dB", 60, @(x) isnumeric(x) && isscalar(x));
ip.parse(varargin{:});
rankTol = max(double(ip.Results.RankTolerance), eps);
maxCondDb = double(ip.Results.MaxConditionNumber_dB);

cond_dB = NaN;
status = "unavailable";
rankEstimate = NaN;
singularValues = [];

if isempty(H)
    status = "empty_channel";
    return;
end

try
    H = double(H);
catch
    status = "non_numeric_channel";
    return;
end

if isvector(H)
    H = reshape(H, numel(H), 1);
end
if ~ismatrix(H) || isempty(H) || ~all(isfinite(real(H(:)))) || ~all(isfinite(imag(H(:))))
    status = "invalid_channel_matrix";
    return;
end

matrixRankLimit = min(size(H, 1), size(H, 2));
if matrixRankLimit < 2
    singularValues = svd(H);
    singularValues = singularValues(isfinite(singularValues) & singularValues >= 0);
    if ~isempty(singularValues)
        rankEstimate = double(sum(singularValues >= max(singularValues(1) * rankTol, eps)));
    end
    status = "not_applicable_rank1";
    return;
end

try
    singularValues = svd(H);
catch
    status = "svd_failed";
    return;
end
singularValues = singularValues(isfinite(singularValues) & singularValues >= 0);
if isempty(singularValues)
    status = "no_finite_singular_values";
    return;
end

smax = max(singularValues);
threshold = max(smax * rankTol, eps);
rankEstimate = double(sum(singularValues >= threshold));
if rankEstimate < 2
    status = "not_applicable_rank_deficient";
    return;
end

active = singularValues(singularValues >= threshold);
cond_dB = 20 * log10(max(active(1), eps) / max(active(end), eps));
if ~(isfinite(cond_dB) && cond_dB >= 0)
    cond_dB = NaN;
    status = "invalid_condition_number";
    return;
end
if isfinite(maxCondDb) && cond_dB > maxCondDb
    cond_dB = NaN;
    status = "overflow_clipped";
    return;
end

status = "valid";
end
