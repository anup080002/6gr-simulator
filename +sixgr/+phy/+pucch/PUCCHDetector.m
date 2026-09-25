classdef PUCCHDetector
    %PUCCHDETECTOR Format-aware DTX and detection decision.

    methods (Static)
        function [metric,source] = selectMetric( ...
                format,noncoherent,sequenceMetric,energyRatio,payloadBitCount)
            % Select only evidence that is defined for the executed PUCCH
            % format and payload size. nrPUCCHDecode performs normalized-
            % correlation DTX detection for formats 2--4 only for 3--11
            % UCI bits. For 12 or more bits the UCI CRC is applicable and
            % the toolbox detection metric is intentionally zero, so a
            % separately measured energy-presence metric remains necessary.
            assert(isnumeric(payloadBitCount) && isreal(payloadBitCount) && ...
                isscalar(payloadBitCount) && isfinite(payloadBitCount) && ...
                payloadBitCount>=0 && payloadBitCount==fix(payloadBitCount), ...
                'sixgr:phy:pucch:InvalidDetectorPayloadBitCount', ...
                'PUCCH detector payload bit count must be a nonnegative integer scalar.');
            if noncoherent
                metric = sequenceMetric;
                source = "toolbox_noncoherent_sequence_correlation";
                return;
            end
            shortLongFormat = format>=2 && format<=4 && ...
                payloadBitCount>=3 && payloadBitCount<=11;
            if shortLongFormat
                % This is the DTX statistic defined and executed by
                % nrPUCCHDecode for short format-2/3/4 payloads. Do not
                % replace an invalid/missing correlation with energy.
                metric = sequenceMetric;
                source = "toolbox_normalized_sequence_correlation";
                return;
            end
            if ~localFiniteScalar(energyRatio) || energyRatio<0
                metric = NaN;
                source = "invalid_energy_observation";
                return;
            end
            energyMetric = max(0,(energyRatio-1)/(energyRatio+1));
            if format<=1
                if ~localFiniteScalar(sequenceMetric)
                    metric = sequenceMetric;
                    source = "invalid_required_sequence_correlation";
                    return;
                end
                metric = min(double(sequenceMetric),double(energyMetric));
                source = "sequence_and_energy_conjunction";
            else
                metric = double(energyMetric);
                source = "normalized_excess_energy_crc_aided";
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
