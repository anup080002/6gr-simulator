classdef CommonPhaseErrorTracker
    %COMMONPHASEERRORTRACKER Measured PT-RS CPE correction façade.

    methods (Static)
        function result = correct(plan,phaseProfile)
            result = sixgr.phy.rsla.PTRSResourceEngine.measureAndCorrect( ...
                plan,phaseProfile);
            if ~result.CorrectionApplied
                error("RSLA:TrackingCorrectionNotApplied", ...
                    "Measured PT-RS CPE correction was not applied.");
            end
        end
    end
end
