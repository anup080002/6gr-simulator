classdef SchedulingRequestState < handle
    %SCHEDULINGREQUESTSTATE Per-SR-ID pending/prohibit/fallback state.
    properties (SetAccess=private)
        SRID (1,1) double
        State (1,1) string = "IDLE"
        TxCounter (1,1) double = 0
        MaxTransmissions (1,1) double
    end
    methods
        function obj=SchedulingRequestState(srID,maxTransmissions)
            arguments
                srID (1,1) double {mustBeInteger,mustBeNonnegative}
                maxTransmissions (1,1) double {mustBeInteger,mustBePositive}
            end
            obj.SRID=srID; obj.MaxTransmissions=maxTransmissions;
        end
        function [state,transmit]=transition(obj,event)
            state=upper(obj.State); event=upper(string(event)); transmit=false;
            next=sixgr.l2.mac.SchedulingRequestState.nextState(state,event);
            obj.State=next;
            if event=="SR_TX"
                obj.TxCounter=obj.TxCounter+1; transmit=true;
            elseif ismember(event,["UL_GRANT","BSR_SENT","RRC_RELEASE"])
                obj.TxCounter=0;
            end
            state=obj.State;
        end
    end
    methods (Static)
        function next=nextState(state,event)
            state=upper(string(state)); event=upper(string(event));
            keys=[ ...
                "IDLE|DATA_ARRIVAL","PENDING"
                "IDLE|RRC_RELEASE","IDLE"
                "PENDING|BSR_SENT","IDLE"
                "PENDING|RRC_RELEASE","IDLE"
                "PENDING|SR_OCCASION","PENDING"
                "PENDING|SR_TX","PROHIBITED"
                "PENDING|UL_GRANT","IDLE"
                "PROHIBITED|MAX_TX","RA_FALLBACK"
                "PROHIBITED|PROHIBIT_EXPIRE","PENDING"
                "PROHIBITED|RRC_RELEASE","IDLE"
                "PROHIBITED|UL_GRANT","IDLE"
                "RA_FALLBACK|RRC_RELEASE","IDLE"];
            index=find(keys(:,1)==state+"|"+event,1);
            if isempty(index)
                error("sixgr:mac:InvalidSRTransition", ...
                    "Illegal SR transition %s + %s.",state,event);
            end
            next=keys(index,2);
        end
    end
end
