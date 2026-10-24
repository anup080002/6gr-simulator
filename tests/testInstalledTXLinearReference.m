function ok=testInstalledTXLinearReference()
% Exact original-owner joins on real bounded RF calls, not received RSRP.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
cfg=struct(); cfg.run.seed=913; cfg.phy.fc_Hz=2.35e9;
cfg.rf.specification.profile_id='rf_impaired_research';
cfg.rf.txLinearReference=struct('Enabled',true,'Model','fixed_first_order_pa_identity_dac', ...
    'Classification','optional_research_experiment','RequirementClass','IMPLEMENTATION_POLICY');
cfg.rf.pa.enable=true;
cfg.rf.frontend.pa=struct('profile_id','bounded_installed_reference','version','1', ...
    'input_backoff_db',2,'model','memory_polynomial','reference_domain','waveform_samples', ...
    'coefficients',[1+.2i .1-.03i;-.08+.015i .02+.006i],'orders',[1 3],'memory_depth',2);
cfg.rf.frontend.dac=struct('enabled',true,'profile_id','bounded_installed_dac','version','1', ...
    'bits',12,'full_scale',.8,'convention','signed_midtread','reference_domain','waveform_samples', ...
    'dither_enabled',false,'dither_rms',0,'aperture_jitter_seconds',0);
cfg.rf.tx.cfo_Hz=730; cfg.rf.tx.timingOffsetSamples=3;
fs=7.68e6; origin=31; epoch=9; nAnt=2;
owner=sixgr.rf.runtime.RFImpairmentStream(cfg,'tx','DL',fs,nAnt,origin,epoch,false);
other=sixgr.rf.runtime.RFImpairmentStream(cfg,'tx','DL',fs,nAnt,origin,epoch,false);
installed=sixgr.rf.InstalledTXLinearReference.freeze(owner,"gnb",cfg.rf.txLinearReference);
registration=installed.capsule();
sixgr.rf.InstalledTXLinearReference.validateRegistration(registration);
bad=registration; bad.NumAntennas=3;
reject(@()sixgr.rf.InstalledTXLinearReference.validateRegistration(bad),'RF:TXLinearReferenceRegistration');
bad=cfg; bad.rf.txLinearReference.Enabled=false;
reject(@()installed.validatePolicy(bad),'RF:TXLinearReferenceInstallationChanged');
bad=cfg; bad.rf.txLinearReference.Model='undeclared';
reject(@()sixgr.rf.InstalledTXLinearReference.resolvePolicy(bad),'RF:TXLinearReferencePolicy');
assert(isempty(sixgr.rf.InstalledTXLinearReference.resolvePolicy(struct())));
bad=cfg; bad.rf.txLinearReference=[];
reject(@()sixgr.rf.InstalledTXLinearReference.resolvePolicy(bad),'RF:TXLinearReferencePolicy');
x=.3*exp(1i*((0:136).'*[.13 .17])); x(118:end,:)=0;
before=rng; first=0;
for stop=[17 83 137]
    chunk=sixgr.phy.waveform.WaveformChunk(x(first+1:stop,:),origin+first);
    reject(@()installed.apply(other,"gnb",chunk,epoch),'RF:TXLinearReferenceOriginalOwner');
    reject(@()installed.apply(owner,"other",chunk,epoch),'RF:TXLinearReferenceOriginalOwner');
    reject(@()installed.apply(owner,"gnb",chunk,epoch+1),'RF:TXLinearReferenceOriginalOwner');
    assert(owner.NextSampleIndex==origin+first&&other.NextSampleIndex==origin+first);
    stale=installed;
    [installed,actual,r]=installed.apply(owner,"gnb",chunk,epoch);
    plain=other.apply(chunk,epoch);
    assert(isequaln(actual.Waveform,plain.Waveform)&&isequaln(actual.Replay,plain.Replay)&& ...
        isequaln(actual.Row,plain.Row),'Recording must not change original RF samples or replay.');
    reject(@()stale.apply(owner,"gnb",chunk,epoch),'RF:TXLinearReferenceOriginalOwner');
    assert(r.OriginalOwnerBindingVerified&&~r.ReceiverEstimatorInput&& ...
        r.AdditionalRFExecutions==0&&r.AdditionalChannelExecutions==0&& ...
        r.RegistrationSHA256==registration.RegistrationSHA256&& ...
        ~r.Adapter.OriginalOwnerVerified&&~r.Adapter.StandardizedPowerAccuracyQualified&& ...
        ~r.Adapter.ActualNonlinearPortAttribution&&r.Adapter.ResidualEnergy>0&& ...
        r.Adapter.PowerClosureRelativeError<1e-10);
    assert(isequaln(installed.capsule(),registration),'Registration must remain immutable.');
    first=stop;
end
assert(isequal(rng,before)&&owner.NextSampleIndex==origin+137&&other.NextSampleIndex==origin+137);
reject(@()sixgr.rf.InstalledTXLinearReference.freeze(owner,"late",cfg.rf.txLinearReference), ...
    'RF:TXLinearReferenceInstallation');
fprintf('INSTALLED_TX_LINEAR_REFERENCE_PASS intervals=3 owner_hash_clock_policy_negatives=1 received_power_qualified=0\n');
ok=true;
end
function reject(fn,id)
try, fn(); catch cause
    assert(string(cause.identifier)==id,'test:UnexpectedTXReferenceError', ...
        'Expected %s, got %s: %s',id,cause.identifier,cause.message); return;
end
error('test:MissingTXReferenceError','Expected %s.',id);
end
