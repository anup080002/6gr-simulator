function testRachFrequencyOffsetEstimator
%TESTRACHFREQUENCYOFFSETESTIMATOR Guard low-CFO PRACH repetition estimate.

sampleRateHz=1e6;
rng(10512003,"twister");
useful=randn(1024,1)+1i*randn(1024,1);
reference=repmat(useful,8,1);
time=(0:numel(reference)-1)'/sampleRateHz;

for offsetHz=[-250 0 250]
    rotating=reference.*exp(1i*2*pi*offsetHz*time);
    received=[rotating 0.6*rotating.*exp(1i*0.4)];
    estimate=sixgr.rach.estimateFrequencyOffset( ...
        received,reference,sampleRateHz);
    assert(estimate.Valid,"CFO estimate must be valid.");
    assert(estimate.Estimator=="prach_repetition_phase", ...
        "PRACH must use the repetition-phase estimator.");
    assert(abs(estimate.EstimateHz-offsetHz)<1e-6, ...
        "Injected CFO %.3f Hz was estimated as %.9f Hz.", ...
        offsetHz,estimate.EstimateHz);
end

fprintf("testRachFrequencyOffsetEstimator: PASS\n");
end
