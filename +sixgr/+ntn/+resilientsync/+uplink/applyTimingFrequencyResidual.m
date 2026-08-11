function result = applyTimingFrequencyResidual(waveform, sampleRateHz, timingErrorS, frequencyErrorHz)
%APPLYTIMINGFREQUENCYRESIDUAL Apply signed residuals without oracle recovery.

timingSamples = round(double(timingErrorS) * double(sampleRateHz));
waveform = double(waveform); %#ok<NASGU>
input = waveform;
if timingSamples > 0
    shifted = [zeros(timingSamples,size(input,2),'like',input); input];
    shifted = shifted(1:size(input,1),:);
elseif timingSamples < 0
    n = min(-timingSamples,size(input,1));
    shifted = [input(n+1:end,:); zeros(n,size(input,2),'like',input)];
else
    shifted = input;
end
t = (0:size(shifted,1)-1).' ./ double(sampleRateHz);
shifted = shifted .* exp(1i*2*pi*double(frequencyErrorHz).*t);
result = struct("Waveform", shifted, "TimingError_s", double(timingErrorS), ...
    "TimingError_samples", timingSamples, "FrequencyError_Hz", double(frequencyErrorHz), ...
    "ReceiverOracleUsed", false);
end
