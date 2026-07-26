classdef RRMEventEngine < handle
    %RRMEVENTENGINE Measured L3 event A1-A6 entry/leave state.

    properties (Access=private)
        State
    end

    methods
        function obj = RRMEventEngine()
            obj.State = containers.Map("KeyType","char","ValueType","any");
        end

        function result = update(obj,configuration,measurement,sampleIndex)
            eventID = upper(string(configuration.EventID));
            serving = double(measurement.ServingMeasurementDb);
            neighbor = double(measurement.NeighborMeasurementDb);
            t1 = double(configuration.Threshold1Db);
            t2 = double(configuration.Threshold2Db);
            offset = double(configuration.OffsetDb);
            hysteresis = double(configuration.HysteresisDb);
            ttt = double(configuration.TTTSamples);
            if any(~isfinite([serving neighbor t1 t2 offset hysteresis ttt])) || ...
                    ttt<0 || hysteresis<0
                error("RSLA:EventStateViolation", ...
                    "RRM event configuration and filtered measurements must be finite.");
            end
            condition = localCondition(eventID,serving,neighbor,t1,t2,offset,hysteresis);
            key = char(eventID+"-"+string(configuration.ConfigurationEpoch));
            if isKey(obj.State,key), state = obj.State(key); ...
            else, state = struct("Consecutive",0,"Entered",false); end
            if condition, state.Consecutive = state.Consecutive+1; ...
            else, state.Consecutive = 0; end
            threshold = max(1,ttt);
            enter = ~state.Entered && condition && state.Consecutive>=threshold;
            leave = state.Entered && ~condition;
            if enter, state.Entered = true; end
            if leave, state.Entered = false; end
            obj.State(key) = state;
            result = struct("EventID",eventID,"SampleIndex",sampleIndex, ...
                "Condition",condition,"TTTState",state.Consecutive, ...
                "Entered",enter,"Left",leave,"Active",state.Entered, ...
                "Source","filtered_measurement_state");
        end
    end
end

function value = localCondition(eventID,ms,mn,t1,t2,offset,hysteresis)
switch eventID
    case "A1"
        value = ms-hysteresis>t1;
    case "A2"
        value = ms+hysteresis<t1;
    case "A3"
        value = mn-hysteresis>ms+offset;
    case "A4"
        value = mn-offset-hysteresis>t1;
    case "A5"
        value = ms+hysteresis<t1 && mn-hysteresis>t2;
    case "A6"
        value = mn-hysteresis>ms+offset;
    otherwise
        error("RSLA:EventStateViolation","Unsupported event %s.",eventID);
end
end
