classdef ControlBWPContext
    %CONTROLBWPCONTEXT Immutable control/scheduled BWP and epoch binding.

    properties (SetAccess = private)
        Data
        Digest
    end

    methods
        function obj = ControlBWPContext(data)
            required = ["ControlServingCell","ControlCarrier","ControlBWP", ...
                "ScheduledServingCell","ScheduledCarrier","ScheduledBWP", ...
                "SearchSpaceID","CORESETID","ConfigurationEpoch"];
            if ~(isstruct(data) && isscalar(data)) || ...
                    any(~isfield(data, cellstr(required)))
                error("sixgr:phy:pdcch:missing_dci_context", ...
                    "ControlBWPContext is incomplete.");
            end
            for idx = 1:numel(required)
                value = data.(required(idx));
                if ~(isnumeric(value) && isscalar(value) && isfinite(value) && ...
                        value == fix(value) && value >= 0)
                    error("sixgr:phy:pdcch:missing_dci_context", ...
                        "ControlBWPContext field %s must be a nonnegative finite integer.", ...
                        required(idx));
                end
            end
            obj.Data = orderfields(data);
            obj.Digest = string(sixgr.rrc.asn1.asn1SHA256Hex(uint8( ...
                unicode2native(jsonencode(obj.Data), "UTF-8"))));
        end
    end
end
