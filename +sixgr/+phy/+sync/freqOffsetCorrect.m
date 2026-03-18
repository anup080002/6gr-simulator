function [rxOut, freqOffsetHz, NID2, info] = freqOffsetCorrect(rxWaveform, blockPattern, sampleRateHz, varargin)
%freqOffsetCorrect Coarse frequency search/correction for NR SSB capture.
%
%   [rxOut,freqOffsetHz,NID2,info] = sixgr.phy.sync.freqOffsetCorrect(...)
%
%   The routine searches over a small set of candidate frequency offsets and
%   selects the one giving the highest PSS correlation peak.
%
%   Name-value options:
%     SearchBW_Hz : +/- search bandwidth around DC (Hz). If empty, a
%                   conservative default is used.
%     NID2Candidates : vector of NID2 hypotheses (default 0:2)

    if nargin < 3
        error('sixgr:phy:sync:freqOffsetCorrect:BadInput', 'rxWaveform, blockPattern, sampleRateHz are required');
    end

    p = inputParser;
    p.addParameter('SearchBW_Hz', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x >= 0));
    p.addParameter('NID2Candidates', 0:2, @(x) isnumeric(x) && isvector(x));
    p.parse(varargin{:});
    opt = p.Results;

    searchBW_Hz = opt.SearchBW_Hz;
    if isempty(searchBW_Hz)
        searchBW_Hz = min(1.2e6, 0.45 * sampleRateHz);
    end

    candNID2 = unique(opt.NID2Candidates(:).');
    candNID2 = candNID2(candNID2 >= 0 & candNID2 <= 2);
    if isempty(candNID2)
        candNID2 = 0:2;
    end

    % Candidate frequency offsets (Hz)
    if searchBW_Hz == 0
        candHz = 0;
    else
        % Keep a small number of points for a cheap coarse search
        nCand = 9;
        candHz = linspace(-searchBW_Hz, searchBW_Hz, nCand);
    end

    useBatchMex = (exist("sixgr_freq_corr_search_kernel_mex", "file") == 3) || ...
        (exist("sixgr_freq_corr_search_kernel", "file") == 2);
    bestMetric = -inf;
    bestHz = 0;
    bestNID2 = 0;
    xIn = rxWaveform(:,1);

    for nid2 = candNID2
        % Generate a time-domain PSS reference for the given SSB SCS/pattern
        ref = localPSSReference(blockPattern, nid2, sampleRateHz);
        nSearch = min(numel(xIn), max(2048, 2*numel(ref)));
        xSearch = xIn(1:nSearch);

        if useBatchMex
            try
                if exist("sixgr_freq_corr_search_kernel_mex", "file") == 3
                    metricV = sixgr_freq_corr_search_kernel_mex(xSearch, ref, candHz(:), sampleRateHz);
                else
                    metricV = sixgr_freq_corr_search_kernel(xSearch, ref, candHz(:), sampleRateHz);
                end
                [m, idx] = max(metricV(:));
                if m > bestMetric
                    bestMetric = m;
                    bestHz = candHz(max(1, min(numel(candHz), idx)));
                    bestNID2 = nid2;
                end
                continue;
            catch
                % Fallback to MATLAB loop path.
            end
        end

        for fHz = candHz
            x = localFreqShift(xSearch, sampleRateHz, -fHz);
            m = localCorrMetric(x, ref);
            if m > bestMetric
                bestMetric = m;
                bestHz = fHz;
                bestNID2 = nid2;
            end
        end
    end

    % Apply the selected correction
    rxOut = localFreqShift(rxWaveform, sampleRateHz, -bestHz);
    freqOffsetHz = bestHz;
    NID2 = bestNID2;

    info = struct();
    info.SearchBW_Hz = searchBW_Hz;
    info.Candidates_Hz = candHz;
    info.Candidates_NID2 = candNID2;
    info.Metric = bestMetric;
end

function y = localFreqShift(x, fs, fHz)
    n = (0:size(x,1)-1).';
    ph = exp(1j*2*pi*(fHz/fs)*n);
    y = x .* ph;
end

function metric = localCorrMetric(x, ref)
    % Correlate using magnitude peak of convolution
    c = abs(conv(x(:,1), flipud(conj(ref)), 'valid'));
    metric = max(c);
end

function ref = localPSSReference(blockPattern, nid2, fs)
    % Build a reference PSS waveform in time domain.
    % We generate a 20-RB grid with PSS in symbol 1 and OFDM modulate.

    scs_kHz = localSSBSubcarrierSpacing_kHz(blockPattern);
    nrbSSB = 20;

    carrier = nrCarrierConfig;
    carrier.SubcarrierSpacing = scs_kHz;
    carrier.NSizeGrid = nrbSSB;
    carrier.NStartGrid = 0;
    carrier.CyclicPrefix = 'normal';

    pss = nrPSS(nid2);
    ind = nrPSSIndices;

    grid = zeros(carrier.NSizeGrid*12, 4);
    grid(ind) = pss;

    w = nrOFDMModulate(carrier, grid, 'SampleRate', fs);

    % Use a short portion for correlation
    ref = w(1:min(end, 2048));
end

function scs_kHz = localSSBSubcarrierSpacing_kHz(blockPattern)
    bp = upper(strrep(char(string(blockPattern)), ' ', ''));
    switch bp
        case 'CASEA'
            scs_kHz = 15;
        case {'CASEB','CASEC'}
            scs_kHz = 30;
        case {'CASED','CASEE'}
            scs_kHz = 120;
        otherwise
            scs_kHz = 30;
    end
end
