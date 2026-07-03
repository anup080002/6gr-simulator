function [thresholds_dB, info] = cqiRequiredSINRTable(cqiTable, cfg, direction, varargin)
%CQIREQUIREDSINRTABLE Resolve CQI operating SINR thresholds in dB.
%
% The returned 1x15 vector maps CQI index 1..15 to the SINR threshold used
% by the wideband CQI resolver. TS 38.214 defines CQI rows, not a normative
% SINR threshold table; these values therefore retain explicit source and
% value-role metadata.

if nargin < 1 || isempty(cqiTable)
    cqiTable = "table1";
end
if nargin < 2 || isempty(cfg)
    cfg = struct();
end
if nargin < 3 || isempty(direction)
    direction = "DL";
end

ip = inputParser;
ip.addParameter("TargetBLER", NaN, @(x) isnumeric(x) && isscalar(x));
ip.parse(varargin{:});

direction = upper(string(direction));
tableToken = lower(strtrim(string(cqiTable)));
thresholds_dB = [];
info = struct( ...
    "Source", "", ...
    "ValueRole", "", ...
    "Table", char(tableToken), ...
    "Direction", char(direction), ...
    "TargetBLER", double(ip.Results.TargetBLER));

tableField = tableToken + "Thresholds_dB";
if direction == "UL"
    candidatePaths = [ ...
        "phy.pusch." + tableField
        "phy.csi.ul." + tableField
        "phy.csi.ulCQIThresholds_dB"
        "phy.csi." + tableField
        "phy.csi.cqiThresholds_dB"];
else
    candidatePaths = [ ...
        "phy.pdsch." + tableField
        "phy.csi.dl." + tableField
        "phy.csi.dlCQIThresholds_dB"
        "phy.csi." + tableField
        "phy.csi.cqiThresholds_dB"];
end

for i = 1:numel(candidatePaths)
    raw = sixgr.util.structGet(cfg, candidatePaths(i), []);
    vals = localThresholdVector(raw);
    if ~isempty(vals)
        thresholds_dB = vals;
        info.Source = char(candidatePaths(i));
        info.ValueRole = "configured_lab_default_override";
        return;
    end
end

thresholds_dB = localDefaultCQIThresholds(tableToken);
if ~isempty(thresholds_dB)
    info.Source = "resolveWidebandCQI.lab_default_threshold_table";
    info.ValueRole = "lab_default";
end
end

function vals = localThresholdVector(raw)
vals = [];
if isempty(raw)
    return;
end
try
    vals = double(raw(:).');
catch
    vals = [];
    return;
end
vals = vals(isfinite(vals));
if numel(vals) ~= 15
    vals = [];
    return;
end
if any(diff(vals) < 0)
    vals = [];
end
end

function thresholds_dB = localDefaultCQIThresholds(tableToken)
switch lower(strtrim(string(tableToken)))
    case "table1"
        thresholds_dB = [ ...
            -5.90 -4.78 -2.87 -1.02 1.00 3.05 5.08 7.25 9.46 11.81 ...
            14.34 16.52 18.88 21.47 23.84];
    case "table2"
        thresholds_dB = [ ...
            -5.90 -3.10 -0.40 2.05 4.35 6.64 8.91 11.31 13.79 16.07 ...
            18.45 20.77 22.98 25.07 27.20];
    otherwise
        thresholds_dB = [];
end
end
