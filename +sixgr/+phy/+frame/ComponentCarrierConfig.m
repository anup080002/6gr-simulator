classdef ComponentCarrierConfig < handle
    %COMPONENTCARRIERCONFIG Explicit per-CC grid, BWP, and state namespaces.

    properties (SetAccess = private)
        CCID (1,1) string
        ServingCellID (1,1) string
        SchedulingCCIDs (:,1) string
        CenterFrequencyHz (1,1) double
        DLCenterFrequencyHz (1,1) double
        ULCenterFrequencyHz (1,1) double
        Band (1,1) string
        FrequencyRange (1,1) string
        ResearchMode (1,1) logical = false
        ChannelBandwidthMHz (1,1) double
        DuplexMode (1,1) string
        DLCarrierGrid (1,1) struct
        ULCarrierGrid (1,1) struct
        BWPState (1,1) sixgr.phy.frame.BWPStateMachine
        CarrierIndicatorMap (:,1) struct
        ResourceNamespace (1,1) string
        WaveformNamespace (1,1) string
        MeasurementNamespace (1,1) string
    end

    properties (Access = private)
        HARQState containers.Map
        MeasurementState containers.Map
        AvailabilityResolver = []
        BWPList cell = {}
    end

    methods
        function obj = ComponentCarrierConfig(config, bwps)
            if nargin == 0
                obj.HARQState = containers.Map("KeyType", "char", "ValueType", "any");
                obj.MeasurementState = containers.Map( ...
                    "KeyType", "char", "ValueType", "any");
                return;
            end
            if ~isstruct(config) || ~isscalar(config)
                error("sixgr:phy:frame:InvalidComponentCarrierConfig", ...
                    "Component-carrier configuration must be a scalar struct.");
            end
            if nargin < 2
                error("sixgr:phy:frame:MissingComponentCarrierBWPs", ...
                    "ComponentCarrierConfig requires explicit BWPConfig objects.");
            end
            obj.CCID = localIdentifier(localRequired(config, ...
                ["CCID", "cc_id"], "CCID"), "CCID");
            obj.ServingCellID = localIdentifier(localRequired(config, ...
                ["ServingCellID", "serving_cell_id"], "ServingCellID"), ...
                "ServingCellID");
            obj.SchedulingCCIDs = localIdentifierVector(localRequired(config, ...
                ["SchedulingCCIDs", "scheduling_cc_ids"], ...
                "SchedulingCCIDs"), "SchedulingCCIDs");
            obj.CenterFrequencyHz = localPositiveFinite(localRequired(config, ...
                ["CenterFrequencyHz", "center_frequency_hz"], ...
                "CenterFrequencyHz"), "CenterFrequencyHz");
            obj.Band = localText(localRequired(config, ...
                ["Band", "band"], "Band"), "Band");
            obj.FrequencyRange = upper(localText(localRequired(config, ...
                ["FrequencyRange", "frequency_range"], ...
                "FrequencyRange"), "FrequencyRange"));
            research = localOptional(config, ["ResearchMode", "research_mode"], false);
            if ~((islogical(research) || isnumeric(research)) && ...
                    isscalar(research) && isfinite(double(research)) && ...
                    any(double(research) == [0, 1]))
                error("sixgr:phy:frame:InvalidResearchOptIn", ...
                    "Component carrier ResearchMode must be scalar logical.");
            end
            obj.ResearchMode = logical(research);
            if obj.ResearchMode && obj.FrequencyRange ~= "CUSTOM"
                error("sixgr:phy:frame:ResearchCarrierRangeMismatch", ...
                    "Research carriers must retain the explicit CUSTOM runtime frequency-range label.");
            end
            if ~obj.ResearchMode && ~any(obj.FrequencyRange == ["FR1", "FR2-1", "FR2-2"])
                error("sixgr:phy:frame:InvalidFrequencyRange", ...
                    "Component carrier FrequencyRange must be FR1, FR2-1, or FR2-2.");
            end
            obj.ChannelBandwidthMHz = localPositiveFinite(localRequired(config, ...
                ["ChannelBandwidthMHz", "channel_bandwidth_mhz"], ...
                "ChannelBandwidthMHz"), "ChannelBandwidthMHz");
            obj.DuplexMode = upper(localText(localRequired(config, ...
                ["DuplexMode", "duplex_mode"], "DuplexMode"), "DuplexMode"));
            if ~any(obj.DuplexMode == ["FDD", "TDD"])
                error("sixgr:phy:frame:InvalidDuplexMode", ...
                    "Component carrier DuplexMode must be FDD or TDD.");
            end
            if obj.ResearchMode && obj.DuplexMode ~= "TDD"
                error("sixgr:phy:frame:ResearchCarrierTDDOnly", ...
                    "The explicit research-carrier runtime currently supports TDD only.");
            end
            if obj.DuplexMode == "FDD"
                obj.DLCenterFrequencyHz = localPositiveFinite(localRequired( ...
                    config, ["DLCenterFrequencyHz", ...
                    "dl_center_frequency_hz"], "DLCenterFrequencyHz"), ...
                    "DLCenterFrequencyHz");
                obj.ULCenterFrequencyHz = localPositiveFinite(localRequired( ...
                    config, ["ULCenterFrequencyHz", ...
                    "ul_center_frequency_hz"], "ULCenterFrequencyHz"), ...
                    "ULCenterFrequencyHz");
                if obj.DLCenterFrequencyHz == obj.ULCenterFrequencyHz
                    error("sixgr:phy:frame:FDDRequiresSeparateFrequencies", ...
                        "FDD DL and UL center frequencies must be distinct.");
                end
            else
                obj.DLCenterFrequencyHz = obj.CenterFrequencyHz;
                obj.ULCenterFrequencyHz = obj.CenterFrequencyHz;
            end
            obj.DLCarrierGrid = localGrid(localRequired(config, ...
                ["DLCarrierGrid", "dl_carrier_grid"], "DLCarrierGrid"), ...
                "DL", obj.FrequencyRange, obj.DLCenterFrequencyHz, ...
                obj.ChannelBandwidthMHz, obj.ResearchMode);
            obj.ULCarrierGrid = localGrid(localRequired(config, ...
                ["ULCarrierGrid", "ul_carrier_grid"], "ULCarrierGrid"), ...
                "UL", obj.FrequencyRange, obj.ULCenterFrequencyHz, ...
                obj.ChannelBandwidthMHz, obj.ResearchMode);

            obj.BWPList = localBWPCell(bwps);
            for index = 1:numel(obj.BWPList)
                bwp = obj.BWPList{index};
                if bwp.CCID ~= obj.CCID
                    error("sixgr:phy:frame:BWPComponentCarrierMismatch", ...
                        "BWP '%s' belongs to CC '%s', not '%s'.", ...
                        bwp.BWPID, bwp.CCID, obj.CCID);
                end
                if bwp.ServingCellID ~= obj.ServingCellID
                    error("sixgr:phy:frame:BWPServingCellMismatch", ...
                        "BWP '%s' serving-cell identity does not match its carrier.", ...
                        bwp.BWPID);
                end
                if bwp.FrequencyRange ~= obj.FrequencyRange
                    error("sixgr:phy:frame:BWPFrequencyRangeMismatch", ...
                        "BWP '%s' frequency range differs from carrier '%s'.", ...
                        bwp.BWPID, obj.CCID);
                end
                if bwp.ResearchMode ~= obj.ResearchMode
                    error("sixgr:phy:frame:BWPResearchModeMismatch", ...
                        "BWP '%s' research provenance differs from its carrier.", bwp.BWPID);
                end
                grid = obj.gridForDirection(bwp.Direction);
                if bwp.CarrierNStartGrid ~= grid.NStartGrid || ...
                        bwp.CarrierNSizeGrid ~= grid.NSizeGrid
                    error("sixgr:phy:frame:BWPCarrierGridMismatch", ...
                        "BWP '%s' was validated against a different %s carrier grid.", ...
                        bwp.BWPID, bwp.Direction);
                end
            end
            obj.BWPState = sixgr.phy.frame.BWPStateMachine(obj.BWPList);
            obj.CarrierIndicatorMap = localCarrierIndicatorMap(localRequired( ...
                config, ["CarrierIndicatorMap", "carrier_indicator_map"], ...
                "CarrierIndicatorMap"));
            obj.validateCarrierIndicatorMap();

            obj.ResourceNamespace = "CC=" + obj.CCID + "|RESOURCE";
            obj.WaveformNamespace = "CC=" + obj.CCID + "|WAVEFORM";
            obj.MeasurementNamespace = "CC=" + obj.CCID + "|MEASUREMENT";
            obj.HARQState = containers.Map("KeyType", "char", "ValueType", "any");
            obj.MeasurementState = containers.Map( ...
                "KeyType", "char", "ValueType", "any");
        end

        function setAvailabilityResolver(obj, resolver)
            if ~(isa(resolver, "function_handle") && isscalar(resolver))
                error("sixgr:phy:frame:InvalidAvailabilityResolver", ...
                    "Availability resolver must be a scalar function handle.");
            end
            obj.AvailabilityResolver = resolver;
        end

        function setSlotFormatState(obj, state)
            %SETSLOTFORMATSTATE Adapt the canonical TDD availability API.
            if obj.DuplexMode ~= "TDD"
                error("sixgr:phy:frame:SlotFormatStateOnFDDCarrier", ...
                    "Slot-format state is applicable only to a TDD carrier.");
            end
            obj.AvailabilityResolver = @resolve;
            function result = resolve(~, bwp, slotStart, startSymbol, ...
                    numSymbols, direction)
                [frame, slot, ~, aligned] = slotStart.toNumerology(bwp);
                if ~aligned
                    result = struct( ...
                        "Available", false, ...
                        "ReasonCode", "slot_start_not_numerology_aligned", ...
                        "ObservedDirections", "UNKNOWN", ...
                        "DuplexMode", "TDD");
                    return;
                end
                absoluteSlot = double(frame) * bwp.SlotsPerFrame + ...
                    double(slot);
                result = sixgr.phy.frame.SlotFormatResolver.isAvailable( ...
                    state, absoluteSlot, startSymbol, numSymbols, direction);
            end
        end

        function result = symbolAvailability(obj, bwp, startTime, ...
                startSymbol, numSymbols, direction)
            if ~isa(bwp, "sixgr.phy.frame.BWPConfig") || ~isscalar(bwp)
                error("sixgr:phy:frame:InvalidBWPConfig", ...
                    "symbolAvailability requires a scalar BWPConfig.");
            end
            startTime = localTime(startTime);
            startSymbol = localNonnegativeInteger(startSymbol, "startSymbol");
            numSymbols = localPositiveInteger(numSymbols, "numSymbols");
            direction = localDirection(direction);
            if startSymbol + numSymbols > bwp.SymbolsPerSlot
                result = localAvailability(false, ...
                    "symbol_range_out_of_bounds", direction, "OUT_OF_RANGE");
                return;
            end
            if bwp.Direction ~= direction
                result = localAvailability(false, ...
                    "bwp_direction_mismatch", direction, bwp.Direction);
                return;
            end
            if obj.DuplexMode == "FDD"
                result = localAvailability(true, "available", direction, direction);
                return;
            end
            if isempty(obj.AvailabilityResolver)
                result = localAvailability(false, ...
                    "no_symbol_availability_resolver", direction, "UNKNOWN");
                return;
            end
            raw = obj.AvailabilityResolver( ...
                obj, bwp, startTime, startSymbol, numSymbols, direction);
            result = localNormalizeAvailability(raw, direction);
        end

        function scheduledCCID = mapCarrierIndicator(obj, indicator)
            indicator = localNonnegativeInteger(indicator, "CarrierIndicator");
            matches = arrayfun(@(x) double(x.Indicator) == indicator, ...
                obj.CarrierIndicatorMap);
            if nnz(matches) ~= 1
                error("sixgr:phy:frame:UnknownCarrierIndicator", ...
                    "Carrier '%s' has no carrier-indicator mapping for %d.", ...
                    obj.CCID, indicator);
            end
            scheduledCCID = string(obj.CarrierIndicatorMap(matches).ScheduledCCID);
        end

        function result = validateGrantIdentity(obj, grant)
            if ~isstruct(grant) || ~isscalar(grant)
                error("sixgr:phy:frame:InvalidCarrierGrant", ...
                    "Carrier grant identity must be a scalar struct.");
            end
            scheduling = localIdentifier(localRequired(grant, ...
                ["SchedulingCCID", "scheduling_cc_id"], ...
                "SchedulingCCID"), "SchedulingCCID");
            scheduled = localIdentifier(localRequired(grant, ...
                ["ScheduledCCID", "scheduled_cc_id"], ...
                "ScheduledCCID"), "ScheduledCCID");
            indicator = localNonnegativeInteger(localRequired(grant, ...
                ["CarrierIndicator", "carrier_indicator"], ...
                "CarrierIndicator"), "CarrierIndicator");
            if scheduling ~= obj.CCID
                result = localIdentityDecision(false, ...
                    "scheduling_carrier_identity_mismatch", scheduling, ...
                    scheduled, indicator);
                return;
            end
            try
                mapped = obj.mapCarrierIndicator(indicator);
            catch cause
                if string(cause.identifier) == ...
                        "sixgr:phy:frame:UnknownCarrierIndicator"
                    result = localIdentityDecision(false, ...
                        "unknown_carrier_indicator", scheduling, ...
                        scheduled, indicator);
                    return;
                end
                rethrow(cause);
            end
            if mapped ~= scheduled
                result = localIdentityDecision(false, ...
                    "carrier_indicator_target_mismatch", scheduling, ...
                    scheduled, indicator);
                return;
            end
            result = localIdentityDecision(true, "carrier_identity_valid", ...
                scheduling, scheduled, indicator);
        end

        function grid = createResourceGrid(obj, bwpID, direction, numPorts)
            if nargin < 4
                numPorts = 1;
            end
            bwp = obj.BWPState.configuredBWP(bwpID, direction);
            dimensions = bwp.resourceGridDimensions(numPorts);
            grid = complex(zeros(dimensions));
        end

        function key = resourceKey(obj, bwpID, direction, ...
                resourceType, resourceID)
            bwp = obj.BWPState.configuredBWP(bwpID, direction);
            key = bwp.resourceKey(resourceType, resourceID);
        end

        function key = harqKey(obj, direction, processID)
            direction = localDirection(direction);
            processID = localNonnegativeInteger(processID, "HARQProcessID");
            key = "CC=" + obj.CCID + "|HARQ|DIR=" + direction + ...
                "|PID=" + string(processID);
        end

        function putHARQState(obj, direction, processID, state)
            key = char(obj.harqKey(direction, processID));
            obj.HARQState(key) = state;
        end

        function [state, found] = getHARQState(obj, direction, processID)
            key = char(obj.harqKey(direction, processID));
            found = isKey(obj.HARQState, key);
            if found
                state = obj.HARQState(key);
            else
                state = [];
            end
        end

        function count = harqStateCount(obj)
            count = obj.HARQState.Count;
        end

        function key = measurementKey(obj, measurementID)
            measurementID = localIdentifier(measurementID, "measurementID");
            key = obj.MeasurementNamespace + "|ID=" + measurementID;
        end

        function putMeasurementState(obj, measurementID, state)
            obj.MeasurementState(char(obj.measurementKey(measurementID))) = state;
        end

        function [state, found] = getMeasurementState(obj, measurementID)
            key = char(obj.measurementKey(measurementID));
            found = isKey(obj.MeasurementState, key);
            if found
                state = obj.MeasurementState(key);
            else
                state = [];
            end
        end

        function bwp = configuredBWP(obj, bwpID, direction)
            bwp = obj.BWPState.configuredBWP(bwpID, direction);
        end

        function grid = gridForDirection(obj, direction)
            direction = localDirection(direction);
            if direction == "DL"
                grid = obj.DLCarrierGrid;
            else
                grid = obj.ULCarrierGrid;
            end
        end

        function output = toStruct(obj)
            map = obj.CarrierIndicatorMap;
            output = struct( ...
                "CCID", obj.CCID, ...
                "ServingCellID", obj.ServingCellID, ...
                "SchedulingCCIDs", obj.SchedulingCCIDs, ...
                "CenterFrequencyHz", obj.CenterFrequencyHz, ...
                "DLCenterFrequencyHz", obj.DLCenterFrequencyHz, ...
                "ULCenterFrequencyHz", obj.ULCenterFrequencyHz, ...
                "Band", obj.Band, ...
                "FrequencyRange", obj.FrequencyRange, ...
                "ResearchMode", obj.ResearchMode, ...
                "StandardNR", ~obj.ResearchMode, ...
                "ChannelBandwidthMHz", obj.ChannelBandwidthMHz, ...
                "DuplexMode", obj.DuplexMode, ...
                "DLCarrierGrid", obj.DLCarrierGrid, ...
                "ULCarrierGrid", obj.ULCarrierGrid, ...
                "ActiveDLBWPID", obj.BWPState.ActiveDLBWPID, ...
                "ActiveULBWPID", obj.BWPState.ActiveULBWPID, ...
                "CarrierIndicatorMap", map, ...
                "ResourceNamespace", obj.ResourceNamespace, ...
                "WaveformNamespace", obj.WaveformNamespace, ...
                "MeasurementNamespace", obj.MeasurementNamespace, ...
                "HARQStateCount", obj.HARQState.Count);
        end
    end

    methods (Access = private)
        function validateCarrierIndicatorMap(obj)
            indicators = double([obj.CarrierIndicatorMap.Indicator]);
            targets = string({obj.CarrierIndicatorMap.ScheduledCCID});
            if numel(unique(indicators)) ~= numel(indicators)
                error("sixgr:phy:frame:DuplicateCarrierIndicator", ...
                    "Carrier-indicator values must be unique per scheduling CC.");
            end
            if ~any(indicators == 0 & targets == obj.CCID)
                error("sixgr:phy:frame:MissingSelfCarrierIndicator", ...
                    "Carrier '%s' must explicitly map indicator 0 to itself.", ...
                    obj.CCID);
            end
        end
    end
end

function grid = localGrid(input, direction, frequencyRange, ...
        centerFrequencyHz, channelBandwidthMHz, researchMode)
if ~isstruct(input) || ~isscalar(input)
    error("sixgr:phy:frame:InvalidCarrierGrid", ...
        "%s carrier grid must be a scalar struct.", direction);
end
nStart = localNonnegativeInteger(localRequired(input, ...
    ["NStartGrid", "n_start_grid"], "NStartGrid"), "NStartGrid");
nSize = localPositiveInteger(localRequired(input, ...
    ["NSizeGrid", "n_size_grid"], "NSizeGrid"), "NSizeGrid");
scs = localPositiveFinite(localRequired(input, ...
    ["SubcarrierSpacingKHz", "SCSKHz", "scs_khz"], ...
    "SubcarrierSpacingKHz"), "SubcarrierSpacingKHz");
cyclicPrefix = localOptional(input, ...
    ["CyclicPrefix", "cyclic_prefix", "cp_type"], "normal");
if researchMode
    resolved = sixgr.phy.frame.CarrierGridConfig.custom( ...
        "ResearchMode", true, "CenterFrequencyHz", centerFrequencyHz, ...
        "ChannelBandwidthMHz", channelBandwidthMHz, ...
        "SubcarrierSpacingKHz", scs, "NSizeGrid", nSize, ...
        "NStartGrid", nStart, "CyclicPrefix", cyclicPrefix, ...
        "MinimumLowGuardbandHz", localRequired(input, ...
            "MinimumLowGuardbandHz", "MinimumLowGuardbandHz"), ...
        "MinimumHighGuardbandHz", localRequired(input, ...
            "MinimumHighGuardbandHz", "MinimumHighGuardbandHz"));
    rowKey = "none_custom_research_grid";
else
    resolved = sixgr.phy.frame.CarrierGridConfig.resolve( ...
        "Role", "gNB", ...
        "FrequencyRange", frequencyRange, ...
        "CenterFrequencyHz", centerFrequencyHz, ...
        "ChannelBandwidthMHz", channelBandwidthMHz, ...
        "SubcarrierSpacingKHz", scs, ...
        "ConfiguredNSizeGrid", nSize, ...
        "NStartGrid", nStart, ...
        "CyclicPrefix", cyclicPrefix);
    rowKey = string(resolved.RowKey);
end
grid = struct( ...
    "Direction", string(direction), ...
    "NStartGrid", nStart, ...
    "NSizeGrid", nSize, ...
    "SubcarrierSpacingKHz", scs, ...
    "Mu", double(resolved.Mu), ...
    "CyclicPrefix", string(resolved.CyclicPrefix), ...
    "SymbolsPerSlot", double(resolved.SymbolsPerSlot), ...
    "SlotsPerFrame", double(resolved.SlotsPerFrame), ...
    "FrequencyRange", string(resolved.FrequencyRange), ...
    "StandardNR", ~researchMode, ...
    "SourceTable", string(resolved.SourceTable), ...
    "RowKey", rowKey, ...
    "IndexConvention", "zero_based");
if researchMode
    grid.MinimumLowGuardbandHz = resolved.MinimumLowGuardbandHz;
    grid.MinimumHighGuardbandHz = resolved.MinimumHighGuardbandHz;
end
end

function values = localBWPCell(input)
if iscell(input)
    values = input(:).';
elseif isa(input, "sixgr.phy.frame.BWPConfig")
    values = arrayfun(@(x) x, input(:).', "UniformOutput", false);
else
    error("sixgr:phy:frame:InvalidBWPSet", ...
        "Component-carrier BWPs must be BWPConfig objects.");
end
if isempty(values)
    error("sixgr:phy:frame:EmptyBWPSet", ...
        "A component carrier requires at least one configured BWP.");
end
for index = 1:numel(values)
    if ~isa(values{index}, "sixgr.phy.frame.BWPConfig") || ...
            ~isscalar(values{index})
        error("sixgr:phy:frame:InvalidBWPSet", ...
            "Every component-carrier BWP must be a scalar BWPConfig.");
    end
end
end

function map = localCarrierIndicatorMap(input)
if iscell(input)
    input = [input{:}];
end
if ~isstruct(input) || isempty(input)
    error("sixgr:phy:frame:InvalidCarrierIndicatorMap", ...
        "CarrierIndicatorMap must be a nonempty struct sequence.");
end
map = repmat(struct("Indicator", 0, "ScheduledCCID", ""), numel(input), 1);
for index = 1:numel(input)
    map(index).Indicator = localNonnegativeInteger(localRequired(input(index), ...
        ["Indicator", "indicator"], "Indicator"), "Indicator");
    map(index).ScheduledCCID = localIdentifier(localRequired(input(index), ...
        ["ScheduledCCID", "scheduled_cc_id"], "ScheduledCCID"), ...
        "ScheduledCCID");
end
end

function result = localNormalizeAvailability(input, direction)
if ~isstruct(input) || ~isscalar(input)
    error("sixgr:phy:frame:InvalidAvailabilityResult", ...
        "Availability resolver must return a scalar result struct.");
end
available = localRequired(input, ["Available", "available"], "Available");
if ~((islogical(available) || isnumeric(available)) && isscalar(available) && ...
        isfinite(double(available)) && any(double(available) == [0, 1]))
    error("sixgr:phy:frame:InvalidAvailabilityResult", ...
        "Availability result Available must be scalar logical.");
end
reason = string(localRequired(input, ...
    ["ReasonCode", "reason_code"], "ReasonCode"));
observed = localOptional(input, ...
    ["ObservedDirections", "observed_directions"], strings(0,1));
duplex = string(localOptional(input, ["DuplexMode", "duplex_mode"], "TDD"));
result = struct( ...
    "Available", logical(available), ...
    "ReasonCode", reason, ...
    "RequestedDirection", string(direction), ...
    "ObservedDirections", string(observed), ...
    "DuplexMode", duplex);
end

function result = localAvailability(available, reason, requested, observed)
result = struct( ...
    "Available", logical(available), ...
    "ReasonCode", string(reason), ...
    "RequestedDirection", string(requested), ...
    "ObservedDirections", string(observed), ...
    "DuplexMode", "FDD");
end

function result = localIdentityDecision(valid, reason, scheduling, ...
        scheduled, indicator)
result = struct( ...
    "Valid", logical(valid), ...
    "ReasonCode", string(reason), ...
    "SchedulingCCID", string(scheduling), ...
    "ScheduledCCID", string(scheduled), ...
    "CarrierIndicator", double(indicator));
end

function value = localRequired(input, aliases, label)
names = string(fieldnames(input));
for alias = string(aliases(:)).'
    index = find(strcmpi(names, alias), 1);
    if ~isempty(index)
        value = input.(char(names(index)));
        return;
    end
end
error("sixgr:phy:frame:MissingComponentCarrierField", ...
    "Component-carrier field '%s' is required.", label);
end

function value = localOptional(input, aliases, defaultValue)
names = string(fieldnames(input));
for alias = string(aliases(:)).'
    index = find(strcmpi(names, alias), 1);
    if ~isempty(index)
        value = input.(char(names(index)));
        return;
    end
end
value = defaultValue;
end

function value = localIdentifierVector(input, label)
if isnumeric(input)
    if any(~isfinite(input(:))) || any(input(:) < 0) || ...
            any(input(:) ~= fix(input(:)))
        error("sixgr:phy:frame:InvalidCarrierIdentifier", ...
            "%s numeric values must be nonnegative integers.", label);
    end
    value = string(double(input(:)));
elseif ischar(input) || isstring(input) || iscellstr(input)
    value = string(input(:));
else
    error("sixgr:phy:frame:InvalidCarrierIdentifier", ...
        "%s must be a nonempty identifier vector.", label);
end
if isempty(value) || any(strlength(strtrim(value)) == 0) || ...
        any(contains(value, "|"))
    error("sixgr:phy:frame:InvalidCarrierIdentifier", ...
        "%s contains an empty or reserved identifier.", label);
end
value = unique(strtrim(value), "stable");
end

function value = localIdentifier(input, label)
value = localIdentifierVector(input, label);
if numel(value) ~= 1
    error("sixgr:phy:frame:InvalidCarrierIdentifier", ...
        "%s must be scalar.", label);
end
end

function value = localText(input, label)
if ~(ischar(input) || (isstring(input) && isscalar(input)))
    error("sixgr:phy:frame:InvalidComponentCarrierField", ...
        "%s must be scalar text.", label);
end
value = strtrim(string(input));
if strlength(value) == 0
    error("sixgr:phy:frame:InvalidComponentCarrierField", ...
        "%s must not be empty.", label);
end
end

function value = localDirection(input)
value = upper(localText(input, "direction"));
if any(value == ["DOWNLINK", "D"])
    value = "DL";
elseif any(value == ["UPLINK", "U"])
    value = "UL";
end
if ~any(value == ["DL", "UL"])
    error("sixgr:phy:frame:InvalidBWPDirection", ...
        "Direction must be DL or UL.");
end
end

function value = localPositiveFinite(input, label)
if ~(isnumeric(input) && isreal(input) && isscalar(input) && ...
        isfinite(double(input)) && double(input) > 0)
    error("sixgr:phy:frame:InvalidComponentCarrierField", ...
        "%s must be a positive finite scalar.", label);
end
value = double(input);
end

function value = localNonnegativeInteger(input, label)
if ~(isnumeric(input) && isreal(input) && isscalar(input) && ...
        isfinite(double(input)) && double(input) >= 0 && ...
        double(input) == fix(double(input)))
    error("sixgr:phy:frame:InvalidComponentCarrierField", ...
        "%s must be a nonnegative integer scalar.", label);
end
value = double(input);
end

function value = localPositiveInteger(input, label)
value = localNonnegativeInteger(input, label);
if value < 1
    error("sixgr:phy:frame:InvalidComponentCarrierField", ...
        "%s must be a positive integer scalar.", label);
end
end

function value = localTime(input)
if ~isa(input, "sixgr.phy.frame.AbsoluteTime") || ~isscalar(input)
    error("sixgr:phy:frame:InvalidAbsoluteTime", ...
        "Timing input must be a scalar AbsoluteTime.");
end
value = input;
end
