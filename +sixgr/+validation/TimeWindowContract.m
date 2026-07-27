classdef TimeWindowContract
    %TIMEWINDOWCONTRACT Half-open validation KPI phase ownership.
    properties (SetAccess=private)
        StartTime double
        WarmupEnd double
        AcquisitionEnd double
        SteadyEnd double
        TailEnd double
    end
    methods
        function obj=TimeWindowContract(startTime,warmupEnd, ...
                acquisitionEnd,steadyEnd,tailEnd)
            values=double([startTime warmupEnd acquisitionEnd steadyEnd tailEnd]);
            if numel(values)~=5 || any(~isfinite(values)) || ...
                    any(diff(values)<=0)
                error("sixgr:validation:InvalidTimeWindow", ...
                    "Time-window boundaries must be finite and strictly increasing.");
            end
            obj.StartTime=values(1); obj.WarmupEnd=values(2);
            obj.AcquisitionEnd=values(3); obj.SteadyEnd=values(4);
            obj.TailEnd=values(5);
        end
        function phase=classify(obj,timestamp)
            t=double(timestamp);
            if ~(isscalar(t)&&isfinite(t))
                error("sixgr:validation:SchemaNonFinite", ...
                    "KPI timestamp must be finite.");
            end
            if t>=obj.StartTime && t<obj.WarmupEnd
                phase="WARMUP";
            elseif t>=obj.WarmupEnd && t<obj.AcquisitionEnd
                phase="ACQUISITION";
            elseif t>=obj.AcquisitionEnd && t<obj.SteadyEnd
                phase="STEADY_STATE";
            elseif t>=obj.SteadyEnd && t<obj.TailEnd
                phase="TAIL_DRAIN";
            else
                phase="OUTSIDE";
            end
        end
        function out=inclusion(obj,timestamp)
            phase=obj.classify(timestamp);
            out=struct("Phase",phase, ...
                "IncludeBLER",phase=="STEADY_STATE", ...
                "IncludeThroughput",ismember(phase,["STEADY_STATE","TAIL_DRAIN"]), ...
                "IncludeAcquisitionDelay",phase=="ACQUISITION", ...
                "IncludeQueueDrain",phase=="TAIL_DRAIN", ...
                "Status",localStatus(phase));
        end
        function out=asTable(obj,runID)
            phase=["WARMUP";"ACQUISITION";"STEADY_STATE";"TAIL_DRAIN"];
            starts=[obj.StartTime;obj.WarmupEnd;obj.AcquisitionEnd;obj.SteadyEnd];
            ends=[obj.WarmupEnd;obj.AcquisitionEnd;obj.SteadyEnd;obj.TailEnd];
            out=table(repmat(string(runID),4,1),phase,starts,ends, ...
                repmat("[start,end)",4,1),repmat("PASS",4,1), ...
                'VariableNames',["RunID","Phase","StartTime","EndTime", ...
                "BoundaryConvention","Status"]);
        end
    end
end

function out=localStatus(phase)
if phase=="OUTSIDE", out="REJECT"; else, out="PASS"; end
end
