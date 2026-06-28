function ok = calibratedChannelAcceptance()
%CALIBRATEDCHANNELACCEPTANCE Closed-form AWGN, delay, Doppler, and OFDM noise anchors.

carrier = nrCarrierConfig;
carrier.NSizeGrid = 24;
carrier.SubcarrierSpacing = 30;
nt = sixgr.phy.waveform.calibrateOFDMNoiseTransform(carrier, "NumNoiseRE", 2e4);
assert(isfinite(double(nt.SampleToGridNoiseVarianceGain)) && double(nt.SampleToGridNoiseVarianceGain) > 0, ...
    "OFDM sample-to-grid noise gain must be calibrated and positive.");
assert(isfinite(double(nt.GridToSampleNoiseVarianceGain)) && double(nt.GridToSampleNoiseVarianceGain) > 0, ...
    "OFDM grid-to-sample noise gain must be calibrated and positive.");

n = (0:4095).';
signal = complex(ones(size(n)), zeros(size(n)));
noise = complex(cos(2*pi*n/17), sin(2*pi*n/19));
noise = noise .* sqrt(0.01 / mean(abs(noise).^2, "omitnan"));
measuredSNR_dB = 10 * log10(mean(abs(signal).^2, "omitnan") / mean(abs(noise).^2, "omitnan"));
assert(abs(measuredSNR_dB - 20) < 1e-12, ...
    "Closed-form AWGN calibration anchor must measure exactly 20 dB SNR.");

c = 299792458;
distance_m = 300;
delay_s = distance_m / c;
assert(abs(delay_s - 1.000692285594456e-6) < 1e-18, ...
    "Propagation delay must equal d/c for the release anchor.");
speed_mps = 100 / 3.6;
fc_Hz = 4e9;
doppler_Hz = speed_mps / c * fc_Hz;
assert(abs(doppler_Hz - 370.626772442391) < 1e-9, ...
    "Radial Doppler must equal v/c*fc for the release anchor.");
ok = true;
end
