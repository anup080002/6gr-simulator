function ok = testFixedLinkCampaignCheckpointResume()
%TESTFIXEDLINKCAMPAIGNCHECKPOINTRESUME Point-boundary resume is exact.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
scenarioPath = fullfile(pwd, "simulator", "configs", "scenarios", ...
    "master_sinr_sweep.yaml");
scfg = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
cfg = sixgr.lls6g.buildInternalConfig(scfg.toStruct(), ...
    fullfile(tempdir, "fixed_link_checkpoint_resume_fixture"));
assert(logical(sixgr.util.structGet(cfg, ...
    "validation.phase7_execution_validation.enabled", false)), ...
    "The Phase-7 execution-validation YAML block was not mapped to runtime cfg.");

campaignCfg = cfg.validation.fixed_link_campaign;
campaignCfg.direction = "DL";
campaignCfg.snr_db = [10 20];
campaignCfg.mcs = 20;
campaignCfg.min_tb_per_point = 1;
campaignCfg.max_tb_per_point = 1;
campaignCfg.min_errors_for_ci = 0;
campaignCfg.max_ci_half_width = 1;
campaignCfg.trials_per_drop = 1;
campaignCfg.parallel_workers = 0;

tmp = tempname;
mkdir(tmp);
cleanup = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>
checkpointPath = fullfile(tmp, "campaign_checkpoint.mat");

baseline = sixgr.lls6g.campaign.runFixedLinkCampaign(cfg, ...
    "Config", campaignCfg, "WriteArtifacts", false);
partial = sixgr.lls6g.campaign.runFixedLinkCampaign(cfg, ...
    "Config", campaignCfg, "WriteArtifacts", false, ...
    "CheckpointPath", checkpointPath, "MaxPointsThisInvocation", 1);
assert(~partial.Completed && partial.CompletedPointCount == 1 && ...
    exist(checkpointPath, "file") == 2, ...
    "The first invocation must stop at a real persisted point checkpoint.");

resumed = sixgr.lls6g.campaign.runFixedLinkCampaign(cfg, ...
    "Config", campaignCfg, "WriteArtifacts", false, ...
    "CheckpointPath", checkpointPath, "ResumeFromCheckpoint", true);
assert(resumed.Completed && resumed.ResumedFromCheckpoint, ...
    "The resumed invocation must complete from the persisted checkpoint.");
for field = ["Summary","DLTrials","ULTrials","TaskPlan"]
    baselineTable = localScientificTable(baseline.(char(field)));
    resumedTable = localScientificTable(resumed.(char(field)));
    if ~isequaln(baselineTable, resumedTable)
        details = localTableDifference(baselineTable, resumedTable);
        error("sixgr:tests:CheckpointResumeMismatch", ...
            "Resumed fixed-link field %s differs from uninterrupted execution: %s", ...
            field, details);
    end
end
assert(string(baseline.CampaignIdentity) == string(resumed.CampaignIdentity), ...
    "Checkpoint resume must preserve the campaign identity hash.");

badCfg = campaignCfg;
badCfg.snr_db = [11 20];
localAssertIdentifier(@() sixgr.lls6g.campaign.runFixedLinkCampaign(cfg, ...
    "Config", badCfg, "WriteArtifacts", false, ...
    "CheckpointPath", checkpointPath, "ResumeFromCheckpoint", true), ...
    "sixgr:lls6g:campaign:CheckpointIdentityMismatch");
ok = true;
end

function T = localScientificTable(T)
excluded = intersect(string(T.Properties.VariableNames), ...
    ["DecodeLatency_ms","DL_DecodeLatency_ms","UL_DecodeLatency_ms", ...
    "ComputeLatency_ms","ReceiverPipelineLatency_ms"], ...
    "stable");
if ~isempty(excluded)
    T(:, cellstr(excluded)) = [];
end
end

function details = localTableDifference(a, b)
if ~(istable(a) && istable(b))
    details = "non_table_or_type_mismatch";
    return;
end
if height(a) ~= height(b) || width(a) ~= width(b)
    details = "shape=" + mat2str(size(a)) + " vs " + mat2str(size(b));
    return;
end
namesA = string(a.Properties.VariableNames);
namesB = string(b.Properties.VariableNames);
if ~isequal(namesA, namesB)
    details = "variable_names_differ";
    return;
end
bad = strings(0, 1);
for name = namesA
    if ~isequaln(a.(char(name)), b.(char(name)))
        bad(end+1, 1) = name; %#ok<AGROW>
    end
end
details = "columns=" + strjoin(bad, ",");
end

function localAssertIdentifier(fn, expected)
thrown = false;
try
    fn();
catch ME
    thrown = true;
    assert(string(ME.identifier) == string(expected), ...
        "Expected %s, received %s.", expected, ME.identifier);
end
assert(thrown, "Expected %s to be thrown.", expected);
end
