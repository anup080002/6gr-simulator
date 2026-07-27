classdef TimingAdvanceController < handle
    %TIMINGADVANCECONTROLLER Owns independent timing-advance groups.
    properties (Access=private)
        Groups
    end
    methods
        function obj=TimingAdvanceController(tagIDs)
            obj.Groups=containers.Map("KeyType","double","ValueType","any");
            for tagID=double(tagIDs(:).')
                obj.Groups(tagID)=sixgr.l2.mac.TimingAdvanceGroupState(tagID);
            end
        end
        function group=get(obj,tagID)
            if ~isKey(obj.Groups,double(tagID))
                error("sixgr:mac:UnknownTAG","TAG %d is not configured.",tagID);
            end
            group=obj.Groups(double(tagID));
        end
        function allowed=isULAllowed(obj,tagID,currentSlot)
            group=obj.get(tagID); group.tick(currentSlot); allowed=group.ULAllowed;
        end
    end
end
