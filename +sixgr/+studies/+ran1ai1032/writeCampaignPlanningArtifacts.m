function out = writeCampaignPlanningArtifacts(cfg, outputRoot)
%WRITECAMPAIGNPLANNINGARTIFACTS Persist plans without claiming execution.
%
% These tables are deliberately stored below a planning/ folder. Rows carry
% a non-executable planning or calibration-blocked status; none may be
% consumed as a primary PHY or system KPI table.

arguments
    cfg struct
    outputRoot (1,1) string = ""
end
if strlength(outputRoot) == 0
    outputRoot = string(cfg.outputs.root);
end
planFolder = fullfile(outputRoot, "planning");
sixgr.util.ensureFolder(planFolder);

lls = sixgr.studies.ran1ai1032.buildLLSCasePlan(cfg);
sls = sixgr.studies.ran1ai1032.buildPairedDropPlan(cfg);
slsCases = sixgr.studies.ran1ai1032.buildSLSCampaignCases(cfg);
slsCaseTable = slsCases.Cases;
slsCaseTable.ConfigDeltaJSON = cellfun(@jsonencode, ...
    slsCaseTable.ConfigDelta, "UniformOutput", false);
slsCaseTable.ExecutionParametersJSON = cellfun(@jsonencode, ...
    slsCaseTable.ExecutionParameters, "UniformOutput", false);
slsCaseTable(:, ["ConfigDelta","ExecutionParameters"]) = [];

paths = struct();
paths.LLSCases = fullfile(planFolder, "lls_case_plan.csv");
paths.LLSPoints = fullfile(planFolder, "lls_coarse_snr_point_plan.csv");
paths.SLSPairedCases = fullfile(planFolder, "sls_paired_drop_plan.csv");
paths.SLSSeedLedger = fullfile(planFolder, "sls_seed_ledger.csv");
paths.SLSCases = fullfile(planFolder, "sls_expanded_case_plan.csv");
sixgr.util.csvWriteTable(paths.LLSCases, lls.CasePlan);
sixgr.util.csvWriteTable(paths.LLSPoints, lls.PointPlan);
sixgr.util.csvWriteTable(paths.SLSPairedCases, sls.Plan);
sixgr.util.csvWriteTable(paths.SLSSeedLedger, sls.SeedLedger);
sixgr.util.csvWriteTable(paths.SLSCases, slsCaseTable);

Artifact = ["lls_case_plan";"lls_coarse_snr_point_plan"; ...
    "sls_paired_drop_plan";"sls_seed_ledger";"sls_expanded_case_plan"];
Path = string([paths.LLSCases; paths.LLSPoints; ...
    paths.SLSPairedCases; paths.SLSSeedLedger; paths.SLSCases]);
RowCount = [height(lls.CasePlan); height(lls.PointPlan); ...
    height(sls.Plan); height(sls.SeedLedger); height(slsCaseTable)];
ArtifactClass = repmat("campaign_planning_not_result_evidence", 5, 1);
ExecutionStatus = repmat("planned_not_executed", 5, 1);
PrimaryResultEligible = false(5, 1);
manifest = table(Artifact, Path, RowCount, ArtifactClass, ...
    ExecutionStatus, PrimaryResultEligible);
paths.Manifest = fullfile(planFolder, "planning_manifest.csv");
sixgr.util.csvWriteTable(paths.Manifest, manifest);

out = struct("Ok", true, "PlanningFolder", string(planFolder), ...
    "LLSCaseCount", lls.CaseCount, ...
    "LLSCoarsePointCount", lls.CoarsePointCount, ...
    "SLSPairCount", sls.PairCount, ...
    "SLSComparatorRows", height(sls.Plan), ...
    "SLSExpandedCaseCount", height(slsCaseTable), ...
    "Manifest", manifest, "Paths", paths, ...
    "ExecutionStatus", "planned_not_executed");
end
