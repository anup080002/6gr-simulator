classdef ZeroErrorCensorPolicy
    %ZEROERRORCENSORPOLICY One-sided exact high-SNR censor rule.
    methods (Static)
        function out = evaluate(trialCount,confidenceLevel,targetUpper)
            interval = sixgr.validation.BinomialIntervalEngine.exactUpper( ...
                0,trialCount,confidenceLevel);
            out = interval;
            out.TargetUpper = double(targetUpper);
            out.Passed = interval.Upper <= double(targetUpper);
            if out.Passed
                out.PointStatus = "CENSORED_COMPLETE";
                out.StopReason = "ZERO_ERROR_UPPER_BOUND_MET";
            else
                out.PointStatus = "RUNNING";
                out.StopReason = "NONE";
            end
        end
    end
end
