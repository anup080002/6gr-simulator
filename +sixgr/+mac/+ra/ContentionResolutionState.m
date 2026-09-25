classdef ContentionResolutionState
    % UE-owned CCCH contention resolution, TS 38.321 clause 5.1.5.
    % Neither the gNB's Msg3 decode nor the transmitted Msg4 is an input.
    properties (SetAccess=private)
        ExpectedIdentity string
        TemporaryCRNTI double
        StartTicks int64
        ExpiryTicksExclusive int64
        Status string = "armed"
        LastObservationTicks int64 = int64(-1)
        ResolutionTicks int64 = int64(-1)
        IdentityMatches logical = false
        Msg3HARQFlushRequired logical = false
        TemporaryCRNTIDiscardRequired logical = false
        Events table = table()
    end
    methods
        function obj=ContentionResolutionState(identity,rnti,startTicks,durationTicks)
            identity=upper(string(identity));
            assert(isscalar(identity) && ~isempty(regexp(char(identity),'^[0-9A-F]{12}$','once')), ...
                'sixgr:mac:ra:InvalidUEContentionIdentity','UE identity must be its locally transmitted 48-bit CCCH identity.');
            validateattributes(rnti,{'numeric'},{'scalar','finite','integer','>=',1,'<=',65519});
            start=sixgr.phy.frame.AbsoluteTime.fromTicks(startTicks);
            validateattributes(durationTicks,{'int64'},{'scalar','positive'});
            finish=start.plusTicks(durationTicks);
            obj.ExpectedIdentity=identity; obj.TemporaryCRNTI=double(rnti);
            obj.StartTicks=start.Ticks; obj.ExpiryTicksExclusive=finish.Ticks;
        end
        function obj=start(obj,nowTicks)
            assert(obj.Status=="armed" && isequal(nowTicks,obj.StartTicks), ...
                'sixgr:mac:ra:InvalidContentionTimerStart','Start only at the executed Msg3 end-symbol boundary.');
            obj.Status="waiting";
            obj=obj.record(nowTicks,"msg3_transmission_end_timer_started",false,false,"");
        end
        function obj=receive(obj,nowTicks,decodedRNTI,dciCRC,tbCRC,receivedIdentity)
            now=sixgr.phy.frame.AbsoluteTime.fromTicks(nowTicks);
            validateattributes(dciCRC,{'logical'},{'scalar'});
            validateattributes(tbCRC,{'logical'},{'scalar'});
            assert(obj.Status=="waiting" && now.Ticks>=obj.StartTicks && ...
                now.Ticks<=obj.ExpiryTicksExclusive && now.Ticks>obj.LastObservationTicks, ...
                'sixgr:mac:ra:InvalidContentionObservation','Consume each complete UE observation once, inside the running timer.');
            obj.LastObservationTicks=now.Ticks;
            receivedIdentity=upper(string(receivedIdentity));
            assert(isscalar(receivedIdentity),'sixgr:mac:ra:InvalidDecodedContentionIdentity','One decoded identity or an empty identity is required.');
            reason="pdcch_not_decoded";
            if dciCRC && decodedRNTI==obj.TemporaryCRNTI
                reason="msg4_tb_not_decoded";
                if tbCRC
                    obj.ResolutionTicks=now.Ticks;
                    obj.IdentityMatches=receivedIdentity==obj.ExpectedIdentity;
                    obj.Status="identity_mismatch";
                    if obj.IdentityMatches, obj.Status="succeeded"; end
                    obj.Msg3HARQFlushRequired=true;
                    obj.TemporaryCRNTIDiscardRequired=true;
                    reason=obj.Status;
                end
            elseif dciCRC
                reason="different_rnti_not_our_contention";
            end
            obj=obj.record(now.Ticks,reason,dciCRC,tbCRC,receivedIdentity);
        end
        function obj=expire(obj,nowTicks)
            assert(obj.Status=="waiting" && isequal(nowTicks,obj.ExpiryTicksExclusive), ...
                'sixgr:mac:ra:InvalidContentionTimerExpiry','Only the actual outstanding timer boundary can expire contention.');
            obj.Status="expired"; obj.ResolutionTicks=nowTicks;
            obj.Msg3HARQFlushRequired=true; obj.TemporaryCRNTIDiscardRequired=true;
            obj=obj.record(nowTicks,"contention_timer_expired",false,false,"");
        end
    end
    methods (Access=private)
        function obj=record(obj,ticks,event,dci,tb,identity)
            row=table(double(ticks),obj.Status,string(event),dci,tb,string(identity), ...
                obj.IdentityMatches,obj.Msg3HARQFlushRequired,obj.TemporaryCRNTIDiscardRequired, ...
                "ue_received_contention_state",false,false,'VariableNames', ...
                {'EventTicks','State','Event','DCICrcPass','TBCrcPass','ReceivedIdentity', ...
                'IdentityMatches','Msg3HARQFlushRequired','TemporaryCRNTIDiscardRequired', ...
                'Source','ProxyUsed','FallbackUsed'});
            obj.Events=[obj.Events;row];
        end
    end
end
