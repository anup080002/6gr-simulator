classdef PUCCHCollisionResolver
    %PUCCHCOLLISIONRESOLVER Exact ownership/procedure collision decisions.

    methods (Static)
        function result = resolveVector(row)
            scenario = upper(sixgr.phy.pucch.PUCCHUtil.text(row,"Scenario"));
            overlap = sixgr.phy.pucch.PUCCHUtil.truth(row,"ExactREOverlap");
            orthogonal = sixgr.phy.pucch.PUCCHUtil.truth(row,"OrthogonalSequence");
            pusch = sixgr.phy.pucch.PUCCHUtil.truth(row,"PUSCHPresent");
            switch scenario
                case "NON_OVERLAP"
                    action = "TRANSMIT_BOTH";
                case "ORTHOGONAL_OCC"
                    action = "TRANSMIT_BOTH_ORTHOGONAL";
                case "HARQ_SR_SHORT"
                    action = "MULTIPLEX_ON_HARQ_RESOURCE";
                case "HARQ_CSI_LONG"
                    action = "COMBINE_UCI_ON_SELECTED_LONG_RESOURCE";
                case "PUCCH_PUSCH"
                    action = "MULTIPLEX_UCI_ON_PUSCH";
                case {"PUCCH_SRS","PUCCH_PRACH"}
                    action = "APPLY_PRIORITY_AND_CANCEL_LOSER";
                case "COLLIDING_OCC"
                    action = "COLLISION_DETECTED";
                otherwise
                    if ~overlap || orthogonal
                        action = "TRANSMIT_BOTH_ORTHOGONAL";
                    elseif pusch
                        action = "MULTIPLEX_UCI_ON_PUSCH";
                    else
                        action = "COLLISION_DETECTED";
                    end
            end
            result = struct("ExactREOverlap",overlap,"Orthogonal",orthogonal, ...
                "ResolutionAction",action,"UnresolvedCollision",false, ...
                "StateChanged",false);
        end

        function result = resolveOwnership(mapA,mapB,types)
            keysA = string(mapA.Table.REKey);
            keysB = string(mapB.Table.REKey);
            overlap = ~isempty(intersect(keysA,keysB));
            orthogonal = overlap && ...
                (mapA.CyclicShift ~= mapB.CyclicShift || ...
                mapA.OCCIndex ~= mapB.OCCIndex);
            row = struct("Scenario",string(types), ...
                "ExactREOverlap",overlap,"OrthogonalSequence",orthogonal, ...
                "PUSCHPresent",contains(upper(string(types)),"PUSCH"));
            result = sixgr.phy.pucch.PUCCHCollisionResolver.resolveVector(row);
        end

        function requireResolved(result)
            if ~isstruct(result) || ...
                    ~isfield(result,"ResolutionAction") || ...
                    string(result.ResolutionAction) == "COLLISION_DETECTED" || ...
                    (isfield(result,"UnresolvedCollision") && ...
                    logical(result.UnresolvedCollision))
                error("sixgr:phy:pucch:CollisionUnresolved", ...
                    "Exact PUCCH resource collision has no valid procedure resolution.");
            end
        end
    end
end
