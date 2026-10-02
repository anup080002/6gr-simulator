function history=mapHARQHistory(resourceHistory,curve)
%MAPHARQHISTORY Remap every retained resource using the selected RV-prefix
% curve. Different independently fitted betas never reuse an older mapping.
assert(iscell(resourceHistory) && numel(resourceHistory)==numel(curve.RVSequence), ...
    'sixgr:abstraction:HARQFeatureHistory','One retained physical resource vector per HARQ attempt is required.');
history=zeros(1,numel(resourceHistory));
for k=1:numel(resourceHistory)
    gamma=double(resourceHistory{k});
    assert(~isempty(gamma) && all(isfinite(gamma),'all') && all(gamma>=0,'all'), ...
        'sixgr:abstraction:HARQFeatureHistory','Retained per-resource SINR must be finite and nonnegative.');
    if string(curve.Key.EffectiveSINRMethod)=="calibrated_eesm"
        history(k)=10*log10(sixgr.util.eesmLinear(gamma,curve.BetaLinear));
    else
        mapped=sixgr.phy.rsla.MIESMMapper.map(10*log10(gamma), ...
            curve.MILookup,string(curve.CurveID));
        history(k)=mapped.EffectiveSINRDb;
    end
end
end
