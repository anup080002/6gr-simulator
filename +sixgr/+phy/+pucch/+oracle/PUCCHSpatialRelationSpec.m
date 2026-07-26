classdef PUCCHSpatialRelationSpec
    %PUCCHSPATIALRELATIONSPEC Independent active/stale-state check.
    methods (Static)
        function out = resolve(activeID,requestedID,stateStale)
            active=double(activeID)==double(requestedID) && ~logical(stateStale);
            out=struct("Active",active,"SelectedRelationID", ...
                double(requestedID),"Metadata", ...
                sixgr.phy.pucch.oracle.SpecSupport.metadata( ...
                "PUCCHSpatialRelationSpec"));
        end
    end
end
