classdef SROccasionSpec
    %SROCCASIONSPEC Independent periodic SR occasion rule.
    methods (Static)
        function out = resolve(period,offset,slot,pending,prohibited)
            period=double(period);offset=double(offset);slot=double(slot);
            occasion=period>0 && slot>=offset && mod(slot-offset,period)==0;
            transmit=occasion && logical(pending) && ~logical(prohibited);
            out=struct("IsOccasion",occasion,"Transmit",transmit, ...
                "Metadata",sixgr.phy.pucch.oracle.SpecSupport.metadata( ...
                "SROccasionSpec"));
        end
    end
end
