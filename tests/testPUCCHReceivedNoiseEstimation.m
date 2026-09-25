function ok=testPUCCHReceivedNoiseEstimation()
% Actual PUCCH codecs and retained RX RF. The typed control contexts and
% analytic connector are UNIT fixtures, not a completed main TDD scenario.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios','lls_causal_access_to_data_wiring_tdd.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
cfg.rf.rx.agc.enable=true; cfg.rf.rx.agc.targetRms=.2;
cfg.rf.rx.agc.minGain_dB=-80; cfg.rf.rx.agc.maxGain_dB=80;
cfg.rf.adc.enable=true; cfg.rf.adcBits=12; cfg.rf.adc.fullScale=1;
cfg.rf.rx.cfo_Hz=0; cfg.rf.rx.timingOffsetSamples=0;
cfg.rf.rx.phaseNoise.enable=false;
random=RandStream('Threefry','Seed',4702601);
callerRNG=rng;
for format=1:4
    f=sixgr.phy.pucch.PUCCHFixtureFactory.connected(format,[]);
    tx=sixgr.phy.pucch.PUCCHTransmitter.transmit(f.Carrier,f.Assignment,f.Report);
    % Complex unequal branch gains are unknown to the receiver. Even with
    % an AWGN propagation profile it must estimate this post-RF channel.
    desired=tx.Waveform*[.013+.004i .009-.006i];
    [energy,~]=sixgr.phy.waveform.measureReceivedOccupiedREEnergy( ...
        f.Carrier,desired,tx.PUCCHIndices,'SignalFamily','PUCCH');
    [~,ofdm]=sixgr.phy.waveform.ofdmDemodulate(f.Carrier,desired);
    gain=sixgr.phy.waveform.convertNoiseVarianceToGridDomain(1,ofdm,'InputDomain','sample');
    sampleVariance=energy/10^(12/10)/gain;
    noise=sqrt(sampleVariance/2)*(randn(random,size(desired))+1i*randn(random,size(desired)));
    input=desired+noise;
    front=sixgr.rf.runtime.RFImpairmentStream(cfg,'rx','UL', ...
        tx.OFDMInfo.SampleRate,2,0,1,false);
    output=front.apply(sixgr.phy.waveform.WaveformChunk(input,0),1);
    assert(output.Replay.RFAppliedStageCount>0 && output.Replay.AGCDecisionCausal);
    args={'NoiseVariance',NaN,'NoiseVarianceMode','received_dmrs_estimate', ...
        'ChannelProfile','AWGN'};
    rx=sixgr.phy.pucch.PUCCHReceiver.receive(output.Waveform, ...
        f.Carrier,f.Assignment,f.Context,args{:});
    decoded=[rx.DecodedSequence1;rx.DecodedSequence2];
    expected=[tx.Serialization.Sequence1.Bits;tx.Serialization.Sequence2.Bits];
    assert(rx.ReceiverUsable && rx.CRCPassed && isequal(decoded,expected), ...
        'PUCCH Format %d actual received UCI failed.',format);
    assert(isnan(rx.SampleNoiseVariance) && rx.GridNoiseVariance>0 && ...
        isfinite(rx.GridNoiseVariance) && rx.ChannelEstimateApplicable && ...
        string(rx.GridNoiseVarianceSource)=="received_pucch_dmrs_noise_plus_residual_estimate");
    assert(~rx.OraclePayloadBitsUsed && ~isscalar(rx.ChannelEstimate));
    if format==2
        [llr,likelihood]=sixgr.phy.pucch.demapFormat2EqualizerOutput( ...
            f.Carrier,f.Assignment.Resource.toolboxConfig(),rx.EqualizerInfo.EqualizerResult);
        corrected=sixgr.phy.pucch.UCIDecoder.decode(llr,f.Context.Sequence1Length+f.Context.Sequence2Length);
        assert(isequal(corrected.Bits,expected) && corrected.CRCPassed && ...
            ~likelihood.TransmittedBitsUsed && ~likelihood.MeanVarianceUsed);
        fprintf('PUCCH_FORMAT2_GAIN_AWARE_AGC_ADC_PASS receive_branches=2 estimated_channel=1\n');
    end
    localReject(@()sixgr.phy.pucch.PUCCHReceiver.receive(output.Waveform, ...
        f.Carrier,f.Assignment,f.Context,args{:},'InterferenceCovariance',eye(2)), ...
        'sixgr:phy:pucch:OverlappingDisturbanceAuthorities');
    % A declared sample covariance retains its own thermal variance. A
    % received pilot residual cannot be added to that covariance again.
    provided=2e-5; covariance=3e-5*eye(2);
    known=sixgr.phy.pucch.PUCCHReceiver.receive(input,f.Carrier, ...
        f.Assignment,f.Context,'NoiseVariance',provided, ...
        'InterferenceCovariance',covariance,'ChannelProfile','TDL-C');
    assert(abs(known.GridNoiseVariance-provided*gain)<1e-12*provided*gain);
    assert(string(known.GridNoiseVarianceSource)=="provided_variance_converted_to_resource_grid");
    % No covariance is still an explicit provided-variance policy. Cover
    % both sample conversion and already-grid input without replacing either
    % with an unrelated pilot residual. This checks authority, not ACK rate.
    for domain=["sample","grid"]
        supplied=provided;
        if domain=="grid", supplied=provided*gain; end
        explicit=sixgr.phy.pucch.PUCCHReceiver.receive(input,f.Carrier, ...
            f.Assignment,f.Context,'NoiseVariance',supplied, ...
            'NoiseVarianceDomain',domain,'NoiseVarianceMode','provided', ...
            'ChannelProfile','TDL-C');
        expectedGrid=provided*gain;
        assert(abs(explicit.GridNoiseVariance-expectedGrid)<1e-12*expectedGrid);
        assert(abs(explicit.EffectiveGridNoiseInterferenceVariance-expectedGrid)<1e-12*expectedGrid);
        assert(string(explicit.GridNoiseVarianceSource)=="provided_variance_converted_to_resource_grid");
        assert(isempty(explicit.InterferenceCovariance) && ~explicit.OraclePayloadBitsUsed);
        assert(abs(explicit.EqualizerInfo.EqualizerResult.PreEqualizationNoiseVariance-expectedGrid)<1e-12*expectedGrid);
    end
    fprintf('PASS PUCCH Format %d: actual UCI decode after retained AGC/ADC; received DM-RS variance %.8g.\n', ...
        format,rx.GridNoiseVariance);
end
f=sixgr.phy.pucch.PUCCHFixtureFactory.connected(0,[]);
tx=sixgr.phy.pucch.PUCCHTransmitter.transmit(f.Carrier,f.Assignment,f.Report);
localReject(@()sixgr.phy.pucch.PUCCHReceiver.receive(tx.Waveform, ...
    f.Carrier,f.Assignment,f.Context,'NoiseVariance',NaN, ...
    'NoiseVarianceMode','received_dmrs_estimate'), ...
    'sixgr:phy:pucch:NoiseReferenceUnavailable');
localReject(@()sixgr.phy.pucch.PUCCHReceiver.receive(tx.Waveform, ...
    f.Carrier,f.Assignment,f.Context,'NoiseVariance',NaN), ...
    'sixgr:phy:pucch:InvalidNoiseVariance');
assert(isequal(rng,callerRNG),'Receive completion consumed global RNG.');
ok=true;
end

function localReject(action,id)
try, action(); catch cause
    assert(string(cause.identifier)==id,'Expected %s; got %s: %s',id,cause.identifier,cause.message);
    return;
end
error('test:ExpectedError','Expected %s.',id);
end
