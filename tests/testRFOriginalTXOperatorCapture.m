function ok=testRFOriginalTXOperatorCapture()
% Actual retained RF execution, not a CSI/channel/standardized power test.
% Capturing original operands must be observational: identical samples,
% subsequent state evolution, clocks and global RNG on the same partition.
setup6GRSimToolkit('Verbose',false);
saved=rng; cleanup=onCleanup(@()rng(saved)); %#ok<NASGU>
names=["full_DL_double","full_UL_single","disabled","silent_original_PN", ...
    "unsupported_and_preflight","no_retained_large_operator","actual_capture_to_fixed_reference", ...
    "rapp_capture_bridge","saleh_carrier_phase_capture_bridge"];
checks={@()equivalence("DL","double",false,false,257), ...
    @()equivalence("UL","single",false,false,257), ...
    @()equivalence("DL","double",true,false,127), ...
    @()equivalence("UL","double",false,true,129), ...
    @negatives,@()equivalence("DL","double",false,false,4097),@modelBridge, ...
    @()additionalPA("rapp",false),@()additionalPA("saleh",true)};
passed=false(size(checks)); failures=strings(size(checks));
for k=1:numel(checks)
    try
        before=rng; checks{k}(); assert(isequal(before,rng),'No global RNG mutation.');
        passed(k)=true; fprintf('RF_ORIGINAL_TX_CAPTURE %s PASS\n',names(k));
    catch cause
        failures(k)=string(cause.identifier)+": "+string(cause.message);
        fprintf('RF_ORIGINAL_TX_CAPTURE %s FAIL %s\n',names(k),failures(k));
    end
end
assert(all(passed),'test:RFOriginalTXOperatorCapture','%d/%d groups passed: %s', ...
    nnz(passed),numel(passed),strjoin(failures(~passed),' | '));
fprintf('RF_ORIGINAL_TX_CAPTURE_PASS groups=%d actual_RF=1 original_operator=1 shared_owner=0 received_power=0\n',numel(checks));
ok=true;
end

function equivalence(direction,numericClass,disabled,silent,count,model,carrierPhase)
if nargin<6, model="memory_polynomial"; end
if nargin<7, carrierPhase=false; end
[cfg,fs,origin,epoch]=configuration(disabled,model,carrierPhase);
plain=sixgr.rf.runtime.RFImpairmentStream(cfg,'tx',direction,fs,3,origin,epoch,carrierPhase);
captured=sixgr.rf.runtime.RFImpairmentStream(cfg,'tx',direction,fs,3,origin,epoch,carrierPhase);
x=samples(count,3,numericClass);
if silent, x(:)=0; end
first=0;
for last=unique([1 17 count])
    input=x(first+1:last,:); chunk=sixgr.phy.waveform.WaveformChunk(input,origin+first);
    expected=plain.apply(chunk,epoch); [actual,record]=captured.apply(chunk,epoch);
    assert(isequal(actual.Waveform,expected.Waveform) && ...
        isequaln(actual.Replay,expected.Replay) && isequaln(actual.StageTrace,expected.StageTrace), ...
        'test:RFCaptureMutation','Optional capture changed actual samples or compact execution evidence.');
    validate(record,chunk,actual,origin,epoch,fs,direction);
    assert(record.Stages.CarrierPhase.Enabled==carrierPhase);
    if ~disabled
        enabled=[record.Stages.DAC.Enabled record.Stages.IQ.Enabled record.Stages.Element.Enabled ...
            record.Stages.PA.Enabled record.Stages.PhaseNoise.Enabled record.Stages.CFO.Enabled record.Stages.Timing.Enabled];
        assert(all(enabled),'test:RFCaptureScope','The full test must really execute every configured stage.');
        phase=record.Stages.PhaseNoise.Parameters.Trace;
        assert(phase.Available && phase.StartSample0==first && ...
            phase.EndSampleExclusive==last && isequal(size(phase.Multiplier),size(input)) && ...
            string(phase.Backend)=="sixgr_rf_runtime_phase_noise_process");
        if silent
            assert(record.Stages.PhaseNoise.Executed && any(phase.Phase_rad(:)~=0) && ...
                all(actual.Waveform(:)==0), ...
                'test:RFSilentOperator','Zero samples must not suppress the original oscillator execution.');
        end
        expectedCFO=cast(exp(1j*2*pi*cfg.rf.tx.cfo_Hz/fs* ...
            (origin+first+(0:size(input,1)-1)).'),'like',input);
        assert(isequal(record.Stages.CFO.Parameters.Multiplier,expectedCFO));
        [profile,canonical]=sixgr.rf.runtime.PAProfile.fromConfiguration(cfg,direction);
        assert(canonical && isequaln(record.Stages.PA.Parameters.Profile,profile), ...
            'Original PA parameters must include imaginary coefficients and backoff.');
        assert(record.Stages.Element.Parameters.PhysicalInputAlreadyMapped && ...
            isequal(record.Stages.Element.Parameters.Coupling,cfg.rf.tx.element.mutualCoupling.matrix));
        assert(record.Stages.DAC.Parameters.Profile.FullScale==.8 && ...
            record.Stages.DAC.Parameters.Profile.DitherRMS==0 && ...
            record.Stages.Timing.Parameters.DelaySamples==3);
    else
        for name=string(fieldnames(record.Stages)).'
            assert(~record.Stages.(name).Enabled);
        end
        assert(isequal(actual.Waveform,input));
    end
    noLargeOperators(actual.Replay); noLargeOperators(actual.Row);
    % Serialized owner size detects accidental interval-array retention;
    % exact future output below checks behavior, not binary MAT identity.
    a=getByteStreamFromArray(plain); b=getByteStreamFromArray(captured);
    assert(numel(a)==numel(b),'test:RFCaptureRetainedArrays', ...
        'Optional capture must not retain extra interval operators in RF state.');
    assert(captured.NextSampleIndex==origin+last && ~captured.Faulted);
    first=last;
end
% Disable capture on the following call: no stale receipt or PN/PA/delay
% state may leak from the previously captured intervals.
tail=samples(43,3,numericClass);
chunk=sixgr.phy.waveform.WaveformChunk(tail,origin+count);
a=plain.apply(chunk,epoch); b=captured.apply(chunk,epoch);
assert(isequal(a.Waveform,b.Waveform)&&isequaln(a.Replay,b.Replay) && ...
    plain.NextSampleIndex==captured.NextSampleIndex && ~captured.Faulted, ...
    'test:RFCaptureFutureState','Capture advanced/reset the retained RF state.');
end

function additionalPA(model,carrierPhase)
equivalence("DL","double",false,false,129,model,carrierPhase);
modelBridge(model,carrierPhase);
end

function modelBridge(modelName,carrierPhase)
% Test-declared registration connects the real RF receipt to the reference
% adapter. This is NOT a production shared-owner/CSI isolation claim.
if nargin<1, modelName="memory_polynomial"; end
if nargin<2, carrierPhase=false; end
[cfg,fs,origin,epoch]=configuration(false,modelName,carrierPhase);
owner=sixgr.rf.runtime.RFImpairmentStream(cfg,'tx','DL',fs,3,origin,epoch,carrierPhase);
binding=struct('EndpointID',"declared_test_tx",'Direction',"DL", ...
    'ReferenceID',"declared_fixed_linear_aggregate",'Role',"aggregate", ...
    'ConfigurationEpoch',epoch,'SampleRateHz',fs,'NumAntennas',3,'NumericClass',"double", ...
    'WaveformAmplitudeUnit',"normalized_complex_baseband",'OriginSample',origin, ...
    'HistoryInitialization',"declared_zero_model_state");
model=sixgr.rf.runtime.AppliedTXLinearReferenceStream(binding);
registration=string(sixgr.util.sha256Hex('declared_test_registration_not_original_owner_proof'));
x=samples(137,3,"double"); x(118:end,:)=0; first=0;
for last=[17 83 137]
    input=x(first+1:last,:);
    chunk=sixgr.phy.waveform.WaveformChunk(input,origin+first);
    [out,capture]=owner.apply(chunk,epoch);
    validate(capture,chunk,out,origin,epoch,fs,"DL");
    interval=capture;
    interval.ContractVersion="sixgr.rf.supplied_TX_operator_interval/v1";
    interval.EndpointID=binding.EndpointID;
    interval.WaveformAmplitudeUnit=binding.WaveformAmplitudeUnit;
    interval.InstallationSHA256=registration;
    % Explicit model policy, not a parameter invented by the original RF.
    interval.Stages.DAC.Parameters.ReferenceModel="identity_converter_reference";
    [model,reference,receipt]=model.advance(input,input,out.Waveform,interval);
    residual=double(out.Waveform)-double(reference);
    expected=sum(abs(double(out.Waveform(:))).^2);
    closure=sum(abs(double(reference(:))).^2)+sum(abs(residual(:)).^2)+ ...
        2*real(sum(conj(double(reference(:))).*residual(:)));
    assert(abs(expected-closure)<=128*eps(max(1,expected)) && ...
        receipt.PowerClosureRelativeError<1e-12 && receipt.ResidualAvailable && ...
        receipt.ResidualEnergy>0 && receipt.AdditionalRFExecutions==0 && ...
        receipt.AdditionalChannelExecutions==0 && ~receipt.OriginalOwnerVerified && ...
        ~receipt.SharedRuntimeIntegrationQualified && ~receipt.ActualNonlinearPortAttribution && ...
        ~receipt.StandardizedPowerAccuracyQualified && ~receipt.HardwareQualified && ...
        owner.NextSampleIndex==origin+last && model.NextSampleIndex==origin+last, ...
        'test:RFActualReferenceBridge','Retain residual/cross energy without claiming original shared ownership.');
    first=last;
end
end

function validate(r,chunk,out,origin,epoch,fs,direction)
assert(string(r.ContractVersion)=="sixgr.rf.OriginalTXOperatorCapture/v1" && r.Available && ...
    string(r.Source)=="same_execution_retained_TX_RF_stage_operands" && ...
    string(r.Endpoint)=="tx" && string(r.Direction)==direction && ...
    r.ConfigurationEpoch==epoch && r.SampleRateHz==fs && r.NumAntennas==size(chunk.Samples,2) && ...
    string(r.NumericClass)==string(class(chunk.Samples)) && r.OriginSample==origin && ...
    r.StartSample==chunk.StartSample && r.EndSampleExclusive==chunk.EndSample+1 && ...
    ~r.ReferenceModelApplied && ~r.SharedRuntimeOwnerBound && r.AdditionalRFExecutions==0);
assert(string(r.OriginalInputChunkSHA256)==chunk.SHA256 && ...
    string(r.OriginalOutputChunkSHA256)==out.Chunk.SHA256 && ...
    string(r.RFInputWaveformSHA256)==string(sixgr.rf.waveformSHA256(chunk.Samples)) && ...
    string(r.RFOutputWaveformSHA256)==string(sixgr.rf.waveformSHA256(out.Waveform)));
keys=["DAC","IQ","Element","PA","PhaseNoise","CFO","Timing","SampleClockOffset","CarrierPhase"];
assert(isequal(sort(string(fieldnames(r.Stages))),sort(keys.')));
previous=string(r.RFInputWaveformSHA256);
for name=keys
    s=r.Stages.(name);
    assert(islogical(s.Enabled)&&isscalar(s.Enabled)&&islogical(s.Executed)&& ...
        isscalar(s.Executed)&&s.Enabled==s.Executed);
    if s.Enabled
        assert(string(s.InputSHA256)==previous && strlength(string(s.OutputSHA256))==64 && ...
            ~isempty(fieldnames(s.Parameters)),'test:RFStageHashChain','Original stage hash chain is broken.');
        previous=string(s.OutputSHA256);
    else
        assert(string(s.InputSHA256)=="disabled_identity" && ...
            string(s.OutputSHA256)=="disabled_identity" && isempty(fieldnames(s.Parameters)));
    end
end
assert(previous==string(r.RFOutputWaveformSHA256));
assert(strjoin(string(r.StageOrder(:)),">")==string(out.Replay.RFStageOrder));
assert(~r.Stages.SampleClockOffset.Enabled);
if r.Stages.CarrierPhase.Enabled
    assert(isscalar(r.Stages.CarrierPhase.Parameters.Multiplier) && ...
        abs(r.Stages.CarrierPhase.Parameters.Multiplier-exp(1j*13*pi/180))<1e-15);
end
end

function negatives()
[cfg,fs,origin,epoch]=configuration(true);
x=samples(19,3,"double"); chunk=sixgr.phy.waveform.WaveformChunk(x,origin);
reject(@()captureBlock(x,cfg,fs,'tx',false),'RF:TXOperatorCaptureUnsupported');
reject(@()captureBlock([],cfg,fs,'tx',true),'RF:TXOperatorCaptureUnsupported');
reject(@()captureBlock(x,cfg,fs,'txrx',false),'RF:TXOperatorCaptureUnsupported');
rx=sixgr.rf.runtime.RFImpairmentStream(cfg,'rx','UL',fs,3,origin,epoch,false);
reject(@()capture(rx,chunk,epoch),'RF:TXOperatorCaptureUnsupported');
assert(rx.NextSampleIndex==origin && ~rx.Faulted);
actual=rx.apply(chunk,epoch); assert(isequal(actual.Waveform,x));
tx=sixgr.rf.runtime.RFImpairmentStream(cfg,'tx','DL',fs,3,origin,epoch,false);
reject(@()capture(tx,chunk,epoch+1),'RF:StateEpochMismatch');
wrong=sixgr.phy.waveform.WaveformChunk(x,origin+1);
reject(@()capture(tx,wrong,epoch),'RF:StreamClockDiscontinuity');
assert(tx.NextSampleIndex==origin && ~tx.Faulted);
[out,r]=tx.apply(chunk,epoch); validate(r,chunk,out,origin,epoch,fs,"DL");
bad=cfg; bad.rf.tx.timingOffsetSamples=.5;
reject(@()sixgr.rf.runtime.RFImpairmentStream(bad,'tx','DL',fs,3,origin,epoch,false), ...
    'RF:StreamingFractionalTimingRequiresClockBridge');
bad=cfg; bad.rf.tx.sampleClockOffset.ppm=20;
reject(@()sixgr.rf.runtime.RFImpairmentStream(bad,'tx','DL',fs,3,origin,epoch,false), ...
    'RF:StreamingSampleClockRequiresClockBridge');
[bad,~,~,~]=configuration(false); bad.rf.frontend.dac.dither_enabled=true;
bad.rf.frontend.dac.dither_rms=1e-5;
reject(@()sixgr.rf.runtime.RFImpairmentStream(bad,'tx','DL',fs,3,origin,epoch,false), ...
    'RF:StreamingDACRandomStateRequired');
bad=cfg; bad.rf.tx.phaseNoise.enable=true;
bad.rf.phaseNoise=struct('enable',true,'useCommBackend',true, ...
    'maskOffsets_Hz',[1e3 1e4 1e5],'maskLevels_dBcHz',[-85 -95 -110]);
% Canonical ownership requires the explicit canonical mask even when legacy
% mask fields are present. This guard precedes retained-stream validation.
reject(@()sixgr.rf.runtime.RFImpairmentStream(bad,'tx','DL',fs,3,origin,epoch,false), ...
    'RF:PhaseNoiseMaskMissing');
% Separately exercise the retained-stream rejection of a genuinely legacy
% backend, without depending on optional comm.PhaseNoise availability.
bad.rf.specification.profile_id='';
bad.rf.phaseNoise.useCommBackend=false;
reject(@()sixgr.rf.runtime.RFImpairmentStream(bad,'tx','DL',fs,3,origin,epoch,false), ...
    'RF:StreamingPhaseNoiseProfileRequired');
end

function capture(owner,chunk,epoch)
[~,receipt]=owner.apply(chunk,epoch); %#ok<NASGU>
end
function captureBlock(x,cfg,fs,endpoint,resolveOnly)
[~,receipt]=sixgr.rf.applyRFImpairmentChain(x,cfg, ...
    'SampleRateHz',fs,'Endpoint',endpoint,'Direction','DL', ...
    'UseLegacyGlobalConfig',false,'ResolveOnly',resolveOnly); %#ok<NASGU>
end
function reject(fn,id)
try, fn(); catch cause
    assert(string(cause.identifier)==id,'test:RFUnexpectedError', ...
        'Expected %s, got %s: %s',id,cause.identifier,cause.message); return;
end
error('test:RFMissingError','Expected %s.',id);
end
function noLargeOperators(value)
if istable(value), value=table2struct(value); end
if isstruct(value)
    for k=1:numel(value)
        for name=string(fieldnames(value(k))).'
            assert(~any(name==["Phase_rad","Multiplier","OriginalTXOperatorCapture"]), ...
                'test:RFHeavyReplay','Large original operators must not enter compact replay/row.');
            noLargeOperators(value(k).(name));
        end
    end
elseif iscell(value)
    for k=1:numel(value), noLargeOperators(value{k}); end
end
end
function [cfg,fs,origin,epoch]=configuration(disabled,model,carrierPhase)
if nargin<2, model="memory_polynomial"; end
if nargin<3, carrierPhase=false; end
fs=7.68e6; origin=31; epoch=9;
cfg=struct(); cfg.run.seed=613; cfg.phy.fc_Hz=2.35e9;
cfg.rf.specification.profile_id='rf_impaired_research'; cfg.rf.configurationEpoch=epoch;
cfg.rf.tx.phaseNoise.enable=~disabled; cfg.rf.rx.phaseNoise.enable=false;
cfg.rf.pa.enable=~disabled;
if disabled, return; end
cfg.rf.frontend.pa=struct('profile_id','declared_capture_memory_polynomial','version','1', ...
    'input_backoff_db',2,'model','memory_polynomial','reference_domain','waveform_samples', ...
    'coefficients',[1+.2i .1-.03i;-.08+.015i .02+.006i],'orders',[1 3],'memory_depth',2);
if model~="memory_polynomial"
    cfg.rf.frontend.pa=struct('profile_id',"declared_capture_"+model,'version','1', ...
        'input_backoff_db',2,'model',model,'reference_domain','waveform_samples');
    if model=="rapp"
        cfg.rf.frontend.pa.smoothness=2; cfg.rf.frontend.pa.saturation_amplitude=.35;
    elseif model=="saleh"
        cfg.rf.frontend.pa.alpha_am=1.2; cfg.rf.frontend.pa.beta_am=1.1;
        cfg.rf.frontend.pa.alpha_pm=.5; cfg.rf.frontend.pa.beta_pm=.8;
    else
        error('test:UnknownCapturePA','Unknown declared test PA.');
    end
end
if carrierPhase, cfg.rf.carrierPhaseOffset_deg=13; end
cfg.rf.frontend.dac=struct('enabled',true,'profile_id','declared_capture_dac','version','1', ...
    'bits',12,'full_scale',.8,'convention','signed_midtread','reference_domain','waveform_samples', ...
    'dither_enabled',false,'dither_rms',0,'aperture_jitter_seconds',0);
cfg.rf.tx.iqImbalance=struct('enable',true,'gainImbalance_dB',.3,'phaseImbalance_deg',2);
cfg.rf.tx.element=struct('enable',true,'gain_dB',[.1 -.2 .15],'phase_deg',[2 -1 3], ...
    'mutualCoupling',struct('enable',true,'matrix',[1 .03i 0;.02 1 -.01i;0 .04 1]));
cfg.rf.tx.cfo_Hz=730; cfg.rf.tx.timingOffsetSamples=3;
cfg.rf.phaseNoise=struct('enable',true,'useCommBackend',false);
cfg.rf.frontend.phase_noise=struct('profile_id','declared_original_operator_component','version','1', ...
    'mask_offsets_hz',[1e3 1e4 1e5],'mask_levels_dbchz',[-85 -95 -110], ...
    'lo_correlation',.5,'seed',17,'synthesis_method','ar1_mask_fit', ...
    'classification','declared_component_oscillator_not_hardware_qualified');
end
function x=samples(n,columns,numericClass)
t=(0:n-1).'; phase=(1:columns)*.17;
x=cast(.3*exp(1j*(t*.13+phase))+.07*cos(t*.07+phase),char(numericClass));
end
