function ok=testSharedWaveformPhysicalRuntime()
% Real TDD-profile CDL/OFDM samples; physical-owner tests, not a main run.
% Whole/split owners are independent test oracles, never runtime rollback.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios','lls_causal_access_to_data_wiring_tdd.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
runtime=sixgr.truth.CoupledTruthRuntime.initialize(cfg,tempname,multi,struct(),1);
runtime.CurrentSlot=1; runtime.CurrentServingIdx(:)=1;
[dl,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,runtime,1,'DL');
[ul,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,runtime,1,'UL');
p=sixgr.link.prepareTRSTransmission(dl,12,'RuntimeSlot',3);
tx=p.Tx; tx.Waveform=p.TransmitSamples;
truth=sixgr.link.initWaveformTruthChannelState(p.ReceiverConfig,tx,p.TxInfo);
state=truth.RuntimeChannelState;
fs=state.SampleRate_Hz; nt=state.NumTxAnt; nr=state.NumRxAnt;
[x,~]=sixgr.channel.projectRuntimeTransmitSamples(state,p.TransmitSamples);
assert(size(x,2)==nt && any(x(:)~=0));
% Use a real generated TRS waveform fragment followed by actual idle TX
% input. This fixture is not advertised as a decoded complete TRS window.
x=x(1:min(2053,size(x,1)),:);
if ~any(x(:)~=0)
    full=p.TransmitSamples;
    first=find(any(full~=0,2),1);
    [x,~]=sixgr.channel.projectRuntimeTransmitSamples(state,full(first:first+2052,:));
end
assert(any(x(:)~=0));
epoch=3;
% Authored profile coefficients with explicit test-only CFO/ADC activation.
% The physical owner retains these stages; it never reapplies RX to an
% independent noise-only waveform to manufacture diagnostic measurements.
dl.rf.rx.agc.enable=true; dl.rf.rx.agc.targetRms=.2;
dl.rf.rx.agc.minGain_dB=-80; dl.rf.rx.agc.maxGain_dB=80;
dl.rf.rx.cfo_Hz=321; dl.rf.adc.enable=true;
dl.rf.adcBits=12; dl.rf.adc.fullScale=1;
whole=localOwner(dl,ul,state,fs,nt,nr,epoch);
split=localOwner(dl,ul,sixgr.channel.ChannelFactory.forkRuntimeChannelState(state),fs,nt,nr,epoch);
wholeEvent=localEvent(whole,fs,nt,nr);
splitEvent=localEvent(split,fs,nt,nr);
before=rng;
guard=double(state.ChannelPadSamples)+9;
% The authored DDD-S-U fixture has its first full UL slot at 4 ms. Consume
% the actual idle interval before that boundary, not an RX padding tail.
stop=round(4e-3*fs);
assert(stop-size(x,1)>=guard);
for event={wholeEvent,splitEvent}
    e=event{1};
    % This proves node composition happens BEFORE RF/PA. These are known
    % generated contributions, not missing transmissions filled in by RX.
    e.enqueue('gnb','trs_part_a',sixgr.phy.waveform.WaveformChunk(.25*x,0));
    e.enqueue('gnb','trs_part_b',sixgr.phy.waveform.WaveformChunk(.75*x,0));
    e.commitTransmissionsThrough('gnb',stop);
    e.commitTransmissionsThrough('ue',stop); % declared idle transmitter
    for plane=["gnb:tx","ue_rx:pre_rf","ue_rx:post_rf","gnb_rx:pre_rf"]
        e.observe(plane,plane,0,stop);
    end
end
result=wholeEvent.advanceUntilEvent(stop);
actual=struct([]); next=0;
for last=unique([1 17 71 777 stop])
    event=splitEvent.advanceUntilEvent(last);
    assert(event.Execution.StartSample==next && event.Execution.EndSampleExclusive==last);
    assert(numel(event.Execution.Links)==1 && numel(event.Execution.RX)==2);
    assert(event.Execution.Links.Replay.RuntimeChannelStartSample==next && ...
        event.Execution.Links.Replay.RuntimeChannelEndSample==last && ...
        ~event.Execution.Links.Replay.RuntimeChannelAlignmentLookaheadExecutedOnFork);
    assert(isnan(event.Execution.RX(1).Replay.SampleNoiseVariance), ...
        'Causal AGC/CFO/ADC does not authorize a fabricated scalar post-RF variance.');
    actual=[actual event.Completed]; %#ok<AGROW>
    next=last;
end
assert(numel(actual)==numel(result.Completed));
for k=1:numel(actual)
    index=find(string({result.Completed.ID})==actual(k).ID);
    a=actual(k).Observation.readComplete(); b=result.Completed(index).Observation.readComplete();
    if actual(k).ReceiverID=="ue_rx:post_rf" || actual(k).ReceiverID=="gnb:tx"
        assert(isequal(a,b),'Retained RF samples depend on chunk partition.');
    else
        assert(norm(a-b,'fro')<1e-12*max(norm(b,'fro'),realmin));
    end
end
assert(isequal(rng,before),'Shared physical execution consumed the global RNG.');
states=split.channelStates(); assert(states{1}.CurrentSampleIndex==stop);
assert(string(states{1}.StateKey)==string(state.StateKey));
% Two real receiver identities must not share a receiver-noise seed. Their
% noise is generated once per receiver, not once for each incoming link.
assert(result.Execution.RX(1).Replay.NoiseStreamSeed~=result.Execution.RX(2).Replay.NoiseStreamSeed);
localError(@()split.addTransmitter('late',dl,'DL',nt,false),'WAVEFORM:PhysicalLayoutFrozen');
localError(@()split.process(struct(),stop+1,stop+2,[]),'WAVEFORM:PhysicalIntervalMismatch');
assert(~split.Faulted && split.NextSampleIndex==stop);
% A same-clock direction switch occurs only AFTER the outgoing tail has
% actually traversed the channel, with the same reciprocal fading object.
split.retargetTDDLink('serving','ue','gnb_rx',ul);
states=split.channelStates();
assert(states{1}.CurrentSampleIndex==stop && states{1}.Obj.TransmitAndReceiveSwapped);
assert(states{1}.NumTxAnt==nr && states{1}.NumRxAnt==nt);
% Actual uplink samples on the same clock, not a second channel instance.
carrier=sixgr.phy.grid.makeCarrier(ul);
carrier.NSlot=4;
grid=nrResourceGrid(carrier,nr); grid(1:12,1,:)=1;
u=nrOFDMModulate(carrier,grid,'Windowing',0);
u=u(1:512,:);
splitEvent.enqueue('ue','ul_ofdm',sixgr.phy.waveform.WaveformChunk(u,stop));
splitEvent.commitTransmissionsThrough('gnb',stop+size(u,1));
splitEvent.commitTransmissionsThrough('ue',stop+size(u,1));
event=splitEvent.advanceUntilEvent(stop+size(u,1));
assert(event.Execution.Links.Replay.RuntimeChannelStartSample==stop);
assert(event.Execution.Links.Replay.RuntimeChannelEndSample==stop+size(u,1));
localError(@()split.retargetTDDLink('serving','gnb','ue_rx',dl),'WAVEFORM:TDDChannelTailNotConsumed');
assert(~split.Faulted);
% Duplicate shared-state owners are rejected before consuming any sample.
% The original 'whole' owner consumed state.Obj. Use a newly materialized
% independent test channel for the duplicate-registration negative case.
truth2=sixgr.link.initWaveformTruthChannelState(p.ReceiverConfig,tx,p.TxInfo);
fresh=localOwner(dl,ul,truth2.RuntimeChannelState,fs,nt,nr,epoch);
localError(@()fresh.addLink('duplicate','gnb','ue_rx',truth2.RuntimeChannelState,dl), ...
    'WAVEFORM:DuplicatePhysicalChannelOwner');
ok=true;
disp('SHARED_PHYSICAL_RUNTIME_PASS: actual CDL/RF/noise clock, split invariance, DL/UL tail-safe reversal; no main-run claim.');
end

function owner=localOwner(dl,ul,state,fs,nt,nr,epoch)
owner=sixgr.truth.SharedWaveformPhysicalRuntime(fs,0,epoch);
owner.addTransmitter('gnb',dl,'DL',nt,false);
owner.addTransmitter('ue',ul,'UL',nr,false);
owner.addReceiver('ue_rx',dl,'DL',nr,false);
owner.addReceiver('gnb_rx',ul,'UL',nt,false);
owner.addLink('serving','gnb','ue_rx',state,dl);
end

function event=localEvent(owner,fs,nt,nr) %#ok<INUSD>
event=sixgr.phy.waveform.WaveformEventRuntime(fs,0,@owner.process,owner);
owner.attach(event,'double');
end

function localError(action,id)
try, action(); catch cause
    assert(string(cause.identifier)==id,'Expected %s; got %s: %s',id,cause.identifier,cause.message); return;
end
error('test:ExpectedError','Expected %s.',id);
end
