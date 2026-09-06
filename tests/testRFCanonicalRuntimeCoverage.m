function tests=testRFCanonicalRuntimeCoverage
%TESTRFCANONICALRUNTIMECOVERAGE Exercise every canonical Phase-11 component.
tests=functiontests(localfunctions);
end

function testCanonicalCatalogComplete(t)
testPath=mfilename("fullpath");
repoRoot=fileparts(fileparts(testPath));
root=fullfile(repoRoot,"+sixgr","+rf","+runtime");
required=["RFSpecificationProfile","RFCapabilityProfile","RFPlanningResult", ...
    "RFChainConfiguration","RFReferencePlane","RFStateTrace","RFStageLedger", ...
    "AbsolutePowerLedger","OFDMScalingLedger","NoisePowerLedger", ...
    "OscillatorState","CFOState","CFOAcquisitionEngine","CFOTrackingLoop", ...
    "TimingAcquisitionEngine","TimingTrackingLoop","SampleClockState", ...
    "StatefulSampleRateOffsetResampler","PhaseNoiseProfile", ...
    "PhaseNoiseProcess","PhaseNoiseCorrelationState","IQImbalanceProfile", ...
    "IQImbalanceEstimator","IQImbalanceCompensator","DCOffsetAndLOLeakage", ...
    "DACModel","ReconstructionFilter","PAProfile","MemoryPolynomialPA", ...
    "GeneralizedMemoryPolynomialPA","DPDProfile","DPDTrainer", ...
    "CrestFactorReduction","LNAProfile","MixerProfile","RFSelectivityFilter", ...
    "AGCState","ADCModel","AntiAliasFilter","BlockerScenario", ...
    "IntermodulationScenario","ReceiverFrontEnd","TransmitterFrontEnd", ...
    "UplinkPowerControlState","PUSCHPowerController","PUCCHPowerController", ...
    "SRSPowerController","PRACHPowerController","EVMMeasurement", ...
    "ACLRMeasurement","SpectrumEmissionMeasurement", ...
    "InBandEmissionMeasurement","FrequencyErrorMeasurement", ...
    "TimeAlignmentMeasurement","RFArtifactExporter", ...
    "runRFFrontEndPhaseValidation","runRFFrontEndImpactAnalysis"];
for k=1:numel(required)
    verifyTrue(t,isfile(fullfile(root,required(k)+".m")), ...
        "Missing canonical RF runtime: "+required(k));
end
oracleRoot=fullfile(root,"+oracle");
oracles=["CFOAnalyticalSpec","FractionalDelaySpec","ResamplingSpec", ...
    "IQWidelyLinearSpec","PhaseNoisePSDOracle","RappSalehSpec", ...
    "MemoryPolynomialSpec","QuantizerSpec","FriisNoiseFigureSpec", ...
    "PowerControlSpec","EVMReferenceSpec","ACLRFilterSpec"];
for k=1:numel(oracles)
    verifyTrue(t,isfile(fullfile(oracleRoot,oracles(k)+".m")), ...
        "Missing independent RF oracle: "+oracles(k));
end
end

function testPlanningStateAndLedger(t)
profile=sixgr.rf.runtime.RFSpecificationProfile.resolve("rf_impaired_research");
plan=sixgr.rf.runtime.RFPlanningResult.executable(profile,struct("Epoch",7));
verifyEqual(t,plan.Status,"EXECUTE");
x=complex((1:8).',(8:-1:1).');
h1=sixgr.rf.runtime.RFStateTrace.sampleHash(x);
h2=sixgr.rf.runtime.RFStateTrace.sampleHash(2*x);
trace=sixgr.rf.runtime.RFStateTrace.record("gain","state-1",7, ...
    0,8,h1,h2,struct("Gain_dB",6.020599913279624));
verifyEqual(t,trace.SampleEnd,8);
ledger=sixgr.rf.runtime.RFStageLedger(7);
row=struct("Stage","gain","InputReferencePlane","DAC_INPUT", ...
    "OutputReferencePlane","DAC_OUTPUT","InputSHA256",h1, ...
    "OutputSHA256",h2,"StateID","state-1","StateEpoch",7, ...
    "AppliedParameters",struct("Gain_dB",6.020599913279624));
ledger.append(row);
verifyEqual(t,height(ledger.asTable()),1);
emulation=sixgr.rf.runtime.RFSpecificationProfile.resolve( ...
    "rf_conformance_emulation_ue_fr1");
verifyEqual(t,emulation.TableRegistryID,"UE_FR1_CONDUCTED_V19_4");
verifyEqual(t,emulation.SpecificationBaseline.TS_38_521_1,"V19.4.0");
verifyError(t,@()sixgr.rf.runtime.RFSpecificationTableRegistry. ...
    requireEnabled("BS_FR2_RADIATED_PENDING"), ...
    "RF:SpecificationTableUnavailable");
end

function testOFDMScalingAndCFOState(t)
rng(1); waveform=randn(64,1)+1j*randn(64,1);
grid=fft(waveform);
result=sixgr.rf.runtime.OFDMScalingLedger.reconcile( ...
    grid,waveform,64,16);
verifyLessThan(t,result.ParsevalResidual,1e-10);
state=sixgr.rf.runtime.CFOState(1e6,3);
state.update(1000,"estimated_cp",3);
n=(0:127).';
impaired=exp(1j*2*pi*1000*n/1e6);
[corrected,trace]=state.correct(impaired,3);
verifyLessThan(t,max(abs(corrected-1)),1e-12);
verifyEqual(t,trace.SampleIndex,128);
end

function testTimingAndSampleClockState(t)
loop=sixgr.rf.runtime.TimingTrackingLoop(0.5,0.05,4);
for slot=1:20
    trace=loop.update(2,slot,4);
end
verifyLessThan(t,abs(trace.Residual_samples),0.1);
clock=sixgr.rf.runtime.SampleClockState(30.72e6,25,0.25,4);
clockTrace=clock.advance(307200,4);
verifyEqual(t,clockTrace.CumulativeDrift_samples,7.68,"AbsTol",1e-12);
verifyGreaterThan(t,clockTrace.LastTimestamp_s,0);
end

function testPhaseNoiseCorrelationAndOracle(t)
state=sixgr.rf.runtime.PhaseNoiseCorrelationState.factor(4,0.5);
verifyEqual(t,diag(state.Covariance),ones(4,1));
levels=sixgr.rf.runtime.oracle.PhaseNoisePSDOracle.interpolate( ...
    [1e3;1e4],[1e3;1e4;1e5],[-80;-100;-120]);
verifyEqual(t,levels,[-80;-100],"AbsTol",1e-12);
verifyGreaterThan(t,sixgr.rf.runtime.oracle.PhaseNoisePSDOracle. ...
    integratedVariance([1e3;1e4;1e5],[-80;-100;-120]),0);
end

function testIQEstimatorCompensatorAndLeakage(t)
rng(5); reference=randn(1024,1)+1j*randn(1024,1);
[observed,~]=sixgr.rf.runtime.IQImbalanceProfile.apply( ...
    reference,1.5,5,0.02-0.01j);
estimate=sixgr.rf.runtime.IQImbalanceEstimator.estimate( ...
    reference,observed,"SYNCHRONIZED_BASEBAND");
compensator=sixgr.rf.runtime.IQImbalanceCompensator(estimate,2);
[corrected,trace]=compensator.apply(observed,2);
verifyLessThan(t,norm(corrected-reference)/norm(reference),1e-10);
verifyEqual(t,trace.SamplesProcessed,1024);
idle=[true(100,1);false(924,1)];
leak=sixgr.rf.runtime.DCOffsetAndLOLeakage.estimate( ...
    observed,idle,"ADC_OUTPUT");
removed=sixgr.rf.runtime.DCOffsetAndLOLeakage.remove(observed,leak);
verifyTrue(t,all(isfinite(removed)));
end

function testDACAndFilters(t)
profile=struct("Bits",8,"FullScale",1,"Convention","signed_midtread", ...
    "DitherRMS",1e-4,"ApertureJitter_s",1e-13, ...
    "ProfileID","DAC_TEST","Version","1.0.0");
n=(0:1023).'; x=0.5*exp(1j*2*pi*0.02*n);
dac=sixgr.rf.runtime.DACModel.convert(x,profile,1e6,11);
verifyEqual(t,dac.Bits,8);
filterProfile=struct("ProfileID","LPF_TEST","Version","1.0.0", ...
    "Taps",[0.25;0.5;0.25],"Passband_Hz",100e3, ...
    "Stopband_Hz",300e3,"SampleRate_Hz",1e6);
[filtered,state,evidence]=sixgr.rf.runtime.ReconstructionFilter.apply( ...
    dac.Output,filterProfile,[]);
verifyEqual(t,numel(filtered),numel(x));
verifyEqual(t,numel(state),2);
verifyEqual(t,evidence.ReferencePlane,"POST_RECONSTRUCTION_FILTER");
end

function testPAKernelsAndDPDProfile(t)
x=complex(linspace(-0.5,0.5,128).',linspace(0.2,-0.2,128).');
coefficients=[1 0.1;-0.1 0.02];
orders=[1;3];
[runtime,~]=sixgr.rf.runtime.MemoryPolynomialPA.apply( ...
    x,coefficients,orders,[]);
oracle=sixgr.rf.runtime.oracle.MemoryPolynomialSpec.apply( ...
    x,coefficients,orders);
verifyEqual(t,runtime,oracle,"AbsTol",1e-12);
gmp=struct("MainCoefficients",[1;-0.1],"MainOrders",[1;3], ...
    "CrossCoefficients",0.02,"CrossOrders",3,"CrossDelays",1);
verifyTrue(t,all(isfinite(sixgr.rf.runtime. ...
    GeneralizedMemoryPolynomialPA.apply(x,gmp))));
profile=struct("ProfileID","DPD_TEST","Version","1.0.0", ...
    "Model","memory_polynomial","Coefficients",[1;-0.1], ...
    "Orders",[1;3],"MemoryDepth",1, ...
    "TrainingWaveformSHA256",repmat('a',1,64), ...
    "HoldoutWaveformSHA256",repmat('b',1,64));
profile=sixgr.rf.runtime.DPDProfile.validate(profile);
verifyEqual(t,strlength(profile.CoefficientSHA256),64);
end

function testReceiverComponentsAndFrontEnd(t)
cfg=localReceiverConfiguration();
receiver=sixgr.rf.runtime.ReceiverFrontEnd(cfg,6);
n=(0:1023).'; x=0.02*exp(1j*2*pi*0.03*n);
[output,evidence]=receiver.apply(x,1,6);
verifyEqual(t,size(output),size(x));
verifyEqual(t,evidence.ReferencePlane,"ADC_OUTPUT");
verifyTrue(t,all(isfinite(evidence.QuantizationErrorCovariance(:))));
intermod=sixgr.rf.runtime.IntermodulationScenario.run(1e6,1024, ...
    struct("Tone1_Hz",50e3,"Tone2_Hz",80e3,"TonePower_dBm",-30, ...
    "IIP2_dBm",40,"IIP3_dBm",10,"Seed",7));
verifyEqual(t,intermod.IM3Frequencies_Hz,[20e3 110e3]);
end

function testReceiverSlotIsNotADCFullScale(t)
cfg=localReceiverConfiguration();
a=sixgr.rf.runtime.ReceiverFrontEnd(cfg,6);
b=sixgr.rf.runtime.ReceiverFrontEnd(cfg,6);
x=0.02*exp(1j*2*pi*0.03*(0:127).');
[first,e1]=a.apply(x,0,6);
[later,e2]=b.apply(x,99,6);
verifyEqual(t,first,later);
verifyEqual(t,e1.AGC.ClippingRatio,e2.AGC.ClippingRatio);
verifyEqual(t,e1.ADC.FullScale,cfg.ADCProfile.FullScale);
verifyEqual(t,e1.AGC.FullScale,cfg.ADCProfile.FullScale);
end

function testAGCClippingUsesSeparateIQRails(t)
cfg=localReceiverConfiguration();
cfg.AGCProfile.MinGain_dB=0;
cfg.AGCProfile.MaxGain_dB=0;
agc=sixgr.rf.runtime.AGCState(cfg.AGCProfile,6);
x=repmat(0.8+0.8j,128,1);
[y,evidence]=agc.apply(x,1,6);
verifyEqual(t,y,x);
verifyEqual(t,evidence.ClippingRatio,0);
verifyError(t,@()agc.apply(repmat(1.1+0.1j,128,1),1,6),"RF:AGCOverload");
end

function testReceiverNoiseChunkContinuityFixedGain(t)
% Fixed gain isolates RF filtering/noise continuity from AGC update policy.
cfg=localReceiverConfiguration();
cfg.AGCProfile.MinGain_dB=0;
cfg.AGCProfile.MaxGain_dB=0;
cfg.ADCProfile.Bits=24;
cfg.MixerProfile.LOFrequency_Hz=137;
whole=sixgr.rf.runtime.ReceiverFrontEnd(cfg,6);
chunks=sixgr.rf.runtime.ReceiverFrontEnd(cfg,6);
n=(0:1023).';
x=[0.02*exp(1j*2*pi*0.03*n),0.01*exp(-1j*2*pi*0.02*n)];
[expected,~]=whole.apply(x,1,6);
actual=zeros(size(x),'like',expected);
first=1;
for last=[1,17,255,512,1024]
    [actual(first:last,:),~]=chunks.apply(x(first:last,:),1,6);
    first=last+1;
end
verifyEqual(t,actual,expected);
verifyEqual(t,chunks.MixerSampleIndex,whole.MixerSampleIndex);
verifyEqual(t,chunks.FilterState,whole.FilterState,"AbsTol",1e-12);
end

function testTransmitterFrontEnd(t)
rng(7); training=0.2*(randn(512,1)+1j*randn(512,1));
paProfile=struct("ProfileID","RAPP_TX","Model","rapp", ...
    "InputBackoff_dB",3,"Version","1.0.0", ...
    "Smoothness",2,"SaturationAmplitude",1);
[paOutput,~]=sixgr.rf.runtime.PAProfile.apply(training,paProfile);
dpd=sixgr.rf.runtime.DPDTrainer.train(training,paOutput,3,1,"DPD_TX");
dpd.Version="1.0.0"; dpd.Model="memory_polynomial";
dpd.TrainingWaveformSHA256=repmat('c',1,64);
dpd.HoldoutWaveformSHA256=repmat('d',1,64);
dpd=sixgr.rf.runtime.DPDProfile.validate(dpd);
cfg=struct("SampleRate_Hz",1e6, ...
    "DACProfile",struct("Bits",10,"FullScale",1, ...
    "Convention","signed_midtread","DitherRMS",0, ...
    "ApertureJitter_s",0,"ProfileID","DAC_TX","Version","1.0.0"), ...
    "ReconstructionFilterProfile",struct("ProfileID","TX_LPF", ...
    "Version","1.0.0","Taps",[0.25;0.5;0.25], ...
    "Passband_Hz",100e3,"Stopband_Hz",300e3), ...
    "CFRProfile",struct("ClipLevel_dB",8,"Iterations",2), ...
    "DPDProfile",dpd,"PAProfile",paProfile,"Seed",13);
transmitter=sixgr.rf.runtime.TransmitterFrontEnd(cfg,8);
[output,evidence]=transmitter.apply(training,8);
verifyEqual(t,size(output),size(training));
verifyFalse(t,evidence.PowerRestorationApplied);
end

function testPowerControllerFacades(t)
state=sixgr.rf.runtime.UplinkPowerControlState(9);
channels=["PUSCH","PUCCH","SRS","PRACH"];
controllers={@sixgr.rf.runtime.PUSCHPowerController.resolve, ...
    @sixgr.rf.runtime.PUCCHPowerController.resolve, ...
    @sixgr.rf.runtime.SRSPowerController.resolve, ...
    @sixgr.rf.runtime.PRACHPowerController.resolve};
for k=1:numel(channels)
    request=localPowerRequest(channels(k));
    result=controllers{k}(state,request);
    oracle=sixgr.rf.runtime.oracle.PowerControlSpec.resolve( ...
        request.Mu,request.MRB,request.P0_dBm,request.Alpha, ...
        request.MeasuredPathloss_dB,request.DeltaTF_dB,0,request.PCMAX_dBm);
    verifyEqual(t,result.AppliedPower_dBm,oracle.AppliedPower_dBm, ...
        "AbsTol",1e-12);
end
end

function testRFMeasurements(t)
fs=1e6; n=(0:8191).';
reference=exp(1j*2*pi*50e3*n/fs);
observed=reference.*exp(1j*(0.1+2*pi*250*n/fs));
frequency=sixgr.rf.runtime.FrequencyErrorMeasurement.measure( ...
    reference,observed,fs,"SYNCHRONIZED_BASEBAND");
verifyEqual(t,frequency.FrequencyError_Hz,250,"AbsTol",1e-10);
timing=sixgr.rf.runtime.TimeAlignmentMeasurement.measure( ...
    reference,[zeros(4,1);reference;zeros(12,1)],fs,"ADC_OUTPUT");
verifyEqual(t,timing.EstimatedTiming_samples,4,"AbsTol",0.05);
spectrum=sixgr.rf.runtime.SpectrumEmissionMeasurement.measure( ...
    reference+0.01*exp(1j*2*pi*200e3*n/fs),fs, ...
    struct("ProfileID","SEM_TEST","Version","1.0.0", ...
    "BandCenters_Hz",[50e3;200e3],"Bandwidths_Hz",[20e3;20e3], ...
    "Limits_dB",[10;0]));
verifyEqual(t,height(spectrum),2);
mask=false(16,4); mask(1:8,:)=true;
grid=zeros(16,4); grid(mask)=1; measured=grid; measured(~mask)=1e-4;
ibe=sixgr.rf.runtime.InBandEmissionMeasurement.measure( ...
    grid,measured,mask,-20,"EQUALIZED_RE");
verifyTrue(t,ibe.Passed);
end

function testIndependentOracles(t)
verifyEqual(t,sixgr.rf.runtime.oracle.CFOAnalyticalSpec.relative( ...
    1200,200,50),1050);
[q,c,clip]=sixgr.rf.runtime.oracle.QuantizerSpec.signedMidtread( ...
    [-1 0 1],3,0.5);
verifyEqual(t,c,[-3 0 3]); verifyEqual(t,q,[-0.5 0 0.5]);
verifyEqual(t,clip,[true false true]);
nf=sixgr.rf.runtime.oracle.FriisNoiseFigureSpec.cascade( ...
    [10 0],[1 5],100e6,290);
verifyEqual(t,nf.CascadeNF_dB,1.68837119177949,"AbsTol",1e-10);
evm=sixgr.rf.runtime.oracle.EVMReferenceSpec.measure( ...
    ones(32,1),1.01*ones(32,1),false);
verifyEqual(t,evm,1,"AbsTol",1e-12);
end

function cfg=localReceiverConfiguration()
cfg=struct("SampleRate_Hz",1e6,"InputPower_dBm",-30, ...
    "LNAProfile",struct("ProfileID","LNA_TEST","Version","1.0.0", ...
    "Gain_dB",6,"NoiseFigure_dB",2,"P1dBInput_dBm",-5, ...
    "ReferenceImpedance_Ohm",50), ...
    "MixerProfile",struct("ProfileID","MIXER_TEST","Version","1.0.0", ...
    "LOFrequency_Hz",0,"ConversionGain_dB",0, ...
    "NoiseFigure_dB",8,"IIP2_dBm",40,"IIP3_dBm",15), ...
    "SelectivityFilterProfile",struct("ProfileID","RX_LPF", ...
    "Version","1.0.0","Taps",[0.25;0.5;0.25], ...
    "Passband_Hz",100e3,"Stopband_Hz",300e3,"ENBW_Hz",150e3), ...
    "AGCProfile",struct("TargetRMS",0.25,"MinGain_dB",-20, ...
    "MaxGain_dB",20,"Attack",0.8,"Release",0.2,"HoldSamples",4), ...
    "ADCProfile",struct("Bits",10,"FullScale",1, ...
    "Convention","signed_midtread"), ...
    "Temperature_K",290,"NoiseSeed",17,"ReferenceImpedance_Ohm",50);
end

function request=localPowerRequest(channel)
request=struct("Channel",channel,"Mu",1,"MRB",10, ...
    "MeasuredPathloss_dB",80,"PathlossSource","MEASURED_REFERENCE_RS", ...
    "P0_dBm",-90,"Alpha",0.8,"DeltaTF_dB",1,"PCMAX_dBm",23);
end
