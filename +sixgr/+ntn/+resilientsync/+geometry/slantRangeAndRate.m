function result = slantRangeAndRate(satellitePositionM, satelliteVelocityMps, uePositionM, ueVelocityMps)
%SLANTRANGEANDRATE Compute exact range, LOS, delay geometry and range rate.

delta = satellitePositionM - uePositionM;
rangeM = sqrt(sum(delta.^2, 2));
if any(~isfinite(rangeM) | rangeM <= 0)
    error("sixgr:ntn:resilientsync:InvalidSlantRange", ...
        "Satellite and UE geometry produced a nonpositive or nonfinite range.");
end
q = delta ./ rangeM;
relativeVelocity = satelliteVelocityMps - ueVelocityMps;
rangeRate = sum(q .* relativeVelocity, 2);
result = struct("Range_m", rangeM, "RangeRate_m_s", rangeRate, ...
    "LOSUnitVector", q);
end
