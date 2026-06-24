function ok = testPhase7ScientificReadinessScaffold()
%TESTPHASE7SCIENTIFICREADINESSSCAFFOLD Guard Phase 7 readiness artifacts.

setup6GRSimToolkit("Verbose", false);
root = fileparts(fileparts(mfilename("fullpath")));

requiredFiles = [
    "docs/phase7_spec_traceability.csv"
    "phase7_baseline/channel_source_map.csv"
    "phase7_baseline/rf_source_map.csv"
    "phase7_baseline/mobility_source_map.csv"
    "phase7_baseline/kpi_source_map.csv"
    "phase7_baseline/energy_source_map.csv"
    "phase7_baseline/profiler_source_map.csv"
    "phase7_baseline/output_source_map.csv"
    "phase7_baseline/current_channel_call_graph.graphml"
    "phase7_baseline/current_channel_call_graph.svg"
    "phase7_baseline/remaining_gaps.md"
    ];
for i = 1:numel(requiredFiles)
    assertNonemptyFile(root, requiredFiles(i));
end

trace = readtable(relPath(root, "docs/phase7_spec_traceability.csv"), ...
    "TextType", "string", "VariableNamingRule", "preserve", "Delimiter", ",");
needed = ["requirement_id","category","specification","version","clause","table", ...
    "requirement_summary","implementation_function","independent_reference", ...
    "runtime_artifact","validation_test","status"];
assert(all(ismember(needed, string(trace.Properties.VariableNames))), ...
    "Phase 7 traceability CSV is missing required columns.");
for category = ["normative standard requirement","simulator design choice", ...
        "implementation assumption","statistical-analysis choice","publication-quality recommendation"]
    assert(any(strcmp(string(trace.category), category)), ...
        "Phase 7 traceability must include category %s.", category);
end
assert(any(contains(string(trace.version), "v18.8.0")), ...
    "Phase 7 traceability must pin visible 3GPP Release 18 spec versions.");
assert(any(contains(lower(string(trace.status)), ["pending","blocked"], "IgnoreCase", true), "all"), ...
    "Phase 7 traceability must keep pending or blocked limitations explicit.");
assert(~any(strcmpi(strtrim(string(trace.status)), "complete")), ...
    "Phase 7 scaffold must not mark rows simply complete.");

mapFiles = requiredFiles(contains(requiredFiles, "source_map.csv"));
for i = 1:numel(mapFiles)
    T = readtable(relPath(root, mapFiles(i)), "TextType", "string", ...
        "VariableNamingRule", "preserve", "Delimiter", ",");
    assert(ismember("classification", string(T.Properties.VariableNames)), ...
        "Missing classification column in %s.", mapFiles(i));
    lowered = lower(string(T.classification));
    assert(any(contains(lowered, ["partial","diagnostic","incomplete","configuration-only"], "IgnoreCase", true), "all"), ...
        "Source map %s must distinguish non-complete surfaces.", mapFiles(i));
end

gaps = string(fileread(relPath(root, "phase7_baseline/remaining_gaps.md")));
assert(contains(gaps, "Phase7Ok") && contains(lower(gaps), "false"), ...
    "Phase 7 gaps must explicitly keep Phase7Ok false until runtime evidence exists.");
assert(contains(gaps, "32400") && contains(gaps, "500-slot"), ...
    "Phase 7 gaps must record the full-route-vs-short-diagnostic mobility boundary.");

scenarioPath = relPath(root, "simulator/configs/scenarios/lls_mobile_2ue_100kmh_1sector_full_capture.yaml");
scfg = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>
sixgr.truth.buildProvenanceManifest(scfg, tmp);
report = sixgr.analytics.buildPhase7ReadinessArtifacts(scfg, tmp);
assert(isfield(report, "Gates") && isstruct(report.Gates), ...
    "Phase 7 readiness report must return gate status.");

requiredRuntimeFiles = [
    "configuration/csv/configuration_conflicts.csv"
    "storage/csv/capture_policy.csv"
    "geometry/csv/trajectory_geometry.csv"
    "mobility/csv/trajectory_resolution.csv"
    "mobility/csv/inter_ue_distance_validation.csv"
    "reports/csv/phase7_truth_gates.csv"
    "reports/json/phase7_truth_gates.json"
    "reports/final/final_publication_readiness.md"
    ];
for i = 1:numel(requiredRuntimeFiles)
    assertNonemptyFile(tmp, requiredRuntimeFiles(i));
end

conflicts = readtable(relPath(tmp, "configuration/csv/configuration_conflicts.csv"), ...
    "TextType", "string", "VariableNamingRule", "preserve", "Delimiter", ",");
scsRow = strcmp(string(conflicts.Concept), "scs_khz");
assert(any(scsRow) && ~any(strcmp(string(conflicts.ConflictStatus(scsRow)), "conflict_unresolved")), ...
    "Phase 7 config audit must normalize 30 kHz and 30000 Hz SCS values before conflict checks.");

traj = readtable(relPath(tmp, "mobility/csv/trajectory_resolution.csv"), ...
    "TextType", "string", "VariableNamingRule", "preserve", "Delimiter", ",");
assert(double(traj.RequiredTraversalSlots(1)) >= 32000, ...
    "Expected full 50m-to-500m route to require roughly 32400 slots.");
assert(double(traj.ConfiguredSlots(1)) == 500, ...
    "Scenario fixture must remain the requested 500-slot short diagnostic.");
assert(~localAsLogical(traj.FullTrajectoryExecutedOk(1)), ...
    "Phase 7 must not mark a 500-slot short diagnostic as full trajectory execution.");
assert(strcmp(string(traj.Status(1)), "SHORT_MOBILITY_DIAGNOSTIC"), ...
    "Short mobility run must be labeled as a diagnostic.");

interUE = readtable(relPath(tmp, "mobility/csv/inter_ue_distance_validation.csv"), ...
    "TextType", "string", "VariableNamingRule", "preserve", "Delimiter", ",");
assert(double(interUE.ClosestDistance_m(1)) < double(interUE.MinDistanceConfigured_m(1)), ...
    "Opposing UE traces should expose a closest-approach conflict.");
assert(~localAsLogical(interUE.InterUeConstraintResolvedOk(1)), ...
    "Unresolved inter-UE distance conflict must fail closed.");

capture = readtable(relPath(tmp, "storage/csv/capture_policy.csv"), ...
    "TextType", "string", "VariableNamingRule", "preserve", "Delimiter", ",");
assert(~localAsLogical(capture.CapturePolicyTruthfulOk(1)), ...
    "Full-capture profile with raw IQ requested must fail the truthful capture-policy gate.");

gates = readtable(relPath(tmp, "reports/csv/phase7_truth_gates.csv"), ...
    "TextType", "string", "VariableNamingRule", "preserve", "Delimiter", ",");
assert(~localAsLogical(gates.Phase7Ok(1)), "Phase7Ok must fail closed for readiness-only evidence.");
assert(~localAsLogical(gates.ResultOk(1)), "ResultOk must not pass when Phase7Ok is false.");
assert(~localAsLogical(gates.PublicationReadinessOk(1)), ...
    "PublicationReadinessOk must remain false without all Phase 7 gates.");
assert(strcmp(string(gates.ScopeLabel(1)), "SCOPED_IMPLEMENTATION_VALIDATION"), ...
    "Phase 7 gate output must carry the scoped-validation label.");

allFlags = struct();
gateNames = sixgr.runtime.Phase7TruthEvaluator.gateNames();
for i = 1:numel(gateNames)
    allFlags.(char(gateNames(i))) = true;
end
for name = ["Phase1Ok","Phase2Ok","Phase3Ok","Phase4Ok","Phase5Ok","Phase6Ok"]
    allFlags.(char(name)) = true;
end
allFlags.PublicationReadinessOk = true;
statusAll = sixgr.runtime.Phase7TruthEvaluator.evaluate(allFlags);
assert(logical(statusAll.Phase7Ok), "All Phase 7 gates true must produce Phase7Ok=true.");
assert(logical(statusAll.ResultOk), "All phase gates and Phase 7 gates true must produce ResultOk=true.");
assert(logical(statusAll.PublicationReadinessOk), ...
    "Publication readiness must pass only when requested and all Phase 7 gates pass.");

ok = true;
end

function assertNonemptyFile(root, rel)
path = relPath(root, rel);
assert(exist(path, "file") == 2, "Missing Phase 7 artifact: %s", rel);
info = dir(path);
assert(~isempty(info) && info.bytes > 0, "Phase 7 artifact is empty: %s", rel);
end

function path = relPath(root, rel)
path = fullfile(root, strrep(char(rel), "/", filesep));
end

function out = localAsLogical(value)
if islogical(value)
    out = logical(value(1));
elseif isnumeric(value)
    value = double(value(1));
    out = isfinite(value) && value ~= 0;
else
    token = lower(strtrim(string(value(1))));
    out = token == "1" || token == "true" || token == "yes" || token == "pass";
end
end
