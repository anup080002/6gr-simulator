classdef DCOffsetAndLOLeakage
%DCOFFSETANDLOLEAKAGE Explicit carrier-leakage estimation and removal.

    methods(Static)
        function estimate = estimate(samples, idleOrNullMask, referencePlane)
            plane = sixgr.rf.runtime.RFReferencePlane.validate(referencePlane);
            mask = logical(idleOrNullMask(:));
            if isempty(samples) || numel(mask) ~= size(samples,1) || ...
                    ~any(mask) || any(~isfinite(samples(:)))
                error("RF:IQCalibrationMissing", ...
                    "Carrier-leakage estimation requires explicit idle/null samples.");
            end
            offset = mean(double(samples(mask,:)), 1);
            estimate = struct("DCOffset", offset, ...
                "CarrierLeakagePower_dB", 10*log10(max(mean(abs(offset).^2),realmin)), ...
                "ReferencePlane", plane, ...
                "Source", "measured_idle_or_null_resources");
        end

        function output = remove(samples, estimate)
            if ~isstruct(estimate) || ~isfield(estimate, "DCOffset") || ...
                    ~isfield(estimate, "Source") || ...
                    ~contains(lower(string(estimate.Source)), "measured")
                error("RF:IQCalibrationMissing", ...
                    "Carrier-leakage removal requires a measured estimate.");
            end
            output = samples - cast(reshape(estimate.DCOffset,1,[]), "like", samples);
        end
    end
end
