function channel=createNetworkSpatialChannel(cfg,sampleRate,direction,seed)
%CREATENETWORKSPATIALCHANNEL One physical fading recipe for SLS and replay.
% Construct the canonical gNB-to-UE channel first. UL uses the native TDD
% transpose operation, not a separately drawn UE-to-gNB channel or H'.
arguments
    cfg (1,1) struct
    sampleRate (1,1) double {mustBePositive,mustBeFinite}
    direction (1,1) string {mustBeMember(direction,["DL","UL"])}
    seed = []
end
p=cfg.system.linkAbstraction.networkSpatial;
validateattributes([p.bsPorts p.uePorts],{'numeric'},{'integer','positive','finite','numel',2});
assert(strcmpi(sixgr.phy.frame.resolveDuplexMode(cfg),'TDD'), ...
    'sixgr:abstraction:NetworkDuplex','The shared network fading recipe requires TDD.');
model=string(sixgr.util.structGet(cfg,'channel.model', ...
    sixgr.util.structGet(cfg,'channel.type','')));
% Large-scale propagation and small-scale fading are distinct configured
% stages. Request the fading family explicitly without overwriting the
% resolved configuration or bypassing the factory's profile conflict checks.
if any(strcmpi(model,["TR38901","ABG"]))
    enabled=sixgr.util.structGet(cfg,'channel.fading.enable',false);
    family=upper(strtrim(string(sixgr.util.structGet(cfg,'channel.fading.model',''))));
    profile=upper(strtrim(string(sixgr.util.structGet(cfg,'channel.fading.profile',''))));
    assert(isscalar(enabled) && isequal(enabled,true) && isscalar(family) && ...
        any(family==["TDL","CDL"]) && isscalar(profile) && ...
        startsWith(profile,family+"-"), ...
        'sixgr:abstraction:NetworkFadingProfile', ...
        'Large-scale channel requires enabled fading with matching TDL/CDL family and concrete fading.profile.');
    for field=["tdlProfile","cdlProfile","delayProfile"]
        declared=upper(strtrim(string(sixgr.util.structGet(cfg,"channel."+field,''))));
        assert(isscalar(declared) && (strlength(declared)==0 || declared==profile), ...
            'sixgr:abstraction:NetworkFadingProfile', ...
            'channel.%s must not contradict the configured small-scale fading.profile.',field);
    end
    model=family;
end
channel=sixgr.channel.ChannelFactory.create(cfg,'Model',model,'LinkDirection','DL', ...
    'SampleRate',sampleRate,'NumTxAnt',p.bsPorts,'NumRxAnt',p.uePorts,'Seed',seed);
ch=channel.Object;
assert(isa(ch,'nrTDLChannel') || isa(ch,'nrCDLChannel'), ...
    'sixgr:abstraction:NetworkChannel','Require native concrete TDL/CDL, not a flat surrogate.');
assert(~ch.NormalizeChannelOutputs,'sixgr:abstraction:NetworkPower', ...
    'Receive-count normalization breaks reciprocal per-connector power.');
sampling=string(sixgr.util.structGet(p,'channelResponseSampling','signal_rate'));
assert(any(sampling==["signal_rate","static_exact"]), ...
    'sixgr:abstraction:NetworkSampling','Unknown channel response sampling policy.');
assert(sampling~="static_exact" || ch.MaximumDopplerShift==0, ...
    'sixgr:abstraction:NetworkSamplingMobility','Static-exact sampling requires zero Doppler.');
if isa(ch,'nrTDLChannel')
    ch.PathGainSampleRate='signal';
    if sampling=="static_exact", ch.PathGainSampleRate='auto'; end
else
    ch.SampleDensity=Inf;
    if sampling=="static_exact", ch.SampleDensity=64; end
end
if direction=="UL"
    assert(ismethod(ch,'swapTransmitAndReceive'), ...
        'sixgr:abstraction:NetworkReciprocity','Native reciprocal channel operation is unavailable.');
    swapTransmitAndReceive(ch);
end
channel.Object=ch;
channel.Meta.SLSChannelResponseSampling=sampling;
channel.Meta.LinkDirection=direction;
channel.Meta.RuntimeTDDReciprocityExact=true;
channel.Meta.RuntimeTDDReciprocitySource="native_swapTransmitAndReceive_canonical_bs_to_ue";
channel.Meta.NumTxAnt=p.bsPorts; channel.Meta.NumRxAnt=p.uePorts;
if direction=="UL"
    channel.Meta.NumTxAnt=p.uePorts; channel.Meta.NumRxAnt=p.bsPorts;
end
end
