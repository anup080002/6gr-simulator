function evidence = ssbDetectionEvidence(source)
%SSBDETECTIONEVIDENCE Typed measured decisions, including unsuccessful search.
% No threshold or metric is reconstructed from exception text or configured SNR.
if nargin < 1, source = struct(); end
evidence = struct('DetectionMetric',NaN,'DetectionThreshold',NaN, ...
    'DetectionHypothesisCount',NaN,'DetectionStage',"",'DetectionMetricSource',"");
for stage = ["PSS","SSS"]
    evidence.(stage+"NormalizedMetric") = NaN;
    evidence.(stage+"DetectionThreshold") = NaN;
    evidence.(stage+"DetectionHypothesisCount") = NaN;
    evidence.(stage+"DetectionMetricValid") = false;
    evidence.(stage+"DetectionDecisionAvailable") = false;
end
for name = string(fieldnames(evidence)).'
    if isfield(source,name)
        evidence.(name) = source.(name);
    end
end
end
