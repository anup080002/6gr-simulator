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
    p.addParameter('TimingSearchGuardSamples', 0, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0 && x == round(x));
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

    % Candidate windows can contain different signal and noise energy
    % (for example a later SIB1 transmission).  The legacy batch kernel
    % reports an unnormalised correlation amplitude and therefore cannot
    % be used to compare those windows without bias.  Keep this truth path
    % on the energy-normalised implementation below.
    useBatchMex = false;
    bestMetric = -inf;
    bestHz = 0;
    bestNID2 = 0;
    bestWindowIndex = NaN;
    xIn = rxWaveform(:,1);
    metricMatrix = nan(numel(candNID2), numel(candHz));
    bestWindowIndexMatrix = nan(numel(candNID2), numel(candHz));
    [searchSegments, searchWindows, candidateStartSymbols] = ...
        localSSBCandidateSearchSegments( ...
        xIn, ssbTiming, sampleRateHz, ...
        double(opt.TimingSearchGuardSamples));

    for nid2Index = 1:numel(candNID2)
        nid2 = candNID2(nid2Index);
        % Generate a time-domain PSS reference for the given SSB SCS/pattern
        if useBatchMex
            try
                metricV = -inf(numel(candHz), 1);
                bestSegmentV = nan(numel(candHz), 1);
                for segmentIndex = 1:numel(searchSegments)
                    ref = localPSSReference(ssbTiming, nid2, ...
                        sampleRateHz, candidateStartSymbols(segmentIndex));
                    xSearch = searchSegments{segmentIndex};
                    if exist("sixgr_freq_corr_search_kernel_mex", "file") == 3
                        segmentMetric = sixgr_freq_corr_search_kernel_mex( ...
                            xSearch, ref, candHz(:), sampleRateHz);
                    else
                        segmentMetric = sixgr_freq_corr_search_kernel( ...
                            xSearch, ref, candHz(:), sampleRateHz);
                    end
                    segmentMetric = double(segmentMetric(:));
                    improved = segmentMetric > metricV;
                    metricV(improved) = segmentMetric(improved);
                    bestSegmentV(improved) = double(segmentIndex);
                end
                metricMatrix(nid2Index, :) = double(metricV(:)).';
                bestWindowIndexMatrix(nid2Index, :) = ...
                    double(bestSegmentV(:)).';
                [m, idx] = max(metricV(:));
                if m > bestMetric
                    bestMetric = m;
                    bestHz = candHz(max(1, min(numel(candHz), idx)));
                    bestNID2 = nid2;
                    bestWindowIndex = bestSegmentV(idx);
                end
                continue;
            catch
                % Fallback to MATLAB loop path.
            end
        end

        for frequencyIndex = 1:numel(candHz)
            fHz = candHz(frequencyIndex);
            m = -Inf;
            selectedSegmentIndex = NaN;
            for segmentIndex = 1:numel(searchSegments)
                ref = localPSSReference(ssbTiming, nid2, ...
                    sampleRateHz, candidateStartSymbols(segmentIndex));
                x = localFreqShift(searchSegments{segmentIndex}, ...
                    sampleRateHz, -fHz);
                segmentMetric = localCorrMetric(x, ref);
                if segmentMetric > m
                    m = segmentMetric;
                    selectedSegmentIndex = double(segmentIndex);
                end
            end
            metricMatrix(nid2Index, frequencyIndex) = double(m);
            bestWindowIndexMatrix(nid2Index, frequencyIndex) = ...
                selectedSegmentIndex;
            if m > bestMetric
                bestMetric = m;
                bestHz = fHz;
                bestNID2 = nid2;
                bestWindowIndex = selectedSegmentIndex;
            end
        end
    end

    if ~(isscalar(bestWindowIndex) && isfinite(bestWindowIndex) && ...
            bestWindowIndex >= 1 && bestWindowIndex <= numel(searchSegments))
        error("sixgr:phy:sync:PSSCandidateNotDetected", ...
            "PSS search did not resolve a canonical candidate window.");
    end
    selectedReference = localPSSReference( ...
        ssbTiming, bestNID2, sampleRateHz, ...
        candidateStartSymbols(bestWindowIndex));
    selectedSegment = localFreqShift( ...
        searchSegments{bestWindowIndex}, sampleRateHz, -bestHz);
    [~, selectedLag] = localCorrMetricAndLag( ...
        selectedSegment, selectedReference);
    selectedTimingOffset = searchWindows(bestWindowIndex, 1) - 1 + ...
        selectedLag - 1;

    % Apply the selected correction
    rxOut = localFreqShift(rxWaveform, sampleRateHz, -bestHz);
    freqOffsetHz = bestHz;
    NID2 = bestNID2;

    info = struct();
    info.SearchBW_Hz = searchBW_Hz;
    info.Candidates_Hz = candHz;
    info.Candidates_NID2 = candNID2;
    info.MetricMatrix = metricMatrix;
    info.BestWindowIndexMatrix = bestWindowIndexMatrix;
    info.CandidateSearchWindows = double(searchWindows);
    info.SelectedCandidateWindowIndex = double(bestWindowIndex);
    info.SelectedCandidateStartSymbol = double( ...
        candidateStartSymbols(bestWindowIndex));
    info.SelectedTimingOffsetSamples = double(selectedTimingOffset);
    info.SelectedCorrelationLagSamples = double(selectedLag - 1);
    info.TimingSearchGuardSamples = double(opt.TimingSearchGuardSamples);
    info.SearchSamples = double(sum( ...
        searchWindows(:,2) - searchWindows(:,1) + 1));
    info.SearchDuration_ms = 1e3 * info.SearchSamples / ...
        double(sampleRateHz);
    info.Metric = bestMetric;
    info.SSBTiming = ssbTiming;
end

function y = localFreqShift(x, fs, fHz)
    n = (0:size(x,1)-1).';
    ph = exp(1j*2*pi*(fHz/fs)*n);
    y = x .* ph;
end

function metric = localCorrMetric(x, ref)
    [metric, ~] = localCorrMetricAndLag(x, ref);
end

function [metric, lagIndex] = localCorrMetricAndLag(x, ref)
    x = x(:,1);
    ref = ref(:);
    c = abs(conv(x, flipud(conj(ref)), "valid"));
    if isempty(c)
        metric = -Inf;
        lagIndex = NaN;
        return;
    end
    referenceEnergy = sum(abs(ref).^2);
    windowEnergy = conv(abs(x).^2, ones(numel(ref), 1), "valid");
    denominator = sqrt(max(windowEnergy .* referenceEnergy, realmin));
    normalisedCorrelation = c ./ denominator;
    [metric, lagIndex] = max(normalisedCorrelation);
    metric = double(metric);
    lagIndex = double(lagIndex);
end

function ref = localPSSReference(ssbTiming, nid2, fs, candidateStartSymbol)
    ref = sixgr.phy.sync.buildPSSCorrelationReference( ...
        ssbTiming, double(nid2), double(fs), ...
        "CandidateStartSymbol", double(candidateStartSymbol));
end

function [segments, windows, retainedCandidateSymbols] = ...
        localSSBCandidateSearchSegments( ...
        x, ssbTiming, fs, guardSamples)
candidateSymbols = double( ...
    ssbTiming.CandidateStartSymbolsWithinHalfFrame(:));
candidateSymbols = unique(candidateSymbols( ...
    isfinite(candidateSymbols) & candidateSymbols >= 0 & ...
    candidateSymbols == round(candidateSymbols)), "stable");
if isempty(candidateSymbols)
    error("sixgr:phy:sync:MissingSSBCandidateSymbols", ...
        "Canonical SSB timing contains no candidate start symbols.");
end

carrier = nrCarrierConfig;
carrier.SubcarrierSpacing = double( ...
    ssbTiming.SSBSubcarrierSpacingKHz);
carrier.NSizeGrid = 20;
carrier.NStartGrid = 0;
carrier.CyclicPrefix = "normal";
sampling = sixgr.phy.frame.OFDMSamplingResolver.resolve( ...
    carrier, "SampleRate", double(fs), "WindowingSamples", 0);
subframeSymbolLengths = double(sampling.SymbolLengths(:)).';
halfFrameSymbolLengths = repmat(subframeSymbolLengths, 1, 5);

segments = cell(0, 1);
windows = zeros(0, 2);
retainedCandidateSymbols = zeros(0, 1);
for candidateIndex = 1:numel(candidateSymbols)
    startSymbol = candidateSymbols(candidateIndex);
    if startSymbol + 4 > numel(halfFrameSymbolLengths)
        continue;
    end
    firstSample = 1 + sum(halfFrameSymbolLengths(1:startSymbol));
    firstSample = max(1, firstSample - guardSamples);
    reference = localPSSReference( ...
        ssbTiming, 0, fs, startSymbol);
    referenceLength = numel(reference);
    sampleCount = referenceLength + 2 * guardSamples;
    lastSample = min(numel(x), firstSample + sampleCount - 1);
    if firstSample > numel(x) || lastSample < firstSample
        continue;
    end
    segments{end+1,1} = x(firstSample:lastSample); %#ok<AGROW>
    windows(end+1,:) = [firstSample, lastSample]; %#ok<AGROW>
    retainedCandidateSymbols(end+1,1) = startSymbol; %#ok<AGROW>
end
if isempty(segments)
    error("sixgr:phy:sync:SSBCandidateWindowsOutsideCapture", ...
        "No canonical SS/PBCH candidate window intersects the capture.");
end
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
