function Hsnap = spatialSnapshotsFromMeasurementState(measurement)
%SPATIALSNAPSHOTSFROMMEASUREMENTSTATE Consume canonical measured CSI axes.
%
% CSIMeasurementState.ChannelEstimate is already Nrx-by-Nport-by-Nsnapshot.
% This boundary exists to prevent consumers from accidentally applying the
% K-by-L resource-grid converter a second time and collapsing antenna ports.

if ~isa(measurement, "sixgr.phy.mimo.CSIMeasurementState")
    error("sixgr:mimo:MissingMeasurementState", ...
        "Spatial CSI analysis requires an immutable measured CSI state.");
end
if string(measurement.ChannelEstimateConvention) ~= "rx_by_tx_by_snapshot"
    error("sixgr:mimo:InvalidMeasurementConvention", ...
        "Unsupported CSI measurement channel convention %s.", ...
        measurement.ChannelEstimateConvention);
end

Hsnap = double(measurement.ChannelEstimate);
if ismatrix(Hsnap)
    Hsnap = reshape(Hsnap, size(Hsnap, 1), size(Hsnap, 2), 1);
end
if ndims(Hsnap) > 3 || isempty(Hsnap) || ...
        ~all(isfinite(real(Hsnap(:)))) || ~all(isfinite(imag(Hsnap(:))))
    error("sixgr:mimo:InvalidMeasurementState", ...
        "CSI measurement channel must be finite Nrx-by-Nport-by-Nsnapshot data.");
end
end
