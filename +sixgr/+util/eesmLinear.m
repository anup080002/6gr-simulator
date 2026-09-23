function value = eesmLinear(gamma,beta)
%EESMLINEAR Equal-weight EESM without exponential underflow.
% Both arguments are linear ratios, not dB. This is only the numerical
% reduction; callers retain ownership of measurement and beta calibration.
arguments
    gamma {mustBeNumeric,mustBeReal,mustBeFinite,mustBeNonnegative,mustBeNonempty}
    beta (1,1) double {mustBeReal,mustBeFinite,mustBePositive}
end
gamma=double(gamma(:));
minimum=min(gamma);
% Factor exp(-minimum/beta) out of the mean before taking the logarithm.
% At least one shifted exponent is zero. expm1/log1p also preserve small
% differences near zero, without flooring/clipping any measured SINR.
value=minimum-beta*log1p(mean(expm1(-(gamma-minimum)/beta)));
end
