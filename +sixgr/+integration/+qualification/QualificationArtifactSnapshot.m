classdef QualificationArtifactSnapshot
    %QUALIFICATIONARTIFACTSNAPSHOT Current exact filesystem artifact state.
    methods (Static)
        function [audit,resolution,adapterResults] = scan( ...
                runRoot,registry,runID,varargin)
            parser=inputParser;
            parser.addParameter("MaterializeAdapters",false, ...
                @(x)islogical(x)&&isscalar(x));
            parser.parse(varargin{:});
            materializeAdapters=parser.Results.MaterializeAdapters;
            root = localCanonicalRoot(runRoot);
            files = localFiles(root);
            manifest = localManifest(root);
            n = height(registry);
            audit = sixgr.integration.qualification. ...
                QualificationArtifactAuditSchema.empty(n);
            rows = repmat(localResolutionRow(),n,1);
            adapterResults = sixgr.integration.qualification. ...
                EvidenceAdapterRegistry.emptyResults();
            audit.RunID(:) = string(runID);
            audit.ArtifactID = string(registry.ArtifactID);
            audit.Domain = string(registry.Domain);
            audit.ArtifactType = upper(string(registry.ArtifactType));
            audit.ArtifactTypeSource(:) = "registry:ArtifactType";
            audit.MIMEType = sixgr.integration.qualification. ...
                QualificationArtifactAuditSchema.mimeFor(audit.ArtifactType);
            audit.Required(:) = true;
            audit.ProvenanceClass = string(registry.EvidenceClass);
            audit.SourceCSVRelativePath = string(registry.SourceCSV);
            for index=1:n
                [path,relative,method,failure,detail] = localResolve( ...
                    root,files,manifest,string(registry.ArtifactID(index)), ...
                    string(registry.FileName(index)));
                audit.RelativePath(index)=relative;
                audit.Present(index)=strlength(path)>0 && isfile(path);
                rows(index)=localResolutionRow();
                rows(index).ArtifactID=string(registry.ArtifactID(index));
                rows(index).RequestedFileName=string(registry.FileName(index));
                rows(index).ResolvedRelativePath=relative;
                rows(index).ResolutionMethod=method;
                rows(index).Status=localPass(audit.Present(index));
                rows(index).FailureCode=failure;
                rows(index).Details=detail;
                if ~audit.Present(index)
                    audit.Status(index)="MISSING";
                    audit.FailureCode(index)=localOr(failure, ...
                        "FULLSTACK:ArtifactMissing");
                    continue;
                end
                info=dir(path);
                audit.ByteCount(index)=double(info.bytes);
                audit.SHA256(index)=sixgr.integration.qualification. ...
                    ArtifactResolver.fileHash(path);
                audit.HashValid(index)=strlength(audit.SHA256(index))==64;
                try
                    [schemaValid,semanticValid,adapter,materialized] = ...
                        localValidate(path,registry(index,:), ...
                        audit.SHA256(index),materializeAdapters);
                    if ~isempty(adapter)
                        adapter.Domain(:)=string(registry.Domain(index));
                    end
                    if materialized
                        info=dir(path);
                        audit.ByteCount(index)=double(info.bytes);
                        audit.SHA256(index)=sixgr.integration. ...
                            qualification.ArtifactResolver.fileHash(path);
                        adapter.OutputArtifactSHA256(:)=audit.SHA256(index);
                    end
                    if ~isempty(adapter)
                        adapterResults=[adapterResults;adapter]; %#ok<AGROW>
                    end
                    audit.SchemaValid(index)=schemaValid;
                    audit.SemanticValid(index)=semanticValid;
                catch ME
                    audit.SchemaValid(index)=false;
                    audit.SemanticValid(index)=false;
                    audit.FailureCode(index)=string(ME.identifier);
                    if upper(string(registry.ArtifactType(index)))=="CSV" && ...
                            startsWith(string(ME.identifier), ...
                            "FULLSTACK:SchemaAdapter")
                        sourceTable=readtable(path,"Delimiter",",", ...
                            "TextType","string", ...
                            "VariableNamingRule","preserve");
                        required=localList( ...
                            registry.RequiredColumns(index));
                        missing=required(~ismember(required,string( ...
                            sourceTable.Properties.VariableNames)));
                        unsupported=sixgr.integration.qualification. ...
                            EvidenceAdapterRegistry.unsupported( ...
                            string(registry.FileName(index)), ...
                            string(sourceTable.Properties.VariableNames), ...
                            missing,audit.SHA256(index), ...
                            string(ME.identifier)+": "+string(ME.message));
                        unsupported.Domain(:)=string( ...
                            registry.Domain(index));
                        adapterResults=[adapterResults;unsupported]; %#ok<AGROW>
                    end
                end
                audit.SemanticAuditStatus(index)=localPass( ...
                    audit.SemanticValid(index));
                audit.PublicationStatus(index)="UNPUBLISHED";
                audit.Status(index)=localStatus(audit(index,:));
                audit.Valid(index)=audit.Status(index)=="PASS";
                if audit.Status(index)~="PASS" && ...
                        strlength(audit.FailureCode(index))==0
                    audit.FailureCode(index)=localFailure(audit.Status(index));
                end
            end
            resolution=struct2table(rows,"AsArray",true);
            if ~isempty(adapterResults)
                adapterResults=unique(adapterResults,"rows","stable");
            end
        end

        function materialization = materialize(sourceRoot,recoveryRoot,audit)
            source = localCanonicalRoot(sourceRoot);
            target = string(char(java.io.File(char(recoveryRoot)).getAbsolutePath()));
            rows = repmat(localMaterializationRow(),0,1);
            for index=1:height(audit)
                if ~audit.Present(index)
                    continue;
                end
                relative = localSafeRelative(audit.RelativePath(index));
                sourcePath = fullfile(source,replace(relative,"/",filesep));
                targetPath = fullfile(target,replace(relative,"/",filesep));
                sixgr.util.ensureDir(targetPath);
                sourceHash = sixgr.integration.qualification. ...
                    ArtifactResolver.fileHash(sourcePath);
                copied = false;
                if isfile(targetPath)
                    targetHash = sixgr.integration.qualification. ...
                        ArtifactResolver.fileHash(targetPath);
                else
                    targetHash = "";
                end
                if targetHash~=sourceHash
                    [ok,message]=copyfile(sourcePath,targetPath,"f");
                    if ~ok
                        error("FULLSTACK:ArtifactMaterializationFailed", ...
                            "Cannot copy %s: %s",relative,message);
                    end
                    copied=true;
                    targetHash=sixgr.integration.qualification. ...
                        ArtifactResolver.fileHash(targetPath);
                end
                row=localMaterializationRow();
                row.ArtifactID=audit.ArtifactID(index);
                row.RelativePath=relative;
                row.SourceSHA256=sourceHash;
                row.TargetSHA256=targetHash;
                row.Copied=copied;
                row.Status=localPass(sourceHash==targetHash);
                rows(end+1,1)=row; %#ok<AGROW>
            end
            materialization=struct2table(rows,"AsArray",true);
        end
    end
end

function root=localCanonicalRoot(raw)
if ~isfolder(raw)
    error("FULLSTACK:SourceRunMissing","Run root does not exist: %s",raw);
end
root=string(char(java.io.File(char(raw)).getCanonicalPath()));
end

function files=localFiles(root)
listing=dir(fullfile(root,"**","*"));
listing=listing(~[listing.isdir]);
n=numel(listing);
relative=strings(n,1);full=strings(n,1);name=strings(n,1);
prefix=root+filesep;
for index=1:n
    full(index)=string(char(java.io.File(fullfile( ...
        listing(index).folder,listing(index).name)).getCanonicalPath()));
    relative(index)=replace(extractAfter(full(index),strlength(prefix)),"\","/");
    name(index)=string(listing(index).name);
end
files=table(relative,full,name, ...
    'VariableNames',{'RelativePath','FullPath','FileName'});
end

function manifest=localManifest(root)
path=fullfile(root,"reports","csv","full_stack_artifact_manifest.csv");
if isfile(path)
    manifest=readtable(path,"Delimiter",",","TextType","string", ...
        "VariableNamingRule","preserve");
else
    manifest=table();
end
end

function [path,relative,method,failure,detail]= ...
        localResolve(root,files,manifest,artifactID,fileName)
path="";relative="";method="";failure="";detail="";
names=string(manifest.Properties.VariableNames);
if ~isempty(manifest) && all(ismember(["ArtifactID","RelativePath"],names))
    match=string(manifest.ArtifactID)==artifactID;
    if nnz(match)>1
        failure="FULLSTACK:AmbiguousArtifactManifestIdentity";
        detail="ArtifactID has multiple source-manifest rows.";
        return;
    elseif nnz(match)==1
        candidate=localSafeRelative(string(manifest.RelativePath(match)));
        fileMatch=string(files.RelativePath)==candidate;
        if nnz(fileMatch)==1
            path=string(files.FullPath(fileMatch));
            relative=candidate;
            method="SOURCE_MANIFEST_ARTIFACT_ID_CURRENT_SNAPSHOT";
            detail="Exact ArtifactID/path join; stale source hashes are not reused.";
            return;
        elseif nnz(fileMatch)>1
            failure="FULLSTACK:AmbiguousArtifactPath";
            detail="Exact manifest relative path resolves more than once.";
            return;
        end
    end
end
allowed=arrayfun(@localAllowed,string(files.RelativePath));
match=string(files.FileName)==fileName & allowed;
if nnz(match)==1
    path=string(files.FullPath(match));
    relative=string(files.RelativePath(match));
    method="EXACT_UNIQUE_REGISTERED_FILENAME";
    detail="Exact unique registered filename join.";
elseif nnz(match)>1
    failure="FULLSTACK:AmbiguousArtifactPath";
    detail="Registered filename exists under multiple allowed paths.";
else
    failure="FULLSTACK:ArtifactMissing";
    detail="No exact registered artifact path exists.";
end
if strlength(path)>0 && ~startsWith(lower(path),lower(root+filesep))
    error("FULLSTACK:ArtifactPathOutsideRunRoot", ...
        "Resolved artifact escaped the run root.");
end
end

function tf=localAllowed(path)
path=lower(replace(string(path),"\","/"));
tf=any(startsWith(path,["reports/","qualification_evidence/", ...
    "validation/","artifacts/","logs/","meta/"]));
end

function relative=localSafeRelative(raw)
relative=replace(strtrim(string(raw)),"\","/");
if startsWith(relative,"/") || contains(relative,"../") || ...
        contains(relative,":")
    error("FULLSTACK:UnsafeArtifactRelativePath", ...
        "Artifact relative path is unsafe: %s",relative);
end
end

function [schemaValid,semanticValid,adapter,materialized]= ...
        localValidate(path,spec,sourceHash,materializeAdapters)
type=upper(string(spec.ArtifactType));
adapter=sixgr.integration.qualification. ...
    EvidenceAdapterRegistry.emptyResults();
materialized=false;
if type=="CSV"
    T=readtable(path,"Delimiter",",","TextType","string", ...
        "VariableNamingRule","preserve");
    required=localList(spec.RequiredColumns);
    adapted=T;
    if any(~ismember(required,string(T.Properties.VariableNames)))
        [adapted,adapter]=sixgr.integration.qualification. ...
            EvidenceAdapterRegistry.adapt(string(spec.FileName),T, ...
            required,sourceHash);
        stillMissing=required(~ismember(required, ...
            string(adapted.Properties.VariableNames)));
        if ~isempty(stillMissing)
            unsupported=sixgr.integration.qualification. ...
                EvidenceAdapterRegistry.unsupported( ...
                string(spec.FileName), ...
                string(T.Properties.VariableNames),stillMissing, ...
                sourceHash,"No registered lossless mapping for: "+ ...
                strjoin(stillMissing,"|"));
            adapter=[adapter;unsupported];
        end
    end
    schemaValid=all(ismember(required,string(adapted.Properties.VariableNames)));
    minimum=str2double(string(spec.MinimumRows));
    if ~isfinite(minimum),minimum=0;end
    semanticValid=schemaValid && height(adapted)>=minimum && ...
        localFinite(adapted,required) && ~localPlaceholder(adapted);
    canMaterialize=materializeAdapters && schemaValid && ...
        ~isempty(adapter) && all(logical(adapter.Lossless));
    if canMaterialize
        sixgr.integration.qualification.QualificationAtomicWriter. ...
            writeTable(path,adapted);
        materialized=true;
    end
elseif type=="PNG"
    info=imfinfo(path);
    minimumWidth=str2double(string(spec.MinimumWidth));
    minimumHeight=str2double(string(spec.MinimumHeight));
    if ~isfinite(minimumWidth),minimumWidth=1;end
    if ~isfinite(minimumHeight),minimumHeight=1;end
    pixels=imread(path);
    schemaValid=true;
    semanticValid=double(info(1).Width)>=minimumWidth && ...
        double(info(1).Height)>=minimumHeight && ...
        std(double(pixels(:)))>1e-6;
else
    schemaValid=true;semanticValid=true;
end
end

function tf=localFinite(T,required)
tf=true;
for name=reshape(required,1,[])
    raw=T.(char(name));
    if isnumeric(raw) && any(~isfinite(double(raw(:))))
        tf=false;return;
    end
end
end

function tf=localPlaceholder(T)
tf=false;
for name=intersect(["Source","ExecutionBackend","ApproximationMode"], ...
        string(T.Properties.VariableNames),"stable")
    values=lower(string(T.(char(name))));
    tf=tf||any(contains(values,["placeholder","synthetic","fallback"]));
end
end

function values=localList(raw)
values=strip(split(string(raw),"|"));
values=values(strlength(values)>0);
end

function value=localStatus(row)
if ~row.Present
    value="MISSING";
elseif ~row.SchemaValid
    value="INVALID_SCHEMA";
elseif ~row.HashValid
    value="INVALID_HASH";
elseif ~row.SemanticValid
    value="INVALID_SEMANTICS";
else
    value="PASS";
end
end

function value=localFailure(status)
switch string(status)
    case "INVALID_SCHEMA",value="FULLSTACK:ArtifactSchemaInvalid";
    case "INVALID_HASH",value="FULLSTACK:ArtifactHashInvalid";
    case "INVALID_SEMANTICS",value="FULLSTACK:ArtifactSemanticInvalid";
    otherwise,value="FULLSTACK:ArtifactMissing";
end
end

function value=localPass(tf)
if tf,value="PASS";else,value="FAIL";end
end

function value=localOr(value,fallback)
if strlength(string(value))==0,value=string(fallback);end
end

function row=localResolutionRow()
row=struct("ArtifactID","","RequestedFileName","", ...
    "ResolvedRelativePath","","ResolutionMethod","","Status","FAIL", ...
    "FailureCode","","Details","");
end

function row=localMaterializationRow()
row=struct("ArtifactID","","RelativePath","","SourceSHA256","", ...
    "TargetSHA256","","Copied",false,"Status","FAIL");
end
