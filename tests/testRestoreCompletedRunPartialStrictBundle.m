function ok = testRestoreCompletedRunPartialStrictBundle()
%TESTRESTORECOMPLETEDRUNPARTIALSTRICTBUNDLE Partial optional bundles do not masquerade as strict campaigns.

setup6GRSimToolkit("Verbose", false);
tmp = tempname;
mkdir(tmp);
cleanup = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>

partial = struct();
partial.ArtifactTables = struct("pdcch_trials", ...
    table(1, true, 'VariableNames', {'TrialId','StrictOk'}));
result = struct("StrictControl", struct("PDCCH", partial));
report = sixgr.truth.restoreCompletedRunTruthArtifacts(tmp, result);

assert(height(report) == 1);
assert(string(report.Component(1)) == "pdcch");
assert(double(report.ArtifactCount(1)) == 0);
assert(string(report.RestoreStatus(1)) == ...
    "not_restored_incomplete_saved_strict_bundle");
assert(contains(string(report.EvidenceSource(1)), "pdcch_config_strict"));
assert(~isfile(fullfile(tmp, "control", "csv", "pdcch_config_strict.csv")));

ok = true;
fprintf("PASS testRestoreCompletedRunPartialStrictBundle: partial PDCCH bundle remains unavailable.\n");
end
