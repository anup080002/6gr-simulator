function T = buildWaveformPreviewTable(direction, snr_dB, frameIdx, slotIdx, txWave, rxWave, sampleRateHz, varargin)
%BUILDWAVEFORMPREVIEWTABLE Build a compact per-TTI waveform preview table.

p = inputParser;
p.addParameter("MaxSamples", 256, @(x) isnumeric(x) && isscalar(x) && x >= 16);
p.parse(varargin{:});
maxSamples = max(16, round(double(p.Results.MaxSamples)));

T = table();
if isempty(txWave) && isempty(rxWave)
    return;
end

txVec = localColumnizeWaveform(txWave);
rxVec = localColumnizeWaveform(rxWave);
L = max(numel(txVec), numel(rxVec));
if L < 1
    return;
end
if numel(txVec) < L
    txVec(end+1:L, 1) = complex(nan); %#ok<AGROW>
end
if numel(rxVec) < L
    rxVec(end+1:L, 1) = complex(nan); %#ok<AGROW>
end

if L > maxSamples
    idx = unique(round(linspace(1, L, maxSamples)));
else
    idx = (1:L).';
end
idx = idx(:);

fs = double(sampleRateHz);
if ~(isfinite(fs) && fs > 0)
    fs = nan;
end
if isfinite(fs)
    t = (double(idx) - 1) ./ fs;
else
    t = nan(numel(idx), 1);
end

txUse = txVec(idx);
rxUse = rxVec(idx);

T = table( ...
    repmat(string(direction), numel(idx), 1), ...
    repmat(double(snr_dB), numel(idx), 1), ...
    repmat(double(frameIdx), numel(idx), 1), ...
    repmat(double(slotIdx), numel(idx), 1), ...
    double(idx), ...
    t, ...
    real(txUse), imag(txUse), abs(txUse), ...
    real(rxUse), imag(rxUse), abs(rxUse), ...
    'VariableNames', { ...
    'Direction','SNR_dB','Frame','Slot','SampleIndex','Time_s', ...
    'TxReal','TxImag','TxMagnitude','RxReal','RxImag','RxMagnitude'});
end

function x = localColumnizeWaveform(x)
if isempty(x)
    x = complex([]);
    return;
end
if ismatrix(x)
    x = x(:, 1);
end
x = x(:);
end
