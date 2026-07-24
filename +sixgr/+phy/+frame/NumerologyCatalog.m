classdef NumerologyCatalog
%NUMEROLOGYCATALOG Canonical Release-18 NR numerology and CP resolver.
%
% This catalog owns the generic TS 38.211 numerology timing values.  A
% generic numerology is resolved first and the role/frequency-range
% capability matrix is then applied.  No logarithmic rounding is used.

    methods (Static)
        function result = resolve(varargin)
            [scsKHz, cyclicPrefix, role, frequencyRange] = localInputs(varargin{:});

            supportedSCS = [15 30 60 120 240 480 960];
            if ~(isnumeric(scsKHz) || islogical(scsKHz)) || ...
                    ~isscalar(scsKHz) || ~isfinite(double(scsKHz)) || ...
                    double(scsKHz) <= 0
                error("sixgr:phy:frame:InvalidSubcarrierSpacing", ...
                    "Subcarrier spacing must be a positive finite numeric scalar in kHz.");
            end
            scsKHz = double(scsKHz);
            index = find(supportedSCS == scsKHz, 1);
            if isempty(index)
                error("sixgr:phy:frame:UnsupportedSubcarrierSpacing", ...
                    "Subcarrier spacing %.15g kHz is not present in the pinned " + ...
                    "TS 38.211 Release-18 numerology table. Supported values are %s kHz.", ...
                    scsKHz, mat2str(supportedSCS));
            end

            cyclicPrefix = localCyclicPrefix(cyclicPrefix);
            mu = index - 1;
            if cyclicPrefix == "extended" && mu ~= 2
                error("sixgr:phy:frame:UnsupportedCyclicPrefixNumerology", ...
                    "Extended cyclic prefix is supported only for mu=2 / 60 kHz.");
            end

            role = localRole(role);
            frequencyRange = localFrequencyRange(frequencyRange, role);
            localValidateRoleCapability(scsKHz, cyclicPrefix, role, frequencyRange);

            symbolsPerSlot = 14;
            if cyclicPrefix == "extended"
                symbolsPerSlot = 12;
            end
            slotsPerSubframe = 2 ^ mu;
            slotsPerFrame = 10 * slotsPerSubframe;
            slotDurationSeconds = 1e-3 / slotsPerSubframe;

            result = struct( ...
                "Mu", double(mu), ...
                "SubcarrierSpacingKHz", double(scsKHz), ...
                "CyclicPrefix", char(cyclicPrefix), ...
                "SymbolsPerSlot", double(symbolsPerSlot), ...
                "SlotsPerSubframe", double(slotsPerSubframe), ...
                "SlotsPerFrame", double(slotsPerFrame), ...
                "SlotDurationSeconds", double(slotDurationSeconds), ...
                "SlotDurationMilliseconds", double(1e3 * slotDurationSeconds), ...
                "Role", char(role), ...
                "FrequencyRange", char(frequencyRange), ...
                "IndexConvention", "zero_based_phy_indices", ...
                "Source", "3GPP_TS_38_211_V18_8_0_tables_4_2_1_and_4_3_2");
        end

        function tableOut = table(cyclicPrefix)
        %TABLE Return the canonical generic numerology catalog.
            if nargin < 1 || strlength(string(cyclicPrefix)) == 0
                cyclicPrefix = "normal";
            end
            cp = localCyclicPrefix(cyclicPrefix);
            if cp == "normal"
                scs = [15; 30; 60; 120; 240; 480; 960];
            else
                scs = 60;
            end
            rows = struct([]);
            for i = 1:numel(scs)
                row = sixgr.phy.frame.NumerologyCatalog.resolve( ...
                    scs(i), cp, "generic_waveform_test", "");
                if isempty(rows)
                    rows = repmat(row, numel(scs), 1);
                else
                    rows(i) = row;
                end
            end
            tableOut = struct2table(rows, 'AsArray', true);
        end
    end
end

function [scsKHz, cyclicPrefix, role, frequencyRange] = localInputs(varargin)
scsKHz = [];
cyclicPrefix = "normal";
role = "generic_waveform_test";
frequencyRange = "";

if isempty(varargin)
    return;
end

first = varargin{1};
isNameValue = (ischar(first) || (isstring(first) && isscalar(first))) && ...
    any(strcmpi(strtrim(string(first)), [ ...
        "SubcarrierSpacingKHz", "SCSKHz", "CyclicPrefix", "Role", ...
        "FrequencyRange"]));
if ~isNameValue
    scsKHz = first;
    if numel(varargin) >= 2 && ~isempty(varargin{2})
        cyclicPrefix = varargin{2};
    end
    if numel(varargin) >= 3 && ~isempty(varargin{3})
        role = varargin{3};
    end
    if numel(varargin) >= 4 && ~isempty(varargin{4})
        frequencyRange = varargin{4};
    end
    if numel(varargin) > 4
        error("sixgr:phy:frame:InvalidNumerologyArguments", ...
            "NumerologyCatalog.resolve accepts at most four positional arguments.");
    end
    return;
end

if mod(numel(varargin), 2) ~= 0
    error("sixgr:phy:frame:InvalidNumerologyArguments", ...
        "Numerology name-value arguments must occur in pairs.");
end
for i = 1:2:numel(varargin)
    name = lower(strtrim(string(varargin{i})));
    value = varargin{i + 1};
    switch name
        case {"subcarrierspacingkhz", "scskhz"}
            scsKHz = value;
        case "cyclicprefix"
            cyclicPrefix = value;
        case "role"
            role = value;
        case "frequencyrange"
            frequencyRange = value;
        otherwise
            error("sixgr:phy:frame:InvalidNumerologyArguments", ...
                "Unknown NumerologyCatalog option '%s'.", char(name));
    end
end
end

function cyclicPrefix = localCyclicPrefix(value)
if ~(ischar(value) || (isstring(value) && isscalar(value)))
    error("sixgr:phy:frame:InvalidCyclicPrefix", ...
        "CyclicPrefix must be the scalar text value 'normal' or 'extended'.");
end
cyclicPrefix = lower(strtrim(string(value)));
if ~any(cyclicPrefix == ["normal", "extended"])
    error("sixgr:phy:frame:InvalidCyclicPrefix", ...
        "Unsupported cyclic prefix '%s'; allowed values are normal and extended.", ...
        char(cyclicPrefix));
end
end

function role = localRole(value)
if ~(ischar(value) || (isstring(value) && isscalar(value)))
    error("sixgr:phy:frame:InvalidNumerologyRole", ...
        "Numerology role must be scalar text.");
end
role = lower(strtrim(string(value)));
switch role
    case {"generic", "generic_waveform", "generic_waveform_test", "waveform_test"}
        role = "generic_waveform_test";
    case {"carrier", "carrier_grid", "carrier_transmission_grid", ...
            "gnb_carrier_transmission_bandwidth"}
        role = "carrier_transmission_grid";
    case {"bwp", "dl_bwp", "ul_bwp"}
        % Preserve the direction-specific role.
    case {"ssb", "prach"}
        % Canonical as written.
    otherwise
        error("sixgr:phy:frame:InvalidNumerologyRole", ...
            "Unsupported numerology role '%s'.", char(role));
end
end

function frequencyRange = localFrequencyRange(value, role)
isMissing = isempty(value) || ...
    (ischar(value) && isempty(strtrim(value))) || ...
    (isstring(value) && isscalar(value) && strlength(strtrim(value)) == 0);
if isMissing
    if role == "generic_waveform_test"
        frequencyRange = "";
        return;
    end
    error("sixgr:phy:frame:MissingFrequencyRange", ...
        "FrequencyRange is required for numerology role '%s'.", char(role));
end
if ~(ischar(value) || (isstring(value) && isscalar(value)))
    error("sixgr:phy:frame:InvalidFrequencyRange", ...
        "FrequencyRange must be scalar text.");
end
frequencyRange = upper(strtrim(string(value)));
if ~any(frequencyRange == ["FR1", "FR2-1", "FR2-2"])
    error("sixgr:phy:frame:InvalidFrequencyRange", ...
        "Standard NR frequency range must be FR1, FR2-1, or FR2-2; got '%s'.", ...
        char(frequencyRange));
end
end

function localValidateRoleCapability(scsKHz, cyclicPrefix, role, frequencyRange)
if role == "generic_waveform_test"
    return;
end

switch frequencyRange
    case "FR1"
        carrierSCS = [15 30 60];
        ssbSCS = [15 30];
        prachSCS = [15 30 60];
    case "FR2-1"
        carrierSCS = [60 120];
        ssbSCS = [120 240];
        prachSCS = [60 120];
    case "FR2-2"
        carrierSCS = [120 480 960];
        ssbSCS = [120 480 960];
        prachSCS = [120 480 960];
    otherwise
        carrierSCS = [];
        ssbSCS = [];
        prachSCS = [];
end

if any(role == ["carrier_transmission_grid", "bwp", "dl_bwp", "ul_bwp"])
    allowed = carrierSCS;
elseif role == "ssb"
    allowed = ssbSCS;
else
    allowed = prachSCS;
end
if ~any(scsKHz == allowed)
    error("sixgr:phy:frame:UnsupportedNumerologyForRole", ...
        "%g kHz is not supported for role '%s' in %s; allowed values are %s kHz.", ...
        scsKHz, char(role), char(frequencyRange), mat2str(allowed));
end
if cyclicPrefix == "extended" && ~any(role == [ ...
        "carrier_transmission_grid", "bwp", "dl_bwp", "ul_bwp"])
    error("sixgr:phy:frame:UnsupportedCyclicPrefixForRole", ...
        "Extended cyclic prefix is not supported for role '%s'.", char(role));
end
end
