classdef ProtocolSpecificationProfile
    %PROTOCOLSPECIFICATIONPROFILE Pinned bounded Release-18 protocol scope.

    properties (SetAccess = immutable)
        ProfileID (1,1) string
        BoundedClaim (1,1) string
        Specifications table
    end

    methods
        function obj = ProtocolSpecificationProfile(profileID)
            arguments
                profileID (1,1) string
            end
            permitted = ["nr_rel18_connected_mode_bounded_strict", ...
                "nr_rel18_handover_bounded_strict", ...
                "protocol_system_study", "unsupported_extension"];
            if ~ismember(profileID, permitted)
                error("sixgr:protocol:UnsupportedCapability", ...
                    "Unknown protocol specification profile '%s'.", profileID);
            end
            obj.ProfileID = profileID;
            obj.BoundedClaim = "bounded_profile_not_full_stack_conformance";
            obj.Specifications = table( ...
                ["RLC";"PDCP";"SDAP";"RRC";"MAC interface";"NR overall"], ...
                ["TS 38.322";"TS 38.323";"TS 37.324"; ...
                 "TS 38.331";"TS 38.321";"TS 38.300"], ...
                ["V18.2.0";"V18.5.0";"V18.0.0"; ...
                 "V18.9.0";"V18.9.0";"V18.9.0"], ...
                'VariableNames', {'Layer','Specification','Version'});
        end
    end
end
