classdef PUCCHSpatialRelationState
    %PUCCHSPATIALRELATIONSTATE Active causal PUCCH beam/spatial state.

    properties (SetAccess=private)
        Data
        Digest
    end

    methods
        function obj = PUCCHSpatialRelationState(data)
            required = ["SpatialRelationID","ActiveSpatialRelationID", ...
                "ReferenceSignalType","ReferenceSignalID", ...
                "PathlossReferenceRSID","P0PUCCHID","ClosedLoopIndex", ...
                "StateAgeSlots","MaximumAgeSlots","SelectedBeamID", ...
                "AppliedBeamID"];
            sixgr.phy.pucch.UCIReport.requireFields(data,required);
            if double(data.StateAgeSlots) > double(data.MaximumAgeSlots)
                error("sixgr:phy:pucch:StaleSpatialRelation", ...
                    "PUCCH spatial relation is stale.");
            end
            if double(data.SpatialRelationID) ~= ...
                    double(data.ActiveSpatialRelationID)
                error("sixgr:phy:pucch:InactiveSpatialRelation", ...
                    "Requested PUCCH spatial relation is inactive.");
            end
            obj.Data = data;
            obj.Digest = sixgr.phy.pucch.PUCCHUtil.hash(data);
        end
    end

    methods (Static)
        function result = resolveVector(row)
            result = struct("Valid",true,"ErrorID","", ...
                "BeamSource","NONE","PathlossReferenceRSID",NaN);
            stale = sixgr.phy.pucch.PUCCHUtil.truth(row,"StateStale",false);
            active = sixgr.phy.pucch.PUCCHUtil.number( ...
                row,"ActiveSpatialRelationID");
            requested = sixgr.phy.pucch.PUCCHUtil.number( ...
                row,"RequestedSpatialRelationID");
            if stale
                result.Valid = false;
                result.ErrorID = "sixgr:phy:pucch:StaleSpatialRelation";
                return;
            end
            if active ~= requested
                result.Valid = false;
                result.ErrorID = "sixgr:phy:pucch:InactiveSpatialRelation";
                return;
            end
            result.BeamSource = sixgr.phy.pucch.PUCCHUtil.text( ...
                row,"ReferenceSignalType");
            result.PathlossReferenceRSID = sixgr.phy.pucch.PUCCHUtil.number( ...
                row,"PathlossReferenceRSID");
        end
    end
end
