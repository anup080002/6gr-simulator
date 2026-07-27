classdef ServingCellMACContext < handle
    %SERVINGCELLMACCONTEXT Owns cell/BWP/TAG scoped MAC state.

    properties (SetAccess=private)
        UEID (1,1) double
        ServingCell (1,1) double
        ActiveDLBWP (1,1) double
        ActiveULBWP (1,1) double
        TAGID (1,1) double
        ConfigurationEpoch (1,1) double
    end

    methods
        function obj = ServingCellMACContext(ueID, cellID, dlBWP, ulBWP, tagID, epoch)
            arguments
                ueID (1,1) double {mustBeInteger,mustBeNonnegative}
                cellID (1,1) double {mustBeInteger,mustBeNonnegative}
                dlBWP (1,1) double {mustBeInteger,mustBeNonnegative}
                ulBWP (1,1) double {mustBeInteger,mustBeNonnegative}
                tagID (1,1) double {mustBeInteger,mustBeNonnegative}
                epoch (1,1) double {mustBeInteger,mustBeNonnegative}
            end
            obj.UEID=ueID; obj.ServingCell=cellID;
            obj.ActiveDLBWP=dlBWP; obj.ActiveULBWP=ulBWP;
            obj.TAGID=tagID; obj.ConfigurationEpoch=epoch;
        end
    end
end
