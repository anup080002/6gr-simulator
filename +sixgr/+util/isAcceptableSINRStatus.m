function tf = isAcceptableSINRStatus(statusStr)
%ISACCEPTABLESINRSTATUS Single source of truth for usable measured SINR.
%   Any non-missing status beginning with OK is a valid measured-SINR
%   observation regardless of estimator variant. Unavailable, rejected,
%   quarantined, proxy, fallback and empty statuses are excluded.

s = strtrim(string(statusStr));
tf = false(size(s));
valid = ~ismissing(s) & strlength(s) > 0;
tf(valid) = startsWith(upper(s(valid)), "OK");
end
