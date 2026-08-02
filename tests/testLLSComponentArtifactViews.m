function ok = testLLSComponentArtifactViews()
%TESTLLSCOMPONENTARTIFACTVIEWS Component mirrors preserve canonical bytes.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
root = string(tempname);
mkdir(fullfile(root, "air_interface", "csv"));
mkdir(fullfile(root, "reports", "image"));
cleanup = onCleanup(@() rmdir(root, "s")); %#ok<NASGU>

sourceCSV = fullfile(root, "air_interface", "csv", "prach_trials.csv");
writetable(table((1:3).', 'VariableNames', {'Trial'}), sourceCSV);
sourcePNG = fullfile(root, "reports", "image", "prach_correlation.png");
imwrite(uint8(reshape(0:63, 8, 8)), sourcePNG);
sourceSVG = fullfile(root, "reports", "image", "prach_legacy.svg");
fid = fopen(sourceSVG, "w");
assert(fid >= 0);
fprintf(fid, '<svg xmlns="http://www.w3.org/2000/svg"></svg>');
fclose(fid);

out = sixgr.truth.publishComponentArtifactViews(root, ...
    "Enabled", true, "Required", true);
assert(out.Ok);
assert(out.PublishedCount == 2, ...
    "Only the CSV and PNG should be published into the component view.");
assert(out.SkippedLegacySVGCount == 1, ...
    "Legacy SVG must be counted and excluded from component views.");
assert(isfile(fullfile(root, "prach", "csv", "prach_trials.csv")));
assert(isfile(fullfile(root, "prach", "image", "prach_correlation.png")));
assert(~isfile(fullfile(root, "prach", "image", "prach_legacy.svg")));
assert(all(out.Rows.MirrorOnly));
assert(all(out.Rows.CanonicalAuthorityRetained));
assert(all(out.Rows.CanonicalSHA256 == out.Rows.PublishedSHA256));
assert(all(out.Rows.PublishStatus == "PUBLISHED_HASH_VERIFIED"));
assert(isfile(fullfile(root, "reports", "csv", ...
    "component_artifact_publication_manifest.csv")));

repeat = sixgr.truth.publishComponentArtifactViews(root, ...
    "Enabled", true, "Required", true);
assert(repeat.Ok && repeat.PublishedCount == out.PublishedCount, ...
    "Repeated publication must be deterministic and must not recurse into mirrors.");

for masterName = ["master_sinr_sweep.yaml", "master_geometry_based.yaml"]
    scenario = sixgr.lls6g.config.loadScenarioConfig(fullfile(pwd, ...
        "simulator", "configs", "scenarios", masterName));
    assert(logical(scenario.get( ...
        "canonical_control.output.component_artifact_views.enabled", ...
        false)), ...
        "%s must explicitly enable component artifact views.", masterName);
    assert(logical(scenario.get( ...
        "canonical_control.output.component_artifact_views.required", ...
        false)), ...
        "%s must make hash-verified component publication required.", ...
        masterName);
    assert(string(scenario.get( ...
        "canonical_control.output.component_artifact_views.mirror_mode", ...
        "")) == ...
        "byte_identical_hash_verified", ...
        "%s must preserve the canonical byte-identity policy.", masterName);
end
ok = true;
end
