classdef AbsoluteRadioClock < handle
    %ABSOLUTERADIOCLOCK Single authoritative sample-time service.
    properties (SetAccess=immutable)
        SampleRateHz (1,1) double
        SamplesPerSymbol (1,1) double
        SymbolsPerSlot (1,1) double
        SlotsPerFrame (1,1) double
    end
    properties (SetAccess=private)
        AbsoluteSample (1,1) double = 0
    end
    methods
        function obj = AbsoluteRadioClock(sampleRate,samplesPerSymbol, ...
                symbolsPerSlot,slotsPerFrame)
            values = double([sampleRate samplesPerSymbol symbolsPerSlot slotsPerFrame]);
            if any(~isfinite(values)) || any(values <= 0) || ...
                    any(values(2:4) ~= fix(values(2:4)))
                error("sixgr:integration:ClockConfigurationInvalid", ...
                    "AbsoluteRadioClock parameters must be positive and exact.");
            end
            obj.SampleRateHz = values(1);
            obj.SamplesPerSymbol = values(2);
            obj.SymbolsPerSlot = values(3);
            obj.SlotsPerFrame = values(4);
        end
        function advanceTo(obj,sample)
            sample = double(sample);
            if ~isscalar(sample) || sample < obj.AbsoluteSample || ...
                    sample ~= fix(sample)
                error("sixgr:integration:ClockRegression", ...
                    "Absolute radio time cannot move backwards.");
            end
            obj.AbsoluteSample = sample;
        end
        function advance(obj,count)
            obj.advanceTo(obj.AbsoluteSample + double(count));
        end
        function value = view(obj,sample)
            if nargin < 2, sample = obj.AbsoluteSample; end
            absoluteSymbol = floor(double(sample)/obj.SamplesPerSymbol);
            absoluteSlot = floor(absoluteSymbol/obj.SymbolsPerSlot);
            value = struct("AbsoluteSample",double(sample), ...
                "TimeSeconds",double(sample)/obj.SampleRateHz, ...
                "AbsoluteSymbol",absoluteSymbol, ...
                "AbsoluteSlot",absoluteSlot, ...
                "Frame",floor(absoluteSlot/obj.SlotsPerFrame), ...
                "Slot",mod(absoluteSlot,obj.SlotsPerFrame), ...
                "Symbol",mod(absoluteSymbol,obj.SymbolsPerSlot));
        end
    end
end
