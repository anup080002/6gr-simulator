function ok=testSharedSignalDependencyEvidence()
% Actual original Composer/TXRF/CDL owner receipts, with declared component
% impulses. Not an SRS decode, RSRP accuracy, or full n40 scenario claim.
setup6GRSimToolkit('Verbose',false);
localRF();
scenario=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_n40_20mhz_64txru_4rx_cdlc100_impaired.yaml');
cfg=sixgr.lls6g.buildInternalConfig(scenario,tempdir);
runtime=sixgr.truth.CoupledTruthRuntime.initialize( ...
    cfg,tempdir,sixgr.truth.resolveMultiUserSpec(cfg),struct(),0);
runtime.CurrentSlot=1; runtime.CurrentServingIdx(:)=1;
[dl,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,runtime,1,'DL');
[ul,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,runtime,1,'UL');
window=sixgr.truth.resolveTRSObservationWindow(dl,1);
prepared=sixgr.link.prepareTRSTransmission(dl,12, ...
    'RuntimeSlot',window.AbsoluteSlotNumbers(1)+1);
tx=prepared.Tx; tx.Waveform=prepared.TransmitSamples;
truth=sixgr.link.initWaveformTruthChannelState(prepared.ReceiverConfig,tx,prepared.TxInfo);
channel=truth.RuntimeChannelState; fs=channel.SampleRate_Hz; epoch=cfg.rf.configurationEpoch;
assert(isa(channel.Obj,'nrCDLChannel')&&channel.NumTxAnt==64&&channel.NumRxAnt==4);
initial=sixgr.channel.ChannelSignalDependency.install(channel,epoch);
assert(initial.Available&&initial.InputHistoryStartSample==0&&initial.ZeroInputHistoryAtOrigin);
filters=getPathFilters(channel.Obj);
assert(initial.MemorySamples==size(filters,1)-1&& ...
    initial.FilterSHA256==sixgr.phy.waveform.WaveformHash.numeric(filters));
% Public native reset semantics on a disposable fresh clone: leave a
% nonzero sample in each direction, return, and inspect original zero-input
% output. This primitive probe does not bypass the production tail guard.
native=clone(channel.Obj);
sixgr.channel.applyWaveformChannelOnce(native,complex(ones(1,64)),false);
swapTransmitAndReceive(native);
sixgr.channel.applyWaveformChannelOnce(native,complex(ones(1,4)),false);
swapTransmitAndReceive(native);
zeroAfterReturn=sixgr.channel.applyWaveformChannelOnce( ...
    native,complex(zeros(initial.MemorySamples+1,64)),false);
assert(all(zeroAfterReturn==0,'all')&&~native.TransmitAndReceiveSwapped);
assert(channel.CurrentSampleIndex==0&&channel.TotalAppliedSamples==0&& ...
    ~channel.Obj.TransmitAndReceiveSwapped,'Never mutate the original channel in a reset probe.');
legacy=sixgr.channel.ChannelSignalDependency.bind(struct(),channel,channel,struct(),0,1);
assert(~legacy.Available&&legacy.Status=="unavailable_original_installation_receipt_missing");
bad=channel; bad.Meta=rmfield(bad.Meta,'NativeReciprocalFilterInitialization');
unavailable=sixgr.channel.ChannelSignalDependency.install(bad,epoch);
assert(~unavailable.Available);
bad=channel; bad.Meta.NativeReciprocalFilterInitialization.Applied=false;
unavailable=sixgr.channel.ChannelSignalDependency.install(bad,epoch);
assert(~unavailable.Available);
bad=channel; bad.TotalAppliedSamples=1;
unavailable=sixgr.channel.ChannelSignalDependency.install(bad,epoch);
assert(~unavailable.Available&&unavailable.Status=="unavailable_adopted_live_channel_history");
owner=sixgr.truth.SharedWaveformPhysicalRuntime(fs,0,epoch);
owner.addTransmitter('gnb',dl,'DL',64,false); owner.addTransmitter('ue',ul,'UL',4,false);
owner.addReceiver('ue_rx',dl,'DL',4,false); owner.addReceiver('gnb_rx',ul,'UL',64,false);
owner.addLink('serving','gnb','ue_rx',channel,dl);
events=sixgr.phy.waveform.WaveformEventRuntime(fs,0,@owner.process,owner);
owner.attach(events,'double');
% Complete the actual outgoing idle tail; no time jump or live reset.
guard=max(channel.ChannelPadSamples+1,initial.MemorySamples+1);
first=advance(guard); assert(first.Execution.Links.Replay.ChannelSignalDependency.Available);
before=owner.channelStates(); before=sixgr.channel.ChannelSignalDependency.beforeRetarget(before{1});
owner.retargetTDDLink('serving','ue','gnb_rx',ul);
states=owner.channelStates(); ulState=states{1};
assert(ulState.Obj.TransmitAndReceiveSwapped&&ulState.NumTxAnt==4&&ulState.NumRxAnt==64);
% A label-only swap cannot issue a reset receipt.
forged=before; forged.NativeSwapped=ulState.Obj.TransmitAndReceiveSwapped;
reject(@()sixgr.channel.ChannelSignalDependency.afterRetarget(forged,ulState,epoch,guard), ...
    'sixgr:channel:SignalDependencyRetarget');
origin=owner.NextSampleIndex;
old=sixgr.phy.waveform.WaveformChunk(complex(ones(8,4)),origin);
events.enqueue('ue','earlier_access_component',old);
% This finite consumed separation excludes earlier access, rather than
% requiring that this UE transmitted only SRS since the run began.
targetStart=origin+8+initial.MemorySamples+64;
target=sixgr.phy.waveform.WaveformChunk(complex(ones(64,4),ones(64,4)),targetStart);
events.enqueue('ue','target_SRS_component',target);
last=advance(targetStart+64);
d=last.Execution.Links.Replay.ChannelSignalDependency;
assert(d.Available&&d.NativeSwapped&&d.InputHistoryStartSample==origin&& ...
    d.HistoryInitializationSource=="original_native_direction_swap_filter_reset"&& ...
    d.InitializationReceipt.Before.NativeSwapped==false&& ...
    d.InitializationReceipt.After.NativeSwapped==true&& ...
    d.InitializationReceipt.OriginalConsumedZeroTailSamples==guard);
request=struct('TransmitterID',"ue",'ReceiverID',"gnb_rx",'LinkID',"serving", ...
    'ComponentID',"target_SRS_component",'ComponentSHA256',target.SHA256, ...
    'SampleRateHz',fs,'ConfigurationEpoch',epoch,'FFTIntervals',[targetStart+16 targetStart+48]);
proof=sixgr.truth.proveSRSComponentIsolation(events.ExecutionTrace,request);
assert(proof.Available&&~proof.AllHistorySRSOnlyRequired);
txReceipt=last.Execution.TX(string({last.Execution.TX.ID})=="ue").Replay.TXSignalDependency;
assert(txReceipt.Available&&txReceipt.PAModel=="rapp"&&txReceipt.DACConvention=="signed_midtread");
% A second real direction change resets the selected original DL FIR;
% retained RF memory is never reset and still has the original origin.
advance(owner.NextSampleIndex+guard+64);
owner.retargetTDDLink('serving','gnb','ue_rx',dl);
back=advance(owner.NextSampleIndex+17);
backDependency=back.Execution.Links.Replay.ChannelSignalDependency;
assert(backDependency.Available&&~backDependency.NativeSwapped&& ...
    backDependency.InputHistoryStartSample==back.Execution.StartSample&& ...
    backDependency.InitializationReceipt.Before.NativeSwapped&& ...
    ~backDependency.InitializationReceipt.After.NativeSwapped);
assert(~owner.Faulted);
fprintf('SHARED_SIGNAL_DEPENDENCY_PASS native64x4_DL_UL_DL=1 finite_prior_access=1 decoded_SRS=0\n');
ok=true;

    function event=advance(stop)
        events.commitTransmissionsThrough('gnb',stop);
        events.commitTransmissionsThrough('ue',stop);
        event=events.advanceUntilEvent(stop);
        assert(owner.NextSampleIndex==stop&&events.NextSampleIndex==stop);
    end
end

function localRF()
fs=7.68e6; epoch=9; origin=31;
c=struct(); c.rf.specification.profile_id='rf_impaired_research';
c.rf.configurationEpoch=epoch; c.rf.pa.enable=true;
c.rf.frontend.pa=struct('profile_id','declared_dependency_test','version','1', ...
    'input_backoff_db',0,'model','memory_polynomial','reference_domain','waveform_samples', ...
    'coefficients',[1 .25 -.125],'orders',1,'memory_depth',3);
c.rf.tx.timingOffsetSamples=4;
owner=sixgr.rf.runtime.RFImpairmentStream(c,'tx','UL',fs,2,origin,epoch,false);
x=complex(zeros(16,2)); x(1,:)=[1 2];
chunk=sixgr.phy.waveform.WaveformChunk(x,origin); result=owner.apply(chunk,epoch);
expected=filter([zeros(1,4) 1 .25 -.125],1,x);
assert(isequal(result.Waveform,expected));
d=result.Replay.TXSignalDependency;
assert(d.Available&&d.MemorySamples==2&&d.DelaySamples==4&& ...
    d.HistoryOriginSample==origin&&d.ZeroPreserving&&d.ZeroInputHistoryAtOrigin&& ...
    d.OriginalInputChunkSHA256==chunk.SHA256&& ...
    d.RFInputWaveformSHA256==string(result.Replay.RFInputWaveformSHA256)&& ...
    d.RFOutputWaveformSHA256==string(result.Replay.RFOutputWaveformSHA256));
split=sixgr.rf.runtime.RFImpairmentStream(c,'tx','UL',fs,2,origin,epoch,false);
head=split.apply(sixgr.phy.waveform.WaveformChunk(x(1,:),origin),epoch);
tail=split.apply(sixgr.phy.waveform.WaveformChunk(x(2:end,:),origin+1),epoch);
assert(isequal([head.Waveform;tail.Waveform],result.Waveform)&& ...
    tail.Replay.TXSignalDependency.HistoryOriginSample==origin&& ...
    tail.Replay.TXSignalDependency.MemorySamples==2&& ...
    tail.Replay.TXSignalDependency.DelaySamples==4&&any(tail.Waveform~=0,'all'), ...
    'The receipt must retain the actual PA/delay dependency across chunk boundaries.');
% Midrise zero input is nonzero; retain actual samples but never qualify
% those samples as isolated emitted signal power.
c=struct(); c.run.seed=101;
c.rf.frontend.dac=struct('enabled',true,'profile_id','dependency_dac', ...
    'version','1','bits',12,'full_scale',1,'convention','signed_midrise', ...
    'dither_enabled',false,'dither_rms',0,'aperture_jitter_seconds',0);
owner=sixgr.rf.runtime.RFImpairmentStream(c,'tx','UL',fs,2,origin,epoch,false);
result=owner.apply(sixgr.phy.waveform.WaveformChunk(complex(zeros(8,2)),origin),epoch);
assert(any(result.Waveform~=0,'all')&&~result.Replay.TXSignalDependency.Available&& ...
    ~result.Replay.TXSignalDependency.ZeroPreserving&&result.Replay.TXSignalDependency.AdditiveTXOutput);
end

function reject(fn,id)
try, fn(); catch cause
    assert(string(cause.identifier)==string(id),'Unexpected error: %s',cause.identifier); return;
end
error('test:SignalDependencyMissingGuard','Expected %s.',id);
end
