classdef TransmissionBandwidthCatalog
%TRANSMISSIONBANDWIDTHCATALOG TS 38.104 Release-18 gNB NRB catalog.
%
% The standard resolver is fail-closed: an N/A bandwidth/SCS cell throws,
% and a configured NSizeGrid is treated only as a consistency assertion.
% Arbitrary research grids are handled separately by CarrierGridConfig.custom.

    methods (Static)
        function result = resolve(varargin)
            opts = localParseInputs(varargin{:});
            role = localRole(opts.Role);
            bandwidthMHz = localPositiveScalar( ...
                opts.ChannelBandwidthMHz, "ChannelBandwidthMHz");
            scsKHz = localPositiveScalar( ...
                opts.SubcarrierSpacingKHz, "SubcarrierSpacingKHz");

            rangeArgs = {};
            if ~isempty(opts.CenterFrequencyHz)
                rangeArgs = [rangeArgs, {"CenterFrequencyHz", opts.CenterFrequencyHz}]; %#ok<AGROW>
            end
            if strlength(string(opts.FrequencyRange)) > 0
                rangeArgs = [rangeArgs, {"FrequencyRange", opts.FrequencyRange}]; %#ok<AGROW>
            end
            rangeInfo = sixgr.phy.frame.FrequencyRangeResolver.resolve(rangeArgs{:});
            frequencyRange = string(rangeInfo.FrequencyRange);

            rows = localCatalogRows();
            rowIndex = find(rows.ChannelBandwidthMHz == bandwidthMHz & ...
                rows.SubcarrierSpacingKHz == scsKHz & ...
                rows.FrequencyRange == frequencyRange, 1);
            if isempty(rowIndex) || ~rows.Valid(rowIndex)
                error("sixgr:phy:frame:UnsupportedBandwidthSCSCombination", ...
                    "No TS 38.104 Release-18 gNB transmission-bandwidth " + ...
                    "configuration exists for %s, %.15g MHz, %.15g kHz SCS.", ...
                    char(frequencyRange), bandwidthMHz, scsKHz);
            end

            nrb = double(rows.NRB(rowIndex));
            if ~isempty(opts.ConfiguredNSizeGrid)
                configuredGrid = localPositiveInteger( ...
                    opts.ConfiguredNSizeGrid, "ConfiguredNSizeGrid");
                if configuredGrid ~= nrb
                    error("sixgr:phy:frame:ConfiguredGridMismatch", ...
                        "Configured NSizeGrid=%d does not equal the TS 38.104 " + ...
                        "table value N_RB=%d for %s / %.15g MHz / %.15g kHz.", ...
                        configuredGrid, nrb, char(frequencyRange), bandwidthMHz, scsKHz);
                end
            end

            nStartGrid = localNonnegativeInteger(opts.NStartGrid, "NStartGrid");
            occupiedSubcarriers = 12 * nrb;
            occupiedBandwidthHz = occupiedSubcarriers * scsKHz * 1e3;
            guardbandKHz = (bandwidthMHz * 1e3 - ...
                occupiedSubcarriers * scsKHz) / 2 - scsKHz / 2;
            if ~(isfinite(guardbandKHz) && guardbandKHz >= 0)
                error("sixgr:phy:frame:InvalidGuardbandResolution", ...
                    "Resolved guardband is invalid for catalog row %s.", ...
                    char(rows.RowKey(rowIndex)));
            end

            result = struct( ...
                "Valid", true, ...
                "StandardNR", true, ...
                "Role", char(role), ...
                "FrequencyRange", char(frequencyRange), ...
                "FrequencyRangeSubtype", char(frequencyRange), ...
                "CenterFrequencyHz", double(rangeInfo.CenterFrequencyHz), ...
                "ChannelBandwidthMHz", double(bandwidthMHz), ...
                "ChannelBandwidthHz", double(bandwidthMHz * 1e6), ...
                "SubcarrierSpacingKHz", double(scsKHz), ...
                "N_RB", double(nrb), ...
                "NSizeGrid", double(nrb), ...
                "NStartGrid", double(nStartGrid), ...
                "OccupiedSubcarrierCount", double(occupiedSubcarriers), ...
                "OccupiedBandwidthHz", double(occupiedBandwidthHz), ...
                "MinimumGuardbandKHz", double(guardbandKHz), ...
                "MinimumLowGuardbandKHz", double(guardbandKHz), ...
                "MinimumHighGuardbandKHz", double(guardbandKHz), ...
                "MinimumLowGuardbandHz", double(guardbandKHz * 1e3), ...
                "MinimumHighGuardbandHz", double(guardbandKHz * 1e3), ...
                "SourceTable", char(rows.SourceTable(rowIndex)), ...
                "GuardbandSourceTable", char(rows.GuardbandSourceTable(rowIndex)), ...
                "RowKey", char(rows.RowKey(rowIndex)), ...
                "Source", "3GPP_TS_38_104_V18_8_0");
        end

        function rows = table()
        %TABLE Return every valid cell in the pinned TS 38.104 catalog.
            rows = localCatalogRows();
            occupied = 12 .* rows.NRB .* rows.SubcarrierSpacingKHz .* 1e3;
            guardKHz = (rows.ChannelBandwidthMHz .* 1e3 - ...
                12 .* rows.NRB .* rows.SubcarrierSpacingKHz) ./ 2 - ...
                rows.SubcarrierSpacingKHz ./ 2;
            rows.OccupiedBandwidthHz = occupied;
            rows.MinimumGuardbandKHz = guardKHz;
        end
    end
end

function opts = localParseInputs(varargin)
opts = struct( ...
    "Role", "gNB", ...
    "FrequencyRange", "", ...
    "CenterFrequencyHz", [], ...
    "ChannelBandwidthMHz", [], ...
    "SubcarrierSpacingKHz", [], ...
    "ConfiguredNSizeGrid", [], ...
    "NStartGrid", 0);
if mod(numel(varargin), 2) ~= 0
    error("sixgr:phy:frame:InvalidCarrierGridArguments", ...
        "TransmissionBandwidthCatalog arguments must occur in name-value pairs.");
end
for i = 1:2:numel(varargin)
    name = lower(strtrim(string(varargin{i})));
    value = varargin{i + 1};
    switch name
        case "role"
            opts.Role = value;
        case "frequencyrange"
            opts.FrequencyRange = value;
        case {"centerfrequencyhz", "representativecenterfrequencyhz"}
            opts.CenterFrequencyHz = value;
        case "channelbandwidthmhz"
            opts.ChannelBandwidthMHz = value;
        case "channelbandwidthhz"
            opts.ChannelBandwidthMHz = double(value) / 1e6;
        case {"subcarrierspacingkhz", "carrierscskhz", "scskhz"}
            opts.SubcarrierSpacingKHz = value;
        case {"configurednsizegrid", "nsizegrid"}
            opts.ConfiguredNSizeGrid = value;
        case "nstartgrid"
            opts.NStartGrid = value;
        otherwise
            error("sixgr:phy:frame:InvalidCarrierGridArguments", ...
                "Unknown TransmissionBandwidthCatalog option '%s'.", char(name));
    end
end
end

function role = localRole(value)
if ~(ischar(value) || (isstring(value) && isscalar(value)))
    error("sixgr:phy:frame:UnsupportedCarrierRole", ...
        "Carrier role must be scalar text.");
end
role = lower(strtrim(string(value)));
if any(role == ["gnb", "gnb_carrier", "gnb_carrier_transmission_bandwidth"])
    role = "gNB_carrier_transmission_bandwidth";
else
    error("sixgr:phy:frame:UnsupportedCarrierRole", ...
        "TransmissionBandwidthCatalog currently resolves the TS 38.104 " + ...
        "gNB carrier role only; got '%s'.", char(role));
end
end

function value = localPositiveScalar(raw, fieldName)
if ~(isnumeric(raw) || islogical(raw)) || ~isscalar(raw) || ...
        ~isfinite(double(raw)) || double(raw) <= 0
    error("sixgr:phy:frame:InvalidCarrierGridValue", ...
        "%s must be a positive finite numeric scalar.", fieldName);
end
value = double(raw);
end

function value = localPositiveInteger(raw, fieldName)
value = localPositiveScalar(raw, fieldName);
if value ~= round(value)
    error("sixgr:phy:frame:InvalidCarrierGridValue", ...
        "%s must be a positive integer.", fieldName);
end
value = round(value);
end

function value = localNonnegativeInteger(raw, fieldName)
if isempty(raw)
    raw = 0;
end
if ~(isnumeric(raw) || islogical(raw)) || ~isscalar(raw) || ...
        ~isfinite(double(raw)) || double(raw) < 0 || double(raw) ~= round(double(raw))
    error("sixgr:phy:frame:InvalidCarrierGridValue", ...
        "%s must be a nonnegative integer.", fieldName);
end
value = round(double(raw));
end

function rows = localCatalogRows()
% Columns: range code, bandwidth MHz, SCS kHz, N_RB.
% Range codes: 1=FR1, 21=FR2-1, 22=FR2-2.
validValues = [ ...
    1 3 15 15; 1 5 15 25; 1 10 15 52; 1 15 15 79; ...
    1 20 15 106; 1 25 15 133; 1 30 15 160; 1 35 15 188; ...
    1 40 15 216; 1 45 15 242; 1 50 15 270; ...
    1 5 30 11; 1 10 30 24; 1 15 30 38; 1 20 30 51; ...
    1 25 30 65; 1 30 30 78; 1 35 30 92; 1 40 30 106; ...
    1 45 30 119; 1 50 30 133; 1 60 30 162; 1 70 30 189; ...
    1 80 30 217; 1 90 30 245; 1 100 30 273; ...
    1 10 60 11; 1 15 60 18; 1 20 60 24; 1 25 60 31; ...
    1 30 60 38; 1 35 60 44; 1 40 60 51; 1 45 60 58; ...
    1 50 60 65; 1 60 60 79; 1 70 60 93; 1 80 60 107; ...
    1 90 60 121; 1 100 60 135; ...
    21 50 60 66; 21 100 60 132; 21 200 60 264; ...
    21 50 120 32; 21 100 120 66; 21 200 120 132; 21 400 120 264; ...
    22 100 120 66; 22 400 120 264; ...
    22 400 480 66; 22 800 480 124; 22 1600 480 248; ...
    22 400 960 33; 22 800 960 62; 22 1600 960 124; 22 2000 960 148];

fr1BW = [3 5 10 15 20 25 30 35 40 45 50 60 70 80 90 100];
fr21BW = [50 100 200 400];
fr22BW = [100 400 800 1600 2000];
cells = zeros(71, 3);
cursor = 0;
for scs = [15 30 60]
    for bw = fr1BW
        cursor = cursor + 1;
        cells(cursor, :) = [1 bw scs];
    end
end
for scs = [60 120]
    for bw = fr21BW
        cursor = cursor + 1;
        cells(cursor, :) = [21 bw scs];
    end
end
for scs = [120 480 960]
    for bw = fr22BW
        cursor = cursor + 1;
        cells(cursor, :) = [22 bw scs];
    end
end
if cursor ~= 71
    error("sixgr:phy:frame:InternalCarrierCatalogError", ...
        "The pinned TS 38.104 carrier table must contain exactly 71 cells.");
end

values = [cells nan(size(cells, 1), 1)];
valid = false(size(cells, 1), 1);
for i = 1:size(validValues, 1)
    index = find(all(cells == validValues(i, 1:3), 2), 1);
    if isempty(index)
        error("sixgr:phy:frame:InternalCarrierCatalogError", ...
            "Valid carrier row %s is absent from the complete table axes.", ...
            mat2str(validValues(i, :)));
    end
    values(index, 4) = validValues(i, 4);
    valid(index) = true;
end

range = strings(size(values, 1), 1);
range(values(:, 1) == 1) = "FR1";
range(values(:, 1) == 21) = "FR2-1";
range(values(:, 1) == 22) = "FR2-2";
source = strings(size(values, 1), 1);
source(range == "FR1") = "TS_38_104_V18_8_0_Table_5_3_2_1";
source(range == "FR2-1") = "TS_38_104_V18_8_0_Table_5_3_2_2";
source(range == "FR2-2") = "TS_38_104_V18_8_0_Table_5_3_2_3";
guardSource = strings(size(values, 1), 1);
guardSource(range == "FR1") = "TS_38_104_V18_8_0_Table_5_3_3_1";
guardSource(range == "FR2-1") = "TS_38_104_V18_8_0_Table_5_3_3_2";
guardSource(range == "FR2-2") = "TS_38_104_V18_8_0_Table_5_3_3_2a";
rowKey = range + "_" + string(values(:, 3)) + "kHz_" + ...
    string(values(:, 2)) + "MHz";

rows = table(range, values(:, 2), values(:, 3), valid, values(:, 4), source, ...
    guardSource, rowKey, ...
    'VariableNames', ["FrequencyRange", "ChannelBandwidthMHz", ...
    "SubcarrierSpacingKHz", "Valid", "NRB", "SourceTable", ...
    "GuardbandSourceTable", "RowKey"]);
end
