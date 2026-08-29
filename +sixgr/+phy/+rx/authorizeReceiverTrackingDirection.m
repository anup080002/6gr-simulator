function authorized = authorizeReceiverTrackingDirection( ...
        trackingContext, measurementDirection, consumerDirection)
%AUTHORIZERECEIVERTRACKINGDIRECTION Enforce receiver-local sync authority.
%   DL TRS is measured by the UE receiver.  Its timing/CFO estimate is not
%   an uplink gNB receiver correction in either FDD or TDD.  TDD channel
%   reciprocity does not make the two receiver clocks, propagation signs,
%   or time-alignment control loops identical.  The UL receiver obtains
%   time alignment from PRACH/TA and UL SRS/DM-RS observations.
%
%   This resolver is intentionally duplex-neutral.  Duplexing determines
%   which resources may execute; endpoint and direction determine whether
%   a measured synchronization state may be consumed.

arguments
    trackingContext (1,1) struct
    measurementDirection {mustBeTextScalar}
    consumerDirection {mustBeTextScalar}
end

measurementDirection = upper(strtrim(string(measurementDirection)));
consumerDirection = upper(strtrim(string(consumerDirection)));
if ~any(measurementDirection == ["DL","UL"])
    error("sixgr:phy:rx:InvalidTrackingMeasurementDirection", ...
        "Receiver-tracking measurement direction must be DL or UL, got '%s'.", ...
        measurementDirection);
end
if ~any(consumerDirection == ["DL","UL"])
    error("sixgr:phy:rx:InvalidTrackingConsumerDirection", ...
        "Receiver-tracking consumer direction must be DL or UL, got '%s'.", ...
        consumerDirection);
end

authorized = trackingContext;
compatible = measurementDirection == consumerDirection;
authorized.TrackingMeasurementDirection = char(measurementDirection);
authorized.TrackingConsumerDirection = char(consumerDirection);
authorized.TrackingDirectionCompatible = logical(compatible);
authorized.TrackingAuthorityPolicy = ...
    "receiver_endpoint_and_direction_must_match";

authorized.ObservedTRSTimingEstimateAvailable = logical( ...
    sixgr.util.structGet(trackingContext, "TRSTimingEstimateAvailable", false));
authorized.ObservedTRSTimingEstimate_samples = double( ...
    sixgr.util.structGet(trackingContext, "TRSTimingEstimate_samples", NaN));
authorized.ObservedTRSCFOEstimateAvailable = logical( ...
    sixgr.util.structGet(trackingContext, "TRSCFOEstimateAvailable", false));
authorized.ObservedTRSEstimatedCFO_Hz = double( ...
    sixgr.util.structGet(trackingContext, "TRSEstimatedCFO_Hz", NaN));

if compatible
    authorized.TrackingAuthorityStatus = "authorized_same_receiver_direction";
    authorized.TrackingAuthorityReason = "";
    authorized.TRSTimingApplicationScope = measurementDirection + "_RECEIVER_ONLY";
    authorized.TRSCFOApplicationScope = measurementDirection + "_RECEIVER_ONLY";
    return;
end

% Preserve the actual measurement above for audit, but do not expose it as
% an executable correction to the opposite-direction receiver.
authorized.TRSTimingEstimateAvailable = false;
authorized.TRSTimingEstimate_samples = NaN;
authorized.TRSCFOEstimateAvailable = false;
authorized.TRSEstimatedCFO_Hz = NaN;
authorized.TRSEstimatedOscillatorCFO_Hz = NaN;
authorized.TrackingAuthorityStatus = "rejected_cross_direction_receiver_state";
authorized.TrackingAuthorityReason = ...
    "measurement_and_consumer_receiver_directions_differ";
authorized.TRSTimingApplicationScope = measurementDirection + "_RECEIVER_ONLY";
authorized.TRSCFOApplicationScope = measurementDirection + "_RECEIVER_ONLY";
end
