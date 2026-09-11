function policy=resolveWaveformBundlePublicationPolicy(cfg,contractRasterAuthority)
% Separate legacy MATLAB rendering from canonical live CSV-derived PNGs.
% The resolved YAML remains the authority for both. The terminal artifact
% contract disables only the legacy producer, not the live CSV renderer.
validateattributes(contractRasterAuthority,{'logical'},{'scalar'});
figures=logical(sixgr.util.structGet(cfg,'outputs.saveFigures',false));
png=logical(sixgr.util.structGet(cfg,'outputs.savePNG',false));
live=logical(sixgr.util.structGet(cfg,'outputs.liveCSVPNGEnabled',false));
policy=struct('SaveFigures',figures && ~contractRasterAuthority, ...
    'LiveCSVPNGEnabled',figures && png && live);
end
