classdef HARQFeedbackEvent
    %HARQFEEDBACKEVENT Typed ACK/NACK/DTX codebook binding.

    properties (SetAccess=immutable)
        Outcome (1,1) string
        CodebookType (1,1) string
        DAI (1,1) double
        BitPosition (1,1) double
        ServingCell (1,1) double
        HARQProcess (1,1) double
        Codeword (1,1) double
        SourceAttemptID (1,1) string
        DueSlot (1,1) double
        ReceivedSlot (1,1) double
    end

    methods
        function obj=HARQFeedbackEvent(data)
            arguments
                data (1,1) struct
            end
            required=["Outcome","CodebookType","DAI","BitPosition", ...
                "ServingCell","HARQProcess","Codeword","SourceAttemptID", ...
                "DueSlot","ReceivedSlot"];
            for field=required
                if ~isfield(data,field)
                    error("sixgr:mac:InvalidHARQFeedbackContext", ...
                        "Feedback requires %s.",field);
                end
            end
            outcome=upper(string(data.Outcome));
            codebook=lower(string(data.CodebookType));
            dai=double(data.DAI); position=double(data.BitPosition);
            if ~sixgr.l2.mac.HARQFeedbackEvent.isContextValid( ...
                    codebook,outcome,dai,position)
                error("sixgr:mac:InvalidHARQFeedbackContext", ...
                    "Invalid %s codebook binding.",codebook);
            end
            if double(data.ReceivedSlot)~=double(data.DueSlot)
                error("sixgr:mac:HARQFeedbackTimingMismatch", ...
                    "Feedback must occur in the decoded K1 position.");
            end
            obj.Outcome=outcome; obj.CodebookType=codebook;
            obj.DAI=dai; obj.BitPosition=position;
            obj.ServingCell=double(data.ServingCell);
            obj.HARQProcess=double(data.HARQProcess);
            obj.Codeword=double(data.Codeword);
            obj.SourceAttemptID=string(data.SourceAttemptID);
            obj.DueSlot=double(data.DueSlot);
            obj.ReceivedSlot=double(data.ReceivedSlot);
        end

        function nextState=apply(obj)
            if obj.Outcome=="ACK"
                nextState="ACKED_DELIVERED";
            elseif ismember(obj.Outcome,["NACK","DTX"])
                nextState="RETX_PENDING";
            else
                nextState="AWAITING_FEEDBACK";
            end
        end
    end

    methods (Static)
        function valid=isContextValid(codebook,outcome,dai,position)
            valid=false;
            codebook=lower(string(codebook)); outcome=upper(string(outcome));
            if ~ismember(codebook,["type1","type2","type3"]) || ...
                    ~ismember(outcome,["ACK","NACK","DTX","NOT_EXPECTED","INVALID"]) || ...
                    ~ismember(dai,0:3) || ~ismember(position,0:1)
                return;
            end
            if ismember(outcome,["NOT_EXPECTED","INVALID"])
                valid=dai==0 && position==0;
                return;
            end
            if codebook=="type1" && dai>1
                return;
            end
            valid=(position==0)||(dai>=1);
        end
    end
end
