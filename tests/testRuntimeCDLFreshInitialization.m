function ok=testRuntimeCDLFreshInitialization()
% Actual native channel/factory component; no RF or decoded-PHY claim.
setup6GRSimToolkit('Verbose',false);
parent=fullfile(pwd,'logs','runtime_cdl_fresh_initialization');
if ~isfolder(parent), mkdir(parent); end
folder=tempname(parent); mkdir(folder);
fprintf('RUNTIME_CDL_FRESH_INITIALIZATION_AUDIT %s\n',folder);
originalRNG=rng; results={}; failures={};
for precision=["double","single"]
    for direction=["DL","UL"]
        name=direction+"_"+precision;
        try
            results{end+1}=factoryCase(direction,precision,folder); %#ok<AGROW>
        catch cause
            failures{end+1}=failure(name,cause); %#ok<AGROW>
        end
    end
end
try
    results{end+1}=helperGuards(folder);
catch cause
    failures{end+1}=failure("helper_guards",cause);
end
try
    results{end+1}=finiteUnchanged(folder);
catch cause
    failures{end+1}=failure("finite_unchanged_unqualified",cause);
end
finalRNG=rng;
save(fullfile(folder,'summary.mat'),'results','failures','originalRNG','finalRNG','-v7.3');
assert(isequal(originalRNG,finalRNG),'test:RuntimeCDLGlobalRNGChanged');
assert(isempty(failures),'test:RuntimeCDLFreshInitializationFailed', ...
    '%d component case(s) failed; original outputs/stacks retained under %s.',numel(failures),folder);
fprintf('PASS testRuntimeCDLFreshInitialization: four exact factory/fork/checkpoint cases; fresh-only guards; finite behavior unchanged/unqualified.\n');
ok=true;
end

function result=factoryCase(direction,precision,folder)
[cfg,fs,seed]=configuration();
name=direction+"_"+precision; caseFolder=fullfile(folder,char(name)); mkdir(caseFolder);
numTx=4; numRx=2;
if direction=="UL", numTx=2; numRx=4; end
prototype=complex(zeros(37,numTx,char(precision)));
txInfo=struct('OFDM',struct('SampleRate',fs));
key="dir="+direction+";tx=fixture_a;rx=fixture_b;carrier=native_reciprocal_component";
state=sixgr.channel.ChannelFactory.createRuntimeChannelState(cfg,direction, ...
    'LinkKey',key,'Seed',seed,'AbsoluteSampleIndex',73);
state=sixgr.channel.ChannelFactory.materializeRuntimeChannelState(state,cfg,prototype,txInfo, ...
    'NumTxAnt',numTx,'NumRxAnt',numRx);
evidence=state.Meta.NativeReciprocalFilterInitialization;
assert(evidence.Applied && evidence.PhysicalSamplesAdvanced==0 && ...
    evidence.DiscardedSetupSamples==2*state.WarmupSamples && ...
    evidence.SetupSampleClass==precision && evidence.ResetCount==1 && ...
    ~evidence.FiniteDensityQualified && ~evidence.HistoricalCheckpointRepaired);
assert(state.ResetCount==1 && state.CurrentSampleIndex==73 && ...
    state.PendingIdleSamples==0 && state.TotalIdleAdvancedSamples==73 && ...
    state.TotalObjectInputSamples==state.WarmupSamples+73);

% Independent untouched native construction: same installed config, ordinary
% warmup and elapsed idle only. No repaired-helper execution on this oracle.
baseline=ordinaryNative(cfg,fs,seed,direction);
warmup=zeros(state.WarmupSamples,numTx,'like',prototype);
reset(baseline);
sixgr.channel.applyWaveformChannelOnce(baseline,warmup,false);
sixgr.channel.applyWaveformChannelOnce(baseline,zeros(73,numTx,'like',prototype),false);
observations={}; states={state};
compare('prefix',signal(37,numTx,precision,1));
compare('prefix_tail',zeros(128,numTx,'like',prototype));
state=states{1};
forked=sixgr.channel.ChannelFactory.forkRuntimeChannelState(state);
checkpoint=state;
save(fullfile(caseFolder,'original_checkpoint.mat'),'checkpoint','-v7.3');
loaded=load(fullfile(caseFolder,'original_checkpoint.mat'),'checkpoint');
states={state,forked,loaded.checkpoint};
assert(isequal(states{1}.Meta.NativeReciprocalFilterInitialization, ...
    states{3}.Meta.NativeReciprocalFilterInitialization));
compare('same_direction',signal(19,numTx,precision,2));
compare('outgoing_tail',zeros(128,numTx,'like',prototype));
reverse="UL"; if direction=="UL", reverse="DL"; end
retarget(reverse,numRx,numTx);
compare('reverse_direction',signal(41,numRx,precision,3));
compare('reverse_tail',zeros(128,numRx,'like',prototype));
retarget(direction,numTx,numRx);
compare('returned_direction',signal(23,numTx,precision,4));
result=struct('Name',name,'Observations',{observations},'FinalStates',{states}, ...
    'Initialization',evidence,'ExactSamples',true,'ExactGains',true, ...
    'ExactTimes',true,'DecodedPHY',false,'RFExecuted',false);
save(fullfile(caseFolder,'result.mat'),'result','-v7.3');
fprintf('RUNTIME_CDL_FRESH_FACTORY_CASE_PASS %s\n',name);

    function compare(phase,x)
        before=states; % The saved checkpoint below serializes before calls.
        save(fullfile(caseFolder,[phase '_before.mat']),'before','x','-v7.3');
        % Production's continuous physical-input path deliberately isolates
        % sample one before its remaining bounded chunk. Native filtering
        % and absolute-time addition differ at rounding level for another
        % partition; compare identical calls, never a looser tolerance.
        assert(size(x,1)>1 && size(x,1)-1<=states{1}.ElementExpansionChunkSamples, ...
            'test:RuntimeCDLReferencePartitionOutsideFixture');
        nativeCallLengths=[1,size(x,1)-1];
        [firstY,firstG,firstT]=sixgr.channel.applyWaveformChannelOnce(baseline,x(1,:),true);
        [restY,restG,restT]=sixgr.channel.applyWaveformChannelOnce(baseline,x(2:end,:),true);
        expected=cat(1,firstY,restY); g=cat(1,firstG,restG); t=cat(1,firstT,restT);
        actual=cell(size(states));
        for n=1:numel(states)
            [y,replay,states{n},reference]=sixgr.channel.ChannelFactory.applyRuntimeChannelState( ...
                states{n},x,'CaptureChannelReference',true, ...
                'InputSampleDomain','materialized_channel_ports', ...
                'OutputSampleAlignment','continuous_raw_samples');
            actual{n}=struct('Samples',y,'Replay',replay,'Reference',reference);
        end
        observation=struct('Phase',string(phase),'Input',x,'Expected',expected, ...
            'ExpectedPathGains',g,'ExpectedSampleTimes',t,'Actual',{actual}, ...
            'NativeCallLengths',nativeCallLengths);
        save(fullfile(caseFolder,[phase '_original_operands.mat']),'observation','-v7.3');
        observations{end+1}=observation;
        for n=1:numel(states)
            assert(isequal(actual{n}.Samples,expected) && ...
                isequal(actual{n}.Reference.PathGains,g) && ...
                isequal(actual{n}.Reference.SampleTimes_s,t), ...
                'test:RuntimeCDLExactContinuationMismatch','%s/%s owner %d differs.',name,phase,n);
            assert(states{n}.ResetCount==1 && ...
                states{n}.TotalObjectInputSamples==states{n}.WarmupSamples+states{n}.CurrentSampleIndex && ...
                actual{n}.Replay.RuntimeChannelObjectClockExact && ...
                actual{n}.Reference.ObjectTimeOffsetSamples==states{n}.WarmupSamples);
        end
    end
    function retarget(next,nTx,nRx)
        swapTransmitAndReceive(baseline);
        for n=1:numel(states)
            oldClock=states{n}.CurrentSampleIndex;
            oldEvidence=states{n}.Meta.NativeReciprocalFilterInitialization;
            states{n}.Direction=char(next);
            states{n}=sixgr.channel.ChannelFactory.materializeRuntimeChannelState( ...
                states{n},cfg,zeros(1,nTx,'like',prototype),txInfo,'NumTxAnt',nTx,'NumRxAnt',nRx);
            assert(states{n}.CurrentSampleIndex==oldClock && states{n}.ResetCount==1 && ...
                isequal(states{n}.Meta.NativeReciprocalFilterInitialization,oldEvidence), ...
                'test:RuntimeCDLRetargetReinitialized');
        end
    end
end

function result=helperGuards(folder)
[cfg,fs,seed]=configuration(); warmup=complex(zeros(256,4)); count=0;
c=ordinaryNative(cfg,fs,seed,"DL"); c.InitialTime=0.003125;
baseline=ordinaryNative(cfg,fs,seed,"DL"); baseline.InitialTime=c.InitialTime;
e=sixgr.channel.initializeFreshCDLReciprocalFilters(c,warmup);
sixgr.channel.applyWaveformChannelOnce(c,warmup,false);
reset(baseline); sixgr.channel.applyWaveformChannelOnce(baseline,warmup,false);
reject(@()sixgr.channel.initializeFreshCDLReciprocalFilters(c,warmup), ...
    'sixgr:channel:FreshCDLInitializationRequiresUnlocked'); count=count+1;
x=signal(17,4,"double",6);
[a,ag,at]=sixgr.channel.applyWaveformChannelOnce(c,x,true);
[b,bg,bt]=sixgr.channel.applyWaveformChannelOnce(baseline,x,true);
save(fullfile(folder,'helper_nonzero_origin_originals.mat'),'x','a','ag','at','b','bg','bt','e','-v7.3');
assert(isequal(a,b)&&isequal(ag,bg)&&isequal(at,bt)&&e.InitialTime_s==0.003125, ...
    'test:FreshCDLRejectedLiveCallChangedState');
for mode=["finite","global_rng","coefficient_only","response_mode","nonzero","columns"]
    q=ordinaryNative(cfg,fs,seed,"DL"); z=warmup;
    % R2024a exposes only the documented path-gain signature; no alternate
    % response-mode property exists to configure or reject on that release.
    if mode=="response_mode" && ~isprop(q,'ChannelResponseOutput'),continue;end
    switch mode
        case "finite"
            q.SampleDensity=64; id='sixgr:channel:FreshCDLInitializationFiniteDensityUnsupported';
        case "global_rng"
            q.RandomStream='Global stream'; id='sixgr:channel:FreshCDLInitializationRequiresSeededStream';
        case "coefficient_only"
            q.ChannelFiltering=false; id='sixgr:channel:WaveformFilteringDisabled';
        case "response_mode"
            q.ChannelResponseOutput='ofdm-response'; id='sixgr:channel:WaveformResponseModeMismatch';
        case "nonzero"
            z(1)=1; id='sixgr:channel:FreshCDLInitializationRequiresZeros';
        case "columns"
            z=z(:,1:3); id='sixgr:channel:FreshCDLInitializationDimensions';
    end
    before=rng;
    reject(@()sixgr.channel.initializeFreshCDLReciprocalFilters(q,z),id);
    assert(~isLocked(q)&&isequal(rng,before),'test:FreshCDLRejectedSetupConsumedState');
    count=count+1;
end
q=nrTDLChannel;
reject(@()sixgr.channel.initializeFreshCDLReciprocalFilters(q,warmup), ...
    'sixgr:channel:FreshCDLInitializationBackend'); count=count+1;
result=struct('Name',"helper_guards",'NegativeCases',count,'NonzeroNativeOriginExact',true);
end

function result=finiteUnchanged(folder)
[cfg,fs,seed]=configuration(); cfg.channel.perSampleFadingEnabled=false;
x=signal(37,4,"double",7); txInfo=struct('OFDM',struct('SampleRate',fs));
s=sixgr.channel.ChannelFactory.createRuntimeChannelState(cfg,"DL",'Seed',seed);
s=sixgr.channel.ChannelFactory.materializeRuntimeChannelState(s,cfg,x,txInfo,'NumTxAnt',4,'NumRxAnt',2);
baseline=ordinaryNative(cfg,fs,seed,"DL");
reset(baseline); sixgr.channel.applyWaveformChannelOnce(baseline,zeros(s.WarmupSamples,4,'like',x),false);
[a,ag,at]=sixgr.channel.applyWaveformChannelOnce(s.Obj,x,true);
[b,bg,bt]=sixgr.channel.applyWaveformChannelOnce(baseline,x,true);
save(fullfile(folder,'finite_originals.mat'),'a','ag','at','b','bg','bt','-v7.3');
assert(isequal(a,b)&&isequal(ag,bg)&&isequal(at,bt));
assert(~s.Meta.NativeReciprocalFilterInitialization.Applied && ...
    ~s.Meta.NativeReciprocalFilterInitialization.FiniteDensityQualified && ...
    isfinite(s.Obj.SampleDensity));
result=struct('Name',"finite_unchanged_unqualified",'SameDirectionSamplesUnchanged',true, ...
    'FiniteReciprocalForkQualified',false);
end

function object=ordinaryNative(cfg,fs,seed,direction)
native=sixgr.channel.ChannelFactory.create(sixgr.channel.bindRuntimeDoppler(cfg), ...
    'Model','CDL','SampleRate',fs,'NumTxAnt',4,'NumRxAnt',2,'Seed',seed,'LinkDirection','DL');
object=native.Object;
if direction=="UL", swapTransmitAndReceive(object); end
end
function [cfg,fs,seed]=configuration()
cfg=sixgr.config.defaultConfig(); fs=7.68e6; seed=65537;
cfg.run.seed=seed; cfg.channel.seed=seed;
cfg.channel.model='CDL-C'; cfg.channel.cdlProfile='CDL-C'; cfg.channel.delayProfile='CDL-C';
cfg.channel.fading.model='CDL'; cfg.channel.fading.profile='CDL-C';
cfg.channel.awgnOnly=false; cfg.channel.delaySpread_s=100e-9; cfg.channel.doppler_Hz=37;
cfg.channel.channelFiltering=true; cfg.channel.perSampleFadingEnabled=true;
cfg.channel.normalizePathGains=false; cfg.channel.normalizeChannelOutputs=false;
cfg.phy.fc_Hz=2.35e9; cfg.phy.duplex.mode='TDD';
end
function x=signal(n,ports,precision,key)
x=cast(.01*exp(1i*((0:n-1).'*(1:ports)/19+key*(1:ports)/7)),char(precision));
end
function reject(fcn,id)
try
    fcn();
catch cause
    assert(strcmp(cause.identifier,id),'test:FreshCDLWrongRejection', ...
        'Expected %s; observed %s: %s',id,cause.identifier,cause.message);
    return;
end
error('test:FreshCDLMissingRejection','Expected %s.',id);
end
function out=failure(name,cause)
out=struct('Case',name,'Identifier',string(cause.identifier), ...
    'Report',string(getReport(cause,'extended','hyperlinks','off')));
fprintf('RUNTIME_CDL_FRESH_INITIALIZATION_CASE_FAIL %s %s\n',name,cause.identifier);
end
