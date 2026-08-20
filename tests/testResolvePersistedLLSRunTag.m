function ok = testResolvePersistedLLSRunTag()
%TESTRESOLVEPERSISTEDLLSRUNTAG Storage paths must not replace logical RunID.

setup6GRSimToolkit("Verbose", false);
root = string(tempname) + "_recovery_copy";
mkdir(fullfile(root, "meta"));
mkdir(fullfile(root, "air_interface", "csv"));
cleanup = onCleanup(@() rmdir(root, "s")); %#ok<NASGU>

sixgr.util.jsonWrite(fullfile(root, "meta", "scenario_manifest.json"), ...
    struct("RunFolder", char(root), "ConfigHash", repmat('a', 1, 64)));
logicalRunTag = "immutable_waveform_run";
T = table(repmat(logicalRunTag, 2, 1), repmat(logicalRunTag, 2, 1), ...
    'VariableNames', {'RunID','RunTag'});
sixgr.util.csvWriteTable(fullfile(root, "air_interface", "csv", ...
    "dl_fixed_link_campaign_trials.csv"), T);

[resolved, evidence] = sixgr.truth.resolvePersistedLLSRunTag(root);
assert(resolved == logicalRunTag && ...
    string(evidence.Authority) == "primary_trial_tables", ...
    "Primary runtime identity must override the recovery folder name.");

conflicting = table("different_run", ...
    'VariableNames', {'RunID'});
sixgr.util.csvWriteTable(fullfile(root, "air_interface", "csv", ...
    "ul_fixed_link_campaign_trials.csv"), conflicting);
localAssertIdentifier(@() sixgr.truth.resolvePersistedLLSRunTag(root), ...
    "sixgr:truth:recover:PersistedRunTagIdentityMismatch");
delete(fullfile(root, "air_interface", "csv", ...
    "ul_fixed_link_campaign_trials.csv"));

manifest = struct("RunFolder", char(root), "RunTag", char(logicalRunTag), ...
    "ConfigHash", repmat('a', 1, 64));
sixgr.util.jsonWrite(fullfile(root, "meta", "scenario_manifest.json"), manifest);
[resolvedMetadataMatch, evidenceMetadataMatch] = ...
    sixgr.truth.resolvePersistedLLSRunTag(root);
assert(resolvedMetadataMatch == logicalRunTag && ...
    string(evidenceMetadataMatch.Authority) == "primary_trial_tables", ...
    "Matching explicit metadata and primary identity must remain valid.");

ok = true;
end

function localAssertIdentifier(fcn, expected)
try
    fcn();
catch ME
    assert(string(ME.identifier) == string(expected), ...
        "Expected %s, observed %s (%s).", expected, ME.identifier, ME.message);
    return;
end
error("testResolvePersistedLLSRunTag:MissingError", ...
    "Expected typed failure %s.", expected);
end
