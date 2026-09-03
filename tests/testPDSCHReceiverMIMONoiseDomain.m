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
expected = 10*log10(abs(diag(H)).^2/gridNoiseVariance).';
verifyEqual(testCase,measured,expected,"AbsTol",2.0);
verifyLessThan(testCase,double(rx.NoiseVarianceUsedForLLR), ...
    gridNoiseVariance);
verifyEqual(testCase,string(rx.EqualizationInfo.EngineUsed), ...
    "explicit_unbiased_layer_domain_lmmse");
verifySize(testCase, ...
    rx.EqualizationInfo.PostEqualizationNoiseVariancePerResourceLayer, ...
    [double(rx.ResourcePlan.ExactDataRECount),2]);
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
