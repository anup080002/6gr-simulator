function ok=testWaveformEnqueueReceipt()
% Original coordinator registration/consumption only. The deterministic FIR
% processor below is a declared mechanics fixture, not RF/channel/NR evidence.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
for precision=["double","single"]
    localSuccess(precision);
end
localFailure();
localSafeClock();
fprintf('WAVEFORM_ENQUEUE_RECEIPT_PASS groups=4 physical_RF_channel_qualification=0\n');
ok=true;
end

function localSuccess(precision)
first=11; fs=1000; a0=17; stop=24;
r=localRuntime(fs,first,precision,@localProcessor);
baseline=localRuntime(fs,first,precision,@localProcessor);
x=cast(complex(reshape(1:14,7,2),-reshape(1:14,7,2)/3),precision);
a=sixgr.phy.waveform.WaveformChunk(x,a0);
z=sixgr.phy.waveform.WaveformChunk(complex(zeros(3,2,precision)),13);
before=rng;
receipt=r.enqueue('gnb','original_a',a);
zeroReceipt=r.enqueue('gnb','declared_zero',z);
baseline.enqueue('gnb','original_a',a); % Existing no-output API remains exact.
baseline.enqueue('gnb','declared_zero',z);
assert(isequal(rng,before) && r.NextSampleIndex==first && ...
    r.ProcessorState.Calls==0 && isempty(r.ExecutionTrace));
assert(receipt.ContractVersion=="sixgr.waveform.enqueued_component/v1" && ...
    receipt.Source=="original_event_runtime_accepted_component_not_physical_execution" && ...
    receipt.TransmitterID=="gnb" && receipt.ComponentID=="original_a" && ...
    receipt.StartSample==a0 && receipt.EndSampleExclusive==stop && ...
    receipt.SampleRateHz==fs && receipt.NumTransmitAntennas==2 && ...
    receipt.NumericClass==precision && receipt.OriginalSampleSHA256==a.SHA256 && ...
    receipt.HashSerialization=="WaveformChunk.SHA256_numeric" && ...
    receipt.EnqueuedAtSample==first && receipt.CommittedThroughSample==first && ...
    ~receipt.PhysicalExecutionPerformed);
assert(receipt.ReceiptSHA256==string(sixgr.util.sha256Hex(jsonencode(rmfield(receipt,'ReceiptSHA256')))));
assert(zeroReceipt.OriginalSampleSHA256==z.SHA256 && ...
    ~zeroReceipt.PhysicalExecutionPerformed && ~isfield(receipt,'Samples'));
localError(@()r.enqueue('gnb','original_a',a),'WAVEFORM:DuplicateComponent');
localError(@()r.enqueue('gnb','wrong_class', ...
    sixgr.phy.waveform.WaveformChunk(cast(x,localOtherClass(precision)),a0)), ...
    'WAVEFORM:SamplePrecisionMismatch');
for owner={r,baseline}
    q=owner{1};
    q.observe('rx','whole',first,stop);
    q.decisionBoundary('partial',19);
    q.commitTransmissionsThrough('gnb',stop);
end
localError(@()r.enqueue('gnb','committed',a),'WAVEFORM:CommittedTransmission');
events=cell(2,1);
for index=1:2
    events{index}=r.advanceUntilEvent(stop);
    expected=baseline.advanceUntilEvent(stop);
    assert(isequaln(events{index}.Execution,expected.Execution) && ...
        isequaln(r.ProcessorState,baseline.ProcessorState) && ...
        isequaln(r.ExecutionTrace,baseline.ExecutionTrace));
    c=events{index}.Execution.ExecutedContributors;
    assert(events{index}.PhysicalExecutionPerformed && numel(c)==1 && ...
        c.TransmitterID==receipt.TransmitterID && c.Receipt.CompleteContributorList);
    hit=c.Receipt.Components(string({c.Receipt.Components.ComponentID})==receipt.ComponentID);
    assert(isscalar(hit) && hit.OriginalSampleSHA256==receipt.OriginalSampleSHA256 && ...
        hit.StartSample==max(receipt.StartSample,events{index}.StartSample) && ...
        hit.EndSampleExclusive==min(receipt.EndSampleExclusive,events{index}.EndSampleExclusive));
end
expectedInput=[complex(zeros(a0-first,2,precision));x];
assert(isequal(r.ProcessorState.Inputs,expectedInput) && ...
    isequal(events{2}.Completed.Observation.readComplete(),r.ProcessorState.Outputs) && ...
    isequal(rng,before) && ~receipt.PhysicalExecutionPerformed);
% Replacement/cancellation do not rewrite an old enqueue receipt into new
% sample authority. Successful consumption retains the replacement hash.
q=localRuntime(fs,first,precision,@localProcessor);
old=q.enqueue('gnb','replace_me',a);
replacement=sixgr.phy.waveform.WaveformChunk(2*x,a0);
change=q.replaceUnemittedComponent('gnb','replace_me',replacement);
cancelled=q.enqueue('gnb','cancel_me',z);
cancel=q.cancelUnemittedComponent('gnb','cancel_me');
q.commitTransmissionsThrough('gnb',stop);
actual=q.advanceUntilEvent(stop);
components=actual.Execution.ExecutedContributors.Receipt.Components;
assert(numel(components)==1 && components.OriginalSampleSHA256==replacement.SHA256 && ...
    old.OriginalSampleSHA256==a.SHA256 && old.OriginalSampleSHA256~=replacement.SHA256 && ...
    change.OriginalSampleSHA256==old.OriginalSampleSHA256 && ...
    cancel.OriginalSampleSHA256==cancelled.OriginalSampleSHA256);
end

function localFailure()
r=localRuntime(1000,0,"double",@localBadProcessor);
c=sixgr.phy.waveform.WaveformChunk(ones(3,2),0);
receipt=r.enqueue('gnb','registered_not_emitted',c);
r.commitTransmissionsThrough('gnb',3);
localError(@()r.advanceUntilEvent(3),'test:DeclaredProcessorFailure');
assert(r.Faulted && isempty(r.ExecutionTrace) && ~receipt.PhysicalExecutionPerformed);
localError(@()r.enqueue('gnb','retry',c),'WAVEFORM:FaultedEventRuntime');
end

function localSafeClock()
r=localRuntime(1000,0,"double",@localProcessor);
bad=sixgr.phy.waveform.WaveformChunk(ones(2,2),flintmax);
localError(@()localRequestReceipt(r,bad),'WAVEFORM:EnqueueReceiptClock');
% Failed metadata preflight must not reserve the component ID.
good=sixgr.phy.waveform.WaveformChunk(ones(2,2),0);
receipt=r.enqueue('gnb','safe_clock',good);
assert(receipt.StartSample==0 && receipt.EndSampleExclusive==2 && ...
    r.ProcessorState.Calls==0 && ~r.Faulted);
end

function localRequestReceipt(r,chunk)
receipt=r.enqueue('gnb','safe_clock',chunk); %#ok<NASGU>
end

function r=localRuntime(fs,first,precision,processor)
s=struct('Calls',0,'NextSample',first, ...
    'FilterState',complex(zeros(1,2,precision)), ...
    'Inputs',complex(zeros(0,2,precision)),'Outputs',complex(zeros(0,2,precision)));
r=sixgr.phy.waveform.WaveformEventRuntime(fs,first,processor,s);
r.addTransmitter('gnb',2,precision); r.addReceiver('rx',2);
end

function [out,e,s]=localProcessor(inputs,first,stop,s)
assert(s.NextSample==first && numel(inputs)==1);
x=inputs.Chunk.Samples;
[y,s.FilterState]=filter(cast([1 .25],'like',x),1,x,s.FilterState);
s.Calls=s.Calls+1; s.NextSample=stop;
s.Inputs=[s.Inputs;x]; s.Outputs=[s.Outputs;y];
out=struct('ID',"rx",'Chunk',sixgr.phy.waveform.WaveformChunk(y,first));
e=struct('Source',"declared_deterministic_FIR_registration_test", ...
    'ApproximationMode',"none",'StartSample',first,'EndSampleExclusive',stop);
end

function [out,e,s]=localBadProcessor(varargin) %#ok<STOUT,INUSD>
error('test:DeclaredProcessorFailure','Deliberate failed processing; no execution receipt.');
end

function value=localOtherClass(value)
if value=="double", value="single"; else, value="double"; end
end

function localError(action,identifier)
try
    action();
catch cause
    assert(string(cause.identifier)==identifier,'Expected %s; got %s: %s.', ...
        identifier,cause.identifier,cause.message);
    return;
end
error('test:MissingExpectedError','Expected %s.',identifier);
end
