function ok = testTRSReceiveBranchDetection()
% Detect one-port TRS on every physical RX branch, independent of ordering.
setup6GRSimToolkit('Verbose',false);
stream=RandStream('mt19937ar','Seed',5192401);
reference=exp(1i*(pi/2)*randi(stream,[0 3],150,1));
samples=reference*[0.2+0.3i -0.4i]+ ...
    0.1*(randn(stream,150,2)+1i*randn(stream,150,2));
[base,~]=sixgr.phy.trs.correlateTRSReceiveBranches(samples,reference);
for scale=[1 1e-12]
    rotated=scale*samples(:,[2 1]).*[exp(0.71i) exp(-1.39i)];
    value=sixgr.phy.trs.correlateTRSReceiveBranches(rotated,reference);
    assert(abs(value-base)<1e-12,'RX order, branch phase or absolute power changed normalized correlation.');
end
assert(sixgr.phy.trs.correlateTRSReceiveBranches(zeros(150,2),reference)==0);
bad=samples; bad(3,2)=NaN;
assert(isnan(sixgr.phy.trs.correlateTRSReceiveBranches(bad,reference)), ...
    'A bad RX branch must not be silently discarded.');
s = sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios','lls_tdd_5mhz_rank2_4tx2rx_awgn_m10db.yaml'));
cfg = sixgr.lls6g.buildInternalConfig(s,tempname);
p = sixgr.link.prepareTRSTransmission(cfg,-10,'RuntimeSlot', ...
    double(cfg.phy.trs.slotNumbers(1))+1);
tx = p.Tx; strict = p.StrictConfig;
wave = tx.Waveform;
assert(size(wave,2)==1,'TRS has one logical reference port.');
gains = [0 1;1 0;1 -1;1 1i];
for k=1:size(gains,1)
    rx = struct('Waveform',wave*gains(k,:), 'NoiseVariance',0, ...
        'InjectedTimingOffset_samples',0,'FaultMode',"normal");
    % Exact noiseless linear positive fixture (zero-variance Gaussian limit),
    % not a statistical null qualification or an RF-impaired observation.
    rx.WhiteGaussianNoiseModelEstablished=true;
    timing = sixgr.phy.trs.estimateTRSTiming(rx,strict,tx);
    assert(all(timing.Table.TRSTimingEstimateAvailable));
    det = sixgr.phy.trs.detectTRSResources(rx,strict,tx,'Timing',timing);
    assert(det.DetectionSuccess, ...
        'TRS detection discarded a usable RX branch: gains [%s], metric %g.', ...
        num2str(gains(k,:)),det.MeanDetectionMetric);
    assert(abs(det.MeanDetectionMetric-1)<1e-10);
    for j=1:numel(det.SlotDetections)
        d=det.SlotDetections(j);
        expected=nrExtractResources(d.ReferenceIndices,d.RxGrid);
        assert(isequal(size(d.RxRE),size(expected)) && ...
            max(abs(d.RxRE(:)-expected(:)))<1e-12, ...
            'The detector must retain the actual pilot samples on both RX branches.');
    end
    frequency=sixgr.phy.trs.estimateTRSFrequencyOffset(det,strict,tx,struct());
    assert(frequency.EstimateAvailable && abs(frequency.EstimatedCommonFrequency_Hz)<1e-6);
    ch=sixgr.phy.trs.estimateTRSChannel(rx,strict,tx,det);
    assert(ch.EstimateAvailable && ch.HestRxPorts==2);
end
fprintf('TRS receive-branch detection: zero-first, zero-second, opposite and quadrature phases passed.\n');
ok=true;
end
