function ok=testWaveformGainEnergy()
% Analytic checks of independent sample-energy measurement, not radio trials.
x=complex([1 2;3 4],[4 3;2 1]);
for type=["double","single"]
    before=cast(x,type); after=before.*cast(10^(-37/20),type);
    m=sixgr.truth.measureWaveformGainEnergy(before,after,"sqrt_mW");
    assert(m.InputEnergy_mWsample==sum(abs(double(before(:))).^2) && ...
        m.OutputEnergy_mWsample==sum(abs(double(after(:))).^2));
    expected=m.InputEnergy_mWsample*10^(-37/10);
    assert(abs(m.OutputEnergy_mWsample-expected)<=m.RelativeTolerance*expected);
    wrong=sixgr.truth.measureWaveformGainEnergy(before,after*cast(2,type),"sqrt_mW");
    assert(abs(wrong.OutputEnergy_mWsample-expected)>wrong.RelativeTolerance*expected, ...
        'Measurement must expose wrong gain, not regenerate the expected output.');
    assert(m.SampleElementCount==4 && m.SampleCount==2 && m.BranchCount==2 && ...
        ~m.ReceiverEstimatorInput);
    normalized=sixgr.truth.measureWaveformGainEnergy(before,after,"normalized_complex_baseband");
    assert(normalized.InputEnergy==m.InputEnergy && normalized.OutputEnergy==m.OutputEnergy && ...
        isnan(normalized.InputEnergy_mWsample) && isnan(normalized.OutputEnergy_mWsample) && ...
        normalized.EnergyUnit=="sum_squared_normalized_complex_amplitude_not_mW");
end
m=sixgr.truth.measureWaveformGainEnergy(zeros(4,2),zeros(4,2));
assert(m.InputEnergy==0 && m.OutputEnergy==0 && isnan(m.InputEnergy_mWsample), ...
    'Idle energy must stay exactly zero, without a realmin power floor.');
caught=false;
try
    sixgr.truth.measureWaveformGainEnergy(x,NaN(size(x)));
catch err
    if ~strcmp(err.identifier,'sixgr:truth:InvalidGainEnergySamples'), rethrow(err); end
    caught=true;
end
assert(caught); ok=true;
end
