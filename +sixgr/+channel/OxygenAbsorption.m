classdef OxygenAbsorption
%OXYGENABSORPTION Pinned TR 38.901 V19.2.0 oxygen attenuation profile.

    methods(Static)
        function gamma_dBkm = specificAttenuation_dBkm(fc_GHz)
            fc_GHz = double(fc_GHz);
            if any(~isfinite(fc_GHz(:)) | fc_GHz(:) < 0 | fc_GHz(:) > 100)
                error("CHANNEL:MissingOxygenProfile", ...
                    "The pinned oxygen profile supports 0 through 100 GHz.");
            end
            frequency = [0 52 52.5 53 53.5 54 55 56 57 57.5 58 59 ...
                60 60.5 61 62 62.5 63 64 65 66 67 67.5 68 100];
            attenuation = [0 0 0.5 1 1.6 2.2 4 6.6 9.7 11.15 12.6 ...
                14.6 15 14.8 14.6 14.3 12.4 10.5 6.8 3.9 1.9 1 ...
                0.5 0 0];
            gamma_dBkm = interp1(frequency, attenuation, fc_GHz, "linear");
        end

        function loss_dB = pathLoss_dB(fc_Hz, distance_m)
            fc_GHz = double(fc_Hz) ./ 1e9;
            distance_km = double(distance_m) ./ 1000;
            if any(~isfinite(distance_km(:)) | distance_km(:) < 0)
                error("CHANNEL:InvalidGeometry", ...
                    "Oxygen path distance must be finite and nonnegative.");
            end
            gamma = sixgr.channel.OxygenAbsorption.specificAttenuation_dBkm(fc_GHz);
            loss_dB = double(gamma) .* double(distance_km);
        end
    end
end
