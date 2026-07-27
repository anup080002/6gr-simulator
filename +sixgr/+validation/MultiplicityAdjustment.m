classdef MultiplicityAdjustment
    %MULTIPLICITYADJUSTMENT Deterministic Holm family adjustment.
    methods (Static)
        function adjusted = holm(pValues)
            p = double(pValues(:));
            if any(~isfinite(p)|p<0|p>1)
                error("sixgr:validation:InvalidPValue", ...
                    "Holm adjustment requires finite p-values in [0,1].");
            end
            [sorted,order] = sort(p,"ascend");
            m = numel(p);
            sortedAdjusted = zeros(m,1);
            previous = 0;
            for index = 1:m
                candidate = min(1,(m-index+1)*sorted(index));
                previous = max(previous,candidate);
                sortedAdjusted(index) = previous;
            end
            adjusted = zeros(size(p));
            adjusted(order) = sortedAdjusted;
            adjusted = reshape(adjusted,size(pValues));
        end
    end
end
