classdef ReferenceSignalCollisionResolver
    %REFERENCESIGNALCOLLISIONRESOLVER Exact RE-set collision decision.

    methods (Static)
        function result = resolve(resourceA,resourceB,orthogonalityProven)
            a = unique(double(resourceA(:)));
            b = unique(double(resourceB(:)));
            overlap = intersect(a,b);
            if isempty(overlap)
                disposition = "PASS";
            elseif logical(orthogonalityProven)
                disposition = "ORTHOGONAL_SHARE";
            else
                disposition = "COLLISION";
            end
            result = struct("Overlap",overlap, ...
                "OverlapCount",numel(overlap), ...
                "OrthogonalityProven",logical(orthogonalityProven), ...
                "Disposition",disposition, ...
                "Collision",~isempty(overlap)&&~logical(orthogonalityProven));
        end

        function result = resolveVector(row)
            a = sixgr.phy.rsla.RSLAUtil.numberList( ...
                sixgr.phy.rsla.RSLAUtil.text(row,"ResourceAZeroBasedREs",""));
            b = sixgr.phy.rsla.RSLAUtil.numberList( ...
                sixgr.phy.rsla.RSLAUtil.text(row,"ResourceBZeroBasedREs",""));
            result = sixgr.phy.rsla.ReferenceSignalCollisionResolver.resolve( ...
                a,b,sixgr.phy.rsla.RSLAUtil.truth(row, ...
                "OrthogonalityProven",false));
        end
    end
end
