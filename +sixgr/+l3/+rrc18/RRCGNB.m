classdef RRCGNB < sixgr.l3.rrc18.RRCEndpoint
    %RRCGNB Strict bounded gNB RRC endpoint.
    methods
        function obj=RRCGNB(ueID,vectorRoot,timerConfig)
            obj@sixgr.l3.rrc18.RRCEndpoint( ...
                "GNB",ueID,vectorRoot,timerConfig);
        end
    end
end
