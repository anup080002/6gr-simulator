function ok = testContractPlotLineageSourceClosure()
%TESTCONTRACTPLOTLINEAGESOURCECLOSURE Exact chart sources must remain sealed.

setup6GRSimToolkit("Verbose", false);
root = string(tempname);
mkdir(fullfile(root, "reports", "csv"));
cleanup = onCleanup(@() localRemove(root)); %#ok<NASGU>

sourcePath = fullfile(root, "reports", "csv", "source.csv");
sourceT = table((1:3).', (4:6).', 'VariableNames', {'x','y'});
sixgr.util.csvWriteTable(sourcePath, sourceT, "PreserveSchema", true);
sourceHash = localSHA256(sourcePath);
lineageT = table("unit_plot", "reports/image/unit.png", ...
    "reports/csv/source.csv", sourceHash, ...
    'VariableNames', {'PlotId','ImagePath','SourceCSV','SourceCSV_SHA256'});
sixgr.util.csvWriteTable(fullfile(root, "reports", "csv", ...
    "contract_plot_lineage.csv"), lineageT, "PreserveSchema", true);

sealed = sixgr.artifact.verifyContractPlotLineageSources(root);
assert(logical(sealed.Ok) && sealed.FailureCount == 0 && ...
    sealed.SourceCount == 1, ...
    "Exact source bytes must satisfy the chart-lineage closure.");

sourceT.y(1) = 99;
sixgr.util.csvWriteTable(sourcePath, sourceT, "PreserveSchema", true);
changed = sixgr.artifact.verifyContractPlotLineageSources(root);
assert(~logical(changed.Ok) && changed.FailureCount == 1 && ...
    any(string(changed.Details.FailureCode) == "source_hash_mismatch"), ...
    "A post-materialization source mutation must fail closed.");

disabledRoot = fullfile(root, "disabled");
mkdir(fullfile(disabledRoot, "reports", "csv"));
mkdir(fullfile(disabledRoot, "meta"));
emptyLineage = table('Size', [0 4], ...
    'VariableTypes', {'string','string','string','string'}, ...
    'VariableNames', {'PlotId','ImagePath','SourceCSV','SourceCSV_SHA256'});
sixgr.util.csvWriteTable(fullfile(disabledRoot, "reports", "csv", ...
    "contract_plot_lineage.csv"), emptyLineage, "PreserveSchema", true);
sixgr.util.jsonWrite(fullfile(disabledRoot, "meta", ...
    "scenario_config_resolved.json"), struct("output", ...
    struct("save_figures", false)));
disabled = sixgr.artifact.verifyContractPlotLineageSources(disabledRoot);
assert(logical(disabled.Ok) && ~logical(disabled.Applicable) && ...
    disabled.SourceCount == 0 && ...
    string(disabled.Status) == "policy_disabled_by_resolved_yaml", ...
    "YAML-disabled raster output must close with an explicit not-applicable lineage receipt.");

sixgr.util.jsonWrite(fullfile(disabledRoot, "meta", ...
    "scenario_config_resolved.json"), struct("output", ...
    struct("save_figures", true)));
enabledEmpty = sixgr.artifact.verifyContractPlotLineageSources(disabledRoot);
assert(~logical(enabledEmpty.Ok) && logical(enabledEmpty.Applicable) && ...
    any(string(enabledEmpty.Details.FailureCode) == ...
    "contract_plot_lineage_empty_for_enabled_rasters"), ...
    "Raster-enabled runs with empty lineage must fail closed.");

ok = true;
end

function digest = localSHA256(pathValue)
fid = fopen(pathValue, "rb");
assert(fid >= 0);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
digest = lower(string(sixgr.util.sha256Hex(fread(fid, Inf, "*uint8"))));
end

function localRemove(pathValue)
if isfolder(pathValue)
    rmdir(pathValue, "s");
end
end
