function [cfg,nSlots] = e2eReceivedAccessConfig(root,nUE,trafficModel)
% Fully resolved cold-access configuration for E2E publication regressions.
% Not a PHY calibration fixture: actual PBCH/SIB1/RA and DL grants execute.
if nargin<2, nUE=2; end
if nargin<3, trafficModel="traceReplay"; end
trafficModel=string(trafficModel);
assert(isscalar(trafficModel) && ismember(trafficModel,["traceReplay","mmtc","xr"]), ...
    'sixgr:test:UnsupportedPublicationTraffic','Select traceReplay, mmtc or xr explicitly.');
validateattributes(nUE,{'numeric'},{'scalar','integer','>=',1,'<=',3});
scenario=sixgr.lls6g.config.loadScenarioConfig(fullfile(pwd,'simulator', ...
    'configs','scenarios','lls_causal_access_to_data_wiring_tdd.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(scenario,root);
cfg.run.strictMode=true;
cfg.channel.model="TDL-C";
cfg.channel.tdlProfile="TDL-C";
cfg.channel.cdlProfile="";
cfg.channel.delayProfile="TDL-C";
cfg.channel.awgnOnly=false;
cfg.channel.dopplerHz=70;
cfg.channel.fading.enable=true;
cfg.channel.fading.model="TDL";
cfg.channel.fading.profile="TDL-C";
cfg.channel.fading.maxDoppler_Hz=70;
cfg.scenario.ue.nUE=nUE;
cfg.scenario.nUE=nUE;
nSlots=40+30*(nUE-1);
cfg.traffic.model="traceReplay";
cfg.traffic.trace.offeredBitsDL=200*ones(nSlots,nUE);
cfg.traffic.trace.offeredBitsUL=zeros(nSlots,nUE);
cfg.traffic.trace.transport="UDP";
cfg.traffic.trace.flowDirection="DL";
cfg.traffic.flowDirection="DL";
% These tests exercise publication with actual DL activity, not UL SRS
% qualification. Do not disable production control/SRS gates to run UL.
if trafficModel~="traceReplay"
    % Preserve the original bidirectional reporting fixtures' catalog
    % traffic and rank-one non-codebook UL domain. Access setup must not
    % silently turn them into physical codebook-SRS qualification tests.
    defaults=sixgr.config.defaultConfig();
    cfg.traffic=defaults.traffic;
    cfg.traffic.model=char(trafficModel);
    cfg.traffic.flows=struct('name',char(trafficModel), ...
        'service_profile',char(trafficModel),'direction',cfg.traffic.flowDirection, ...
        'protocol',cfg.traffic.transport,'qfi',cfg.traffic.qos.default5QI, ...
        'fiveQi',cfg.traffic.qos.default5QI, ...
        'packetDelayBudget_ms',cfg.traffic.packetDelayBudget_ms, ...
        'packetSize_bytes',cfg.traffic.packetSize_bytes, ...
        'packetInterval_ms',cfg.traffic.packetInterval_ms, ...
        'rate_Mbps',cfg.traffic.targetRate_Mbps,'jitterPct',cfg.traffic.jitterPct, ...
        'weight',1,'burstiness','medium');
    cfg.phy.pusch.transmissionScheme=defaults.phy.pusch.transmissionScheme;
    cfg.phy.pusch.TransmissionScheme=defaults.phy.pusch.transmissionScheme;
    cfg.phy.pusch.nLayers=defaults.phy.pusch.nLayers;
    cfg.phy.pusch.numLayers=defaults.phy.pusch.nLayers;
    assert(strcmpi(cfg.phy.pusch.transmissionScheme,'nonCodebook') && ...
        cfg.phy.pusch.nLayers==1 && strcmpi(cfg.traffic.flowDirection,'BIDIR'), ...
        'Review reporting fixtures if the original catalog traffic/UL domain changes.');
end
end
