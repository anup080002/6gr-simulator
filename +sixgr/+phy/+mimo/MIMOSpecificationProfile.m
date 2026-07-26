classdef MIMOSpecificationProfile
    %MIMOSPECIFICATIONPROFILE Release-pinned normative baseline for Phase 07.

    properties (SetAccess = immutable)
        ProfileID (1,1) string
        TS38211 (1,1) string
        TS38212 (1,1) string
        TS38213 (1,1) string
        TS38214 (1,1) string
        TS38215 (1,1) string
        TS38331 (1,1) string
        TR38901 (1,1) string
    end

    methods
        function obj = MIMOSpecificationProfile()
            obj.ProfileID = "NR_REL18_MIMO_CSI_BEAMFORMING_STRICT";
            obj.TS38211 = "V18.8.0";
            obj.TS38212 = "V18.8.0";
            obj.TS38213 = "V18.8.0";
            obj.TS38214 = "V18.9.0";
            obj.TS38215 = "V18.x";
            obj.TS38331 = "V18.9.0";
            obj.TR38901 = "V18.0.0";
        end

        function value = asStruct(obj)
            value = struct( ...
                "ProfileID", obj.ProfileID, ...
                "TS38211", obj.TS38211, ...
                "TS38212", obj.TS38212, ...
                "TS38213", obj.TS38213, ...
                "TS38214", obj.TS38214, ...
                "TS38215", obj.TS38215, ...
                "TS38331", obj.TS38331, ...
                "TR38901", obj.TR38901);
        end
    end
end
