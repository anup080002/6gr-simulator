function result = classifyMismatch(mismatch, thresholdsSigma)
%CLASSIFYMISMATCH Quantize normalized mismatch with explicit confidence.

thresholds = sort(double(thresholdsSigma(:)));
if isempty(thresholds) || any(~isfinite(thresholds) | thresholds <= 0)
    error("sixgr:ntn:resilientsync:InvalidMismatchThresholds", ...
        "Mismatch thresholds must be finite and positive.");
end
index = 1 + sum(abs(double(mismatch.Normalized)) >= thresholds);
labels = ["consistent","review","adapt","reject"];
if index > numel(labels), index = numel(labels); end
result = mismatch;
result.ClassIndex = index-1;
result.Class = labels(index);
end
