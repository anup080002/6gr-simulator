function [status, crossingSNR_dB, info] = qualifyObservedBLERCrossing( ...
        snr_dB, bler, targetBLER, maxBracketWidth_dB)
%QUALIFYOBSERVEDBLERCROSSING Classify a measured BLER target crossing.
%   Linear interpolation is permitted only inside an explicitly resolved
%   SNR bracket.  A wide bracket is retained as measured endpoint evidence
%   but is not converted into a fabricated point estimate.

arguments
    snr_dB (:,1) double
    bler (:,1) double
    targetBLER (1,1) double {mustBeFinite,mustBeGreaterThan(targetBLER,0),mustBeLessThan(targetBLER,1)}
    maxBracketWidth_dB (1,1) double {mustBeFinite,mustBePositive} = 2
end

status = "insufficient_finite_points";
crossingSNR_dB = NaN;
info = struct( ...
    "BracketLowSNR_dB", NaN, ...
    "BracketHighSNR_dB", NaN, ...
    "BracketWidth_dB", NaN, ...
    "MaxBracketWidth_dB", double(maxBracketWidth_dB), ...
    "InterpolationApplied", false);

mask = isfinite(snr_dB) & isfinite(bler);
if nnz(mask) < 2
    return;
end
x = double(snr_dB(mask));
y = double(bler(mask));
[x, order] = sort(x(:));
y = y(order);

exactTolerance = max(eps(double(targetBLER)) * 8, 1e-15);
exactIndex = find(abs(y - double(targetBLER)) <= exactTolerance, 1, "first");
if ~isempty(exactIndex)
    status = "crossing_observed_exact_point";
    crossingSNR_dB = x(exactIndex);
    info.BracketLowSNR_dB = x(exactIndex);
    info.BracketHighSNR_dB = x(exactIndex);
    info.BracketWidth_dB = 0;
    return;
end

for i = 1:numel(x) - 1
    y1 = y(i);
    y2 = y(i + 1);
    if (y1 > targetBLER && y2 < targetBLER) || ...
            (y1 < targetBLER && y2 > targetBLER)
        width_dB = x(i + 1) - x(i);
        info.BracketLowSNR_dB = x(i);
        info.BracketHighSNR_dB = x(i + 1);
        info.BracketWidth_dB = width_dB;
        if width_dB > maxBracketWidth_dB
            status = "crossing_underresolved_bracket";
            return;
        end
        crossingSNR_dB = x(i) + (targetBLER - y1) * width_dB / (y2 - y1);
        status = "crossing_observed_interpolated";
        info.InterpolationApplied = true;
        return;
    end
end

if all(y > targetBLER)
    status = "no_crossing_all_points_above_target";
elseif all(y < targetBLER)
    status = "no_crossing_all_points_below_target";
else
    status = "no_crossing_nonmonotonic_points";
end
end
