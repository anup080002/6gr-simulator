function ok=testAppliedTXLinearReferenceStream()
% DECLARED original-operand wrappers and deterministic mathematical kernels.
% No shared owner, original oscillator capture, RF stream, channel, received
% CSI power, hardware or standardized accuracy is qualified by this test.
setup6GRSimToolkit('Verbose',false);
saved=rng; restore=onCleanup(@()rng(saved)); %#ok<NASGU>
names=["arithmetic_and_components","split_silence","zero_linear_taps", ...
    "common_DC_and_independent_history","single_precision","nonlinear_residual", ...
    "invalid_operands","exact_clock_range","late_component_birth"];
checks={@arithmetic,@splitSilence,@zeroTaps,@commonAndHistory, ...
    @singlePrecision,@nonlinearResidual,@invalidOperands,@exactClockRange,@lateComponentBirth};
passed=false(size(checks)); failures=strings(size(checks));
for k=1:numel(checks)
    try
        before=rng; checks{k}(); assert(isequal(before,rng),'No global RNG mutation is allowed.');
        passed(k)=true; fprintf('TX_LINEAR_REFERENCE %s PASS\n',names(k));
    catch cause
        failures(k)=string(cause.identifier)+": "+string(cause.message);
        fprintf('TX_LINEAR_REFERENCE %s FAIL %s\n',names(k),failures(k));
    end
end
assert(all(passed),'test:AppliedTXLinearReferenceStream', ...
    '%d/%d groups passed: %s',nnz(passed),numel(passed),strjoin(failures(~passed),' | '));
fprintf('TX_LINEAR_REFERENCE_PASS groups=%d supplied_operands_only=1 original_owner=0 received_power=0\n',numel(checks));
ok=true;
end

function arithmetic()
b=binding("aggregate","double"); policy=operators("linear");
[x1,x2]=signals(83,3,"double"); x=x1+x2;
[actual,interval]=declaredExecution(x,b.OriginSample,b,policy,struct());
owner=sixgr.rf.runtime.AppliedTXLinearReferenceStream(b);
[next,y,r]=owner.advance(x,x,actual,interval);
assert(owner.NextSampleIndex==b.OriginSample&&next.NextSampleIndex==b.OriginSample+size(x,1));
expected=independentLinear(x,b.OriginSample,b,policy);
near(y,expected,1e-13); near(y,actual,1e-13);
c1=component(b,"port3000"); c2=component(b,"port3001");
[~,y1,r1]=c1.advance(x1,x,actual,interval);
[~,y2,r2]=c2.advance(x2,x,actual,interval);
near(y1+y2,y,1e-13);
assert(~r1.ResidualAvailable&&~r2.ResidualAvailable&&isnan(r1.ResidualEnergy));
scope(r); scope(r1); assert(r.PowerClosureRelativeError<1e-13);
end

function splitSilence()
b=binding("aggregate","double"); p=operators("memory_polynomial");
[x1,x2]=signals(137,3,"double"); x=x1+x2;
x(1:11,:)=0; x(65:70,:)=0; x(130:end,:)=0;
[actual,interval]=declaredExecution(x,b.OriginSample,b,p,struct());
whole=sixgr.rf.runtime.AppliedTXLinearReferenceStream(b);
[~,expected]=whole.advance(x,x,actual,interval);
split=sixgr.rf.runtime.AppliedTXLinearReferenceStream(b);
state=struct(); combined=zeros(size(x),'like',x); original=zeros(size(x),'like',x); first=0;
for last=[1 3 11 12 66 91 137]
    input=x(first+1:last,:);
    [part,record,state]=declaredExecution(input,b.OriginSample+first,b,p,state);
    [split,value,r]=split.advance(input,input,part,record);
    combined(first+1:last,:)=value; original(first+1:last,:)=part;
    assert(r.StartSample==b.OriginSample+first&&r.EndSampleExclusive==b.OriginSample+last);
    first=last;
end
near(original,actual,1e-13); near(combined,expected,1e-13);
% Matrix multiplication may choose different floating-point blocking for a
% one-row interval. This is mathematical continuity, not a bitwise claim
% about independently repartitioned physical RF execution.
% Original provenance differs by interval; numerical split invariance does
% not demand identical hashes for different interval populations.
end

function zeroTaps()
b=binding("aggregate","double"); [x1,x2]=signals(51,3,"double"); x=x1+x2;
for repeated=[false true]
    p=operators("memory_polynomial");
    if repeated
        p.PA.Profile.Orders=[1;3;1];
        p.PA.Profile.Coefficients=[1+.2i .1 0; .3 -.05 0; -1-.2i -.1 0];
    else
        p.PA.Profile.Orders=[3;5]; p.PA.Profile.Coefficients=[.3 -.05 0;.07 0 .01];
    end
    [actual,record]=declaredExecution(x,b.OriginSample,b,p,struct());
    stream=sixgr.rf.runtime.AppliedTXLinearReferenceStream(b);
    [~,reference,r]=stream.advance(x,x,actual,record);
    assert(all(reference(:)==0)&&r.ReferenceEnergy==0 && r.ResidualEnergy>0 && ...
        r.ReferenceResidualCrossEnergy==0 && r.PowerClosureRelativeError==0);
end
end

function commonAndHistory()
b=binding("aggregate","double"); p=operators("linear"); p.IQ.DCOffset=.06+.03i;
[x1,x2]=signals(49,3,"double"); x=x1+x2;
[actual,record,originalState]=declaredExecution(x,b.OriginSample,b,p,struct());
aggregate=sixgr.rf.runtime.AppliedTXLinearReferenceStream(b);
[aggregate,allReference,r]=aggregate.advance(x,x,actual,record);
c1=component(b,"first"); c2=component(b,"second"); common=component(b,"never_emitted");
[c1,y1,r1]=c1.advance(x1,x,actual,record); [c2,y2]=c2.advance(x2,x,actual,record);
[common,zero,rz]=common.advance(zeros(size(x),'like',x),x,actual,record);
assert(all(zero(:)==0)&&~r1.AggregateCommonIQDCIncluded && r.AggregateCommonIQDCIncluded);
expectedCommon=independentLinear(zeros(size(x),'like',x),b.OriginSample,b,p);
near(allReference-(y1+y2),expectedCommon,1e-13);
scope(rz);
% A silent component has its own zero history even while the aggregate has
% prior nonzero memory. Never import aggregate PA/delay state into it.
tail=zeros(7,3); [actualTail,tailRecord]=declaredExecution( ...
    tail,b.OriginSample+size(x,1),b,p,originalState);
[~,zeroTail]=common.advance(tail,tail,actualTail,tailRecord);
[~,aggregateTail]=aggregate.advance(tail,tail,actualTail,tailRecord);
assert(all(zeroTail(:)==0)&&any(aggregateTail(:)~=0));
assert(c1.NextSampleIndex==c2.NextSampleIndex);
end

function singlePrecision()
b=binding("aggregate","single"); p=operators("memory_polynomial");
[x1,x2]=signals(67,3,"single"); x=x1+x2;
[actual,record]=declaredExecution(x,b.OriginSample,b,p,struct());
stream=sixgr.rf.runtime.AppliedTXLinearReferenceStream(b);
[~,y,r]=stream.advance(x,x,actual,record);
assert(isa(y,'single')&&r.NumericClass=="single"&&r.PowerClosureRelativeError<1e-12);
scope(r);
end

function nonlinearResidual()
b=binding("aggregate","double"); [x1,x2]=signals(97,3,"double"); x=2*(x1+x2);
for model=["rapp","saleh","memory_polynomial"]
    p=operators(model); p.DAC.Enabled=true;
    [actual,record]=declaredExecution(x,b.OriginSample,b,p,struct());
    stream=sixgr.rf.runtime.AppliedTXLinearReferenceStream(b);
    [~,reference,r]=stream.advance(x,x,actual,record);
    residual=actual-reference;
    assert(r.ResidualAvailable&&r.ResidualEnergy>0);
    near(r.ResidualEnergy,sum(abs(residual(:)).^2),1e-13);
    near(r.ReferenceResidualCrossEnergy,2*real(sum(conj(reference(:)).*residual(:))),1e-13);
    near(r.ActualAggregateOutputEnergy, ...
        r.ReferenceEnergy+r.ResidualEnergy+r.ReferenceResidualCrossEnergy,1e-13);
    % Every pairwise cross term belongs to power closure; summing isolated
    % component energies alone is not an aggregate-power formula.
    c1=component(b,"target"); c2=component(b,"other");
    [~,a]=c1.advance(2*x1,x,actual,record); [~,d]=c2.advance(2*x2,x,actual,record);
    near(a+d,reference,1e-13);
    E=sum(abs(a(:)).^2)+sum(abs(d(:)).^2)+sum(abs(residual(:)).^2);
    cross=2*real(sum(conj(a(:)).*d(:))+sum(conj(a(:)).*residual(:))+sum(conj(d(:)).*residual(:)));
    near(E+cross,sum(abs(actual(:)).^2),1e-13);
    scope(r);
end
end

function invalidOperands()
b=binding("aggregate","double"); p=operators("linear"); [x,z]=signals(19,3,"double"); x=x+z;
[actual,r,originalState]=declaredExecution(x,b.OriginSample,b,p,struct());
stream=sixgr.rf.runtime.AppliedTXLinearReferenceStream(b);
bad=r; bad.StartSample=bad.StartSample+1; reject(@()stream.advance(x,x,actual,bad),'Clock');
bad=r; bad.EndSampleExclusive=bad.EndSampleExclusive-1; reject(@()stream.advance(x,x,actual,bad),'Clock');
for field=["ConfigurationEpoch","NumAntennas","SampleRateHz","OriginSample"]
    bad=r; bad.(field)=bad.(field)+1; reject(@()stream.advance(x,x,actual,bad),'Binding');
end
bad=r; bad.RFOutputWaveformSHA256=repmat('0',1,64); reject(@()stream.advance(x,x,actual,bad),'Samples');
reject(@()stream.advance(single(x),x,actual,r),'Samples');
reject(@()stream.advance(2*x,x,actual,r),'Samples');
bad=r; bad.Stages.NewStage=bad.Stages.DAC; reject(@()stream.advance(x,x,actual,bad),'Stage');
bad=r; bad.StageOrder=flip(bad.StageOrder); reject(@()stream.advance(x,x,actual,bad),'Stage');
bad=r; bad.Stages.PA.Executed=false; reject(@()stream.advance(x,x,actual,bad),'Stage');
bad=r; bad.Stages.IQ.Enabled=2; reject(@()stream.advance(x,x,actual,bad),'Stage');
bad=r; bad.Stages.Element.Parameters.PhysicalInputAlreadyMapped=false; reject(@()stream.advance(x,x,actual,bad),'Stage');
bad=r; bad.Stages.PhaseNoise.Parameters.Trace.Multiplier(1,1)=0; reject(@()stream.advance(x,x,actual,bad),'Stage');
bad=r; bad.Stages.PhaseNoise.Parameters.Trace.StateEpoch=NaN; reject(@()stream.advance(x,x,actual,bad),'Stage');
bad=r; bad.Stages.PhaseNoise.Parameters.Trace.Backend="comm_phase_noise_runtime_backend"; reject(@()stream.advance(x,x,actual,bad),'Stage');
bad=r; bad.Stages.CFO.Parameters.Multiplier=flipud(bad.Stages.CFO.Parameters.Multiplier); reject(@()stream.advance(x,x,actual,bad),'Clock');
for delay=[-1 .5]
    bad=r; bad.Stages.Timing.Parameters.DelaySamples=delay; reject(@()stream.advance(x,x,actual,bad),'Stage');
end
bad=r; bad.Stages.SampleClockOffset=enabled(struct('PPM',1));
bad.Stages.SampleClockOffset.InputSHA256=bad.Stages.Timing.OutputSHA256;
bad.Stages.SampleClockOffset.OutputSHA256=bad.Stages.Timing.OutputSHA256;
reject(@()stream.advance(x,x,actual,bad),'Unsupported');
bad=r; bad.Stages.DAC.Parameters=struct('InventedDefault',1); reject(@()stream.advance(x,x,actual,bad),'Stage');
assert(stream.NextSampleIndex==b.OriginSample&&stream.StaticOperatorSHA256=="");
[next,expected]=stream.advance(x,x,actual,r);
[out,following]=declaredExecution(x,next.NextSampleIndex,b,p,originalState);
changed=following; changed.InstallationSHA256=repmat('1',1,64);
reject(@()next.advance(x,x,out,changed),'Installation');
changed=following; changed.Stages.IQ.Parameters.Alpha=changed.Stages.IQ.Parameters.Alpha+.1;
reject(@()next.advance(x,x,out,changed),'Installation');
assert(next.NextSampleIndex==b.OriginSample+size(x,1));
fresh=sixgr.rf.runtime.AppliedTXLinearReferenceStream(b); [~,again]=fresh.advance(x,x,actual,r);
assert(isequal(expected,again),'Rejected value-state calls must not contaminate later valid calls.');
end

function exactClockRange()
% One sample with ALL stages disabled must still consume one exact clock
% tick. The same original stage/hash chain is retained in every negative.
b=binding("aggregate","double"); x=complex([.1 .2 .3]);
r=identityInterval(x,b); stream=sixgr.rf.runtime.AppliedTXLinearReferenceStream(b);
[next,y,receipt]=stream.advance(x,x,x,r);
assert(isequal(x,y)&&next.NextSampleIndex==b.OriginSample+1 && ...
    receipt.EndSampleExclusive-receipt.StartSample==1);
assert(receipt.OriginalRFInputSHA256==receipt.OriginalRFOutputSHA256);
for origin={2^60,single(2^24),uint64(37)}
    badBinding=b; badBinding.OriginSample=origin{1};
    reject(@()sixgr.rf.runtime.AppliedTXLinearReferenceStream(badBinding),'Binding');
end
for coordinate=["ConfigurationEpoch","NumAntennas"]
    badBinding=b; badBinding.(coordinate)=2^60;
    reject(@()sixgr.rf.runtime.AppliedTXLinearReferenceStream(badBinding),'Binding');
end
for ending={2^60,single(b.OriginSample+1),uint64(b.OriginSample+1)}
    bad=r; bad.EndSampleExclusive=ending{1};
    reject(@()stream.advance(x,x,x,bad),'Clock');
end
bad=r; bad.StartSample=single(b.OriginSample);
reject(@()stream.advance(x,x,x,bad),'Clock');
% The last exactly representable interval is valid; any following sample
% must fail BEFORE the clock addition can round back to its start.
edge=b; edge.OriginSample=flintmax-1;
edgeRecord=identityInterval(x,edge);
edgeStream=sixgr.rf.runtime.AppliedTXLinearReferenceStream(edge);
[edgeNext,edgeOutput,edgeReceipt]=edgeStream.advance(x,x,x,edgeRecord);
assert(isequal(edgeOutput,x)&&edgeNext.NextSampleIndex==flintmax && ...
    edgeReceipt.EndSampleExclusive-edgeReceipt.StartSample==1);
bad=edgeRecord; bad.StartSample=flintmax; bad.EndSampleExclusive=flintmax;
reject(@()edgeNext.advance(x,x,x,bad),'Clock');
edge.OriginSample=flintmax;
overflow=sixgr.rf.runtime.AppliedTXLinearReferenceStream(edge);
bad=identityInterval(x,edge); % Deliberate rounded zero-duration supplied record.
reject(@()overflow.advance(x,x,x,bad),'Clock');
assert(stream.NextSampleIndex==b.OriginSample && overflow.NextSampleIndex==flintmax);
end

function r=identityInterval(x,b)
keys={'DAC','IQ','Element','PA','PhaseNoise','CFO','Timing','SampleClockOffset','CarrierPhase'};
for k=1:numel(keys), stages.(keys{k})=disabled(); end
r=struct('ContractVersion',"sixgr.rf.supplied_TX_operator_interval/v1", ...
    'EndpointID',b.EndpointID,'Direction',b.Direction,'ConfigurationEpoch',b.ConfigurationEpoch, ...
    'SampleRateHz',b.SampleRateHz,'NumAntennas',b.NumAntennas,'NumericClass',b.NumericClass, ...
    'WaveformAmplitudeUnit',b.WaveformAmplitudeUnit,'OriginSample',b.OriginSample, ...
    'StartSample',b.OriginSample,'EndSampleExclusive',b.OriginSample+size(x,1), ...
    'InstallationSHA256',sixgr.util.sha256Hex('declared_identity_test_installation_not_original_owner'), ...
    'RFInputWaveformSHA256',sixgr.rf.waveformSHA256(x),'RFOutputWaveformSHA256',sixgr.rf.waveformSHA256(x), ...
    'StageOrder',["tx_dac","tx_iq","tx_element_rf","tx_pa","tx_phase_noise", ...
    "tx_cfo","tx_timing","tx_sample_clock_offset"],'Stages',stages);
end

function lateComponentBirth()
% The real aggregate has prior nonzero PA/delay history; the new component
% was zero before its first support. Its zero model history is not a new LO.
b=binding("component","double"); b.ReferenceID="later_port3001";
p=operators("memory_polynomial"); p.IQ.DCOffset=.06+.03i;
[previous,other]=signals(31,3,"double"); previous=previous+other;
[oldOutput,oldRecord,originalState]=declaredExecution(previous,b.OriginSample,b,p,struct());
continuous=sixgr.rf.runtime.AppliedTXLinearReferenceStream(b);
[continuous,oldZero]=continuous.advance(zeros(size(previous)),previous,oldOutput,oldRecord);
assert(all(oldZero(:)==0));
first=b.OriginSample+size(previous,1);
birth=struct('ContractVersion',"sixgr.rf.declared_TX_component_birth/v1", ...
    'ParentComponentID',"declared_CSIRS_component",'ResourceID',"resource2",'LogicalPort',3001, ...
    'ModelHistoryStartSample',first,'ComponentSupportStartSample',first+8, ...
    'ComponentSupportEndSampleExclusive',first+28, ...
    'RegistrationSHA256',sixgr.util.sha256Hex('declared_test_registration_not_original_owner'));
late=sixgr.rf.runtime.AppliedTXLinearReferenceStream.fromComponentBirth(b,birth);
[x,others]=signals(30,3,"double"); x([1:8 29:30],:)=0;
aggregate=x+others;
[actual,record,originalState]=declaredExecution(aggregate,first,b,p,originalState);
[continuous,expected]=continuous.advance(x,aggregate,actual,record);
[late,observed,receipt]=late.advance(x,aggregate,actual,record);
assert(isequal(expected,observed) && receipt.OriginSample==b.OriginSample && ...
    receipt.ModelHistoryStartSample==first && isequal(receipt.ComponentBirth,birth));
assert(record.Stages.PhaseNoise.Parameters.Trace.StartSample0==31);
scope(receipt);
% Tail samples use the retained component PA/delay memory; no aggregate
% history is imported and no oscillator is reinitialized.
tail=zeros(9,3); [actual,record]=declaredExecution(tail,late.NextSampleIndex,b,p,originalState);
[~,expected]=continuous.advance(tail,tail,actual,record);
[~,observed]=late.advance(tail,tail,actual,record);
assert(isequal(expected,observed)&&any(observed(:)~=0), ...
    'Retain actual finite model tails after the component input support ends.');
fresh=sixgr.rf.runtime.AppliedTXLinearReferenceStream.fromComponentBirth(b,birth);
[actual,record]=declaredExecution(aggregate,first,b,p,struct());
outside=x; outside(1,1)=.1;
reject(@()fresh.advance(outside,aggregate,actual,record),'History');
outside=x; outside(29,1)=.1;
reject(@()fresh.advance(outside,aggregate,actual,record),'History');
bad=record; bad.Stages.PhaseNoise.Parameters.Trace.StartSample0=0;
bad.Stages.PhaseNoise.Parameters.Trace.EndSampleExclusive=size(x,1);
reject(@()fresh.advance(x,aggregate,actual,bad),'Stage');
bad=record; bad.OriginSample=first;
reject(@()fresh.advance(x,aggregate,actual,bad),'Binding');
for key=["ModelHistoryStartSample","ComponentSupportStartSample","ComponentSupportEndSampleExclusive"]
    invalid=birth; invalid.(key)=uint64(invalid.(key));
    reject(@()sixgr.rf.runtime.AppliedTXLinearReferenceStream.fromComponentBirth(b,invalid),'History');
end
invalid=birth; invalid.ModelHistoryStartSample=b.OriginSample-1;
reject(@()sixgr.rf.runtime.AppliedTXLinearReferenceStream.fromComponentBirth(b,invalid),'History');
invalid=birth; invalid.ComponentSupportStartSample=first-1;
reject(@()sixgr.rf.runtime.AppliedTXLinearReferenceStream.fromComponentBirth(b,invalid),'History');
invalid=birth; invalid.ComponentSupportEndSampleExclusive=invalid.ComponentSupportStartSample;
reject(@()sixgr.rf.runtime.AppliedTXLinearReferenceStream.fromComponentBirth(b,invalid),'History');
invalid=birth; invalid.RegistrationSHA256="not_a_hash";
reject(@()sixgr.rf.runtime.AppliedTXLinearReferenceStream.fromComponentBirth(b,invalid),'Samples');
aggregateBinding=b; aggregateBinding.Role="aggregate";
reject(@()sixgr.rf.runtime.AppliedTXLinearReferenceStream.fromComponentBirth(aggregateBinding,birth),'History');
assert(fresh.NextSampleIndex==first && fresh.StaticOperatorSHA256=="");
end

function b=binding(role,numericClass)
b=struct('EndpointID',"declared_tx",'Direction',"DL",'ReferenceID',"all_input", ...
    'Role',role,'ConfigurationEpoch',7,'SampleRateHz',1.92e6,'NumAntennas',3, ...
    'NumericClass',numericClass,'WaveformAmplitudeUnit',"normalized_complex_baseband", ...
    'OriginSample',37,'HistoryInitialization',"declared_zero_model_state");
end
function c=component(b,id)
b.Role="component"; b.ReferenceID=id;
c=sixgr.rf.runtime.AppliedTXLinearReferenceStream(b);
end
function p=operators(model)
c=sixgr.rf.runtime.IQImbalanceProfile.coefficients(1.3,9);
p.IQ=struct('Alpha',c.Alpha,'Beta',c.Beta,'DCOffset',0);
p.Element=struct('Gain',[1 .8*exp(.2i) 1.1*exp(-.3i)], ...
    'Coupling',[1 .02i 0;.03 1 -.01i;0 .01 1],'PhysicalInputAlreadyMapped',true);
q=struct('ProfileID',"declared_PA",'Version',"1",'Model',model, ...
    'ReferenceDomain',"normalized_complex_baseband_full_scale",'InputBackoff_dB',2.7);
switch model
    case "rapp", q.Smoothness=2; q.SaturationAmplitude=.27;
    case "saleh", q.AlphaAM=1.4; q.BetaAM=2; q.AlphaPM=.6; q.BetaPM=.8;
    otherwise
        q.Model="memory_polynomial"; q.Orders=[1;3;1]; q.MemoryDepth=3;
        q.Coefficients=[.8+.1i -.07+.02i .03;-.2+.03i .01 0;.1-.02i .02 .01i];
        if model=="linear", q.Coefficients(2,:)=0; end
end
p.PA=struct('Profile',q); p.CFO=12000; p.Delay=3; p.CarrierPhase=exp(.17i);
p.DAC=struct('Enabled',false,'Profile',struct('Bits',7,'FullScale',.35, ...
    'Convention',"signed_midtread",'DitherRMS',0,'ApertureJitter_s',0, ...
    'ProfileID',"declared_DAC",'Version',"1",'Seed',19));
end
function [a,d]=signals(n,columns,numericClass)
t=(0:n-1).'; k=1:columns;
a=cast(.23*exp(1j*(.13*t+.21*k)),char(numericClass));
d=cast(.15*exp(1j*(.19*t-.37*k))+.03*cos(.07*t+k),char(numericClass));
end

function [y,r,state]=declaredExecution(x,first,b,p,state)
% Actual deterministic PA/converter kernels; other operators explicitly
% declared here. This is NOT an original RF stream execution receipt.
keys={'DAC','IQ','Element','PA','PhaseNoise','CFO','Timing','SampleClockOffset','CarrierPhase'};
for k=1:numel(keys), stages.(keys{k})=disabled(); end
y=x;
if p.DAC.Enabled
    before=y; result=sixgr.rf.runtime.DACModel.convert(y,p.DAC.Profile,b.SampleRateHz,p.DAC.Profile.Seed);
    y=result.Output;
    stages.DAC=seal(enabled(struct('Profile',p.DAC.Profile,'ReferenceModel',"identity_converter_reference")),before,y);
end
before=y; y=p.IQ.Alpha.*y+p.IQ.Beta.*conj(y)+cast(p.IQ.DCOffset,'like',y);
stages.IQ=seal(enabled(p.IQ),before,y);
before=y; y=(y.*cast(p.Element.Gain,'like',y))*cast(p.Element.Coupling.','like',y);
stages.Element=seal(enabled(p.Element),before,y);
before=y; q=p.PA.Profile;
if string(q.Model)=="memory_polynomial"
    if ~isfield(state,'PA'), state.PA=[]; end
    driven=y.*cast(10^(-q.InputBackoff_dB/20),'like',y);
    [y,state.PA]=sixgr.rf.runtime.MemoryPolynomialPA.apply(driven,q.Coefficients,q.Orders,state.PA);
else
    y=sixgr.rf.runtime.PAProfile.apply(y,q);
end
stages.PA=seal(enabled(p.PA),before,y);
sample=first+(0:size(x,1)-1).';
phase=.04*sin(.13*sample+(1:b.NumAntennas)*.2)+.02*cos(.3*sample);
pn=struct('Available',true,'Phase_rad',phase,'Multiplier',cast(exp(1j.*phase),'like',x), ...
    'Backend',"sixgr_rf_runtime_phase_noise_process",'StateEpoch',b.ConfigurationEpoch, ...
    'StartSample0',first-b.OriginSample,'EndSampleExclusive',first-b.OriginSample+size(x,1), ...
    'Scope',"original_executed_phase_noise_multiplier");
before=y; y=y.*pn.Multiplier; stages.PhaseNoise=seal(enabled(struct('Trace',pn)),before,y);
multiplier=cast(exp(1j*2*pi*p.CFO/b.SampleRateHz*sample),'like',x);
before=y; y=y.*multiplier;
stages.CFO=seal(enabled(struct('FrequencyHz',p.CFO,'Multiplier',multiplier)),before,y);
if ~isfield(state,'Delay'), state.Delay=zeros(p.Delay,b.NumAntennas,'like',x); end
before=y; [y,state.Delay]=filter([zeros(1,p.Delay) 1],1,y,state.Delay,1);
stages.Timing=seal(enabled(struct('DelaySamples',p.Delay)),before,y);
before=y; y=y.*p.CarrierPhase;
stages.CarrierPhase=seal(enabled(struct('Multiplier',p.CarrierPhase)),before,y);
r=struct('ContractVersion',"sixgr.rf.supplied_TX_operator_interval/v1", ...
    'EndpointID',b.EndpointID,'Direction',b.Direction,'ConfigurationEpoch',b.ConfigurationEpoch, ...
    'SampleRateHz',b.SampleRateHz,'NumAntennas',b.NumAntennas,'NumericClass',b.NumericClass, ...
    'WaveformAmplitudeUnit',b.WaveformAmplitudeUnit,'OriginSample',b.OriginSample, ...
    'StartSample',first,'EndSampleExclusive',first+size(x,1), ...
    'InstallationSHA256',sixgr.util.sha256Hex('declared_test_installation_not_original_owner'), ...
    'RFInputWaveformSHA256',sixgr.rf.waveformSHA256(x),'RFOutputWaveformSHA256',sixgr.rf.waveformSHA256(y), ...
    'StageOrder',["tx_dac","tx_iq","tx_element_rf","tx_pa","tx_phase_noise", ...
    "tx_cfo","tx_timing","tx_sample_clock_offset","tx_carrier_phase"], ...
    'Stages',stages);
end
function y=independentLinear(x,first,b,p)
% Independent arithmetic oracle for the declared linear-only fixture.
y=p.IQ.Alpha.*x+p.IQ.Beta.*conj(x)+cast(p.IQ.DCOffset,'like',x);
y=(y.*p.Element.Gain)*p.Element.Coupling.';
q=p.PA.Profile; taps=sum(q.Coefficients(q.Orders==1,:),1)*10^(-q.InputBackoff_dB/20);
y=filter(taps,1,y);
sample=first+(0:size(x,1)-1).';
phase=.04*sin(.13*sample+(1:b.NumAntennas)*.2)+.02*cos(.3*sample);
y=y.*exp(1j.*phase).*exp(1j*2*pi*p.CFO/b.SampleRateHz*sample);
y=filter([zeros(1,p.Delay) 1],1,y).*p.CarrierPhase;
end
function s=disabled()
s=struct('Enabled',false,'Executed',false,'InputSHA256',"disabled_identity", ...
    'OutputSHA256',"disabled_identity",'Parameters',struct());
end
function s=enabled(parameters)
s=struct('Enabled',true,'Executed',true,'InputSHA256',"",'OutputSHA256',"",'Parameters',parameters);
end
function s=seal(s,x,y)
s.InputSHA256=sixgr.rf.waveformSHA256(x); s.OutputSHA256=sixgr.rf.waveformSHA256(y);
end
function scope(r)
assert(r.SuppliedOperandsValidated&&~r.OriginalOwnerVerified&&~r.SharedRuntimeIntegrationQualified && ...
    ~r.ActualNonlinearPortAttribution&&~r.StandardizedPowerAccuracyQualified&&~r.HardwareQualified && ...
    ~r.ReceiverEstimatorInput&&r.AdditionalRFExecutions==0&&r.AdditionalChannelExecutions==0);
end
function near(a,b,tolerance)
assert(isequal(size(a),size(b))&&norm(double(a(:))-double(b(:)))<= ...
    tolerance*max(1,norm(double(b(:)))),'test:TXLinearReferenceArithmetic','Mathematical closure failed.');
end
function reject(action,suffix)
identifier="RF:TXLinearReference"+suffix;
try, action(); catch cause
    assert(string(cause.identifier)==identifier,'test:TXLinearReferenceWrongError', ...
        'Expected %s; got %s: %s',identifier,cause.identifier,cause.message); return;
end
error('test:TXLinearReferenceMissingError','Expected %s.',identifier);
end
