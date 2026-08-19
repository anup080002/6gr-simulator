classdef SequentialStoppingPolicy
    %SEQUENTIALSTOPPINGPOLICY Fail-closed optional-stopping decisions.
    methods (Static)
        function out = evaluate(errorCount,trialCount,design,lookIndex)
            if nargin < 4, lookIndex = 1; end
            if ~(isstruct(design)&&isscalar(design))
                error("sixgr:validation:InvalidSequentialDesign", ...
                    "A scalar sequential design is required.");
            end
            k = double(errorCount); n = double(trialCount);
            if ~(isscalar(k)&&isscalar(n)&&isfinite(k)&&isfinite(n)&& ...
                    k==fix(k)&&n==fix(n)&&n>=0&&k>=0&&k<=n)
                error("sixgr:validation:InvalidBinomialCounts", ...
                    "Sequential counts require integer 0 <= errors <= trials.");
            end
            lookIndex = double(lookIndex);
            interval = localInterval(k,n,design,lookIndex);
            pointStatus = "RUNNING";
            stopReason = "NONE";
            if n < double(design.MinTrials)
                stopReason = "MIN_TRIALS_NOT_MET";
            else
                zeroPass = false;
                if k == 0
                    zeroPass = interval.Upper <= ...
                        double(design.TargetZeroErrorUpperBound);
                end
                ciPass = k >= double(design.MinErrors) && ...
                    interval.HalfWidth <= double(design.TargetHalfWidth);
                if zeroPass
                    pointStatus = "CENSORED_COMPLETE";
                    stopReason = "ZERO_ERROR_UPPER_BOUND_MET";
                elseif ciPass
                    pointStatus = "COMPLETE";
                    stopReason = "MIN_ERRORS_AND_CI_MET";
                elseif n >= double(design.MaxTrials)
                    pointStatus = "INCOMPLETE_MAX_TRIALS";
                    stopReason = "MAX_TRIALS_REACHED_INCOMPLETE";
                end
            end
            out = interval;
            out.PointStatus = sixgr.validation.PointStatus.parse(pointStatus);
            out.StopReason = sixgr.validation.StopReason.parse(stopReason);
            out.Stopped = ismember(out.PointStatus, ...
                ["COMPLETE","CENSORED_COMPLETE","INCOMPLETE_MAX_TRIALS"]);
        end
    end
end

function interval = localInterval(k,n,design,lookIndex)
if n == 0
    interval = struct("Method","NOT_COMPUTED", ...
        "ConfidenceLevel",double(design.LookConfidenceLevel), ...
        "Sidedness","NOT_COMPUTED","Convention","ERROR_COUNT", ...
        "ErrorCount",k,"TrialCount",n,"Estimate",NaN, ...
        "Lower",NaN,"Upper",NaN,"HalfWidth",NaN, ...
        "LookIndex",lookIndex,"AlphaSpent",0, ...
        "DesignID",string(design.DesignID));
    return;
end
args = {"LookIndex",lookIndex, ...
    "AlphaSpent",double(design.AlphaPerLook), ...
    "DesignID",string(design.DesignID)};
if k == 0 && n >= double(design.MinTrials)
    interval = sixgr.validation.BinomialIntervalEngine.exactUpper( ...
        k,n,double(design.LookConfidenceLevel),args{:});
else
    interval = sixgr.validation.BinomialIntervalEngine.compute( ...
        k,n,double(design.LookConfidenceLevel), ...
        string(design.IntervalMethod),args{:});
end
end
