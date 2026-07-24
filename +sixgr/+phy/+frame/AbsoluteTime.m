classdef AbsoluteTime
    %ABSOLUTETIME Exact zero-based NR frame/slot/symbol time.
    %
    % Time is stored in the 38.211 basic time unit Tc. One 10 ms radio
    % frame contains 19,660,800 Tc ticks. The normal-CP symbol lengths
    % include the extra 16*kappa Tc term at each 0.5 ms boundary; extended
    % CP at mu=2 is represented by its exact, uniform 40,960 Tc length.
    % Consequently this class represents physical CP-OFDM boundaries, not
    % an equal subdivision of a slot, and never accumulates floating-point
    % slot or symbol rounding.

    properties (SetAccess = private)
        Ticks (1,1) int64 = int64(0)
    end

    properties (Constant)
        TicksPerFrame (1,1) int64 = int64(19660800)
        TicksPerSecond (1,1) int64 = int64(1966080000)
        FrameDurationSeconds (1,1) double = 0.010
        IndexConvention (1,1) string = "zero_based"
    end

    methods
        function obj = AbsoluteTime(ticks)
            if nargin == 0
                return;
            end
            if isa(ticks, "sixgr.phy.frame.AbsoluteTime")
                obj.Ticks = ticks.Ticks;
                return;
            end
            if ~(isnumeric(ticks) && isreal(ticks) && isscalar(ticks) && ...
                    isfinite(double(ticks)) && double(ticks) >= 0 && ...
                    double(ticks) == fix(double(ticks)) && ...
                    double(ticks) <= double(intmax("int64")))
                error("sixgr:phy:frame:InvalidAbsoluteTime", ...
                    "Absolute time ticks must be a nonnegative int64-range integer scalar.");
            end
            obj.Ticks = int64(ticks);
        end

        function value = tickValue(obj)
            value = obj.Ticks;
        end

        function value = seconds(obj)
            % Display conversion only; timing decisions must use Ticks.
            value = double(obj.Ticks) / double(obj.TicksPerSecond);
        end

        function value = milliseconds(obj)
            value = 1e3 * obj.seconds();
        end

        function out = plusTicks(obj, deltaTicks)
            delta = sixgr.phy.frame.AbsoluteTime.requireInteger( ...
                deltaTicks, "deltaTicks", true);
            if delta >= 0
                overflow = obj.Ticks > intmax("int64") - delta;
            elseif delta == intmin("int64")
                overflow = true;
            else
                overflow = obj.Ticks < -delta;
            end
            if overflow
                error("sixgr:phy:frame:AbsoluteTimeOverflow", ...
                    "Absolute-time tick addition is outside the nonnegative int64 range.");
            end
            out = sixgr.phy.frame.AbsoluteTime(obj.Ticks + delta);
        end

        function out = plusSlots(obj, numberOfSlots, numerology)
            count = sixgr.phy.frame.AbsoluteTime.requireInteger( ...
                numberOfSlots, "numberOfSlots", true);
            spec = sixgr.phy.frame.AbsoluteTime.resolveNumerology(numerology);
            [frame, slot, symbol, aligned] = obj.toNumerology(spec);
            if ~aligned
                error("sixgr:phy:frame:UnalignedNumerologyBoundary", ...
                    "plusSlots requires an exact symbol boundary.");
            end
            absoluteSlot = sixgr.phy.frame.AbsoluteTime.safeAdd( ...
                sixgr.phy.frame.AbsoluteTime.safeMultiply( ...
                frame, int64(spec.SlotsPerFrame)), slot);
            targetSlot = sixgr.phy.frame.AbsoluteTime.safeAdd( ...
                absoluteSlot, count);
            if targetSlot < 0
                error("sixgr:phy:frame:AbsoluteTimeUnderflow", ...
                    "Slot addition precedes the absolute-time origin.");
            end
            out = sixgr.phy.frame.AbsoluteTime.fromAbsoluteSlotSymbol( ...
                targetSlot, symbol, spec);
        end

        function out = plusSymbols(obj, numberOfSymbols, numerology)
            %PLSYMBOLS Move by exact physical CP-OFDM symbol boundaries.
            count = sixgr.phy.frame.AbsoluteTime.requireInteger( ...
                numberOfSymbols, "numberOfSymbols", true);
            spec = sixgr.phy.frame.AbsoluteTime.resolveNumerology(numerology);
            [frame, slot, symbol, aligned] = obj.toNumerology(spec);
            if ~aligned
                error("sixgr:phy:frame:UnalignedNumerologyBoundary", ...
                    "plusSymbols requires an exact symbol boundary.");
            end
            symbolsPerFrame = int64(spec.SymbolsPerSlot * ...
                spec.SlotsPerFrame);
            withinFrameSymbol = int64(slot) * ...
                int64(spec.SymbolsPerSlot) + int64(symbol);
            absoluteSymbol = sixgr.phy.frame.AbsoluteTime.safeAdd( ...
                sixgr.phy.frame.AbsoluteTime.safeMultiply( ...
                frame, symbolsPerFrame), withinFrameSymbol);
            targetSymbol = sixgr.phy.frame.AbsoluteTime.safeAdd( ...
                absoluteSymbol, count);
            if targetSymbol < 0
                error("sixgr:phy:frame:AbsoluteTimeUnderflow", ...
                    "Symbol addition precedes the absolute-time origin.");
            end
            targetFrame = idivide(targetSymbol, symbolsPerFrame, "floor");
            targetWithinFrame = rem(targetSymbol, symbolsPerFrame);
            targetSlot = idivide(targetWithinFrame, ...
                int64(spec.SymbolsPerSlot), "floor");
            targetSymbolInSlot = rem(targetWithinFrame, ...
                int64(spec.SymbolsPerSlot));
            out = sixgr.phy.frame.AbsoluteTime.fromFrameSlotSymbol( ...
                targetFrame, targetSlot, targetSymbolInSlot, spec);
        end

        function ticks = durationTicks(obj, numberOfSymbols, numerology)
            %DURATIONTICKS Exact elapsed ticks for symbols starting at obj.
            target = obj.plusSymbols(numberOfSymbols, numerology);
            ticks = obj.ticksUntil(target);
        end

        function delta = ticksUntil(obj, other)
            other = sixgr.phy.frame.AbsoluteTime.requireTime(other, "other");
            delta = other.Ticks - obj.Ticks;
        end

        function [frame, slot, symbol, aligned] = toNumerology(obj, numerology)
            %TONUMEROLOGY Convert to zero-based indices without rounding.
            spec = sixgr.phy.frame.AbsoluteTime.resolveNumerology(numerology);
            frame = idivide(obj.Ticks, obj.TicksPerFrame, "floor");
            withinFrame = rem(obj.Ticks, obj.TicksPerFrame);
            globalSymbol = find(spec.SymbolStartTicks <= withinFrame, ...
                1, "last") - 1;
            boundary = spec.SymbolStartTicks(globalSymbol + 1);
            aligned = withinFrame == boundary;
            slot = idivide(int64(globalSymbol), ...
                int64(spec.SymbolsPerSlot), "floor");
            symbol = rem(int64(globalSymbol), int64(spec.SymbolsPerSlot));
            if nargout < 4 && ~aligned
                error("sixgr:phy:frame:UnalignedNumerologyBoundary", ...
                    "Absolute tick %d is not a symbol boundary for mu=%d, " + ...
                    "%s CP. Request the fourth output to inspect alignment.", ...
                    obj.Ticks, spec.Mu, spec.CyclicPrefix);
            end
        end

        function [slotStart, frame, slot] = floorToSlot(obj, numerology)
            spec = sixgr.phy.frame.AbsoluteTime.resolveNumerology(numerology);
            frame = idivide(obj.Ticks, obj.TicksPerFrame, "floor");
            withinFrame = rem(obj.Ticks, obj.TicksPerFrame);
            slot = find(spec.SlotStartTicks <= withinFrame, ...
                1, "last") - 1;
            slot = int64(slot);
            tick = sixgr.phy.frame.AbsoluteTime.safeMultiply( ...
                frame, obj.TicksPerFrame) + ...
                spec.SlotStartTicks(double(slot) + 1);
            slotStart = sixgr.phy.frame.AbsoluteTime(tick);
        end

        function tf = eq(a, b)
            [a, b] = sixgr.phy.frame.AbsoluteTime.requirePair(a, b);
            tf = a.Ticks == b.Ticks;
        end

        function tf = ne(a, b)
            tf = ~(a == b);
        end

        function tf = lt(a, b)
            [a, b] = sixgr.phy.frame.AbsoluteTime.requirePair(a, b);
            tf = a.Ticks < b.Ticks;
        end

        function tf = le(a, b)
            tf = (a < b) || (a == b);
        end

        function tf = gt(a, b)
            tf = ~(a <= b);
        end

        function tf = ge(a, b)
            tf = ~(a < b);
        end

        function value = char(obj)
            value = char(sprintf("tick:%d", obj.Ticks));
        end

        function value = string(obj)
            value = "tick:" + string(obj.Ticks);
        end

        function output = toStruct(obj)
            output = struct( ...
                "Ticks", obj.Ticks, ...
                "TicksPerFrame", obj.TicksPerFrame, ...
                "TicksPerSecond", obj.TicksPerSecond, ...
                "TimeSecondsDisplay", obj.seconds(), ...
                "IndexConvention", obj.IndexConvention);
        end
    end

    methods (Static)
        function obj = fromTicks(ticks)
            obj = sixgr.phy.frame.AbsoluteTime(ticks);
        end

        function obj = fromFrameSlotSymbol(frame, slot, symbol, numerology)
            spec = sixgr.phy.frame.AbsoluteTime.resolveNumerology(numerology);
            frame = sixgr.phy.frame.AbsoluteTime.requireInteger( ...
                frame, "frame", false);
            slot = sixgr.phy.frame.AbsoluteTime.requireInteger( ...
                slot, "slot", false);
            symbol = sixgr.phy.frame.AbsoluteTime.requireInteger( ...
                symbol, "symbol", false);
            if slot >= spec.SlotsPerFrame
                error("sixgr:phy:frame:InvalidSlotIndex", ...
                    "Zero-based slot index %d is outside [0,%d] for " + ...
                    "mu=%d, %s CP.", ...
                    slot, spec.SlotsPerFrame - 1, spec.Mu, spec.CyclicPrefix);
            end
            if symbol >= spec.SymbolsPerSlot
                error("sixgr:phy:frame:InvalidSymbolIndex", ...
                    "Zero-based symbol index %d is outside [0,%d] for " + ...
                    "mu=%d, %s CP.", ...
                    symbol, spec.SymbolsPerSlot - 1, spec.Mu, spec.CyclicPrefix);
            end
            globalSymbol = double(slot) * spec.SymbolsPerSlot + ...
                double(symbol);
            offset = spec.SymbolStartTicks(globalSymbol + 1);
            maxFrame = idivide(intmax("int64") - offset, ...
                sixgr.phy.frame.AbsoluteTime.TicksPerFrame, "floor");
            if frame > maxFrame
                error("sixgr:phy:frame:AbsoluteTimeOverflow", ...
                    "Frame index %d exceeds the exact int64 timeline range.", frame);
            end
            tick = sixgr.phy.frame.AbsoluteTime.safeMultiply( ...
                frame, sixgr.phy.frame.AbsoluteTime.TicksPerFrame) + ...
                offset;
            obj = sixgr.phy.frame.AbsoluteTime(tick);

        end

        function obj = fromAbsoluteSlotSymbol(absoluteSlot, symbol, numerology)
            spec = sixgr.phy.frame.AbsoluteTime.resolveNumerology(numerology);
            absoluteSlot = sixgr.phy.frame.AbsoluteTime.requireInteger( ...
                absoluteSlot, "absoluteSlot", false);
            slotsPerFrame = int64(spec.SlotsPerFrame);
            frame = idivide(absoluteSlot, slotsPerFrame, "floor");
            slot = rem(absoluteSlot, slotsPerFrame);
            obj = sixgr.phy.frame.AbsoluteTime.fromFrameSlotSymbol( ...
                frame, slot, symbol, spec);
        end

        function spec = resolveNumerology(input)
            %RESOLVENUMEROLOGY Normalize a resolved catalog object or BWP.
            if isa(input, "sixgr.phy.frame.BWPConfig")
                spec = struct( ...
                    "Mu", double(input.Mu), ...
                    "SCSKHz", double(input.SCSKHz), ...
                    "CyclicPrefix", string(input.CyclicPrefix), ...
                    "SymbolsPerSlot", double(input.SymbolsPerSlot), ...
                    "SlotsPerFrame", double(input.SlotsPerFrame));
            elseif isstruct(input)
                spec = struct();
                spec.Mu = sixgr.phy.frame.AbsoluteTime.firstField( ...
                    input, ["Mu", "mu"], NaN);
                spec.SCSKHz = sixgr.phy.frame.AbsoluteTime.firstField( ...
                    input, ["SCSKHz", "scsKHz", "scs_khz", ...
                    "SubcarrierSpacingKHz", "SubcarrierSpacing"], NaN);
                spec.CyclicPrefix = string( ...
                    sixgr.phy.frame.AbsoluteTime.firstField(input, ...
                    ["CyclicPrefix", "cyclicPrefix", "cp_type"], "normal"));
                spec.SymbolsPerSlot = sixgr.phy.frame.AbsoluteTime.firstField( ...
                    input, ["SymbolsPerSlot", "symbolsPerSlot", ...
                    "symbols_per_slot"], NaN);
                spec.SlotsPerFrame = sixgr.phy.frame.AbsoluteTime.firstField( ...
                    input, ["SlotsPerFrame", "slotsPerFrame", ...
                    "slots_per_frame"], NaN);
            elseif isnumeric(input) && isreal(input) && isscalar(input) && ...
                    isfinite(double(input))
                value = double(input);
                if value >= 0 && value <= 6 && value == fix(value)
                    scsValues = [15, 30, 60, 120, 240, 480, 960];
                    spec = struct("Mu", value, ...
                        "SCSKHz", scsValues(value + 1), ...
                        "CyclicPrefix", "normal", "SymbolsPerSlot", NaN, ...
                        "SlotsPerFrame", NaN);
                else
                    spec = struct("Mu", NaN, "SCSKHz", value, ...
                        "CyclicPrefix", "normal", "SymbolsPerSlot", NaN, ...
                        "SlotsPerFrame", NaN);
                end
            else
                error("sixgr:phy:frame:UnsupportedNumerology", ...
                    "Numerology must be a resolved struct, BWPConfig, mu " + ...
                    "integer, or supported SCS value.");
            end

            cp = lower(strrep(string(spec.CyclicPrefix), "-", "_"));
            if cp == "extended_cp"
                cp = "extended";
            elseif cp == "normal_cp"
                cp = "normal";
            end
            resolved = sixgr.phy.frame.NumerologyCatalog.resolve( ...
                spec.SCSKHz, cp, "generic_waveform_test", "");
            if isfinite(double(spec.Mu)) && ...
                    double(spec.Mu) ~= double(resolved.Mu)
                error("sixgr:phy:frame:NumerologySCSMismatch", ...
                    "Configured mu=%d conflicts with the catalog-resolved " + ...
                    "mu=%d for %g kHz SCS.", ...
                    spec.Mu, resolved.Mu, spec.SCSKHz);
            end
            expectedSymbols = double(resolved.SymbolsPerSlot);
            expectedSlots = double(resolved.SlotsPerFrame);
            if ~(isscalar(spec.SymbolsPerSlot) && ...
                    isfinite(double(spec.SymbolsPerSlot)))
                spec.SymbolsPerSlot = expectedSymbols;
            elseif double(spec.SymbolsPerSlot) ~= expectedSymbols
                error("sixgr:phy:frame:NumerologySymbolCountMismatch", ...
                    "%s CP at mu=%d requires %d symbols per slot.", ...
                    string(resolved.CyclicPrefix), resolved.Mu, expectedSymbols);
            end
            if ~(isscalar(spec.SlotsPerFrame) && ...
                    isfinite(double(spec.SlotsPerFrame)))
                spec.SlotsPerFrame = expectedSlots;
            elseif double(spec.SlotsPerFrame) ~= expectedSlots
                error("sixgr:phy:frame:NumerologySlotCountMismatch", ...
                    "mu=%d requires %d slots per 10 ms frame.", ...
                    resolved.Mu, expectedSlots);
            end

            spec.Mu = double(resolved.Mu);
            spec.SCSKHz = double(resolved.SubcarrierSpacingKHz);
            spec.CyclicPrefix = string(resolved.CyclicPrefix);
            spec.SymbolsPerSlot = double(expectedSymbols);
            spec.SlotsPerFrame = double(expectedSlots);
            [symbolLengths, symbolStarts, slotStarts] = ...
                sixgr.phy.frame.AbsoluteTime.physicalBoundaries( ...
                spec.Mu, spec.CyclicPrefix, expectedSymbols, expectedSlots);
            spec.SymbolLengthsTicks = symbolLengths;
            spec.SymbolStartTicks = symbolStarts;
            spec.SlotStartTicks = slotStarts;
            spec.TicksPerSlot = idivide( ...
                sixgr.phy.frame.AbsoluteTime.TicksPerFrame, ...
                int64(expectedSlots), "floor");
            % Compatibility metadata only. Normal-CP symbols are not
            % uniform, so active timing code must consume the vectors above.
            spec.TicksPerSymbol = min(symbolLengths);
            spec.SymbolTicksUniform = all(symbolLengths == symbolLengths(1));
            spec.IndexConvention = "zero_based";
        end
    end

    methods (Static, Access = private)
        function value = firstField(input, candidates, defaultValue)
            value = defaultValue;
            names = string(fieldnames(input));
            for candidate = string(candidates(:)).'
                index = find(strcmpi(names, candidate), 1);
                if ~isempty(index)
                    value = input.(char(names(index)));
                    return;
                end
            end
        end

        function value = requireInteger(input, label, allowNegative)
            if ~(isnumeric(input) && isreal(input) && isscalar(input) && ...
                    isfinite(double(input)) && double(input) == fix(double(input)))
                error("sixgr:phy:frame:InvalidIntegerTimeInput", ...
                    "%s must be a finite integer scalar.", label);
            end
            if ~allowNegative && double(input) < 0
                error("sixgr:phy:frame:InvalidIntegerTimeInput", ...
                    "%s must be nonnegative.", label);
            end
            if abs(double(input)) > double(intmax("int64"))
                error("sixgr:phy:frame:InvalidIntegerTimeInput", ...
                    "%s is outside the int64 range.", label);
            end
            value = int64(input);
        end

        function value = requireTime(input, label)
            if ~isa(input, "sixgr.phy.frame.AbsoluteTime") || ~isscalar(input)
                error("sixgr:phy:frame:InvalidAbsoluteTime", ...
                    "%s must be a scalar sixgr.phy.frame.AbsoluteTime.", label);
            end
            value = input;
        end

        function [a, b] = requirePair(a, b)
            a = sixgr.phy.frame.AbsoluteTime.requireTime(a, "left operand");
            b = sixgr.phy.frame.AbsoluteTime.requireTime(b, "right operand");
        end

        function value = safeMultiply(a, b)
            a = int64(a);
            b = int64(b);
            if a == 0 || b == 0
                value = int64(0);
                return;
            end
            if a == intmin("int64") || b == intmin("int64")
                error("sixgr:phy:frame:AbsoluteTimeOverflow", ...
                    "Absolute-time multiplication exceeds the int64 range.");
            end
            magnitudeA = abs(a);
            magnitudeB = abs(b);
            if magnitudeA > idivide(intmax("int64"), magnitudeB, "floor")
                error("sixgr:phy:frame:AbsoluteTimeOverflow", ...
                    "Absolute-time multiplication exceeds the int64 range.");
            end
            value = a * b;
        end

        function value = safeAdd(a, b)
            a = int64(a);
            b = int64(b);
            if (b > 0 && a > intmax("int64") - b) || ...
                    (b < 0 && a < intmin("int64") - b)
                error("sixgr:phy:frame:AbsoluteTimeOverflow", ...
                    "Absolute-time integer addition exceeds the int64 range.");
            end
            value = a + b;
        end

        function [lengths, starts, slotStarts] = physicalBoundaries( ...
                mu, cyclicPrefix, symbolsPerSlot, slotsPerFrame)
            symbolCount = symbolsPerSlot * slotsPerFrame;
            if cyclicPrefix == "extended"
                if mu ~= 2 || symbolsPerSlot ~= 12
                    error("sixgr:phy:frame:UnsupportedNumerology", ...
                        "Extended CP physical timing is defined only for mu=2.");
                end
                lengths = repmat(int64(40960), 1, symbolCount);
            else
                scale = int64(2 ^ mu);
                if rem(int64(140288), scale) ~= 0
                    error("sixgr:phy:frame:InternalPhysicalTimingMismatch", ...
                        "Normal-CP base symbol length is not integral at mu=%d.", ...
                        mu);
                end
                shortLength = idivide(int64(140288), scale, "floor");
                lengths = repmat(shortLength, 1, symbolCount);
                symbolsPerSubframe = 14 * 2 ^ mu;
                for subframe = 0:9
                    first = subframe * symbolsPerSubframe + 1;
                    second = first + 7 * 2 ^ mu;
                    lengths([first, second]) = ...
                        lengths([first, second]) + int64(1024);
                end
            end
            if int64(sum(double(lengths))) ~= ...
                    sixgr.phy.frame.AbsoluteTime.TicksPerFrame
                error("sixgr:phy:frame:InternalPhysicalTimingMismatch", ...
                    "Resolved CP-OFDM symbols do not fill one 10 ms frame.");
            end
            starts = zeros(1, symbolCount, "int64");
            if symbolCount > 1
                starts(2:end) = int64(cumsum( ...
                    double(lengths(1:end - 1))));
            end
            slotStarts = starts(1:symbolsPerSlot:end);
        end
    end
end
