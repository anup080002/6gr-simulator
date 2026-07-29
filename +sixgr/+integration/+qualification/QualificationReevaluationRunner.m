classdef QualificationReevaluationRunner
    %QUALIFICATIONREEVALUATIONRUNNER Read-only Phase-18 evidence recovery.
    methods (Static)
        function result = run(varargin)
            parser = inputParser;
            addParameter(parser,"SourceRunRoot","", ...
                @(x)ischar(x)||isstring(x));
            addParameter(parser,"OutputRoot","", ...
                @(x)ischar(x)||isstring(x));
            addParameter(parser,"ReadOnlySource",true,@islogical);
            addParameter(parser,"RebuildArtifactIndex",true,@islogical);
            addParameter(parser,"ApplyLosslessSchemaAdapters",true,@islogical);
            addParameter(parser,"Strict",true,@islogical);
            parse(parser,varargin{:});
            options = parser.Results;
            if ~options.ReadOnlySource
                error("FULLSTACK:ReadOnlyReevaluationRequired", ...
                    "Phase-18 recovery requires ReadOnlySource=true.");
            end
            if ~options.RebuildArtifactIndex
                error("FULLSTACK:ArtifactIndexRebuildRequired", ...
                    "Phase-18 recovery requires a rebuilt artifact index.");
            end
            sourceRoot = localCanonical(options.SourceRunRoot);
            outputRoot = localOutputPath(options.OutputRoot);
            if sourceRoot==outputRoot || ...
                    startsWith(lower(outputRoot), ...
                    lower(sourceRoot+string(filesep)))
                error("FULLSTACK:ReanalysisInsideSourceRun", ...
                    "Reanalysis output must be outside the immutable source run.");
            end
            if isfolder(outputRoot)
                existing = dir(fullfile(outputRoot,"**","*"));
                existing = existing(~[existing.isdir]);
                if ~isempty(existing)
                    error("FULLSTACK:ReanalysisOutputNotEmpty", ...
                        "Reanalysis output must be a new empty root: %s", ...
                        outputRoot);
                end
            end
            csvDir = fullfile(outputRoot,"reports","csv");
            jsonDir = fullfile(outputRoot,"reports","json");
            mdDir = fullfile(outputRoot,"reports","md");
            sixgr.util.ensureFolder(csvDir);
            sixgr.util.ensureFolder(jsonDir);
            sixgr.util.ensureFolder(mdDir);

            repoRoot = sixgr.integration.qualification. ...
                FullStackQualificationProfile.repoRoot();
            scenarioPath = fullfile(repoRoot,"simulator","configs", ...
                "scenarios", ...
                "lls_webgui_full_stack_sinr_geometry_qualification.yaml");
            scfg = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
            profile = sixgr.integration.qualification. ...
                FullStackQualificationProfile.load(scfg);
            resolver = sixgr.integration.qualification. ...
                ArtifactResolver.create(sourceRoot,profile);
            sourceDigestBefore = resolver.InventorySHA256;
            sourceFileCount = height(resolver.Files);

            runManifest = localRead(resolver,"full_stack_run_manifest.csv");
            runID = string(runManifest.RunID(1));
            originalSubcases = localRead(resolver, ...
                "full_stack_subcase_results.csv");
            originalValues = localRead(resolver, ...
                "full_stack_value_correctness_results.csv");
            originalComponents = localRead(resolver, ...
                "full_stack_component_coverage_results.csv");
            originalAcceptance = localRead(resolver, ...
                "full_stack_acceptance_results.csv");
            negatives = localRead(resolver, ...
                "full_stack_negative_fault_injection_results.csv");
            regression = localRead(resolver, ...
                "full_stack_regression_summary.csv");
            publication = localRead(resolver, ...
                "full_stack_webgui_publication.csv");

            [artifactAudit,artifactAdapters] = ...
                sixgr.integration.qualification.ArtifactResolver.audit( ...
                resolver,options.ApplyLosslessSchemaAdapters);
            [values,valueTrace,resolutionTrace,valueAdapters] = ...
                sixgr.integration.qualification. ...
                MultiSourceValueEvaluator.evaluate( ...
                profile.ValueChecks,resolver,runID, ...
                options.ApplyLosslessSchemaAdapters);
            adapterResults = [artifactAdapters;valueAdapters];
            if ~isempty(adapterResults)
                adapterResults = unique(adapterResults,"rows","stable");
            end
            [components,subcases,statusTrace] = ...
                sixgr.integration.qualification. ...
                QualificationStatusReducer.reduce( ...
                profile,runID,originalSubcases,values,negatives, ...
                artifactAudit,regression);
            acceptance = sixgr.integration.qualification. ...
                QualificationStatusReducer.acceptance( ...
                profile,runID,subcases,components,values,negatives, ...
                artifactAudit,regression,resolver);
            finalization = sixgr.integration.qualification. ...
                QualificationFinalizationCoordinator.assess( ...
                subcases,values,components,artifactAudit, ...
                publication,regression,acceptance);
            statusTrace = [statusTrace; ...
                localFinalizationTrace(finalization.Stages)];

            triage = localRemainingTriage(values,valueTrace, ...
                resolutionTrace,components,subcases,acceptance, ...
                artifactAudit,negatives,finalization);
            missingArtifacts = artifactAudit(~artifactAudit.Present,:);
            domainFailures = localDomainFailures(triage);

            sixgr.util.csvWriteTable(fullfile(csvDir, ...
                "phase18_failure_triage.csv"),triage);
            sixgr.util.csvWriteTable(fullfile(csvDir, ...
                "phase18_artifact_resolution_trace.csv"), ...
                resolutionTrace);
            sixgr.util.csvWriteTable(fullfile(csvDir, ...
                "phase18_schema_adapter_results.csv"),adapterResults);
            sixgr.util.csvWriteTable(fullfile(csvDir, ...
                "phase18_value_evaluation_trace.csv"),valueTrace);
            sixgr.util.csvWriteTable(fullfile(csvDir, ...
                "phase18_status_reduction_trace.csv"),statusTrace);
            sixgr.util.csvWriteTable(fullfile(csvDir, ...
                "phase18_recomputed_value_results.csv"),values);
            sixgr.util.csvWriteTable(fullfile(csvDir, ...
                "phase18_recomputed_component_results.csv"),components);
            sixgr.util.csvWriteTable(fullfile(csvDir, ...
                "phase18_recomputed_subcase_results.csv"),subcases);
            sixgr.util.csvWriteTable(fullfile(csvDir, ...
                "phase18_recomputed_acceptance_results.csv"),acceptance);
            sixgr.util.csvWriteTable(fullfile(csvDir, ...
                "phase18_remaining_missing_artifacts.csv"), ...
                missingArtifacts);
            sixgr.util.csvWriteTable(fullfile(csvDir, ...
                "phase18_remaining_domain_failures.csv"), ...
                domainFailures);

            reportPath = fullfile(mdDir,"PHASE18_REANALYSIS_REPORT.md");
            sixgr.util.writeTextFile(reportPath,localReport( ...
                runID,sourceDigestBefore,originalValues,values, ...
                originalComponents,components,originalSubcases, ...
                subcases,originalAcceptance,acceptance,triage, ...
                finalization),"MimeType", ...
                "text/markdown; charset=UTF-8", ...
                "ArtifactKind","report");

            resolverAfter = sixgr.integration.qualification. ...
                ArtifactResolver.create(sourceRoot,profile);
            sourceDigestAfter = resolverAfter.InventorySHA256;
            sourceUnchanged = sourceDigestBefore==sourceDigestAfter && ...
                sourceFileCount==height(resolverAfter.Files);
            if options.Strict && ~sourceUnchanged
                error("FULLSTACK:SourceRunMutated", ...
                    "Immutable source run inventory changed during reanalysis.");
            end

            canonical = localCanonicalOutputHashes(outputRoot);
            manifest = struct();
            manifest.ReanalysisVersion = ...
                "phase18-reanalysis-v1";
            manifest.Completed = true;
            manifest.SourceRunID = char(runID);
            manifest.SourceInventorySHA256Before = ...
                char(sourceDigestBefore);
            manifest.SourceInventorySHA256After = ...
                char(sourceDigestAfter);
            manifest.SourceFileCount = sourceFileCount;
            manifest.SourceRunUnchanged = sourceUnchanged;
            manifest.ReadOnlySource = true;
            manifest.RebuildArtifactIndex = true;
            manifest.LosslessSchemaAdaptersOnly = true;
            manifest.ContractCounts = struct("ValueChecks",107, ...
                "Components",163,"Subcases",31, ...
                "AcceptanceRules",387,"Artifacts",746);
            manifest.OriginalPassCounts = struct( ...
                "Values",nnz(string(originalValues.Status)=="PASS"), ...
                "Components",nnz(string(originalComponents.Status)=="PASS"), ...
                "Subcases",nnz(string(originalSubcases.Status)=="PASS"), ...
                "Acceptance",nnz(string(originalAcceptance.Status)=="PASS"));
            manifest.RecomputedPassCounts = struct( ...
                "Values",nnz(string(values.Status)=="PASS"), ...
                "Components",nnz(string(components.Status)=="PASS"), ...
                "Subcases",nnz(string(subcases.Status)=="PASS"), ...
                "Acceptance",nnz(string(acceptance.Status)=="PASS"));
            manifest.FinalStatus = char(finalization.FinalStatus);
            manifest.FinalManifestComplete = ...
                finalization.FinalManifestComplete;
            manifest.PublicationComplete = ...
                finalization.PublicationComplete;
            manifest.RegressionComplete = ...
                finalization.RegressionComplete;
            manifest.CanonicalOutputHashes = table2struct(canonical);
            manifestPath = fullfile(jsonDir, ...
                "phase18_reanalysis_manifest.json");
            sixgr.util.writeTextFile(manifestPath, ...
                string(jsonencode(manifest,"PrettyPrint",true)), ...
                "MimeType","application/json; charset=UTF-8", ...
                "ArtifactKind","manifest");
            manifestHash = sixgr.integration.qualification. ...
                ArtifactResolver.fileHash(manifestPath);

            if runID=="phase18_actual_20260728_04"
                originalInventory = localOriginalInventory( ...
                    originalValues,values,valueTrace,resolutionTrace, ...
                    originalComponents,components,originalSubcases, ...
                    subcases,originalAcceptance,acceptance, ...
                    artifactAudit,negatives,triage,finalization);
                auditDir = fullfile(repoRoot,"audit", ...
                    "full_stack_qualification");
                sixgr.util.ensureFolder(auditDir);
                sixgr.util.csvWriteTable(fullfile(auditDir, ...
                    "phase18_actual_20260728_04_failure_inventory.csv"), ...
                    originalInventory);
                nextOrder = localNextDomainOrder( ...
                    artifactAudit,triage,subcases);
                sixgr.util.csvWriteTable(fullfile(auditDir, ...
                    "PHASE18_NEXT_DOMAIN_ORDER.csv"),nextOrder);
            end

            result = struct("Completed",true,"RunID",runID, ...
                "SourceRunUnchanged",sourceUnchanged, ...
                "SourceInventorySHA256",sourceDigestAfter, ...
                "ManifestPath",string(manifestPath), ...
                "ManifestSHA256",manifestHash, ...
                "FinalStatus",finalization.FinalStatus, ...
                "OutputRoot",string(outputRoot));
        end
    end
end

function path = localCanonical(raw)
path = string(raw);
if strlength(strtrim(path))==0 || ~isfolder(path)
    error("FULLSTACK:SourceRunMissing", ...
        "A valid SourceRunRoot is required.");
end
path = string(char(java.io.File(char(path)).getCanonicalPath()));
end

function path = localOutputPath(raw)
path = string(raw);
if strlength(strtrim(path))==0
    error("FULLSTACK:ReanalysisOutputMissing", ...
        "A distinct OutputRoot is required.");
end
path = string(char(java.io.File(char(path)).getAbsolutePath()));
end

function T = localRead(resolver,identity)
loaded = sixgr.integration.qualification. ...
    QualificationTableLoader.load(resolver,identity,"Status",false);
T = loaded.Table;
end

function trace = localFinalizationTrace(stages)
rows = repmat(localReductionRow(),height(stages),1);
for index=1:height(stages)
    rows(index).ParentType="SUITE";
    rows(index).ParentID="PHASE18";
    rows(index).ChildType="FINALIZATION_STAGE";
    rows(index).ChildID=string(stages.Stage(index));
    rows(index).Required=true;
    rows(index).ChildStatus=string(stages.State(index));
    rows(index).ParentPassContribution= ...
        string(stages.State(index))=="COMPLETE";
    rows(index).Reason=string(stages.Details(index));
end
trace=struct2table(rows,"AsArray",true);
end

function row = localReductionRow()
row=struct("ParentType","","ParentID","","ChildType","", ...
    "ChildID","","Required",false,"ChildStatus","", ...
    "ParentPassContribution",false,"Reason","");
end

function triage = localRemainingTriage(values,valueTrace,resolutionTrace, ...
    components,subcases,acceptance,audit,negatives,finalization)
rows = repmat(localFailureRow(),0,1);
sequence=0;
for index=find(string(values.Status)~="PASS").'
    sequence=sequence+1;
    checkID=string(values.CheckID(index));
    trace=valueTrace(string(valueTrace.CheckID)==checkID,:);
    resolutions=resolutionTrace(string(resolutionTrace.CheckID)==checkID,:);
    sourceExists=~isempty(resolutions) && all(resolutions.Resolved);
    [failureClass,framework,domain] = localValueClass(trace,sourceExists);
    row=localFailureRow();
    row.FailureID=compose("REMAIN-%05d",sequence);
    row.SourceLedger="phase18_recomputed_value_results.csv";
    row.RowID=checkID;
    row.SubcaseID=string(values.SubcaseID(index));
    row.Domain=string(values.Domain(index));
    row.FailureCode=localTraceCode(trace,string(values.FailureCode(index)));
    row.FailureClass=failureClass;
    row.SourceArtifact=string(values.SourceCSV(index));
    row.SourceExists=sourceExists;
    row.RequiredColumnExists=~contains(row.FailureCode, ...
        "ValueColumnMissing");
    row.EvaluatorParsed=~isempty(trace) && ...
        strlength(string(trace.ParsedExpression(1)))>0;
    row.ComparatorExecuted=~isempty(trace) && ...
        strlength(string(trace.ObservedType(1)))>0;
    row.FrameworkBugSuspected=framework;
    row.DomainFailureSuspected=domain;
    row.Details=string(values.Details(index));
    rows(end+1,1)=row; %#ok<AGROW>
end
for index=find(string(audit.Status)~="PASS").'
    sequence=sequence+1;
    row=localFailureRow();
    row.FailureID=compose("REMAIN-%05d",sequence);
    row.SourceLedger="phase18_rebuilt_artifact_audit";
    row.RowID=string(audit.ArtifactID(index));
    row.Domain=string(audit.Domain(index));
    row.FailureCode=string(audit.FailureCode(index));
    row.SourceArtifact=string(audit.FileName(index));
    row.SourceExists=logical(audit.Present(index));
    row.RequiredColumnExists=logical(audit.SchemaValid(index));
    row.EvaluatorParsed=true;
    row.ComparatorExecuted=logical(audit.Present(index));
    if ~row.SourceExists
        row.FailureClass="ARTIFACT_MISSING";
        row.DomainFailureSuspected=true;
    elseif ~logical(audit.HashValid(index))
        row.FailureClass="FINALIZATION_ORDER_BUG";
        row.FrameworkBugSuspected=true;
    elseif ~logical(audit.SchemaValid(index))
        row.FailureClass="SCHEMA_ADAPTER_MISSING";
        row.FrameworkBugSuspected=true;
    else
        row.FailureClass="DOMAIN_NUMERICAL_FAILURE";
        row.DomainFailureSuspected=true;
    end
    row.Details=string(audit.Details(index));
    rows(end+1,1)=row; %#ok<AGROW>
end
rows=localAppendStatusFailures(rows,components,"ComponentID", ...
    "phase18_recomputed_component_results.csv","COMPONENT",sequence);
sequence=numel(rows);
rows=localAppendStatusFailures(rows,subcases,"SubcaseID", ...
    "phase18_recomputed_subcase_results.csv","SUBCASE",sequence);
sequence=numel(rows);
rows=localAppendStatusFailures(rows,acceptance,"RuleID", ...
    "phase18_recomputed_acceptance_results.csv","ACCEPTANCE",sequence);
sequence=numel(rows);
for index=find(string(negatives.Status)~="PASS").'
    sequence=sequence+1;
    row=localFailureRow();
    row.FailureID=compose("REMAIN-%05d",sequence);
    row.SourceLedger="full_stack_negative_fault_injection_results.csv";
    row.RowID=string(negatives.CaseID(index));
    row.SubcaseID=string(negatives.SubcaseID(index));
    row.Domain=string(negatives.Domain(index));
    row.FailureCode=string(negatives.ExpectedError(index));
    row.FailureClass="DOMAIN_RUNTIME_FAILURE";
    row.SourceArtifact=string(negatives.EvidenceArtifactID(index));
    row.SourceExists=strlength(row.SourceArtifact)>0;
    row.RequiredColumnExists=true;
    row.EvaluatorParsed=true;
    row.ComparatorExecuted=true;
    row.DomainFailureSuspected=true;
    row.Details=string(negatives.Details(index));
    rows(end+1,1)=row; %#ok<AGROW>
end
if finalization.FinalStatus=="INTERRUPTED"
    sequence=sequence+1;
    row=localFailureRow();
    row.FailureID=compose("REMAIN-%05d",sequence);
    row.SourceLedger="finalization_state_machine";
    row.RowID="REGRESSION_COMPLETE";
    row.SubcaseID="SC-30";
    row.Domain="Regression";
    row.FailureCode="FULLSTACK:RegressionIncomplete";
    row.FailureClass="INTERRUPTED_REGRESSION";
    row.SourceArtifact="full_stack_regression_summary.csv";
    row.SourceExists=true;
    row.RequiredColumnExists=true;
    row.EvaluatorParsed=true;
    row.ComparatorExecuted=true;
    row.FrameworkBugSuspected=false;
    row.DomainFailureSuspected=true;
    row.Details="Source regression ledger is blocked and unexecuted; final manifest is explicitly incomplete.";
    rows(end+1,1)=row; %#ok<AGROW>
end
triage=struct2table(rows,"AsArray",true);
end

function rows=localAppendStatusFailures(rows,T,idColumn,ledger,kind,sequence)
for index=find(string(T.Status)~="PASS").'
    sequence=sequence+1;
    row=localFailureRow();
    row.FailureID=compose("REMAIN-%05d",sequence);
    row.SourceLedger=string(ledger);
    row.RowID=string(T.(char(idColumn))(index));
    if ismember("SubcaseID",string(T.Properties.VariableNames))
        row.SubcaseID=string(T.SubcaseID(index));
    end
    if ismember("ComponentID",string(T.Properties.VariableNames))
        row.ComponentID=string(T.ComponentID(index));
    end
    if ismember("Domain",string(T.Properties.VariableNames))
        row.Domain=string(T.Domain(index));
    else
        row.Domain=string(kind);
    end
    if ismember("FailureCode",string(T.Properties.VariableNames))
        row.FailureCode=string(T.FailureCode(index));
    end
    row.FailureClass="DOMAIN_RUNTIME_FAILURE";
    row.SourceExists=true;
    row.RequiredColumnExists=true;
    row.EvaluatorParsed=true;
    row.ComparatorExecuted=true;
    row.DomainFailureSuspected=true;
    if ismember("Details",string(T.Properties.VariableNames))
        row.Details=string(T.Details(index));
    else
        row.Details=kind+" failed deterministic bottom-up reduction.";
    end
    rows(end+1,1)=row; %#ok<AGROW>
end
end

function [className,framework,domain]=localValueClass(trace,sourceExists)
framework=false;
domain=false;
if isempty(trace)
    className="UNCLASSIFIED";
    return;
end
code=string(trace.FailureCode(1));
if ~sourceExists || contains(code,["ValueSourceMissing", ...
        "ArtifactMissing"])
    className="ARTIFACT_MISSING";
    domain=true;
elseif contains(code,["ValueColumnMissing","ScalarValueRequired", ...
        "SchemaAdapter","ValueShapeMismatch"])
    className="SCHEMA_ADAPTER_MISSING";
    framework=true;
elseif strlength(string(trace.ObservedType(1)))>0
    className="DOMAIN_NUMERICAL_FAILURE";
    domain=true;
else
    className="EVALUATOR_BUG";
    framework=true;
end
end

function code=localTraceCode(trace,fallback)
if ~isempty(trace) && strlength(string(trace.FailureCode(1)))>0
    code=string(trace.FailureCode(1));
else
    code=string(fallback);
end
end

function failures=localDomainFailures(triage)
mask=ismember(string(triage.FailureClass), ...
    ["DOMAIN_RUNTIME_FAILURE","DOMAIN_NUMERICAL_FAILURE", ...
    "INTERRUPTED_REGRESSION"]);
failures=triage(mask,:);
end

function inventory=localOriginalInventory(originalValues,values, ...
    valueTrace,resolutionTrace,originalComponents,components, ...
    originalSubcases,subcases,originalAcceptance,acceptance,audit, ...
    negatives,triage,finalization)
rows=repmat(localFailureRow(),0,1);
sequence=0;
for index=find(string(originalValues.Status)~="PASS").'
    sequence=sequence+1;
    id=string(originalValues.CheckID(index));
    current=values(string(values.CheckID)==id,:);
    trace=valueTrace(string(valueTrace.CheckID)==id,:);
    resolution=resolutionTrace(string(resolutionTrace.CheckID)==id,:);
    sourceExists=~isempty(resolution)&&all(resolution.Resolved);
    details=string(originalValues.Details(index));
    if string(current.Status)=="PASS"
        if contains(details,"ValueSourceMissing")
            className="ARTIFACT_RESOLUTION_BUG";
        elseif contains(details,"ValueColumnMissing")
            className="SCHEMA_ADAPTER_MISSING";
        else
            className="EVALUATOR_BUG";
        end
        framework=true;domain=false;
    else
        [className,framework,domain]=localValueClass(trace,sourceExists);
    end
    row=localFailureRow();
    row.FailureID=compose("ORIGINAL-%05d",sequence);
    row.SourceLedger="full_stack_value_correctness_results.csv";
    row.RowID=id;
    row.SubcaseID=string(originalValues.SubcaseID(index));
    row.Domain=string(originalValues.Domain(index));
    row.FailureCode=string(originalValues.FailureCode(index));
    row.FailureClass=className;
    row.SourceArtifact=string(originalValues.SourceCSV(index));
    row.SourceExists=sourceExists;
    row.RequiredColumnExists=~contains(localTraceCode(trace,""), ...
        "ValueColumnMissing");
    row.EvaluatorParsed=~isempty(trace)&& ...
        strlength(string(trace.ParsedExpression(1)))>0;
    row.ComparatorExecuted=~isempty(trace)&& ...
        strlength(string(trace.ObservedType(1)))>0;
    row.FrameworkBugSuspected=framework;
    row.DomainFailureSuspected=domain;
    row.Details=details+" Recomputed="+string(current.Status)+".";
    rows(end+1,1)=row; %#ok<AGROW>
end
for index=find(string(originalSubcases.Status)=="PASS").'
    id=string(originalSubcases.SubcaseID(index));
    child=components(string(components.SubcaseID)==id & ...
        localTruth(components.Mandatory),:);
    current=subcases(string(subcases.SubcaseID)==id,:);
    if any(string(child.Status)~="PASS") || string(current.Status)~="PASS"
        sequence=sequence+1;
        row=localFailureRow();
        row.FailureID=compose("ORIGINAL-%05d",sequence);
        row.SourceLedger="full_stack_subcase_status.csv";
        row.RowID=id;
        row.SubcaseID=id;
        row.Domain=string(originalSubcases.Category(index));
        row.FailureCode="FULLSTACK:IllegalParentChildStatus";
        row.FailureClass="STATUS_REDUCER_BUG";
        row.SourceExists=true;
        row.RequiredColumnExists=true;
        row.EvaluatorParsed=true;
        row.ComparatorExecuted=true;
        row.FrameworkBugSuspected=true;
        row.Details="Original subcase PASS had a mandatory recomputed child failure.";
        rows(end+1,1)=row; %#ok<AGROW>
    end
end
if finalization.FinalStatus=="INTERRUPTED"
    sequence=sequence+1;
    row=localFailureRow();
    row.FailureID=compose("ORIGINAL-%05d",sequence);
    row.SourceLedger="full_stack_run_manifest.csv";
    row.RowID="FINAL_MANIFEST";
    row.SubcaseID="SC-30";
    row.Domain="Finalization";
    row.FailureCode="FULLSTACK:InterruptedFinalization";
    row.FailureClass="FINALIZATION_ORDER_BUG";
    row.SourceArtifact="full_stack_run_manifest.csv";
    row.SourceExists=true;
    row.RequiredColumnExists=true;
    row.EvaluatorParsed=true;
    row.ComparatorExecuted=true;
    row.FrameworkBugSuspected=true;
    row.Details="Original manifest declared terminal FAIL although regression remained blocked and unexecuted.";
    rows(end+1,1)=row; %#ok<AGROW>
end
% Preserve every remaining primary failure after the original false-negative
% inventory.  IDs are namespaced and therefore deterministic.
rows=[rows;table2struct(triage,"ToScalar",false)]; %#ok<AGROW>
inventory=struct2table(rows,"AsArray",true);
% Reference inputs are intentionally consumed here so accidental schema
% removal is caught by MATLAB before output.
assert(height(originalComponents)==height(components));
assert(height(originalAcceptance)==height(acceptance));
assert(height(audit)>0 && height(negatives)>0);
end

function T=localNextDomainOrder(audit,triage,subcases)
waves=["Frame/waveform schema and correctness closure"; ...
    "PDSCH/DL-SCH production runner and exporters"; ...
    "PUSCH/UL-SCH production runner and exporters"; ...
    "Fixed DL/UL SINR sweep SC-04/SC-05"; ...
    "Initial access SC-06"; ...
    "MIMO/beam SC-13/SC-14"; ...
    "NLOS/interference/mobility/power/handover gaps"; ...
    "Validation/oracle artifacts"; ...
    "Final artifact/WebGUI publication"; ...
    "Sharded complete regression"];
tokens=["frame|waveform";"pdsch";"pusch";"pdsch|pusch"; ...
    "initial";"mimo|beam";"channel|rf|handover|interference"; ...
    "validation";"integration|webgui";"regression"];
runtime=["20-40 min";"45-90 min";"45-90 min";"30-60 min"; ...
    "30-60 min";"45-90 min";"45-90 min";"20-45 min"; ...
    "15-30 min";"measured baseline plus 25%"];
n=numel(waves);
blocking=zeros(n,1);
missing=zeros(n,1);
actual=zeros(n,1);
dependent=zeros(n,1);
reuse=zeros(n,1);
for index=1:n
    parts=split(tokens(index),"|");
    amask=false(height(audit),1);
    fmask=false(height(triage),1);
    smask=false(height(subcases),1);
    for part=reshape(parts,1,[])
        amask=amask|contains(lower(string(audit.Domain)),part)| ...
            contains(lower(string(audit.FileName)),part);
        fmask=fmask|contains(lower(string(triage.Domain)),part)| ...
            contains(lower(string(triage.SourceArtifact)),part);
        smask=smask|contains(lower(string(subcases.Category)),part)| ...
            contains(lower(string(subcases.Name)),part);
    end
    blocking(index)=index;
    missing(index)=nnz(amask & ~audit.Present);
    actual(index)=nnz(fmask & ismember(string( ...
        triage.FailureClass),["DOMAIN_RUNTIME_FAILURE", ...
        "DOMAIN_NUMERICAL_FAILURE","INTERRUPTED_REGRESSION"]));
    dependent(index)=nnz(smask & string(subcases.Status)~="PASS");
    if nnz(amask)>0
        reuse(index)=100*nnz(amask&audit.Present)/nnz(amask);
    end
end
T=table((1:n)',waves,blocking,missing,actual,dependent,reuse,runtime, ...
    'VariableNames',{'Rank','DomainWave','BlockingCriticalPath', ...
    'MissingMandatoryArtifacts','ActualDomainFailureCount', ...
    'DependentSubcasesBlocked','ExistingEvidenceReusePct', ...
    'EstimatedRuntimeToVerify'});
end

function hashes=localCanonicalOutputHashes(outputRoot)
listing=dir(fullfile(outputRoot,"reports","**","*"));
listing=listing(~[listing.isdir]);
paths=strings(numel(listing),1);
sha=strings(numel(listing),1);
for index=1:numel(listing)
    full=string(fullfile(listing(index).folder,listing(index).name));
    relative=replace(erase(full,string(outputRoot)+filesep),"\","/");
    paths(index)=relative;
    sha(index)=sixgr.integration.qualification. ...
        ArtifactResolver.fileHash(full);
end
hashes=sortrows(table(paths,sha, ...
    'VariableNames',{'RelativePath','SHA256'}),"RelativePath");
end

function text=localReport(runID,digest,originalValues,values, ...
    originalComponents,components,originalSubcases,subcases, ...
    originalAcceptance,acceptance,triage,finalization)
lines=["# Phase-18 Existing-Run Reanalysis";""; ...
    "Source RunID: `"+runID+"`"; ...
    "Source inventory SHA-256: `"+digest+"`"; ...
    "Source handling: immutable/read-only"; ...
    "Final source-suite status: **"+finalization.FinalStatus+"**"; ...
    "FinalManifestComplete: `"+ ...
    lower(string(finalization.FinalManifestComplete))+"`";""; ...
    "## Original versus recomputed PASS counts";""; ...
    "| Ledger | Original | Recomputed |"; ...
    "|---|---:|---:|"; ...
    "| Values | "+nnz(string(originalValues.Status)=="PASS")+ ...
    "/"+height(originalValues)+" | "+ ...
    nnz(string(values.Status)=="PASS")+"/"+height(values)+" |"; ...
    "| Components | "+nnz(string(originalComponents.Status)=="PASS")+ ...
    "/"+height(originalComponents)+" | "+ ...
    nnz(string(components.Status)=="PASS")+"/"+height(components)+" |"; ...
    "| Subcases | "+nnz(string(originalSubcases.Status)=="PASS")+ ...
    "/"+height(originalSubcases)+" | "+ ...
    nnz(string(subcases.Status)=="PASS")+"/"+height(subcases)+" |"; ...
    "| Acceptance | "+nnz(string(originalAcceptance.Status)=="PASS")+ ...
    "/"+height(originalAcceptance)+" | "+ ...
    nnz(string(acceptance.Status)=="PASS")+"/"+height(acceptance)+" |"; ...
    ""; "## Remaining failure classes";""];
classes=unique(string(triage.FailureClass),"stable");
for className=reshape(classes,1,[])
    lines(end+1,1)="- "+className+": "+ ... %#ok<AGROW>
        nnz(string(triage.FailureClass)==className);
end
lines=[lines;"";"No contract threshold, comparator, mandatory rule, " + ...
    "artifact, component, or subcase was weakened. Missing measured " + ...
    "evidence remains missing."];
text=strjoin(lines,newline)+newline;
end

function row=localFailureRow()
row=struct("FailureID","","SourceLedger","","RowID","", ...
    "SubcaseID","","ComponentID","","Domain","","FailureCode","", ...
    "FailureClass","UNCLASSIFIED","SourceArtifact","", ...
    "SourceExists",false,"RequiredColumnExists",false, ...
    "EvaluatorParsed",false,"ComparatorExecuted",false, ...
    "FrameworkBugSuspected",false,"DomainFailureSuspected",false, ...
    "Details","");
end

function tf=localTruth(value)
tf=ismember(lower(strtrim(string(value))), ...
    ["true","1","yes","pass","required"]);
end
