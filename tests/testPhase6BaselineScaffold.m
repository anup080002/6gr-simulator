function ok = testPhase6BaselineScaffold()
%TESTPHASE6BASELINESCAFFOLD Guard the Phase 6 baseline and truth gates.

setup6GRSimToolkit("Verbose", false);
root = fileparts(fileparts(mfilename("fullpath")));

requiredFiles = [
    "docs/phase6_spec_traceability.csv"
    "docs/phase6_advanced_phy_architecture.md"
    "docs/phase6_no_oracle_policy.md"
    "docs/phase6_known_limitations.md"
    "docs/phase6_operating_instructions.md"
    "docs/phase6_test_plan.md"
    "phase6_baseline/phase6_branch_metadata.csv"
    "phase6_baseline/existing_csi_source_map.csv"
    "phase6_baseline/existing_srs_source_map.csv"
    "phase6_baseline/existing_tracking_source_map.csv"
    "phase6_baseline/existing_mimo_source_map.csv"
    "phase6_baseline/existing_mumimo_source_map.csv"
    "phase6_baseline/current_oracle_fields.csv"
    "phase6_baseline/current_call_graph.graphml"
    "phase6_baseline/current_call_graph.svg"
    "phase6_baseline/existing_phase6_gaps.md"
    ];
for i = 1:numel(requiredFiles)
    assertNonemptyFile(root, requiredFiles(i));
end

trace = readtable(relPath(root, "docs/phase6_spec_traceability.csv"), ...
    "TextType", "string", "VariableNamingRule", "preserve", "Delimiter", ",");
needed = ["requirement_id","subsystem","specification","specification_version", ...
    "clause","table","normative_or_implementation_specific", ...
    "requirement_summary","production_function","independent_reference", ...
    "runtime_evidence","unit_test","implementation_status"];
assert(all(ismember(needed, string(trace.Properties.VariableNames))), ...
    "Phase 6 traceability CSV is missing required columns.");
for prefix = ["PH6-RRC","PH6-CSIRS","PH6-SRS","PH6-PUCCH2","PH6-RANK2","PH6-DLMU","PH6-ULMU","PH6-NOORACLE","PH6-GATES"]
    assert(any(startsWith(string(trace.requirement_id), prefix)), ...
        "Phase 6 traceability must include %s rows.", prefix);
end
assert(any(contains(lower(string(trace.normative_or_implementation_specific)), "normative")), ...
    "Phase 6 traceability must distinguish normative requirements.");
assert(any(contains(lower(string(trace.normative_or_implementation_specific)), "implementation-specific")), ...
    "Phase 6 traceability must distinguish implementation-specific algorithms.");
assert(any(contains(string(trace.specification_version), "v18.8.0")), ...
    "Phase 6 traceability must pin visible 3GPP Release 18 spec versions.");
assert(any(contains(lower(string(trace.implementation_status)), "pending")), ...
    "Phase 6 scaffold must keep pending limitations explicit.");
assert(~any(strcmpi(strtrim(string(trace.implementation_status)), "complete")), ...
    "Phase 6 scaffold must not mark rows simply complete.");

oracle = readtable(relPath(root, "phase6_baseline/current_oracle_fields.csv"), ...
    "TextType", "string", "VariableNamingRule", "preserve", "Delimiter", ",");
assert(ismember("phase6_status", string(oracle.Properties.VariableNames)), ...
    "Phase 6 oracle map must include phase6_status.");
assert(any(contains(lower(string(oracle.phase6_status)), ["forbidden","must_not"], "IgnoreCase", true), "all"), ...
    "Phase 6 oracle map must name forbidden or must-not-use boundaries.");

mapFiles = requiredFiles(contains(requiredFiles, "source_map.csv"));
for i = 1:numel(mapFiles)
    T = readtable(relPath(root, mapFiles(i)), "TextType", "string", ...
        "VariableNamingRule", "preserve", "Delimiter", ",");
    assert(ismember("classification", string(T.Properties.VariableNames)), ...
        "Missing classification column in %s.", mapFiles(i));
    lowered = lower(string(T.classification));
    assert(any(contains(lowered, ["partial","diagnostic","incomplete","helper"], "IgnoreCase", true), "all"), ...
        "Source map %s must distinguish non-complete surfaces.", mapFiles(i));
end

gaps = string(fileread(relPath(root, "phase6_baseline/existing_phase6_gaps.md")));
assert(contains(gaps, "Phase6Ok") && contains(lower(gaps), "false"), ...
    "Phase 6 gaps must explicitly keep Phase6Ok false until runtime evidence exists.");
assert(contains(gaps, "configured rank") && contains(gaps, "effective rank"), ...
    "Phase 6 gaps must preserve configured-vs-effective rank distinction.");
assert(contains(gaps, "MU-MIMO") && contains(gaps, "overlapping PRBs"), ...
    "Phase 6 gaps must avoid same-slot-only MU-MIMO claims.");

status = sixgr.runtime.Phase6TruthEvaluator.evaluate(struct("Phase5Ok", true));
assert(~logical(status.Phase6Ok), ...
    "Phase6Ok must stay false when Phase 6 runtime evidence gates are missing.");
assert(~logical(status.FullScenarioResultOk), ...
    "Full scenario ResultOk must not be inferred from Phase6Ok.");
assert(any(status.FailureCodes == "Phase6RrcConfigurationOk_false"), ...
    "Phase 6 failure codes must expose the missing RRC configuration gate.");

allFlags = struct();
gateNames = sixgr.runtime.Phase6TruthEvaluator.gateNames();
for i = 1:numel(gateNames)
    allFlags.(char(gateNames(i))) = true;
end
statusAll = sixgr.runtime.Phase6TruthEvaluator.evaluate(allFlags);
assert(logical(statusAll.Phase6Ok), "All Phase 6 gates true must produce Phase6Ok=true.");
assert(~logical(statusAll.FullScenarioResultOk), ...
    "Even a true Phase6Ok must not auto-promote to full scenario ResultOk.");

ok = true;
end

function assertNonemptyFile(root, rel)
path = relPath(root, rel);
assert(exist(path, "file") == 2, "Missing Phase 6 artifact: %s", rel);
info = dir(path);
assert(~isempty(info) && info.bytes > 0, "Phase 6 artifact is empty: %s", rel);
end

function path = relPath(root, rel)
path = fullfile(root, strrep(char(rel), "/", filesep));
end
