classdef MeasurementStateStore < handle
    %MEASUREMENTSTATESTORE Keyed observed-measurement state.

    properties (Access=private)
        Values
    end

    methods
        function obj = MeasurementStateStore()
            obj.Values = struct([]);
        end

        function put(obj,measurement)
            if ~isstruct(measurement) || ~isfield(measurement,"Valid") || ...
                    ~logical(measurement.Valid)
                error("RSLA:MissingMeasuredInput", ...
                    "Only valid observed measurement state may be installed.");
            end
            obj.Values(end+1) = measurement;
        end

        function [measurement,validity] = newest(obj,consumer)
            candidates = obj.Values;
            valid = false(1,numel(candidates));
            results = cell(1,numel(candidates));
            for index = 1:numel(candidates)
                try
                    results{index} = sixgr.phy.rsla.MeasurementValidityChecker.validate( ...
                        candidates(index),consumer);
                    valid(index) = true;
                catch
                    valid(index) = false;
                end
            end
            candidates = candidates(valid);
            results = results(valid);
            if isempty(candidates)
                error("RSLA:MissingMeasuredInput", ...
                    "No complete-key, finite-age observed measurement is available.");
            end
            [~,order] = max([candidates.ProducerSlot]);
            measurement = candidates(order);
            validity = results{order};
        end
    end
end
