function T = buildWaveformPreviewTable(direction, snr_dB, frameIdx, slotIdx, txWave, rxWave, sampleRateHz, varargin)
%BUILDWAVEFORMPREVIEWTABLE Retain indexed samples from every TX/RX column.
% This is a sparse display preview, not a resampled waveform for spectral
% analysis. Matching TX/RX column numbers do not imply a one-to-one RF path.

p = inputParser;
p.addParameter("MaxSamples", 256, @(x) isnumeric(x) && isscalar(x) && x >= 16);
p.parse(varargin{:});
maxSamples = max(16, round(double(p.Results.MaxSamples)));

T = table();
if isempty(txWave) && isempty(rxWave)
    return;
end
validateattributes(txWave,{'numeric'},{'2d'},mfilename,'txWave');
validateattributes(rxWave,{'numeric'},{'2d'},mfilename,'rxWave');
chunks=cell(max(size(txWave,2),size(rxWave,2)),1);
for branch=1:numel(chunks)
    tx=[]; rx=[]; txIndex=NaN; rxIndex=NaN;
    if branch<=size(txWave,2), tx=txWave(:,branch); txIndex=branch; end
    if branch<=size(rxWave,2), rx=rxWave(:,branch); rxIndex=branch; end
    row=localBranchPreview(direction,snr_dB,frameIdx,slotIdx,tx,rx,sampleRateHz,maxSamples);
    row.TxAntennaIndex=repmat(txIndex,height(row),1);
    row.RxAntennaIndex=repmat(rxIndex,height(row),1);
    row.ObservationSampleRateHz=repmat(double(sampleRateHz),height(row),1);
    chunks{branch}=row;
end
T=vertcat(chunks{:});
end

function T=localBranchPreview(direction,snr_dB,frameIdx,slotIdx,txWave,rxWave,sampleRateHz,maxSamples)
T=table();
txVec = txWave(:);
rxVec = rxWave(:);
L = max(numel(txVec), numel(rxVec));
if L < 1
    return;
end
if numel(txVec) < L
    txVec(end+1:L, 1) = complex(nan,nan); %#ok<AGROW>
end
if numel(rxVec) < L
    rxVec(end+1:L, 1) = complex(nan,nan); %#ok<AGROW>
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
