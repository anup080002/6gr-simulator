classdef RLCBearerIdentity
    %RLCBEARERIDENTITY Immutable RLC entity ownership tuple.
    properties (SetAccess = immutable)
        UEID (1,1) string
        BearerID (1,1) string
        Direction (1,1) string
        ConfigurationEpoch (1,1) double
        EntityID (1,1) string
    end
    methods
        function obj=RLCBearerIdentity(ueID,bearerID,direction,epoch)
            direction=upper(string(direction));
            if ~ismember(direction,["DL","UL"]) || epoch<1 || epoch~=floor(epoch)
                error("sixgr:rlc:InvalidIdentity","Invalid RLC ownership tuple.");
            end
            obj.UEID=string(ueID); obj.BearerID=string(bearerID);
            obj.Direction=direction; obj.ConfigurationEpoch=epoch;
            obj.EntityID=join([obj.UEID,obj.BearerID,direction,string(epoch)],"|");
        end
    end
end
