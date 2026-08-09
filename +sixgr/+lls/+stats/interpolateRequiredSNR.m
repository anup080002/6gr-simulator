function result = interpolateRequiredSNR(snrDb, bler, targetBLER)
%INTERPOLATEREQUIREDSNR Interpolate only inside a simulated BLER crossing.

snrDb = double(snrDb(:));
bler = double(bler(:));
targetBLER = double(targetBLER);
valid = isfinite(snrDb) & isfinite(bler) & bler > 0 & bler <= 1;
snrDb = snrDb(valid);
bler = bler(valid);
[snrDb, order] = sort(snrDb);
bler = bler(order);
result = struct("TargetBLER", targetBLER, "RequiredSNR_dB", NaN, ...
    "Valid", false, "Status", "no_bracketing_simulated_points");
for idx = 1:numel(snrDb)-1
    y1 = bler(idx); y2 = bler(idx+1);
    if (y1-targetBLER) * (y2-targetBLER) <= 0 && y1 ~= y2
        x = interp1(log10([y1 y2]), [snrDb(idx) snrDb(idx+1)], log10(targetBLER));
        result.RequiredSNR_dB = double(x);
        result.Valid = true;
        result.Status = "interpolated_between_simulated_transition_points";
        return;
    end
end
end
