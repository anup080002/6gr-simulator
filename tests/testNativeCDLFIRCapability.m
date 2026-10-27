function ok=testNativeCDLFIRCapability()
% Installed native capability, not R2024a qualification on another runtime.
setup6GRSimToolkit('Verbose',false);
cfg=sixgr.config.defaultConfig(); fs=7.68e6;
cfg.channel.model='CDL-C'; cfg.channel.cdlProfile='CDL-C';
cfg.channel.delayProfile='CDL-C'; cfg.channel.fading.model='CDL';
cfg.channel.fading.profile='CDL-C'; cfg.channel.awgnOnly=false;
cfg.channel.delaySpread_s=100e-9; cfg.channel.doppler_Hz=37;
cfg.channel.channelFiltering=true; cfg.channel.perSampleFadingEnabled=true;
cfg.channel.normalizePathGains=false; cfg.channel.normalizeChannelOutputs=false;
cfg.phy.fc_Hz=2.35e9;
native=sixgr.channel.ChannelFactory.create(sixgr.channel.bindRuntimeDoppler(cfg), ...
    'Model','CDL','SampleRate',fs,'NumTxAnt',4,'NumRxAnt',2,'Seed',65537,'LinkDirection','DL');
channel=native.Object; originalRNG=rng;
receipt=sixgr.channel.initializeFreshCDLReciprocalFilters(channel,complex(zeros(256,4)));
assert(receipt.ContractVersion=="sixgr.channel.FreshCDLReciprocalFilters/v2");
c=receipt.NativeCapability;
assert(sixgr.channel.nativeCDLFIRCapabilityValid(c)&&isequal(rng,originalRNG));
baseline=clone(channel);
second=sixgr.channel.probeNativeCDLFIRSemantics(channel,complex(zeros(256,4)));
assert(sixgr.channel.nativeCDLFIRCapabilityValid(second));
x=.01*exp(1i*((0:32).'*(1:4)/19));
[a,ag,at]=sixgr.channel.applyWaveformChannelOnce(channel,x,true);
[b,bg,bt]=sixgr.channel.applyWaveformChannelOnce(baseline,x,true);
assert(isequal(a,b)&&isequal(ag,bg)&&isequal(at,bt)&&isequal(rng,originalRNG), ...
    'test:CapabilityChangedOriginal','Capability probe advanced the original channel or RNG.');
mutations={'Passed',false;'Passed',1;'RuntimeMATLABRelease',"foreign_runtime"; ...
    'RuntimeMATLABVersion',"foreign_build"; ...
    'RuntimeToolboxVersion',"foreign_version";'OriginalPhysicalSamplesAdvanced',1; ...
    'OriginalOwnerChannelExecutions',1;'ProbeChannelExecutions',8; ...
    'ExactCloneContinuation',false;'ExactSaveLoadContinuation',false; ...
    'SampleDensity',64;'MeasurementOrAccuracyQualification',true};
for k=1:size(mutations,1)
    bad=c; bad.(mutations{k,1})=mutations{k,2};
    assert(~sixgr.channel.nativeCDLFIRCapabilityValid(bad));
end
bad=c;bad.Checks{3}.Swapped=~bad.Checks{3}.Swapped;
assert(~sixgr.channel.nativeCDLFIRCapabilityValid(bad));
bad=c;bad.Checks{1}.RelativeError=2*bad.Checks{1}.RelativeRoundoffBound;
assert(~sixgr.channel.nativeCDLFIRCapabilityValid(bad));
bad=c;bad.Checks{1}.FilterSHA256="missing";
assert(~sixgr.channel.nativeCDLFIRCapabilityValid(bad));
d=struct('NativeFilterAuthority',"public_CDL_Inf_capability_verified_original_filters", ...
    'NativeCapability',c,'NativeCapabilitySHA256',receipt.NativeCapabilitySHA256,'SampleRateHz',fs);
assert(sixgr.channel.isNativeCDLReferenceDependency(d));
bad=d;bad.NativeCapabilitySHA256=repmat('0',1,64);
assert(~sixgr.channel.isNativeCDLReferenceDependency(bad));
bad=d;bad.SampleRateHz=fs*2;assert(~sixgr.channel.isNativeCDLReferenceDependency(bad));
legacy=struct('NativeFilterAuthority',"R2026a_Inf_fresh_both_direction_public_getPathFilters");
assert(sixgr.channel.isNativeCDLReferenceDependency(legacy)==strcmp(version('-release'),'2026a'));
for model=["CDL","TDL"]
    if model=="CDL", q=nrCDLChannel; else, q=nrTDLChannel; end
    contract=sixgr.channel.waveformChannelOutputContract(q);
    assert(contract.OutputCount==3&&~isLocked(q));
    q.ChannelFiltering=false;
    rejected=false;
    try,sixgr.channel.waveformChannelOutputContract(q);
    catch e,rejected=strcmp(e.identifier,'sixgr:channel:WaveformFilteringDisabled');end
    assert(rejected&&~isLocked(q));
end
fprintf('PASS testNativeCDLFIRCapability: actual probe, unchanged original continuation, tamper/foreign-runtime/output-contract guards.\n');
ok=true;
end
