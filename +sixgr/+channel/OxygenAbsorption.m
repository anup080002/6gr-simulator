classdef OxygenAbsorption
%OXYGENABSORPTION Simplified ITU-R P.676 oxygen absorption helper.
%
% This helper models gaseous oxygen attenuation as an additive large-scale
% loss for mmWave paths. It is intentionally narrow: below 6 GHz it returns
% negligible attenuation; near the 60 GHz absorption line it returns about
% 15 dB/km under standard atmosphere, matching the expected engineering
% range for simulator truth metadata.

    methods(Static)
        function gamma_dBkm = specificAttenuation_dBkm(fc_GHz)
            fc_GHz = double(fc_GHz);
            if ~(isscalar(fc_GHz) && isfinite(fc_GHz) && fc_GHz > 0)
                gamma_dBkm = NaN;
                return;
            end
            if fc_GHz <= 6
                gamma_dBkm = 0;
                return;
            end
            baseline = 0.01 * max(fc_GHz - 6, 0) / 10;
            oxygenLine = 15.0 .* exp(-0.5 .* ((fc_GHz - 60) ./ 6.5).^2);
            highBandTail = 0.08 .* max(fc_GHz - 45, 0) ./ 10;
            gamma_dBkm = max(0, baseline + oxygenLine + highBandTail);
        end

        function loss_dB = pathLoss_dB(fc_Hz, distance_m)
            fc_GHz = double(fc_Hz) ./ 1e9;
            distance_km = double(distance_m) ./ 1000;
            gamma = sixgr.channel.OxygenAbsorption.specificAttenuation_dBkm(fc_GHz);
            loss_dB = double(gamma) .* max(0, double(distance_km));
        end
    end
end
