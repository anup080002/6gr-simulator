classdef CSIMeasurementState
    %CSIMEASUREMENTSTATE Immutable measured CSI/SRS/SSB state.

    properties (SetAccess = immutable)
        MeasurementID (1,1) string
        UEID (1,1) string
        ResourceType (1,1) string
        ResourceID (1,1) string
        ResourceOrdinal (1,1) double
        Slot (1,1) double
        MaxAgeSlots (1,1) double
        ChannelEstimate
        NoiseVariance
        InterferenceCovariance
        Provenance (1,1) string
        Digest (1,1) string
    end

    methods
        function obj = CSIMeasurementState(options)
            arguments
                options.MeasurementID (1,1) string
                options.UEID (1,1) string
                options.ResourceType (1,1) string
                options.ResourceID (1,1) string
                options.ResourceOrdinal (1,1) double = NaN
                options.Slot (1,1) double {mustBeInteger,mustBeNonnegative}
                options.MaxAgeSlots (1,1) double {mustBeInteger,mustBeNonnegative}
                options.ChannelEstimate
                options.NoiseVariance
                options.InterferenceCovariance = []
                options.Provenance (1,1) string = "measured_runtime_reference_signal"
            end
            if isempty(options.ChannelEstimate)
                error("sixgr:mimo:MissingMeasurementState", ...
                    "Measured channel state is required.");
            end
            if ~startsWith(options.Provenance, "measured_")
                error("sixgr:mimo:BeamMeasurementOracleForbidden", ...
                    "Strict measurement provenance must begin with measured_.");
            end
            obj.MeasurementID = options.MeasurementID;
            obj.UEID = options.UEID;
            obj.ResourceType = options.ResourceType;
            obj.ResourceID = options.ResourceID;
            ordinal = double(options.ResourceOrdinal);
            if ~(isnan(ordinal) || (isfinite(ordinal) && ordinal >= 0 && ordinal == round(ordinal)))
                error("sixgr:mimo:BeamReportMismatch", ...
                    "ResourceOrdinal must be a nonnegative integer or NaN when no configured resource set exists.");
            end
            obj.ResourceOrdinal = ordinal;
            obj.Slot = options.Slot;
            obj.MaxAgeSlots = options.MaxAgeSlots;
            obj.ChannelEstimate = options.ChannelEstimate;
            obj.NoiseVariance = options.NoiseVariance;
            obj.InterferenceCovariance = options.InterferenceCovariance;
            obj.Provenance = options.Provenance;
            obj.Digest = sixgr.phy.mimo.MatrixContract.digest(options.ChannelEstimate);
        end

        function validateAt(obj, slotValue)
            age = double(slotValue) - obj.Slot;
            if age < 0 || age > obj.MaxAgeSlots
                error("sixgr:mimo:StaleMeasurementState", ...
                    "Measurement %s age %g exceeds limit %g.", ...
                    obj.MeasurementID, age, obj.MaxAgeSlots);
            end
        end
    end
end
