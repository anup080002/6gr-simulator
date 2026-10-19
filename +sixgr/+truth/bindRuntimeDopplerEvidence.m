function row = bindRuntimeDopplerEvidence(row,state,ue,cellIndex)
%BINDRUNTIMEDOPPLEREVIDENCE Audit the channel object, never a radial surrogate.
row.ProjectedRadialDopplerHz = double(state.LargeScaleState.Doppler_Hz(ue,cellIndex));
row.SignedDoppler_Hz = double(state.LargeScaleState.SignedDoppler_Hz(ue,cellIndex));
user = struct();
if isfield(state.LargeScaleState,'UEVelocity_mps')
    user.RuntimeUEVelocity_mps = state.LargeScaleState.UEVelocity_mps(ue,:);
end
cfg = sixgr.channel.bindRuntimeDoppler(state.CfgMobility,user);
row.ExpectedDopplerHz = cfg.channel.doppler_Hz;
row.DopplerQuantity = "maximum_fading_doppler";
row.DopplerSourceMode = string(sixgr.util.structGet(cfg,'channel.dopplerSourceMode','configured'));
row.AppliedDopplerHz = NaN;
row.AppliedDopplerSource = "not_yet_materialized";
channels = sixgr.util.structGet(state,'RuntimeChannelStates',struct([]));
if isfield(state,'SharedWaveformStream') && ...
        isa(state.SharedWaveformStream,'sixgr.truth.CoupledWaveformStream')
    channels = state.SharedWaveformStream.directionalChannelState(ue,"DL");
else
    key = sixgr.channel.ChannelFactory.runtimeChannelKey(cfg,"DL", ...
        'UEIndex',ue,'ServingCell',cellIndex);
    key = sixgr.channel.ChannelFactory.runtimeChannelStateKey(cfg,key);
    keep = arrayfun(@(ch) string(sixgr.util.structGet(ch,'StateKey', ...
        sixgr.util.structGet(ch,'LinkKey',''))) == string(key),channels);
    channels = channels(keep);
end
for index = 1:numel(channels)
    ch = channels(index);
    if ~logical(sixgr.util.structGet(ch,'Materialized',false)), continue; end
    if isfield(ch,'Obj') && isobject(ch.Obj) && isprop(ch.Obj,'MaximumDopplerShift')
        value = double(ch.Obj.MaximumDopplerShift);
        source = string(class(ch.Obj))+".MaximumDopplerShift";
    else
        % Static reciprocal wrappers retain the actual constructed native
        % object's setting in metadata; never substitute a config value.
        value = sixgr.util.structGet(ch,'Meta.MaximumDopplerShift_Hz',NaN);
        source = string(sixgr.util.structGet(ch,'Meta.MaximumDopplerEvidenceSource',''));
    end
    if isnumeric(value) && ~isempty(value) && all(isfinite(value(:))) && strlength(source)>0
        row.AppliedDopplerHz = max(double(value(:)));
        row.AppliedDopplerSource = source;
        return;
    end
end
end
