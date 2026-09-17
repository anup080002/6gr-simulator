classdef PUCCHDetector
    %PUCCHDETECTOR Format-aware DTX and detection decision.

    methods (Static)
        function metric = selectMetric(format,noncoherent,sequenceMetric,energyRatio)
            % Preserve the existing finite-evidence rule, never replace a
            % required invalid sequence metric with an energy-only decision.
            if noncoherent
                metric = sequenceMetric;
                return;
            end
            if ~localFiniteScalar(energyRatio) || energyRatio<0
                metric = NaN;
                return;
            end
            energyMetric = max(0,(energyRatio-1)/(energyRatio+1));
            if format<=1
                if ~localFiniteScalar(sequenceMetric)
                    metric = sequenceMetric;
                    return;
                end
                metric = min(double(sequenceMetric),double(energyMetric));
            else
                metric = double(energyMetric);
            end
        end

        function result = decide(~,metric,threshold,~)
            % Format-specific policy is resolved by the caller. Candidate
            % decoder bits cannot rescue a missing/invalid observation metric.
            assert(~isempty(threshold),'sixgr:phy:pucch:MissingDetectionThreshold', ...
                'Supply the explicitly resolved receiver threshold; no detector-local default.');
            assert(isnumeric(threshold) && isreal(threshold) && isscalar(threshold) && ...
                isfinite(threshold) && threshold>=0 && threshold<=1, ...
                'sixgr:phy:pucch:InvalidDetectionThreshold', ...
                'Detection threshold must be a finite scalar in [0,1].');
            finiteMetric = localFiniteScalar(metric);
            dtx = ~finiteMetric || metric < threshold;
            result = struct("DTX",logical(dtx), ...
                "DetectionMetric",double(localScalar(metric)), ...
                "DetectionMetricValid",logical(finiteMetric), ...
                "DetectionThreshold",double(threshold), ...
                "Detected",~logical(dtx));
        end
    end
end

function valid = localFiniteScalar(value)
valid = isnumeric(value) && isreal(value) && isscalar(value) && isfinite(value);
end

function value = localScalar(input)
% Preserve invalid scalar numeric evidence (NaN/Inf), but never promote the
% first element of a malformed vector or coerce text into a received metric.
value = NaN;
if isnumeric(input) && isreal(input) && isscalar(input), value=double(input); end
end
