function ok=testFixedMatrixAWGNRuntime()
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_5mhz_rank2_4tx2rx_awgn_m10db.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
assert(cfg.phy.nTxAnt==4 && cfg.phy.nRxAnt==2);
assert(cfg.phy.pdsch.maxLayers==2 && cfg.phy.pusch.maxLayers==2);
[common,control]=sixgr.phy.ra.resolveRARCommonControl(cfg,sixgr.phy.grid.makeCarrier(cfg));
assert(common.AggregationLevel==8 && control.NCCE==8 && ...
    isequal(common.SearchSpace.NumCandidates,[0 0 0 1 0]), ...
    'The low-SNR profile must carry its legal AL8-only common search space.');
H=cfg.channel.awgnSpatialMatrixDL;
assert(isequal(size(H),[2 4]) && norm(H*H'-eye(2),'fro')<1e-12);
info=struct('OFDM',struct('SampleRate',7680000));
initial=sixgr.channel.ChannelFactory.createRuntimeChannelState(cfg,'DL','UEIndex',1,'ServingCell',1);
initial.TargetUEIndex=1; initial.TargetServingCell=1;
initial=sixgr.channel.ChannelFactory.materializeRuntimeChannelState( ...
    initial,cfg,zeros(1,4),info,'NumTxAnt',4,'NumRxAnt',2);
x=reshape(complex(sin(1:400),cos(1:400)),100,4);
[y,replay,done,reference]=sixgr.channel.ChannelFactory.applyRuntimeChannelState( ...
    initial,x,'CaptureChannelReference',true,'InputSampleDomain','materialized_channel_ports', ...
    'OutputSampleAlignment','continuous_raw_samples');
assert(isequal(y,x*H.') && done.CurrentSampleIndex==100);
assert(strcmp(replay.RuntimeChannelOutputWaveformSHA256, ...
    sixgr.channel.ChannelFactory.runtimeNumericArraySHA256(y)));
assert(sixgr.channel.isAppliedChannelReference(reference));
assert(isequal(reshape(reference.PathGains(1,1,:,:),4,2),H.'));
bad=reference; bad.PathGains(1,1,1,1)=99;
assert(~sixgr.channel.isAppliedChannelReference(bad));
owner=sixgr.truth.SharedWaveformPhysicalRuntime(info.OFDM.SampleRate,0,1);
owner.addTransmitter('gnb',cfg,'DL',4,false);
owner.addTransmitter('ue',cfg,'UL',2,false);
owner.addReceiver('ue_rx',cfg,'DL',2,false);
owner.addReceiver('gnb_rx',cfg,'UL',4,false);
owner.addLink('matrix','gnb','ue_rx',initial,cfg);
owner.retargetTDDLink('matrix','ue','gnb_rx',cfg);
states=owner.channelStates(); reverse=states{1};
assert(reverse.NumTxAnt==2 && reverse.NumRxAnt==4 && ...
    isequal(reverse.Meta.AWGNSpatialMatrix,H.'));
u=x(:,1:2);
v=sixgr.channel.ChannelFactory.applyRuntimeChannelState( ...
    reverse,u,'InputSampleDomain','materialized_channel_ports');
assert(isequal(v,u*H));
owner.retargetTDDLink('matrix','gnb','ue_rx',cfg);
states=owner.channelStates();
assert(isequal(states{1}.Meta.AWGNSpatialMatrix,H));
fprintf('FIXED_MATRIX_AWGN_PASS DL=4x2 UL=2x4 singular_values=[1,1] no_hidden_gain=1 reciprocal=1\n');
ok=true;
end
