function ok=testSharedIdentityAWGNRuntime()
% Bounded prerequisite: exact four-port identity on a shared physical clock.
% Not a PDCCH/PUCCH/CSI/SRS or 400-MHz throughput acceptance claim.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
cfg=sixgr.config.defaultConfig();
cfg.channel.model='AWGN'; cfg.channel.awgnOnly=true;
cfg.channel.pathlossEnabled=false; cfg.channel.shadowFadingEnabled=false;
cfg.channel.sharedIdentityAWGNEnabled=false;
assert(~sixgr.channel.ChannelFactory.requiresRuntimeChannelState(cfg));
cfg.channel.sharedIdentityAWGNEnabled=true;
assert(sixgr.channel.ChannelFactory.requiresRuntimeChannelState(cfg));
cfg.phy.carrier.NSizeGrid=264;
cfg.phy.carrier.SubcarrierSpacing=120;
cfg.phy.carrier.SubcarrierSpacing_kHz=120;
cfg.phy.fc_Hz=7e9;
% Explicit duplex authority for this physical-operator component fixture.
cfg.phy.duplexMode='TDD';
cfg.frame.duplexMode='TDD';
cfg.channel.duplexMode='TDD';
info=struct('OFDM',struct('SampleRate',491520000));
factory=@sixgr.channel.ChannelFactory.createRuntimeChannelState;
initial=factory(cfg,'DL','UEIndex',1,'ServingCell',1);
initial.TargetUEIndex=1; initial.TargetServingCell=1;
initial=sixgr.channel.ChannelFactory.materializeRuntimeChannelState( ...
    initial,cfg,zeros(1,4),info,'NumTxAnt',4,'NumRxAnt',4);
assert(initial.NumTxAnt==4 && initial.NumRxAnt==4 && ~initial.UseFading && ...
    isempty(initial.Obj) && initial.CurrentSampleIndex==0);
reverse=factory(cfg,'UL','UEIndex',1,'ServingCell',1);
assert(string(reverse.StateKey)==string(initial.StateKey));
other=factory(cfg,'DL','UEIndex',2,'ServingCell',1);
assert(string(other.StateKey)~=string(initial.StateKey));
x=reshape(complex(sin(1:4004),cos(1:4004)),1001,4);
[whole,replay,finished,reference]=apply(initial,x,true);
assert(isequal(whole,x) && finished.CurrentSampleIndex==1001 && ...
    replay.ChannelModelApplied=="AWGN" && ~replay.ChannelFadingApplied);
assert(reference.Source=="executed_identity_AWGN_operator" && ...
    ~reference.ReceiverEstimatorInput && reference.AdditionalChannelExecutions==0);
assert(sixgr.channel.isAppliedChannelReference(reference));
badReference=reference; badReference.PathGains(1,1,1,2)=.01;
assert(~sixgr.channel.isAppliedChannelReference(badReference));
state=initial; chunks=cell(1,3); bounds=[0 1 337 1001];
for k=1:3
    [chunks{k},r,state]=apply(state,x(bounds(k)+1:bounds(k+1),:),false);
    assert(r.RuntimeChannelStartSample==bounds(k) && r.RuntimeChannelEndSample==bounds(k+1));
end
assert(isequal(vertcat(chunks{:}),whole) && state.TotalAppliedSamples==1001);
% Exact channel-reference coefficients reconstruct all actually used ports.
h=reshape(reference.PathGains(1,1,:,:),4,4);
assert(isequal(h,eye(4)) && isequal(x*h,x) && isequal(reference.PathFilters,1));
assert(reference.EndSampleExclusive-reference.StartSample==size(x,1));
bad=cfg; bad.channel.model='CDL';
reject(@()sixgr.channel.ChannelFactory.requiresRuntimeChannelState(bad), ...
    'ChannelFactory:InvalidSharedIdentityAWGN');
bad=cfg; bad.channel.pathlossEnabled=true;
reject(@()sixgr.channel.ChannelFactory.requiresRuntimeChannelState(bad), ...
    'ChannelFactory:InvalidSharedIdentityAWGN');
reject(@()sixgr.channel.ChannelFactory.materializeRuntimeChannelState( ...
    factory(cfg,'DL'),cfg,zeros(1,4),info,'NumTxAnt',4,'NumRxAnt',2), ...
    'ChannelFactory:IdentityAWGNPortMismatch');
reject(@()apply(initial,x(:,1:2),false),'ChannelFactory:ProjectedInputDimensionMismatch');
% The physical owner applies noise/RF once, and reverses the same link
% without manufacturing a fading object or consuming a made-up FIR tail.
cfg.run.noiseOperatingMode='standalone_awgn_snr_argument';
cfg.channel.snr_dB=30;
owner=sixgr.truth.SharedWaveformPhysicalRuntime(info.OFDM.SampleRate,0,1);
owner.addTransmitter('gnb',cfg,'DL',4,false);
owner.addTransmitter('ue',cfg,'UL',4,false);
owner.addReceiver('ue_rx',cfg,'DL',4,false);
owner.addReceiver('gnb_rx',cfg,'UL',4,false);
owner.addLink('identity','gnb','ue_rx',initial,cfg);
event=sixgr.phy.waveform.WaveformEventRuntime(info.OFDM.SampleRate,0,@owner.process,owner);
owner.attach(event,'double');
scoring=owner.registerLinkScoringPlane(event,'identity','ue_rx');
owner.requestLinkChannelReference(event,'identity','ue_rx',0,size(x,1));
event.enqueue('gnb','dl',sixgr.phy.waveform.WaveformChunk(x,0));
event.commitTransmissionsThrough('gnb',size(x,1));
event.commitTransmissionsThrough('ue',size(x,1));
for plane=["gnb:tx","ue_rx:pre_rf","ue_rx:post_rf",scoring]
    event.observe(plane,'identity_dl',0,size(x,1));
end
received=event.advanceUntilEvent(size(x,1));
dl=received.Completed(string({received.Completed.ReceiverID})==scoring);
assert(isequal(dl.Observation.readComplete(),x));
assert(received.Execution.ChannelReferences.Reference.Source=="executed_identity_AWGN_operator");
% Verify the generic observation exporter on actual executed sample planes.
% This test envelope is not a claim that the sinusoidal fixture is TRS.
envelope=struct('ExecutionStage',"trs_waveform_prepared_not_received", ...
    'SampleRateHz',info.OFDM.SampleRate,'TransmitStartSample',0,'NumSamples',size(x,1));
parent=fullfile(pwd,'results','diagnostics','shared_identity_awgn');
if ~isfolder(parent), mkdir(parent); end
folder=tempname(parent); mkdir(folder);
[row,~]=sixgr.truth.exportSharedChannelObservation(folder, ...
    table(1,'VariableNames',{'Slot'}),received.Completed,envelope,scoring);
verified=sixgr.channel.validateSharedChannelObservationArtifact(folder,row);
assert(string(verified.Manifest.Source)=="executed_identity_AWGN_operator" && ...
    row.ChannelObservationSource=="executed_identity_AWGN_operator");
owner.retargetTDDLink('identity','ue','gnb_rx',cfg);
states=owner.channelStates();
assert(states{1}.CurrentSampleIndex==size(x,1) && states{1}.Direction=="UL" && ...
    string(states{1}.StateKey)==string(initial.StateKey) && states{1}.Meta.RuntimeTDDReciprocityDirection=="UL");
stop=2*size(x,1);
ulScoring=owner.registerLinkScoringPlane(event,'identity','gnb_rx');
event.enqueue('ue','ul',sixgr.phy.waveform.WaveformChunk(x,size(x,1)));
event.commitTransmissionsThrough('gnb',stop); event.commitTransmissionsThrough('ue',stop);
event.observe(ulScoring,'identity_ul',size(x,1),stop);
received=event.advanceUntilEvent(stop);
assert(isequal(received.Completed.Observation.readComplete(),x));
% A YAML opt-in must not be silently ignored by the old research runner.
scenario=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_7ghz_400mhz_adaptive_dl5_ul2_30db.yaml');
wrongRunner=scenario.toStruct(); wrongRunner.channels.shared_identity_awgn_enabled=true;
reject(@()sixgr.lls6g.config.validateScenarioConfig(wrongRunner), ...
    'sixgr:lls6g:config:SharedIdentityAWGNRunnerRequired');
ok=true;
fprintf('SHARED_IDENTITY_AWGN_RUNTIME_PASS ports=4 Fs=491520000 samples=1001 artifact=%s control_integration=0 throughput_qualification=0\n',folder);
end

function [y,replay,state,reference]=apply(state,x,capture)
[y,replay,state,reference]=sixgr.channel.ChannelFactory.applyRuntimeChannelState( ...
    state,x,'OutputSampleAlignment','continuous_raw_samples', ...
    'InputSampleDomain','materialized_channel_ports','CaptureChannelReference',capture);
end

function reject(action,id)
try
    action();
catch ME
    assert(strcmp(ME.identifier,id),'Expected %s, got %s: %s',id,ME.identifier,ME.message);
    return;
end
error('test:ExpectedRejection','Expected %s.',id);
end
