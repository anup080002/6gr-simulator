function ok = testPhase4DocumentationSet()
%TESTPHASE4DOCUMENTATIONSET Guard required Phase 4 documentation artifacts.

required = [
    "docs/phase4_random_access_architecture.md"
    "docs/phase4_decoded_rach_configuration.md"
    "docs/phase4_ssb_ro_mapping.md"
    "docs/phase4_prach_occasion_derivation.md"
    "docs/phase4_prach_sequence_and_waveform.md"
    "docs/phase4_prach_power_control.md"
    "docs/phase4_prach_receiver.md"
    "docs/phase4_ra_rnti.md"
    "docs/phase4_rar_pdcch_pdsch.md"
    "docs/phase4_rar_mac_pdu.md"
    "docs/phase4_timing_advance.md"
    "docs/phase4_msg3_chain.md"
    "docs/phase4_msg3_harq.md"
    "docs/phase4_msg4_contention_resolution.md"
    "docs/phase4_collision_handling.md"
    "docs/phase4_no_oracle_policy.md"
    "docs/phase4_test_plan.md"
    "docs/phase4_operating_instructions.md"
    "docs/phase4_known_limitations.md"
    "docs/phase4_spec_traceability.csv"
    ];

for ii = 1:numel(required)
    path = fullfile(pwd, required(ii));
    assert(exist(path, "file") == 2, "Missing Phase 4 documentation artifact: %s", required(ii));
    info = dir(path);
    assert(~isempty(info) && info.bytes > 0, "Phase 4 documentation artifact is empty: %s", required(ii));
end

trace = readtable(fullfile(pwd, "docs", "phase4_spec_traceability.csv"), "TextType", "string");
needed = ["requirement_id","subsystem","specification","specification_version", ...
    "clause","table","requirement_summary","production_function", ...
    "independent_reference","runtime_evidence","unit_test","implementation_status"];
assert(all(ismember(needed, string(trace.Properties.VariableNames))), ...
    "Phase 4 spec traceability CSV is missing required columns.");
assert(any(startsWith(string(trace.requirement_id), "PH4-OWN")), ...
    "Phase 4 traceability must include decoded-configuration ownership rows.");
assert(any(startsWith(string(trace.requirement_id), "PH4-MSG")), ...
    "Phase 4 traceability must include Msg1/Msg2/Msg3/Msg4 rows.");
assert(any(contains(lower(string(trace.implementation_status)), "pending")), ...
    "Phase 4 traceability must keep pending limitations explicit until Phase4Ok is complete.");

ok = true;
end
