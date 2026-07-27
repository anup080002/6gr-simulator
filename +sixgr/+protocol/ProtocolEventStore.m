classdef ProtocolEventStore < handle
    %PROTOCOLEVENTSTORE Append-only event store with monotonic ordering.

    properties (Access = private)
        Events cell = {}
        LastTime (1,1) double = -Inf
    end

    methods
        function event = append(obj, time, layer, type, options)
            arguments
                obj
                time (1,1) double
                layer (1,1) string
                type (1,1) string
                options.UEID (1,1) string = ""
                options.BearerID (1,1) string = ""
                options.SourceEventID (1,1) string = ""
                options.ConfigurationEpoch (1,1) double = 0
                options.Payload = struct()
            end
            if time < obj.LastTime
                error("sixgr:protocol:LineageViolation", ...
                    "Protocol event time cannot move backwards.");
            end
            event = sixgr.protocol.ProtocolEvent( ...
                numel(obj.Events) + 1, time, layer, type, ...
                "UEID", options.UEID, "BearerID", options.BearerID, ...
                "SourceEventID", options.SourceEventID, ...
                "ConfigurationEpoch", options.ConfigurationEpoch, ...
                "Payload", options.Payload);
            obj.Events{end+1} = event;
            obj.LastTime = time;
        end

        function value = toTable(obj, runID)
            n = numel(obj.Events);
            value = table('Size', [n 12], ...
                'VariableTypes', repmat({'string'}, 1, 12), ...
                'VariableNames', {'RunID','EventSequence','AbsoluteTime', ...
                'UEID','BearerID','Layer','EventType','SourceEventID', ...
                'ConfigurationEpoch','PayloadSHA256','EventID','Status'});
            for index = 1:n
                event = obj.Events{index};
                value(index,:) = {string(runID), string(event.EventSequence), ...
                    string(event.AbsoluteTime), event.UEID, event.BearerID, ...
                    event.Layer, event.EventType, event.SourceEventID, ...
                    string(event.ConfigurationEpoch), event.PayloadSHA256, ...
                    event.EventID, "PASS"};
            end
        end

        function count = count(obj)
            count = numel(obj.Events);
        end
    end
end
