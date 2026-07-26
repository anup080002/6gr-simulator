classdef OLLAState < handle
    %OLLASTATE Event-sourced per-UE/cell/direction/BWP/table OLLA state.

    properties (SetAccess=immutable)
        Key struct
        TargetBLER double
        MuAckDb double
        MuNackDb double
        LowDb double
        HighDb double
        DTXPolicy string
    end
    properties (SetAccess=private)
        MarginDb double = 0
        EventIndex double = 0
        LastEventSlot double = NaN
        Events = struct([])
    end

    methods
        function obj = OLLAState(key,targetBLER,muAckDb,lowDb,highDb,dtxPolicy)
            required = ["UEID","Direction","ServingCellID","ScheduledCellID", ...
                "BWPID","MCSTable","ConfigurationEpoch"];
            for field = required
                if ~isfield(key,char(field))
                    error("RSLA:InvalidOLLAConfiguration", ...
                        "OLLA key is missing %s.",field);
                end
            end
            if ~(isscalar(targetBLER)&&isfinite(targetBLER)&& ...
                    targetBLER>0&&targetBLER<1&& ...
                    isscalar(muAckDb)&&isfinite(muAckDb)&&muAckDb>0&& ...
                    isfinite(lowDb)&&isfinite(highDb)&&lowDb<highDb&& ...
                    ismember(upper(string(dtxPolicy)),["NACK","IGNORE","RESET"]))
                error("RSLA:InvalidOLLAConfiguration", ...
                    "Invalid target, step, bounds or DTX policy.");
            end
            obj.Key = key;
            obj.TargetBLER = targetBLER;
            obj.MuAckDb = muAckDb;
            obj.MuNackDb = muAckDb*(1-targetBLER)/targetBLER;
            obj.LowDb = lowDb;
            obj.HighDb = highDb;
            obj.DTXPolicy = upper(string(dtxPolicy));
        end

        function event = update(obj,outcome,slot)
            outcome = upper(string(outcome));
            if outcome=="DTX"
                outcome = obj.DTXPolicy;
                if outcome=="IGNORE"
                    event = obj.localEvent("DTX_IGNORED",slot,obj.MarginDb,obj.MarginDb,"");
                    return;
                elseif outcome=="RESET"
                    obj.reset("DTX",slot);
                    event = obj.Events(end);
                    return;
                end
            end
            before = obj.MarginDb;
            if outcome=="ACK"
                after = max(obj.LowDb,min(obj.HighDb,before-obj.MuAckDb));
            elseif outcome=="NACK"
                after = max(obj.LowDb,min(obj.HighDb,before+obj.MuNackDb));
            else
                error("RSLA:InvalidOLLAConfiguration", ...
                    "OLLA outcome must be ACK, NACK or DTX.");
            end
            obj.MarginDb = after;
            event = obj.localEvent(outcome,slot,before,after,"");
        end

        function reset(obj,reason,slot)
            before = obj.MarginDb;
            obj.MarginDb = 0;
            obj.localEvent("RESET",slot,before,0,string(reason));
        end

        function value = history(obj)
            value = obj.Events;
        end
    end

    methods (Access=private)
        function event = localEvent(obj,outcome,slot,before,after,reason)
            obj.EventIndex = obj.EventIndex+1;
            obj.LastEventSlot = double(slot);
            event = struct("Key",obj.Key,"EventIndex",obj.EventIndex, ...
                "Slot",double(slot),"Outcome",string(outcome), ...
                "MarginBeforeDb",before,"MarginAfterDb",after, ...
                "TargetBLER",obj.TargetBLER,"MuAckDb",obj.MuAckDb, ...
                "MuNackDb",obj.MuNackDb,"ResetReason",string(reason), ...
                "EventSHA256","");
            event.EventSHA256 = sixgr.phy.rsla.RSLAUtil.hash(event);
            if isempty(obj.Events)
                obj.Events = event;
            else
                obj.Events(end+1) = event;
            end
        end
    end
end
