classdef SPSState < handle
    %SPSSTATE Downlink semi-persistent scheduling lifecycle.
    properties (SetAccess=private)
        State (1,1) string = "INACTIVE"
        PeriodSlots (1,1) double
        OffsetSlot (1,1) double
    end
    methods
        function obj=SPSState(periodSlots,offsetSlot)
            obj.PeriodSlots=periodSlots; obj.OffsetSlot=offsetSlot;
        end
        function activate(obj), obj.State="ACTIVE"; end
        function deactivate(obj), obj.State="INACTIVE"; end
        function tf=isOccasion(obj,slot)
            tf=obj.State=="ACTIVE" && mod(slot-obj.OffsetSlot,obj.PeriodSlots)==0;
        end
    end
end
