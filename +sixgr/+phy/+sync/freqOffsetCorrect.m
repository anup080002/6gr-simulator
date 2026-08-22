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
    p.addParameter('CFOHypothesesHz', [], ...
        @(x) isempty(x) || (isnumeric(x) && isvector(x) && all(isfinite(x))));
    p.addParameter('TimingSearchGuardSamples', 0, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0 && x == round(x));
    p.addParameter('SSBCenterFrequencyOffsetHz', 0, ...
        @(x) isnumeric(x) && isscalar(x) && isreal(x) && isfinite(x));
    p.addParameter('FineCFOEnabled', false, ...
        @(x) (islogical(x) || isnumeric(x)) && isscalar(x));
    p.addParameter('FineCFOMethod', "cyclic_prefix", ...
        @(x) ischar(x) || (isstring(x) && isscalar(x)));
    p.addParameter('FineCFOMaxResidualHz', Inf, ...
        @(x) isnumeric(x) && isscalar(x) && ~isnan(x) && x > 0);
    p.addParameter('FineCFOMinimumSymbols', 2, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 1 && x == round(x));
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

    % Candidate frequency offsets (Hz). An explicit caller-supplied grid is
    % authoritative; the nine-point grid is retained only for legacy calls.
    if ~isempty(opt.CFOHypothesesHz)
        candHz = unique(double(opt.CFOHypothesesHz(:).'),"stable");
        if any(abs(candHz) > searchBW_Hz + max(1,eps(searchBW_Hz)))
            error("sixgr:phy:sync:CFOHypothesisOutsideSearchRange", ...
                "Explicit CFO hypotheses must lie inside +/-SearchBW_Hz.");
        end
    elseif searchBW_Hz == 0
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
    % NCRBSSB/KSSB place the SS/PBCH block relative to Point A.  That
    % deterministic carrier-grid placement is not oscillator CFO and must
    % be removed before correlating with the zero-centred 20-RB PSS
    % reference.  Keeping the two terms separate prevents a non-centred SSB
    % from being reported as UE/gNB frequency error.
    ssbCenterOffsetHz = double(opt.SSBCenterFrequencyOffsetHz);
    xIn = localFreqShift(rxWaveform, sampleRateHz, -ssbCenterOffsetHz);
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

    % Refine the residual CFO without truth information.  Once coarse PSS
    % acquisition has reduced the offset below half the SCS, the repeated
    % cyclic prefix provides a practical fractional-CFO phase measurement.
    coarseCorrected = localFreqShift(xIn, sampleRateHz, -bestHz);
    fineResidualHz = 0;
    fineInfo = struct("Enabled",logical(opt.FineCFOEnabled), ...
        "Method",string(opt.FineCFOMethod),"Available",false, ...
        "ResidualEstimateHz",NaN,"SymbolsUsed",0, ...
        "ComplexProducts",0,"ComplexAdditions",0, ...
        "ExpectedUnambiguousRangeHz",double(ssbTiming.SSBSubcarrierSpacingKHz)*500);
    if logical(opt.FineCFOEnabled)
        if ~strcmpi(string(opt.FineCFOMethod),"cyclic_prefix")
            error("sixgr:phy:sync:UnsupportedFineCFOMethod", ...
                "Fine CFO method '%s' is unsupported; expected cyclic_prefix.", ...
                string(opt.FineCFOMethod));
        end
        fineInfo = localCyclicPrefixResidualCFO(coarseCorrected, ...
            sampleRateHz,selectedTimingOffset, ...
            candidateStartSymbols(bestWindowIndex),ssbTiming, ...
            double(opt.FineCFOMaxResidualHz), ...
            double(opt.FineCFOMinimumSymbols));
        if ~fineInfo.Available
            error("sixgr:phy:sync:FineCFOUnavailable", ...
                "CP-based fine CFO was enabled but fewer than %d complete SSB symbols were available.", ...
                double(opt.FineCFOMinimumSymbols));
        end
        fineResidualHz = double(fineInfo.ResidualEstimateHz);
    end
    freqOffsetHz = bestHz + fineResidualHz;
    rxOut = localFreqShift(xIn, sampleRateHz, -freqOffsetHz);
    NID2 = bestNID2;

    info = struct();
    info.SearchBW_Hz = searchBW_Hz;
    info.SSBCenterFrequencyOffsetHz = double(ssbCenterOffsetHz);
    info.SSBPlacementCorrectionAppliedHz = double(-ssbCenterOffsetHz);
    info.OscillatorCFOEstimateHz = double(freqOffsetHz);
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
    referenceLength = numel(selectedReference);
    timingLagsPerWindow = max(0, ...
        searchWindows(:,2)-searchWindows(:,1)+1-referenceLength+1);
    totalTimingLags = sum(timingLagsPerWindow);
    correlationVectors = numel(candNID2)*numel(candHz)*size(searchWindows,1);
    arithmeticScale = numel(candNID2)*numel(candHz)*size(rxWaveform,2);
    info.ReferenceLengthSamples = double(referenceLength);
    info.TimingLagsEvaluated = double(totalTimingLags*numel(candNID2)*numel(candHz));
    info.PSSSequences = double(numel(candNID2));
    info.PSSCorrelationVectors = double(correlationVectors);
    info.PSSComplexMultiplications = double(totalTimingLags*referenceLength*arithmeticScale);
    info.PSSComplexAdditions = double(totalTimingLags*max(referenceLength-1,0)*arithmeticScale);
    info.FFTCount = 0;
    info.CoarseCFOEstimateHz = double(bestHz);
    info.FineCFOEstimateHz = double(fineResidualHz);
    info.FinalCFOEstimateHz = double(freqOffsetHz);
    info.FineCFO = fineInfo;
    info.SSBTiming = ssbTiming;
end

function info = localCyclicPrefixResidualCFO(x,fs,pssStartZeroBased, ...
        candidateStartSymbol,ssbTiming,maxResidualHz,minSymbols)
carrier = nrCarrierConfig;
carrier.SubcarrierSpacing = double(ssbTiming.SSBSubcarrierSpacingKHz);
carrier.NSizeGrid = 20;
carrier.NStartGrid = 0;
carrier.CyclicPrefix = "normal";
sampling = sixgr.phy.frame.OFDMSamplingResolver.resolve( ...
    carrier,"SampleRate",double(fs),"WindowingSamples",0);
nfft = double(sampling.Nfft);
cp = double(sampling.CyclicPrefixLengthsPerSlot(:).');
symbolWithinSlot = mod(double(candidateStartSymbol),numel(cp));
cursor = round(double(pssStartZeroBased)) + 1;
accumulator = complex(0);
symbolsUsed = 0;
products = 0;
for symbolOffset = 0:3
    symbolIndex = symbolWithinSlot + symbolOffset + 1;
    if symbolIndex > numel(cp)
        break;
    end
    cpLength = cp(symbolIndex);
    first = cursor;
    lastPrefix = first + cpLength - 1;
    firstRepeated = first + nfft;
    lastRepeated = firstRepeated + cpLength - 1;
    if first < 1 || lastRepeated > size(x,1)
        break;
    end
    prefix = x(first:lastPrefix,:);
    repeated = x(firstRepeated:lastRepeated,:);
    terms = conj(prefix).*repeated;
    accumulator = accumulator + sum(terms,"all");
    products = products + numel(terms);
    symbolsUsed = symbolsUsed + 1;
    cursor = cursor + cpLength + nfft;
end
available = symbolsUsed >= minSymbols && isfinite(real(accumulator)) && ...
    isfinite(imag(accumulator)) && abs(accumulator) > 0;
residualHz = NaN;
if available
    residualHz = angle(accumulator)*double(fs)/(2*pi*nfft);
    if abs(residualHz) > maxResidualHz
        available = false;
    end
end
info = struct("Enabled",true,"Method","cyclic_prefix", ...
    "Available",logical(available),"ResidualEstimateHz",double(residualHz), ...
    "SymbolsUsed",double(symbolsUsed),"ComplexProducts",double(products), ...
    "ComplexAdditions",double(max(products-1,0)), ...
    "ExpectedUnambiguousRangeHz",double(fs)/(2*nfft));
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
    if isvector(x)
        x = x(:);
    end
    ref = ref(:);
    nLag = size(x,1)-numel(ref)+1;
    if nLag < 1
        metric = -Inf;
        lagIndex = NaN;
        return;
    end
    referenceEnergy = sum(abs(ref).^2);
    rho2 = zeros(nLag,size(x,2));
    for rxIndex = 1:size(x,2)
        c = abs(conv(x(:,rxIndex),flipud(conj(ref)),"valid"));
        windowEnergy = conv(abs(x(:,rxIndex)).^2,ones(numel(ref),1),"valid");
        rho2(:,rxIndex) = abs(c).^2 ./ ...
            max(windowEnergy.*referenceEnergy,realmin);
    end
    combinedCorrelation = sqrt(mean(rho2,2));
    [metric, lagIndex] = max(combinedCorrelation);
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
    sampleRows = size(x, 1);
    lastSample = min(sampleRows, firstSample + sampleCount - 1);
    if firstSample > sampleRows || lastSample < firstSample
        continue;
    end
    % Preserve receive branches. Single-subscript indexing linearizes an
    % Nsample-by-Nrx capture and creates false cross-antenna time windows.
    segments{end+1,1} = x(firstSample:lastSample, :); %#ok<AGROW>
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
