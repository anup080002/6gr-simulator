classdef BSRStateMachine < handle
    %BSRSTATEMACHINE Event-owned BSR triggers, timers, and formats.
    properties (SetAccess=private)
        UEID (1,1) double
        Buffers (1,:) double
        PendingTrigger (1,1) string = "none"
        PeriodicTimer (1,1) double
        RetxTimer (1,1) double
        LastReportSlot (1,1) double = NaN
    end
    methods
        function obj=BSRStateMachine(ueID,numLCG,periodicSlots,retxSlots)
            arguments
                ueID (1,1) double {mustBeInteger,mustBeNonnegative}
                numLCG (1,1) double {mustBeInteger,mustBePositive}
                periodicSlots (1,1) double {mustBeInteger,mustBePositive}
                retxSlots (1,1) double {mustBeInteger,mustBePositive}
            end
            obj.UEID=ueID; obj.Buffers=zeros(1,numLCG);
            obj.PeriodicTimer=periodicSlots; obj.RetxTimer=retxSlots;
        end
        function arrival(obj,lcgID,bytes)
            validateattributes(lcgID,{'numeric'},{'scalar','integer','>=',0,'<',numel(obj.Buffers)});
            validateattributes(bytes,{'numeric'},{'scalar','integer','nonnegative'});
            wasEmpty=sum(obj.Buffers)==0;
            obj.Buffers(lcgID+1)=obj.Buffers(lcgID+1)+bytes;
            if bytes>0 && wasEmpty, obj.PendingTrigger="regular"; end
        end
        function trigger(obj,kind)
            kind=lower(string(kind));
            if ~ismember(kind,["regular","periodic","retx","padding"])
                error("sixgr:mac:InvalidBSRTrigger","Unknown BSR trigger.");
            end
            obj.PendingTrigger=kind;
        end
        function decision=buildReport(obj,grantBytes,slot)
            active=find(obj.Buffers>0)-1;
            if isempty(active)
                decision=struct("Transmit",false,"Format","none","Indices",[]);
                return;
            end
            if numel(active)==1
                format="short"; required=2;
            else
                format="long"; required=2+numel(active);
            end
            if grantBytes<required
                if grantBytes>=2
                    format="shortTruncated"; active=active(1);
                else
                    decision=struct("Transmit",false,"Format","none","Indices",[]);
                    return;
                end
            end
            indices=arrayfun(@(x)sixgr.l2.mac.BSRTableR18.indexForBytes( ...
                obj.Buffers(x+1),"8bit"),active);
            decision=struct("Transmit",true,"Format",format, ...
                "LCGIDs",active,"Indices",indices,"Trigger",obj.PendingTrigger);
            obj.PendingTrigger="none"; obj.LastReportSlot=slot;
        end
    end
end
