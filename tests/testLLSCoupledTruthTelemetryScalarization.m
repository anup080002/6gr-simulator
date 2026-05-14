function ok = testLLSCoupledTruthTelemetryScalarization()
%TESTLLSCOUPLEDTRUTHTELEMETRYSCALARIZATION Serving trace rows must stay scalar.

setup6GRSimToolkit("Verbose", false);

prototype = struct( ...
    "Slot", NaN, "ServingBeamIndex", NaN, "WidebandCQI", NaN, ...
    "InterferenceMode", "", "LOSFlag", false, "CQIDerivedModulation", "");
row = prototype;
row.Slot = [9; 10];
row.ServingBeamIndex = [4 7];
row.WidebandCQI = [3 5];
row.InterferenceMode = ["full_buffer"; "peer_loaded"];
row.LOSFlag = [true false];
row.CQIDerivedModulation = ["QPSK"; "16QAM"];

normalized = sixgr.truth.CoupledTruthRuntime.normalizeTelemetryRowToPrototype(row, prototype);
T = struct2table(normalized, "AsArray", true);

assert(istable(T) && height(T) == 1, ...
    "Serving-trace scalarization must always materialize exactly one telemetry row.");
assert(isscalar(double(normalized.Slot)) && double(normalized.Slot) == 9, ...
    "Serving-trace scalarization must keep the first scalar slot stamp.");
assert(isscalar(double(normalized.ServingBeamIndex)) && double(normalized.ServingBeamIndex) == 4, ...
    "Serving-trace scalarization must keep a scalar serving-beam index.");
assert(isscalar(double(normalized.WidebandCQI)) && double(normalized.WidebandCQI) == 3, ...
    "Serving-trace scalarization must keep a scalar CQI value.");
assert(islogical(normalized.LOSFlag) && isscalar(normalized.LOSFlag) && logical(normalized.LOSFlag), ...
    "Serving-trace scalarization must keep LOSFlag scalar.");
assert(isscalar(string(normalized.InterferenceMode)) && string(normalized.InterferenceMode) == "full_buffer", ...
    "Serving-trace scalarization must keep a scalar interference-mode token.");
assert(isscalar(string(normalized.CQIDerivedModulation)) && string(normalized.CQIDerivedModulation) == "QPSK", ...
    "Serving-trace scalarization must keep a scalar modulation label.");

ok = true;
end
