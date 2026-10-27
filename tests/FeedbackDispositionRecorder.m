classdef FeedbackDispositionRecorder < handle
    % Test-only scheduler call recorder; never used by simulation execution.
    properties
        Updates = {}
        TransitionUpdates = {}
    end
    methods
        function updateAfterRx(obj,feedback)
            obj.Updates{end+1}=feedback;
        end
        function observeMCSTransitionFeedback(obj,feedback)
            obj.TransitionUpdates{end+1}=feedback;
        end
    end
end
