function ok=testSLSNetworkChannelSampling()
% Exact static response comparison. Moving-channel adaptive sampling rejected.
request=sixgr.config.loadSimulationRequest( ...
    'simulator/configs/scenarios/sls_nr_tdd_21cell_connected.yaml');
public=request.Config;
savedChannel=public.channel;
for direction=["DL","UL"]
    built=sixgr.system.abstraction.createNetworkSpatialChannel(public,122880000,direction,9123);
    assert(isa(built.Object,'nrTDLChannel') && strcmp(built.Object.DelayProfile,'TDL-A'));
    assert(abs(built.Object.DelaySpread-30e-9)<1e-18);
    assert(built.Object.NumTransmitAntennas==4 && built.Object.NumReceiveAntennas==4);
    assert(isequaln(public.channel,savedChannel),'Fading selection must not overwrite large-scale configuration.');
end
for variant=1:5
    bad=public;
    switch variant
        case 1, bad.channel.fading.profile='TDL';
        case 2, bad.channel.fading=rmfield(bad.channel.fading,'profile');
        case 3, bad.channel.fading.model='CDL';
        case 4, bad.channel.fading.enable=false;
        case 5, bad.channel.tdlProfile='TDL-C';
    end
    rejected=false;
    try
        sixgr.system.abstraction.createNetworkSpatialChannel(bad,122880000,"DL",9123);
    catch cause
        assert(strcmp(cause.identifier,'sixgr:abstraction:NetworkFadingProfile'),'%s',cause.message);
        rejected=true;
    end
    assert(rejected,'Missing, disabled or contradictory fading must not become a default channel.');
end
sc=sixgr.lls6g.config.loadScenarioConfig('simulator/configs/scenarios/h4_100_tdla30_connected_adaptive.yaml');
cfg=sixgr.lls6g.buildInternalConfig(sc,tempname);
f=sixgr.lls6g.config.readConfigFile('simulator/configs/system/calibrated_link_abstraction.yaml');
cfg=sixgr.util.mergeStruct(cfg,f);
cfg.run.executionID='sampling_contract'; cfg.channel.normalizeChannelOutputs=false;
cfg.rf=struct(); cfg.phy.impairments=struct();
cfg.phy.carrier.NSizeGrid=6; cfg.phy.carrier.NStartGrid=0;
cfg.system.linkAbstraction.networkSpatial.bsPorts=4;
cfg.system.linkAbstraction.networkSpatial.uePorts=4;
cfg.system.linkAbstraction.networkSpatial.dlAntennaBasis='direct_ports';
cfg.channel.doppler_Hz=0; cfg.channel.fading.maxDoppler_Hz=0;
[scs,symbols]=ndgrid(0:71,0:13); coords=[scs(:),symbols(:)];
large=struct('Pathloss_dB',80,'TxPower_dBm',30);
for doppler=0
    cfg.channel.doppler_Hz=doppler; cfg.channel.fading.maxDoppler_Hz=doppler;
    cfg.system.linkAbstraction.networkSpatial.channelResponseSampling='signal_rate';
    dense=sixgr.system.abstraction.NetworkSpatialGrantProvider(cfg);
    cfg.system.linkAbstraction.networkSpatial.channelResponseSampling='static_exact';
    adaptive=sixgr.system.abstraction.NetworkSpatialGrantProvider(cfg);
    H=dense.channel('DL',1,1,0,large,coords);
    A=adaptive.channel('DL',1,1,0,large,coords);
    relative=norm(A(:)-H(:))/norm(H(:));
    fprintf('SLS_CHANNEL_SAMPLING_COMPARISON doppler_hz=%g relative_error=%g\n',doppler,relative);
    assert(relative<1e-12,'Static response must match the dense reference to numerical precision.');
    assert(size(A,3)==1008 && norm(A(:,:,1)-A(:,:,72),'fro')>1e-12, ...
        'Frequency selectivity must survive response sampling.');
    U=adaptive.channel('UL',1,1,0,large,coords);
    assert(isequal(U,permute(A,[2 1 3])));
    fprintf('SLS_CHANNEL_SAMPLING_PASS doppler_hz=%g relative_error=%g\n',doppler,relative);
end
cfg.channel.doppler_Hz=100; cfg.channel.fading.maxDoppler_Hz=100;
try
    sixgr.system.abstraction.NetworkSpatialGrantProvider(cfg);
    error('test:ExpectedError','Moving-channel adaptive sampling must be rejected.');
catch ME
    assert(strcmp(ME.identifier,'sixgr:abstraction:NetworkSamplingMobility'),'%s',ME.message);
end
cfg.system.linkAbstraction.networkSpatial.channelResponseSampling='unknown';
try
    sixgr.system.abstraction.NetworkSpatialGrantProvider(cfg);
    error('test:ExpectedError','Unknown sampling must be rejected.');
catch ME
    assert(strcmp(ME.identifier,'sixgr:abstraction:NetworkSampling'),'%s',ME.message);
end
ok=true;
end
