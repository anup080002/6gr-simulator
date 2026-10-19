function ok=testPRACHNativeRepetitionBackground()
% Actual native PRACH samples; auxiliary scoring cannot change decisions.
setup6GRSimToolkit('Verbose',false);
saved=rng; cleanup=onCleanup(@()rng(saved)); %#ok<NASGU>
rng(719013);
s=sixgr.lls6g.config.loadScenarioConfig('simulator/configs/scenarios/lls_causal_access_to_data_wiring_tdd.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
ra=sixgr.mac.ra.RAConfig(cfg);
[tx,occasion]=sixgr.phy.ra.generateMsg1PRACHWaveform(cfg,ra);
pr=tx.PRACHRuntimeConfig;
assert(tx.Format=="B4");
for model=["AWGN","CDL-C"]
    for branches=[1 4 64]
        clean=repmat(tx.Waveform(:,1),1,branches);
        if model=="CDL-C"
            channel=nrCDLChannel('DelayProfile','CDL-C','DelaySpread',100e-9, ...
                'SampleRate',tx.SampleRate_Hz,'MaximumDopplerShift',70,'Seed',927);
            channel.TransmitAntennaArray.Size=[1 1 1 1 1];
            channel.ReceiveAntennaArray.Size=[sqrt(branches) sqrt(branches) 1 1 1];
            clean=channel(tx.Waveform(:,1));
        end
        variance=mean(abs(clean).^2,'all')/100;
        rx=clean+sqrt(variance/2)*(randn(size(clean))+1i*randn(size(clean)));
        before=rng;
        [idx,timing,native]=nrPRACHDetect(tx.Carrier,tx.PRACH,rx, ...
            'PreambleIndex',0:63,'DetectionThreshold',.02);
        det=sixgr.rach.PRACHDetector(rx,pr,'Occasion',occasion, ...
            'DetectorBackend','toolbox_peak','DetectionThresholdMode','fixed', ...
            'DetectionThreshold',.02);
        assert(isequal(before,rng),'Diagnostics may not draw a new channel/noise realization.');
        assert(det.Detected && det.DetectedPreambleIndex==idx && ...
            det.TimingOffsetSamples==timing && det.Threshold==native.DetectionThreshold);
        assert(isequal(det.CorrelationPeaks(:),double(native.CorrelationPeaks(:))));
        b=det.NoiseFloorEvidence; t=det.CorrelationTrace;
        assert(b.PairCount==6 && b.RxAntennaCount==branches && ...
            b.NFFT==tx.OFDMInfo.Nfft && b.SampleRateHz==tx.SampleRate_Hz);
        assert(isfinite(b.NoiseFloor) && b.NoiseFloor>0 && ...
            b.Normalization==b.ReferenceEnergy*b.OccupiedReceivedEnergy);
        assert(numel(t.LagSamples)==b.NFFT && isnan(t.Threshold) && ...
            t.DecisionThreshold==det.Threshold && t.DecisionPeakMetric==det.PeakMetric);
        assert(det.PeakToNoiseRatio==max(t.CorrelationAbs)/b.NoiseFloor);
        if model=="AWGN"
            assert(abs(b.SampleEquivalentVariance/variance-1)<.2, ...
                'AWGN reference: measured variance=%g expected=%g.',b.SampleEquivalentVariance,variance);
        end
        [static,~]=sixgr.rach.measureNativePRACHBackground(clean,pr,occasion,idx);
        impaired=clean.*exp(1i*2*pi*400*(0:size(clean,1)-1).'/tx.SampleRate_Hz);
        [rotating,~]=sixgr.rach.measureNativePRACHBackground(impaired,pr,occasion,idx);
        assert(rotating.SampleEquivalentVariance>static.SampleEquivalentVariance && ...
            contains(rotating.Definition,'inter_repetition_variation'), ...
            'CFO/channel variation must remain in measured background, not be called thermal noise.');
        fprintf('PRACH_NATIVE_BACKGROUND_PASS model=%s RX=%d Nfft=%d variance_ratio=%g\n', ...
            model,branches,b.NFFT,b.SampleEquivalentVariance/variance);
    end
end
[missing,trace]=sixgr.rach.measureNativePRACHBackground(rx(1:3,:),pr,occasion,idx);
assert(isnan(missing.NoiseFloor) && isempty(fieldnames(trace)) && ...
    missing.Status=="unavailable_incomplete_native_useful_symbols");
% The target H4 native sample clock must also be exercised. This is an
% explicit AWGN receive-branch fixture, not a 64x4 fading/access run.
s=sixgr.lls6g.config.loadScenarioConfig('simulator/configs/scenarios/h4_100_cdlc100_connected_impaired_40db_adaptation.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
ra=sixgr.mac.ra.RAConfig(cfg);
[tx,occasion]=sixgr.phy.ra.generateMsg1PRACHWaveform(cfg,ra);
assert(tx.Carrier.NSizeGrid==273 && tx.SampleRate_Hz==122.88e6);
rx=repmat(tx.Waveform(:,1),1,64);
variance=mean(abs(rx).^2,'all')/100;
rx=rx+sqrt(variance/2)*(randn(size(rx))+1i*randn(size(rx)));
[idx,timing,native]=nrPRACHDetect(tx.Carrier,tx.PRACH,rx, ...
    'PreambleIndex',0:63,'DetectionThreshold',.02);
det=sixgr.rach.PRACHDetector(rx,tx.PRACHRuntimeConfig,'Occasion',occasion, ...
    'DetectorBackend','toolbox_peak','DetectionThresholdMode','fixed','DetectionThreshold',.02);
assert(det.DetectedPreambleIndex==idx && det.TimingOffsetSamples==timing && ...
    det.Threshold==native.DetectionThreshold);
assert(det.NoiseFloorEvidence.NFFT==tx.OFDMInfo.Nfft && ...
    det.NoiseFloorEvidence.SampleRateHz==122.88e6 && ...
    abs(det.NoiseFloorEvidence.SampleEquivalentVariance/variance-1)<.2);
fprintf('PRACH_NATIVE_H4_BACKGROUND_PASS 273PRB Fs=122.88MHz RX=64 Nfft=%g variance_ratio=%g\n', ...
    det.NoiseFloorEvidence.NFFT,det.NoiseFloorEvidence.SampleEquivalentVariance/variance);
ok=true;
end
