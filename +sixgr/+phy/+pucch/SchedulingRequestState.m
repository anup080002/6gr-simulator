classdef SchedulingRequestState
    %SCHEDULINGREQUESTSTATE Exact periodic/event-triggered SR state.

    properties (SetAccess=private)
        Data
        Digest
    end

    methods
        function obj = SchedulingRequestState(data)
            required = ["SchedulingRequestID","PeriodSlots","OffsetSlots", ...
                "AbsoluteSlot","PendingPositiveSR","ProhibitTimerActive"];
            sixgr.phy.pucch.UCIReport.requireFields(data,required);
            period = double(data.PeriodSlots);
            offset = double(data.OffsetSlots);
            slot = double(data.AbsoluteSlot);
            if ~(period >= 1 && period == fix(period) && offset >= 0 && ...
                    offset < period && slot >= 0 && slot == fix(slot))
                error("sixgr:phy:pucch:MissingSRConfiguration", ...
                    "SR period/offset/slot configuration is invalid.");
            end
            data.IsOccasion = slot >= offset && mod(slot-offset,period) == 0;
            data.Transmit = data.IsOccasion && ...
                logical(data.PendingPositiveSR) && ...
                ~logical(data.ProhibitTimerActive);
            data.Value = double(data.Transmit);
            data.ResourceSource = string(localResource(data.Transmit));
            obj.Data = data;
            obj.Digest = sixgr.phy.pucch.PUCCHUtil.hash(data);
        end
    end

    methods (Static)
        function obj = fromVector(row)
            data = struct( ...
                "SchedulingRequestID",sixgr.phy.pucch.PUCCHUtil.number( ...
                row,"SchedulingRequestID"), ...
                "PeriodSlots",sixgr.phy.pucch.PUCCHUtil.number(row,"PeriodSlots"), ...
                "OffsetSlots",sixgr.phy.pucch.PUCCHUtil.number(row,"OffsetSlots"), ...
                "AbsoluteSlot",sixgr.phy.pucch.PUCCHUtil.number(row,"AbsoluteSlot"), ...
                "PendingPositiveSR",sixgr.phy.pucch.PUCCHUtil.truth( ...
                row,"PendingPositiveSR"), ...
                "ProhibitTimerActive",sixgr.phy.pucch.PUCCHUtil.truth( ...
                row,"ProhibitTimerActive"), ...
                "Priority",0,"ResourceID", ...
                sixgr.phy.pucch.PUCCHUtil.number(row,"SchedulingRequestID"));
            obj = sixgr.phy.pucch.SchedulingRequestState(data);
        end
    end
end

function value = localResource(transmit)
if transmit
    value = "SR_CONFIG_RESOURCE";
else
    value = "NONE";
end
end
