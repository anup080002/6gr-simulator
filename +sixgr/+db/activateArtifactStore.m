function out = activateArtifactStore(runFolder, cfg, meta)
if nargin < 3
    meta = struct();
end
out = sixgr.db.artifactStore("activate", runFolder, cfg, meta);
end
