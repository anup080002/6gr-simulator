classdef PUCCHDetector
    %PUCCHDETECTOR Format-aware DTX and detection decision.

    methods (Static)
        function result = decide(format,metric,threshold,decoded)
            if isempty(threshold), threshold = 0.2; end
            finiteMetric = isscalar(metric) && isfinite(metric);
            if finiteMetric
                dtx = metric < threshold;
            else
                dtx = isempty(decoded);
            end
            result = struct("DTX",logical(dtx), ...
                "DetectionMetric",double(localScalar(metric)), ...
                "DetectionThreshold",double(threshold), ...
                "Detected",~logical(dtx));
        end
    end
end

function value = localScalar(input)
if isempty(input), value = NaN; else, value = double(input(1)); end
end
