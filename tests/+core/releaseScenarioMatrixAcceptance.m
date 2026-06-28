function ok = releaseScenarioMatrixAcceptance()
%RELEASESCENARIOMATRIXACCEPTANCE Validate minimal release scenario matrix coverage.

matrixPath = fullfile(pwd, "simulator", "configs", "scenarios", "release_acceptance_matrix.yaml");
cfg = sixgr.lls6g.config.readConfigFile(matrixPath);
sixgr.lls6g.config.validateScenarioConfig(cfg, "Kind", "matrix", "AllowPartial", false, "Context", matrixPath);

scenarios = string(cfg.scenarios(:));
assert(numel(scenarios) >= 10, "Release acceptance matrix must cover at least ten scenario anchors.");
for i = 1:numel(scenarios)
    assert(exist(fullfile(pwd, scenarios(i)), "file") == 2, ...
        "Release acceptance scenario path does not exist: %s", scenarios(i));
end

tokens = lower(join(scenarios, " "));
requiredFamilies = ["dl", "ul", "control", "csi", "random_access", ...
    "harq", "interference", "rank", "mimo", "longrun"];
for i = 1:numel(requiredFamilies)
    assert(contains(tokens, requiredFamilies(i)), ...
        "Release acceptance matrix missing coverage token '%s'.", requiredFamilies(i));
end
assert(strcmp(string(cfg.meta.matrix_id), "release_acceptance_10of10_v1"), ...
    "Release acceptance matrix ID must be stable for archive reproducibility.");
ok = true;
end
