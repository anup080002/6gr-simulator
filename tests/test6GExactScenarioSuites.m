function ok = test6GExactScenarioSuites()
%TEST6GEXACTSCENARIOSUITES Validate the exact named scenario-suite YAMLs.

setup6GRSimToolkit("Verbose", false);

suiteNames = [ ...
    "DL_PDSCH_AWGN_CALIBRATION"
    "DL_PDSCH_FADING_MIMO"
    "UL_PUSCH_WAVEFORM_AND_PAPR"
    "CONTROL_CHANNELS"
    "SYNC_AND_BROADCAST"
    "RANDOM_ACCESS"
    "CSI_ACQUISITION"
    "HARQ_AND_RETRANSMISSION"
    "AI_ML_AND_ENERGY"
    "WIDEBAND_STRESS"];

root = pwd;
scenarioDir = fullfile(root, "simulator", "configs", "scenarios");

for i = 1:numel(suiteNames)
    suitePath = fullfile(scenarioDir, suiteNames(i) + ".yaml");
    assert(exist(suitePath, "file") == 2, "Exact scenario suite '%s' is missing.", suiteNames(i));
    raw = sixgr.lls6g.config.readConfigFile(suitePath);
    sixgr.lls6g.config.validateScenarioConfig(raw, ...
        "Kind", "matrix", "AllowPartial", false, "Context", suitePath);
    assert(strcmp(string(raw.meta.matrix_id), suiteNames(i)), ...
        "Matrix suite '%s' must use the exact matrix_id.", suiteNames(i));
    assert(isfield(raw, "scenarios") && ~isempty(raw.scenarios), ...
        "Matrix suite '%s' must list scenarios.", suiteNames(i));

    suiteClasses = strings(0, 1);
    for k = 1:numel(raw.scenarios)
        scenarioPath = localResolveScenarioPath(root, suitePath, string(raw.scenarios{k}));
        assert(exist(scenarioPath, "file") == 2, ...
            "Matrix suite '%s' references missing scenario '%s'.", suiteNames(i), string(raw.scenarios{k}));
        scRaw = sixgr.lls6g.config.readConfigFile(scenarioPath);
        cls = string(sixgr.util.structGet(scRaw, "meta.research_class", ""));
        assert(strlength(cls) > 0, ...
            "Scenario '%s' in suite '%s' must declare meta.research_class.", string(raw.scenarios{k}), suiteNames(i));
        suiteClasses(end+1,1) = cls; %#ok<AGROW>
    end

    buckets = localStudyBuckets(suiteClasses);
    assert(any(buckets == "baseline"), ...
        "Matrix suite '%s' must contain at least one baseline-tagged scenario.", suiteNames(i));
end

ok = true;
end

function scenarioPath = localResolveScenarioPath(repoRoot, matrixPath, scenarioPathIn)
scenarioPath = char(string(scenarioPathIn));
if exist(scenarioPath, "file") == 2
    return;
end
baseDir = fileparts(char(string(matrixPath)));
candidate = fullfile(baseDir, scenarioPath);
if exist(candidate, "file") == 2
    scenarioPath = candidate;
    return;
end
candidate = fullfile(repoRoot, scenarioPath);
if exist(candidate, "file") == 2
    scenarioPath = candidate;
    return;
end
error("sixgr:test:MissingScenarioPath", "Unable to resolve suite scenario path '%s'.", scenarioPathIn);
end

function buckets = localStudyBuckets(classes)
classes = lower(string(classes(:)));
buckets = repmat("unclassified", size(classes));
buckets(ismember(classes, ["baseline_benchmark", "agreed_starting_point"])) = "baseline";
buckets(ismember(classes, ["study_item_candidate", "optional_research_experiment"])) = "open_study";
end
