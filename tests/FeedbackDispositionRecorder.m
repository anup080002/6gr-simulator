classdef FeedbackDispositionRecorder < handle
    % Test-only scheduler call recorder; never used by simulation execution.
    properties
        Updates = {}
    end
    methods
        function updateAfterRx(obj,feedback)
            obj.Updates{end+1}=feedback;
        end
    end
end
