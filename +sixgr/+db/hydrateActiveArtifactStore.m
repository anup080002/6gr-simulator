function out = hydrateActiveArtifactStore(targetRoot)
%HYDRATEACTIVEARTIFACTSTORE Persist active MySQL run artifacts to disk.
%
% MySQL-backed web runs execute in a staging folder, but the browser and
% post-run audits read the public display folder. Hydration mirrors the
% exact stored artifact bytes back to that display folder without inventing
% or materializing replacement rows.

if nargin < 1
    targetRoot = "";
end
out = sixgr.db.artifactStore("hydrate_display_folder", targetRoot);
end
