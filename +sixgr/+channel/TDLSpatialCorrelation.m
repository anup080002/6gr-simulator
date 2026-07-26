function matrix = TDLSpatialCorrelation(nPorts, adjacentCorrelation)
%TDLSPATIALCORRELATION Bounded Toeplitz analytical TDL correlation floor.
%
% This is explicitly a correlation-matrix profile and is not labelled as
% full geometry/angle coupling.

arguments
    nPorts (1,1) double {mustBeInteger,mustBePositive}
    adjacentCorrelation (1,1) double {mustBeFinite}
end
if abs(adjacentCorrelation) >= 1
    error("CHANNEL:InvalidTDLProfile", ...
        "Adjacent TDL correlation magnitude must be less than one.");
end
index = 0:nPorts-1;
matrix = adjacentCorrelation .^ abs(index(:) - index);
end
