classdef MeasurementAvailabilityQueue < handle
    %MEASUREMENTAVAILABILITYQUEUE Enforce availability and expiry of CSI/RS evidence.
    properties (SetAccess=immutable)
        Scheduler
        Store
        ConfigurationEpoch (1,1) double
    end
    methods
        function obj = MeasurementAvailabilityQueue(scheduler,store,epoch)
            obj.Scheduler = scheduler; obj.Store = store;
            obj.ConfigurationEpoch = double(epoch);
        end
        function publish(obj,type,payload,processingDelay,validity,varargin)
            now = obj.Scheduler.Clock.AbsoluteSample;
            event = sixgr.integration.EventEnvelope(type,"receiver", ...
                "scheduler",now,now+double(processingDelay), ...
                now+double(processingDelay)+double(validity),payload, ...
                "RunID",obj.Store.RunID, ...
                "ConfigurationEpoch",obj.ConfigurationEpoch,varargin{:});
            obj.Store.append(event); obj.Scheduler.enqueue(event);
        end
        function rows = release(obj)
            events = obj.Scheduler.releaseDue();
            rows = cell(numel(events),1);
            for ii = 1:numel(events)
                rows{ii} = obj.Store.consume(events{ii}.EventID, ...
                    obj.Scheduler.Clock.AbsoluteSample, ...
                    obj.ConfigurationEpoch);
            end
        end
    end
end
