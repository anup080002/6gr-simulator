classdef PUCCHRepetitionPlan
    %PUCCHREPETITIONPLAN Immutable configured repetition slots.

    properties (SetAccess=private)
        Slots
        Count
        Digest
    end

    methods
        function obj = PUCCHRepetitionPlan(firstSlot,count)
            sixgr.phy.pucch.PUCCHUtil.assertInteger(count,1,64, ...
                "sixgr:phy:pucch:InvalidHopping","RepetitionCount");
            obj.Slots = firstSlot + (0:count-1);
            obj.Count = count;
            obj.Digest = sixgr.phy.pucch.PUCCHUtil.hash(obj.Slots);
        end
    end
end
