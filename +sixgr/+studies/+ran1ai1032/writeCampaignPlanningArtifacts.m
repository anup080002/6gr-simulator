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
paths.MCSDefinitions = fullfile(planFolder, "mcs_indication_definitions.csv");
sixgr.util.csvWriteTable(paths.LLSCases, lls.CasePlan);
sixgr.util.csvWriteTable(paths.LLSPoints, lls.PointPlan);
sixgr.util.csvWriteTable(paths.SLSPairedCases, sls.Plan);
sixgr.util.csvWriteTable(paths.SLSSeedLedger, sls.SeedLedger);
sixgr.util.csvWriteTable(paths.SLSCases, slsCaseTable);
mapDefinitions=localComparatorDefinitions();
sixgr.util.csvWriteTable(paths.MCSDefinitions, mapDefinitions);

Artifact = ["lls_case_plan";"lls_coarse_snr_point_plan"; ...
    "sls_paired_drop_plan";"sls_seed_ledger";"sls_expanded_case_plan"; ...
    "mcs_indication_definitions"];
Path = string([paths.LLSCases; paths.LLSPoints; ...
    paths.SLSPairedCases; paths.SLSSeedLedger; paths.SLSCases; paths.MCSDefinitions]);
RowCount = [height(lls.CasePlan); height(lls.PointPlan); ...
    height(sls.Plan); height(sls.SeedLedger); height(slsCaseTable); ...
    height(mapDefinitions)];
ArtifactClass = [repmat("campaign_planning_not_result_evidence", 5, 1); ...
    "deterministic_MCS_definition_not_performance"];
ExecutionStatus = [repmat("planned_not_executed", 5, 1); ...
    "definition_only_not_physical_result"];
PrimaryResultEligible = false(6, 1);
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

function M=localComparatorDefinitions()
% Enumerate the installed YAML-backed codepoint maps. An unassigned
% codepoint is a definition, never a received grant or performance row.
ids=["C0","C1","C2a","C3","C4","C5"];
M=table();
for i=1:numel(ids)
    [T,tableName]=sixgr.studies.ran1ai1032.MCSCatalog.correctedComparator(ids(i));
    width=unique(double(T.indication_width_bits));
    assert(isscalar(width) && width>=1 && width==fix(width), ...
        'sixgr:ran1ai1032:ComparatorWidth','Comparator width must be uniform.');
    count=2^width;
    codepoint=(0:count-1)';
    comparatorID=repmat(ids(i),count,1);
    mcsTable=repmat(string(tableName),count,1);
    indicationWidthBits=repmat(width,count,1);
    entryID=strings(count,1);
    Qm=nan(count,1);
    rateX1024=nan(count,1);
    entryKind=repmat("unassigned",count,1);
    newTBAllowed=false(count,1);
    retransmissionAllowed=false(count,1);
    for k=1:height(T)
        row=double(T.indication_index(k))+1;
        entryID(row)=string(T.entry_id(k));
        Qm(row)=double(T.Qm(k));
        rateX1024(row)=double(T.target_code_rate_x1024(k));
        entryKind(row)=string(T.entry_kind(k));
        newTBAllowed(row)=logical(T.new_TB_allowed(k));
        retransmissionAllowed(row)=logical(T.retransmission_allowed(k));
    end
    definitionSource=repmat("installed_yaml_mcs_catalog",count,1);
    resultClass=repmat("deterministic_definition_not_measured_performance",count,1);
    M=[M;table(comparatorID,mcsTable,codepoint,indicationWidthBits, ...
        entryID,Qm,rateX1024,entryKind,newTBAllowed, ...
        retransmissionAllowed,definitionSource,resultClass)]; %#ok<AGROW>
end
end
