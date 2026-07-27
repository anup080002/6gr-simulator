classdef RRCEndpoint < handle
    %RRCENDPOINT Bounded Release-18 UPER/state/timer endpoint authority.
    properties (SetAccess=private)
        Role (1,1) string
        UEID (1,1) string
        Registry sixgr.l3.rrc18.asn1.RRCASN1Registry
        StateMachine sixgr.l3.rrc18.RRCStateMachine
        Timers sixgr.l3.rrc18.RRCTimerSet
        SecurityActive (1,1) logical=false
    end
    methods
        function obj=RRCEndpoint(role,ueID,vectorRoot,timerConfig)
            role=upper(string(role));
            if ~ismember(role,["UE","GNB"])
                error("sixgr:rrc:ASN1ConstraintViolation", ...
                    "RRC endpoint role must be UE or GNB.");
            end
            obj.Role=role;obj.UEID=string(ueID);
            obj.Registry=sixgr.l3.rrc18.asn1.RRCASN1Registry(vectorRoot);
            obj.StateMachine=sixgr.l3.rrc18.RRCStateMachine( ...
                role,obj.UEID,vectorRoot);
            obj.Timers=sixgr.l3.rrc18.RRCTimerSet(timerConfig);
        end
        function bytes=encode(obj,messageType,transactionID)
            obj.Registry.requireEnabled(messageType,transactionID);
            bytes=sixgr.l3.rrc18.asn1.RRCBoundedUPERCodec.encode( ...
                messageType,transactionID);
        end
        function decoded=decode(obj,channel,bytes)
            decoded=sixgr.l3.rrc18.asn1.RRCBoundedUPERCodec.decode( ...
                bytes,channel);
            obj.Registry.requireEnabled(decoded.MessageType, ...
                decoded.TransactionID);
        end
        function event=transition(obj,eventName,time,transactionID)
            arguments
                obj
                eventName (1,1) string
                time (1,1) double
                transactionID=[]
            end
            event=obj.StateMachine.apply(eventName,time,transactionID);
            if eventName=="SECURITY_MODE_COMPLETE_DECODED"
                obj.SecurityActive=true;
            end
        end
        function tick(obj,time),obj.Timers.tick(time);end
    end
end
