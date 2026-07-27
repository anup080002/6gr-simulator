classdef ConfiguredGrantType1State < handle
    %CONFIGUREDGRANTTYPE1STATE RRC-activated configured grant lifecycle.
    properties (SetAccess=private)
        State (1,1) string = "CONFIGURED"
        PeriodSlots (1,1) double
        OffsetSlot (1,1) double
    end
    methods
        function obj=ConfiguredGrantType1State(periodSlots,offsetSlot)
            obj.PeriodSlots=periodSlots; obj.OffsetSlot=offsetSlot;
        end
        function release(obj), obj.State="RELEASED"; end
        function tf=isOccasion(obj,slot)
            tf=obj.State=="CONFIGURED" && mod(slot-obj.OffsetSlot,obj.PeriodSlots)==0;
        end
    end
end
