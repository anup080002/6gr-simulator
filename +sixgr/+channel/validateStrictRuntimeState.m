function validateStrictRuntimeState(state)
%VALIDATESTRICTRUNTIMESTATE Fail closed on inconsistent channel runtime state.
%
% This validator is intentionally executed before waveform allocation.  It
% validates provenance, geometry, model-profile, absolute-power,
% interference, mobility and ray-contract state without changing the input
% state or consuming random numbers.

arguments
    state (1,1) struct
end

kind = upper(localRequiredText(state, "Kind", ...
    "CHANNEL:UnsupportedProfile", "Runtime-state kind is required."));
switch kind
    case "OBSERVED_GEOMETRY"
        localRequireFields(state, ["Distance3D_m","SignedDoppler_Hz"], ...
            "CHANNEL:MissingObservedGeometry");
        if ~isfinite(state.Distance3D_m) || state.Distance3D_m < 0 || ...
                ~isfinite(state.SignedDoppler_Hz)
            error("CHANNEL:MissingObservedGeometry", ...
                "Observed distance and signed Doppler must be finite.");
        end

    case "PROVENANCE"
        observed = localRequiredLogical(state, "Observed", ...
            "CHANNEL:InvalidProvenance");
        provenance = lower(localRequiredText(state, "ProvenanceClass", ...
            "CHANNEL:InvalidProvenance", "ProvenanceClass is required."));
        if observed && ismember(provenance, ...
                ["configured","configured_oracle","model_backfill","reconstructed"])
            error("CHANNEL:InvalidProvenance", ...
                "Configured or reconstructed values cannot be labelled observed.");
        end

    case "COMPARISON"
        expectedSource = localRequiredText(state, "ExpectedSourceID", ...
            "CHANNEL:CircularComparison", "ExpectedSourceID is required.");
        actualSource = localRequiredText(state, "ActualSourceID", ...
            "CHANNEL:CircularComparison", "ActualSourceID is required.");
        if expectedSource == actualSource
            error("CHANNEL:CircularComparison", ...
                "Expected and applied values must have independent sources.");
        end

    case "COORDINATE_FRAME"
        frame = upper(localRequiredText(state, "Frame", ...
            "CHANNEL:InvalidCoordinateFrame", "Coordinate frame is required."));
        units = lower(localRequiredText(state, "Units", ...
            "CHANNEL:InvalidCoordinateFrame", "Coordinate units are required."));
        if frame ~= "ENU" || ~ismember(units, ["m","metre","meter"])
            error("CHANNEL:InvalidCoordinateFrame", ...
                "Strict geometry requires a pinned local ENU frame in metres.");
        end

    case "TOPOLOGY"
        localRequireFields(state, "CloneIDs", "CHANNEL:InvalidTopology");
        ids = string(state.CloneIDs(:));
        if any(strlength(ids) == 0) || numel(unique(ids)) ~= numel(ids)
            error("CHANNEL:InvalidTopology", ...
                "Every physical or cloned site must have a unique identity.");
        end

    case "DROP"
        inside = localRequiredLogical(state, "InsideDeclaredRegion", ...
            "CHANNEL:InvalidDropDistribution");
        if ~inside
            error("CHANNEL:InvalidDropDistribution", ...
                "UE position lies outside the declared drop region.");
        end

    case "LOS_SCENARIO"
        scenario = localRequiredText(state, "Scenario", ...
            "CHANNEL:UnknownLOSScenario", "LOS scenario is required.");
        supported = ["RMA","UMA","UMI","INH-OFFICE","INH_FACTORY", ...
            "INH-OFFICE-MIXED","INH-OFFICE-OPEN"];
        if ~ismember(upper(scenario), supported)
            error("CHANNEL:UnknownLOSScenario", ...
                "LOS scenario '%s' is not in the pinned registry.", scenario);
        end

    case "LOS_TRANSITION"
        authorized = localRequiredLogical(state, "CorrelatedTransition", ...
            "CHANNEL:InvalidLOSStateTransition");
        if ~authorized
            error("CHANNEL:InvalidLOSStateTransition", ...
                "LOS state changed without a correlated transition.");
        end

    case "PATHLOSS_APPLICABILITY"
        localRequireFields(state, ["Distance2D_m","MinimumDistance_m", ...
            "MaximumDistance_m","HUT_m","MinimumHUT_m","MaximumHUT_m"], ...
            "CHANNEL:PathlossOutOfRange");
        if state.Distance2D_m < state.MinimumDistance_m || ...
                state.Distance2D_m > state.MaximumDistance_m || ...
                state.HUT_m < state.MinimumHUT_m || ...
                state.HUT_m > state.MaximumHUT_m
            error("CHANNEL:PathlossOutOfRange", ...
                "Distance or antenna height is outside the pinned equation range.");
        end

    case "LSP_PROFILE"
        available = localRequiredLogical(state, "ProfileAvailable", ...
            "CHANNEL:MissingLSPProfile");
        if ~available
            error("CHANNEL:MissingLSPProfile", ...
                "No pinned LSP profile exists for the requested tuple.");
        end

    case "LSP_COVARIANCE"
        localRequireFields(state, "Covariance", "CHANNEL:InvalidLSPCovariance");
        covariance = double(state.Covariance);
        if isempty(covariance) || size(covariance,1) ~= size(covariance,2) || ...
                any(~isfinite(covariance), "all") || ...
                norm(covariance-covariance', "fro") > 1e-10 || ...
                min(eig((covariance+covariance')/2)) < -1e-10
            error("CHANNEL:InvalidLSPCovariance", ...
                "LSP cross-correlation matrix must be finite, symmetric and PSD.");
        end

    case "LSP_CONTINUITY"
        localRequireFields(state, ["ObservedDelta","MaximumDelta"], ...
            "CHANNEL:SpatialConsistencyViolation");
        if abs(state.ObservedDelta) > state.MaximumDelta
            error("CHANNEL:SpatialConsistencyViolation", ...
                "Adjacent LSP states violate the pinned continuity bound.");
        end

    case "O2I_MATERIAL"
        registered = localRequiredLogical(state, "MaterialRegistered", ...
            "CHANNEL:MissingO2IMaterialProfile");
        if ~registered
            error("CHANNEL:MissingO2IMaterialProfile", ...
                "O2I material mixture is not registered.");
        end

    case "INDOOR_DISTANCE"
        localRequireFields(state, ["IndoorDistance_m","MaximumIndoorDistance_m"], ...
            "CHANNEL:InvalidIndoorDistance");
        if state.IndoorDistance_m < 0 || ...
                state.IndoorDistance_m > state.MaximumIndoorDistance_m
            error("CHANNEL:InvalidIndoorDistance", ...
                "Indoor distance is outside the pinned material profile.");
        end

    case "OXYGEN_PROFILE"
        pinned = localRequiredLogical(state, "ProfilePinned", ...
            "CHANNEL:MissingOxygenProfile");
        if ~pinned
            error("CHANNEL:MissingOxygenProfile", ...
                "No pinned oxygen-absorption profile covers this frequency.");
        end

    case "TDL_PROFILE"
        profile = upper(localRequiredText(state, "Profile", ...
            "CHANNEL:InvalidTDLProfile", "A concrete TDL profile is required."));
        localRequireFields(state, ["DelaySpread_s","SupportedDelaySpreads_s"], ...
            "CHANNEL:InvalidTDLProfile");
        concrete = ismember(profile, ["TDL-A","TDL-B","TDL-C","TDL-D","TDL-E"]);
        delaySpread = double(state.DelaySpread_s);
        supported = double(state.SupportedDelaySpreads_s(:));
        if ~concrete || ~isfinite(delaySpread) || ...
                ~any(abs(supported-delaySpread) <= max(1e-15,eps(delaySpread)))
            error("CHANNEL:InvalidTDLProfile", ...
                "Unsupported concrete TDL profile or delay-spread tuple.");
        end

    case "CDL_PROFILE"
        profile = upper(localRequiredText(state, "Profile", ...
            "CHANNEL:InvalidCDLProfile", "A concrete CDL profile is required."));
        compatible = localRequiredLogical(state, "ArrayCompatible", ...
            "CHANNEL:InvalidCDLProfile");
        if ~ismember(profile, ["CDL-A","CDL-B","CDL-C","CDL-D","CDL-E"]) || ...
                ~compatible
            error("CHANNEL:InvalidCDLProfile", ...
                "Unsupported concrete CDL profile or antenna-array tuple.");
        end

    case "ANTENNA_ARRAY"
        localRequireFields(state, ["ElementCount","PanelDimensions"], ...
            "CHANNEL:InvalidAntennaArray");
        dimensions = double(state.PanelDimensions(:));
        if any(dimensions < 1) || any(mod(dimensions,1) ~= 0) || ...
                prod(dimensions) ~= double(state.ElementCount)
            error("CHANNEL:InvalidAntennaArray", ...
                "Element count and declared panel dimensions do not agree.");
        end

    case "PORT_PROJECTION"
        localRequireFields(state, ["InputPower","OutputPower","Tolerance"], ...
            "CHANNEL:PortProjectionMismatch");
        if abs(double(state.OutputPower)-double(state.InputPower)) > ...
                double(state.Tolerance)
            error("CHANNEL:PortProjectionMismatch", ...
                "Logical-to-physical port projection changed total power.");
        end

    case "DOPPLER_STATE"
        localRequireFields(state, ["ExpectedSign","ActualDoppler_Hz"], ...
            "CHANNEL:InvalidDopplerState");
        expectedSign = sign(double(state.ExpectedSign));
        actualSign = sign(double(state.ActualDoppler_Hz));
        if expectedSign ~= actualSign || ~isfinite(state.ActualDoppler_Hz)
            error("CHANNEL:InvalidDopplerState", ...
                "Observed Doppler sign is inconsistent with runtime geometry.");
        end

    case "POWER_REFERENCE"
        required = ["TxConnector_dBm","TxAntennaGain_dBi","PathGain_dB", ...
            "RxConnector_dBm","SampleReference"];
        localRequireFields(state, required, ...
            "CHANNEL:MissingAbsolutePowerReference");
        if strlength(string(state.SampleReference)) == 0
            error("CHANNEL:MissingAbsolutePowerReference", ...
                "Absolute sample reference is empty.");
        end

    case "POWER_RECONCILIATION"
        localRequireFields(state, ["ExpectedPower_dBm","MeasuredPower_dBm", ...
            "Tolerance_dB"], "CHANNEL:PowerLedgerMismatch");
        if abs(state.ExpectedPower_dBm-state.MeasuredPower_dBm) > state.Tolerance_dB
            error("CHANNEL:PowerLedgerMismatch", ...
                "Measured sample-domain power does not reconcile with the ledger.");
        end

    case "INTERFERENCE_LINK"
        complete = localRequiredLogical(state, "CompleteChannelState", ...
            "CHANNEL:InterferenceLinkMissing");
        if ~complete
            error("CHANNEL:InterferenceLinkMissing", ...
                "An overlapping interferer lacks waveform/channel/power state.");
        end

    case "INTERFERENCE_LEDGER"
        localRequireFields(state, ["Composite","Contributions","Tolerance"], ...
            "CHANNEL:InterferenceLedgerMismatch");
        composite = state.Composite(:);
        contributions = state.Contributions;
        if size(contributions,1) ~= numel(composite) || ...
                max(abs(composite-sum(contributions,2)),[],"all") > state.Tolerance
            error("CHANNEL:InterferenceLedgerMismatch", ...
                "Composite samples do not equal recorded link contributions.");
        end

    case "INTERFERENCE_COVARIANCE"
        localRequireFields(state, ["ExpectedCovariance","MeasuredCovariance", ...
            "Tolerance"], "CHANNEL:CovarianceMismatch");
        if ~isequal(size(state.ExpectedCovariance),size(state.MeasuredCovariance)) || ...
                max(abs(state.ExpectedCovariance-state.MeasuredCovariance),[],"all") ...
                > state.Tolerance
            error("CHANNEL:CovarianceMismatch", ...
                "Measured covariance is inconsistent with contribution samples.");
        end

    case "MOBILITY_MODEL"
        model = upper(localRequiredText(state, "Model", ...
            "CHANNEL:UnknownMobilityModel", "Mobility model is required."));
        if ~ismember(model, ["STATIC","LINEAR","RANDOM_WAYPOINT", ...
                "GAUSS_MARKOV","HST","TRACE"])
            error("CHANNEL:UnknownMobilityModel", ...
                "Mobility model '%s' is not registered.", model);
        end

    case "MOBILITY_TRAJECTORY"
        localRequireFields(state, ["VelocityBefore_mps","VelocityAfter_mps", ...
            "MaximumAcceleration_mps2","DeltaTime_s"], ...
            "CHANNEL:InvalidMobilityTrajectory");
        acceleration = norm(double(state.VelocityAfter_mps(:))- ...
            double(state.VelocityBefore_mps(:))) / double(state.DeltaTime_s);
        if ~isfinite(acceleration) || acceleration > state.MaximumAcceleration_mps2
            error("CHANNEL:InvalidMobilityTrajectory", ...
                "Velocity discontinuity exceeds the declared acceleration model.");
        end

    case "HANDOVER"
        eventPresent = localRequiredLogical(state, "DecodedEventPresent", ...
            "CHANNEL:MissingHandoverMeasurement");
        if ~eventPresent
            error("CHANNEL:MissingHandoverMeasurement", ...
                "Serving-cell change lacks a decoded measurement/control event.");
        end

    case "BLOCKAGE"
        profile = upper(localRequiredText(state, "Profile", ...
            "CHANNEL:UnsupportedBlockageProfile", ...
            "Blockage profile is required."));
        if ~ismember(profile, ["NONE","STATIC_SCREEN"])
            error("CHANNEL:UnsupportedBlockageProfile", ...
                "Blockage profile '%s' is not implemented.", profile);
        end

    case "RAY_CONTRACT"
        required = ["SceneSHA256","MaterialSHA256","Solver","SolverVersion"];
        localRequireFields(state, required, ...
            "CHANNEL:RayTracingContractMissing");
        if strlength(string(state.SceneSHA256)) ~= 64 || ...
                strlength(string(state.MaterialSHA256)) ~= 64
            error("CHANNEL:RayTracingContractMissing", ...
                "Ray-tracing scene/material hashes must be pinned SHA-256 values.");
        end

    case "RAY_RESULT"
        expected = localRequiredText(state, "ExpectedSceneSHA256", ...
            "CHANNEL:RayTracingHashMismatch", "Expected scene hash is required.");
        actual = localRequiredText(state, "ActualSceneSHA256", ...
            "CHANNEL:RayTracingHashMismatch", "Actual scene hash is required.");
        if expected ~= actual
            error("CHANNEL:RayTracingHashMismatch", ...
                "Ray result belongs to a different scene contract.");
        end

    case "STRICT_FALLBACK"
        used = localRequiredLogical(state, "FallbackUsed", ...
            "CHANNEL:StrictFallbackForbidden");
        if used
            error("CHANNEL:StrictFallbackForbidden", ...
                "Strict channel execution cannot substitute or clamp a profile.");
        end

    otherwise
        error("CHANNEL:UnsupportedProfile", ...
            "Unsupported strict runtime-state kind '%s'.", kind);
end
end

function localRequireFields(state, names, identifier)
names = string(names);
missing = names(~isfield(state, cellstr(names)));
if ~isempty(missing)
    error(identifier, "Required runtime-state field(s) missing: %s.", ...
        strjoin(missing, ", "));
end
end

function value = localRequiredText(state, name, identifier, message)
if ~isfield(state, name) || ~isscalar(string(state.(name))) || ...
        ismissing(string(state.(name))) || strlength(string(state.(name))) == 0
    error(identifier, message);
end
value = string(state.(name));
end

function value = localRequiredLogical(state, name, identifier)
if ~isfield(state, name) || ~isscalar(state.(name))
    error(identifier, "Required logical runtime-state field '%s' is missing.", name);
end
value = logical(state.(name));
end
