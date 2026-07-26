classdef L1MeasurementFilter
    %L1MEASUREMENTFILTER Explicit receiver-policy averaging over observed REs.

    methods (Static)
        function value = apply(samples,windowLength)
            samples = double(samples(:));
            if isempty(samples) || any(~isfinite(samples)) || ...
                    ~(isscalar(windowLength)&&isfinite(windowLength)&& ...
                    windowLength>=1&&windowLength==floor(windowLength))
                error("RSLA:InvalidMeasurementFilter", ...
                    "L1 filtering requires finite samples and integer window length.");
            end
            value = movmean(samples,[windowLength-1 0]);
        end
    end
end
