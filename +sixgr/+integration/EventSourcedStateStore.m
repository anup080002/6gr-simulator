classdef EventSourcedStateStore < handle
    %EVENTSOURCEDSTATESTORE Append-only event log with consumption evidence.
    properties (SetAccess=immutable)
        RunID (1,1) string
    end
    properties (Access=private)
        Events (:,1) cell = cell(0,1)
        ConsumedAt (:,1) double = zeros(0,1)
    end
    methods
        function obj = EventSourcedStateStore(runID)
            obj.RunID = string(runID);
        end
        function append(obj,event)
            if event.RunID ~= obj.RunID
                error("sixgr:integration:InvalidEvent", ...
                    "Event RunID does not match the state store.");
            end
            if any(cellfun(@(x)x.EventID == event.EventID,obj.Events))
                error("sixgr:integration:TaskConflict", ...
                    "Duplicate event identity %s.",event.EventID);
            end
            obj.Events{end+1,1} = event;
            obj.ConsumedAt(end+1,1) = NaN;
        end
        function payload = consume(obj,eventID,now,epoch)
            ids = string(cellfun(@(x)x.EventID,obj.Events,"UniformOutput",false));
            index = find(ids == string(eventID),1);
            if isempty(index)
                error("sixgr:integration:InvalidEvent","Unknown event %s.",eventID);
            end
            event = obj.Events{index};
            event.assertConsumable(now,epoch);
            obj.ConsumedAt(index) = double(now);
            payload = event.Payload;
        end
        function value = table(obj)
            n = numel(obj.Events);
            rows = repmat(struct("RunID","","EventID","","EventType","", ...
                "Producer","","Consumer","","ProducedAt",NaN, ...
                "AvailableAt",NaN,"ExpiryAt",NaN,"ConsumedAt",NaN, ...
                "ParentEventIDs","","ConfigurationEpoch",NaN, ...
                "PayloadSHA256","","Status",""),n,1);
            for ii = 1:n
                event = obj.Events{ii};
                rows(ii) = struct("RunID",obj.RunID, ...
                    "EventID",event.EventID,"EventType",event.EventType, ...
                    "Producer",event.Producer,"Consumer",event.Consumer, ...
                    "ProducedAt",event.ProducedAt, ...
                    "AvailableAt",event.AvailableAt, ...
                    "ExpiryAt",event.ExpiryAt, ...
                    "ConsumedAt",obj.ConsumedAt(ii), ...
                    "ParentEventIDs",join(event.ParentEventIDs,"|"), ...
                    "ConfigurationEpoch",event.ConfigurationEpoch, ...
                    "PayloadSHA256",event.PayloadSHA256,"Status","PASS");
            end
            value = struct2table(rows,"AsArray",true);
        end
    end
end
