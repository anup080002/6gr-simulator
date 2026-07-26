classdef BootstrapAcquisitionState < handle
    %BOOTSTRAPACQUISITIONSTATE Bounded pre-measurement link acquisition.

    properties (SetAccess=immutable)
        AcquisitionLimitSlots double
        BootstrapCQI double
        BootstrapMCS double
    end
    properties (SetAccess=private)
        MeasuredAcquired logical = false
        FirstMeasuredSlot double = NaN
    end

    methods
        function obj = BootstrapAcquisitionState(limit,cqi,mcs)
            if ~(isscalar(limit)&&isfinite(limit)&&limit>=0&&limit==floor(limit))
                error("RSLA:BootstrapExpired","Acquisition limit must be finite.");
            end
            obj.AcquisitionLimitSlots = limit;
            obj.BootstrapCQI = cqi;
            obj.BootstrapMCS = mcs;
        end

        function transition(obj,slot)
            obj.MeasuredAcquired = true;
            obj.FirstMeasuredSlot = double(slot);
        end

        function result = decide(obj,slot)
            slot = double(slot);
            if obj.MeasuredAcquired
                result = struct("DecisionSource","MEASURED_DECODED_REPORT", ...
                    "BootstrapUsed",false,"MeasuredUsed",true, ...
                    "TransitionedToMeasured",true);
            elseif slot<=obj.AcquisitionLimitSlots
                result = struct("DecisionSource","BOOTSTRAP", ...
                    "BootstrapUsed",true,"MeasuredUsed",false, ...
                    "TransitionedToMeasured",false);
            else
                error("RSLA:BootstrapExpired", ...
                    "Bootstrap acquisition expired without a valid decoded report.");
            end
        end
    end
end
