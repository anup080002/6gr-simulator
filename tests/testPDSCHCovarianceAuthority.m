function ok=testPDSCHCovarianceAuthority()
% Actual coded RX test, not a full-band or statistical performance claim.
% The 100-MHz sampling clock carries a bounded six-PRB allocation. Changing
% waveform units must not change decoded bits, layer symbols or model SINR.
setup6GRSimToolkit('Verbose',false);
fixture=StrictPDSCHChainFixture.create(2,'NPRB',6, ...
    'OFDMOptions',{'Nfft',4096,'SampleRate',122.88e6});
tx=sixgr.pdsch.PDSCHTransmitter(fixture.TransportBlocks,fixture.Assignment, ...
    fixture.ResourcePlan,fixture.Carrier,fixture.ReferenceConfig, ...
    'PrecoderBundle',fixture.PrecoderBundle);
H=[1 .35i;.2 1.3]; variance=.02;
R=[.04 .01i;-.01i .03];
stream=RandStream('mt19937ar','Seed',89231);
noise=sqrt(variance/(2*tx.OFDMInfo.SampleToGridNoiseVarianceGain))* ...
    complex(randn(stream,size(tx.Waveform)),randn(stream,size(tx.Waveform)));
waveform=tx.Waveform*H.'+noise;
receiver=rmfield(fixture.ReceiverConfig,'ReferenceChannelGain');
receiver.ChannelModel='STATIC-MIMO'; receiver.NPhysicalRxAntennas=2;
cases=0;
for includesNoise=[false true]
    baseline=[];
    for scale=[1 1e-3 1e-9]
        rxConfig=receiver; rxConfig.NoiseVariance=scale^2*variance;
        rx=sixgr.pdsch.PDSCHReceiver(scale*waveform,fixture.Assignment, ...
            fixture.ResourcePlan,fixture.Carrier,fixture.ReferenceConfig,rxConfig, ...
            'CodingPlans',tx.CodingPlans,'PrecoderBundle',fixture.PrecoderBundle, ...
            'InterferenceCovariance',scale^2*R, ...
            'InterferenceCovarianceIncludesNoise',includesNoise);
        expected=scale^2*(R+double(~includesNoise)*variance*eye(2));
        actual=rx.EqualizationInfo.DisturbanceCovariance;
        assert(norm(actual-expected,'fro')<1e-12*norm(expected,'fro'), ...
            'test:PDSCHPhysicalCovarianceModified', ...
            'The receiver must not replace physical covariance eigenvalues with an absolute numerical floor.');
        assert(rx.EqualizationInfo.PreEqualizationNoiseVariance==scale^2*variance, ...
            'test:PDSCHPhysicalNoiseModified','Preserve supplied noise in its actual grid units.');
        eq=rx.EqualizationInfo.EqualizerResult;
        reconstructed=complex(zeros(size(rx.LayerSymbols)));
        for re=1:eq.NRE
            W=reshape(eq.W(re,:,:),2,2);
            A=reshape(eq.EffectiveResponseWH(re,:,:),2,2);
            reconstructed(re,:)=(W*rx.PreEqualizationRxSymbols(re,:).').';
            for layer=1:2
                denominator=abs(A(layer,3-layer))^2+real(W(layer,:)*actual*W(layer,:)');
                assert(abs(1/eq.PostEqSINRLinear(re,layer)-denominator) ...
                    <1e-10*denominator);
            end
        end
        assert(norm(reconstructed-rx.LayerSymbols,'fro')<1e-11*norm(rx.LayerSymbols,'fro'), ...
            'Published weights must reproduce the actual demapper symbols.');
        if isempty(baseline)
            baseline=rx;
        else
            assert(norm(rx.LayerSymbols-baseline.LayerSymbols,'fro') ...
                <1e-8*norm(baseline.LayerSymbols,'fro'));
            assert(max(abs(rx.PostEqSINRRawEqualizerPerLayer_dB- ...
                baseline.PostEqSINRRawEqualizerPerLayer_dB))<1e-7);
            assert(isequal(rx.CRCPass,baseline.CRCPass) && ...
                isequal(rx.TransportBlocks,baseline.TransportBlocks));
        end
        cases=cases+1;
    end
end
for covariance={diag([1 -.1]),[1 2;0 1]}
    rxConfig=receiver; rxConfig.NoiseVariance=variance;
    rejected=false;
    try
        sixgr.pdsch.PDSCHReceiver(waveform,fixture.Assignment,fixture.ResourcePlan, ...
            fixture.Carrier,fixture.ReferenceConfig,rxConfig,'CodingPlans',tx.CodingPlans, ...
            'PrecoderBundle',fixture.PrecoderBundle, ...
            'InterferenceCovariance',covariance{1}, ...
            'InterferenceCovarianceIncludesNoise',true);
    catch failure
        rejected=contains(string(failure.identifier),'Covariance');
        assert(rejected,'Unexpected failure: %s',failure.identifier);
    end
    assert(rejected,'test:PDSCHInvalidCovarianceAccepted', ...
        'Non-Hermitian or indefinite disturbance matrices must fail, not be silently repaired.');
end
for flag={NaN,-1,2,1i,[0 1],[false true]}
    rejected=false;
    try
        sixgr.pdsch.PDSCHReceiver(waveform,fixture.Assignment,fixture.ResourcePlan, ...
            fixture.Carrier,fixture.ReferenceConfig,receiver,'CodingPlans',tx.CodingPlans, ...
            'PrecoderBundle',fixture.PrecoderBundle,'InterferenceCovariance',R, ...
            'InterferenceCovarianceIncludesNoise',flag{1});
    catch failure
        rejected=strcmp(failure.identifier, ...
            'sixgr:pdsch:PDSCHReceiver:InvalidNoiseInclusionFlag');
        assert(rejected,'Unexpected failure: %s',failure.identifier);
    end
    assert(rejected,'test:PDSCHInvalidNoiseFlagAccepted', ...
        'Invalid noise inclusion flags must not be converted to logical true.');
end
ok=true;
fprintf('PDSCH_COVARIANCE_AUTHORITY_PASS scale_cases=%d negative_cases=8\n',cases);
end
