classdef IQImbalanceProfile
%IQIMBALANCEPROFILE Bounded widely-linear IQ/DC model.

    methods(Static)
        function coefficients = coefficients(gainImbalance_dB, phaseImbalance_deg)
            gain = 10^(double(gainImbalance_dB)/20);
            phase = double(phaseImbalance_deg)*pi/180;
            alpha = 0.5*(1 + gain*exp(-1j*phase));
            beta = 0.5*(1 - gain*exp(1j*phase));
            coefficients = struct("Alpha", alpha, "Beta", beta, ...
                "IRR_dB", 20*log10(abs(alpha)/max(abs(beta),realmin)));
        end

        function [y, evidence] = apply(x, gainImbalance_dB, ...
                phaseImbalance_deg, dcOffset)
            if any(~isfinite(x(:))) || ~isfinite(real(dcOffset)) || ...
                    ~isfinite(imag(dcOffset))
                error("RF:NonFiniteSamples", ...
                    "IQ imbalance stage requires finite samples and offset.");
            end
            c = sixgr.rf.runtime.IQImbalanceProfile.coefficients( ...
                gainImbalance_dB, phaseImbalance_deg);
            y = c.Alpha.*x + c.Beta.*conj(x) + cast(dcOffset,"like",x);
            evidence = c;
            evidence.DCOffset = dcOffset;
            evidence.Source = "configured_transmitter_impairment";
        end

        function estimate = estimateFromCalibration(inputSamples, outputSamples)
            x = double(inputSamples(:));
            y = double(outputSamples(:));
            if numel(x) ~= numel(y) || numel(x) < 2 || ...
                    any(~isfinite(x)) || any(~isfinite(y))
                error("RF:IQCalibrationMissing", ...
                    "Measured input/output calibration samples are required.");
            end
            A = [x conj(x) ones(size(x))];
            if rcond(A'*A) < 1e-12
                error("RF:IQCalibrationMissing", ...
                    "IQ calibration waveform is rank deficient.");
            end
            theta = A\y;
            estimate = struct("Alpha",theta(1),"Beta",theta(2), ...
                "DCOffset",theta(3),"Source","measured_calibration_samples");
        end

        function y = compensate(x, estimate)
            if ~isstruct(estimate) || ~all(isfield(estimate, ...
                    ["Alpha","Beta","DCOffset","Source"])) || ...
                    ~contains(string(estimate.Source),"measured")
                error("RF:IQCalibrationMissing", ...
                    "Strict IQ compensation requires measured calibration state.");
            end
            a = complex(estimate.Alpha);
            b = complex(estimate.Beta);
            d = complex(estimate.DCOffset);
            determinant = abs(a)^2-abs(b)^2;
            if abs(determinant) <= eps
                error("RF:IQCalibrationMissing", ...
                    "IQ calibration matrix is singular.");
            end
            z = x-d;
            y = (conj(a).*z-b.*conj(z))./determinant;
        end
    end
end
