function ok = testPhase7ComponentArtifactPathResolution()
%TESTPHASE7COMPONENTARTIFACTPATHRESOLUTION Contract outputs live in components/.

root = tempname();
cleanup = onCleanup(@() localRemove(root)); %#ok<NASGU>
mkdir(fullfile(root, "reports", "csv"));
mkdir(fullfile(root, "components", "pdsch", "csv"));
mkdir(fullfile(root, "artifact_generation"));

coverage = table(1, 1, 0, 0, 1, 1, 0, 0, ...
    'VariableNames', {'tables_total','tables_available', ...
    'tables_policy_disabled','tables_missing','charts_total', ...
    'charts_available','charts_policy_disabled','charts_missing'});
sixgr.util.csvWriteTable(fullfile(root, "reports", "csv", ...
    "contract_materialization_coverage.csv"), coverage);

imageAudit = table("reports/image/example.png", "pass", true, false, true, ...
    'VariableNames', {'relative_path','status','readable', ...
    'blank_or_low_information','source_csv_exists'});
sixgr.util.csvWriteTable(fullfile(root, "reports", "csv", ...
    "all_image_artifact_audit.csv"), imageAudit);

componentPath = fullfile(root, "components", "pdsch", "csv", ...
    "pdsch_bler_curve.csv");
sixgr.util.csvWriteTable(componentPath, table(20, 0, ...
    'VariableNames', {'SNR_dB','BLER'}));
generation = table(true, "PASS", "pdsch/csv/pdsch_bler_curve.csv", ...
    'VariableNames', {'Required','Status','OutputRelativePath'});
sixgr.util.csvWriteTable(fullfile(root, "artifact_generation", ...
    "artifact_generation_results.csv"), generation);

result = sixgr.analytics.evaluatePublicationReadinessGates(struct(), root);
T = result.Tables.ArtifactCompleteness;
assert(logical(T.ArtifactCompletenessOk(1)), ...
    "A required PASS contract output under components/ must resolve exactly.");
assert(strlength(strtrim(string(T.MissingArtifacts(1)))) == 0);

delete(componentPath);
resultMissing = sixgr.analytics.evaluatePublicationReadinessGates(struct(), root);
missingT = resultMissing.Tables.ArtifactCompleteness;
assert(~logical(missingT.ArtifactCompletenessOk(1)) && ...
    contains(string(missingT.MissingArtifacts(1)), ...
    "artifact_generation:pdsch/csv/pdsch_bler_curve.csv"), ...
    "A missing component artifact must still fail closed.");

ok = true;
fprintf("PASS testPhase7ComponentArtifactPathResolution: component contract paths resolve without fallback rows.\n");
end

function localRemove(pathValue)
if isfolder(pathValue)
    rmdir(pathValue, "s");
end
end
