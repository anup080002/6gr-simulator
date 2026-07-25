classdef PDSCHSPSContext
    %PDSCHSPSContext Immutable activated SPS state and exact occasion truth.

    properties (SetAccess = immutable)
        Data (1,1) struct
        ContextDigest (1,1) string
    end

    methods
        function obj = PDSCHSPSContext(data)
            arguments
                data (1,1) struct
            end
            required = [ ...
                "ConfigurationPresent","ConfigId","ConfigurationEpoch", ...
                "ActivationDCIId","ActivationDCIFormat", ...
                "ActivationDCICRCPass","ActivationDCIRNTIMatch", ...
                "Activated","Released","OccasionMatch","OccasionIndex", ...
                "Assignment"];
            missing = required(~isfield(data, required));
            if ~isempty(missing)
                error("sixgr:pdsch:IncompleteSPSContext", ...
                    "PDSCH SPS context is missing: %s.", ...
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
