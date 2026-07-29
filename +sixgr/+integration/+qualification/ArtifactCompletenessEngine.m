classdef ArtifactCompletenessEngine
    %ARTIFACTCOMPLETENESSENGINE Structural and semantic selected-preset audit.
    methods (Static)
        function audit=run(ctx)
            registry=sixgr.integration.qualification. ...
                ArtifactRequirementRegistry.load(ctx.Profile);
            [manifest,csvAudit,imageAudit,combined]=localScan(ctx,registry);
            sixgr.util.csvWriteTable(fullfile(ctx.CSVDir, ...
                "all_csv_artifact_audit.csv"),csvAudit);
            sixgr.util.csvWriteTable(fullfile(ctx.CSVDir, ...
                "all_image_artifact_audit.csv"),imageAudit);
            completeness=localCompleteness(registry,csvAudit,imageAudit);
            sixgr.util.csvWriteTable(fullfile(ctx.CSVDir, ...
                "all_artifact_completeness.csv"),completeness);
            sixgr.util.csvWriteTable(fullfile(ctx.CSVDir, ...
                "full_stack_artifact_audit.csv"),combined);
            localWriteManifest(ctx,manifest);
            audit=struct("Manifest",manifest,"CSVAudit",csvAudit, ...
                "ImageAudit",imageAudit,"Completeness",completeness, ...
                "Combined",combined,"Passed", ...
                all(string(combined.Status)=="PASS"));
        end

        function manifest=finalizeManifest(ctx)
            registry=sixgr.integration.qualification. ...
                ArtifactRequirementRegistry.load(ctx.Profile);
            [manifest,~,~,~]=localScan(ctx,registry);
            localWriteManifest(ctx,manifest);
        end
    end
end

function [manifest,csvAudit,imageAudit,combined]=localScan(ctx,registry)
n=height(registry);
mrows=repmat(localManifestRow(),n,1);
crows=repmat(localCSVRow(),0,1);
irows=repmat(localImageRow(),0,1);
arows=repmat(localCombinedRow(),n,1);
artifactIndex=sixgr.integration.qualification.RunArtifactIndex. ...
    build(ctx.RunFolder);
semanticIndex=localImageSemanticIndex(artifactIndex);
for index=1:n
    spec=registry(index,:);
    name=string(spec.FileName);
    [path,uniquePath]=sixgr.integration.qualification. ...
        RunArtifactIndex.findUnique(artifactIndex,name);
    present=strlength(path)>0&&uniquePath;
    schemaValid=false;semanticValid=false;hashValid=false;
    failure="";details="";
    placeholder=false;byteCount=0;sha="";
    if present
        info=dir(path);byteCount=info.bytes;
        sha=sixgr.integration.qualification.FullStackRunContext.fileHash(path);
        hashValid=strlength(sha)==64;
        if string(spec.ArtifactType)=="CSV"
            [schemaValid,semanticValid,placeholder,failure,details,crow]= ...
                localValidateCSV(path,spec);
            crows(end+1,1)=crow; %#ok<AGROW>
        else
            [schemaValid,semanticValid,failure,details,irow]= ...
                localValidateImage(path,spec,artifactIndex,semanticIndex);
            irows(end+1,1)=irow; %#ok<AGROW>
        end
    else
        failure="FULLSTACK:ArtifactMissingOrAmbiguous";
        details="Required artifact was absent or had duplicate paths.";
        if string(spec.ArtifactType)=="CSV"
            crow=localCSVRow();crow.ArtifactID=char(spec.ArtifactID);
            crow.FileName=char(name);crow.Required=true;
            crow.FailureCode=char(failure);crows(end+1,1)=crow; %#ok<AGROW>
        else
            irow=localImageRow();irow.ArtifactID=char(spec.ArtifactID);
            irow.FileName=char(name);irow.Required=true;
            irow.FailureCode=char(failure);irows(end+1,1)=irow; %#ok<AGROW>
        end
    end
    published=ctx.WebGUILaunched&&present;
    valid=present&&schemaValid&&semanticValid&&hashValid&&~placeholder;
    mrows(index)=struct("ArtifactID",char(spec.ArtifactID), ...
        "RunID",char(ctx.RunID),"Domain",char(spec.Domain), ...
        "ArtifactType",char(spec.ArtifactType), ...
        "RelativePath",char(localRelative(path,ctx.RunFolder)), ...
        "FileName",char(name),"ByteCount",double(byteCount), ...
        "SHA256",char(localManifestHash(name,sha)), ...
        "SourceArtifactIDs",char(localSourceIDs(spec,registry)), ...
        "EvidenceClass",char(spec.EvidenceClass), ...
        "Validity",char(localValidity(valid)), ...
        "Placeholder",logical(placeholder), ...
        "WebGUIPublished",logical(published), ...
        "GeneratedUTC",char(localUTC()));
    arows(index)=struct("ArtifactID",char(spec.ArtifactID), ...
        "FileName",char(name),"RequiredForPreset",true, ...
        "Present",logical(present),"SchemaValid",logical(schemaValid), ...
        "HashValid",logical(hashValid),"SemanticValid",logical(semanticValid), ...
        "WebGUIPublished",logical(published), ...
        "Status",char(localStatus(valid&&published)), ...
        "FailureCode",char(failure),"Details",char(details));
end
manifest=struct2table(mrows,"AsArray",true);
csvAudit=struct2table(crows,"AsArray",true);
imageAudit=struct2table(irows,"AsArray",true);
combined=struct2table(arows,"AsArray",true);
end

function [schemaValid,semanticValid,placeholder,failure,details,row]= ...
    localValidateCSV(path,spec)
row=localCSVRow();row.ArtifactID=char(spec.ArtifactID);
row.FileName=char(spec.FileName);row.Required=true;
schemaValid=false;semanticValid=false;placeholder=false;
failure="";details="";
try
    T=readtable(path,"TextType","string","VariableNamingRule","preserve");
    required=localList(spec.RequiredColumns);
    headerValid=all(ismember(required,string(T.Properties.VariableNames)));
    minRows=max(1,str2doubleDefault(spec.MinimumRows,1));
    minValid=height(T)>=minRows;
    pk=localList(spec.PrimaryKey);
    pkValid=true;
    if ~isempty(pk)&&all(ismember(pk,string(T.Properties.VariableNames)))
        keys=strings(height(T),1);
        for key=reshape(pk,1,[])
            keys=keys+"|"+string(T.(char(key)));
        end
        pkValid=numel(unique(keys))==numel(keys);
    elseif ~isempty(pk)
        pkValid=false;
    end
    finiteValid=localFiniteRequired(T,required);
    placeholder=localPlaceholder(T);
    schemaValid=headerValid&&minValid&&pkValid;
    semanticValid=finiteValid&&~placeholder;
    if ~schemaValid
        failure="FULLSTACK:CSVSchemaInvalid";
    elseif ~semanticValid
        failure="FULLSTACK:CSVSemanticInvalid";
    end
    details=sprintf("rows=%d required=%d header=%d pk=%d finite=%d placeholder=%d", ...
        height(T),numel(required),headerValid,pkValid,finiteValid,placeholder);
    row.Present=true;
    row.HeaderValid=headerValid;row.PrimaryKeyValid=pkValid;
    row.MinimumRowsValid=minValid;row.FiniteValuesValid=finiteValid;
    row.Status=char(localStatus(schemaValid&&semanticValid));
    row.FailureCode=char(failure);
catch ME
    failure="FULLSTACK:CSVParseFailed";
    details=string(ME.identifier)+": "+string(ME.message);
    row.FailureCode=char(failure);
end
end

function [decodeValid,semanticValid,failure,details,row]= ...
    localValidateImage(path,spec,artifactIndex,semanticIndex)
row=localImageRow();row.ArtifactID=char(spec.ArtifactID);
row.FileName=char(spec.FileName);row.Required=true;
decodeValid=false;semanticValid=false;failure="";details="";
try
    info=imfinfo(path);pixels=imread(path);
    decodeValid=true;
    minWidth=str2doubleDefault(spec.MinimumWidth,900);
    minHeight=str2doubleDefault(spec.MinimumHeight,600);
    dimensionsValid=double(info.Width)>=minWidth&& ...
        double(info.Height)>=minHeight;
    nonblank=std(double(pixels(:)))>1e-6;
    sources=localList(spec.SourceCSV);
    sourceValid=true;
    for source=reshape(sources,1,[])
        [sourcePath,uniquePath]=sixgr.integration.qualification. ...
            RunArtifactIndex.findUnique(artifactIndex,source);
        sourceValid=sourceValid&&uniquePath&&strlength(sourcePath)>0;
    end
    imageName=char(string(spec.FileName));
    semanticAudit=isKey(semanticIndex,imageName)&& ...
        logical(semanticIndex(imageName));
    semanticValid=dimensionsValid&&nonblank&&sourceValid&&semanticAudit;
    if ~semanticValid,failure="FULLSTACK:PNGSemanticInvalid";end
    details=sprintf("width=%d height=%d dimensions=%d nonblank=%d source=%d semantic=%d", ...
        info.Width,info.Height,dimensionsValid,nonblank,sourceValid,semanticAudit);
    row.Present=true;row.DecodeValid=decodeValid;
    row.DimensionsValid=dimensionsValid;row.Nonblank=nonblank;
    row.SourceCSVHashValid=sourceValid;
    row.SemanticAuditValid=semanticAudit;
    row.Status=char(localStatus(decodeValid&&semanticValid));
    row.FailureCode=char(failure);
catch ME
    failure="FULLSTACK:PNGDecodeFailed";
    details=string(ME.identifier)+": "+string(ME.message);
    row.FailureCode=char(failure);
end
end

function semanticIndex=localImageSemanticIndex(artifactIndex)
semanticIndex=containers.Map("KeyType","char","ValueType","logical");
audits=sixgr.integration.qualification.RunArtifactIndex. ...
    endingWith(artifactIndex,"image_semantic_audit.csv");
for index=1:numel(audits)
    try
        T=readtable(audits(index), ...
            "TextType","string","VariableNamingRule","preserve");
    catch
        continue;
    end
    imageCol=intersect(["ImageFile","FileName","PNGFile"], ...
        string(T.Properties.VariableNames),"stable");
    if isempty(imageCol),continue;end
    images=string(T.(char(imageCol(1))));
    for rowIndex=1:height(T)
        imageName=char(images(rowIndex));
        if strlength(string(imageName))==0,continue;end
        if ismember("Status",string(T.Properties.VariableNames))
            valid=upper(string(T.Status(rowIndex)))=="PASS";
        else
            valid=true;
        end
        if isKey(semanticIndex,imageName)
            semanticIndex(imageName)=semanticIndex(imageName)&&valid;
        else
            semanticIndex(imageName)=logical(valid);
        end
    end
end
end

function tf=localFiniteRequired(T,required)
tf=true;
for name=reshape(required,1,[])
    if ~ismember(name,string(T.Properties.VariableNames)),tf=false;return;end
    raw=T.(char(name));
    if isnumeric(raw)
        tf=tf&&all(isfinite(double(raw)));
    end
end
end

function tf=localPlaceholder(T)
tf=false;
if ismember("Placeholder",string(T.Properties.VariableNames))
    raw=T.Placeholder;
    if islogical(raw)||isnumeric(raw)
        tf=any(logical(raw));
    else
        tf=any(ismember(lower(strtrim(string(raw))),["true","1","yes"]));
    end
end
for name=intersect(["Source","ExecutionBackend","ApproximationMode"], ...
        string(T.Properties.VariableNames),"stable")
    values=lower(string(T.(char(name))));
    tf=tf||any(contains(values,["placeholder","synthetic","fallback"]));
end
end

function completeness=localCompleteness(registry,csvAudit,imageAudit)
domains=unique(string(registry.Domain),"stable");
rows=repmat(struct("Domain","","RequiredCSV",0,"PresentCSV",0, ...
    "ValidCSV",0,"RequiredPNG",0,"PresentPNG",0,"ValidPNG",0, ...
    "CompletenessPct",0,"Status","FAIL"),numel(domains),1);
for index=1:numel(domains)
    domain=domains(index);spec=registry(string(registry.Domain)==domain,:);
    csvIDs=string(spec.ArtifactID(spec.ArtifactType=="CSV"));
    pngIDs=string(spec.ArtifactID(spec.ArtifactType=="PNG"));
    cmask=ismember(string(csvAudit.ArtifactID),csvIDs);
    imask=ismember(string(imageAudit.ArtifactID),pngIDs);
    validCSV=nnz(cmask&string(csvAudit.Status)=="PASS");
    validPNG=nnz(imask&string(imageAudit.Status)=="PASS");
    presentCSV=nnz(cmask&logical(csvAudit.Present));
    presentPNG=nnz(imask&logical(imageAudit.Present));
    requiredCount=numel(csvIDs)+numel(pngIDs);
    validCount=validCSV+validPNG;
    pct=100*validCount/max(requiredCount,1);
    rows(index)=struct("Domain",char(domain),"RequiredCSV",numel(csvIDs), ...
        "PresentCSV",presentCSV,"ValidCSV",validCSV, ...
        "RequiredPNG",numel(pngIDs),"PresentPNG",presentPNG, ...
        "ValidPNG",validPNG,"CompletenessPct",pct, ...
        "Status",char(localStatus(validCount==requiredCount)));
end
completeness=struct2table(rows,"AsArray",true);
end

function localWriteManifest(ctx,manifest)
path=fullfile(ctx.CSVDir,"full_stack_artifact_manifest.csv");
sixgr.util.csvWriteTable(path,manifest);
payload=struct("run_id",char(ctx.RunID), ...
    "suite_preset",char(ctx.Profile.Preset), ...
    "resolved_yaml_sha256",char(ctx.ResolvedYAMLSHA256), ...
    "executed_yaml_sha256",char(ctx.ExecutedYAMLSHA256), ...
    "manifest_csv_sha256",char( ...
        sixgr.integration.qualification.FullStackRunContext.fileHash(path)), ...
    "artifacts",table2struct(manifest));
sixgr.util.jsonWrite(fullfile(ctx.ReportsDir, ...
    "full_stack_artifact_manifest.json"),payload);
end

function ids=localSourceIDs(spec,registry)
sources=localList(spec.SourceCSV);ids=strings(0,1);
for source=reshape(sources,1,[])
    mask=string(registry.FileName)==source;
    ids=[ids;string(registry.ArtifactID(mask))]; %#ok<AGROW>
end
ids=strjoin(unique(ids,"stable"),"|");
end

function hash=localManifestHash(name,hash)
if string(name)=="full_stack_artifact_manifest.csv"
    % A manifest cannot contain its own final byte hash. The JSON sidecar
    % hashes the finalized CSV; every other contracted artifact is bound here.
    hash="";
end
end

function out=localList(value)
out=strip(split(string(value),"|"));
out=out(strlength(out)>0);
end

function rel=localRelative(path,root)
if strlength(path)==0,rel="";return;end
rel=replace(string(path),string(root)+filesep,"");
rel=replace(rel,"\","/");
end

function value=str2doubleDefault(raw,default)
value=str2double(string(raw));
if ~(isscalar(value)&&isfinite(value)),value=default;end
end

function value=localValidity(tf)
if tf,value="VALID";else,value="INVALID";end
end

function value=localStatus(tf)
if tf,value="PASS";else,value="FAIL";end
end

function value=localUTC()
value=string(datetime("now","TimeZone","UTC", ...
    "Format","yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"));
end

function row=localManifestRow()
row=struct("ArtifactID","","RunID","","Domain","","ArtifactType","", ...
    "RelativePath","","FileName","","ByteCount",0,"SHA256","", ...
    "SourceArtifactIDs","","EvidenceClass","","Validity","INVALID", ...
    "Placeholder",false,"WebGUIPublished",false,"GeneratedUTC","");
end

function row=localCSVRow()
row=struct("ArtifactID","","FileName","","Required",true, ...
    "Present",false,"HeaderValid",false,"PrimaryKeyValid",false, ...
    "MinimumRowsValid",false,"FiniteValuesValid",false, ...
    "Status","FAIL","FailureCode","");
end

function row=localImageRow()
row=struct("ArtifactID","","FileName","","Required",true, ...
    "Present",false,"DecodeValid",false,"DimensionsValid",false, ...
    "Nonblank",false,"SourceCSVHashValid",false, ...
    "SemanticAuditValid",false,"Status","FAIL","FailureCode","");
end

function row=localCombinedRow()
row=struct("ArtifactID","","FileName","","RequiredForPreset",true, ...
    "Present",false,"SchemaValid",false,"HashValid",false, ...
    "SemanticValid",false,"WebGUIPublished",false,"Status","FAIL", ...
    "FailureCode","","Details","");
end
