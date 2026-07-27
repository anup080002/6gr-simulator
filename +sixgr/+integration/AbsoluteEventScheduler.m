classdef AbsoluteEventScheduler < handle
    %ABSOLUTEEVENTSCHEDULER Deterministic AvailableAt-ordered event queue.
    properties (SetAccess=immutable)
        Clock
    end
    properties (Access=private)
        Queue (:,1) cell = cell(0,1)
    end
    methods
        function obj = AbsoluteEventScheduler(clock)
            obj.Clock = clock;
        end
        function enqueue(obj,event)
            if ~isa(event,"sixgr.integration.EventEnvelope")
                error("sixgr:integration:InvalidEvent","Expected EventEnvelope.");
            end
            obj.Queue{end+1,1} = event;
            obj.sortQueue();
        end
        function events = releaseDue(obj)
            due = cellfun(@(x)x.AvailableAt <= obj.Clock.AbsoluteSample,obj.Queue);
            events = obj.Queue(due);
            obj.Queue = obj.Queue(~due);
        end
        function n = count(obj)
            n = numel(obj.Queue);
        end
    end
    methods (Access=private)
        function sortQueue(obj)
            if numel(obj.Queue) < 2, return; end
            key = cellfun(@(x)x.AvailableAt,obj.Queue);
            ids = string(cellfun(@(x)x.EventID,obj.Queue,"UniformOutput",false));
            [~,order] = sortrows(table(key(:),ids(:)),[1 2]);
            obj.Queue = obj.Queue(order);
        end
    end
end
