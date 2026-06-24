function ok = testPhase5DocumentationSet()
%TESTPHASE5DOCUMENTATIONSET Guard required Phase 5 baseline documentation.

root = fileparts(fileparts(mfilename("fullpath")));

requiredDocs = [
    "docs/phase5_connected_mode_architecture.md"
    "docs/phase5_rrc_setup_complete.md"
    "docs/phase5_srb1_stack.md"
    "docs/phase5_dedicated_configuration.md"
    "docs/phase5_ue_specific_pdcch.md"
    "docs/phase5_connected_dci.md"
    "docs/phase5_pucch_format0.md"
    "docs/phase5_pucch_format1.md"
    "docs/phase5_harq_ack_codebook.md"
    "docs/phase5_dl_harq.md"
    "docs/phase5_ul_harq.md"
    "docs/phase5_soft_combining.md"
    "docs/phase5_scheduling_request.md"
    "docs/phase5_bsr_phr.md"
    "docs/phase5_dynamic_scheduler.md"
    "docs/phase5_link_adaptation_olla.md"
    "docs/phase5_pdsch_chain.md"
    "docs/phase5_pusch_chain.md"
    "docs/phase5_packet_lineage.md"
    "docs/phase5_ue2_slot24_root_cause.md"
    "docs/phase5_no_oracle_policy.md"
    "docs/phase5_test_plan.md"
    "docs/phase5_operating_instructions.md"
    "docs/phase5_known_limitations.md"
    "docs/phase5_spec_traceability.csv"
    ];

for ii = 1:numel(requiredDocs)
    assertNonemptyFile(root, requiredDocs(ii));
end

requiredBaseline = [
    "phase5_baseline/phase5_branch_metadata.csv"
    "phase5_baseline/existing_rrc_connected_source_map.csv"
    "phase5_baseline/existing_pdcch_source_map.csv"
    "phase5_baseline/existing_pdsch_pusch_source_map.csv"
    "phase5_baseline/existing_pucch_source_map.csv"
    "phase5_baseline/existing_harq_source_map.csv"
    "phase5_baseline/existing_scheduler_source_map.csv"
    "phase5_baseline/existing_packet_flow_source_map.csv"
    "phase5_baseline/current_oracle_fields.csv"
    "phase5_baseline/current_call_graph.graphml"
    "phase5_baseline/current_call_graph.svg"
    "phase5_baseline/existing_phase5_gaps.md"
    ];

for ii = 1:numel(requiredBaseline)
    assertNonemptyFile(root, requiredBaseline(ii));
end

requiredUe2 = [
    "debug/ue2_slot24/reproduction_command.txt"
    "debug/ue2_slot24/reproduction_context.json"
    "debug/ue2_slot24/stage_hashes.csv"
    "debug/ue2_slot24/re_accounting.csv"
    "debug/ue2_slot24/tbs_reconciliation.csv"
    "debug/ue2_slot24/receiver_stage_comparison.csv"
    "debug/ue2_slot24/llr_comparison.csv"
    "debug/ue2_slot24/decoder_comparison.csv"
    "debug/ue2_slot24/root_cause.md"
    "debug/ue2_slot24/raw/README.md"
    ];

for ii = 1:numel(requiredUe2)
    assertNonemptyFile(root, requiredUe2(ii));
end

trace = readtable(relPath(root, "docs/phase5_spec_traceability.csv"), ...
    "TextType", "string", "VariableNamingRule", "preserve", "Delimiter", ",");
needed = ["requirement_id","subsystem","specification","specification_version", ...
    "clause","table","requirement_summary","production_function", ...
    "independent_reference","runtime_evidence","unit_test","implementation_status"];
assert(all(ismember(needed, string(trace.Properties.VariableNames))), ...
    "Phase 5 spec traceability CSV is missing required columns.");
assert(any(startsWith(string(trace.requirement_id), "PH5-RRC")), ...
    "Phase 5 traceability must include RRC rows.");
assert(any(startsWith(string(trace.requirement_id), "PH5-PDCCH")), ...
    "Phase 5 traceability must include PDCCH rows.");
assert(any(startsWith(string(trace.requirement_id), "PH5-PUCCH")), ...
    "Phase 5 traceability must include PUCCH rows.");
assert(any(startsWith(string(trace.requirement_id), "PH5-HARQ")), ...
    "Phase 5 traceability must include HARQ rows.");
assert(any(contains(lower(string(trace.implementation_status)), "pending")), ...
    "Phase 5 traceability must keep pending limitations explicit.");
assert(~any(strcmpi(strtrim(string(trace.implementation_status)), "complete")), ...
    "This scaffold must not mark Phase 5 traceability rows simply complete.");
assert(any(contains(string(trace.specification_version), "v18.8.0")), ...
    "Phase 5 traceability must pin visible 3GPP Release 18 spec versions.");

arch = string(fileread(relPath(root, "docs/phase5_connected_mode_architecture.md")));
assert(count(arch, "sequenceDiagram") >= 6, ...
    "Phase 5 architecture must include the six requested sequence diagrams.");

limitations = string(fileread(relPath(root, "docs/phase5_known_limitations.md")));
for token = ["LLS_TEST_DATA_BEARER","rank 1","CSI-RS","SRS","TRS","MU-MIMO"]
    assert(contains(limitations, token), ...
        "Phase 5 known limitations must mention %s.", token);
end

gaps = string(fileread(relPath(root, "phase5_baseline/existing_phase5_gaps.md")));
assert(contains(gaps, "Phase5Ok") && contains(lower(gaps), "false"), ...
    "Phase 5 gaps must explicitly keep Phase5Ok false until runtime evidence exists.");

oracle = readtable(relPath(root, "phase5_baseline/current_oracle_fields.csv"), ...
    "TextType", "string", "VariableNamingRule", "preserve", "Delimiter", ",");
assert(ismember("phase5_status", string(oracle.Properties.VariableNames)), ...
    "Phase 5 oracle map must include phase5_status.");
assert(any(contains(lower(string(oracle.phase5_status)), "forbidden")) || ...
    any(contains(lower(string(oracle.phase5_status)), "must_not")), ...
    "Phase 5 oracle map must name forbidden or must-not-use boundaries.");

mapFiles = requiredBaseline(contains(requiredBaseline, "source_map.csv"));
for ii = 1:numel(mapFiles)
    T = readtable(relPath(root, mapFiles(ii)), "TextType", "string", ...
        "VariableNamingRule", "preserve", "Delimiter", ",");
    assert(ismember("classification", string(T.Properties.VariableNames)), ...
        "Missing classification column in %s.", mapFiles(ii));
    assert(any(contains(lower(string(T.classification)), ["incomplete","partial","diagnostic","configuration","unsupported"]), "all"), ...
        "Source map %s must distinguish non-complete surfaces.", mapFiles(ii));
end

ue2 = string(fileread(relPath(root, "debug/ue2_slot24/root_cause.md")));
assert(contains(lower(ue2), "pending live reproduction"), ...
    "UE2 slot-24 root-cause file must remain pending until live evidence exists.");

ok = true;
end

function assertNonemptyFile(root, rel)
path = relPath(root, rel);
assert(exist(path, "file") == 2, "Missing Phase 5 artifact: %s", rel);
info = dir(path);
assert(~isempty(info) && info.bytes > 0, "Phase 5 artifact is empty: %s", rel);
end

function path = relPath(root, rel)
path = fullfile(root, strrep(char(rel), "/", filesep));
end
