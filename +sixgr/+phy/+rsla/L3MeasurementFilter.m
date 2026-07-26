classdef L3MeasurementFilter
    %L3MEASUREMENTFILTER RRC k-coefficient recurrence.

    methods (Static)
        function result = apply(samples,k)
            samples = double(samples(:));
            if isempty(samples) || any(~isfinite(samples)) || ...
                    ~(isscalar(k)&&isfinite(k)&&k>=0)
                error("RSLA:InvalidMeasurementFilter", ...
                    "L3 filtering requires finite samples and k >= 0.");
            end
            alpha = 2^(-double(k)/4);
            filtered = zeros(size(samples));
            filtered(1) = samples(1);
            for index = 2:numel(samples)
                filtered(index) = (1-alpha)*filtered(index-1)+ ...
                    alpha*samples(index);
            end
            result = struct("Filtered",filtered,"Alpha",alpha, ...
                "FilterK",double(k), ...
                "Policy","receiver_policy_not_normative_constant");
        end
    end
end
