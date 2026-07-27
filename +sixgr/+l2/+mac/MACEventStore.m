classdef MACEventStore < handle
    %MACEVENTSTORE Append-only, sequence-checked MAC event journal.

    properties (SetAccess=private)
        Events (1,:) cell = {}
        Sequence (1,1) double = 0
    end

    methods
        function sequence = append(obj, event)
            if ~isa(event, "sixgr.l2.mac.MACEvent")
                error("sixgr:mac:InvalidEvent", ...
                    "MACEventStore accepts only MACEvent values.");
            end
            if any(cellfun(@(x) x.EventID == event.EventID, obj.Events))
                error("sixgr:mac:DuplicateEvent", ...
                    "Event %s is already present.", event.EventID);
            end
            if ~isempty(obj.Events)
                previous = obj.Events{end};
                before = [previous.AbsoluteSlot previous.AbsoluteSymbol];
                after = [event.AbsoluteSlot event.AbsoluteSymbol];
                if after(1) < before(1) || ...
                        (after(1) == before(1) && after(2) < before(2))
                    error("sixgr:mac:EventTimeRegression", ...
                        "Event time cannot regress.");
                end
            end
            obj.Sequence = obj.Sequence + 1;
            obj.Events{end+1} = event;
            sequence = obj.Sequence;
        end

        function appendBatch(obj, events)
            checkpointEvents = obj.Events;
            checkpointSequence = obj.Sequence;
            try
                for ii = 1:numel(events)
                    if iscell(events)
                        event = events{ii};
                    else
                        event = events(ii);
                    end
                    obj.append(event);
                end
            catch ME
                obj.Events = checkpointEvents;
                obj.Sequence = checkpointSequence;
                rethrow(ME);
            end
        end

        function value = replay(obj, projector, initialValue)
            value = initialValue;
            for ii = 1:numel(obj.Events)
                value = projector(value, obj.Events{ii}, ii);
            end
        end

        function value = toTable(obj, runID)
            if nargin < 2
                runID = "MAC_RUNTIME";
            end
            n = numel(obj.Events);
            value = table('Size',[n 13], ...
                'VariableTypes',repmat({'string'},1,13), ...
                'VariableNames',{'RunID','EventSequence','EventID', ...
                'EventType','UEID','ServingCell','Direction', ...
                'AbsoluteSlot','AbsoluteSymbol','SourceEventID', ...
                'PayloadSHA256','Status','ConfigurationEpoch'});
            for ii = 1:n
                e = obj.Events{ii};
                value(ii,:) = {string(runID),string(ii),e.EventID,e.EventType, ...
                    string(e.UEID),string(e.ServingCell),e.Direction, ...
                    string(e.AbsoluteSlot),string(e.AbsoluteSymbol), ...
                    e.SourceEventID,e.PayloadSHA256,"PASS", ...
                    string(e.ConfigurationEpoch)};
            end
        end
    end
end
