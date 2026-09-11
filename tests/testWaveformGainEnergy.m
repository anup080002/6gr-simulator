function ok=testWaveformGainEnergy()
% Analytic checks of independent sample-energy measurement, not radio trials.
x=complex([1 2;3 4],[4 3;2 1]);
for type=["double","single"]
    before=cast(x,type); after=before.*cast(10^(-37/20),type);
    m=sixgr.truth.measureWaveformGainEnergy(before,after);
    assert(m.InputEnergy_mWsample==sum(abs(double(before(:))).^2) && ...
        m.OutputEnergy_mWsample==sum(abs(double(after(:))).^2));
    expected=m.InputEnergy_mWsample*10^(-37/10);
    assert(abs(m.OutputEnergy_mWsample-expected)<=m.RelativeTolerance*expected);
    wrong=sixgr.truth.measureWaveformGainEnergy(before,after*cast(2,type));
    assert(abs(wrong.OutputEnergy_mWsample-expected)>wrong.RelativeTolerance*expected, ...
        'Measurement must expose wrong gain, not regenerate the expected output.');
    assert(m.SampleElementCount==4 && m.SampleCount==2 && m.BranchCount==2 && ...
        ~m.ReceiverEstimatorInput);
end
m=sixgr.truth.measureWaveformGainEnergy(zeros(4,2),zeros(4,2));
assert(m.InputEnergy_mWsample==0 && m.OutputEnergy_mWsample==0, ...
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
