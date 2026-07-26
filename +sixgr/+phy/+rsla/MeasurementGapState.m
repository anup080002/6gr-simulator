classdef MeasurementGapState
    %MEASUREMENTGAPSTATE Installed gap/resource opportunity checker.

    methods (Static)
        function result = evaluate(periodSlots,lengthSlots,offsetSlots, ...
                absoluteSlot,resourceAvailable)
            values = [periodSlots lengthSlots offsetSlots absoluteSlot];
            if any(~isfinite(values)) || periodSlots<1 || lengthSlots<1 || ...
                    lengthSlots>periodSlots || offsetSlots<0 || ...
                    offsetSlots>=periodSlots || absoluteSlot<0
                error("RSLA:MeasurementGapViolation", ...
                    "Invalid installed measurement-gap configuration.");
            end
            inGap = mod(absoluteSlot-offsetSlots,periodSlots)<lengthSlots;
            allowed = inGap && logical(resourceAvailable);
            result = struct("GapActive",inGap, ...
                "ResourceAvailable",logical(resourceAvailable), ...
                "MeasurementAllowed",allowed);
        end

        function requireAllowed(result)
            if ~result.MeasurementAllowed
                error("RSLA:MeasurementGapViolation", ...
                    "Measurement is outside its installed gap/resource opportunity.");
            end
        end
    end
end
