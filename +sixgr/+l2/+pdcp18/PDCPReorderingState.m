classdef PDCPReorderingState < handle
    % TS 38.323 V18.5.0 5.2.2: buffers and state hold COUNT, not bare SN.

    properties (SetAccess = private)
        SNBits (1,1) double
        RX_DELIV (1,1) double = 0
        RX_NEXT (1,1) double = 0
        RX_REORD (1,1) double = 0
        DuplicateCount (1,1) double = 0
        Delivered double = []
        Buffered double = []
        ReorderingTime_s (1,1) double = inf
        TimerExpiry_s (1,1) double = inf
        TimerRunning (1,1) logical = false
        LastTime_s (1,1) double = 0
        SampleRateHz (1,1) double = NaN
        ClockEpoch (1,1) double = NaN
        LastSample (1,1) double = 0
        TimerExpirySample (1,1) double = inf
        ReorderingSamples (1,1) double = inf
    end

    methods
        function obj = PDCPReorderingState(snBits, initialSN, reorderingTime_s, sampleRateHz, clockEpoch)
            arguments
                snBits (1,1) double
                initialSN (1,1) double = 0
                reorderingTime_s (1,1) double = inf
                sampleRateHz (1,1) double = NaN
                clockEpoch (1,1) double = NaN
            end
            if ~ismember(snBits, [12 18]) || ~isfinite(initialSN) || ...
                    initialSN<0 || initialSN>2^32-1 || initialSN~=fix(initialSN) || ...
                    isnan(reorderingTime_s) || reorderingTime_s<0
                error("sixgr:pdcp:MalformedPDU", ...
                    "Reordering SN length must be 12 or 18.");
            end
            obj.SNBits = snBits;
            obj.RX_DELIV = initialSN;
            obj.RX_NEXT = initialSN;
            obj.RX_REORD = initialSN;
            obj.ReorderingTime_s = reorderingTime_s;
            if ~isnan(sampleRateHz)||~isnan(clockEpoch)
                assert(isfinite(sampleRateHz)&&sampleRateHz>0&&isfinite(clockEpoch)&& ...
                    clockEpoch>=0&&clockEpoch==fix(clockEpoch), ...
                    'sixgr:pdcp:ReorderingClockViolation','Sample-based reordering needs both original clock fields.');
                obj.SampleRateHz=sampleRateHz;obj.ClockEpoch=clockEpoch;
                if isfinite(reorderingTime_s),obj.ReorderingSamples=obj.sampleAt(reorderingTime_s);end
            end
        end

        function value = snapshot(obj)
            value=struct(); names=properties(obj);
            for k=1:numel(names), value.(names{k})=obj.(names{k}); end
        end

        function other = copy(obj)
            % Isolated preview for clock/COUNT validation; no live timer mutation.
            other=sixgr.l2.pdcp18.PDCPReorderingState(obj.SNBits,obj.RX_DELIV,obj.ReorderingTime_s,obj.SampleRateHz,obj.ClockEpoch);
            names=properties(obj);
            for k=1:numel(names), other.(names{k})=obj.(names{k}); end
        end

        function count = inferCount(obj, sn)
            if ~isscalar(sn) || ~isfinite(sn) || sn < 0 || sn ~= floor(sn) || sn >= 2^obj.SNBits
                error("sixgr:pdcp:ReorderingStateViolation", ...
                    "Received SN is invalid.");
            end
            modulus=2^obj.SNBits; window=modulus/2;
            hfn=floor(obj.RX_DELIV/modulus); baseSN=mod(obj.RX_DELIV,modulus);
            if sn<baseSN-window, hfn=hfn+1;
            elseif sn>=baseSN+window, hfn=hfn-1;
            end
            count=hfn*modulus+sn;
        end

        function tf = alreadyReceived(obj,count)
            tf=count<obj.RX_DELIV || ismember(count,obj.Buffered);
        end

        function [delivered,accepted,count] = receive(obj, sn, time)
            if nargin<3, time=obj.LastTime_s; end
            delivered=obj.advance(time);
            count=obj.inferCount(sn); accepted=false;
            if count<0 || obj.alreadyReceived(count)
                obj.DuplicateCount = obj.DuplicateCount + 1;
                return;
            end
            assert(count<=2^32-1,'sixgr:pdcp:CountExhausted','Received COUNT exceeds 32 bits.');
            accepted=true; obj.Buffered(end+1)=count;
            obj.RX_NEXT=max(obj.RX_NEXT,count+1);
            delivered=[delivered obj.releaseContiguous()];
            obj.updateTimer(time);
            if obj.TimerRunning
                delivered=[delivered obj.advance(time)];
            end
        end

        function delivered = advance(obj,time)
            assert(isscalar(time) && isfinite(time) && time>=0 && (isfinite(obj.SampleRateHz)||time>=obj.LastTime_s), ...
                'sixgr:pdcp:ReorderingClockViolation','PDCP clock must be finite and monotonic.');
            expired=time>=obj.TimerExpiry_s;
            if isfinite(obj.SampleRateHz)
                sample=obj.sampleAt(time);
                assert(sample>=obj.LastSample,'sixgr:pdcp:ReorderingClockViolation','Original sample clock moved backwards.');
                obj.LastSample=sample;time=sample/obj.SampleRateHz;
                expired=sample>=obj.TimerExpirySample;
            end
            obj.LastTime_s=time; delivered=[];
            if ~obj.TimerRunning || ~expired, return; end
            below=sort(obj.Buffered(obj.Buffered<obj.RX_REORD));
            obj.Buffered(obj.Buffered<obj.RX_REORD)=[];
            obj.Delivered=[obj.Delivered below]; obj.RX_DELIV=obj.RX_REORD;
            delivered=[below obj.releaseContiguous()];
            obj.TimerRunning=false; obj.TimerExpiry_s=inf;obj.TimerExpirySample=inf;
            obj.updateTimer(time);
        end
    end
    methods (Access=private)
        function sample=sampleAt(obj,time)
            value=time*obj.SampleRateHz;sample=round(value);
            assert(isscalar(time)&&isfinite(time)&&time>=0&&abs(value-sample)<=max(1e-7,8*eps(value)), ...
                'sixgr:pdcp:ReorderingClockViolation','PDCP reordering needs an original integer sample boundary.');
        end
        function ready = releaseContiguous(obj)
            ready=[];
            while ismember(obj.RX_DELIV, obj.Buffered)
                obj.Buffered(obj.Buffered == obj.RX_DELIV) = [];
                ready(end+1) = obj.RX_DELIV; %#ok<AGROW>
                obj.Delivered(end+1) = obj.RX_DELIV;
                obj.RX_DELIV = obj.RX_DELIV + 1;
            end
        end
        function updateTimer(obj,time)
            if obj.TimerRunning && obj.RX_DELIV>=obj.RX_REORD
                obj.TimerRunning=false; obj.TimerExpiry_s=inf;obj.TimerExpirySample=inf;
            end
            if ~obj.TimerRunning && obj.RX_DELIV<obj.RX_NEXT
                obj.RX_REORD=obj.RX_NEXT; obj.TimerRunning=true;
                if isfinite(obj.SampleRateHz)
                    obj.TimerExpirySample=obj.sampleAt(time)+obj.ReorderingSamples;
                    obj.TimerExpiry_s=obj.TimerExpirySample/obj.SampleRateHz;
                else
                    obj.TimerExpiry_s=time+obj.ReorderingTime_s;
                end
            end
        end
    end
end
