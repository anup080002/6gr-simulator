function ok=testPDCCHQualificationNoiseReference()
% Physical noise checks, not a claim of statistical detector qualification.
setup6GRSimToolkit('Verbose',false);
for nrb=[24 273]
    carrier=nrCarrierConfig('NSizeGrid',nrb,'SubcarrierSpacing',30);
    sparse=nrResourceGrid(carrier,4); sparse(1:72,1:2,:)=1;
    dense=ones(size(sparse));
    sparseWave=nrOFDMModulate(carrier,sparse);
    denseWave=nrOFDMModulate(carrier,dense);
    stream=RandStream('Threefry','Seed',20261015); stream.Substream=19;
    before=rng;
    [rx,meta,noise]=sixgr.phy.waveform.addOccupiedREAWGN( ...
        sparseWave,carrier,7.5,'Stream',stream,'SignalEnergyPerOccupiedRE',.25);
    assert(isequal(before,rng) && meta.CallerGlobalRNGStatePreserved);
    assert(isequal(rx,sparseWave+noise) && meta.Substream==19);
    stream.Substream=19;
    [~,denseMeta,denseNoise]=sixgr.phy.waveform.addOccupiedREAWGN( ...
        denseWave,carrier,7.5,'Stream',stream,'SignalEnergyPerOccupiedRE',.25);
    assert(isequal(noise,denseNoise) && ...
        meta.SampleNoiseVariance==denseMeta.SampleNoiseVariance, ...
        'Sparse/full allocations must not change the declared reference noise.');
    native=nrOFDMDemodulate(carrier,noise);
    actualVariance=mean(abs(native(:)).^2);
    target=.25*10^(-7.5/10);
    assert(abs(10*log10(actualVariance/target))<.2, ...
        'Independent native demodulation disagrees with occupied-RE noise.');
    info=nrOFDMInfo(carrier);
    assert(abs(meta.SampleNoiseVariance-target/info.Nfft)<1e-13);
    stream.Substream=20;
    [~,~,other]=sixgr.phy.waveform.addOccupiedREAWGN(sparseWave,carrier,7.5,'Stream',stream);
    assert(~isequal(other,noise));
    try
        sixgr.phy.waveform.addOccupiedREAWGN(sparseWave,carrier,7.5,'Stream',stream,'Seed',1);
        error('test:ExpectedError','Ambiguous random stream was accepted.');
    catch cause
        assert(string(cause.identifier)=="sixgr:phy:waveform:AmbiguousNoiseStream");
    end
    fprintf('PDCCH_NOISE_REFERENCE nrb=%d error_dB=%.9g density_invariant=1\n', ...
        nrb,10*log10(actualVariance/target));
end
b=pdcchStrictAnchorResult();
for oracle=["NoiseVar","NoiseOnlyWaveform"]
    try
        sixgr.phy.pdcch.blindDecodePDCCH(complex(zeros(20,1)),b.Config,oracle,1e-6);
        error('test:ExpectedOracleRejection','Strict receiver accepted an injected-noise oracle.');
    catch cause
        assert(string(cause.identifier)=="sixgr:phy:pdcch:OracleNoiseInputForbidden");
    end
end
T=b.Result.ArtifactTables.pdcch_trials;
assert(all(T.NoiseCalibrationSource=="sixgr.phy.waveform.addOccupiedREAWGN"));
assert(all(T.SNRReferencePlane=="occupied_resource_grid_re_pre_equalization"));
assert(all(~T.GeneratedNoiseSuppliedToReceiver));
assert(~any(contains(T.ReceiverNoiseVarianceSource,["noise_only_waveform","override"])));
assert(all(abs(T.AppliedGridNoiseVariance./T.SignalEnergyPerOccupiedRE - 10.^(-T.SNRdB/10))<1e-13));
assert(all(abs(T.AppliedSampleNoiseVariance.*T.SampleToGridNoiseVarianceGain - T.AppliedGridNoiseVariance)<1e-13));
assert(all(T.ScoringNoiseComparedRECount>0));
assert(all(abs(10*log10(T.ScoringMeasuredGridNoiseVariance./T.AppliedGridNoiseVariance))<.3));
assert(all(T.StrictOk(ismember(T.TrialType,["positive_dci_1_0","positive_dci_0_0"]))));
assert(all(T.NegativeExpectedOk(ismember(T.TrialType,["wrong_rnti","no_signal_coreset"]))));
assert(~b.Result.StatisticallyQualified, ...
    'A bounded physical mini-anchor cannot establish detector qualification.');
ok=true;
fprintf('PDCCH_QUALIFICATION_NOISE_REFERENCE_PASS practical_receiver=1\n');
end
