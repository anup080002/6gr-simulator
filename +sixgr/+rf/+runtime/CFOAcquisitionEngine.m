classdef CFOAcquisitionEngine
%CFOACQUISITIONENGINE Non-oracle CFO estimation from complex samples.

    methods(Static)
        function estimate = estimateTone(samples, sampleRateHz, varargin)
            p = inputParser;
            p.addParameter("AmbiguityLimitHz", double(sampleRateHz)/2);
            p.addParameter("MinimumPower", 1e-12);
            p.parse(varargin{:});
            x = double(samples(:));
            if numel(x) < 2 || any(~isfinite(x)) || ...
                    mean(abs(x).^2) <= double(p.Results.MinimumPower)
                error("RF:CFOAcquisitionFailed", ...
                    "No finite signal energy is available for CFO acquisition.");
            end
            phaseProduct = sum(conj(x(1:end-1)) .* x(2:end));
            if abs(phaseProduct) <= eps
                error("RF:CFOAcquisitionFailed", ...
                    "CFO phase-increment likelihood is degenerate.");
            end
            estimatedHz = angle(phaseProduct) * double(sampleRateHz) / (2*pi);
            limit = double(p.Results.AmbiguityLimitHz);
            if ~(isfinite(limit) && limit > 0) || abs(estimatedHz) >= limit
                error("RF:CFOAmbiguityUnresolved", ...
                    "The CFO estimate is outside the declared unambiguous range.");
            end
            estimate = struct( ...
                "EstimatedIntegerCFO_Hz", 0, ...
                "EstimatedFractionalCFO_Hz", estimatedHz, ...
                "EstimatedCFO_Hz", estimatedHz, ...
                "Likelihood", abs(phaseProduct), ...
                "FalseLock", false, ...
                "Source", "sample_phase_increment_non_oracle");
        end
    end
end
