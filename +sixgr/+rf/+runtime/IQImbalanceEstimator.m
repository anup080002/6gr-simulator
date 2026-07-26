classdef IQImbalanceEstimator
%IQIMBALANCEESTIMATOR Pilot/calibration-derived widely-linear estimator.

    methods(Static)
        function estimate = estimate(referencePilots, observedPilots, ...
                referencePlane)
            plane = sixgr.rf.runtime.RFReferencePlane.validate(referencePlane);
            estimate = sixgr.rf.runtime.IQImbalanceProfile. ...
                estimateFromCalibration(referencePilots, observedPilots);
            estimate.ReferencePlane = plane;
            estimate.Estimator = "pilot_widely_linear_least_squares";
            estimate.CalibrationSHA256 = ...
                sixgr.rf.runtime.RFStateTrace.sampleHash(observedPilots);
            values = [estimate.Alpha; estimate.Beta; estimate.DCOffset];
            bytes = typecast([real(values(:));imag(values(:))], "uint8");
            estimate.EstimateID = string(sixgr.util.sha256Hex(bytes));
        end
    end
end
