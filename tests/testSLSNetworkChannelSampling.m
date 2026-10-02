function ok=testSLSNetworkChannelSampling()
% Exact static response comparison. Moving-channel adaptive sampling rejected.
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
