function cqi = mapSINRToCQI(sinr_dB, cqiTable)
%MAPSINRTOCQI Legacy SINR-to-CQI helper using non-uniform NR table thresholds.
%
% 3GPP defines CQI rows, not a universal SINR threshold curve. This helper
% mirrors the calibrated lab-default thresholds used by resolveWidebandCQI
% so older report code does not retain the previous uniform 2 dB ladder.

if nargin < 2 || isempty(cqiTable)
    cqiTable = "table1";
end
thresholds_dB = localDefaultCQIThresholds(cqiTable);
cqi = zeros(size(sinr_dB));
for i = 1:numel(cqi)
    value = double(sinr_dB(i));
    if ~(isfinite(value))
        cqi(i) = 0;
        continue;
    end
    idx = find(value >= thresholds_dB, 1, "last");
    if isempty(idx)
        cqi(i) = 0;
    else
        cqi(i) = max(0, min(15, idx));
    end
end
end

function thresholds_dB = localDefaultCQIThresholds(cqiTable)
switch lower(strtrim(string(cqiTable)))
    case {"", "1", "table1", "table_1", "cqi_table1", "cqi_table_1"}
        thresholds_dB = [ ...
            -5.90 -4.78 -2.87 -1.02 1.00 3.05 5.08 7.25 9.46 11.81 ...
            14.34 16.52 18.88 21.47 23.84];
    case {"2", "table2", "table_2", "cqi_table2", "cqi_table_2"}
        thresholds_dB = [ ...
            -5.90 -3.10 -0.40 2.05 4.35 6.64 8.91 11.31 13.79 16.07 ...
            18.45 20.77 22.98 25.07 27.20];
    otherwise
        thresholds_dB = [ ...
            -5.90 -4.78 -2.87 -1.02 1.00 3.05 5.08 7.25 9.46 11.81 ...
            14.34 16.52 18.88 21.47 23.84];
end
end
