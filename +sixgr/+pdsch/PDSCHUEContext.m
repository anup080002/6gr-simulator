classdef PDSCHUEContext
    %PDSCHUEContext Immutable UE/RRC/BWP state used to validate assignments.

    properties (SetAccess = immutable)
        Data (1,1) struct
        ContextDigest (1,1) string
    end

    methods
        function obj = PDSCHUEContext(data)
            arguments
                data (1,1) struct
            end
            required = [ ...
                "UEId","ServingCellId","SchedulingCellId","CCId","BWPId", ...
                "ConfigurationEpoch","ActiveBWPContextPresent","EpochCurrent", ...
                "ServingCellActive","MCSContextSupported","TCIStateActive", ...
                "UECapability1024QAM","RRCEnabled1024QAM", ...
                "DeploymentAllows1024QAM","FrequencyRange", ...
                "OperatingBand","DeploymentClass", ...
                "FrequencyRangeAllows1024QAM","BandAllows1024QAM"];
            missing = required(~isfield(data, required));
            if ~isempty(missing)
                error("sixgr:pdsch:IncompleteUEContext", ...
                    "PDSCH UE context is missing: %s.", ...
                    strjoin(cellstr(missing), ", "));
            end
            obj.Data = orderfields(data);
            bytes = uint8(unicode2native(jsonencode(obj.Data), "UTF-8"));
            obj.ContextDigest = string(sixgr.util.sha256Hex(bytes));
        end

        function data = toStruct(obj)
            data = obj.Data;
        end
    end
end
