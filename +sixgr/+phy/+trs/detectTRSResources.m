function det = detectTRSResources(rx, cfg, tx, varargin)
%DETECTTRSRESOURCES Correlate received grid REs with configured TRS symbols.

p = inputParser;
p.addParameter("Timing", struct(), @isstruct);
p.parse(varargin{:});
timing = p.Results.Timing;
resources = localResolveSlotResources(cfg, tx);
timingT = sixgr.util.structGet(timing, "Table", table());
policy=string(sixgr.util.structGet(cfg,'DetectionPolicy','fixed_correlation'));
projectionPolicy=policy=="white_noise_projection_v1";
assert(isscalar(policy) && any(policy==["fixed_correlation","white_noise_projection_v1"]), ...
    'sixgr:phy:trs:InvalidDetectionPolicy','Install a supported TRS detection policy.');
searchHypotheses=NaN;
if projectionPolicy
    assert(tx.SampleRateHz==double(tx.OFDM.Nfft)*double(resources(1).Carrier.SubcarrierSpacing)*1000, ...
        'sixgr:phy:trs:UnqualifiedResampledNoise', ...
        'The projection candidate requires the native FFT sample clock; qualify resampled noise separately.');
    assert(isequal(sixgr.util.structGet(rx,'WhiteGaussianNoiseModelEstablished',false),true), ...
        'sixgr:phy:trs:UnestablishedWhiteNoiseModel', ...
        'Projection candidate requires executed equal-variance white Gaussian noise and no RX RF distortion.');
    assert(istable(timingT) && height(timingT)==numel(resources) && ...
        ismember('TimingHypothesisCount',timingT.Properties.VariableNames) && ...
        all(isfinite(timingT.TimingHypothesisCount) & timingT.TimingHypothesisCount>=1 & ...
        timingT.TimingHypothesisCount==fix(timingT.TimingHypothesisCount)), ...
        'sixgr:phy:trs:MissingTimingSearchEvidence','Retain every actual searched timing lag.');
    % A union bound over every lag AND every configured receive window.
    searchHypotheses=sum(timingT.TimingHypothesisCount);
end
rows = repmat(localDetectionRow(), numel(resources), 1);
slotDetections = repmat(localSlotDetection(), 0, 1);
for ii = 1:numel(resources)
    corrWave = [];
    window = struct();
    ofdmInfo = struct();
    rxGrid = [];
    metric = NaN;
    threshold = double(cfg.DetectionThreshold);
    statisticalDecision = false;
    falseAlarmBound = NaN;
    noiseAssumption = "";
    if projectionPolicy, threshold=NaN; end
    phase = NaN;
    branchPhase = [];
    nRx = NaN;
    observed = 0;
    status = "detection_failed";
    attempted = true;
    try
        estTiming = localTimingForSlot(timingT, resources(ii).Slot);
        [corrWave,window] = sixgr.phy.trs.extractTRSReceiveWindow( ...
            rx.Waveform,tx,ii,estTiming,resources(ii));
        [rxGrid,ofdmInfo] = sixgr.phy.waveform.ofdmDemodulate( ...
            resources(ii).Carrier, corrWave);
        assert(size(rxGrid,2)==window.SymbolCount, ...
            'sixgr:phy:trs:ReceiveSymbolCountMismatch', ...
            'Demodulated TRS symbols must match the retained sample window.');
        % A one-port reference occupies one RE plane; it does not mean the
        % receiver has one antenna. Extract the locations on every RX plane.
        K=size(rxGrid,1); L=size(rxGrid,2); nRx=size(rxGrid,3);
        indices=double(resources(ii).Indices(:));
        assert(resources(ii).Ports==1 && all(indices>=1 & indices<=K*L), ...
            'sixgr:phy:trs:ReferencePortIdentity', ...
            'Tracking references must identify one logical TRS port.');
        received=reshape(rxGrid,K*L,nRx);
        rxRE = received(indices,:);
        ref = resources(ii).Symbols(:);
        [metric,branchPhase] = sixgr.phy.trs.correlateTRSReceiveBranches(rxRE,ref);
        if projectionPolicy
            decision=sixgr.phy.trs.whiteNoiseCoherenceDecision(rxRE,ref, ...
                cfg.TargetFalseAlarmProbability,searchHypotheses);
            metric=decision.Correlation;
            threshold=decision.CorrelationThreshold;
            statisticalDecision=decision.Detected;
            falseAlarmBound=decision.SearchFalseAlarmBound;
            noiseAssumption=decision.NoiseAssumption;
        end
        % There is no common absolute channel phase across RX antennas.
        if nRx==1, phase=branchPhase; end
        observed = localObservedRECount(rxRE, double(rx.NoiseVariance), ...
            string(sixgr.util.structGet(rx, "FaultMode", "normal")));
        status = "detection_metric_available";
    catch ME
        status = "detection_failed:" + string(ME.identifier);
        rxRE = complex(zeros(0, 1));
    end
    coverage = double(observed) ./ max(double(resources(ii).NRE), 1);
    success = isfinite(metric) && metric >= threshold && ...
        coverage >= double(cfg.MinCoverageRatio);
    if projectionPolicy, success=success && statisticalDecision; end
    row = localDetectionRow();
    row.RunId = string(cfg.RunId);
    row.ConfigHash = string(cfg.ConfigHash);
    row.Slot = double(resources(ii).Slot);
    row.DetectionAttempted = logical(attempted);
    row.DetectionSuccess = logical(success);
    row.DetectionMetric = double(metric);
    row.DetectionThreshold = threshold;
    row.DetectionPolicy = policy;
    row.TargetFalseAlarmProbability = double(sixgr.util.structGet(cfg,'TargetFalseAlarmProbability',NaN));
    row.SearchHypothesisCount = searchHypotheses;
    row.SearchFalseAlarmBound = falseAlarmBound;
    row.NoiseAssumption = noiseAssumption;
    row.ExpectedRECount = double(resources(ii).NRE);
    row.ObservedRECount = double(observed);
    row.ResourceCoverageRatio = double(coverage);
    row.MinCoverageRatio = double(cfg.MinCoverageRatio);
    row.ReferencePhase_rad = double(phase);
    row.ReferencePhasePerReceiveBranch_rad = strjoin(string(branchPhase),"|");
    row.NumReceiveAntennas = double(nRx);
    row.DetectionMetricSource = "all_receive_branches_noncoherent_reference_correlation_power";
    if projectionPolicy, row.DetectionMetricSource="received_reference_projection_beta_tail_search_union_bound"; end
    row.NoiseVariance = double(rx.NoiseVariance);
    row.Status = string(status);
    row.TruthStatus = "real_lls_evidence";
    if ~isempty(fieldnames(window))
        row.ReceiveStartSample1Based = window.StartSample1Based;
        row.ReceiveEndSample1Based = window.EndSample1Based;
        row.ReceivedSymbolCount = window.SymbolCount;
        row.EstimatedTimingOffset_samples = window.TimingOffset_samples;
        row.ReceiveWindowSource = window.Source;
    end
    rows(ii) = row;
    s = localSlotDetection();
    s.Slot = double(resources(ii).Slot);
    s.RxGrid = rxGrid;
    s.RxRE = rxRE;
    s.ReferenceSymbols = resources(ii).Symbols(:);
    s.ReferenceIndices = resources(ii).Indices(:);
    s.CyclicPrefixFraction = double(sixgr.util.structGet(ofdmInfo,'CyclicPrefixFraction',NaN));
    s.Detected = logical(success);
    s.PhaseRad = double(phase);
    s.PhasePerReceiveBranchRad = branchPhase;
    s.Metric = double(metric);
    s.CoverageRatio = double(coverage);
    s.CorrectedWaveform = corrWave;
    slotDetections(end+1, 1) = s; %#ok<AGROW>
end

function resources = localResolveSlotResources(cfg, tx)
if isfield(tx, "SlotResources") && isfield(tx, "Config") && ...
        isfield(tx.Config, "ConfigHash") && string(tx.Config.ConfigHash) == string(cfg.ConfigHash)
    resources = tx.SlotResources;
else
    resources = sixgr.phy.trs.generateTRSSymbolsAndIndices(cfg).SlotResources;
end
end
det = struct();
det.Table = struct2table(rows, "AsArray", true);
det.SlotDetections = slotDetections;
det.DetectionAttempted = any([rows.DetectionAttempted]);
det.DetectionSuccess = all([rows.DetectionSuccess]);
det.MeanDetectionMetric = mean([rows.DetectionMetric], "omitnan");
det.MinCoverageRatio = min([rows.ResourceCoverageRatio]);
end

function est = localTimingForSlot(timingT, slot)
required = ["Slot","EstimatedTimingOffset_samples","TRSTimingEstimateAvailable"];
if ~istable(timingT) || ~all(ismember(required,string(timingT.Properties.VariableNames)))
    error('sixgr:phy:trs:MissingReceivedTiming','TRS demodulation requires a received timing estimate.');
end
idx = find(double(timingT.Slot)==double(slot));
if ~isscalar(idx) || ~isequal(timingT.TRSTimingEstimateAvailable(idx),true)
    error('sixgr:phy:trs:MissingReceivedTiming','TRS slot must have exactly one available received timing estimate.');
end
est = double(timingT.EstimatedTimingOffset_samples(idx));
validateattributes(est,{'numeric'},{'scalar','real','finite','integer'});
end

function row = localDetectionRow()
row = struct("RunId", "", "ConfigHash", "", "Slot", NaN, ...
    "DetectionAttempted", false, "DetectionSuccess", false, ...
    "DetectionMetric", NaN, "DetectionThreshold", NaN, "ExpectedRECount", NaN, ...
    "DetectionPolicy", "", "TargetFalseAlarmProbability", NaN, ...
    "SearchHypothesisCount", NaN, "SearchFalseAlarmBound", NaN, "NoiseAssumption", "", ...
    "ObservedRECount", NaN, "ResourceCoverageRatio", NaN, "MinCoverageRatio", NaN, ...
    "ReferencePhase_rad", NaN, "ReferencePhasePerReceiveBranch_rad", "", ...
    "NumReceiveAntennas", NaN, "DetectionMetricSource", "", ...
    "NoiseVariance", NaN, "Status", "", "TruthStatus", "", ...
    "ReceiveStartSample1Based",NaN,"ReceiveEndSample1Based",NaN, ...
    "ReceivedSymbolCount",NaN,"EstimatedTimingOffset_samples",NaN,"ReceiveWindowSource","");
end

function row = localSlotDetection()
row = struct("Slot", NaN, "RxGrid", [], "RxRE", [], "ReferenceSymbols", [], ...
    "Detected", false, "PhaseRad", NaN, "PhasePerReceiveBranchRad", [], ...
    "Metric", NaN, "CoverageRatio", NaN, ...
    "CorrectedWaveform", [], "ReferenceIndices", [], "CyclicPrefixFraction", NaN);
end

function observed = localObservedRECount(rxRE, noiseVariance, faultMode)
% Count physical RE locations, not RE-count times the number of RX antennas.
finiteMask = all(isfinite(rxRE),2);
if lower(strtrim(string(faultMode))) == "missing_resource_subset"
    amplitude=sqrt(sum(abs(rxRE).^2,2));
    ampThreshold = localCoverageAmplitudeThreshold(amplitude(finiteMask), ...
        size(rxRE,2)*noiseVariance);
    observed = nnz(finiteMask & amplitude > ampThreshold);
else
    observed = nnz(finiteMask);
end
end

function threshold = localCoverageAmplitudeThreshold(rxRE, noiseVariance)
if isfinite(double(noiseVariance))
    noiseThreshold = 2 * sqrt(max(double(noiseVariance), 0));
else
    noiseThreshold = 0;
end
rxAbs = abs(rxRE(:));
rxAbs = rxAbs(isfinite(rxAbs));
if isempty(rxAbs)
    threshold = noiseThreshold;
    return;
end
relativeThreshold = 0.1 * localPercentile(rxAbs, 90);
threshold = max(noiseThreshold, relativeThreshold);
end

function value = localPercentile(x, pct)
x = sort(double(x(:)));
x = x(isfinite(x));
if isempty(x)
    value = NaN;
    return;
end
pct = max(0, min(100, double(pct)));
idx = 1 + (numel(x) - 1) * pct / 100;
lo = max(1, floor(idx));
hi = min(numel(x), ceil(idx));
if lo == hi
    value = x(lo);
else
    frac = idx - lo;
    value = (1 - frac) * x(lo) + frac * x(hi);
end
end
