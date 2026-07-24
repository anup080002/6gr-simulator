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
%     SSBTiming   : canonical SSBTimingResolver result. New standard-path
%                   callers must provide this object.

    if nargin < 3
        error('sixgr:phy:sync:freqOffsetCorrect:BadInput', 'rxWaveform, blockPattern, sampleRateHz are required');
    end

    p = inputParser;
    p.addParameter('SearchBW_Hz', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x >= 0));
    p.addParameter('NID2Candidates', 0:2, @(x) isnumeric(x) && isvector(x));
    p.addParameter('SSBTiming', struct(), @localOptionalTiming);
    p.parse(varargin{:});
    opt = p.Results;
    ssbTiming = localResolveTiming(blockPattern, opt.SSBTiming);

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
        ref = localPSSReference(ssbTiming, nid2, sampleRateHz);
        % Cell search must cover the whole received SSB observation window.
        % A short prefix-only search misses valid SSBs that start later in a
        % burst period and can turn a no-signal prefix into a false NID2/CFO.
        nSearch = numel(xIn);
        xSearch = xIn;

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
    info.SearchSamples = double(numel(xIn));
    info.Metric = bestMetric;
    info.SSBTiming = ssbTiming;
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

function ref = localPSSReference(ssbTiming, nid2, fs)
    % Build a reference PSS waveform in time domain.
    % We generate a 20-RB grid with PSS in symbol 1 and OFDM modulate.

    scs_kHz = double(ssbTiming.SSBSubcarrierSpacingKHz);
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

    w = sixgr.phy.waveform.ofdmModulate( ...
        carrier, grid, 'SampleRate', fs, 'Windowing', 0);

    % Use a short portion for correlation
    ref = w(1:min(end, 2048));
end

function timing = localResolveTiming(blockPattern, supplied)
    if isstruct(supplied) && isscalar(supplied) && ...
            ~isempty(fieldnames(supplied))
        timing = localValidateTiming(supplied, blockPattern);
        return;
    end

    % Compatibility-only positional signature: validate the explicit case
    % through the canonical resolver. It never owns an independent symbol
    % list or a default case. New callers pass SSBTiming directly.
    caseLetter = localCaseLetter(blockPattern);
    if any(caseLetter == ["A", "B", "C"])
        range = "FR1";
        lmax = 8;
    elseif any(caseLetter == ["D", "E"])
        range = "FR2-1";
        lmax = NaN;
    else
        range = "FR2-2";
        lmax = NaN;
    end
    timing = sixgr.phy.frame.SSBTimingResolver.resolve( ...
        "Case", caseLetter, ...
        "FrequencyRange", range, ...
        "Lmax", lmax);
end

function timing = localValidateTiming(timing, blockPattern)
    required = ["BlockPattern", "SSBSubcarrierSpacingKHz", ...
        "CandidateIndices", "CandidateStartSymbolsWithinHalfFrame", ...
        "Lmax", "ResolvedValid"];
    missing = required(~isfield(timing, cellstr(required)));
    if ~isempty(missing)
        error("sixgr:phy:sync:InvalidSSBTiming", ...
            "SSBTiming is missing canonical fields: %s.", ...
            strjoin(missing, ", "));
    end
    if ~(isscalar(timing.ResolvedValid) && logical(timing.ResolvedValid))
        error("sixgr:phy:sync:InvalidSSBTiming", ...
            "SSBTiming must be a successfully resolved canonical object.");
    end
    expected = localCaseLetter(blockPattern);
    actual = localCaseLetter(timing.BlockPattern);
    if actual ~= expected
        error("sixgr:phy:sync:SSBTimingCaseMismatch", ...
            "BlockPattern %s conflicts with supplied SSBTiming %s.", ...
            string(blockPattern), string(timing.BlockPattern));
    end
end

function letter = localCaseLetter(raw)
    letter = upper(strtrim(string(raw)));
    if ~isscalar(letter) || strlength(letter) == 0
        error("sixgr:phy:frame:MissingSSBCase", ...
            "An explicit SSB case A through G is required.");
    end
    letter = strtrim(erase(letter, "CASE"));
    if ~any(letter == ["A", "B", "C", "D", "E", "F", "G"])
        error("sixgr:phy:frame:UnsupportedSSBCase", ...
            "Unsupported SSB case '%s'; expected Case A through Case G.", ...
            string(raw));
    end
end

function tf = localOptionalTiming(value)
    tf = isstruct(value) && isscalar(value);
end
