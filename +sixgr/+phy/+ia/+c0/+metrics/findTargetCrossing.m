function result = findTargetCrossing(points,metric,target)
%FINDTARGETCROSSING Interpolate only between measured bracketing points.
snr = double(points.SNRDB);
value = double(points.(char(metric)));
valid = isfinite(snr)&isfinite(value);
snr = snr(valid); value = value(valid);
[snr,order] = sort(snr); value = value(order);
result = struct("Metric",string(metric),"Target",double(target), ...
    "Bracketed",false,"LowerSNRDB",NaN,"UpperSNRDB",NaN, ...
    "LowerValue",NaN,"UpperValue",NaN,"CrossingSNRDB",NaN, ...
    "Interpolation","not_available", ...
    "Status","BLOCKED_UNBRACKETED");
for k = 1:numel(snr)-1
    a = value(k)-target;
    b = value(k+1)-target;
    if a == 0
        result.Bracketed = true;
        result.LowerSNRDB = snr(k); result.UpperSNRDB = snr(k);
        result.LowerValue = value(k); result.UpperValue = value(k);
        result.CrossingSNRDB = snr(k); result.Status = "SIMULATED";
        return;
    end
    if a*b <= 0
        result.Bracketed = true;
        result.LowerSNRDB = snr(k); result.UpperSNRDB = snr(k+1);
        result.LowerValue = value(k); result.UpperValue = value(k+1);
        if value(k)>0 && value(k+1)>0
            x = [log10(value(k)) log10(value(k+1))];
            result.CrossingSNRDB = interp1( ...
                x,[snr(k) snr(k+1)],log10(target),"linear");
            result.Interpolation = "linear_in_log10_probability";
        else
            % A measured zero-error point is a legitimate lower endpoint,
            % but log10(0) is undefined. Use the two raw Monte Carlo
            % estimates directly and disclose the interpolation domain.
            result.CrossingSNRDB = interp1( ...
                [value(k) value(k+1)],[snr(k) snr(k+1)], ...
                target,"linear");
            result.Interpolation = "linear_in_probability_zero_endpoint";
        end
        result.Status = "SIMULATED";
        return;
    end
end
end
