classdef QualificationFinalizationRecoveryRunner
    %QUALIFICATIONFINALIZATIONRECOVERYRUNNER Transactional Phase-18 recovery.
    methods (Static)
        function result=run(sourceRunRoot,recoveryRunRoot,varargin)
            parser=inputParser;
            parser.addParameter("Strict",true,@(x)islogical(x)&&isscalar(x));
            parser.addParameter("StopAfterStage","", ...
                @(x)ischar(x)||isstring(x));
            parser.parse(varargin{:});
            source=localCanonical(sourceRunRoot,true);
            recovery=localCanonical(recoveryRunRoot,false);
            if source==recovery || startsWith(lower(recovery),lower(source+filesep))
                error("FULLSTACK:RecoveryRootOverlapsSource", ...
                    "Recovery output must be separate from the immutable source.");
            end
            sourceConfig=fullfile(source,"reports","config", ...
                "executed_scenario.yaml");
            if ~isfile(sourceConfig)
                error("FULLSTACK:RecoveryConfigurationMissing", ...
                    "The immutable source executed YAML is unavailable.");
            end
            scfg=sixgr.lls6g.config.loadScenarioConfig(sourceConfig);
            profile=sixgr.integration.qualification. ...
                FullStackQualificationProfile.load(scfg);
            sourceResolver=sixgr.integration.qualification. ...
                ArtifactResolver.create(source,profile);
            sourceDigest=sourceResolver.InventorySHA256;
            inputDigest=localInputManifestDigest(sourceDigest);
            sourceRunID=localSourceRunID(source);
            recoveryRunID=sourceRunID+"_recovery";
            csvDir=fullfile(recovery,"reports","csv");
            reportsDir=fullfile(recovery,"reports");
            metaDir=fullfile(recovery,"meta");
            sixgr.util.ensureFolder(csvDir);
            sixgr.util.ensureFolder(metaDir);
            ledgerPath=fullfile(csvDir,"finalization_stage_ledger.csv");
            ledger=localLoadLedger(ledgerPath);

            if localAlreadyComplete(ledger,inputDigest,recovery)
                result=localResult(source,recovery,sourceDigest,ledger,true);
                return;
            end
            ledger=localInvalidateChangedInput( ...
                ledger,inputDigest,ledgerPath);
            stages=localStages();
            for stageIndex=1:numel(stages)
                if string(ledger.Status(stageIndex))=="COMPLETE"
                    if string(parser.Results.StopAfterStage)==stages(stageIndex)
                        result=localResult(source,recovery,sourceDigest, ...
                            ledger,true);
                        return;
                    end
                    continue;
                end
                ledger=localResetFrom(ledger,stageIndex);
                ledger.StartUTC(stageIndex)=localUTC();
                ledger.Status(stageIndex)="RUNNING";
                ledger.InputManifestSHA256(stageIndex)=inputDigest;
                localWriteLedger(ledgerPath,ledger);
                try
                    outputHash=localExecuteStage(stageIndex,source,recovery, ...
                        sourceRunID,recoveryRunID,profile,csvDir, ...
                        reportsDir,metaDir,sourceDigest);
                    ledger.EndUTC(stageIndex)=localUTC();
                    ledger.Status(stageIndex)="COMPLETE";
                    ledger.OutputManifestSHA256(stageIndex)=outputHash;
                    ledger.FailureCode(stageIndex)="";
                    ledger.Details(stageIndex)=localStageDetail(stageIndex);
                    localWriteLedger(ledgerPath,ledger);
                catch ME
                    ledger.EndUTC(stageIndex)=localUTC();
                    ledger.Status(stageIndex)="FAIL";
                    ledger.FailureCode(stageIndex)=string(ME.identifier);
                    ledger.Details(stageIndex)=string(ME.message);
                    localWriteLedger(ledgerPath,ledger);
                    if parser.Results.Strict
                        rethrow(ME);
                    end
                    result=localResult(source,recovery,sourceDigest,ledger,false);
                    return;
                end
                if string(parser.Results.StopAfterStage)==stages(stageIndex)
                    result=localResult(source,recovery,sourceDigest,ledger,false);
                    return;
                end
            end
            after=sixgr.integration.qualification. ...
                ArtifactResolver.create(source,profile);
            if after.InventorySHA256~=sourceDigest
                error("FULLSTACK:ImmutableSourceChanged", ...
                    "Source inventory changed during recovery.");
            end
            result=localResult(source,recovery,sourceDigest,ledger,false);
        end
    end
end

function outputHash=localExecuteStage(index,source,recovery,sourceRunID, ...
        recoveryRunID,profile,csvDir,reportsDir,metaDir,sourceDigest)
registry=profile.SelectedArtifactRegistry;
switch index
    case 1 % F00
        payload=struct("SchemaVersion","phase18-source-lock/v1", ...
            "SourceRunID",sourceRunID,"SourceRunRoot",source, ...
            "SourceInventorySHA256",sourceDigest,"ReadOnly",true);
        path=fullfile(metaDir,"source_run_lock.json");
        sixgr.integration.qualification. ...
            QualificationAtomicWriter.writeJSON(path,payload);
        outputHash=localHash(path);
    case 2 % F01
        [sourceAudit,resolution]=sixgr.integration.qualification. ...
            QualificationArtifactSnapshot.scan( ...
            source,registry,sourceRunID);
        materialized=sixgr.integration.qualification. ...
            QualificationArtifactSnapshot.materialize( ...
            source,recovery,sourceAudit);
        path=fullfile(csvDir,"artifact_path_resolution.csv");
        sixgr.integration.qualification. ...
            QualificationAtomicWriter.writeTable(path,resolution);
        materializationPath=fullfile(csvDir, ...
            "artifact_materialization.csv");
        sixgr.integration.qualification. ...
            QualificationAtomicWriter.writeTable( ...
            materializationPath,materialized);
        outputHash=localDigest([path,materializationPath]);
    case 3 % F02
        [audit,~,adapters]=sixgr.integration.qualification. ...
            QualificationArtifactSnapshot.scan( ...
            recovery,registry,recoveryRunID, ...
            "MaterializeAdapters",true);
        normalizationPath=fullfile(csvDir, ...
            "artifact_schema_normalization.csv");
        sixgr.integration.qualification. ...
            QualificationAtomicWriter.writeTable( ...
            normalizationPath,audit);
        typeResolution=audit(:,["ArtifactID","RelativePath", ...
            "ArtifactType","MIMEType","ArtifactTypeSource","Status"]);
        typePath=fullfile(csvDir,"artifact_type_resolution.csv");
        sixgr.integration.qualification. ...
            QualificationAtomicWriter.writeTable(typePath,typeResolution);
        adapterPath=fullfile(csvDir,"domain_adapter_results.csv");
        adapterOutput=localAdapterContract(adapters);
        sixgr.integration.qualification. ...
            QualificationAtomicWriter.writeTable(adapterPath,adapterOutput);
        outputHash=localDigest([normalizationPath,typePath,adapterPath]);
    case {4,5} % F03/F04
        audit=localRead(fullfile(csvDir, ...
            "artifact_schema_normalization.csv"));
        if index==4
            domains=["Validation"];
            name="validation_export_dispatch.csv";
            subcases=["SC-27";"SC-28"];
        else
            domains=["End-to-End Integration","Full Stack Qualification"];
            name="integration_export_dispatch.csv";
            subcases=["SC-28";"SC-29"];
        end
        dispatch=localDispatch(audit,domains,subcases);
        path=fullfile(csvDir,name);
        sixgr.integration.qualification. ...
            QualificationAtomicWriter.writeTable(path,dispatch);
        outputHash=localHash(path);
    case 6 % F05
        status=localStatusSeparation(source,sourceRunID,recoveryRunID);
        path=fullfile(csvDir,"recovery_status_separation.csv");
        sixgr.integration.qualification. ...
            QualificationAtomicWriter.writeTable(path,status);
        outputHash=localHash(path);
    case 7 % F06
        localRegenerateFigures(recovery,profile,csvDir);
        paths=[fullfile(csvDir,"full_stack_image_semantic_audit.csv"); ...
            localFullStackImagePaths(registry,csvDir)];
        outputHash=localDigest(paths(isfile(paths)));
    case 8 % F07
        [audit,~]=sixgr.integration.qualification. ...
            QualificationArtifactSnapshot.scan( ...
            recovery,registry,recoveryRunID);
        semantic=localRead(fullfile(csvDir, ...
            "full_stack_image_semantic_audit.csv"));
        [audit,trace]=sixgr.integration.qualification. ...
            QualificationImageSemanticJoin.apply(audit,semantic,recovery);
        path=fullfile(csvDir,"artifact_join_trace.csv");
        sixgr.integration.qualification. ...
            QualificationAtomicWriter.writeTable(path,trace);
        normalized=fullfile(csvDir,"artifact_schema_normalization.csv");
        sixgr.integration.qualification. ...
            QualificationAtomicWriter.writeTable(normalized,audit);
        outputHash=localDigest([path,normalized]);
    case 9 % F08
        manifest=localRecoveredManifest( ...
            recovery,profile,recoveryRunID,false);
        path=fullfile(csvDir,"recovered_artifact_manifest.csv");
        sixgr.integration.qualification. ...
            QualificationAtomicWriter.writeTable(path,manifest);
        outputHash=localHash(path);
    case 10 % F09
        audit=localJoinedAudit(recovery,profile,recoveryRunID);
        published=sixgr.integration.qualification. ...
            CompositeArtifactPublisher.publish( ...
            recoveryRunID,recovery,audit,"DatabaseMandatory",false);
        path=fullfile(csvDir,"recovered_webgui_publication.csv");
        sixgr.integration.qualification. ...
            QualificationAtomicWriter.writeTable( ...
            path,published.Filesystem);
        databasePath=fullfile(csvDir, ...
            "recovered_database_publication.csv");
        sixgr.integration.qualification. ...
            QualificationAtomicWriter.writeTable( ...
            databasePath,published.Database);
        outputHash=localDigest([path,databasePath]);
    case 11 % F10
        audit=localJoinedAudit(recovery,profile,recoveryRunID);
        completeness=sixgr.integration.qualification. ...
            QualificationArtifactCompleteness.reduce(audit);
        path=fullfile(csvDir,"recovered_artifact_completeness.csv");
        sixgr.integration.qualification. ...
            QualificationAtomicWriter.writeTable(path,completeness);
        outputHash=localHash(path);
    case 12 % F11
        regression=localRecoveredRegression(source);
        path=fullfile(csvDir,"recovered_regression_status.csv");
        sixgr.integration.qualification. ...
            QualificationAtomicWriter.writeTable(path,regression);
        outputHash=localHash(path);
    case 13 % F12
        audit=localJoinedAudit(recovery,profile,recoveryRunID);
        [classification,missing,invalid,candidates]= ...
            localClassify(audit);
        paths=[fullfile(csvDir,"recovery_failure_classification.csv"); ...
            fullfile(csvDir,"recovery_missing_runtime_evidence.csv"); ...
            fullfile(csvDir,"recovery_invalid_existing_evidence.csv"); ...
            fullfile(csvDir,"recovery_regeneration_candidates.csv")];
        tables={classification,missing,invalid,candidates};
        for item=1:numel(paths)
            sixgr.integration.qualification. ...
                QualificationAtomicWriter.writeTable(paths(item),tables{item});
        end
        outputHash=localDigest(paths);
    case 14 % F13
        status=localFinalStatus(recovery,sourceRunID,recoveryRunID);
        report=localRecoveryReport(source,recovery,sourceDigest,status);
        reportPath=fullfile(reportsDir,"recovery_report.md");
        sixgr.integration.qualification. ...
            QualificationAtomicWriter.writeText(reportPath,report);
        payload=struct("SchemaVersion","phase18-recovery-manifest/v1", ...
            "SourceRunID",sourceRunID,"RecoveryRunID",recoveryRunID, ...
            "SourceRunRoot",source,"RecoveryRunRoot",recovery, ...
            "SourceInventorySHA256",sourceDigest, ...
            "ExecutionCompletionStatus",status.ExecutionCompletionStatus, ...
            "InfrastructureFinalizationStatus", ...
            status.InfrastructureFinalizationStatus, ...
            "QualificationStatus",status.QualificationStatus, ...
            "PublicationStatus",status.PublicationStatus, ...
            "RegressionStatus",status.RegressionStatus);
        metaPath=fullfile(metaDir,"recovery_manifest.json");
        sixgr.integration.qualification. ...
            QualificationAtomicWriter.writeJSON(metaPath,payload);
        statusPath=fullfile(csvDir,"recovery_final_status.csv");
        sixgr.integration.qualification. ...
            QualificationAtomicWriter.writeTable(statusPath, ...
            struct2table(status));
        outputHash=localDigest([reportPath,metaPath,statusPath]);
    case 15 % F14
        manifest=localRecoveredManifest( ...
            recovery,profile,recoveryRunID,true);
        path=fullfile(csvDir,"recovered_artifact_manifest.csv");
        sixgr.integration.qualification. ...
            QualificationAtomicWriter.writeTable(path,manifest);
        outputHash=localHash(path);
    otherwise
        error("FULLSTACK:UnknownRecoveryStage","Unknown recovery stage.");
end
end

function audit=localJoinedAudit(root,profile,runID)
normalized=fullfile(root,"reports","csv", ...
    "artifact_schema_normalization.csv");
if isfile(normalized)
    candidate=localRead(normalized);
    required=sixgr.integration.qualification. ...
        QualificationArtifactAuditSchema.VariableNames;
    if all(ismember(required,string(candidate.Properties.VariableNames)))
        audit=candidate;
        return;
    end
end
[audit,~]=sixgr.integration.qualification. ...
    QualificationArtifactSnapshot.scan( ...
    root,profile.SelectedArtifactRegistry,runID);
semanticPath=fullfile(root,"reports","csv", ...
    "full_stack_image_semantic_audit.csv");
if isfile(semanticPath)
    semantic=localRead(semanticPath);
    [audit,~]=sixgr.integration.qualification. ...
        QualificationImageSemanticJoin.apply(audit,semantic,root);
end
end

function manifest=localRecoveredManifest(root,profile,runID,includeRecovery)
manifest=localJoinedAudit(root,profile,runID);
manifest.GeneratedUTC(:)="";
if includeRecovery
    excluded=["reports/csv/recovered_artifact_manifest.csv", ...
        "reports/csv/finalization_stage_ledger.csv"];
    listing=dir(fullfile(root,"**","*"));
    listing=listing(~[listing.isdir]);
    extras=repmat(localExtraRow(),0,1);
    sequence=0;
    for index=1:numel(listing)
        full=string(fullfile(listing(index).folder,listing(index).name));
        relative=replace(erase(full,string(root)+filesep),"\","/");
        if ismember(relative,excluded) || ...
                any(manifest.RelativePath==relative)
            continue;
        end
        sequence=sequence+1;
        row=localExtraRow();
        row.SchemaVersion=sixgr.integration.qualification. ...
            QualificationArtifactAuditSchema.Version;
        row.RunID=runID;
        row.ArtifactID=compose("RECOVERY-%05d",sequence);
        row.Domain="Recovery Infrastructure";
        row.RelativePath=relative;
        row.ArtifactType=sixgr.integration.qualification. ...
            QualificationArtifactAuditSchema.typeFromPath(relative);
        row.MIMEType=sixgr.integration.qualification. ...
            QualificationArtifactAuditSchema.mimeFor(row.ArtifactType);
        row.Required=false;row.Present=true;row.Valid=true;
        row.Status="PASS";
        row.SHA256=localHash(full);
        row.ByteCount=double(listing(index).bytes);
        row.SemanticAuditStatus="NOT_APPLICABLE";
        row.ProvenanceClass="RECOVERY_DERIVED_FROM_IMMUTABLE_SOURCE";
        row.PublicationStatus="PUBLISHED";
        row.ArtifactTypeSource="derived:recognized_extension";
        row.SchemaValid=true;row.HashValid=true;row.SemanticValid=true;
        extras(end+1,1)=row; %#ok<AGROW>
    end
    if ~isempty(extras)
        manifest=[manifest;struct2table(extras,"AsArray",true)];
    end
end
manifest=sortrows(manifest,"ArtifactID");
end

function localRegenerateFigures(recovery,profile,csvDir)
staging=fullfile(recovery,"reports", ...
    ".phase18_plot_staging");
if isfolder(staging)
    localSafeRemove(staging,recovery);
end
mkdir(staging);
cleanup=onCleanup(@()localSafeRemove(staging,recovery)); %#ok<NASGU>
ctx=struct("Profile",profile,"RunFolder",recovery, ...
    "CSVDir",string(staging));
sixgr.integration.qualification.FullStackArtifactExporter. ...
    writeFigures(ctx);
files=dir(fullfile(staging,"*"));
files=files(~[files.isdir]);
for index=1:numel(files)
    source=fullfile(files(index).folder,files(index).name);
    target=fullfile(csvDir,files(index).name);
    localAtomicCopy(source,target);
end
end

function localAtomicCopy(source,target)
[folder,name,extension]=fileparts(target);
sixgr.util.ensureFolder(folder);
temporary=fullfile(folder,"."+name+"."+ ...
    char(java.util.UUID.randomUUID())+".tmp"+extension);
cleanup=onCleanup(@()localDelete(temporary)); %#ok<NASGU>
[ok,message]=copyfile(source,temporary,"f");
if ~ok,error("FULLSTACK:AtomicCopyFailed","%s",message);end
if endsWith(lower(target),".png"),imfinfo(temporary);end
if isfile(target),delete(target);end
[ok,message]=movefile(temporary,target,"f");
if ~ok,error("FULLSTACK:AtomicRenameFailed","%s",message);end
end

function paths=localFullStackImagePaths(registry,csvDir)
spec=registry(registry.Domain=="Full Stack Qualification" & ...
    registry.ArtifactType=="PNG",:);
paths=fullfile(csvDir,string(spec.FileName));
end

function T=localAdapterContract(adapters)
names={'Domain','SourceArtifact','TargetArtifact','SourceSchema', ...
    'TargetSchema','RowsIn','RowsOut','Lossless','DerivedColumns', ...
    'Status','FailureCode','SourceSHA256','TargetSHA256'};
if isempty(adapters)
    T=table(strings(0,1),strings(0,1),strings(0,1),strings(0,1), ...
        strings(0,1),zeros(0,1),zeros(0,1),false(0,1),strings(0,1), ...
        strings(0,1),strings(0,1),strings(0,1),strings(0,1), ...
        'VariableNames',names);
    return;
end
n=height(adapters);
T=table(string(adapters.Domain),string(adapters.SourceArtifact), ...
    string(adapters.TargetArtifact),string(adapters.SourceSchemaID), ...
    string(adapters.TargetSchemaID),double(adapters.RowsIn), ...
    double(adapters.RowsOut), ...
    logical(adapters.Lossless),string(adapters.TargetColumns), ...
    string(adapters.Status),string(adapters.FailureCode), ...
    string(adapters.SourceArtifactSHA256), ...
    string(adapters.OutputArtifactSHA256), ...
    'VariableNames',names);
end

function T=localDispatch(audit,domains,subcases)
mask=ismember(audit.Domain,domains);
selected=audit(mask,:);
n=height(selected);
if n==0
    T=table(strings(0,1),strings(0,1),strings(0,1),false(0,1), ...
        false(0,1),false(0,1),strings(0,1),strings(0,1), ...
        'VariableNames',{'SubcaseID','Domain','ArtifactID','Executed', ...
        'EvidencePresent','CorrectnessChecked','Status','FailureCode'});
    return;
end
subcase=repmat(subcases(1),n,1);
if numel(subcases)>1
    subcase(contains(lower(selected.Domain),"webgui"))=subcases(end);
end
T=table(subcase,selected.Domain,selected.ArtifactID, ...
    selected.Present,selected.Present,selected.Valid,selected.Status, ...
    selected.FailureCode, ...
    'VariableNames',{'SubcaseID','Domain','ArtifactID','Executed', ...
    'EvidencePresent','CorrectnessChecked','Status','FailureCode'});
end

function status=localStatusSeparation(source,sourceRunID,recoveryRunID)
regression=localRecoveredRegression(source);
status=struct("SourceRunID",sourceRunID,"RecoveryRunID",recoveryRunID, ...
    "ExecutionCompletionStatus","COMPLETED", ...
    "InfrastructureFinalizationStatus","IN_PROGRESS", ...
    "QualificationStatus","FAIL_INCOMPLETE", ...
    "PublicationStatus","PENDING", ...
    "RegressionStatus",localAggregateStatus(regression));
status=struct2table(status);
end

function regression=localRecoveredRegression(source)
path=fullfile(source,"reports","csv", ...
    "full_stack_regression_summary.csv");
if isfile(path)
    regression=localRead(path);
else
    regression=table("SOURCE_REGRESSION","FAIL", ...
        "FULLSTACK:RegressionEvidenceMissing", ...
        'VariableNames',{'Suite','Status','Details'});
end
end

function status=localFinalStatus(recovery,sourceRunID,recoveryRunID)
csvDir=fullfile(recovery,"reports","csv");
completeness=localRead(fullfile(csvDir, ...
    "recovered_artifact_completeness.csv"));
publication=localRead(fullfile(csvDir, ...
    "recovered_webgui_publication.csv"));
regression=localRead(fullfile(csvDir,"recovered_regression_status.csv"));
status=struct("SourceRunID",sourceRunID,"RecoveryRunID",recoveryRunID, ...
    "ExecutionCompletionStatus","COMPLETED", ...
    "InfrastructureFinalizationStatus","PASS", ...
    "QualificationStatus",localAggregateStatus(completeness), ...
    "PublicationStatus",localAggregateStatus(publication), ...
    "RegressionStatus",localAggregateStatus(regression));
end

function value=localAggregateStatus(T)
if ~isempty(T) && ismember("Status",string(T.Properties.VariableNames)) ...
        && all(upper(string(T.Status))=="PASS")
    value="PASS";
else
    value="FAIL";
end
end

function [classification,missing,invalid,candidates]=localClassify(audit)
failed=audit(audit.Required & audit.Status~="PASS",:);
n=height(failed);
category=strings(n,1);
for index=1:n
    if ~failed.Present(index)
        category(index)="MISSING_RUNTIME_EVIDENCE";
    elseif failed.Status(index)=="INVALID_SCHEMA"
        category(index)="ARTIFACT_SCHEMA";
    elseif failed.Status(index)=="INVALID_HASH"
        category(index)="ARTIFACT_HASH";
    elseif failed.Status(index)=="INVALID_SEMANTICS"
        category(index)="ARTIFACT_SEMANTIC";
    else
        category(index)="NUMERICAL_FAILURE";
    end
end
classification=table(failed.ArtifactID,failed.Domain, ...
    failed.RelativePath,failed.ArtifactType,failed.Present, ...
    failed.Status,category,failed.FailureCode, ...
    'VariableNames',{'ArtifactID','Domain','RelativePath', ...
    'ArtifactType','Present','ArtifactStatus','FailureCategory', ...
    'FailureCode'});
missing=classification(category=="MISSING_RUNTIME_EVIDENCE",:);
invalid=classification(category~="MISSING_RUNTIME_EVIDENCE",:);
candidateMask=ismember(category,["ARTIFACT_SCHEMA","ARTIFACT_SEMANTIC"]);
candidates=classification(candidateMask,:);
end

function report=localRecoveryReport(source,recovery,digest,status)
completeness=localRead(fullfile(recovery,"reports","csv", ...
    "recovered_artifact_completeness.csv"));
full=completeness(completeness.Domain=="Full Stack Qualification",:);
classification=localRead(fullfile(recovery,"reports","csv", ...
    "recovery_failure_classification.csv"));
lines=["# Phase-18 Finalization Recovery";""; ...
    "Source run (immutable): `"+source+"`"; ...
    "Recovery root: `"+recovery+"`"; ...
    "Source inventory SHA-256: `"+digest+"`";""; ...
    "Execution completion: **"+status.ExecutionCompletionStatus+"**"; ...
    "Infrastructure finalization: **"+ ...
    status.InfrastructureFinalizationStatus+"**"; ...
    "Qualification: **"+status.QualificationStatus+"**"; ...
    "Filesystem publication: **"+status.PublicationStatus+"**"; ...
    "Regression: **"+status.RegressionStatus+"**";""; ...
    "Full-stack valid CSV: "+full.ValidCSV+"/"+full.RequiredCSV; ...
    "Full-stack valid PNG: "+full.ValidPNG+"/"+full.RequiredPNG; ...
    "Full-stack completeness: "+compose("%.6f",full.CompletenessPct)+"%"; ...
    "Remaining classified failures: "+height(classification);""; ...
    "No simulation physics was executed. No configured value, proxy row, " + ...
    "placeholder, or threshold substitution was used."];
report=strjoin(lines,newline)+newline;
end

function result=localResult(source,recovery,digest,ledger,resumed)
complete=all(ledger.Status=="COMPLETE");
manifest=fullfile(recovery,"reports","csv", ...
    "recovered_artifact_manifest.csv");
if isfile(manifest),manifestHash=localHash(manifest);else,manifestHash="";end
result=struct("CompletedWithoutException",complete, ...
    "ResumedExistingFinalization",resumed,"SourceRunRoot",source, ...
    "RecoveryRunRoot",recovery,"SourceInventorySHA256",digest, ...
    "RecoveryManifestSHA256",manifestHash, ...
    "CompletedStageCount",nnz(ledger.Status=="COMPLETE"), ...
    "StageCount",height(ledger),"StageLedger",ledger);
end

function tf=localAlreadyComplete(ledger,inputDigest,recovery)
tf=height(ledger)==15 && all(ledger.Status=="COMPLETE") && ...
    all(ledger.InputManifestSHA256==inputDigest);
if tf
    path=fullfile(recovery,"reports","csv", ...
        "recovered_artifact_manifest.csv");
    tf=isfile(path) && localHash(path)== ...
        ledger.OutputManifestSHA256(end);
end
end

function ledger=localInvalidateChangedInput(ledger,digest,path)
if any(ledger.Status=="COMPLETE" & ...
        ledger.InputManifestSHA256~=digest)
    ledger=localResetFrom(ledger,1);
    localWriteLedger(path,ledger);
end
end

function digest=localInputManifestDigest(sourceDigest)
pipelineVersion="phase18-recovery-finalizer/v4";
digest=lower(string(sixgr.util.sha256Hex(uint8(char( ...
    string(sourceDigest)+"|"+pipelineVersion)))));
end

function ledger=localResetFrom(ledger,index)
ledger.StartUTC(index:end)="";
ledger.EndUTC(index:end)="";
ledger.Status(index:end)="PENDING";
ledger.InputManifestSHA256(index:end)="";
ledger.OutputManifestSHA256(index:end)="";
ledger.FailureCode(index:end)="";
ledger.Details(index:end)="";
end

function ledger=localLoadLedger(path)
stages=localStages();
if isfile(path)
    existing=localRead(path);
    if height(existing)==numel(stages) && ...
            all(string(existing.Stage)==stages)
        ledger=existing;
        return;
    end
end
n=numel(stages);
ledger=table(stages,strings(n,1),strings(n,1), ...
    repmat("PENDING",n,1),strings(n,1),strings(n,1), ...
    strings(n,1),strings(n,1), ...
    'VariableNames',{'Stage','StartUTC','EndUTC','Status', ...
    'InputManifestSHA256','OutputManifestSHA256', ...
    'FailureCode','Details'});
end

function localWriteLedger(path,ledger)
sixgr.integration.qualification.QualificationAtomicWriter. ...
    writeTable(path,ledger);
end

function stages=localStages()
stages=["F00_SOURCE_RUN_LOCKED"; ...
    "F01_DOMAIN_EXPORTS_DISCOVERED"; ...
    "F02_DOMAIN_SCHEMA_NORMALIZED"; ...
    "F03_VALIDATION_EVIDENCE_EXPORTED"; ...
    "F04_INTEGRATION_EVIDENCE_EXPORTED"; ...
    "F05_SUMMARY_TABLES_EXPORTED"; ...
    "F06_PLOTS_GENERATED"; ...
    "F07_IMAGE_SEMANTIC_AUDIT_DONE"; ...
    "F08_FINAL_ARTIFACT_MANIFEST_DONE"; ...
    "F09_WEBGUI_PUBLICATION_DONE"; ...
    "F10_COMPLETENESS_DONE"; ...
    "F11_REGRESSION_DONE"; ...
    "F12_FINAL_STATUS_REDUCED"; ...
    "F13_FINAL_RUN_MANIFEST_WRITTEN"; ...
    "F14_FINALIZED"];
end

function detail=localStageDetail(index)
details=["Immutable source inventory locked."; ...
    "Registered source evidence discovered and materialized."; ...
    "Artifact schemas and types normalized."; ...
    "Validation evidence dispatch recorded from actual artifacts."; ...
    "Integration evidence dispatch recorded from actual artifacts."; ...
    "Recovery status tables exported."; ...
    "Full-stack plots regenerated from observed CSVs."; ...
    "Exact semantic image joins completed."; ...
    "Draft recovered artifact manifest written."; ...
    "Filesystem publication indexed independently of MySQL."; ...
    "Canonical artifact completeness reduced."; ...
    "Source regression evidence classified."; ...
    "Remaining evidence failures classified."; ...
    "Recovery report and status manifest written."; ...
    "Final post-export artifact inventory written."];
detail=details(index);
end

function runID=localSourceRunID(source)
path=fullfile(source,"reports","csv","full_stack_run_manifest.csv");
if isfile(path)
    T=localRead(path);
    if ismember("RunID",string(T.Properties.VariableNames)) && ~isempty(T)
        runID=string(T.RunID(1));
        return;
    end
end
[~,runID]=fileparts(source);
runID=string(runID);
end

function root=localCanonical(raw,mustExist)
raw=string(raw);
if mustExist && ~isfolder(raw)
    error("FULLSTACK:SourceRunMissing","Run root is unavailable: %s",raw);
end
if mustExist
    root=string(char(java.io.File(char(raw)).getCanonicalPath()));
else
    root=string(char(java.io.File(char(raw)).getAbsolutePath()));
    sixgr.util.ensureFolder(root);
    root=string(char(java.io.File(char(root)).getCanonicalPath()));
end
end

function localSafeRemove(path,root)
if ~isfolder(path),return;end
canonical=string(char(java.io.File(char(path)).getCanonicalPath()));
root=string(char(java.io.File(char(root)).getCanonicalPath()));
if ~startsWith(lower(canonical),lower(root+filesep))
    error("FULLSTACK:UnsafeRecoveryCleanup", ...
        "Cleanup target escaped the recovery root.");
end
rmdir(canonical,"s");
end

function localDelete(path)
if isfile(path),delete(path);end
end

function T=localRead(path)
T=readtable(path,"Delimiter",",","TextType","string", ...
    "VariableNamingRule","preserve");
end

function value=localHash(path)
value=sixgr.integration.qualification.ArtifactResolver.fileHash(path);
end

function digest=localDigest(paths)
paths=sort(string(paths(:)));
lines=strings(0,1);
for path=reshape(paths,1,[])
    if isfile(path)
        lines(end+1,1)=replace(path,"\","/")+"|"+localHash(path); %#ok<AGROW>
    end
end
digest=lower(string(sixgr.util.sha256Hex( ...
    unicode2native(char(strjoin(lines,newline)+newline),"UTF-8"))));
end

function value=localUTC()
value=string(datetime("now","TimeZone","UTC", ...
    "Format","yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"));
end

function row=localExtraRow()
row=table2struct(sixgr.integration.qualification. ...
    QualificationArtifactAuditSchema.empty(1));
end
