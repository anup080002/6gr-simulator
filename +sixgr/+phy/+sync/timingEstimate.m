function [timingOffset, info] = timingEstimate(rxWaveform, arg2, arg3, arg4, varargin)
%timingEstimate Estimate SSB timing offset using NR timing estimator.
%
%   [timingOffset, info] = sixgr.phy.sync.timingEstimate(rxWaveform, NID2,
%   blockPattern, sampleRateHz)
%
%   Backward-compatible calling form (older internal call sites):
%   timingEstimate(rxWaveform, blockPattern, sampleRateHz, NID2)
%
%   Inputs
%     rxWaveform   : Nsamp-by-Nr complex samples
%     NID2         : physical-layer cell ID group (0..2)
%     blockPattern : 'Case A'|'Case B'|'Case C'|'Case D'|'Case E'
%     sampleRateHz : sampling rate in Hz
%
%   Name-value options
%     'UseAntenna' : scalar antenna index for timing (default: 1)
%
%   Outputs
%     timingOffset : sample offset returned by nrTimingEstimate
%     info         : struct with debug fields

    % Parse positional args in a robust way.
    % Expected (preferred): (rxWaveform, NID2, blockPattern, sampleRateHz)
    % Alternate (legacy):  (rxWaveform, blockPattern, sampleRateHz, NID2)
    NID2 = [];
    blockPattern = 'Case B';
    sampleRateHz = [];

    if nargin < 4
        error('sixgr:phy:sync:timingEstimate:BadInputs', 'Expected at least 4 inputs.');
    end

    if isnumeric(arg2) && isscalar(arg2)
        NID2 = double(arg2);
        blockPattern = arg3;
        sampleRateHz = double(arg4);
    elseif ischar(arg2) || isstring(arg2)
        blockPattern = arg2;
        sampleRateHz = double(arg3);
        NID2 = double(arg4);
    else
        error('sixgr:phy:sync:timingEstimate:BadInputs', 'Unsupported input ordering/types.');
    end

    % Name-value parsing
    p = inputParser;
    p.addParameter('UseAntenna', 1, @(x) isnumeric(x) && isscalar(x) && x >= 1);
    p.parse(varargin{:});
    opt = p.Results;

    if isvector(rxWaveform)
        rxWaveform = rxWaveform(:);
    end

    blockPattern = char(string(blockPattern));

    if isempty(sampleRateHz) || ~isfinite(sampleRateHz) || sampleRateHz <= 0
        error('sixgr:phy:sync:timingEstimate:BadSampleRate', 'sampleRateHz must be a positive scalar.');
    end

    if isempty(NID2) || ~isscalar(NID2) || NID2 < 0 || NID2 > 2
        error('sixgr:phy:sync:timingEstimate:BadNID2', 'NID2 must be 0, 1, or 2.');
    end

    Nr = size(rxWaveform, 2);
    ant = min(max(1, round(opt.UseAntenna)), Nr);

    % Use a 4-symbol SSB-shaped reference grid. PSS occupies symbol 2 of the
    % SS/PBCH block per TS 38.211 7.4.3.1; using a 2-symbol shortcut biases
    % timing against the actual SSB OFDM symbol layout.
    nrbSSB = 20;
    scsSSB_kHz = localSSBSubcarrierSpacing_kHz(blockPattern);
    initialNSlot = 0;

    refGrid = complex(zeros(nrbSSB*12, 4));
    pssSym = nrPSS(NID2);
    try
        pssSub = nrPSSIndices('IndexStyle', 'subscript', 'IndexBase', '1based');
        if size(pssSub, 2) >= 2
            refGrid(sub2ind(size(refGrid), pssSub(:,1), pssSub(:,2))) = pssSym;
        else
            refGrid(double(pssSub(:)), 2) = pssSym;
        end
    catch
        pssInd = nrPSSIndices();
        try
            [row_pss, col_pss] = ind2sub(size(refGrid), pssInd);
            refGrid(sub2ind(size(refGrid), row_pss(:), col_pss(:))) = pssSym;
        catch
            refGrid(double(pssInd(:)), 2) = pssSym;
        end
    end

    % Provide SampleRate to match the input waveform.
    % Prefer the refGrid syntax; fall back to refInd/refSym if required.
    try
        timingOffset = nrTimingEstimate(rxWaveform(:, ant), nrbSSB, scsSSB_kHz, initialNSlot, refGrid, ...
            'SampleRate', sampleRateHz);
    catch
        pssInd = nrPSSIndices();
        timingOffset = nrTimingEstimate(rxWaveform(:, ant), nrbSSB, scsSSB_kHz, initialNSlot, pssInd, pssSym, ...
            'SampleRate', sampleRateHz);
    end

    timingOffset = double(timingOffset);
    if ~isfinite(timingOffset) || timingOffset < 0 || timingOffset > size(rxWaveform,1)/2
        warning('sixgr:sync:BadTimingEstimate', ...
            'SSB timing estimate %.3f is out of range for waveform length %d. Clamped to 0.', ...
            double(timingOffset), size(rxWaveform,1));
        timingOffset = 0;
    end

    info = struct();
    info.NID2 = double(NID2);
    info.BlockPattern = blockPattern;
    info.SubcarrierSpacing_kHz = scsSSB_kHz;
    info.NRBSSB = nrbSSB;
    info.InitialNSlot = initialNSlot;
    info.SampleRate_Hz = double(sampleRateHz);
    info.UseAntenna = ant;
    info.RawTimingEstimate_samples = double(timingOffset);
    info.TimingEstimateStatus = "available_raw_estimate";
end

function scs_kHz = localSSBSubcarrierSpacing_kHz(blockPattern)
    bp = upper(strrep(char(blockPattern), ' ', ''));
    switch bp
        case 'CASEA'
            scs_kHz = 15;
        case {'CASEB','CASEC'}
            scs_kHz = 30;
        case 'CASED'
            scs_kHz = 120;
        case 'CASEE'
            scs_kHz = 240;
        otherwise
            scs_kHz = 30;
    end
end
