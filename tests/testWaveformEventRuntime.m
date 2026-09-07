function ok=testWaveformEventRuntime()
% Coordinator mechanics with an explicitly declared deterministic FIR
% fixture, NOT a fading/RF/NR receiver qualification result.
setup6GRSimToolkit('Verbose',false);
chunk=@(x,first)sixgr.phy.waveform.WaveformChunk(x,first);
state=struct('Calls',0,'NextSample',0,'FilterState',complex(zeros(1,2)), ...
    'Inputs',complex(zeros(0,2)),'Outputs',complex(zeros(0,2)));
r=sixgr.phy.waveform.WaveformEventRuntime(1000,0,@localProcessor,state);
r.addTransmitter('gnb',2,'double');
r.addTransmitter('ue',2,'double');
r.addReceiver('rx',2);
r.addReceiver('tx_capture',2);
a=complex(reshape(1:24,12,2),-reshape(1:24,12,2));
b=complex(3*ones(5,2),ones(5,2));
r.enqueue('gnb','a',chunk(a,0));
r.enqueue('gnb','b',chunk(b,3));
r.observe('rx','early',1,4);
r.observe('rx','long',0,12);
r.observe('tx_capture','early',0,4); % Same ID on a different plane.
r.decisionBoundary('feedback',4);
r.decisionBoundary('schedule',7);
initialRNG=rng;
event=r.advanceUntilEvent(0);
assert(~event.PhysicalExecutionPerformed && r.ProcessorState.Calls==0);
localError(@()r.advanceUntilEvent(12),'WAVEFORM:UncommittedTransmissionInterval');
assert(~r.Faulted && r.NextSampleIndex==0 && r.ProcessorState.Calls==0);
assert(isequal(rng,initialRNG));
r.commitTransmissionsThrough('gnb',4);
r.commitTransmissionsThrough('ue',4); % Explicit idle UE, no invented signal.
localError(@()r.enqueue('ue','late',chunk(b,3)),'WAVEFORM:CommittedTransmission');
event=r.advanceUntilEvent(12);
assert(event.EndSampleExclusive==4 && event.Decisions=="feedback");
assert(numel(event.Completed)==2 && r.ProcessorState.Calls==1);
expected=a; expected(4:8,:)=expected(4:8,:)+b;
assert(isequal(r.ProcessorState.Inputs,expected(1:4,:)));
assert(isequal(event.Completed(1).Observation.readComplete(),r.ProcessorState.Outputs(2:4,:)));
assert(isequal(event.Completed(2).Observation.readComplete(),expected(1:4,:)));
assert(numel(event.Completed(1).Segments)==1);
assert(event.Completed(1).Segments{1}.StartSample==0 && ...
    event.Completed(1).Segments{1}.EndSampleExclusive==4);

% A receiver result can now cause an actual future UE transmission before
% any samples of that transmission have been consumed.
u=complex(-ones(3,2),2*ones(3,2));
r.enqueue('ue','causal_response',chunk(u,4));
expected(5:7,:)=expected(5:7,:)+u;
r.commitTransmissionsThrough('gnb',12);
r.commitTransmissionsThrough('ue',12);
event=r.advanceUntilEvent(12);
assert(event.EndSampleExclusive==7 && event.Decisions=="schedule" && isempty(event.Completed));
event=r.advanceUntilEvent(9);
assert(event.EndSampleExclusive==9 && isempty(event.Completed));
event=r.advanceUntilEvent(12);
assert(event.EndSampleExclusive==12 && numel(event.Completed)==1);
assert(event.Completed.ID=="long" && numel(event.Completed.Segments)==4);
assert(isequal(r.ProcessorState.Inputs,expected));
assert(isequal(r.ProcessorState.Outputs,filter([1 .25],1,expected)));
assert(isequal(event.Completed.Observation.readComplete(),r.ProcessorState.Outputs));
assert(r.ProcessorState.Calls==4 && numel(r.ExecutionTrace)==4);
assert(isequal(rng,initialRNG),'Pure orchestration must not use the global random stream.');
localError(@()r.observe('rx','past',11,14),'WAVEFORM:LateObservation');
localError(@()r.decisionBoundary('feedback',14),'WAVEFORM:DuplicateDecisionBoundary');
assert(~r.Faulted && r.NextSampleIndex==12);

% Invalid physical execution can have mutated retained handles: never retry
% it, or fill its missing receiver plane with zeros.
for mode=["throw","missing_plane","proxy","source_proxy","fallback","pathloss_fallback","clock","short","nan"]
    f=sixgr.phy.waveform.WaveformEventRuntime(1000,0, ...
        @(inputs,first,stop,s)localBadProcessor(inputs,first,stop,s,mode),state);
    f.addTransmitter('gnb',2,'double'); f.addReceiver('rx',2);
    f.commitTransmissionsThrough('gnb',3);
    switch mode
        case "throw", expectedError="test:PhysicalProcessorFailure";
        case "missing_plane", expectedError="WAVEFORM:IncompletePhysicalOutputs";
        case {"proxy","source_proxy","fallback","pathloss_fallback"}, expectedError="WAVEFORM:ProxyPhysicalExecutionForbidden";
        case "clock", expectedError="WAVEFORM:PhysicalExecutionClockMismatch";
        otherwise, expectedError="WAVEFORM:PhysicalOutputIntervalMismatch";
    end
    localError(@()f.advanceUntilEvent(3),expectedError);
    assert(f.Faulted && f.FailureIdentifier==expectedError && isempty(f.ExecutionTrace));
    localError(@()f.advanceUntilEvent(3),'WAVEFORM:FaultedEventRuntime');
    localError(@()f.enqueue('gnb','retry',chunk(a,0)),'WAVEFORM:FaultedEventRuntime');
end
ok=true;
disp('WAVEFORM_EVENT_RUNTIME_PASS');
end

function [outputs,execution,state]=localProcessor(inputs,first,stop,state)
assert(state.NextSample==first && numel(inputs)==2);
x=inputs(1).Chunk.Samples+inputs(2).Chunk.Samples;
[y,state.FilterState]=filter([1 .25],1,x,state.FilterState);
state.Calls=state.Calls+1; state.NextSample=stop;
state.Inputs=[state.Inputs;x]; state.Outputs=[state.Outputs;y];
outputs=struct('ID',{'rx','tx_capture'},'Chunk', ...
    {sixgr.phy.waveform.WaveformChunk(y,first),sixgr.phy.waveform.WaveformChunk(x,first)});
execution=struct('Source',"deterministic_FIR_unit_fixture",'ApproximationMode',"none", ...
    'StartSample',first,'EndSampleExclusive',stop);
end

function [outputs,execution,state]=localBadProcessor(inputs,first,stop,state,mode)
if mode=="throw", error('test:PhysicalProcessorFailure','Deliberate processor failure.'); end
x=inputs(1).Chunk.Samples;
execution=struct('Source',"negative_contract_unit_fixture",'ApproximationMode',"none", ...
    'StartSample',first,'EndSampleExclusive',stop);
if mode=="short", x=x(1:end-1,:); end
if mode=="nan", x(1)=NaN; end
outputs=struct('ID','rx','Chunk',sixgr.phy.waveform.WaveformChunk(x,first));
switch mode
    case "missing_plane", outputs=outputs([]);
    case "proxy", execution.ApproximationMode="fast_proxy";
    case "source_proxy", execution.Source="legacy_fast_proxy";
    case "fallback", execution.FallbackUsed=true;
    case "pathloss_fallback", execution.FallbackUsedForPathloss=true;
    case "clock", execution.StartSample=first+1;
end
end

function localError(action,identifier)
try
    action();
catch cause
    assert(string(cause.identifier)==identifier,'Expected %s; got %s.',identifier,cause.identifier);
    return;
end
error('test:MissingExpectedError','Expected %s.',identifier);
end
