function ok = test6GAIUseCaseCoverage()
%TEST6GAIUSECASECOVERAGE Ensure all prompt-listed AI use cases are selectable by config.

setup6GRSimToolkit("Verbose", false);

tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>

cases = { ...
    "link_adaptation_mcs_selection", "simulator/configs/models/link_adaptation_descriptor.json", "ai_link_adaptation_benchmark.csv"; ...
    "interference_classification", "simulator/configs/models/interference_classifier_descriptor.json", "ai_interference_classification_benchmark.csv"; ...
    "detector_selection", "simulator/configs/models/detector_selector_descriptor.json", "ai_detector_selection_benchmark.csv"; ...
    "impairment_mitigation", "simulator/configs/models/impairment_mitigation_descriptor.json", "ai_impairment_mitigation_benchmark.csv"};

for i = 1:size(cases, 1)
    useCase = string(cases{i,1});
    modelPath = string(cases{i,2});
    csvName = string(cases{i,3});
    scenarioPath = fullfile(tmp, char(useCase + ".yaml"));
    fid = fopen(scenarioPath, "w");
    fprintf(fid, "%s", ['{' ...
        '"inherits":["' strrep(fullfile(pwd, "simulator", "configs", "scenarios", "ce_ai_nn.yaml"), '\', '\\') '"],' ...
        '"meta":{"scenario_id":"' char(useCase) '","description":"ai use case","version":"1","owner":"test","maturity_tag":"smoke"},' ...
        '"ai_ml":{"enabled":true,"use_case":"' char(useCase) '","mode":"online_inference",' ...
        '"model_path":"' char(modelPath) '","model_id":"' char(useCase) '_descriptor","model_version":"1.0",' ...
        '"benchmark_observations":2},' ...
        '"output":{"save_figures":false,"save_mat":false}}']);
    fclose(fid);

    out = run_6g_phy_lls_single(scenarioPath, tmp, "smoke");
    assert(out.Ok, "AI use case %s should complete.", useCase);
    csvPath = fullfile(char(out.RunFolder), "reports", "csv", char(csvName));
    assert(exist(csvPath, "file") == 2, "AI use case %s must write %s.", useCase, csvName);
end

ok = true;
end
