classdef HARQProcess < handle
    %HARQPROCESS Explicit event-driven HARQ state machine.

    properties (SetAccess=private)
        Direction (1,1) string
        State (1,1) string = "IDLE"
        TBKey = []
        Attempts (1,:) cell = {}
        FeedbackHistory (1,:) cell = {}
    end

    methods
        function obj=HARQProcess(direction)
            direction=upper(string(direction));
            if ~ismember(direction,["DL","UL"])
                error("sixgr:mac:InvalidDirection","Direction must be DL or UL.");
            end
            obj.Direction=direction;
        end

        function next=transition(obj,event,varargin)
            next=sixgr.l2.mac.HARQProcess.nextState( ...
                obj.Direction,obj.State,event);
            if next=="NEW_DATA_RESERVED"
                if isempty(varargin) || ~isa(varargin{1},"sixgr.l2.mac.HARQTBKey")
                    error("sixgr:mac:HARQIdentityMissing", ...
                        "RESERVE_NEW requires an immutable HARQTBKey.");
                end
                obj.TBKey=varargin{1};
            end
            obj.State=next;
            if next=="IDLE"
                obj.TBKey=[]; obj.Attempts={}; obj.FeedbackHistory={};
            end
        end

        function addAttempt(obj,attempt)
            if ~isa(attempt,"sixgr.l2.mac.HARQAttemptKey")
                error("sixgr:mac:InvalidHARQAttempt","Expected HARQAttemptKey.");
            end
            if isempty(obj.TBKey)
                error("sixgr:mac:HARQIdentityMissing","No reserved TB.");
            end
            obj.TBKey.assertSame(attempt.TBKey);
            if ~isempty(obj.Attempts)
                first=obj.Attempts{1};
                if first.CodingLayoutSHA256~=attempt.CodingLayoutSHA256 || ...
                        first.RateMatchSHA256~=attempt.RateMatchSHA256
                    error("sixgr:mac:HARQCodingLayoutMismatch", ...
                        "Retransmission coding/rate identity changed.");
                end
            end
            obj.Attempts{end+1}=attempt;
        end
    end

    methods (Static)
        function next=nextState(direction,state,event)
            direction=upper(string(direction)); state=upper(string(state));
            event=upper(string(event));
            keys = [ ...
                "DL|IDLE|RESERVE_NEW","NEW_DATA_RESERVED"
                "DL|NEW_DATA_RESERVED|COMMIT_GRANT","TX_SCHEDULED"
                "DL|TX_SCHEDULED|CANCEL_BEFORE_TX","IDLE"
                "DL|TX_TRANSMITTED|START_FEEDBACK_WAIT","AWAITING_FEEDBACK"
                "DL|AWAITING_FEEDBACK|ACK","ACKED_DELIVERED"
                "DL|AWAITING_FEEDBACK|DTX","RETX_PENDING"
                "DL|AWAITING_FEEDBACK|TA_EXPIRED","FLUSHED"
                "DL|RETX_PENDING|MAX_RETX","DROPPED"
                "DL|RETX_PENDING|RRC_RESET","FLUSHED"
                "DL|DROPPED|RELEASE","IDLE"
                "UL|IDLE|RESERVE_NEW","NEW_DATA_RESERVED"
                "UL|NEW_DATA_RESERVED|CANCEL_GRANT","IDLE"
                "UL|TX_SCHEDULED|PHY_TX","TX_TRANSMITTED"
                "UL|AWAITING_FEEDBACK|NACK","RETX_PENDING"
                "UL|AWAITING_FEEDBACK|MAX_RETX","DROPPED"
                "UL|AWAITING_FEEDBACK|RRC_RESET","FLUSHED"
                "UL|RETX_PENDING|COMMIT_RETX","RETX_SCHEDULED"
                "UL|RETX_SCHEDULED|PHY_TX","TX_TRANSMITTED"
                "UL|RETX_SCHEDULED|CANCEL_RETX","RETX_PENDING"
                "UL|ACKED_DELIVERED|RELEASE","IDLE"
                "UL|FLUSHED|RELEASE","IDLE"];
            query=direction+"|"+state+"|"+event;
            index=find(keys(:,1)==query,1);
            if isempty(index)
                error("sixgr:mac:InvalidHARQTransition", ...
                    "Illegal %s HARQ transition %s + %s.",direction,state,event);
            end
            next=keys(index,2);
        end
    end
end
