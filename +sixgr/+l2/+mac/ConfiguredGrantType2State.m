classdef ConfiguredGrantType2State < handle
    %CONFIGUREDGRANTTYPE2STATE DCI-activated/released configured grant.
    properties (SetAccess=private)
        State (1,1) string = "INACTIVE"
        PeriodSlots (1,1) double
        OffsetSlot (1,1) double
        AuthorityEventID (1,1) string = ""
    end
    methods
        function obj=ConfiguredGrantType2State(periodSlots,offsetSlot)
            obj.PeriodSlots=periodSlots; obj.OffsetSlot=offsetSlot;
        end
        function activate(obj,decodedDCIEventID)
            if strlength(string(decodedDCIEventID))==0
                error("sixgr:mac:DecodedGrantAuthorityRequired", ...
                    "CG Type 2 activation requires decoded DCI.");
            end
            obj.State="ACTIVE"; obj.AuthorityEventID=string(decodedDCIEventID);
        end
        function release(obj,decodedDCIEventID)
            if strlength(string(decodedDCIEventID))==0
                error("sixgr:mac:DecodedGrantAuthorityRequired", ...
                    "CG Type 2 release requires decoded DCI.");
            end
            obj.State="RELEASED"; obj.AuthorityEventID=string(decodedDCIEventID);
        end
        function tf=isOccasion(obj,slot)
            tf=obj.State=="ACTIVE" && mod(slot-obj.OffsetSlot,obj.PeriodSlots)==0;
        end
    end
end
