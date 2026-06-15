function T = buildMetricUnitCatalogue(runFolder)
%BUILDMETRICUNITCATALOGUE Build a CSV-column unit catalogue for a run folder.
%
% The catalogue scans exported CSV files and maps known suffixes/tokens to
% units. Unknown columns are left as "unknown" rather than guessed.

if nargin < 1 || isempty(runFolder)
    runFolder = pwd;
end
runFolder = char(string(runFolder));
files = dir(fullfile(runFolder, "**", "*.csv"));

rows = struct("csv_path", {}, "column_name", {}, "unit", {}, "description", {});
for i = 1:numel(files)
    fp = fullfile(files(i).folder, files(i).name);
    try
        opts = detectImportOptions(fp, "NumHeaderLines", 0);
        vars = string(opts.VariableNames);
    catch
        continue;
    end
    rel = string(erase(fp, runFolder));
    rel = regexprep(rel, '^[\\/]+', '');
    for v = 1:numel(vars)
        [unit, desc] = localUnitForColumn(vars(v));
        rows(end+1) = struct("csv_path", char(rel), "column_name", char(vars(v)), ...
            "unit", char(unit), "description", char(desc)); %#ok<AGROW>
    end
end

if isempty(rows)
    T = table(strings(0,1), strings(0,1), strings(0,1), strings(0,1), ...
        'VariableNames', {'csv_path','column_name','unit','description'});
else
    T = struct2table(rows);
end
end

function [unit, desc] = localUnitForColumn(name)
n = lower(string(name));
unit = "unknown";
desc = "Unit not classified by catalogue.";
if endsWith(n, ["_db","db"]) || contains(n, "sinr") || contains(n, "rsrp") || contains(n, "rsrq")
    unit = "dB";
    desc = "Log-domain radio metric.";
elseif endsWith(n, ["_dbm","dbm"])
    unit = "dBm";
    desc = "Absolute power in dBm.";
elseif endsWith(n, ["_mbps","mbps"])
    unit = "Mbps";
    desc = "Megabits per second.";
elseif endsWith(n, ["_hz","hz"])
    unit = "Hz";
    desc = "Frequency in hertz.";
elseif endsWith(n, ["_ms","ms"])
    unit = "ms";
    desc = "Time duration in milliseconds.";
elseif endsWith(n, ["_us","us"])
    unit = "us";
    desc = "Time duration in microseconds.";
elseif contains(n, "sample")
    unit = "samples";
    desc = "Discrete sample count or offset.";
elseif contains(n, "bler") || contains(n, "ber") || contains(n, "probability") || contains(n, "rate")
    unit = "ratio";
    desc = "Unitless ratio/probability.";
elseif contains(n, "bits")
    unit = "bits";
    desc = "Bit count.";
elseif contains(n, "bytes")
    unit = "bytes";
    desc = "Byte count.";
elseif contains(n, "index") || contains(n, "mcs") || contains(n, "cqi") || contains(n, "pmi") || contains(n, "ri")
    unit = "index";
    desc = "Protocol/table index.";
elseif contains(n, "count") || startsWith(n, "n_") || startsWith(n, "num")
    unit = "count";
    desc = "Count.";
elseif endsWith(n, ["_m","meter","meters"])
    unit = "m";
    desc = "Distance in meters.";
end
end
