classdef FilesystemArtifactPublisher
    %FILESYSTEMARTIFACTPUBLISHER Exact idempotent run-root publication.
    methods (Static)
        function T=publish(runID,runRoot,audit)
            root=string(char(java.io.File(char(runRoot)).getCanonicalPath()));
            present=audit(logical(audit.Present),:);
            n=height(present);
            status=repmat("FAIL",n,1);
            failure=strings(n,1);
            fullPath=strings(n,1);
            for index=1:n
                relative=replace(string(present.RelativePath(index)),"\","/");
                path=string(char(java.io.File(fullfile(root, ...
                    replace(relative,"/",filesep))).getCanonicalPath()));
                if ~startsWith(lower(path),lower(root+filesep))
                    failure(index)="FULLSTACK:PublicationPathOutsideRunRoot";
                    continue;
                end
                if isfile(path) && sixgr.integration.qualification. ...
                        ArtifactResolver.fileHash(path)==present.SHA256(index)
                    status(index)="PASS";
                    fullPath(index)=path;
                else
                    failure(index)="FULLSTACK:PublicationHashMismatch";
                end
            end
            T=table(repmat(string(runID),n,1),present.ArtifactID, ...
                present.RelativePath,fullPath,present.SHA256, ...
                repmat("FILESYSTEM",n,1),status,failure, ...
                'VariableNames',{'RunID','ArtifactID','RelativePath', ...
                'PublishedPath','SHA256','Publisher','Status','FailureCode'});
            if numel(unique(T.ArtifactID))~=height(T)
                error("FULLSTACK:DuplicateFilesystemPublication", ...
                    "Filesystem publication contains duplicate artifact IDs.");
            end
            T=sortrows(T,"ArtifactID");
        end
    end
end
