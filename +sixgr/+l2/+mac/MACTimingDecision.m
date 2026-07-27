classdef MACTimingDecision
    %MACTIMINGDECISION Immutable result of central MAC timing resolution.

    properties (SetAccess=immutable)
        DecisionID (1,1) string
        K0 (1,1) double
        K1 (1,1) double
        K2 (1,1) double
        PDCCHSlot (1,1) double
        PDSCHSlot (1,1) double
        PUSCHSlot (1,1) double
        FeedbackSlot (1,1) double
        TDDLegal (1,1) logical
        ProcessingLegal (1,1) logical
        ResourceLegal (1,1) logical
        SourceDCIEventID (1,1) string
    end

    methods
        function obj = MACTimingDecision(data)
            arguments
                data (1,1) struct
            end
            required=["K0","K1","K2","PDCCHSlot","PDSCHSlot", ...
                "PUSCHSlot","FeedbackSlot","TDDLegal","ProcessingLegal", ...
                "ResourceLegal","SourceDCIEventID"];
            for field=required
                if ~isfield(data,field)
                    error("sixgr:mac:MissingTimingSource", ...
                        "Timing decision is missing %s.",field);
                end
            end
            obj.K0=data.K0; obj.K1=data.K1; obj.K2=data.K2;
            obj.PDCCHSlot=data.PDCCHSlot; obj.PDSCHSlot=data.PDSCHSlot;
            obj.PUSCHSlot=data.PUSCHSlot; obj.FeedbackSlot=data.FeedbackSlot;
            obj.TDDLegal=logical(data.TDDLegal);
            obj.ProcessingLegal=logical(data.ProcessingLegal);
            obj.ResourceLegal=logical(data.ResourceLegal);
            obj.SourceDCIEventID=string(data.SourceDCIEventID);
            obj.DecisionID=sixgr.l2.mac.MACHash.of(data);
        end
    end
end
