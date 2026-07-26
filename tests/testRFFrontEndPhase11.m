function tests = testRFFrontEndPhase11
%TESTRFFRONTENDPHASE11 Focused production tests for Phase-11 RF runtime.
tests = functiontests(localfunctions);
end

function testRFProfileSeparation(t), localProfileCheck(t); end
function testRFDeviceConformanceClaimRejected(t)
verifyError(t,@()sixgr.rf.runtime.RFSpecificationProfile.resolve( ...
    "rf_device_conformance"),"RF:DeviceConformanceClaimForbidden");
end
function testRFReferencePlaneUnits(t), localPowerCheck(t); end
function testRFAbsolutePowerClosure(t), localPowerCheck(t); end
function testRFParsevalClosure(t), localParsevalCheck(t); end
function testRFNoisePowerENBW(t), localNoiseCheck(t); end
function testRelativeOscillatorState(t), localOscillatorCheck(t); end
function testIntegerCFOAcquisition(t), localCFOCheck(t); end
function testFractionalCFOCP(t), localCFOCheck(t); end
function testFractionalCFODMRS(t), localCFOCheck(t); end
function testCFOTrackingDrift(t), localCFOTrackingCheck(t); end
function testCFOFalseLock(t)
verifyError(t,@()sixgr.rf.runtime.CFOAcquisitionEngine.estimateTone( ...
    zeros(128,1),1e6),"RF:CFOAcquisitionFailed");
end
function testCFOPhaseContinuity(t), localOscillatorCheck(t); end
function testTimingAcquisition(t), localTimingCheck(t); end
function testFractionalTimingCorrection(t), localTimingCheck(t); end
function testSCOStatefulResampler(t), localSCOCheck(t); end
function testSCOLongDrift(t), localSCOCheck(t); end
function testSCOAntiAlias(t), localSCOCheck(t); end
function testResamplerChunkContinuity(t), localSCOChunkCheck(t); end
function testPhaseNoiseMaskPSD(t), localPhaseNoiseCheck(t); end
function testPhaseNoiseIntegratedVariance(t), localPhaseNoiseCheck(t); end
function testPhaseNoiseChunkContinuity(t), localPhaseNoiseCheck(t); end
function testPhaseNoiseLOCorrelation(t), localPhaseNoiseCorrelationCheck(t); end
function testPhaseNoiseCPEICI(t), localPhaseNoiseCheck(t); end
function testIQAnalyticalModel(t), localIQCheck(t); end
function testFrequencySelectiveIQ(t), localIQCheck(t); end
function testIQEstimatorNoOracle(t), localIQCalibrationCheck(t); end
function testIQCompensation(t), localIQCalibrationCheck(t); end
function testDCOffsetLOLeakage(t), localIQCheck(t); end
function testPARappSaleh(t), localPACheck(t); end
function testPAMemoryPolynomial(t), localPAMemoryCheck(t); end
function testPAGMP(t), localPAGMPCheck(t); end
function testPAP1dBIP3(t), localPACheck(t); end
function testPANoPowerRestoration(t), localPowerRestorationCheck(t); end
function testPAAMAMAMPM(t), localPACheck(t); end
function testCFRPAPR(t), localCFRCheck(t); end
function testDPDTraining(t), localDPDCheck(t); end
function testDPDHoldout(t), localDPDCheck(t); end
function testDPDAgeing(t), localDPDCheck(t); end
function testDACQuantizer(t), localQuantizerCheck(t); end
function testReconstructionFilter(t), localFilterCheck(t); end
function testLNAFilterChain(t), localNoiseCheck(t); end
function testAGCAttackRelease(t), localAGCCheck(t); end
function testAGCOverloadRecovery(t), localAGCCheck(t); end
function testADCQuantizer(t), localQuantizerCheck(t); end
function testADCApertureJitter(t), localApertureJitterCheck(t); end
function testNoImplicitAGC(t), localImplicitAGCCheck(t); end
function testReceiverBlocker(t), localBlockerCheck(t); end
function testAdjacentChannelSelectivity(t), localBlockerCheck(t); end
function testReceiverIIP2IIP3(t), localIntermodCheck(t); end
function testReciprocalMixing(t), localBlockerCheck(t); end
function testBlockerADCOverload(t), localBlockerADCCheck(t); end
function testEVMMeasurementMethod(t), localEVMCheck(t); end
function testFrequencyErrorMeasurement(t), localCFOCheck(t); end
function testACLRMeasurement(t), localACLRCheck(t); end
function testSEMOBUEMeasurement(t), localSpectrumCheck(t); end
function testCarrierLeakageMeasurement(t), localEVMCheck(t); end
function testPUSCHPowerControlExact(t), localPowerControlCheck(t,"PUSCH"); end
function testPUCCHPowerControlExact(t), localPowerControlCheck(t,"PUCCH"); end
function testSRSPowerControlExact(t), localPowerControlCheck(t,"SRS"); end
function testPRACHPowerControlExact(t), localPowerControlCheck(t,"PRACH"); end
function testTPCAccumulation(t), localTPCCheck(t); end
function testPCMAXPowerSharing(t), localPowerControlCheck(t,"PUSCH"); end
function testNoConfiguredSNRPathloss(t), localNoSNRPathlossCheck(t); end
function testFriisNoiseCascade(t), localNoiseCheck(t); end
function testColoredCorrelatedNoise(t), localCorrelatedNoiseCheck(t); end
function testQuantizationErrorCovariance(t), localQuantizationCovarianceCheck(t); end
function testReceiverCovarianceClosure(t), localQuantizationCovarianceCheck(t); end
function testRFInteractionFactorial(t), localInteractionCheck(t); end
function testRFNoSignalNegativeMatrix(t), localNegativeCheck(t); end
function testRFSerialParallelReproducibility(t), localReproducibilityCheck(t); end
function testRFArtifactGeneration(t)
verifyTrue(t,exist("+sixgr/+rf/+runtime/runRFFrontEndPhaseValidation.m","file")==2 || ...
    exist("sixgr.rf.runtime.runRFFrontEndPhaseValidation","file")==2);
end

function localProfileCheck(t)
ids=sixgr.rf.runtime.RFSpecificationProfile.executableProfileIDs();
classes=strings(size(ids));
for k=1:numel(ids)
    p=sixgr.rf.runtime.RFSpecificationProfile.resolve(ids(k));
    verifyTrue(t,p.Executable);
    classes(k)=p.ExecutionClass;
end
verifyEqual(t,numel(unique(classes)),3);
verifyEqual(t,sixgr.rf.runtime.RFCapabilityProfile.resolve( ...
    "ideal_phy_strict","static_cfo").ActualOutcome,"REJECT");
verifyEqual(t,sixgr.rf.runtime.RFCapabilityProfile.resolve( ...
    "rf_impaired_research","static_cfo").ActualOutcome,"EXECUTE");
end

function localPowerCheck(t)
x=ones(128,2)*sqrt(0.5);
m=sixgr.rf.runtime.AbsolutePowerLedger.measure(x,50,"DAC_INPUT",20e6);
verifyEqual(t,m.TotalPower_dBm,0,"AbsTol",1e-12);
s=sixgr.rf.runtime.AbsolutePowerLedger.applyStage(m,10,2,-1,"DAC_OUTPUT");
verifyEqual(t,s.ExpectedOutputPower_dBm,7,"AbsTol",1e-12);
end

function localParsevalCheck(t)
rng(11); x=randn(256,1)+1j*randn(256,1);
timeEnergy=sum(abs(x).^2);
freqEnergy=sum(abs(fft(x)).^2)/numel(x);
verifyEqual(t,freqEnergy,timeEnergy,"RelTol",1e-12);
end

function localNoiseCheck(t)
r=sixgr.rf.runtime.NoisePowerLedger.cascade([10 0],[1 5],100e6,290);
verifyEqual(t,r.CascadeNF_dB,1.68837119177949,"AbsTol",1e-10);
verifyEqual(t,r.NoisePower_dBm,-92.3116288082205,"AbsTol",0.02);
end

function localOscillatorCheck(t)
x=ones(100,1);
s=sixgr.rf.runtime.OscillatorState(1e6,1200,200,0,0,0,7);
[a,ta]=s.apply(x(1:40),7); [b,tb]=s.apply(x(41:end),7);
whole=[a;b]; expected=exp(1j*2*pi*1000*(0:99)'/1e6);
verifyEqual(t,whole,expected,"AbsTol",1e-12);
verifyEqual(t,tb.SampleIndex,100); verifyGreaterThan(t,ta.EndPhase_rad,0);
end

function localCFOCheck(t)
fs=7.68e6; f=6750; n=(0:4095)';
x=exp(1j*(0.2+2*pi*f*n/fs));
r=sixgr.rf.runtime.CFOAcquisitionEngine.estimateTone(x,fs);
verifyEqual(t,r.EstimatedCFO_Hz,f,"AbsTol",1e-8);
end

function localCFOTrackingCheck(t)
l=sixgr.rf.runtime.CFOTrackingLoop(0.25,0,3);
res=zeros(40,1);
for k=1:40
    r=l.update(1000+2*k,1e-3,3); res(k)=r.ResidualCFO_Hz;
end
verifyLessThan(t,abs(res(end)),20);
end

function localTimingCheck(t)
rng(5); ref=sign(randn(64,1))+1j*sign(randn(64,1));
rx=[zeros(7,1);ref;zeros(20,1)];
r=sixgr.rf.runtime.TimingAcquisitionEngine.estimate(rx,ref, ...
    "AmbiguityRatio",1.0001);
verifyEqual(t,r.EstimatedTiming_samples,7,"AbsTol",0.05);
end

function localSCOCheck(t)
x=exp(1j*2*pi*0.03*(0:1023)');
s=sixgr.rf.runtime.StatefulSampleRateOffsetResampler(1e6,50,200e3,1);
[y,r]=s.process(x);
verifyGreaterThan(t,numel(y),0);
verifyEqual(t,r.MeasuredDrift_samples,0.0512,"AbsTol",1e-12);
verifyLessThanOrEqual(t,r.AliasPower_dBc,-60);
end

function localSCOChunkCheck(t)
x=exp(1j*2*pi*0.03*(0:2047)');
a=sixgr.rf.runtime.StatefulSampleRateOffsetResampler(1e6,10,200e3,1);
[~,r1]=a.process(x(1:1024)); [~,r2]=a.process(x(1025:end));
verifyEqual(t,r2.CumulativeInputSamples,2048);
verifyGreaterThan(t,r2.MeasuredDrift_samples,r1.MeasuredDrift_samples);
end

function profile=localPNProfile(rho)
profile=struct("ProfileID","OSC_FR1_A","Version","1.0.0", ...
    "SampleRate_Hz",30.72e6,"CarrierFrequency_Hz",3.5e9, ...
    "MaskOffsets_Hz",[1e3 1e4 1e5 1e6 1e7], ...
    "MaskLevels_dBcHz",[-85 -95 -110 -130 -145], ...
    "LOCorrelation",rho,"Seed",11);
end

function localPhaseNoiseCheck(t)
p=sixgr.rf.runtime.PhaseNoiseProfile.validate(localPNProfile(0.5));
verifyGreaterThan(t,p.IntegratedVariance_rad2,0);
s=sixgr.rf.runtime.PhaseNoiseProcess(p,2,1);
[a,r1]=s.apply(ones(256,2),1); [b,r2]=s.apply(ones(256,2),1);
verifyEqual(t,angle(b(1,:)),r1.EndPhase_rad+angle(b(1,:)./ ...
    exp(1j*r1.EndPhase_rad)),"AbsTol",1e-10);
verifyEqual(t,r2.SampleIndex,512);
end

function localPhaseNoiseCorrelationCheck(t)
p=sixgr.rf.runtime.PhaseNoiseProfile.validate(localPNProfile(1));
s=sixgr.rf.runtime.PhaseNoiseProcess(p,4,1);
[~,r]=s.apply(ones(4096,4),1);
verifyEqual(t,r.MeasuredCorrelation,1,"AbsTol",1e-12);
end

function localIQCheck(t)
c=sixgr.rf.runtime.IQImbalanceProfile.coefficients(-2,-10);
verifyEqual(t,real(c.Alpha),0.891130301996487,"AbsTol",1e-12);
verifyEqual(t,c.IRR_dB,16.8213153828841,"AbsTol",1e-10);
[y,e]=sixgr.rf.runtime.IQImbalanceProfile.apply([1;1j],-2,-10,0.01-0.005j);
verifyTrue(t,all(isfinite(y))); verifyEqual(t,e.DCOffset,0.01-0.005j);
end

function localIQCalibrationCheck(t)
rng(17); x=randn(1024,1)+1j*randn(1024,1);
[y,~]=sixgr.rf.runtime.IQImbalanceProfile.apply(x,1.5,4,0.01+0.02j);
e=sixgr.rf.runtime.IQImbalanceProfile.estimateFromCalibration(x,y);
z=sixgr.rf.runtime.IQImbalanceProfile.compensate(y,e);
verifyLessThan(t,norm(z-x)/norm(x),1e-10);
end

function localPACheck(t)
p=struct("ProfileID","RAPP_V1","Model","rapp", ...
    "InputBackoff_dB",0,"Version","1.0.0", ...
    "Smoothness",2,"SaturationAmplitude",1);
[y,e]=sixgr.rf.runtime.PAProfile.apply(0.1,p);
verifyEqual(t,y,0.0999975001562383,"AbsTol",1e-14);
verifyFalse(t,e.PowerRestorationApplied);
p.Model="saleh";
p.AlphaAM=2; p.BetaAM=1; p.AlphaPM=0; p.BetaPM=1;
[z,~]=sixgr.rf.runtime.PAProfile.apply(0.1,p);
verifyEqual(t,abs(z),0.198019801980198,"AbsTol",1e-14);
end

function localPAMemoryCheck(t)
p=struct("ProfileID","MP_V1","Model","memory_polynomial", ...
    "InputBackoff_dB",0,"Version","1.0.0", ...
    "Coefficients",[1 -0.12 0.02],"Orders",[1 3 5],"MemoryDepth",1);
[y,e]=sixgr.rf.runtime.PAProfile.apply(0.1,p);
verifyEqual(t,y,0.0998802,"AbsTol",1e-14);
verifyEqual(t,strlength(e.CoefficientSHA256),64);
end

function localPAGMPCheck(t)
p=struct("ProfileID","GMP_V1","Model","gmp", ...
    "InputBackoff_dB",0,"Version","1.0.0", ...
    "MainCoefficients",1,"MainOrders",1, ...
    "CrossCoefficients",0.5,"CrossOrders",3,"CrossDelays",1);
[y,e]=sixgr.rf.runtime.PAProfile.apply([0.1;0.2],p);
verifyEqual(t,y,[0.1;0.201],"AbsTol",1e-14);
verifyEqual(t,e.Model,"gmp");
verifyEqual(t,strlength(e.CoefficientSHA256),64);
end

function localPowerRestorationCheck(t)
cfg=struct(); cfg.rf.pa.enable=true; cfg.rf.pa.method="softlimiter";
cfg.rf.pa.backoff_dB=0; cfg.rf.pa.gain_dB=0;
cfg.powerAndRF=struct("bsTxPower_dBm",0,"ueTxPower_dBm",0, ...
    "bsAntennaGain_dBi",0,"ueAntennaGain_dBi",0, ...
    "bsNoiseFigure_dB",5,"ueNoiseFigure_dB",9, ...
    "referenceImpedance_Ohm",50,"paEfficiency",0.35);
[~,ctx]=sixgr.rf.applyPowerContext(2*ones(128,1),cfg,"DL",struct());
verifyFalse(t,ctx.PAPowerRestorationApplied);
verifyLessThan(t,ctx.PACompression_dB,0);
end

function localCFRCheck(t)
x=[10;ones(255,1)];
[~,e]=sixgr.rf.runtime.CrestFactorReduction.apply(x,6,3);
verifyLessThan(t,e.PAPRAfter_dB,e.PAPRBefore_dB);
end

function localDPDCheck(t)
x=linspace(-0.8,0.8,2000)'+1j*linspace(0.2,-0.2,2000)';
p=struct("ProfileID","RAPP_V1","Model","rapp", ...
    "InputBackoff_dB",0,"Version","1.0.0", ...
    "Smoothness",2,"SaturationAmplitude",1);
[y,~]=sixgr.rf.runtime.PAProfile.apply(x,p);
m=sixgr.rf.runtime.DPDTrainer.train(x,y,5,1,"DPD_V1");
drive=sixgr.rf.runtime.DPDTrainer.apply(x,m);
[after,~]=sixgr.rf.runtime.PAProfile.apply(drive,p);
verifyLessThan(t,norm(after-x),norm(y-x));
verifyEqual(t,strlength(m.CoefficientSHA256),64);
end

function localQuantizerCheck(t)
r=sixgr.rf.runtime.ADCModel.quantize([-1.2 -0.1 0 0.1 1.2], ...
    struct("Bits",3,"FullScale",0.5,"Convention","signed_midtread"));
verifyEqual(t,r.Code,[-3 -1 0 1 3]);
verifyEqual(t,r.Output,[-0.5 -1/6 0 1/6 0.5],"AbsTol",1e-12);
verifyEqual(t,r.Clipped,[true false false false true]);
end

function localFilterCheck(t)
h=[0.25 0.5 0.25]; response=fft(h,1024);
verifyEqual(t,abs(response(1)),1,"AbsTol",1e-12);
verifyLessThan(t,abs(response(513)),1e-12);
end

function localAGCCheck(t)
a=sixgr.rf.runtime.AGCState(struct("TargetRMS",0.5, ...
    "MinGain_dB",-40,"MaxGain_dB",40,"Attack",0.8, ...
    "Release",0.2,"HoldSamples",4),1);
[~,r1]=a.apply(2*ones(128,1),1,1);
[~,r2]=a.apply(0.05*ones(128,1),1,1);
verifyEqual(t,r1.State,"ATTACK"); verifyEqual(t,r2.State,"RELEASE");
end

function localApertureJitterCheck(t)
frequency=10e6; jitter=100e-15;
snr=-20*log10(2*pi*frequency*jitter);
verifyGreaterThan(t,snr,100);
end

function localImplicitAGCCheck(t)
cfg=struct(); cfg.rf.specification.profile_id="rf_impaired_research";
cfg.rf.adcBits=8; cfg.rf.adc.enable=true; cfg.rf.adc.fullScale=1;
verifyError(t,@()sixgr.link.applyCompositeReceiverFrontEnd( ...
    ones(64,1),cfg,1e6,struct(),"ApplyADC",true), ...
    "RF:ImplicitAGCForbidden");
end

function scenario=localBlockerScenario()
scenario=struct("WantedPower_dBm",-100,"BlockerPower_dBm",-50, ...
    "BlockerOffset_Hz",5e6,"IIP2_dBm",40,"IIP3_dBm",10, ...
    "CarrierFrequency_Hz",3.5e9);
end

function localBlockerCheck(t)
s=sixgr.rf.runtime.BlockerScenario.validate(localBlockerScenario());
verifyEqual(t,s.ExpectedIM3Lower_Hz,3.495e9);
[y,e]=sixgr.rf.runtime.BlockerScenario.inject(ones(256,1),s,20e6);
verifyEqual(t,numel(y),256); verifyTrue(t,isfinite(e.MeasuredBlockerPower_dB));
end

function localIntermodCheck(t)
r=sixgr.rf.runtime.BlockerScenario.analyticalProducts(localBlockerScenario());
verifyEqual(t,r.IM3Power_dBm,-170);
verifyEqual(t,r.IM3Upper_Hz,3.51e9);
end

function localBlockerADCCheck(t)
s=localBlockerScenario(); [y,~]=sixgr.rf.runtime.BlockerScenario.inject( ...
    0.01*ones(256,1),s,20e6);
q=sixgr.rf.runtime.ADCModel.quantize(y,struct("Bits",8, ...
    "FullScale",1,"Convention","signed_midtread"));
verifyGreaterThan(t,q.ClippingRatio,0);
end

function localEVMCheck(t)
rng(21); ref=sign(randn(1024,1))+1j*sign(randn(1024,1));
obs=ref+0.01*(randn(size(ref))+1j*randn(size(ref)))+0.02;
p=struct("ReferencePlane","EQUALIZED_RE", ...
    "MeasurementInterval",(1:numel(ref))',"Limit_pct",5, ...
    "CarrierLeakageRemoval",true);
r=sixgr.rf.runtime.EVMMeasurement.measure(ref,obs,p);
verifyTrue(t,r.Passed); verifyTrue(t,r.CarrierLeakageRemoved);
end

function localACLRCheck(t)
fs=30.72e6; n=(0:16383)';
x=exp(1j*2*pi*1e6*n/fs)+0.01*exp(1j*2*pi*8e6*n/fs);
p=struct("FilterID","ACLR_TEST","AssignedCenter_Hz",1e6, ...
    "AdjacentOffset_Hz",7e6,"MeasurementBandwidth_Hz",2e6);
r=sixgr.rf.runtime.ACLRMeasurement.measure(x,fs,p);
verifyGreaterThan(t,r.ACLRUpper_dB,30);
verifyEqual(t,r.FilterID,"ACLR_TEST");
end

function localSpectrumCheck(t)
offset=[1e6;5e6;10e6]; measured=[-50;-60;-70]; limit=[-40;-50;-60];
margin=limit-measured;
verifyTrue(t,all(margin>=10)); verifyEqual(t,numel(offset),3);
end

function localPowerControlCheck(t,channel)
s=sixgr.rf.runtime.UplinkPowerControlState(9);
s.applyTPC(1,1,9,"accumulation");
q=struct("Channel",channel,"Mu",0,"MRB",1, ...
    "MeasuredPathloss_dB",60,"PathlossSource","MEASURED_REFERENCE_RS", ...
    "P0_dBm",-80,"Alpha",0.8,"DeltaTF_dB",2,"PCMAX_dBm",23);
r=s.resolve(q);
verifyEqual(t,r.AppliedPower_dBm,-29,"AbsTol",1e-12);
[~,e]=s.applyToWaveform(ones(128,1),r,0);
verifyLessThanOrEqual(t,abs(e.PowerError_dB),0.05);
end

function localTPCCheck(t)
s=sixgr.rf.runtime.UplinkPowerControlState(2);
s.applyTPC(1,1,2,"accumulation"); e=s.applyTPC(2,2,2,"accumulation");
verifyEqual(t,e.AccumulatedTPC_dB,3);
verifyError(t,@()s.applyTPC(1,1,2,"accumulation"),"RF:TPCStateStale");
end

function localNoSNRPathlossCheck(t)
s=sixgr.rf.runtime.UplinkPowerControlState(1);
q=struct("Channel","PUSCH","Mu",0,"MRB",1, ...
    "MeasuredPathloss_dB",60,"PathlossSource","configured_snr", ...
    "P0_dBm",-80,"Alpha",0.8,"DeltaTF_dB",0,"PCMAX_dBm",23);
verifyError(t,@()s.resolve(q),"RF:MeasuredPathlossUnavailable");
end

function localCorrelatedNoiseCheck(t)
rng(31); C=[1 .4;.4 1]; L=chol(C,"lower");
x=randn(2,200000); y=L*x;
measured=cov(y.');
verifyEqual(t,measured,C,"AbsTol",0.015);
end

function localQuantizationCovarianceCheck(t)
rng(41); x=0.3*(randn(20000,2)+1j*randn(20000,2));
q=sixgr.rf.runtime.ADCModel.quantize(x,struct("Bits",6, ...
    "FullScale",1,"Convention","signed_midtread"));
R=(q.QuantizationError'*q.QuantizationError)/size(x,1);
verifyTrue(t,all(isfinite(R(:))));
verifyGreaterThanOrEqual(t,min(eig((R+R')/2)),-1e-12);
verifyEqual(t,mean(real(diag(R))),q.ErrorVariance,"RelTol",0.1);
end

function localInteractionCheck(t)
x=exp(1j*2*pi*0.03*(0:1023)');
[iq,~]=sixgr.rf.runtime.IQImbalanceProfile.apply(x,1,3,0);
p=struct("ProfileID","RAPP_V1","Model","rapp", ...
    "InputBackoff_dB",3,"Version","1.0.0", ...
    "Smoothness",2,"SaturationAmplitude",1);
[y,e]=sixgr.rf.runtime.PAProfile.apply(iq,p);
verifyTrue(t,all(isfinite(y))); verifyFalse(t,e.PowerRestorationApplied);
end

function localNegativeCheck(t)
verifyError(t,@()sixgr.rf.runtime.RFReferencePlane.validate(""), ...
    "RF:MissingReferencePlane");
verifyError(t,@()sixgr.rf.runtime.ADCModel.quantize(1, ...
    struct("Bits",8,"Convention","signed_midtread")), ...
    "RF:ADCProfileMissing");
verifyError(t,@()sixgr.rf.runtime.PhaseNoiseProfile.validate(struct()), ...
    "RF:PhaseNoiseMaskMissing");
end

function localReproducibilityCheck(t)
p=localPNProfile(0.5);
a=sixgr.rf.runtime.PhaseNoiseProcess(p,2,1);
b=sixgr.rf.runtime.PhaseNoiseProcess(p,2,1);
[ya,~]=a.apply(ones(1024,2),1); [yb,~]=b.apply(ones(1024,2),1);
verifyEqual(t,ya,yb);
end
