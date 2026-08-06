function [statistic, scopeNote] = beamMetricStatisticIdentity(baseStatistic, direction, snrDb)
%BEAMMETRICSTATISTICIDENTITY Encode aggregation scope in metric-row identity.
%
% The legacy metric table has no separate Direction/SNR columns.  Scope is
% therefore encoded in Statistic so DL/UL or per-SNR aggregates cannot
% collide under the table's natural MetricKey/Entity/Statistic key.

statistic = string(baseStatistic);
scope = strings(0, 1);
direction = upper(strtrim(string(direction)));
if ~ismissing(direction) && strlength(direction) > 0 && direction ~= "NAN"
    statistic = statistic + "_direction_" + lower(direction);
    scope(end+1, 1) = "Direction=" + direction; %#ok<AGROW>
end
snrDb = double(snrDb);
if isscalar(snrDb) && isfinite(snrDb)
    token = lower(string(compose("%.12g", snrDb)));
    token = replace(token, "-", "m");
    token = replace(token, "+", "p");
    token = replace(token, ".", "p");
    statistic = statistic + "_snr_" + token + "_db";
    scope(end+1, 1) = "SNR_dB=" + string(compose("%.12g", snrDb)); %#ok<AGROW>
end
scopeNote = strjoin(scope, "; ");
end
