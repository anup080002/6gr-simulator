classdef RARetryState
    % UE four-step CBRA retry state. A gNB detector result is not an input.
    properties (SetAccess=private)
        TransmissionCounter double = 1
        PowerRampingCounter double = 1
        PreambleTransMax double = NaN
        Status string = "ready"
        PreviousReference string = ""
        CurrentReference string = ""
        PreviousTransmissionEndTicks int64 = int64(-1)
        CurrentTransmissionEndTicks int64 = int64(-1)
        EarliestNextAttemptTicks int64 = int64(0)
        ResponseExpiryTicks int64 = int64(0)
        RunId string = ""
        BackoffSeed double
        BackoffRNGState
        Events table = table()
    end
    methods
        function obj=RARetryState(seed)
            validateattributes(seed,{'numeric'},{'scalar','integer','finite','>=',0,'<=',2^32-1});
            obj.BackoffSeed=double(seed);
            stream=RandStream('mt19937ar','Seed',obj.BackoffSeed);
            obj.BackoffRNGState=stream.State;
        end
        function tf=canStart(obj,nowTicks)
            now=sixgr.phy.frame.AbsoluteTime.fromTicks(nowTicks);
            tf=obj.Status=="ready" && now.Ticks>=obj.EarliestNextAttemptTicks;
        end
        function obj=prepare(obj,reference,nowTicks,suspendRamping,lastLBTFailure)
            reference=string(reference);
            if ~isscalar(reference) || strlength(reference)==0 || ~obj.canStart(nowTicks)
                error('sixgr:mac:ra:RetryNotEligible','A retry requires an identified reference and an expired backoff without an active/exhausted attempt.');
            end
            validateattributes(suspendRamping,{'logical'},{'scalar'});
            validateattributes(lastLBTFailure,{'logical'},{'scalar'});
            % TS 38.321 5.1.3. A changed reference retains the counter; it
            % does not reset it or increment it merely because an ID grew.
            if obj.TransmissionCounter>1 && obj.PreviousTransmissionEndTicks>=0 && ...
                    ~suspendRamping && ~lastLBTFailure && reference==obj.PreviousReference
                obj.PowerRampingCounter=obj.PowerRampingCounter+1;
            end
            obj.CurrentReference=reference; obj.CurrentTransmissionEndTicks=int64(-1);
            obj.Status="prepared";
        end
        function obj=arm(obj,ra)
            if obj.Status~="prepared" || ra.AttemptId~=obj.TransmissionCounter || ...
                    ra.PreamblePowerRampingCounter~=obj.PowerRampingCounter
                error('sixgr:mac:ra:RetryCounterAuthority','Prepared PHY power and attempt counters must match the UE state.');
            end
            validateattributes(ra.PreambleTransMax,{'numeric'},{'scalar','integer','positive','finite'});
            if obj.TransmissionCounter>ra.PreambleTransMax
                error('sixgr:mac:ra:PreambleTransMaxExceeded','No transmission is allowed after preambleTransMax is exhausted.');
            end
            obj.PreambleTransMax=double(ra.PreambleTransMax);
            obj.RunId=string(ra.RunId);
            obj.ResponseExpiryTicks=ra.RARMonitoringWindow.ExpiryTicksExclusive;
            obj.Status="waiting_rar";
        end
        function obj=transmitted(obj,actualEndTicks)
            actual=sixgr.phy.frame.AbsoluteTime.fromTicks(actualEndTicks);
            if obj.Status~="waiting_rar" || obj.CurrentTransmissionEndTicks>=0 || ...
                    actual.Ticks<=obj.PreviousTransmissionEndTicks || actual.Ticks>=obj.ResponseExpiryTicks
                error('sixgr:mac:ra:InvalidPreambleCompletion','Record one actual chronological preamble completion before its response deadline.');
            end
            obj.CurrentTransmissionEndTicks=actual.Ticks;
            obj.PreviousTransmissionEndTicks=actual.Ticks;
            obj.PreviousReference=obj.CurrentReference;
        end
        function [obj,row]=responseExpired(obj,receiver,nowTicks)
            now=sixgr.phy.frame.AbsoluteTime.fromTicks(nowTicks);
            if obj.Status~="waiting_rar" || obj.CurrentTransmissionEndTicks<0 || ...
                    ~isa(receiver,'sixgr.phy.ra.RARReceiveWindow') || receiver.Status~="expired" || ...
                    string(receiver.RAConfig.RunId)~=obj.RunId || now.Ticks~=obj.ResponseExpiryTicks || ...
                    receiver.Window.ExpiryTicksExclusive~=obj.ResponseExpiryTicks
                error('sixgr:mac:ra:MissingUERARTimeout','Only an executed UE receive-window expiry can advance these retry counters.');
            end
            previous=obj.TransmissionCounter;
            obj.TransmissionCounter=previous+1;
            exhausted=obj.TransmissionCounter==obj.PreambleTransMax+1;
            draw=NaN; backoffTicks=int64(0);
            if exhausted
                obj.Status="exhausted";
            else
                stream=RandStream('mt19937ar','Seed',obj.BackoffSeed);
                stream.State=obj.BackoffRNGState;
                draw=rand(stream); obj.BackoffRNGState=stream.State;
                backoffTicks=int64(ceil(receiver.PreambleBackoff_ms*draw* ...
                    double(sixgr.phy.frame.AbsoluteTime.TicksPerSecond)/1000));
                next=now.plusTicks(backoffTicks);
                obj.EarliestNextAttemptTicks=next.Ticks;
                obj.Status="ready";
            end
            earliest=NaN;
            if ~exhausted, earliest=double(obj.EarliestNextAttemptTicks); end
            row=table(obj.RunId,double(receiver.RAConfig.UEId),previous,obj.TransmissionCounter, ...
                obj.PowerRampingCounter,obj.PreambleTransMax,obj.CurrentReference, ...
                double(obj.CurrentTransmissionEndTicks),double(now.Ticks), ...
                receiver.PreambleBackoff_ms,string(receiver.BackoffSource),obj.BackoffSeed,draw, ...
                double(backoffTicks),earliest,exhausted,obj.Status, ...
                "actual_ue_rar_timeout_and_retry_state",false,false, ...
                'VariableNames',{'RunId','UEId','CompletedAttempt','NextTransmissionCounter', ...
                'PowerRampingCounter','PreambleTransMax','SelectedReference', ...
                'PreambleTransmissionEndTicks','ResponseExpiryTicks','PreambleBackoff_ms', ...
                'BackoffSource','BackoffSeed','UniformDraw','BackoffTicks','EarliestRetryTicks', ...
                'PreambleTransMaxExhausted','Status','Source','ProxyUsed','FallbackUsed'});
            if isempty(obj.Events), obj.Events=row; else, obj.Events=[obj.Events;row]; end
        end
        function obj=rarAccepted(obj)
            if obj.Status~="waiting_rar" || obj.CurrentTransmissionEndTicks<0
                error('sixgr:mac:ra:RARWithoutPreamble','A received response requires the active transmitted preamble.');
            end
            obj.Status="waiting_contention";
        end
        function obj=completed(obj)
            if obj.Status~="waiting_contention"
                error('sixgr:mac:ra:AccessCompletionWithoutRAR','Access completion requires actual RAR reception.');
            end
            obj.Status="completed";
        end
    end
end
