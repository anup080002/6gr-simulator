function ok=testSpectralPortAndPowerAccounting()
% Independent analytic tones: no RF realization or calibrated-power claim.
fs=63000; n=(0:62).';
x=[2*exp(1j*2*pi*3*n/63),3*exp(-1j*2*pi*7*n/63)];
s=sixgr.phy.waveform.SpectralMeasurement.measure(x,fs,'FFTSize',63, ...
    'OccupiedBand_Hz',[-fs/2 fs/2],'GuardBands_Hz',zeros(0,2));
assert(s.NumPorts==2&&isequal(size(s.PSDPerPort),[63 2]));
assert(max(abs(s.TimeDomainPowerPerPort-[4 9]))<1e-12);
assert(max(abs(s.SpectralIntegralPowerPerPort-[4 9]))<1e-12);
assert(abs(s.SpectralIntegralPower-13)<1e-12&&abs(s.OccupiedPower-13)<1e-12);
[~,peaks]=max(s.PSDPerPort,[],1);
assert(isequal(reshape(s.Frequency_Hz(peaks),1,[]),[3000 -7000]));
assert(s.RBW_Hz==fs/63&&s.FrequencyBinSpacing_Hz==fs/63);
padded=sixgr.phy.waveform.SpectralMeasurement.measure(x,fs,'FFTSize',252, ...
    'OccupiedBand_Hz',[-fs/2 fs/2],'GuardBands_Hz',zeros(0,2));
assert(abs(padded.SpectralIntegralPower-13)<1e-12);
assert(padded.RBW_Hz==s.RBW_Hz&&padded.FrequencyBinSpacing_Hz==fs/252);
h=sixgr.phy.waveform.SpectralMeasurement.measure(x,fs,'FFTSize',252,'AnalysisWindow','hann');
w=.5-.5*cos(2*pi*n/62);
assert(abs(h.RBW_Hz-fs*sum(w.^2)/sum(w)^2)<1e-10);
assert(max(abs(h.ErrorPerPort_dB))<1e-10);
silent=sixgr.phy.waveform.SpectralMeasurement.measure(zeros(8,2),fs);
assert(all(silent.ZeroPowerPorts)&&all(isinf(silent.PSD_dB_per_Hz)&silent.PSD_dB_per_Hz<0));
assert(silent.SpectralIntegralPower==0&&silent.Error_dB==0);
profile=struct('ProfileID','analytic_full_band','Version','1', ...
    'BandCenters_Hz',0,'Bandwidths_Hz',fs,'Limits_dB',20,'FFTSize',63);
e=sixgr.rf.runtime.SpectrumEmissionMeasurement.measure(x,fs,profile);
assert(height(e)==2&&isequal(e.PortIndex,[1;2]));
assert(max(abs(e.MeasuredPower_InputAmplitudeSquared-[4;9]))<1e-12);
profile.FFTSize=252;
z=sixgr.rf.runtime.SpectrumEmissionMeasurement.measure(x,fs,profile);
assert(max(abs(z.MeasuredPower_InputAmplitudeSquared-e.MeasuredPower_InputAmplitudeSquared))<1e-12);
assert(max(abs(z.IntegratedSpectrumPower-z.TimeDomainPower))<1e-12);
% Adjacent half-open filters partition DC once, never twice.
profile.BandCenters_Hz=[-fs/4;fs/4]; profile.Bandwidths_Hz=[fs/2;fs/2];
profile.Limits_dB=[20;20]; profile.FFTSize=64;
dc=sixgr.rf.runtime.SpectrumEmissionMeasurement.measure(ones(64,1),fs,profile);
assert(dc.MeasuredPower_InputAmplitudeSquared(1)==0&&dc.MeasuredPower_InputAmplitudeSquared(2)==1);
assert(isinf(dc.Measured_dB(1))&&dc.Measured_dB(1)<0);
expect(@()sixgr.phy.waveform.SpectralMeasurement.measure(x,fs,'SegmentOverlap',.5), ...
    'WAVEFORM:SpectralConfigurationInvalid');
expect(@()sixgr.phy.waveform.SpectralMeasurement.measure(1,fs,'AnalysisWindow','hann'), ...
    'WAVEFORM:SpectralConfigurationInvalid');
expect(@()sixgr.phy.waveform.SpectralMeasurement.measure(x,NaN), ...
    'WAVEFORM:SpectralConfigurationInvalid');
profile.BandCenters_Hz=fs; profile.Bandwidths_Hz=fs; profile.Limits_dB=0;
expect(@()sixgr.rf.runtime.SpectrumEmissionMeasurement.measure(x,fs,profile), ...
    'RF:SpectrumMeasurementInvalid');
ok=true; fprintf('SPECTRAL_PORT_POWER_ACCOUNTING_PASS\n');
end
function expect(f,id)
try, f(); catch ME, assert(strcmp(ME.identifier,id),'Unexpected rejection: %s',ME.identifier); return; end
error('test:ExpectedSpectralRejection','Expected %s.',id);
end
