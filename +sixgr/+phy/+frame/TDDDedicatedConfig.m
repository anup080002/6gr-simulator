classdef TDDDedicatedConfig
    %TDDDEDICATEDCONFIG Dedicated overrides layered over common TDD state.
    %
    % Dedicated configuration may resolve only common-flexible symbols.
    % CommonDirection is copied for inspection but is never modified.

    properties (SetAccess = private)
        CommonConfig sixgr.phy.frame.TDDCommonConfig
        CommonDirection char
        DedicatedDirection string
        SymbolDirection char
        ResolvedDirection string
        Overrides struct
        IndexConvention (1,1) string = "zero_based"
        DuplexMode (1,1) string = "TDD"
    end

    methods (Static)
        function obj = apply(commonConfig, overrides)
            arguments
                commonConfig (1,1) sixgr.phy.frame.TDDCommonConfig
                overrides struct = struct([])
            end
            common = commonConfig.CommonDirection;
            dedicated = strings(size(common));
            symbolMap = common;
            normalized = repmat(struct( ...
                "SlotIndex", 0, "Mode", "", ...
                "FirstDownlinkSymbols", 0, "LastUplinkSymbols", 0), ...
                0, 1);
            ratio = commonConfig.ActiveSubcarrierSpacingKHz / ...
                commonConfig.ReferenceSubcarrierSpacingKHz;

            for i = 1:numel(overrides)
                rule = sixgr.phy.frame.TDDDedicatedConfig.normalizeOverride( ...
                    overrides(i), ...
                    commonConfig.ReferenceSymbolsPerSlot, ...
                    commonConfig.ReferenceSlotsPerPattern);
                rows = rule.SlotIndex * ratio + (1:ratio);
                commonRow = reshape(common(rows, :).', 1, []);
                desiredReference = repmat( ...
                    'F', 1, commonConfig.ReferenceSymbolsPerSlot);
                switch rule.Mode
                    case "alldownlink"
                        desiredReference(:) = 'D';
                    case "alluplink"
                        desiredReference(:) = 'U';
                    case "explicit"
                        if rule.FirstDownlinkSymbols > 0
                            desiredReference(1:rule.FirstDownlinkSymbols) = 'D';
                        end
                        if rule.LastUplinkSymbols > 0
                            firstUL = commonConfig.ReferenceSymbolsPerSlot - ...
                                rule.LastUplinkSymbols + 1;
                            if any(desiredReference(firstUL:end) == 'D')
                                error("sixgr:phy:frame:DedicatedExplicitOverlap", ...
                                    "Dedicated DL and UL regions overlap in slot %d.", ...
                                    rule.SlotIndex);
                            end
                            desiredReference(firstUL:end) = 'U';
                        end
                end
                desired = repelem(desiredReference, ratio);

                sixgr.phy.frame.TDDDedicatedConfig.rejectContradictions( ...
                    commonRow, desired, ...
                    rule.SlotIndex);
                flex = commonRow == 'F';
                dedicatedFlat = reshape(dedicated(rows, :).', 1, []);
                symbolFlat = reshape(symbolMap(rows, :).', 1, []);
                if any(strlength(dedicatedFlat(flex)) > 0)
                    error("sixgr:phy:frame:DuplicateDedicatedSlotOverride", ...
                        "Slot %d has more than one dedicated override.", rule.SlotIndex);
                end
                dedicatedFlat(flex) = ...
                    sixgr.phy.frame.TDDDedicatedConfig. ...
                    charVectorToStrings(desired(flex));
                changed = flex & desired ~= 'F';
                symbolFlat(changed) = desired(changed);
                dedicated(rows, :) = reshape(dedicatedFlat, ...
                    commonConfig.SymbolsPerSlot, ratio).';
                symbolMap(rows, :) = reshape(symbolFlat, ...
                    commonConfig.SymbolsPerSlot, ratio).';
                normalized(end + 1, 1) = rule; %#ok<AGROW>
            end

            resolved = strings(size(common));
            resolved(symbolMap == 'D') = "D";
            resolved(symbolMap == 'U') = "U";
            resolved(symbolMap == 'F') = "UNRESOLVED_FLEX";

            obj = sixgr.phy.frame.TDDDedicatedConfig;
            obj.CommonConfig = commonConfig;
            obj.CommonDirection = common;
            obj.DedicatedDirection = dedicated;
            obj.SymbolDirection = symbolMap;
            obj.ResolvedDirection = resolved;
            obj.Overrides = normalized;
        end
    end

    methods
        function text = compactMap(obj)
            text = strjoin(string(cellstr(obj.SymbolDirection)), "|");
        end

        function directions = directionsForFrame(obj, frameIndex)
            validateattributes(frameIndex, {'numeric'}, ...
                {'scalar','integer','nonnegative','finite'});
            cfg = obj.CommonConfig;
            absoluteSlots = double(frameIndex) * cfg.SlotsPerFrame + ...
                (0:(cfg.SlotsPerFrame - 1));
            rows = mod(absoluteSlots, cfg.ActiveSlotsPerPattern) + 1;
            directions = obj.SymbolDirection(rows, :);
        end
    end

    methods (Static, Access = private)
        function rule = normalizeOverride(raw, symbolsPerSlot, slotsPerPattern)
            slot = sixgr.phy.frame.TDDDedicatedConfig.firstField(raw, ...
                {"SlotIndex","slotIndex","Slot"});
            mode = sixgr.phy.frame.TDDDedicatedConfig.firstField(raw, ...
                {"Mode","mode","SlotFormat"});
            if isempty(slot) || isempty(mode)
                error("sixgr:phy:frame:MissingTDDDedicatedField", ...
                    "Each dedicated override requires SlotIndex and Mode.");
            end
            validateattributes(slot, {'numeric'}, ...
                {'scalar','integer','nonnegative','finite'});
            if slot >= slotsPerPattern
                error("sixgr:phy:frame:DedicatedSlotOutsideCommonPeriod", ...
                    "Dedicated slot %d is outside the %d-slot common period.", ...
                    slot, slotsPerPattern);
            end
            mode = lower(strtrim(string(mode)));
            if ~any(mode == ["alldownlink","alluplink","explicit"])
                error("sixgr:phy:frame:InvalidTDDDedicatedMode", ...
                    "Dedicated Mode must be allDownlink, allUplink, or explicit.");
            end
            dl = 0;
            ul = 0;
            if mode == "explicit"
                dl = sixgr.phy.frame.TDDDedicatedConfig.firstField(raw, ...
                    {"FirstDownlinkSymbols","DedicatedDLSymbols", ...
                    "nrofDownlinkSymbols","DLSymbols"});
                ul = sixgr.phy.frame.TDDDedicatedConfig.firstField(raw, ...
                    {"LastUplinkSymbols","DedicatedULSymbols", ...
                    "nrofUplinkSymbols","ULSymbols"});
                if isempty(dl) || isempty(ul)
                    error("sixgr:phy:frame:MissingTDDDedicatedField", ...
                        "Explicit override requires first DL and last UL counts.");
                end
                validateattributes(dl, {'numeric'}, ...
                    {'scalar','integer','nonnegative','<=',symbolsPerSlot});
                validateattributes(ul, {'numeric'}, ...
                    {'scalar','integer','nonnegative','<=',symbolsPerSlot});
                if dl + ul > symbolsPerSlot
                    error("sixgr:phy:frame:DedicatedExplicitOverlap", ...
                        "Explicit dedicated DL and UL counts exceed the slot.");
                end
            end
            rule = struct("SlotIndex", double(slot), "Mode", mode, ...
                "FirstDownlinkSymbols", double(dl), ...
                "LastUplinkSymbols", double(ul));
        end

        function rejectContradictions(common, desired, slotIndex)
            if any(common == 'D' & desired == 'U') || ...
                    any(common == 'U' & desired == 'D')
                error("sixgr:phy:frame:DedicatedOverridesNonFlexibleSymbol", ...
                    "Dedicated configuration for slot %d contradicts a " + ...
                    "common fixed symbol.", slotIndex);
            end
        end

        function value = firstField(s, names)
            value = [];
            fields = fieldnames(s);
            for i = 1:numel(names)
                index = find(strcmpi(fields, names{i}), 1);
                if ~isempty(index)
                    value = s.(fields{index});
                    return;
                end
            end
        end

        function values = charVectorToStrings(chars)
            values = reshape(string(cellstr(chars(:))), 1, []);
        end
    end

    methods (Access = private)
        function obj = TDDDedicatedConfig
        end
    end
end
