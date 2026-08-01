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
