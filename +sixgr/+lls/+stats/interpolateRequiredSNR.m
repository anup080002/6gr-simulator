function result = interpolateRequiredSNR(snrDb, bler, targetBLER, varargin)
%INTERPOLATEREQUIREDSNR Interpolate only inside a simulated BLER crossing.

ip = inputParser;
ip.addParameter("LowerCI",[],@(x) isempty(x) || isnumeric(x));
ip.addParameter("UpperCI",[],@(x) isempty(x) || isnumeric(x));
ip.addParameter("ConfidenceLevel",NaN,@(x) isnumeric(x) && isscalar(x));
ip.parse(varargin{:});

snrDb = double(snrDb(:));
bler = double(bler(:));
targetBLER = double(targetBLER);
lowerCI = double(ip.Results.LowerCI(:));
upperCI = double(ip.Results.UpperCI(:));
haveCI = numel(lowerCI) == numel(snrDb) && numel(upperCI) == numel(snrDb);
valid = isfinite(snrDb) & isfinite(bler) & bler >= 0 & bler <= 1;
snrDb = snrDb(valid);
bler = bler(valid);
if haveCI
    lowerCI = lowerCI(valid);
    upperCI = upperCI(valid);
else
    lowerCI = nan(size(bler));
    upperCI = nan(size(bler));
end
[snrDb, order] = sort(snrDb);
bler = bler(order);
lowerCI = lowerCI(order);
upperCI = upperCI(order);
result = struct("TargetBLER", targetBLER, "RequiredSNR_dB", NaN, ...
    "LowerBracketSNR_dB",NaN,"UpperBracketSNR_dB",NaN, ...
    "ConfidenceLevel",double(ip.Results.ConfidenceLevel), ...
    "EstimationBasis","none","Valid", false, ...
    "Status", "no_bracketing_simulated_points");
for idx = 1:numel(snrDb)-1
    y1 = bler(idx); y2 = bler(idx+1);
    if y1 > 0 && y2 > 0 && ...
            (y1-targetBLER) * (y2-targetBLER) <= 0 && y1 ~= y2
        x = interp1(log10([y1 y2]), [snrDb(idx) snrDb(idx+1)], log10(targetBLER));
        result.RequiredSNR_dB = double(x);
        result.LowerBracketSNR_dB = snrDb(idx);
        result.UpperBracketSNR_dB = snrDb(idx+1);
        result.EstimationBasis = "empirical_bler_log_interpolation";
        result.Valid = true;
        result.Status = "interpolated_between_simulated_transition_points";
        return;
    end
end

% A zero-error point is censored, not a BLER value of exactly zero. If its
% Wilson upper confidence bound lies below the target while the preceding
% point's lower confidence bound lies above the target, the target crossing
% is proven to lie inside the simulated SNR bracket at the stated confidence.
% Use the upper bound in log interpolation to report a conservative scalar
% estimate while retaining the exact bracket in separate columns.
for idx = 1:numel(snrDb)-1
    if bler(idx) > 0 && bler(idx+1) == 0 && ...
            isfinite(lowerCI(idx)) && isfinite(upperCI(idx+1)) && ...
            lowerCI(idx) > targetBLER && upperCI(idx+1) > 0 && ...
            upperCI(idx+1) < targetBLER
        x = interp1(log10([bler(idx) upperCI(idx+1)]), ...
            [snrDb(idx) snrDb(idx+1)],log10(targetBLER));
        result.RequiredSNR_dB = double(x);
        result.LowerBracketSNR_dB = snrDb(idx);
        result.UpperBracketSNR_dB = snrDb(idx+1);
        result.EstimationBasis = ...
            "zero_error_wilson_upper_bound_conservative_log_interpolation";
        result.Valid = true;
        result.Status = ...
            "confidence_bracketed_using_zero_error_wilson_upper_bound";
        return;
    end
end
end
