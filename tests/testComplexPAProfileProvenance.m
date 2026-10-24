function [ok,evidence]=testComplexPAProfileProvenance()
% Actual public PA/retained RF callers with declared coefficient fixtures.
% No bypass to kernel-only execution if profile serialization fails. These
% bounded sample tests are not measured PA calibration or RF conformance.
setup6GRSimToolkit('Verbose',false);
savedRNG=rng;
n=(0:63).';
x=[(.13+.001*n).*exp(1i*.17*n),(.21-.001*n).*exp(-1i*.11*n)];
coefficients={ [1+.2i .1-.03i;-.08+.015i .02+.006i], ...
               [1+.2i .1+.07i;-.08+.015i .02+.006i], ...
               [1 .1;-.08 .02], zeros(2,2)};
names=["complex_A","imaginary_only_change_B","real","zero"];
assert(isequal(real(coefficients{1}),real(coefficients{2}))&& ...
    ~isequal(imag(coefficients{1}),imag(coefficients{2})));
outputs=cell(4,3); hashes=strings(4,3); checks=table();
directions=["DL","UL"];
for k=1:4
    cfg=config(coefficients{k});
    [profile,canonical]=sixgr.rf.runtime.PAProfile.fromConfiguration(cfg,'DL');
    assert(canonical&&isequal(profile.Coefficients,coefficients{k})&& ...
        isequal(size(profile.Coefficients),[2 2]));
    for caller=1:3
        label="PAProfile.apply";
        if caller>1, label="RFImpairmentStream_"+directions(caller-1); end
        passed=false; identifier=""; message="";
        try
            before=profile;
            if caller==1
                [actual,receipt]=sixgr.rf.runtime.PAProfile.apply(x,profile);
                assert(isequaln(profile,before),'test:PAProfileMutation','Do not rewrite numeric coefficients for JSON.');
                hash=string(receipt.CoefficientSHA256);
                expectedHash=profileHash(orderfields(profile));
                assert(string(receipt.CoefficientHashSerialization)== ...
                    "jsonSafeValue_orderfields_profile_UTF8/v1", ...
                    'test:PAHashSerialization','Declare the actual ordered full-profile hash serialization.');
                assert(receipt.BackoffReferencePlane=="before_pa_nonlinearity"&& ...
                    ~receipt.PowerRestorationApplied&&receipt.InputBackoff_dB==profile.InputBackoff_dB);
                if isreal(profile.Coefficients)
                    assert(hash==legacyHash(orderfields(profile)), ...
                        'test:PARealHashCompatibility','Do not change legacy real-profile hash bytes.');
                end
            else
                direction=directions(caller-1);
                [actual,hash]=streamExecution(cfg,profile,x,direction);
                expectedHash=profileHash(profile);
            end
            driven=x.*cast(10^(-profile.InputBackoff_dB/20),'like',x);
            [kernel,~]=sixgr.rf.runtime.MemoryPolynomialPA.apply( ...
                driven,profile.Coefficients,profile.Orders,[]);
            assert(isequal(actual,kernel),'test:PAActualKernel', ...
                'Actual caller output must retain the exact kernel and original input backoff.');
            oracle=sixgr.rf.runtime.oracle.MemoryPolynomialSpec.apply( ...
                driven,profile.Coefficients,profile.Orders);
            assert(isequal(size(actual),size(x))&&isa(actual,class(x))&&all(isfinite(actual(:)))&& ...
                norm(actual-oracle,'fro')<=128*eps(max(1,norm(oracle,'fro'))), ...
                'test:PAIndependentArithmetic','Retain complex memory taps and dimensions in actual output.');
            assert(hash==expectedHash&&strlength(hash)==64,'test:PAProfileHash', ...
                'The original full profile, including imaginary coefficients, must determine the retained hash.');
            if k==4
                assert(all(actual(:)==0),'test:PAZeroProfile','Zero coefficients must remain a real zero-output case.');
            else
                assert(norm(actual-x,'fro')>0,'test:PAActualOutput','Do not replace physical output with unchanged input.');
            end
            outputs{k,caller}=actual; hashes(k,caller)=hash; passed=true;
        catch cause
            identifier=string(cause.identifier); message=string(cause.message);
            fprintf('COMPLEX_PA_CALLER_FAIL case=%s caller=%s error=%s message=%s\n', ...
                names(k),label,identifier,message);
        end
        checks=[checks;table(names(k),label,passed,identifier,message, ...
            'VariableNames',{'DeclaredProfile','ActualCaller','Passed','ErrorIdentifier','ErrorMessage'})]; %#ok<AGROW>
    end
end
% Do not infer imaginary-coefficient provenance from a kernel-only check.
% These assertions use outputs and hashes returned by BOTH real callers.
for caller=1:3
    selected=caller:3:height(checks);
    if ~all(checks.Passed(selected)), continue; end
    assert(hashes(1,caller)~=hashes(2,caller)&& ...
        norm(outputs{1,caller}-outputs{2,caller},'fro')>0, ...
        'test:PAImaginaryCoefficientCollision', ...
        'Imaginary-only profile differences must affect actual output and retained provenance.');
end
assert(isequal(savedRNG,rng),'test:PAGlobalRNGMutation','Deterministic PA tests must not consume global RNG.');
evidence=struct('Scope',"actual_PA_and_retained_RF_callers_declared_coefficients", ...
    'Checks',checks,'ProfileHashes',hashes,'FullScenarioQualified',false, ...
    'CalibratedHardware',false,'StatisticalQualification',false);
disp(checks(:,{'DeclaredProfile','ActualCaller','Passed','ErrorIdentifier'}));
assert(all(checks.Passed),'test:ComplexPAProfileProvenance', ...
    '%d/%d actual-caller groups failed; retain their errors, never substitute kernel-only success.', ...
    nnz(~checks.Passed),height(checks));
ok=true;
fprintf('COMPLEX_PA_PROFILE_PROVENANCE_PASS actual_caller_groups=%d complex_imaginary_only_hashes=1 real_zero=1 hardware_qualified=0\n',height(checks));
end

function cfg=config(coefficients)
cfg=struct(); cfg.rf.specification.profile_id='rf_impaired_research';
cfg.rf.configurationEpoch=9; cfg.phy.fc_Hz=2.35e9; cfg.rf.pa.enable=true;
cfg.rf.frontend.pa=struct('profile_id','declared_complex_memory_polynomial', ...
    'version','1','input_backoff_db',2,'model','memory_polynomial', ...
    'reference_domain','waveform_samples','coefficients',coefficients, ...
    'orders',[1 3],'memory_depth',2);
% This isolated caller regression enables PA only; it does not qualify the
% composite chain's DAC/PN/oscillator or array behavior.
cfg.rf.tx.phaseNoise.enable=false; cfg.rf.rx.phaseNoise.enable=false;
end

function [actual,hash]=streamExecution(cfg,profile,x,direction)
fs=7.68e6; origin=31; epoch=9;
owner=sixgr.rf.runtime.RFImpairmentStream(cfg,'tx',direction,fs,2,origin,epoch,false);
out=owner.apply(sixgr.phy.waveform.WaveformChunk(x,origin),epoch);
actual=out.Waveform; dependency=out.Replay.TXSignalDependency;
hash=string(dependency.PAProfileSHA256);
assert(string(dependency.PAProfileHashSerialization)== ...
    "jsonSafeValue_profile_field_order_UTF8/v1", ...
    'test:PAHashSerialization','Preserve and declare the original installed-profile field order.');
assert(dependency.Available&&dependency.MemorySamples==1&&dependency.DelaySamples==0&& ...
    dependency.ConfigurationEpoch==epoch&&dependency.SampleRateHz==fs&& ...
    dependency.StartSample==origin&&dependency.EndSampleExclusive==origin+size(x,1)&& ...
    string(dependency.PAModel)=="memory_polynomial"&&dependency.AdditionalRFExecutions==0&& ...
    string(out.ExecutionStage)=="actual_retained_rf_stream"&& ...
    string(out.Replay.RFOutputWaveformSHA256)==string(sixgr.rf.waveformSHA256(actual)));
if isreal(profile.Coefficients)
    assert(hash==legacyHash(profile),'test:PARealHashCompatibility','Keep real installed-profile hash bytes.');
end
split=sixgr.rf.runtime.RFImpairmentStream(cfg,'tx',direction,fs,2,origin,epoch,false);
parts=zeros(size(x),'like',x); first=0;
for last=[1 2 13 size(x,1)]
    segment=split.apply(sixgr.phy.waveform.WaveformChunk(x(first+1:last,:),origin+first),epoch);
    assert(string(segment.Replay.TXSignalDependency.PAProfileSHA256)==hash);
    parts(first+1:last,:)=segment.Waveform; first=last;
end
assert(isequal(parts,actual),'test:PAChunkPartition','Profile hashing must not reset retained PA history.');
tail=owner.apply(sixgr.phy.waveform.WaveformChunk(complex(zeros(2,2)),origin+size(x,1)),epoch);
driven=[x;complex(zeros(2,2))].*cast(10^(-profile.InputBackoff_dB/20),'like',x);
[full,~]=sixgr.rf.runtime.MemoryPolynomialPA.apply(driven,profile.Coefficients,profile.Orders,[]);
assert(isequal(tail.Waveform,full(end-1:end,:)),'test:PAMemoryTail','Retain original complex memory through zero input.');
end

function hash=profileHash(profile)
hash=string(sixgr.util.sha256Hex(uint8(unicode2native( ...
    jsonencode(sixgr.util.jsonSafeValue(profile)),'UTF-8'))));
end

function hash=legacyHash(profile)
hash=string(sixgr.util.sha256Hex(uint8(unicode2native(jsonencode(profile),'UTF-8'))));
end
