function [dmrsSym, info] = applyPDSCHDMRSEPREDifference(dmrsSym, cfg)
% The configured quantity follows the conformance-table convention:
%   data EPRE / DM-RS EPRE in dB = data EPRE - DM-RS EPRE.
path = "phy.pdsch.dmrs.dataToDMRSEPREDifference_dB";
rawDifference = sixgr.util.structGet(cfg, char(path), []);
if isempty(rawDifference)
    difference_dB = 0;
    source = "default_zero_db";
else
    if ~(isnumeric(rawDifference) && isreal(rawDifference) && isscalar(rawDifference) && isfinite(rawDifference))
        error("sixgr:phy:dl:PDSCHDMRSEPREDifferenceInvalid", ...
            "%s must be a finite real numeric scalar.", char(path));
    end
    difference_dB = double(rawDifference);
    source = path;
end

configuredPowerBoost_dB = -difference_dB;
if abs(difference_dB + 3) <= 1e-12
    % Conformance FRC tables express data-to-DM-RS EPRE as -3 dB while
    % the corresponding exact reference-symbol amplitude is beta=sqrt(2).
    amplitudeScale = sqrt(2);
    powerScale = 2;
    scalePolicy = "normative_minus3_db_beta_sqrt2";
else
    amplitudeScale = 10.^(configuredPowerBoost_dB ./ 20);
    powerScale = amplitudeScale.^2;
    scalePolicy = "literal_configured_db_ratio";
end
if ~(isfinite(amplitudeScale) && amplitudeScale > 0 && isfinite(powerScale) && powerScale > 0)
    error("sixgr:phy:dl:PDSCHDMRSEPREDifferenceInvalid", ...
        "%s=%g dB produces a non-finite or non-positive DM-RS scale.", ...
        char(path), difference_dB);
end
realizedPowerBoost_dB = 10 .* log10(powerScale);
realizedDifference_dB = -realizedPowerBoost_dB;

dmrsSym = dmrsSym .* cast(amplitudeScale, "like", dmrsSym);
info = struct( ...
    "ContractVersion", "PDSCHDMRSEPREDifference/v1", ...
    "Source", source, ...
    "DataToDMRSEPREDifference_dB", double(difference_dB), ...
    "ConfiguredDMRSPowerBoost_dB", double(configuredPowerBoost_dB), ...
    "RealizedDataToDMRSEPREDifference_dB", double(realizedDifference_dB), ...
    "DMRSPowerBoost_dB", double(realizedPowerBoost_dB), ...
    "DMRSAmplitudeScale", double(amplitudeScale), ...
    "DMRSPowerScale", double(powerScale), ...
    "Applied", logical(abs(difference_dB) > 1e-12), ...
    "NormativeMinus3dBBetaApplied", logical(scalePolicy == "normative_minus3_db_beta_sqrt2"), ...
    "ScalePolicy", scalePolicy, ...
    "Equation", "normative_minus3_db_uses_beta_sqrt2_otherwise_10_power_minus_delta_db_over_20");
end
