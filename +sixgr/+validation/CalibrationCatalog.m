classdef CalibrationCatalog
    %CALIBRATIONCATALOG Exact calibration resolution with holdout gating.
    methods (Static)
        function out = validate(input)
            required = ["CalibrationID","Direction","ProfileID", ...
                "ChannelModel","MCS","Rank","Receiver","SCS_kHz", ...
                "Bandwidth_Hz","TargetBLER","RawDatasetSHA256", ...
                "HoldoutDatasetSHA256","TrainingDrops","HoldoutDrops", ...
                "HoldoutPredictionError","MaxAllowedHoldoutError"];
            if ~istable(input) || height(input)==0 || ...
                    any(~ismember(required,string(input.Properties.VariableNames)))
                error("sixgr:validation:SchemaMissingColumn", ...
                    "Calibration catalog is missing mandatory columns.");
            end
            if numel(unique(string(input.CalibrationID))) ~= height(input)
                error("sixgr:validation:SchemaDuplicateKey", ...
                    "CalibrationID values must be unique.");
            end
            if any(input.HoldoutPredictionError > input.MaxAllowedHoldoutError)
                error("sixgr:validation:CalibrationHoldoutFailed", ...
                    "Calibration held-out prediction error exceeds its bound.");
            end
            if any(input.TrainingDrops < 1 | input.HoldoutDrops < 1)
                error("sixgr:validation:IncompleteMandatoryPoint", ...
                    "Calibration requires nonempty training and held-out drops.");
            end
            localHashes(string(input.RawDatasetSHA256));
            localHashes(string(input.HoldoutDatasetSHA256));
            out = input;
        end
        function out = resolve(input,key)
            input = sixgr.validation.CalibrationCatalog.validate(input);
            names = ["Direction","ProfileID","ChannelModel","MCS","Rank", ...
                "Receiver","SCS_kHz","Bandwidth_Hz","TargetBLER"];
            mask = true(height(input),1);
            for name = names
                if ~isfield(key,char(name))
                    error("sixgr:validation:SchemaMissingColumn", ...
                        "Calibration key is missing %s.",name);
                end
                column = input.(char(name));
                value = key.(char(name));
                if isnumeric(column)
                    mask = mask & column == double(value);
                else
                    mask = mask & string(column) == string(value);
                end
            end
            rows = find(mask);
            if isempty(rows)
                error("sixgr:validation:CalibrationNotFound", ...
                    "No exact calibration entry matches the requested key.");
            elseif numel(rows) > 1
                error("sixgr:validation:SchemaDuplicateKey", ...
                    "Calibration key is not unique.");
            end
            out = input(rows,:);
        end
    end
end

function localHashes(values)
for value = reshape(values,1,[])
    if strlength(value) ~= 64 || ...
            isempty(regexp(char(lower(value)),"^[0-9a-f]{64}$","once"))
        error("sixgr:validation:OracleHashMismatch", ...
            "Calibration dataset hash must be a SHA-256 digest.");
    end
end
end
