function ok=testPhaseNoiseOriginalOperator()
% Original oscillator operator receipt only: no RF stream, channel, CSI
% estimator or radio-clock/standards-power qualification. The two-output
% PhaseNoiseModel API must retain operands from the SAME original call.
setup6GRSimToolkit('Verbose',false);
saved=rng; restore=onCleanup(@()rng(saved)); %#ok<NASGU>
names=["canonical_double","canonical_single","zero_input", ...
    "partition_and_correlation","spectral_operator","disabled_and_legacy"];
checks={@()samePartition("double","ar1_mask_fit"), ...
    @()samePartition("single","ar1_mask_fit"),@zeroInput, ...
    @partitionAndCorrelation,@spectralOperator,@disabledAndLegacy};
passed=false(size(checks)); failures=strings(size(checks));
for k=1:numel(checks)
    try
        checks{k}(); passed(k)=true;
        fprintf('PN_ORIGINAL_OPERATOR %s PASS\n',names(k));
    catch cause
        failures(k)=string(cause.identifier)+": "+string(cause.message);
        fprintf('PN_ORIGINAL_OPERATOR %s FAIL %s\n',names(k),failures(k));
    end
end
assert(all(passed),'test:PhaseNoiseOriginalOperator', ...
    '%d/%d groups passed: %s',nnz(passed),numel(passed),strjoin(failures(~passed),' | '));
fprintf('PN_ORIGINAL_OPERATOR_PASS groups=%d shared_RF=0 received_power=0\n',numel(checks));
ok=true;
end

function samePartition(numericClass,method)
[cfg,fs,epoch,seed]=configuration(method,0.5);
before=rng;
plain=sixgr.rf.PhaseNoiseModel(cfg,fs,seed);
captured=sixgr.rf.PhaseNoiseModel(cfg,fs,seed);
x=samples(257,3,numericClass); first=0;
for last=[1 19 127 257]
    input=x(first+1:last,:);
    expected=plain.apply(input,fs);
    [actual,trace]=captured.apply(input,fs);
    validateTrace(trace,input,actual,first,epoch, ...
        "sixgr_rf_runtime_phase_noise_process","original_executed_phase_noise_multiplier");
    assert(isequal(actual,expected), ...
        'Capturing the original operator must not change samples on the same partition.');
    first=last;
end
tail=samples(71,3,numericClass);
expected=plain.apply(tail,fs);
[actual,trace]=captured.apply(tail,fs);
validateTrace(trace,tail,actual,first,epoch, ...
    "sixgr_rf_runtime_phase_noise_process","original_executed_phase_noise_multiplier");
assert(isequal(actual,expected), ...
    'An optional receipt must not advance or reset oscillator state.');
assert(isequal(before,rng),'Canonical construction/capture must not consume global RNG.');
end

function zeroInput()
[cfg,fs,epoch,seed]=configuration("ar1_mask_fit",0.5);
before=rng;
silent=sixgr.rf.PhaseNoiseModel(cfg,fs,seed);
nonzero=sixgr.rf.PhaseNoiseModel(cfg,fs,seed);
x=complex(zeros(129,3,'single'));
[actual,trace]=silent.apply(x,fs);
[~,reference]=nonzero.apply(complex(ones(size(x),'like',x)),fs);
validateTrace(trace,x,actual,0,epoch, ...
    "sixgr_rf_runtime_phase_noise_process","original_executed_phase_noise_multiplier");
assert(isequal(actual,x)&&any(trace.Phase_rad(:)~=0) && ...
    isequal(trace.Phase_rad,reference.Phase_rad)&& ...
    isequal(trace.Multiplier,reference.Multiplier), ...
    'Enabled zero input still executes the original oscillator; never infer its multiplier from y/x.');
tail=samples(65,3,"single");
[a,ta]=silent.apply(tail,fs); [b,tb]=nonzero.apply(tail,fs);
assert(isequal(a,b)&&isequal(ta.Phase_rad,tb.Phase_rad));
validateTrace(ta,tail,a,129,epoch, ...
    "sixgr_rf_runtime_phase_noise_process","original_executed_phase_noise_multiplier");
assert(isequal(before,rng));
end

function partitionAndCorrelation()
for rho=[0 1]
    [cfg,fs,epoch,seed]=configuration("ar1_mask_fit",rho);
    before=rng;
    whole=sixgr.rf.PhaseNoiseModel(cfg,fs,seed);
    split=sixgr.rf.PhaseNoiseModel(cfg,fs,seed);
    x=samples(513,3,"double");
    [expected,allTrace]=whole.apply(x,fs);
    actual=zeros(size(x),'like',x); phase=zeros(size(x));
    multiplier=zeros(size(x),'like',x); first=0;
    for last=[1 2 31 129 513]
        [part,t]=split.apply(x(first+1:last,:),fs);
        validateTrace(t,x(first+1:last,:),part,first,epoch, ...
            "sixgr_rf_runtime_phase_noise_process","original_executed_phase_noise_multiplier");
        actual(first+1:last,:)=part; phase(first+1:last,:)=t.Phase_rad;
        multiplier(first+1:last,:)=t.Multiplier; first=last;
    end
    assert(isequal(actual,expected)&&isequal(phase,allTrace.Phase_rad) && ...
        isequal(multiplier,allTrace.Multiplier), ...
        'AR1 original trajectories must be invariant to the declared split.');
    if rho==1
        assert(isequal(phase(:,1),phase(:,2))&&isequal(phase(:,1),phase(:,3)), ...
            'The installed common LO must retain exactly common phase.');
    else
        assert(~isequal(phase(:,1),phase(:,2))&&~isequal(phase(:,1),phase(:,3)), ...
            'Independent configured oscillator streams must not be replaced by one common trace.');
    end
    tail=samples(43,3,"double");
    [a,ta]=whole.apply(tail,fs); [b,tb]=split.apply(tail,fs);
    assert(isequal(a,b)&&isequal(ta.Phase_rad,tb.Phase_rad));
    assert(isequal(before,rng));
end
end

function spectralOperator()
% Same-partition capture equality is exact even when the original FIR uses
% FFT convolution. Different FFT partitions may differ by roundoff only.
samePartition("double","spectral_fir");
samePartition("single","spectral_fir");
[cfg,fs,epoch,seed]=configuration("spectral_fir",1);
before=rng;
whole=sixgr.rf.PhaseNoiseModel(cfg,fs,seed);
split=sixgr.rf.PhaseNoiseModel(cfg,fs,seed);
x=samples(513,2,"double"); [expected,allTrace]=whole.apply(x,fs);
actual=zeros(size(x),'like',x); phase=zeros(size(x)); first=0;
for last=[7 31 201 513]
    [part,t]=split.apply(x(first+1:last,:),fs);
    validateTrace(t,x(first+1:last,:),part,first,epoch, ...
        "sixgr_rf_runtime_phase_noise_process","original_executed_phase_noise_multiplier");
    actual(first+1:last,:)=part; phase(first+1:last,:)=t.Phase_rad; first=last;
end
tolerance=128*eps('double');
assert(max(abs(actual-expected),[],'all')<=tolerance*max(1,max(abs(expected),[],'all')) && ...
    max(abs(phase-allTrace.Phase_rad),[],'all')<=tolerance*max(1,max(abs(allTrace.Phase_rad),[],'all')), ...
    'Only numerical FFT partition roundoff is allowed, not trajectory regeneration.');
assert(isequal(before,rng));
end

function disabledAndLegacy()
[cfg,fs,epoch,seed]=configuration("ar1_mask_fit",0.5);
cfg.rf.phaseNoise.enable=false; before=rng;
disabled=sixgr.rf.PhaseNoiseModel(cfg,fs,seed);
for numericClass=["double","single"]
    % An explicit reset starts a new LOCAL identity-operator counter.
    disabled.reset(seed);
    first=0;
    for count=[13 29]
        x=samples(count,2,numericClass); [actual,t]=disabled.apply(x,fs);
        validateTrace(t,x,actual,first,epoch,"disabled","disabled_identity_operator");
        assert(isequal(actual,x)&&all(t.Phase_rad(:)==0) && all(t.Multiplier(:)==1));
        first=first+count;
    end
end
assert(isequal(before,rng));
% Do not invent exact comm.PhaseNoise phase using a sample ratio. Replay
% the SAME declared legacy call with identical global starting state solely
% to check that asking for an unavailable receipt preserves its behavior.
legacy=struct(); legacy.rf.phaseNoise=struct('enable',true,'useCommBackend',true, ...
    'maskOffsets_Hz',[1e3 1e4 1e5],'maskLevels_dBcHz',[-85 -95 -110]);
legacy.rf.configurationEpoch=epoch;
x=samples(127,1,"double"); starting=rng;
plain=sixgr.rf.PhaseNoiseModel(legacy,fs,seed);
expected=plain.apply(x,fs); afterPlain=rng;
rng(starting);
captured=sixgr.rf.PhaseNoiseModel(legacy,fs,seed);
[actual,t]=captured.apply(x,fs); afterCaptured=rng;
assert(isequal(actual,expected)&&isequal(afterPlain,afterCaptured), ...
    'An unavailable legacy receipt must preserve original samples and RNG behavior.');
requiredTrace(t);
assert(~t.Available&&isempty(t.Phase_rad)&&isempty(t.Multiplier) && ...
    string(t.Backend)==captured.Backend && ...
    string(t.Scope)~="original_executed_phase_noise_multiplier" && ...
    string(t.Scope)~="disabled_identity_operator", ...
    'A legacy backend without exact retained operators must be unavailable, not a fabricated identity.');
if exist('comm.PhaseNoise','class')==8
    assert(captured.Backend=="comm_phase_noise_runtime_backend", ...
        'This installed-toolbox negative must exercise the actual comm backend.');
    fprintf('PN_ORIGINAL_OPERATOR legacy_comm_checked=1 exact_operator_available=0\n');
else
    fprintf('PN_ORIGINAL_OPERATOR legacy_comm_checked=0 legacy_backend=%s\n',captured.Backend);
end
rng(starting);
end

function validateTrace(t,x,y,first,epoch,backend,scope)
requiredTrace(t);
assert(t.Available && isequal(t.StateEpoch,epoch) && ...
    isequal(t.StartSample0,first)&&isequal(t.EndSampleExclusive,first+size(x,1)) && ...
    string(t.Backend)==backend&&string(t.Scope)==scope, ...
    'Trace identity must describe the original local oscillator interval.');
assert(isa(t.Phase_rad,'double')&&isreal(t.Phase_rad) && ...
    isequal(size(t.Phase_rad),size(x))&&all(isfinite(t.Phase_rad(:))) && ...
    strcmp(class(t.Multiplier),class(x))&&isequal(size(t.Multiplier),size(x)) && ...
    all(isfinite(t.Multiplier(:))), ...
    'Retain original phase and actual numeric-class multiplier, not a fitted scalar.');
assert(isequal(t.Multiplier,cast(exp(1j.*t.Phase_rad),'like',x)) && ...
    isequal(y,x.*t.Multiplier), ...
    'Receipt multiplier must be exactly the cast exp used by this original call.');
end

function requiredTrace(t)
assert(isstruct(t)&&isscalar(t)&&all(isfield(t, ...
    {'Available','Phase_rad','Multiplier','Backend','StateEpoch', ...
    'StartSample0','EndSampleExclusive','Scope'})) && ...
    islogical(t.Available)&&isscalar(t.Available), ...
    'The explicit optional original-operator trace contract is required.');
end

function [cfg,fs,epoch,seed]=configuration(method,rho)
fs=7.68e6; epoch=9; seed=613;
cfg=struct(); cfg.rf.specification.profile_id='rf_impaired_research';
cfg.rf.configurationEpoch=epoch; cfg.phy.fc_Hz=2.35e9;
cfg.rf.phaseNoise=struct('enable',true,'useCommBackend',false);
raw=struct('profile_id','declared_original_operator_component','version','1', ...
    'mask_offsets_hz',[1e3 1e4 1e5],'mask_levels_dbchz',[-85 -95 -110], ...
    'lo_correlation',rho,'seed',17,'synthesis_method',method, ...
    'classification','declared_component_oscillator_not_hardware_qualified');
if method=="spectral_fir"
    % Flat two-sided PSD gives a bounded exact native FIR construction;
    % this is an operator test, not spectral-mask accuracy qualification.
    raw.mask_offsets_hz=[fs/8 fs/4]; raw.mask_levels_dbchz=[-100 -100];
    raw.fir_length=64;
end
cfg.rf.frontend.phase_noise=raw;
end

function x=samples(n,columns,numericClass)
time=(0:n-1).'; phase=(1:columns)*0.17;
% Numeric class is explicit; waveform amplitude is normalized baseband.
x=cast(0.3*exp(1j*(time*0.13+phase)) + ...
    0.07*cos(time*0.07+phase),char(numericClass));
end
