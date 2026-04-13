function profile = resolveCQIProfile(cqiTable, cqiIndex)
%RESOLVECQIPROFILE Resolve an NR CQI table row into modulation and code rate.
%
%   PROFILE = sixgr.link.resolveCQIProfile(CQITABLE, CQIINDEX) returns a
%   struct with fields:
%     Valid
%     Table
%     CQI
%     Qm
%     Modulation
%     TargetCodeRate
%     SpectralEfficiency
%
% Supported tables follow TS 38.214 Section 5.2.2.1:
%   table1
%   table2

tableToken = localNormalizeCQITable(cqiTable);
idx = round(double(cqiIndex));

profile = struct( ...
    "Valid", false, ...
    "Table", char(tableToken), ...
    "CQI", double(idx), ...
    "Qm", NaN, ...
    "Modulation", "", ...
    "TargetCodeRate", NaN, ...
    "SpectralEfficiency", NaN);

if ~(isscalar(idx) && isfinite(idx) && idx >= 0)
    return;
end

if idx == 0
    profile.Valid = true;
    profile.Qm = 0;
    profile.Modulation = "";
    profile.TargetCodeRate = 0;
    profile.SpectralEfficiency = 0;
    return;
end

switch tableToken
    case "table1"
        Qm = [2 2 2 2 2 2 4 4 4 6 6 6 6 6 6];
        R1024 = [78 120 193 308 449 602 378 490 616 466 567 666 772 873 948];
        se = [0.1523 0.2344 0.3770 0.6016 0.8770 1.1758 ...
            1.4766 1.9141 2.4063 2.7305 3.3223 3.9023 4.5234 5.1152 5.5547];
    case "table2"
        Qm = [2 2 2 4 4 4 6 6 6 6 6 8 8 8 8];
        R1024 = [78 193 449 378 490 616 466 567 666 772 873 711 797 885 948];
        se = [0.1523 0.3770 0.8770 1.4766 1.9141 2.4063 ...
            2.7305 3.3223 3.9023 4.5234 5.1152 5.5547 6.2266 6.9141 7.4063];
    otherwise
        return;
end

if idx < 1 || idx > numel(Qm)
    return;
end

profile.Valid = true;
profile.Qm = double(Qm(idx));
profile.Modulation = char(localQmToModulation(profile.Qm));
profile.TargetCodeRate = double(R1024(idx)) / 1024;
profile.SpectralEfficiency = double(se(idx));
end

function tableToken = localNormalizeCQITable(cqiTable)
token = lower(strtrim(char(string(cqiTable))));
switch token
    case {"", "1", "table1", "table_1", "cqi_table1", "cqi_table_1", "nr_table1", "nr_cqi_table1"}
        tableToken = "table1";
    case {"2", "table2", "table_2", "cqi_table2", "cqi_table_2", "nr_table2", "nr_cqi_table2"}
        tableToken = "table2";
    otherwise
        tableToken = string(token);
end
end

function modText = localQmToModulation(qm)
switch round(double(qm))
    case 2
        modText = "QPSK";
    case 4
        modText = "16QAM";
    case 6
        modText = "64QAM";
    case 8
        modText = "256QAM";
    otherwise
        modText = "";
end
end
