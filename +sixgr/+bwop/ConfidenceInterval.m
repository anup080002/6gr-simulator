classdef ConfidenceInterval
    %CONFIDENCEINTERVAL Exact campaign statistics helpers.

    methods (Static)
        function [low,high] = wilson(successes,trials,confidence)
            if nargin < 3, confidence = 0.95; end
            successes = double(successes); trials = double(trials);
            if any(trials(:) <= 0 | successes(:) < 0 | successes(:) > trials(:))
                error("sixgr:bwop:InvalidBinomialCounts", ...
                    "Wilson intervals require 0 <= successes <= trials and trials > 0.");
            end
            if ~(isscalar(confidence) && confidence > 0 && confidence < 1)
                error("sixgr:bwop:InvalidConfidenceLevel", ...
                    "Confidence level must be in (0,1).");
            end
            z = -sqrt(2)*erfcinv(2*((1+confidence)/2));
            p = successes./trials;
            denominator = 1 + z^2./trials;
            centre = (p + z^2./(2*trials))./denominator;
            radius = z.*sqrt(p.*(1-p)./trials + z^2./(4*trials.^2))./denominator;
            low = max(0,centre-radius);
            high = min(1,centre+radius);
        end

        function status = stoppingStatus(errors,blocks,minErrors,maxBlocks)
            if errors >= minErrors
                status = "TARGET_ERRORS_REACHED";
            elseif blocks >= maxBlocks
                status = "LOW_CONFIDENCE_MAX_BLOCKS";
            else
                status = "CONTINUE";
            end
        end
    end
end
