function correlation = LSPSpatialCorrelation(separation_m, correlationDistance_m)
%LSPSPATIALCORRELATION Exponential bounded analytical spatial correlation.

arguments
    separation_m double {mustBeFinite,mustBeNonnegative}
    correlationDistance_m double {mustBeFinite,mustBePositive}
end
correlation = exp(-double(separation_m) ./ double(correlationDistance_m));
end
