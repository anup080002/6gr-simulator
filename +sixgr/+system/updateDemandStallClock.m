function [demandStart_s, stalledElapsed_s] = updateDemandStallClock(demandStart_s, now_s, hasDemand, madeProgress)
%UPDATEDEMANDSTALLCLOCK Time only a continuous, unserved demand interval.
% Access, idle slots and initialization are not failures to serve demand.
% A productive grant/service event ends the interval. NaN means unarmed.
validateattributes(now_s, {'numeric'}, {'scalar','real','finite','nonnegative'});
assert(isscalar(demandStart_s) && isnumeric(demandStart_s) && ...
    (isnan(demandStart_s) || (isfinite(demandStart_s) && ...
    demandStart_s >= 0 && demandStart_s <= now_s)), ...
    'sixgr:system:InvalidDemandStallClock', 'Demand clock must be monotonic.');
validateattributes(hasDemand, {'logical'}, {'scalar'});
validateattributes(madeProgress, {'logical'}, {'scalar'});
if ~hasDemand || madeProgress
    demandStart_s = NaN;
elseif isnan(demandStart_s)
    demandStart_s = now_s;
end
stalledElapsed_s = 0;
if isfinite(demandStart_s)
    stalledElapsed_s = now_s - demandStart_s;
end
end
