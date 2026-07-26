classdef CalibrationDatasetRegistry < handle
    %CALIBRATIONDATASETREGISTRY Exact-key calibration lookup without fallback.

    properties (Access=private)
        Values
    end

    methods
        function obj = CalibrationDatasetRegistry()
            obj.Values = containers.Map("KeyType","char","ValueType","any");
        end

        function register(obj,dataset)
            dataset = sixgr.phy.rsla.CQIMCSCalibrationDataset.validate(dataset);
            key = char(string(dataset.ProfileKey));
            if isKey(obj.Values,key)
                error("RSLA:InvalidCalibrationProvenance", ...
                    "Calibration profile key %s is already registered.",key);
            end
            obj.Values(key) = dataset;
        end

        function value = resolveCQI(obj,profileKey)
            key = char(string(profileKey));
            if ~isKey(obj.Values,key)
                error("RSLA:MissingCQICalibration", ...
                    "No exact CQI/MCS calibration exists for profile %s.",key);
            end
            value = obj.Values(key);
        end

        function value = resolveEffectiveSINR(obj,profileKey,method)
            value = obj.resolveCQI(profileKey);
            if ~isfield(value,"EffectiveSINRMethod") || ...
                    upper(string(value.EffectiveSINRMethod))~=upper(string(method)) || ...
                    ~isfield(value,"EffectiveSINRParameter")
                error("RSLA:MissingEffectiveSINRCalibration", ...
                    "No exact %s calibration exists for profile %s.", ...
                    string(method),string(profileKey));
            end
        end
    end
end
