classdef TDDCommonConfig
    %TDDCOMMONCONFIG Canonical symbol-level TDD common configuration.
    %
    % PHY-facing slot and symbol indices are zero based. CommonDirection is
    % immutable and contains only D, U, and F. Flexible symbols remain
    % UNRESOLVED_FLEX in ResolvedDirection until a dedicated or runtime
    % decision is applied.

    properties (SetAccess = private)
        ReferenceSubcarrierSpacingKHz (1,1) double
        ActiveSubcarrierSpacingKHz (1,1) double
        CyclicPrefix (1,1) string
        SymbolsPerSlot (1,1) double
        ReferenceSymbolsPerSlot (1,1) double
        SlotsPerFrame (1,1) double
        PatternDurationMilliseconds (1,1) double
        ReferenceSlotsPerPattern (1,1) double
        ActiveSlotsPerPattern (1,1) double
        CommonDirection char
        ResolvedDirection string
        Pattern1 struct
        Pattern2 struct
        IndexConvention (1,1) string = "zero_based"
        DuplexMode (1,1) string = "TDD"
        AlignmentEpoch (1,1) string = "first_symbol_even_frame"
    end

    methods (Static)
        function obj = resolve(varargin)
            %RESOLVE Resolve RRC-equivalent common TDD patterns.
            p = inputParser;
            p.FunctionName = "sixgr.phy.frame.TDDCommonConfig.resolve";
            addParameter(p, "ReferenceSubcarrierSpacingKHz", [], ...
                @(x) isnumeric(x) && isscalar(x));
            addParameter(p, "ActiveSubcarrierSpacingKHz", [], ...
                @(x) isnumeric(x) && isscalar(x));
            addParameter(p, "CyclicPrefix", "normal", ...
                @(x) ischar(x) || isstring(x));
            addParameter(p, "Pattern1", struct(), @isstruct);
            addParameter(p, "Pattern2", struct(), ...
                @(x) isempty(x) || isstruct(x));
            parse(p, varargin{:});

            refSCS = double(p.Results.ReferenceSubcarrierSpacingKHz);
            activeSCS = double(p.Results.ActiveSubcarrierSpacingKHz);
            cp = lower(strtrim(string(p.Results.CyclicPrefix)));
            [referenceNumerology, activeNumerology] = ...
                sixgr.phy.frame.TDDCommonConfig.resolveNumerologies( ...
                refSCS, activeSCS, cp);
            activeSymbols = double(activeNumerology.SymbolsPerSlot);
            refSymbols = double(referenceNumerology.SymbolsPerSlot);

            pattern1 = sixgr.phy.frame.TDDCommonConfig.normalizePattern( ...
                p.Results.Pattern1, ...
                "pattern1", referenceNumerology);
            hasPattern2 = ~isempty(p.Results.Pattern2) && ...
                ~isempty(fieldnames(p.Results.Pattern2));
            if hasPattern2
                pattern2 = sixgr.phy.frame.TDDCommonConfig.normalizePattern( ...
                    p.Results.Pattern2, "pattern2", referenceNumerology);
            else
                pattern2 = struct();
            end

            durationMs = pattern1.PeriodicityMilliseconds;
            referenceFlat = sixgr.phy.frame.TDDCommonConfig.resolvePattern( ...
                pattern1, refSymbols);
            if hasPattern2
                durationMs = durationMs + pattern2.PeriodicityMilliseconds;
                referenceFlat = [referenceFlat, ...
                    sixgr.phy.frame.TDDCommonConfig.resolvePattern( ...
                    pattern2, refSymbols)]; %#ok<AGROW>
            end
            durationTicks = ...
                sixgr.phy.frame.TDDCommonConfig.durationTicks(durationMs);
            twentyMillisecondsTicks = int64(2) * ...
                sixgr.phy.frame.AbsoluteTime.TicksPerFrame;
            if mod(twentyMillisecondsTicks, durationTicks) ~= 0
                error("sixgr:phy:frame:TDDPeriodDoesNotDivide20ms", ...
                    "The combined common TDD period %.12g ms must divide 20 ms exactly.", ...
                    durationMs);
            end

            expectedActiveSlots = ...
                sixgr.phy.frame.TDDCommonConfig.slotsInDuration( ...
                durationTicks, activeNumerology, "combined common TDD period");
            activeFlat = ...
                sixgr.phy.frame.TDDCommonConfig.mapReferenceToActive( ...
                referenceFlat, referenceNumerology, activeNumerology, ...
                expectedActiveSlots);
            expectedSymbols = expectedActiveSlots * activeSymbols;
            if numel(activeFlat) ~= expectedSymbols
                error("sixgr:phy:frame:TDDNumerologyMappingNotExact", ...
                    "The reference-SCS pattern cannot be mapped to the active " + ...
                    "BWP symbol grid without rounding time.");
            end
            common = reshape(activeFlat, activeSymbols, expectedActiveSlots).';
            resolved = strings(size(common));
            resolved(common == 'D') = "D";
            resolved(common == 'U') = "U";
            resolved(common == 'F') = "UNRESOLVED_FLEX";

            obj = sixgr.phy.frame.TDDCommonConfig;
            obj.ReferenceSubcarrierSpacingKHz = refSCS;
            obj.ActiveSubcarrierSpacingKHz = activeSCS;
            obj.CyclicPrefix = cp;
            obj.SymbolsPerSlot = activeSymbols;
            obj.ReferenceSymbolsPerSlot = refSymbols;
            obj.SlotsPerFrame = double(activeNumerology.SlotsPerFrame);
            obj.PatternDurationMilliseconds = durationMs;
            obj.ReferenceSlotsPerPattern = numel(referenceFlat) / refSymbols;
            obj.ActiveSlotsPerPattern = expectedActiveSlots;
            obj.CommonDirection = common;
            obj.ResolvedDirection = resolved;
            obj.Pattern1 = pattern1;
            obj.Pattern2 = pattern2;
        end
    end

    methods
        function common = directionsForFrame(obj, frameIndex)
            %DIRECTIONSFORFRAME Return the common map for a 10 ms frame.
            validateattributes(frameIndex, {'numeric'}, ...
                {'scalar','integer','nonnegative','finite'});
            absoluteSlots = double(frameIndex) * obj.SlotsPerFrame + ...
                (0:(obj.SlotsPerFrame - 1));
            common = obj.directionsAtAbsoluteSlots(absoluteSlots);
        end

        function common = directionsAtAbsoluteSlots(obj, absoluteSlots)
            %DIRECTIONSATABSOLUTESLOTS Resolve slots against the even-frame epoch.
            validateattributes(absoluteSlots, {'numeric'}, ...
                {'vector','integer','nonnegative','finite'});
            cycleSlots = obj.ActiveSlotsPerPattern;
            rows = mod(double(absoluteSlots), cycleSlots) + 1;
            common = obj.CommonDirection(rows, :);
        end

        function resolved = resolvedDirectionsForFrame(obj, frameIndex)
            validateattributes(frameIndex, {'numeric'}, ...
                {'scalar','integer','nonnegative','finite'});
            absoluteSlots = double(frameIndex) * obj.SlotsPerFrame + ...
                (0:(obj.SlotsPerFrame - 1));
            rows = mod(absoluteSlots, obj.ActiveSlotsPerPattern) + 1;
            resolved = obj.ResolvedDirection(rows, :);
        end

        function text = compactMap(obj)
            %COMPACTMAP Return a pipe-delimited zero-based slot map.
            rows = string(cellstr(obj.CommonDirection));
            text = strjoin(rows, "|");
        end
    end

    methods (Static, Access = private)
        function [reference, active] = resolveNumerologies( ...
                refSCS, activeSCS, cp)
            if ~any(cp == ["normal", "extended"])
                error("sixgr:phy:frame:UnsupportedCyclicPrefix", ...
                    "CyclicPrefix must be normal or extended.");
            end
            if cp == "extended" && (refSCS ~= 60 || activeSCS ~= 60)
                error("sixgr:phy:frame:ExtendedCPRequires60kHz", ...
                    "Extended CP TDD mapping is supported only at 60 kHz.");
            end
            try
                reference = sixgr.phy.frame.NumerologyCatalog.resolve( ...
                    refSCS, cp, "generic_waveform_test", "");
            catch cause
                if any(string(cause.identifier) == [ ...
                        "sixgr:phy:frame:InvalidSubcarrierSpacing", ...
                        "sixgr:phy:frame:UnsupportedSubcarrierSpacing"])
                    error("sixgr:phy:frame:UnsupportedReferenceSCS", ...
                        "Reference SCS %.12g kHz is not in the canonical " + ...
                        "Release-18 numerology catalog.", refSCS);
                end
                rethrow(cause);
            end
            try
                active = sixgr.phy.frame.NumerologyCatalog.resolve( ...
                    activeSCS, cp, "generic_waveform_test", "");
            catch cause
                if any(string(cause.identifier) == [ ...
                        "sixgr:phy:frame:InvalidSubcarrierSpacing", ...
                        "sixgr:phy:frame:UnsupportedSubcarrierSpacing"])
                    error("sixgr:phy:frame:UnsupportedActiveBWPSCS", ...
                        "Active BWP SCS %.12g kHz is not in the canonical " + ...
                        "Release-18 numerology catalog.", activeSCS);
                end
                rethrow(cause);
            end
            if refSCS > activeSCS
                error("sixgr:phy:frame:ReferenceSCSExceedsActiveBWPSCS", ...
                    "Reference SCS %.12g kHz exceeds active BWP SCS %.12g kHz.", ...
                    refSCS, activeSCS);
            end
        end

        function ticks = durationTicks(milliseconds)
            raw = double(milliseconds) * ...
                double(sixgr.phy.frame.AbsoluteTime.TicksPerSecond) / 1e3;
            nearest = round(raw);
            if ~(isfinite(raw) && raw > 0 && abs(raw - nearest) < 1e-7)
                error("sixgr:phy:frame:TDDPeriodNotOnAbsoluteTimeline", ...
                    "TDD periodicity %.12g ms is not representable in Tc ticks.", ...
                    milliseconds);
            end
            ticks = int64(nearest);
        end

        function slots = slotsInDuration(ticks, numerology, label)
            ticksPerSlot = idivide( ...
                sixgr.phy.frame.AbsoluteTime.TicksPerFrame, ...
                int64(numerology.SlotsPerFrame), "floor");
            if mod(ticks, ticksPerSlot) ~= 0
                error("sixgr:phy:frame:TDDPeriodNotIntegralSlots", ...
                    "%s is not an integer number of %.12g kHz slots.", ...
                    label, numerology.SubcarrierSpacingKHz);
            end
            slots = double(idivide(ticks, ticksPerSlot, "floor"));
            if slots < 1
                error("sixgr:phy:frame:TDDPeriodNotIntegralSlots", ...
                    "%s must contain at least one complete slot.", label);
            end
        end

        function activeFlat = mapReferenceToActive( ...
                referenceFlat, referenceNumerology, activeNumerology, ...
                activeSlots)
            activeSymbols = double(activeNumerology.SymbolsPerSlot);
            referenceSymbols = double(referenceNumerology.SymbolsPerSlot);
            activeFlat = repmat('F', 1, activeSlots * activeSymbols);
            referenceSymbolsPerFrame = ...
                double(referenceNumerology.SlotsPerFrame) * ...
                referenceSymbols;
            for index = 0:(numel(activeFlat) - 1)
                absoluteSlot = floor(index / activeSymbols);
                symbol = mod(index, activeSymbols);
                startTime = sixgr.phy.frame.AbsoluteTime. ...
                    fromAbsoluteSlotSymbol(absoluteSlot, symbol, ...
                    activeNumerology);
                endTime = startTime.plusSymbols(1, activeNumerology);
                endInside = sixgr.phy.frame.AbsoluteTime.fromTicks( ...
                    endTime.tickValue() - int64(1));
                [startFrame, startSlot, startSymbol, ~] = ...
                    startTime.toNumerology(referenceNumerology);
                [endFrame, endSlot, endSymbol, ~] = ...
                    endInside.toNumerology(referenceNumerology);
                startReferenceIndex = double(startFrame) * ...
                    referenceSymbolsPerFrame + double(startSlot) * ...
                    referenceSymbols + double(startSymbol);
                endReferenceIndex = double(endFrame) * ...
                    referenceSymbolsPerFrame + double(endSlot) * ...
                    referenceSymbols + double(endSymbol);
                if startReferenceIndex ~= endReferenceIndex
                    error("sixgr:phy:frame:TDDNumerologyMappingNotExact", ...
                        "An active-BWP symbol crosses a reference-SCS " + ...
                        "symbol boundary on the exact Tc timeline.");
                end
                sourceIndex = mod(startReferenceIndex, ...
                    numel(referenceFlat)) + 1;
                activeFlat(index + 1) = referenceFlat(sourceIndex);
            end
        end

        function pattern = normalizePattern(raw, label, referenceNumerology)
            symbolsPerSlot = double(referenceNumerology.SymbolsPerSlot);
            aliases = struct( ...
                "PeriodicityMilliseconds", {{ ...
                    "PeriodicityMilliseconds", "Periodicity_ms", ...
                    "dl_UL_TransmissionPeriodicity", ...
                    "dl-UL-TransmissionPeriodicity"}}, ...
                "NumDownlinkSlots", {{ ...
                    "NumDownlinkSlots", "nrofDownlinkSlots", "DLSlots"}}, ...
                "NumDownlinkSymbols", {{ ...
                    "NumDownlinkSymbols", "nrofDownlinkSymbols", "DLSymbols"}}, ...
                "NumUplinkSlots", {{ ...
                    "NumUplinkSlots", "nrofUplinkSlots", "ULSlots"}}, ...
                "NumUplinkSymbols", {{ ...
                    "NumUplinkSymbols", "nrofUplinkSymbols", "ULSymbols"}});
            names = fieldnames(aliases);
            pattern = struct();
            for i = 1:numel(names)
                canonical = names{i};
                value = sixgr.phy.frame.TDDCommonConfig.firstField( ...
                    raw, aliases.(canonical));
                if isempty(value)
                    error("sixgr:phy:frame:MissingTDDCommonPatternField", ...
                        "%s.%s is required.", label, canonical);
                end
                if strcmp(canonical, "PeriodicityMilliseconds")
                    value = sixgr.phy.frame.TDDCommonConfig.parsePeriodicity( ...
                        value);
                end
                validateattributes(value, {'numeric'}, ...
                    {'scalar','real','finite','nonnegative'});
                pattern.(canonical) = double(value);
            end
            countFields = ["NumDownlinkSlots","NumDownlinkSymbols", ...
                "NumUplinkSlots","NumUplinkSymbols"];
            for field = countFields
                if pattern.(field) ~= floor(pattern.(field))
                    error("sixgr:phy:frame:InvalidTDDCommonPatternCount", ...
                        "%s.%s must be an integer.", label, field);
                end
            end
            if pattern.NumDownlinkSymbols > symbolsPerSlot || ...
                    pattern.NumUplinkSymbols > symbolsPerSlot
                error("sixgr:phy:frame:TDDPatternOverbooked", ...
                    "%s partial-symbol counts exceed the slot size.", label);
            end
            periodTicks = sixgr.phy.frame.TDDCommonConfig. ...
                durationTicks(pattern.PeriodicityMilliseconds);
            pattern.NumReferenceSlots = ...
                sixgr.phy.frame.TDDCommonConfig.slotsInDuration( ...
                periodTicks, referenceNumerology, ...
                label + " periodicity");
            pattern.Name = char(label);
        end

        function flat = resolvePattern(pattern, symbolsPerSlot)
            totalSymbols = pattern.NumReferenceSlots * symbolsPerSlot;
            dlCount = pattern.NumDownlinkSlots * symbolsPerSlot + ...
                pattern.NumDownlinkSymbols;
            ulCount = pattern.NumUplinkSlots * symbolsPerSlot + ...
                pattern.NumUplinkSymbols;
            if dlCount + ulCount > totalSymbols
                error("sixgr:phy:frame:TDDPatternOverbooked", ...
                    "Common TDD pattern requests %d DL plus %d UL symbols " + ...
                    "inside a %d-symbol period.", dlCount, ulCount, totalSymbols);
            end
            flat = repmat('F', 1, totalSymbols);
            flat(1:dlCount) = 'D';
            if ulCount > 0
                flat((end - ulCount + 1):end) = 'U';
            end
        end

        function value = firstField(s, names)
            value = [];
            if isempty(s)
                return;
            end
            fields = fieldnames(s);
            for i = 1:numel(names)
                index = find(strcmpi(fields, names{i}), 1);
                if ~isempty(index)
                    value = s.(fields{index});
                    return;
                end
            end
        end

        function value = parsePeriodicity(raw)
            if isnumeric(raw)
                value = raw;
            else
                token = lower(strtrim(string(raw)));
                token = erase(token, ["dl-ul-transmissionperiodicity", ...
                    "periodicity", "_", "-"]);
                token = erase(token, "ms");
                token = replace(token, "p", ".");
                value = str2double(token);
            end
            allowed = [0.5 0.625 1 1.25 2 2.5 3 4 5 10];
            if ~(isnumeric(value) && isscalar(value) && isfinite(value) && ...
                    any(abs(double(value) - allowed) < 1e-12))
                error("sixgr:phy:frame:UnsupportedTDDPeriodicity", ...
                    "TDD periodicity must be one of %s ms.", mat2str(allowed));
            end
            value = double(value);
        end
    end

    methods (Access = private)
        function obj = TDDCommonConfig
        end
    end
end
