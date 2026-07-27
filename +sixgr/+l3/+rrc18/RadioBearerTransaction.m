classdef RadioBearerTransaction < handle
    %RADIOBEARERTRANSACTION Validate/prepare/commit/rollback bearer changes.

    properties (SetAccess = private)
        TransactionID (1,1) string
        ConfigurationEpoch (1,1) double
        Prepared (1,1) logical = false
        Committed (1,1) logical = false
        RolledBack (1,1) logical = false
        Configuration struct = struct()
    end

    methods
        function obj = RadioBearerTransaction(id, epoch)
            arguments
                id (1,1) string
                epoch (1,1) double {mustBeInteger,mustBePositive}
            end
            obj.TransactionID = id;
            obj.ConfigurationEpoch = epoch;
        end

        function prepare(obj, config)
            arguments
                obj
                config struct
            end
            if obj.Prepared || obj.Committed
                error("sixgr:rrc:BearerCommitFailed", ...
                    "Bearer transaction was already prepared or committed.");
            end
            sixgr.l3.rrc18.RadioBearerTransaction.validate(config);
            obj.Configuration = config;
            obj.Prepared = true;
        end

        function result = commit(obj, committers)
            arguments
                obj
                committers cell
            end
            if ~obj.Prepared || obj.Committed
                error("sixgr:rrc:BearerCommitFailed", ...
                    "Bearer transaction is not ready to commit.");
            end
            completed = false(size(committers));
            try
                for index = 1:numel(committers)
                    committers{index}("commit", obj.Configuration, ...
                        obj.ConfigurationEpoch);
                    completed(index) = true;
                end
            catch exception
                for index = find(completed)
                    try
                        committers{index}("rollback", obj.Configuration, ...
                            obj.ConfigurationEpoch);
                    catch
                    end
                end
                obj.RolledBack = true;
                throwAsCaller(MException("sixgr:rrc:BearerCommitFailed", ...
                    "Atomic bearer commit rolled back: %s", exception.message));
            end
            obj.Committed = true;
            result = struct("RRCValidated", true, "RLCCommitted", true, ...
                "PDCPCommitted", true, "SDAPCommitted", true, ...
                "MACCommitted", true, "Atomic", true, ...
                "ConfigurationEpoch", obj.ConfigurationEpoch);
        end
    end

    methods (Static)
        function validate(config)
            required = ["Action","BearerProfile","SRBorDRB", ...
                "RLCMode","RLCSNBits","PDCPSNBits","SDAPEnabled"];
            if ~all(isfield(config, required))
                error("sixgr:rrc:ASN1ConstraintViolation", ...
                    "Radio bearer configuration is incomplete.");
            end
            action = upper(string(config.Action));
            if ~ismember(action, ["ADD","MODIFY","RELEASE"])
                error("sixgr:rrc:ASN1ConstraintViolation", ...
                    "Unsupported radio bearer action.");
            end
            bearer = upper(string(config.SRBorDRB));
            mode = upper(string(config.RLCMode));
            rlcSN = double(config.RLCSNBits);
            pdcpSN = double(config.PDCPSNBits);
            profile = upper(string(config.BearerProfile));
            valid = false;
            if profile == "SRB0_TM"
                valid = bearer == "SRB" && mode == "TM" && ...
                    rlcSN == 0 && pdcpSN == 0 && ~logical(config.SDAPEnabled);
            elseif startsWith(profile, "SRB1_") || startsWith(profile, "SRB2_")
                valid = bearer == "SRB" && mode == "AM" && ...
                    rlcSN == 12 && pdcpSN == 12 && ~logical(config.SDAPEnabled);
            elseif startsWith(profile, "DRB_")
                valid = bearer == "DRB" && ismember(mode, ["UM","AM"]) && ...
                    ((mode == "UM" && ismember(rlcSN,[6 12])) || ...
                     (mode == "AM" && ismember(rlcSN,[12 18]))) && ...
                    ismember(pdcpSN, [12 18]) && logical(config.SDAPEnabled);
            end
            if ~valid
                error("sixgr:rrc:ASN1ConstraintViolation", ...
                    "Cross-layer radio bearer tuple is invalid.");
            end
        end
    end
end
