function tests = testPDSCHReceiverAWGNNoiseDomain
%TESTPDSCHRECEIVERAWGNNOISEDOMAIN Guard the grid-to-layer noise transform.
tests = functiontests(localfunctions);
end

function testScaledAWGNChannelReportsReceiverDerivedSINR(testCase)
setup6GRSimToolkit("Verbose",false);
fixture = StrictPDSCHChainFixture.create(1);
tx = sixgr.pdsch.PDSCHTransmitter( ...
    fixture.TransportBlocks,fixture.Assignment,fixture.ResourcePlan, ...
    fixture.Carrier,fixture.ReferenceConfig, ...
    "PrecoderBundle",fixture.PrecoderBundle);
channelGain = 9*exp(1j*0.37);
snrPoints = [-20 0 20];
measuredPoints = nan(size(snrPoints));
rng(9200,"twister");
unitNoise = complex(randn(size(tx.Waveform)),randn(size(tx.Waveform)))/sqrt(2);
for index = 1:numel(snrPoints)
    gridNoiseVariance = abs(channelGain)^2/10^(snrPoints(index)/10);
    timeNoiseVariance = gridNoiseVariance/ ...
        double(tx.OFDMInfo.SampleToGridNoiseVarianceGain);
    noise = sqrt(timeNoiseVariance)*unitNoise;
    receiver = fixture.ReceiverConfig;
    receiver.NoiseVariance = gridNoiseVariance;
    rx = sixgr.pdsch.PDSCHReceiver( ...
        channelGain*tx.Waveform+noise,fixture.Assignment, ...
        fixture.ResourcePlan,fixture.Carrier,fixture.ReferenceConfig, ...
        receiver,"CodingPlans",tx.CodingPlans, ...
        "PrecoderBundle",fixture.PrecoderBundle);
    measured = double( ...
        rx.Metrics.MeasuredPostEqualizationSINRdBPerLayer);
    receivedGrid = reshape(rx.OFDMGrid,[],size(rx.OFDMGrid,3));
    expectedReceived = receivedGrid(double(rx.ResourcePlan.DataIndices)+1,:);
    verifyEqual(testCase,rx.PreEqualizationRxSymbols,expectedReceived);
    verifyEqual(testCase,string(rx.PreEqualizationSymbolDomain),"received_data_RE_by_RX_antenna");
    verifyGreaterThan(testCase,norm(rx.PreEqualizationRxSymbols(:)-rx.LayerSymbols(:)),1, ...
        "A nine-fold channel gain must not be removed from the raw pre-EQ evidence.");
    measuredPoints(index) = mean(measured,"omitnan");
    estimatedGain = double(rx.ChannelGainPerPhysicalPort);
    expectedMeasured = 10*log10( ...
        abs(estimatedGain)^2/double(rx.EstimatedNoiseVariance));
    expectedDecoderNoise = gridNoiseVariance/abs(estimatedGain)^2;
    verifyEqual(testCase,measured,expectedMeasured,"AbsTol",1e-10);
    verifyEqual(testCase,double(rx.NoiseVarianceUsedForLLR), ...
        expectedDecoderNoise,"RelTol",1e-10);
    verifyNotEqual(testCase,double(rx.NoiseVarianceUsedForLLR), ...
        gridNoiseVariance);
    verifyEqual(testCase,string(rx.Source), ...
        "explicit_pdsch_dlsch_production_receiver");
end
verifyGreaterThan(testCase,diff(measuredPoints),[8 8], ...
    "Receiver-derived post-equalization SINR must be monotonic across [-20,0,20] dB.");
verifyGreaterThan(testCase,measuredPoints(end),10, ...
    "A clean +20 dB AWGN decode must not report a negative post-equalization SINR.");
end

function testPRGPrecoderRetainsPerREWidebandReduction(testCase)
setup6GRSimToolkit('Verbose',false);
f=StrictPDSCHChainFixture.create(2,'NPRB',4);
W=cat(3,eye(2),[1 1;1 -1]/sqrt(2));
spec=struct('Mode',"prg_noncodebook",'NPorts',2,'NLayers',2, ...
    'NPRG',2,'NSymbolGroups',1,'PRGSize',2,'PRBSet',0:3, ...
    'ScheduledSymbols',0:13,'SymbolGroupMap',zeros(1,14),'W',W, ...
    'MatrixSource',"independent_test_matrices",'CodebookIdentifier',"", ...
    'NormalizationConvention',"semi_unitary");
bundle=sixgr.pdsch.PDSCHPrecoderBundle(spec);
tx=sixgr.pdsch.PDSCHTransmitter(f.TransportBlocks,f.Assignment, ...
    f.ResourcePlan,f.Carrier,f.ReferenceConfig,'PrecoderBundle',bundle);
stream=RandStream('mt19937ar','Seed',67231);
variance=.001;
noise=sqrt(variance/(2*tx.OFDMInfo.SampleToGridNoiseVarianceGain))* ...
    complex(randn(stream,size(tx.Waveform)),randn(stream,size(tx.Waveform)));
receiver=rmfield(f.ReceiverConfig,'ReferenceChannelGain');
receiver.NoiseVariance=variance;
rx=sixgr.pdsch.PDSCHReceiver(tx.Waveform*diag([2 .4])+noise, ...
    f.Assignment,f.ResourcePlan,f.Carrier,f.ReferenceConfig,receiver, ...
    'CodingPlans',tx.CodingPlans,'PrecoderBundle',bundle);
portNoise=rx.EstimatedNoiseVariance./abs(rx.ChannelGainPerPhysicalPort(:)).^2;
indices=double(f.ResourcePlan.DataIndices(:));
prb=floor(mod(indices,48)/12); sym=floor(indices/48);
denominator=zeros(numel(indices),2);
for re=1:numel(indices)
    inverse=bundle.slice(prb(re),sym(re))\eye(2);
    denominator(re,:)=real(diag(inverse*diag(portNoise)*inverse')).';
end
expected=mean(10*log10(1./denominator),1);
verifyEqual(testCase,rx.PostEqSINRRawEqualizerPerLayer_dB,expected,'AbsTol',1e-10);
verifyEqual(testCase,rx.PostEqSINRRawReduction,"mean_dB_over_data_RE_then_layers");
verifyGreaterThan(testCase,max(abs(expected-10*log10(1./mean(denominator,1)))),.1);
verifyTrue(testCase,rx.CRCPass);
end
