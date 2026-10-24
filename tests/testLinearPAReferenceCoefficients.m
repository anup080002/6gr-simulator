function ok=testLinearPAReferenceCoefficients()
% Declared profiles and actual mathematical PA kernels only. No RF stream,
% channel, received-power, hardware or standards-accuracy qualification.
setup6GRSimToolkit('Verbose',false);
saved=rng; restore=onCleanup(@()rng(saved)); %#ok<NASGU>
names=["rapp_limit","saleh_limit","complex_memory_limit", ...
    "absent_first_order","coefficient_shape_and_order","invalid_profiles"];
checks={@rappLimit,@salehLimit,@memoryLimit,@absentOrderOne,@shapeAndOrder,@invalidProfiles};
passed=false(size(checks)); failures=strings(size(checks));
for k=1:numel(checks)
    try
        checks{k}(); passed(k)=true;
        fprintf('LINEAR_PA_REFERENCE %s PASS\n',names(k));
    catch cause
        failures(k)=string(cause.identifier)+": "+string(cause.message);
        fprintf('LINEAR_PA_REFERENCE %s FAIL %s\n',names(k),failures(k));
    end
end
assert(all(passed),'test:LinearPAReferenceCoefficients', ...
    '%d/%d groups passed: %s',nnz(passed),numel(passed),strjoin(failures(~passed),' | '));
fprintf('LINEAR_PA_REFERENCE_PASS groups=%d fixed_model_only=1 original_RF_bound=0\n',numel(checks));
ok=true;
end

function rappLimit()
p=profile("rapp",5.7); p.Smoothness=2.1; p.SaturationAmplitude=0.83;
r=verify(p); g=10^(-p.InputBackoff_dB/20);
assert(r.LinearTaps==g&&r.TapsBeforeInputBackoff==1 && ...
    r.DeclaredOrderOnePresent&&isequal(r.TapDelaysSamples0,0));
x=signal(); amplitudes=[0.2 1e-4]; errors=zeros(size(amplitudes));
for k=1:numel(amplitudes)
    a=amplitudes(k);
    [actual,receipt]=sixgr.rf.runtime.PAProfile.apply(a*x,p);
    expected=filter(r.LinearTaps,1,x);
    errors(k)=norm(actual/a-expected,'fro')/norm(expected,'fro');
    assert(receipt.BackoffReferencePlane=="before_pa_nonlinearity" && ...
        ~receipt.PowerRestorationApplied);
end
assert(errors(2)<1e-10&&errors(2)<errors(1), ...
    'Actual Rapp small-signal limit must approach the declared reference, not fitted gain.');
p.SaturationAmplitude=0.41; changed=verify(p);
assert(changed.LinearTaps==r.LinearTaps && ...
    changed.ConsumedProfileParametersSHA256~=r.ConsumedProfileParametersSHA256, ...
    'Nonlinear saturation changes provenance but not the fixed first-order term.');
end

function salehLimit()
p=profile("saleh",-2.4);
p.AlphaAM=2.3; p.BetaAM=0.7; p.AlphaPM=-0.48; p.BetaPM=1.1;
r=verify(p); g=10^(-p.InputBackoff_dB/20);
assert(r.LinearTaps==p.AlphaAM*g&&r.InputBackoffAmplitudeGain>1);
x=signal(); amplitudes=[0.1 1e-5]; errors=zeros(size(amplitudes));
for k=1:numel(amplitudes)
    a=amplitudes(k);
    actual=sixgr.rf.runtime.PAProfile.apply(a*x,p);
    expected=filter(r.LinearTaps,1,x);
    errors(k)=norm(actual/a-expected,'fro')/norm(expected,'fro');
end
assert(errors(2)<1e-8&&errors(2)<errors(1));
p.AlphaPM=1.7; changed=verify(p);
assert(changed.LinearTaps==r.LinearTaps && ...
    changed.ConsumedProfileParametersSHA256~=r.ConsumedProfileParametersSHA256);
% The executed Saleh kernel accepts negative finite denominator terms.
% Their poles are away from this origin limit; no global range is claimed.
p.BetaAM=-0.7; p.BetaPM=-1.1; negativeBeta=verify(p);
assert(negativeBeta.LinearTaps==r.LinearTaps && ...
    negativeBeta.ConsumedProfileParametersSHA256~=r.ConsumedProfileParametersSHA256);
a=1e-5; actual=sixgr.rf.runtime.PAProfile.apply(a*x,p);
expected=filter(negativeBeta.LinearTaps,1,x);
assert(norm(actual/a-expected,'fro')/norm(expected,'fro')<1e-8);
end

function memoryLimit()
p=profile("memory_polynomial",7.3);
p.Orders=[5;1;3]; p.MemoryDepth=3;
p.Coefficients=[0.03+0.02i -0.01i 0.007; ...
    0.8+0.3i -0.2+0.07i 0.04-0.09i; ...
    -0.13+0.08i 0.03-0.02i 0.01i];
r=verify(p); g=10^(-p.InputBackoff_dB/20);
assert(isequal(r.OriginalPolynomialOrders,p.Orders) && ...
    isequal(r.TapsBeforeInputBackoff,p.Coefficients(2,:)) && ...
    isequal(r.LinearTaps,p.Coefficients(2,:)*g) && ...
    isequal(r.TapDelaysSamples0,0:2));
x=signal(); amplitudes=[0.2 1e-4]; errors=zeros(size(amplitudes));
for k=1:numel(amplitudes)
    a=amplitudes(k);
    % Actual retained-PA kernel convention: original backoff is applied
    % to its INPUT, exactly as RFImpairmentStream.applyPA does. No RF owner
    % or executed interval is manufactured by this component test.
    driven=(a*x).*g;
    [actual,~]=sixgr.rf.runtime.MemoryPolynomialPA.apply( ...
        driven,p.Coefficients,p.Orders,[]);
    expected=filter(r.LinearTaps,1,x);
    errors(k)=norm(actual/a-expected,'fro')/norm(expected,'fro');
    [first,state]=sixgr.rf.runtime.MemoryPolynomialPA.apply( ...
        driven(1:19,:),p.Coefficients,p.Orders,[]);
    [second,~]=sixgr.rf.runtime.MemoryPolynomialPA.apply( ...
        driven(20:end,:),p.Coefficients,p.Orders,state);
    assert(isequal([first;second],actual), ...
        'Actual kernel history must be continuous across the split.');
end
assert(errors(2)<1e-8&&errors(2)<errors(1));
% Changing only a coefficient's imaginary part must not disappear through
% JSON encoding or a real-only digest.
changed=p; changed.Coefficients(2,2)=changed.Coefficients(2,2)+0.01i;
s=verify(changed);
assert(s.LinearTapsSHA256~=r.LinearTapsSHA256 && ...
    s.ConsumedProfileParametersSHA256~=r.ConsumedProfileParametersSHA256);
end

function absentOrderOne()
p=profile("memory_polynomial",3.1);
p.Orders=[3 5]; p.MemoryDepth=2;
p.Coefficients=[0.7+0.2i -0.11i;0.04 0.02+0.01i];
r=verify(p);
assert(~r.DeclaredOrderOnePresent&&isequal(r.LinearTaps,complex(zeros(1,2))) && ...
    isequal(r.TapDelaysSamples0,[0 1]), ...
    'Missing order one is a zero reference, never an invented unity tap.');
x=signal(); amplitudes=[0.1 1e-4]; responses=zeros(size(amplitudes));
for k=1:numel(amplitudes)
    a=amplitudes(k); driven=(a*x)*10^(-p.InputBackoff_dB/20);
    actual=sixgr.rf.runtime.MemoryPolynomialPA.apply(driven,p.Coefficients,p.Orders,[]);
    responses(k)=norm(actual,'fro')/(a*norm(x,'fro'));
end
assert(responses(2)<1e-8&&responses(2)<responses(1));
end

function shapeAndOrder()
% Preserve production's one-tap row-vector convention.
p=profile("memory_polynomial",1.9);
p.Orders=[3 1 5]; p.MemoryDepth=1; p.Coefficients=[-0.2 0.9 0.03];
r=verify(p);
assert(isequal(r.OriginalPolynomialOrders,[3 1 5]) && ...
    r.LinearTaps==0.9*10^(-p.InputBackoff_dB/20));
[actual,~]=sixgr.rf.runtime.PAProfile.apply(1e-5*signal(),p);
expected=1e-5*signal()*r.LinearTaps;
assert(norm(actual-expected,'fro')/norm(expected,'fro')<1e-9);
% A single-order multi-tap ROW is not transposed into multiple orders.
p.Orders=1; p.MemoryDepth=3; p.Coefficients=[1+0.1i .25 -.125i];
r=verify(p);
assert(isequal(r.TapsBeforeInputBackoff,p.Coefficients) && ...
    isequal(size(r.LinearTaps),[1 3]));
x=signal();
actual=sixgr.rf.runtime.MemoryPolynomialPA.apply( ...
    x*10^(-p.InputBackoff_dB/20),p.Coefficients,p.Orders,[]);
expected=filter(r.LinearTaps,1,x);
assert(norm(actual-expected,'fro')<1e-13*norm(expected,'fro'));
% Repeated original orders are additive in the actual kernel, not ambiguous.
p=profile("memory_polynomial",4.1);
p.Orders=[1;3;1;3]; p.MemoryDepth=2;
p.Coefficients=[0.6+0.2i -0.08i; -0.13 0.02+0.01i; ...
    0.3-0.1i 0.07+0.02i; 0.04i -0.01];
r=verify(p); g=10^(-p.InputBackoff_dB/20);
assert(isequal(r.OriginalPolynomialOrders,p.Orders) && ...
    isequal(r.TapsBeforeInputBackoff,sum(p.Coefficients([1 3],:),1)));
a=1e-5;
actual=sixgr.rf.runtime.MemoryPolynomialPA.apply( ...
    a*x*g,p.Coefficients,p.Orders,[]);
expected=filter(r.LinearTaps,1,x);
assert(norm(actual/a-expected,'fro')/norm(expected,'fro')<1e-8);
reordered=p; reordered.Orders=p.Orders([3 2 1 4]);
reordered.Coefficients=p.Coefficients([3 2 1 4],:);
s=verify(reordered);
assert(isequal(s.LinearTaps,r.LinearTaps) && ...
    s.ConsumedProfileParametersSHA256~=r.ConsumedProfileParametersSHA256, ...
    'Original row identity/order is retained even for equivalent coefficients.');
% Present order-one rows can cancel exactly; do not replace the zero sum.
p.Coefficients(3,:)=-p.Coefficients(1,:); zero=verify(p);
assert(zero.DeclaredOrderOnePresent&&all(zero.LinearTaps==0));
actual=sixgr.rf.runtime.MemoryPolynomialPA.apply( ...
    a*x*g,p.Coefficients,p.Orders,[]);
assert(norm(actual,'fro')/(a*norm(x,'fro'))<1e-8);
end

function invalidProfiles()
id='RF:InvalidLinearPAReferenceProfile';
p=profile("rapp",2); p.Smoothness=2; p.SaturationAmplitude=1;
reject(struct(),id); reject([p p],id);
for name=["ProfileID","Version","Model","ReferenceDomain","InputBackoff_dB","Smoothness","SaturationAmplitude"]
    reject(rmfield(p,name),id);
end
for value={NaN,Inf,[1 2],1i,1e6,-1e6}
    b=p; b.InputBackoff_dB=value{1}; reject(b,id);
end
for value={0,-1,NaN,1i,[1 2]}
    b=p; b.Smoothness=value{1}; reject(b,id);
    b=p; b.SaturationAmplitude=value{1}; reject(b,id);
end
b=p; b.ReferenceDomain=""; reject(b,id);
b=p; b.ProfileID=missing; reject(b,id);
b=p; b.Model="gmp"; reject(b,'RF:UnsupportedLinearPAReferenceModel');
b=p; b.Model="configured_not_executed"; reject(b,'RF:UnsupportedLinearPAReferenceModel');
b=profile("saleh",2); b.AlphaAM=2; b.BetaAM=1; b.AlphaPM=0.5; b.BetaPM=1;
for name=["AlphaAM","BetaAM","AlphaPM","BetaPM"]
    reject(rmfield(b,name),id);
    c=b; c.(name)=NaN; reject(c,id);
    c=b; c.(name)=1i; reject(c,id);
end
p=profile("memory_polynomial",2); p.Orders=[1 3]; p.MemoryDepth=2; p.Coefficients=ones(2);
for name=["Orders","MemoryDepth","Coefficients"], reject(rmfield(p,name),id); end
for value={[],[1 2.5],[0 3],[1 NaN],[1 3i]}
    b=p; b.Orders=value{1}; reject(b,id);
end
for value={[],[1 2 3],ones(3),[1 NaN;2 3],[1 Inf;2 3]}
    b=p; b.Coefficients=value{1}; reject(b,id);
end
for value={0,1.5,NaN,3,[1 2]}
    b=p; b.MemoryDepth=value{1}; reject(b,id);
end
% Invalid single-order column cannot silently become a multi-tap row.
b=p; b.Orders=1; b.MemoryDepth=3; b.Coefficients=[1;.2;.1]; reject(b,id);
end

function p=profile(model,backoff)
p=struct('ProfileID',"declared_component_PA",'Version',"1", ...
    'Model',model,'ReferenceDomain',"normalized_complex_baseband_full_scale", ...
    'InputBackoff_dB',backoff);
end
function x=signal()
n=(0:63).';
x=[0.7*exp(1i*0.17*n),0.4*cos(0.13*n)+0.3i*sin(0.31*n)];
end
function r=verify(p)
before=rng; original=p;
r=sixgr.rf.runtime.linearPAReferenceCoefficients(p);
assert(isequaln(p,original)&&isequal(before,rng));
assert(r.ContractVersion=="sixgr.rf.fixed_linear_PA_reference/v1" && ...
    r.ReferenceModel=="fixed_declared_first_order_PA" && ...
    r.InputBackoffIncluded&&r.AdditionalBackoffApplicationsRequired==0 && ...
    ~r.OriginalRFExecutionBound&&~r.CoefficientsFittedFromSamples && ...
    ~r.OperatingTrajectoryConditioned&&~r.ActualNonlinearPerPortOutput && ...
    ~r.HardwareQualified&&~r.StandardizedPowerAccuracyQualified && ...
    ~r.ReferenceUsedByReceiver&&r.AdditionalRFExecutions==0&&r.AdditionalChannelExecutions==0);
assert(r.ConsumedProfileParametersSHA256== ...
    sixgr.util.sha256Hex(char(r.ConsumedProfileParametersJSON)) && ...
    r.LinearTapsSHA256==sixgr.phy.waveform.WaveformHash.runtimeArray(r.LinearTaps));
end
function reject(p,identifier)
try
    sixgr.rf.runtime.linearPAReferenceCoefficients(p);
catch cause
    assert(strcmp(cause.identifier,identifier),'test:LinearPAWrongFailure', ...
        'Expected %s, got %s: %s',identifier,cause.identifier,cause.message);
    return;
end
error('test:LinearPAMissingFailure','Expected %s.',identifier);
end
