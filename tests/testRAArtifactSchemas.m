function ok = testRAArtifactSchemas()
tmp = tempname;
res = sixgr.phy.ra.runFourStepRA(raStrictAnchorConfig(), ...
    "RunFolder", tmp, "RunId", "test_ra_artifacts", "WriteArtifacts", true);
assert(logical(res.StrictOk), "Artifact schema test requires a strict successful RA run.");
csvDir = fullfile(tmp, "control", "csv");
required = ["ra_attempts.csv","ra_state_transitions.csv","msg1_prach_detection.csv", ...
    "msg2_rar_trials.csv","msg2_pdcch_candidates.csv","msg3_pusch_trials.csv", ...
    "msg4_contention_resolution.csv","ra_timer_events.csv","ra_negative_trials.csv", ...
    "ra_collision_trials.csv","ra_oracle_guard.csv"];
for ii = 1:numel(required)
    path = fullfile(csvDir, required(ii));
    assert(exist(path, "file") == 2, "Missing RA artifact: %s", path);
    T = readtable(path, "TextType", "string");
    if ~any(required(ii) == ["ra_negative_trials.csv","ra_collision_trials.csv"])
        assert(height(T) > 0, "Required positive RA artifact must have rows: %s", required(ii));
    end
end
attempts = readtable(fullfile(csvDir, "ra_attempts.csv"), "TextType", "string");
assert(all(ismember(["RunId","RABindingSource","RARBytesHex","Msg3ContentionIdentity", ...
    "FailureReason","UsedOracleFields","StrictOk"], string(attempts.Properties.VariableNames))), ...
    "ra_attempts.csv schema is missing required columns.");
figDir = fullfile(tmp, "reports", "figures");
figs = ["ra_procedure_timeline.png","msg1_prach_correlation.png","msg2_rar_pdcch_candidates.png", ...
    "msg3_pusch_constellation.png","msg4_contention_resolution_flow.svg","ra_collision_outcome.png"];
for ii = 1:numel(figs)
    assert(exist(fullfile(figDir, figs(ii)), "file") == 2, "Missing RA figure: %s", figs(ii));
end
ok = true;
end
