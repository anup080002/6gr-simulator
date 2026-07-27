classdef RRCUE < sixgr.l3.rrc18.RRCEndpoint
    %RRCUE Strict bounded UE RRC endpoint.
    methods
        function obj=RRCUE(ueID,vectorRoot,timerConfig)
            obj@sixgr.l3.rrc18.RRCEndpoint( ...
                "UE",ueID,vectorRoot,timerConfig);
        end
    end
end
