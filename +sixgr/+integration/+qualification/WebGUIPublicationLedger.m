classdef WebGUIPublicationLedger
    %WEBGUIPUBLICATIONLEDGER Prove selected artifacts are browser-addressable.
    methods (Static)
        function T=build(ctx)
            registry=ctx.Profile.SelectedArtifactRegistry;
            n=height(registry);
            published=false(n,1);
            previewable=false(n,1);
            downloadable=false(n,1);
            provenance=false(n,1);
            validation=false(n,1);
            sourceSHA=strings(n,1);
            artifactSHA=strings(n,1);
            status=repmat("FAIL",n,1);
            artifactIndex=sixgr.integration.qualification. ...
                RunArtifactIndex.build(ctx.RunFolder);
            for index=1:n
                name=string(registry.FileName(index));
                path=localFindUniqueOrEmpty(artifactIndex,name);
                exists=strlength(path)>0;
                published(index)=ctx.WebGUILaunched&&ctx.WebGUISecured&&exists;
                previewable(index)=published(index)&& ...
                    ismember(string(registry.ArtifactType(index)),["CSV","PNG"]);
                downloadable(index)=published(index);
                provenance(index)=published(index)&& ...
                    strlength(string(registry.EvidenceClass(index)))>0;
                validation(index)=published(index);
                if exists
                    artifactSHA(index)=sixgr.integration.qualification. ...
                        FullStackRunContext.fileHash(path);
                end
                sources=localList(registry.SourceCSV(index));
                if numel(sources)==1
                    sourcePath=localFindUniqueOrEmpty( ...
                        artifactIndex,sources(1));
                    if strlength(sourcePath)>0
                        sourceSHA(index)=sixgr.integration.qualification. ...
                            FullStackRunContext.fileHash(sourcePath);
                    end
                end
                if published(index)&&previewable(index)&& ...
                        downloadable(index)&&provenance(index)&&validation(index)
                    status(index)="PASS";
                end
            end
            unpublishedCount=nnz(~published);
            missingBadgeCount=nnz(~provenance);
            page=repmat("Results",n,1);
            section=string(registry.WebGUISection);
            T=table(repmat(ctx.RunID,n,1),page,section, ...
                string(registry.ArtifactID),published,previewable, ...
                downloadable,provenance,validation, ...
                repmat(ctx.WebGUIAuthMode,n,1), ...
                string(registry.EvidenceClass),sourceSHA,artifactSHA, ...
                repmat(unpublishedCount,n,1), ...
                repmat(missingBadgeCount,n,1),status, ...
                'VariableNames',{'RunID','Page','Section','ArtifactID', ...
                'Published','Previewable','Downloadable', ...
                'ProvenanceVisible','ValidationVisible', ...
                'WebGUIAuthMode','EvidenceClass','SourceCSV_SHA256', ...
                'ArtifactSHA256', ...
                'UnpublishedRequiredArtifactCount', ...
                'MissingProvenanceBadgeCount','Status'});
            sixgr.util.csvWriteTable(fullfile(ctx.CSVDir, ...
                "full_stack_webgui_publication.csv"),T);
        end
    end
end

function out=localList(value)
out=strip(split(string(value),"|"));
out=out(strlength(out)>0);
end

function path=localFindUniqueOrEmpty(artifactIndex,name)
[path,uniquePath]=sixgr.integration.qualification. ...
    RunArtifactIndex.findUnique(artifactIndex,name);
if ~uniquePath,path="";end
end
