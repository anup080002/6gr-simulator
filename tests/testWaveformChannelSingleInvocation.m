function ok=testWaveformChannelSingleInvocation()
% Native execution equivalence plus separately labelled fault-counter tests.
setup6GRSimToolkit('Verbose',false);
assert(exist('nrTDLChannel','class')==8 && exist('nrCDLChannel','class')==8, ...
    'sixgr:test:ChannelToolboxRequired','Native channel qualification requires 5G Toolbox.');
rs=RandStream('mt19937ar','Seed',81);
x=complex(randn(rs,128,1),randn(rs,128,1));
for name=["TDL","CDL"]
    cfg=localConfig(name);
    channel=sixgr.channel.ChannelFactory.create(cfg,'SampleRate',7.68e6, ...
        'NumTxAnt',1,'NumRxAnt',1,'Seed',41);
    actual=channel.Object; expected=clone(actual);
    [y,g,t,e]=sixgr.channel.applyWaveformChannelOnce(actual,x,true);
    [yr,gr,tr]=expected(x);
    assert(isequaln(y,yr) && isequaln(g,gr) && isequaln(t,tr) && ...
        e.ExecutionCompleted && e.ModelApplied==string(actual.DelayProfile), ...
        'sixgr:test:ChannelSingleCallEquivalence','Native samples/response/clock must be exact.');
    [y2,~,~,~]=sixgr.channel.applyWaveformChannelOnce(actual,x,false);
    yr2=expected(x);
    assert(isequaln(y2,yr2),'sixgr:test:ChannelContinuationEquivalence', ...
        'Capturing response must not add channel state advances.');
    bad=clone(actual); release(bad); bad.ChannelFiltering=false;
    localReject(@()sixgr.channel.applyWaveformChannelOnce(bad,x,true), ...
        'sixgr:channel:WaveformFilteringDisabled');
    assert(~isLocked(bad),'Coefficient-only channel must reject before consumption.');
    bad=clone(actual); release(bad); bad.ChannelResponseOutput='ofdm-response';
    localReject(@()sixgr.channel.applyWaveformChannelOnce(bad,x,true), ...
        'sixgr:channel:WaveformResponseModeMismatch');
    assert(~isLocked(bad),'Wrong response mode must reject before consumption.');
    % The factory still supports coefficient consumers; only waveform
    % materialization rejects this deliberately incompatible configuration.
    cfg.channel.channelFiltering=false;
    coefficient=sixgr.channel.ChannelFactory.create(cfg,'SampleRate',7.68e6, ...
        'NumTxAnt',1,'NumRxAnt',1,'Seed',41);
    assert(~coefficient.Object.ChannelFiltering && ~isLocked(coefficient.Object));
    state=sixgr.channel.ChannelFactory.createRuntimeChannelState(cfg,'DL','Seed',41);
    localReject(@()sixgr.channel.ChannelFactory.materializeRuntimeChannelState( ...
        state,cfg,x,struct('OFDM',struct('SampleRate',7.68e6)), ...
        'NumTxAnt',1,'NumRxAnt',1),'sixgr:channel:WaveformFilteringDisabled');
    localReject(@()sixgr.channel.measureStaticMIMOImpulseResponse( ...
        coefficient.Object,1,1,7.68e6),'sixgr:channel:WaveformFilteringDisabled');
    assert(~isLocked(coefficient.Object),'Static probe must reject before reset/consumption.');
    cfg.phy.duplex.mode='TDD'; cfg.channel.doppler_Hz=0;
    staticState=sixgr.channel.ChannelFactory.createRuntimeChannelState(cfg,'DL','Seed',41);
    localReject(@()sixgr.channel.ChannelFactory.materializeRuntimeChannelState( ...
        staticState,cfg,x,struct('OFDM',struct('SampleRate',7.68e6)), ...
        'NumTxAnt',1,'NumRxAnt',1),'sixgr:channel:WaveformFilteringDisabled');
    fprintf('WAVEFORM_CHANNEL_NATIVE_ONCE_PASS model=%s exact_continuation=1 mode_rejection=1\n',name);
end
h=reshape([1 0.3i -0.2],[],1,1);
fir=sixgr.channel.StaticReciprocalMIMOChannel(h,7.68e6);
[y,g,t,e]=sixgr.channel.applyWaveformChannelOnce(fir,x,true);
% Compare the same stateful filter operation. MATLAB's no-state overload
% uses a different arithmetic path (v45 measured 5.55e-17 difference).
% Retain exact equality and explicitly verify continuation as well.
[reference,zf]=filter(h,1,x,complex(zeros(numel(h)-1,1)));
assert(isequaln(y,reference) && isempty(g) && isempty(t) && ...
    isequaln(e.ImpulseResponse,h) && e.Kind=="static_reciprocal_fir", ...
    'sixgr:test:StaticFIRResponseContract','Exact FIR coefficients are not native path gains.');
[continued,~,~,~]=sixgr.channel.applyWaveformChannelOnce(fir,x,false);
[referenceNext,~]=filter(h,1,x,zf);
assert(isequaln(continued,referenceNext), ...
    'sixgr:test:StaticFIRContinuation','FIR state must advance exactly once per input.');
for capture=[false true]
    fault=sixgrtest.FailingWaveformChannel();
    localReject(@()sixgr.channel.applyWaveformChannelOnce(fault,x,capture), ...
        'sixgrtest:InjectedWaveformFailure');
    assert(fault.Calls==1,'sixgr:test:StatefulChannelRetried', ...
        'An error after state mutation must propagate with exactly one invocation.');
end
fprintf('WAVEFORM_CHANNEL_ONCE_PASS native_backends=2 static_fir=1 declared_fault_cases=2 no_native_fault_claim=1\n');
ok=true;
end

function cfg=localConfig(model)
cfg=struct(); cfg.run.seed=41;
cfg.channel.model=char(model);
if model=="TDL", cfg.channel.tdlProfile='TDL-C'; else, cfg.channel.cdlProfile='CDL-C'; end
cfg.channel.delaySpread_s=30e-9; cfg.channel.doppler_Hz=120;
cfg.channel.channelFiltering=true; cfg.channel.normalizePathGains=true;
cfg.phy.fc_Hz=4e9; cfg.phy.carrier.NSizeGrid=24;
cfg.phy.carrier.SubcarrierSpacing=30; cfg.phy.duplex.mode='FDD';
end

function localReject(f,id)
try
    f();
catch err
    assert(strcmp(err.identifier,id),'sixgr:test:WrongChannelFailure', ...
        'Expected %s, observed %s: %s',id,err.identifier,err.message);
    return;
end
error('sixgr:test:MissingChannelFailure','Expected rejection %s.',id);
end
