function ok = test6GParameterCatalog()
%TEST6GPARAMETERCATALOG Ensure 6G config parameter metadata is YAML-backed and complete.

setup6GRSimToolkit("Verbose", false);

scenarioCatalog = sixgr.lls6g.config.loadParameterCatalog("scenario");
matrixCatalog = sixgr.lls6g.config.loadParameterCatalog("matrix");
scenarioSchema = sixgr.lls6g.config.schema("scenario");
matrixSchema = sixgr.lls6g.config.schema("matrix");

assert(all(ismember(string(fieldnames(scenarioCatalog.sections)), scenarioSchema.AllowedTopLevel)), ...
    "Scenario schema should be derived from the scenario parameter catalog.");
assert(all(ismember(string(fieldnames(matrixCatalog.sections)), matrixSchema.AllowedTopLevel)), ...
    "Matrix schema should be derived from the matrix parameter catalog.");

globalCfg = sixgr.lls6g.config.readConfigFile(fullfile(pwd, "simulator", "configs", "defaults", "global.yaml"));
localAssertCatalogCoverage(globalCfg, scenarioCatalog.sections);

assert(any(lower(string(scenarioCatalog.sections.scenario.parameters.runner_profile.allowed_values)) == "waveform_bundle"), ...
    "Catalog must expose allowed scenario runner profiles.");
assert(any(lower(string(scenarioCatalog.sections.ai_ml.parameters.use_case.allowed_values)) == "beam_prediction"), ...
    "Catalog must expose AI use-case values.");
assert(any(double(scenarioCatalog.sections.modulation.parameters.dl_modulation_order.allowed_numeric_values) == 12), ...
    "Catalog must expose modulation-order options.");
assert(numel(scenarioCatalog.value_maps.modulation_order_to_name) >= 7, ...
    "Catalog must expose modulation-order to modulation-name mappings.");

matrixCfg = sixgr.lls6g.config.readConfigFile(fullfile(pwd, "simulator", "configs", "scenarios", "matrix_regression.yaml"));
assert(isfield(matrixCatalog.sections, "execution"), "Matrix catalog must define execution section.");
assert(isfield(matrixCatalog.sections.execution.parameters, "max_parallel_jobs"), ...
    "Matrix catalog must define execution.max_parallel_jobs.");
assert(~isempty(matrixCfg.scenarios), "Matrix regression must keep a non-empty scenario list.");

ok = true;
end

function localAssertCatalogCoverage(cfg, sectionRules)
sectionNames = string(fieldnames(cfg));
for i = 1:numel(sectionNames)
    sec = sectionNames(i);
    if sec == "inherits"
        continue;
    end
    assert(isfield(sectionRules, sec), "Scenario catalog missing section '%s'.", sec);
    params = string(fieldnames(cfg.(sec)));
    for j = 1:numel(params)
        key = params(j);
        assert(isfield(sectionRules.(sec).parameters, key), ...
            "Scenario catalog missing parameter '%s.%s'.", sec, key);
    end
end
end
