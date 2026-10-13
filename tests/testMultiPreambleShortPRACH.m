function ok=testMultiPreambleShortPRACH()
% Short-B4/four-RX cross-root rejection. Small deterministic receiver check,
% NOT a false-alarm probability campaign or general fading qualification.
setup6GRSimToolkit('Verbose',false); old=rng; cleanup=onCleanup(@()rng(old)); rng(927143,'twister');
base=struct('channel',struct('model','AWGN','awgnOnly',true), ...
    'random_access',struct('configuration_index',157,'prach_format','B4', ...
    'subcarrier_spacing_khz',30,'carrier_scs_khz',15,'n_size_grid',25, ...
    'zero_correlation_zone',8,'restricted_set','UnrestrictedSet', ...
    'duplex_mode','TDD','root_sequence_index',1,'num_rx_antennas',4, ...
    'num_slots',20,'num_subframes',20,'detection_threshold_mode','auto'));
pc=sixgr.rach.PRACHConfig(base); occ=sixgr.rach.mapPRACHToOccasion(pc,'OccasionIndex',1);
a=sixgr.rach.generatePRACHWaveform(pc,'Occasion',occ,'PreambleIndex',0);
b=sixgr.rach.generatePRACHWaveform(pc,'Occasion',occ,'PreambleIndex',1);
for mode=1:4
    delay=[2 4];
    first=[zeros(delay(1),1);a.Waveform;zeros(delay(2)-delay(1),1)];
    second=[zeros(delay(2),1);b.Waveform];
    wanted=[0 1];
    if mode==2, second=second*0.6; end
    if mode==3, second(:)=0; wanted=0; end
    if mode==4, first(:)=0; second(:)=0; wanted=[]; end
    % Actual complex receive branches, not duplicate labelled scalar rows.
    received=first*[1 0.8i 0.7 -0.6i]+second*[0.7 -0.9i 0.6 0.8i];
    sigma=sqrt(mean(abs(a.Waveform).^2)/100);
    received=received+sigma*(randn(size(received))+1i*randn(size(received)))/sqrt(2);
    t=sixgr.rach.PRACHDetector(received,pc,'Occasion',occ, ...
        'DetectorBackend','toolbox_peak','DetectionThresholdMode','auto');
    [ds,bg]=sixgr.rach.detectUnrestrictedPreambles(received,pc,occ,t,2);
    assert(bg.PairCount>0 && bg.RxAntennaCount==4);
    assert(abs(bg.SampleEquivalentVariance/sigma^2-1)<0.15, ...
        'test:PRACHMeasuredNoise','Received repetition residual does not recover the independently injected noise.');
    assert(isfinite(bg.NoiseFloor) && bg.NoiseFloor>0);
    assert(isequal(sort([ds.DetectedPreambleIndex]),wanted), ...
        'test:ShortPRACHSet','Short-preamble candidate identities disagree with the independent waveform construction.');
    for d=reshape(ds,1,[])
        assert(abs(d.TimingOffsetSamples-delay(d.DetectedPreambleIndex+1))<=1);
        assert(d.Threshold==t.Threshold && d.ThresholdCalibrationStatus=="single_detection_not_statistical_qualification");
        assert(isfinite(d.PDPNoiseFloor) && d.PDPNoiseFloor>0);
        assert(d.CorrelationTrace.NoiseFloor==d.PDPNoiseFloor);
        assert(d.PeakToNoiseRatio==d.PeakMetric/d.PDPNoiseFloor);
    end
end
ok=true; disp('SHORT_MULTI_PRACH_PASS: independent B4 four-RX delays, equal/unequal powers, single producer and no-signal negative.');
end
