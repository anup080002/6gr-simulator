classdef QualificationImageSemanticJoin
    %QUALIFICATIONIMAGESEMANTICJOIN Exact path/hash/source semantic binding.
    methods (Static)
        function [audit,trace] = apply(audit,semanticAudit,runRoot)
            required = ["ImageFile","SourceCSV","SourceCSV_SHA256", ...
                "PNG_SHA256","Status"];
            names = string(semanticAudit.Properties.VariableNames);
            if any(~ismember(required,names))
                error("FULLSTACK:SemanticAuditSchemaInvalid", ...
                    "Image semantic audit lacks: %s", ...
                    strjoin(required(~ismember(required,names)),", "));
            end
            root = string(char(java.io.File(char(runRoot)).getCanonicalPath()));
            pngRows=find(audit.ArtifactType=="PNG" & audit.Present);
            rows=repmat(localTraceRow(),numel(pngRows),1);
            for offset=1:numel(pngRows)
                index=pngRows(offset);
                relative=localPath(audit.RelativePath(index));
                imageName=string(java.io.File(char(relative)).getName());
                semanticNames=string(semanticAudit.ImageFile);
                direct=replace(semanticNames,"\","/")==relative;
                if ~any(direct) && all(~contains(semanticNames,["/","\\"]))
                    direct=semanticNames==imageName;
                end
                row=localTraceRow();
                row.ArtifactID=audit.ArtifactID(index);
                row.ImageRelativePath=relative;
                row.SemanticRowCount=nnz(direct);
                valid=false;
                failure="";
                details="";
                if nnz(direct)~=1
                    failure="FULLSTACK:SemanticAuditJoinCardinality";
                    details="Exact semantic row count must be one.";
                else
                    semantic=semanticAudit(direct,:);
                    imagePath=localFull(root,relative);
                    actualPNG=sixgr.integration.qualification. ...
                        ArtifactResolver.fileHash(imagePath);
                    pngHash=lower(string(semantic.PNG_SHA256));
                    row.PNGHashMatch=actualPNG==pngHash;
                    [sourceIndex,sourceRelative] = localSource( ...
                        audit,string(semantic.SourceCSV));
                    row.SourceCSVRelativePath=sourceRelative;
                    row.SourceRowCount=nnz(sourceIndex);
                    if nnz(sourceIndex)==1
                        sourcePath=localFull(root,sourceRelative);
                        actualSource=sixgr.integration.qualification. ...
                            ArtifactResolver.fileHash(sourcePath);
                        row.SourceHashMatch=actualSource==lower( ...
                            string(semantic.SourceCSV_SHA256));
                        row.SourceValid=audit.Present(sourceIndex) && ...
                            audit.HashValid(sourceIndex) && ...
                            localReadableNonemptyCSV(sourcePath);
                    end
                    row.SemanticStatusPass=upper(string(semantic.Status))=="PASS";
                    valid=row.SemanticStatusPass && row.PNGHashMatch && ...
                        row.SourceRowCount==1 && row.SourceHashMatch && ...
                        row.SourceValid;
                    if ~valid
                        failure="FULLSTACK:ImageSemanticBindingInvalid";
                        details="Path/hash/source semantic binding failed.";
                    else
                        details="Exact image and source path/hash join passed.";
                    end
                end
                audit.SemanticValid(index)=valid;
                audit.SemanticAuditStatus(index)=localPass(valid);
                if valid && audit.SchemaValid(index) && audit.HashValid(index)
                    audit.Status(index)="PASS";
                    audit.Valid(index)=true;
                    audit.FailureCode(index)="";
                else
                    audit.Status(index)="INVALID_SEMANTICS";
                    audit.Valid(index)=false;
                    audit.FailureCode(index)=failure;
                end
                row.Status=localPass(valid);
                row.FailureCode=failure;
                row.Details=details;
                rows(offset)=row;
            end
            trace=struct2table(rows,"AsArray",true);
        end
    end
end

function tf=localReadableNonemptyCSV(path)
try
    T=readtable(path,"Delimiter",",","TextType","string", ...
        "VariableNamingRule","preserve");
    tf=height(T)>0 && width(T)>0;
catch
    tf=false;
end
end

function [index,relative]=localSource(audit,source)
source=replace(string(source),"\","/");
paths=replace(string(audit.RelativePath),"\","/");
if contains(source,"/")
    index=find(paths==source & audit.ArtifactType=="CSV");
else
    names=arrayfun(@(x)string(java.io.File(char(x)).getName()),paths);
    index=find(names==source & audit.ArtifactType=="CSV");
end
if numel(index)==1
    relative=paths(index);
else
    relative="";
end
end

function full=localFull(root,relative)
full=string(char(java.io.File(fullfile(root, ...
    replace(relative,"/",filesep))).getCanonicalPath()));
if ~startsWith(lower(full),lower(root+filesep))
    error("FULLSTACK:ArtifactPathOutsideRunRoot", ...
        "Semantic artifact path escaped the run root.");
end
end

function path=localPath(raw)
path=replace(strtrim(string(raw)),"\","/");
if strlength(path)==0 || startsWith(path,"/") || contains(path,"../")
    error("FULLSTACK:InvalidSemanticArtifactPath", ...
        "Semantic audit path is not a safe run-relative path.");
end
end

function value=localPass(tf)
if tf,value="PASS";else,value="FAIL";end
end

function row=localTraceRow()
row=struct("ArtifactID","","ImageRelativePath","", ...
    "SemanticRowCount",0,"PNGHashMatch",false, ...
    "SourceCSVRelativePath","","SourceRowCount",0, ...
    "SourceHashMatch",false,"SourceValid",false, ...
    "SemanticStatusPass",false,"Status","FAIL", ...
    "FailureCode","","Details","");
end
