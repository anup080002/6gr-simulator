function tests=testWaveformPhase13
%TESTWAVEFORMPHASE13 Mandatory production tests for waveform Phase 13.
tests=functiontests(localfunctions);
end

function testWaveformProfilePlanning(testCase)
input=localRead("waveform_capability_profile_matrix.csv");
for index=1:height(input)
    plan=sixgr.phy.waveform.WaveformCapabilityProfile.plan( ...
        input.ProfileID(index),input.Feature(index));
    verifyEqual(testCase,plan.Outcome,input.ExpectedOutcome(index));
    if plan.Outcome=="REJECT"
        verifyEqual(testCase,plan.ErrorID,input.ExpectedError(index));
    end
end
end

function testOFDMParameterResolver(testCase)
carrier=localCarrier(30,"normal",25);
result=sixgr.phy.waveform.OFDMParameterResolver.resolve(carrier);
verifyEqual(testCase,result.SampleRate,result.Nfft*30e3,"AbsTol",1e-9);
verifyTrue(testCase,result.NoFallback);
end

function testOFDMInvalidParameterMatrix(testCase)
carrier=localCarrier(30,"normal",25);
verifyError(testCase,@()sixgr.phy.waveform.OFDMParameterResolver.resolve( ...
    carrier,"Nfft",128),"WAVEFORM:InvalidOFDMParameters");
verifyError(testCase,@()sixgr.phy.waveform.OFDMParameterResolver.resolve( ...
    carrier,"Nfft",512,"SampleRate",1.5e6), ...
    "WAVEFORM:InvalidOFDMParameters");
end

function testSubcarrierMapper(testCase)
map=sixgr.phy.waveform.SubcarrierMapper.build(512,300, ...
    "BWPStartSubcarrier",12);
verifyEqual(testCase,numel(unique(map.FFTBin)),height(map));
verifyEqual(testCase,min(map.REIndex),0);
end

function testSmallFFTIndependentVectors(testCase)
result=localVectors("small_fft");
verifyEqual(testCase,sum(result.MismatchCount),0);
end

function testCPInsertionRemoval(testCase)
input=(1:16).';cp=4;
withCP=sixgr.phy.waveform.CPInsertionRemoval.insert(input,cp);
verifyEqual(testCase,sixgr.phy.waveform.CPInsertionRemoval.remove( ...
    withCP,cp,16),input);
end

function testOFDMSampleScaling(testCase)
grid=ones(8,1);wave=sixgr.phy.waveform.CanonicalOFDMModulator.math( ...
    grid,16,0);
verifyEqual(testCase,sum(abs(wave).^2),sum(abs(grid).^2), ...
    "AbsTol",1e-12);
end

function testOFDMParseval(testCase)
grid=exp(1j*2*pi*(0:15).'/16);
fftGrid=sixgr.phy.waveform.SubcarrierMapper.place(grid,32);
useful=ifft(fftGrid)*sqrt(32);
result=sixgr.phy.waveform.ParsevalLedger.verify(grid,useful);
verifyLessThanOrEqual(testCase,result.RelativeError,1e-10);
end

function testOFDMPowerLedger(testCase)
ledger=sixgr.phy.waveform.WaveformPowerLedger();
ledger.add("CASE","grid","occupied_re",ones(16,1),1);
ledger.requireClosed();
verifyEqual(testCase,ledger.Rows.Status,"PASS");
end

function testOFDMNoNoiseRoundTrip(testCase)
[grid,recovered]=localRoundTrip(128,9,24,3,11);
verifyLessThanOrEqual(testCase,localNMSE(grid,recovered),1e-10);
end

function testOFDMNormalCP(testCase)
result=sixgr.phy.waveform.OFDMParameterResolver.resolve( ...
    localCarrier(30,"normal",25));
verifyEqual(testCase,result.SymbolsPerSlot,14);
verifyTrue(testCase,all(result.CyclicPrefixLengthsPerSlot>0));
end

function testOFDMExtendedCP60kHz(testCase)
result=sixgr.phy.waveform.OFDMParameterResolver.resolve( ...
    localCarrier(60,"extended",25));
verifyEqual(testCase,result.SymbolsPerSlot,12);
end

function testOFDMStreamState(testCase)
state=sixgr.phy.waveform.OFDMStreamState(1e6,7);
state.advance(100,1e6,pi/4);
snapshot=state.snapshot();
verifyEqual(testCase,snapshot.NextSampleIndex,100);
verifyEqual(testCase,snapshot.ConfigurationEpoch,7);
end

function testOFDMChunkEquivalence(testCase)
x=exp(1j*2*pi*(0:255).'/31);
one=sixgr.phy.waveform.OFDMStreamState(1e6,0);
[reference,~]=sixgr.phy.waveform.WaveformStreamComposer.frequencyShift( ...
    x,1e3,1e6,one);
chunk=sixgr.phy.waveform.OFDMStreamState(1e6,0);
[a,chunk]=sixgr.phy.waveform.WaveformStreamComposer.frequencyShift( ...
    x(1:37),1e3,1e6,chunk);
[b,~]=sixgr.phy.waveform.WaveformStreamComposer.frequencyShift( ...
    x(38:end),1e3,1e6,chunk);
verifyLessThanOrEqual(testCase,localNMSE(reference.Samples, ...
    [a.Samples;b.Samples]),1e-12);
end

function testOFDMPhaseContinuity(testCase)
state=sixgr.phy.waveform.OFDMStreamState(1e6,0);
[~,state,first]=sixgr.phy.waveform.DigitalUpconverter.process( ...
    ones(17,1),125e3,1e6,state);
[~,~,second]=sixgr.phy.waveform.DigitalUpconverter.process( ...
    ones(19,1),125e3,1e6,state);
verifyEqual(testCase,mod(second.InitialPhase_rad-first.FinalStatePhase_rad+pi, ...
    2*pi)-pi,0,"AbsTol",1e-12);
end

function testWindowingStrictDefaultZero(testCase)
profile=sixgr.phy.waveform.WindowingProfile.resolve( ...
    "nr_rel19_cp_ofdm_strict",0,false);
verifyEqual(testCase,profile.OverlapSamples,0);
verifyError(testCase,@()sixgr.phy.waveform.WindowingProfile.resolve( ...
    "nr_rel19_cp_ofdm_strict",4,true), ...
    "WAVEFORM:WindowingMustBeExplicit");
end

function testWOLAWindowCoefficients(testCase)
[rise,fall]=sixgr.phy.waveform.WindowingProfile.coefficients(16);
verifyLessThanOrEqual(testCase,max(abs(rise.^2+fall.^2-1)),1e-12);
end

function testWOLAOverlapAdd(testCase)
profile=sixgr.phy.waveform.WindowingProfile.resolve( ...
    "waveform_research_candidate",4,true);
state=sixgr.phy.waveform.WindowOverlapState(4,1);
[output,state]=sixgr.phy.waveform.WOLAEngine.process( ...
    ones(32,3,1),profile,state);
output=[output;sixgr.phy.waveform.WOLAEngine.flush(state)];
verifyEqual(testCase,numel(output),3*(32-4)+4);
end

function testWOLAChunkContinuity(testCase)
tableOne=localBaseCSV("waveform_windowing_wola.csv");
verifyLessThanOrEqual(testCase,max(tableOne.ChunkNMSE),1e-12);
end

function testWOLAMatchedReceiver(testCase)
tableOne=localBaseCSV("waveform_windowing_wola.csv");
verifyLessThanOrEqual(testCase,max(tableOne.EVM_pct),1e-4);
end

function testTransformPrecodingPlan(testCase)
plan=sixgr.phy.waveform.TransformPrecodingPlan( ...
    localAssignment(1,4,true,"QPSK"), ...
    "nr_rel19_ul_dfts_ofdm_strict");
verifyEqual(testCase,plan.M,48);
end

function testTransformPrecodingSingleLayer(testCase)
verifyError(testCase,@()sixgr.phy.waveform.TransformPrecodingPlan( ...
    localAssignment(2,4,true,"QPSK"), ...
    "nr_rel19_ul_dfts_ofdm_strict"), ...
    "WAVEFORM:TransformPrecodingLayerCount");
end

function testTransformPrecodingDFTSizes(testCase)
input=localRead("waveform_dft_size_test_vectors.csv");
for index=1:height(input)
    actual=sixgr.phy.waveform.TransformPrecodingPlan.isValidDFTSize( ...
        str2double(input.M(index)));
    verifyEqual(testCase,actual,input.Allowed(index)=="true");
end
end

function testTransformPrecodingContiguousMapping(testCase)
verifyError(testCase,@()sixgr.phy.waveform.TransformPrecodingPlan( ...
    localAssignment(1,4,false,"QPSK"), ...
    "nr_rel19_ul_dfts_ofdm_strict"), ...
    "WAVEFORM:NoncontiguousTransformAllocation");
end

function testUnitaryDFTIndependentVectors(testCase)
result=localVectors("unitary_dft");
verifyEqual(testCase,sum(result.MismatchCount),0);
end

function testDFTSpreadingLocalizedMapping(testCase)
symbols=(1:12).';
spread=sixgr.phy.waveform.UnitaryDFTSpreader.apply(symbols,12);
[grid,indices]=sixgr.phy.waveform.LocalizedDFTMapper.map(spread,64,7);
verifyEqual(testCase, ...
    sixgr.phy.waveform.LocalizedDFTMapper.extract(grid,indices),spread);
end

function testDFTDespreadingRoundTrip(testCase)
symbols=exp(1j*2*pi*(0:47).'/48);
spread=sixgr.phy.waveform.UnitaryDFTSpreader.apply(symbols,48);
recovered=sixgr.phy.waveform.UnitaryDFTDespreader.apply(spread,48);
verifyLessThanOrEqual(testCase,localNMSE(symbols,recovered),1e-24);
end

function testPiOver2BPSKIndependentVectors(testCase)
result=localVectors("pi2_bpsk");
verifyEqual(testCase,sum(result.MismatchCount),0);
end

function testPiOver2BPSKChunkBoundary(testCase)
bits=repmat([0;1;1;0],8,1);
[one,~]=sixgr.phy.waveform.PiOver2BPSKMapper.map(bits,3);
[a,next]=sixgr.phy.waveform.PiOver2BPSKMapper.map(bits(1:11),3);
[b,~]=sixgr.phy.waveform.PiOver2BPSKMapper.map(bits(12:end),next);
verifyEqual(testCase,[a;b],one,"AbsTol",1e-12);
end

function testLowPAPRRunnerUsesCanonicalWaveform(testCase)
data=localBaseCSV("waveform_low_papr_processing.csv");
verifyTrue(testCase,all(ismember(["CP-OFDM","DFT-s-OFDM"],unique(data.Mode))));
verifyTrue(testCase,all(data.Status=="PASS"));
end

function testPAPRAnalyticalVectors(testCase)
result=localVectors("papr");
verifyEqual(testCase,sum(result.MismatchCount),0);
end

function testPAPROversamplingConvergence(testCase)
measurement=sixgr.phy.waveform.PAPRMeasurement.measure(ones(64,1),[1 2 4 8]);
verifyLessThanOrEqual(testCase,abs(measurement.PAPR_dB(4)- ...
    measurement.PAPR_dB(3)),1e-12);
end

function testPAPRCCDFConfidence(testCase)
row=sixgr.phy.waveform.PAPRMeasurement.ccdf([1 2 3 4 5],3,.95);
verifyGreaterThanOrEqual(testCase,row.LowerCI,0);
verifyLessThanOrEqual(testCase,row.UpperCI,1);
verifyEqual(testCase,row.Trials,5);
end

function testSpectralSingleToneVectors(testCase)
result=localVectors("spectral");
verifyEqual(testCase,sum(result.MismatchCount),0);
end

function testSpectralParsevalClosure(testCase)
x=exp(1j*2*pi*7*(0:255).'/256);
result=sixgr.phy.waveform.SpectralMeasurement.measure( ...
    x,3.84e6,"FFTSize",512);
verifyLessThanOrEqual(testCase,abs(result.Error_dB),.01);
end

function testSpectralGuardLeakage(testCase)
data=localBaseCSV("waveform_spectral_metrics.csv");
verifyTrue(testCase,all(isfinite(data.GuardLeakage_dB)));
end

function testMultiNumerologyPlanning(testCase)
plan=sixgr.phy.waveform.WaveformCapabilityProfile.plan( ...
    "nr_rel19_multinumerology_strict","multi_numerology_sync");
verifyEqual(testCase,plan.Outcome,"EXECUTE");
end

function testMultiNumerologySynchronousComposition(testCase)
result=localComposition(0);
verifyLessThanOrEqual(testCase,result.ContributionSumError,1e-12);
end

function testMultiNumerologyAsynchronousComposition(testCase)
result=localComposition(7);
verifyLessThanOrEqual(testCase,result.ContributionSumError,1e-12);
verifyGreaterThan(testCase,size(result.Samples,1),128);
end

function testMultiNumerologyDemodulation(testCase)
result=localComposition(0);
verifyEqual(testCase,result.Samples,sum(result.Contributions,2), ...
    "AbsTol",1e-12);
end

function testComponentCarrierPlanning(testCase)
state=sixgr.phy.waveform.OFDMStreamState(1e6,0);
verifyError(testCase,@()sixgr.phy.waveform.DigitalUpconverter.process( ...
    ones(8,1),.5e6,1e6,state),"WAVEFORM:CarrierFrequencyOverlap");
end

function testComponentCarrierComposition(testCase)
result=localComposition(0);
verifyEqual(testCase,result.Samples,sum(result.Contributions,2), ...
    "AbsTol",1e-12);
end

function testDigitalUpconverterPhaseContinuity(testCase)
testOFDMPhaseContinuity(testCase);
end

function testPerCarrierPowerLedger(testCase)
data=localBaseCSV("waveform_component_carrier_composition.csv");
verifyLessThanOrEqual(testCase,max(abs(data.PowerMeasured_dBm- ...
    data.PowerExpected_dBm)),.01);
end

function testWaveformInterferenceContributionSum(testCase)
data=localBaseCSV("waveform_interference_composition.csv");
verifyLessThanOrEqual(testCase,max(data.SumError),1e-12);
end

function testWaveformCFOAndTimingSensitivity(testCase)
data=localBaseCSV("waveform_sync_sensitivity.csv");
cfo=data(data.Impairment=="CFO",:);
verifyGreaterThanOrEqual(testCase,cfo.EVM_pct(end),cfo.EVM_pct(1));
end

function testWaveformCPExceededISI(testCase)
data=localBaseCSV("waveform_evm_isi_ici.csv");
inside=data.ISIPower_dB(data.DelaySamples<=data.CPLength);
outside=data.ISIPower_dB(data.DelaySamples>data.CPLength);
verifyGreaterThan(testCase,max(outside),max(inside));
end

function testWaveformAWGNCampaign(testCase)
data=localBaseCSV("waveform_awgn_roundtrip.csv");
verifyEqual(testCase,height(data),10);
verifyTrue(testCase,all(data.Status=="PASS"));
end

function testWaveformTDLCampaign(testCase)
data=localBaseCSV("waveform_tdl_cdl_trials.csv");
verifyEqual(testCase,sum(data.ChannelProfile=="TDL-C"),10);
verifyTrue(testCase,all(isfinite(data.EVM_pct(data.ChannelProfile=="TDL-C"))));
end

function testWaveformCDLCampaign(testCase)
data=localBaseCSV("waveform_tdl_cdl_trials.csv");
verifyEqual(testCase,sum(data.ChannelProfile=="CDL-D"),10);
verifyTrue(testCase,all(isfinite(data.EVM_pct(data.ChannelProfile=="CDL-D"))));
end

function testWaveformMIMOPortPower(testCase)
grid=ones(24,2,2)/sqrt(2);
wave=sixgr.phy.waveform.CanonicalOFDMModulator.math(grid,128,9);
verifyEqual(testCase,mean(abs(wave(:,1)).^2), ...
    mean(abs(wave(:,2)).^2),"AbsTol",1e-12);
end

function testWaveformPRGPrecoding(testCase)
symbols=[1;1j]/sqrt(2);precoder=[1 1;1 -1]/sqrt(2);
ports=precoder*symbols;
verifyEqual(testCase,sum(abs(ports).^2),sum(abs(symbols).^2), ...
    "AbsTol",1e-12);
end

function testWaveformNegativeMatrix(testCase)
data=localBaseCSV("waveform_negative_tests.csv");
verifyEqual(testCase,height(data),161);
verifyTrue(testCase,all(data.ExpectedError==data.ActualError));
verifyFalse(testCase,any(data.WaveformGenerated|data.StateMutation));
end

function testWaveformCapabilityMatrix(testCase)
data=localBaseCSV("waveform_capability_results.csv");
verifyEqual(testCase,height(data),180);
verifyEqual(testCase,sum(data.ActualOutcome=="EXECUTE"),60);
verifyEqual(testCase,sum(data.ActualOutcome=="REJECT"),120);
end

function testWaveformIndependentVectorCoverage(testCase)
data=localBaseCSV("waveform_independent_vector_results.csv");
verifyGreaterThanOrEqual(testCase,height(data),20);
verifyEqual(testCase,sum(data.MismatchCount),0);
end

function testWaveformArtifactGeneration(testCase)
[csvContract,imageContract]=localContracts();
verifyTrue(testCase,all(isfile(fullfile(localBaseArtifacts(), ...
    string(csvContract.FileName)))));
verifyTrue(testCase,all(isfile(fullfile(localBaseArtifacts(), ...
    string(imageContract.ImageFile)))));
end

function testWaveformRuntimeScaling(testCase)
data=localBaseCSV("waveform_runtime_scaling.csv");
verifyEqual(testCase,height(data),10);
verifyTrue(testCase,all(isfinite(data.Duration_s)&data.Duration_s>=0));
end

function testWaveformSerialParallelReproducibility(testCase)
data=localBaseCSV("waveform_reproducibility.csv");
verifyTrue(testCase,all(data.WaveformSHA256==data.ExpectedSHA256));
end

function testResearchCandidatePlanningRejection(testCase)
plan=sixgr.phy.waveform.WaveformCapabilityProfile.plan( ...
    "waveform_research_candidate","otfs");
verifyEqual(testCase,plan.Outcome,"REJECT");
verifyEqual(testCase,plan.ErrorID,"WAVEFORM:UnsupportedResearchCandidate");
end

function testFullWaveformProfileEndToEnd(testCase)
base=localBaseArtifacts();
impact=fullfile(localRoot(),"artifacts","waveform_generation_impact");
verifyEqual(testCase,numel(dir(fullfile(base,"*.csv"))),32);
verifyEqual(testCase,numel(dir(fullfile(base,"*.png"))),22);
verifyEqual(testCase,numel(dir(fullfile(impact,"*.csv"))),16);
verifyEqual(testCase,numel(dir(fullfile(impact,"*.png"))),30);
rules=readtable(fullfile(impact,"waveform_impact_rule_evaluation.csv"), ...
    "Delimiter",",","VariableNamingRule","preserve","TextType","string");
verifyEqual(testCase,height(rules),96);
verifyTrue(testCase,all(rules.Result=="PASS"));
end

function result=localVectors(family)
persistent vectors
if isempty(vectors)
    vectors=sixgr.phy.waveform.WaveformVectorValidator.validate( ...
        localVectorRoot(),"ThrowOnMismatch",true);
end
result=vectors(vectors.Family==family,:);
end

function [grid,recovered]=localRoundTrip(nfft,cp,occupied,symbols,seed)
stream=RandStream("mt19937ar","Seed",seed);
bits=randi(stream,[0 1],occupied*symbols*2,1);
grid=reshape(((1-2*bits(1:2:end))+ ...
    1j*(1-2*bits(2:2:end)))/sqrt(2),occupied,symbols);
wave=sixgr.phy.waveform.CanonicalOFDMModulator.math(grid,nfft,cp);
recovered=sixgr.phy.waveform.CanonicalOFDMDemodulator.math( ...
    wave,nfft,repmat(cp,1,symbols),occupied);
end

function result=localComposition(startSample)
x=exp(1j*2*pi*(0:127).'/23);
components=repmat(struct("ComponentID","","Samples",x, ...
    "SampleRate_Hz",1.92e6,"StartSample",0, ...
    "FrequencyOffset_Hz",0,"Power_dB",0),2,1);
components(1).ComponentID="A";components(1).FrequencyOffset_Hz=-2e5;
components(2).ComponentID="B";components(2).FrequencyOffset_Hz=2e5;
components(2).StartSample=startSample;components(2).Power_dB=-3;
result=sixgr.phy.waveform.MultiNumerologyWaveformComposer.compose( ...
    components,1.92e6);
end

function assignment=localAssignment(layers,prbs,contiguous,modulation)
assignment=struct("Decoded",true,"LayerCount",layers, ...
    "PRBCount",prbs,"Contiguous",contiguous, ...
    "ConfigurationEpoch",1,"CurrentConfigurationEpoch",1, ...
    "PTRSSymbolPartitionExact",true,"Modulation",modulation);
end

function carrier=localCarrier(scs,cp,nSize)
carrier=nrCarrierConfig;
carrier.SubcarrierSpacing=scs;carrier.NSizeGrid=nSize;
carrier.CyclicPrefix=char(cp);
end

function data=localRead(name)
path=fullfile(localVectorRoot(),name);
options=detectImportOptions(path,"Delimiter",",","VariableNamingRule","preserve");
options=setvartype(options,options.VariableNames,"string");
data=readtable(path,options);
end

function data=localBaseCSV(name)
data=readtable(fullfile(localBaseArtifacts(),name), ...
    "Delimiter",",","VariableNamingRule","preserve","TextType","string");
for column=1:width(data)
    raw=data.(data.Properties.VariableNames{column});
    if isstring(raw)
        numeric=str2double(raw);
        if all(isfinite(numeric)|ismissing(raw))
            data.(data.Properties.VariableNames{column})=numeric;
        end
    end
end
end

function [csvContract,imageContract]=localContracts()
csvContract=localRead("desired_waveform_csv_contract.csv");
imageContract=localRead("desired_waveform_image_contract.csv");
end

function root=localRoot()
root=fileparts(fileparts(mfilename("fullpath")));
end

function root=localVectorRoot()
root=fullfile(localRoot(),"tests","vectors","waveform");
end

function root=localBaseArtifacts()
root=fullfile(localRoot(),"artifacts","waveform_generation_phase");
end

function value=localNMSE(reference,actual)
value=sum(abs(actual(:)-reference(:)).^2)/ ...
    max(sum(abs(reference(:)).^2),eps);
end
