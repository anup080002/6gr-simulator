function [dlPath,ulPath]=constellationArtifactPaths(cfg,csvDir)
% Capture scope, not duplex/storage backend, determines the artifact name.
scope=string(sixgr.util.structGet(cfg,'outputs.constellationCaptureScope','preview'));
assert(isscalar(scope)&&any(scope==["preview","full_allocation"]), ...
    'sixgr:link:InvalidConstellationCaptureScope','Expected preview or full_allocation.');
suffix="preview";
if scope=="full_allocation", suffix="samples"; end
dlPath=fullfile(csvDir,"dl_constellation_"+suffix+".csv");
ulPath=fullfile(csvDir,"ul_constellation_"+suffix+".csv");
end
