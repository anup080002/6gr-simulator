function tests = testPDSCHReceiverMIMONoiseDomain
%TESTPDSCHRECEIVERMIMONOISEDOMAIN Guard pre/post-equalization noise domains.
tests = functiontests(localfunctions);
end

function testStaticMIMOReportsLayerDomainSINRAndNoise(testCase)
setup6GRSimToolkit("Verbose",false);
fixture = StrictPDSCHChainFixture.create(2,"NPRB",4);
tx = sixgr.pdsch.PDSCHTransmitter( ...
    fixture.TransportBlocks,fixture.Assignment,fixture.ResourcePlan, ...
    fixture.Carrier,fixture.ReferenceConfig, ...
    "PrecoderBundle",fixture.PrecoderBundle);
H = diag([2.0,1.5]);
gridNoiseVariance = 1e-2;
timeNoiseVariance = gridNoiseVariance/double( ...
    tx.OFDMInfo.SampleToGridNoiseVarianceGain);
rng(11927,"twister");
noise = sqrt(timeNoiseVariance/2)*complex( ...
    randn(size(tx.Waveform,1),2),randn(size(tx.Waveform,1),2));
receiver = rmfield(fixture.ReceiverConfig,"ReferenceChannelGain");
receiver.ChannelModel = "STATIC-MIMO";
receiver.NPhysicalRxAntennas = 2;
receiver.NoiseVariance = gridNoiseVariance;
rx = sixgr.pdsch.PDSCHReceiver( ...
    tx.Waveform*H.'+noise,fixture.Assignment,fixture.ResourcePlan, ...
    fixture.Carrier,fixture.ReferenceConfig,receiver, ...
    "CodingPlans",tx.CodingPlans,"PrecoderBundle",fixture.PrecoderBundle);

measured = double(rx.Metrics.MeasuredPostEqualizationSINRdBPerLayer);
receivedGrid = reshape(rx.OFDMGrid,[],size(rx.OFDMGrid,3));
verifyEqual(testCase,rx.PreEqualizationRxSymbols, ...
    receivedGrid(double(rx.ResourcePlan.DataIndices)+1,:));
verifySize(testCase,rx.PreEqualizationRxSymbols, ...
    [double(rx.ResourcePlan.ExactDataRECount),2]);
expected = 10*log10(abs(diag(H)).^2/gridNoiseVariance).';
verifyEqual(testCase,measured,expected,"AbsTol",2.0);
verifyLessThan(testCase,double(rx.NoiseVarianceUsedForLLR), ...
    gridNoiseVariance);
verifyEqual(testCase,string(rx.EqualizationInfo.EngineUsed), ...
    "canonical_equalizeMMSE_unit_desired_gain");
verifySize(testCase, ...
    rx.EqualizationInfo.PostEqualizationNoiseVariancePerResourceLayer, ...
    [double(rx.ResourcePlan.ExactDataRECount),2]);
equalizerResult = rx.EqualizationInfo.EqualizerResult;
verifyEqual(testCase,string(equalizerResult.ContractVersion), ...
    "PDSCHResourceSelectiveEqualizerResult/v1");
verifySize(testCase,equalizerResult.W, ...
    [double(rx.ResourcePlan.ExactDataRECount),2,2]);
verifySize(testCase,equalizerResult.EffectiveResponseWH, ...
    [double(rx.ResourcePlan.ExactDataRECount),2,2]);
verifySize(testCase,equalizerResult.PostEqSINRPerRE_dB, ...
    [double(rx.ResourcePlan.ExactDataRECount),2]);
verifyTrue(testCase,all(isfinite(real(equalizerResult.W(:)))) && ...
    all(isfinite(imag(equalizerResult.W(:)))) && ...
    all(isfinite(equalizerResult.PostEqSINRPerRE_dB(:))), ...
    "The production PDSCH receiver must retain finite exact applied weights and per-RE SINR.");
appliedSymbols = localApplyEqualizerWeights( ...
    equalizerResult.W,rx.DataPortSymbols.');
verifyEqual(testCase,appliedSymbols,equalizerResult.EqualizedSymbols, ...
    "AbsTol",1e-12, ...
    "Published PDSCH equalizer weights must reproduce the symbols consumed by the demapper.");
verifyTrue(testCase,logical(rx.CRCPass));
end

function testDecisionResidualBoundsUnmodelledDataDomainDistortion(testCase)
% The bound must be produced from received equalized symbols, not from Tx
% bits or an injected truth channel.  Keep DM-RS clean and add deterministic
% distortion only on scheduled data REs so the raw estimator/equalizer
% variance is deliberately over-optimistic.
setup6GRSimToolkit("Verbose",false);
fixture = StrictPDSCHChainFixture.create(1,"NPRB",4);
tx = sixgr.pdsch.PDSCHTransmitter( ...
    fixture.TransportBlocks,fixture.Assignment,fixture.ResourcePlan, ...
    fixture.Carrier,fixture.ReferenceConfig);
distortedGrid = tx.Grid;
% Resource-plan indices are deliberately zero-based for standards-domain
% auditability.  Convert the transmitter's exact data allocation to MATLAB
% subscripts exactly as PDSCHTransmitter.localMapPortSymbols does.
dataIndices = double(tx.ResourcePlan.DataIndices(:)) + 1;
dataSymbols = distortedGrid(dataIndices);
phase = exp(1i*0.16*sin((1:numel(dataSymbols)).'*sqrt(2)));
distortedGrid(dataIndices) = dataSymbols .* phase;
distortedWaveform = nrOFDMModulate(tx.Carrier,distortedGrid);

receiver = fixture.ReceiverConfig;
receiver.NoiseVariance = 1e-10;
rx = sixgr.pdsch.PDSCHReceiver( ...
    distortedWaveform,fixture.Assignment,fixture.ResourcePlan, ...
    fixture.Carrier,fixture.ReferenceConfig,receiver, ...
    "CodingPlans",tx.CodingPlans, ...
    "EnableDecisionDirectedPostEqSINRBound",true);

raw = double(rx.PostEqSINRRawEqualizerPerLayer_dB);
bounded = double(rx.Metrics.MeasuredPostEqualizationSINRdBPerLayer);
residual = rx.DecisionDirectedPostEqualizationResidual;
verifyTrue(testCase,logical(residual.Available));
verifyTrue(testCase,logical(rx.PostEqSINRDecisionResidualBoundApplied));
verifyLessThan(testCase,bounded,raw);
verifyEqual(testCase,bounded,double(residual.SINRdBPerLayer), ...
    "AbsTol",1e-10);
minimumResidualVariance = min(double(residual.NoiseVariancePerLayer));
roundoff = 10 * eps(max(1,abs(minimumResidualVariance)));
verifyGreaterThanOrEqual(testCase,double(rx.NoiseVarianceUsedForLLR), ...
    minimumResidualVariance - roundoff);
verifyEqual(testCase,string(residual.Source), ...
    "canonical_pdsch_decision_directed_post_equalization_residual");
end

function testZeroNoiseModelBoundaryDoesNotAbortDecodedEvidence(testCase)
setup6GRSimToolkit('Verbose',false);
fixture=StrictPDSCHChainFixture.create(1,'NPRB',4);
tx=sixgr.pdsch.PDSCHTransmitter(fixture.TransportBlocks,fixture.Assignment, ...
    fixture.ResourcePlan,fixture.Carrier,fixture.ReferenceConfig);
receiver=rmfield(fixture.ReceiverConfig,'ReferenceChannelGain');
receiver.ChannelModel='STATIC-MIMO'; receiver.NoiseVariance=0;
rx=sixgr.pdsch.PDSCHReceiver(tx.Waveform,fixture.Assignment,fixture.ResourcePlan, ...
    fixture.Carrier,fixture.ReferenceConfig,receiver,'CodingPlans',tx.CodingPlans);
verifyTrue(testCase,rx.CRCPass);
verifyEqual(testCase,rx.TransportBlocks,fixture.TransportBlocks);
verifyEqual(testCase,rx.EqualizationInfo.DisturbanceCovariance,0);
verifyEqual(testCase,rx.EqualizationInfo.PreEqualizationNoiseVariance,0);
verifyEqual(testCase,rx.Metrics.MeasuredPostEqualizationSINRdBPerLayer,Inf);
verifyEqual(testCase,rx.Metrics.PostEqualizationSINRValueStatusPerLayer,"unavailable");
verifyEqual(testCase,rx.Metrics.PostEqualizationSINRNAReasonPerLayer, ...
    "nonfinite_post_equalization_model_boundary");
verifyTrue(testCase,all(isfinite(rx.Metrics.EVMPerCodeword)));
verifyEqual(testCase,rx.EqualizationInfo.EqualizerResult.PostEqSINRLinear, ...
    Inf(rx.EqualizationInfo.EqualizerResult.NRE,1));
end

function symbols = localApplyEqualizerWeights(weights, received)
weights = complex(double(weights));
received = complex(double(received));
nRE = size(weights,1);
nLayers = size(weights,2);
nRx = size(weights,3);
assert(size(received,1) == nRE && size(received,2) == nRx, ...
    "Receiver evidence dimensions do not match the equalizer contract.");
symbols = complex(zeros(nRE,nLayers));
for re = 1:nRE
    for layer = 1:nLayers
        symbols(re,layer) = reshape(weights(re,layer,:),1,nRx) * ...
            reshape(received(re,:),nRx,1);
    end
end
end

function testCoupledLayersRetainExecutedInterference(testCase)
setup6GRSimToolkit('Verbose',false);
fixture=StrictPDSCHChainFixture.create(2,'NPRB',4);
tx=sixgr.pdsch.PDSCHTransmitter(fixture.TransportBlocks,fixture.Assignment, ...
    fixture.ResourcePlan,fixture.Carrier,fixture.ReferenceConfig, ...
    'PrecoderBundle',fixture.PrecoderBundle);
H=[1 .65;.25 1]; variance=.05;
stream=RandStream('mt19937ar','Seed',48119);
noise=sqrt(variance/(2*tx.OFDMInfo.SampleToGridNoiseVarianceGain))* ...
    complex(randn(stream,size(tx.Waveform)),randn(stream,size(tx.Waveform)));
receiver=rmfield(fixture.ReceiverConfig,'ReferenceChannelGain');
receiver.ChannelModel='STATIC-MIMO'; receiver.NPhysicalRxAntennas=2;
receiver.NoiseVariance=variance;
rx=sixgr.pdsch.PDSCHReceiver(tx.Waveform*H.'+noise,fixture.Assignment, ...
    fixture.ResourcePlan,fixture.Carrier,fixture.ReferenceConfig,receiver, ...
    'CodingPlans',tx.CodingPlans,'PrecoderBundle',fixture.PrecoderBundle);
eq=rx.EqualizationInfo.EqualizerResult;
e=sixgr.phy.rx.interLayerEvidence(eq);
verifyGreaterThan(testCase,min(e.ResidualInterLayerPowerPerLayer),0);
% Independently reconstruct SINR's inter-layer + disturbance denominator
% from the exact applied weights, not a second fitted channel/noise value.
C=rx.EqualizationInfo.DisturbanceCovariance;
residual=zeros(eq.NRE,2);
for re=1:eq.NRE
    W=reshape(eq.W(re,:,:),2,2);
    A=reshape(eq.EffectiveResponseWH(re,:,:),2,2);
    for layer=1:2
        other=3-layer;
        residual(re,layer)=abs(A(layer,other))^2/abs(A(layer,layer))^2;
        total=residual(re,layer)+real(W(layer,:)*C*W(layer,:)');
        verifyEqual(testCase,1/eq.PostEqSINRLinear(re,layer),total,'AbsTol',1e-10);
    end
end
verifyEqual(testCase,e.ResidualInterLayerPowerPerLayer,mean(residual,1),'AbsTol',1e-12);
% The DL and UL schedulers must receive the same explicitly declared
% wideband reduction of the *executed* per-RE equalizer SINR. Summing
% powers before unit-gain normalization instead weights weak REs
% differently from the symbols that the decoder actually consumed.
expectedWideband=mean(10*log10(eq.PostEqSINRLinear),1);
verifyEqual(testCase,rx.PostEqSINRRawEqualizerPerLayer_dB, ...
    expectedWideband,'AbsTol',1e-10);
end
