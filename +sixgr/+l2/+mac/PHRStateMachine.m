classdef PHRStateMachine < handle
    %PHRSTATEMACHINE Event-owned PH/PCMAX reporting and timers.
    properties (SetAccess=private)
        UEID (1,1) double
        PendingTrigger (1,1) string = "none"
        ProhibitUntilSlot (1,1) double = -Inf
        PeriodicDueSlot (1,1) double = Inf
    end
    methods
        function obj=PHRStateMachine(ueID)
            obj.UEID=double(ueID);
        end
        function trigger(obj,kind,currentSlot)
            kind=lower(string(kind));
            if ~ismember(kind,["periodic","pathlosschange", ...
                    "powerbackoffchange","activation","prohibitexpiry"])
                error("sixgr:mac:InvalidPHRTrigger","Unknown PHR trigger.");
            end
            if currentSlot>=obj.ProhibitUntilSlot
                obj.PendingTrigger=kind;
            end
        end
        function report=buildReport(obj,entries,currentSlot,prohibitSlots)
            if obj.PendingTrigger=="none" || currentSlot<obj.ProhibitUntilSlot
                report=struct("Transmit",false); return;
            end
            n=numel(entries);
            ph=zeros(n,1); pcmax=zeros(n,1);
            for ii=1:n
                ph(ii)=sixgr.l2.mac.PHRMappingR18.phIndex(entries(ii).PH_dB);
                pcmax(ii)=sixgr.l2.mac.PHRMappingR18.pcmaxIndex(entries(ii).PCMAX_dBm);
            end
            report=struct("Transmit",true,"PHIndex",ph, ...
                "PCMAXIndex",pcmax,"MultipleEntry",n>1, ...
                "Trigger",obj.PendingTrigger);
            obj.PendingTrigger="none";
            obj.ProhibitUntilSlot=currentSlot+prohibitSlots;
        end
    end
end
