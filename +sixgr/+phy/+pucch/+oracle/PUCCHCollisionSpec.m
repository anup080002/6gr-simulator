classdef PUCCHCollisionSpec
    %PUCCHCOLLISIONSPEC Independent exact RE-key collision rule.
    methods (Static)
        function out = resolve(keysA,keysB,cyclicShiftA,cyclicShiftB,occA,occB)
            overlap=~isempty(intersect(string(keysA),string(keysB)));
            orthogonal=overlap && (double(cyclicShiftA)~=double(cyclicShiftB) || ...
                double(occA)~=double(occB));
            out=struct("ExactREOverlap",overlap,"Orthogonal",orthogonal, ...
                "Collision",overlap && ~orthogonal,"Metadata", ...
                sixgr.phy.pucch.oracle.SpecSupport.metadata( ...
                "PUCCHCollisionSpec"));
        end
    end
end
