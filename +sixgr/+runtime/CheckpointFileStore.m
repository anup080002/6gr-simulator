classdef CheckpointFileStore
    % Versioned, content-addressed snapshots shared by checkpoint generations.
    % Never hard-link a mutable producer to the private snapshot. Both the
    % current source and any reused object are fully hashed, not trusted by
    % filename, size, timestamps or an in-memory cache.
    methods (Static)
        function [snapshot,digest,reused] = capture(base,source)
            scope=sixgr.runtime.ExecutionStageProfiler.scope("checkpoint","versioned_file_snapshot"); %#ok<NASGU>
            base=char(java.io.File(char(base)).getCanonicalPath());
            assert(isfile(source),'sixgr:checkpoint:MissingArtifact','Missing snapshot source.');
            before=dir(source);
            digest=string(sixgr.util.sha256File(source));
            snapshot="@objects/"+digest+".bin";
            target=sixgr.runtime.CheckpointFileStore.resolve(base,snapshot);
            reused=isfile(target);
            if reused
                info=dir(target);
                assert(info.bytes==before.bytes && string(sixgr.util.sha256File(target))==digest, ...
                    'sixgr:checkpoint:SnapshotObjectIntegrity','Existing snapshot object is corrupted.');
            else
                parent=fileparts(target); if ~isfolder(parent), mkdir(parent); end
                % Existing byte-verified publisher uses a sibling temporary
                % and never exposes a partially copied canonical object.
                sixgr.util.copyFileVerified(string(source),string(target),digest);
            end
            after=dir(source);
            assert(after.bytes==before.bytes && string(sixgr.util.sha256File(source))==digest, ...
                'sixgr:checkpoint:SnapshotSourceChanged','Producer changed during checkpoint capture.');
        end

        function path=resolve(base,snapshot)
            token=char(string(snapshot));
            assert(~isempty(regexp(token,'^@objects/[a-f0-9]{64}\.bin$','once')), ...
                'sixgr:checkpoint:SnapshotObjectPath','Invalid content-addressed snapshot reference.');
            base=char(java.io.File(char(base)).getCanonicalPath());
            path=char(java.io.File(fullfile(base,'objects',token(10:end))).getCanonicalPath());
            assert(startsWith(lower(string(path)),lower(string(base)+filesep+"objects"+filesep)), ...
                'sixgr:checkpoint:SnapshotObjectPath','Snapshot reference escaped its private store.');
        end
    end
end
