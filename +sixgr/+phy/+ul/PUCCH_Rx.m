function [rx, info] = PUCCH_Rx(rxWaveform, cfg, varargin)
%PUCCH_Rx Recover a basic PUCCH transmission (OFDM -> PUCCH -> UCI).
%
%   [RX,INFO] = sixgr.phy.ul.PUCCH_Rx(RXWAVEFORM, CFG) performs:
%     - OFDM demodulation
%     - DM-RS-based channel estimation (when DM-RS exists)
%     - Optional MMSE equalization
%     - nrPUCCHDecode to obtain soft UCI bits (formats 2/3/4) or hard bits
%       (formats 0/1)
%     - nrUCIDecode for formats 2/3/4 to recover uncoded UCI bits
%
%   Name-Value options:
%     "Carrier"            : nrCarrierConfig override
%     "PUCCH"              : override PUCCH config object (nrPUCCHxConfig)
%     "Format"             : 0|1|2|3|4 override (default: cfg.phy.pucch.format)
%     "NumUCIBits"         : number of uncoded UCI bits (formats 2/3/4)
%     "ExpectedUCIBits"    : optionally provide transmitted uncoded bits
%     "NoiseVar"           : explicit runtime noise variance metadata
%     "NoiseVarDomain"     : "time", "grid", "frequency", or "auto"
%     "ConfiguredNoiseVariance": explicit configured/derived AWGN variance
%     "Equalize"           : true/false (default: true)
%     "ChannelEstimatorFcn": channel-estimator function handle
%     "DetectionThreshold" : forwarded to nrPUCCHDecode (optional)
%
%   Outputs (RX struct):
%     .UCISoft        : cell array (formats 2/3/4) of soft bits
%     .UCIBits        : decoded uncoded UCI bits (formats 2/3/4) or hard bits
%     .Symbols        : constellation symbols returned by nrPUCCHDecode
%     .DetMetric      : detection metric returned by nrPUCCHDecode
%     .ChannelEstimate: H estimate grid (if estimated)
%     .NoiseVar       : noise variance used
%     .NoiseVarStatus : "OK" or "NOT_AVAILABLE"
%     .NoiseVarSource : provenance for the used/unavailable noise variance
%     .Ok             : true if decode succeeded
%
%   INFO returns intermediate artifacts for debugging.

    % ---- Parse name-value options ---------------------------------------
    p = inputParser;
    p.FunctionName = "sixgr.phy.ul.PUCCH_Rx";
    addRequired(p, "rxWaveform", @(x) isnumeric(x) && ~isempty(x));
    addRequired(p, "cfg", @(x) isstruct(x) || isobject(x));

    addParameter(p, "Carrier", [], @(x) isempty(x) || isa(x, "nrCarrierConfig"));
    addParameter(p, "PUCCH",   [], @(x) isempty(x) || isobject(x));
    addParameter(p, "Format",  [], @(x) isempty(x) || (isscalar(x) && isnumeric(x)));
    addParameter(p, "NumUCIBits", [], @(x) isempty(x) || (isscalar(x) && isnumeric(x) && x>=0));
    addParameter(p, "ExpectedUCIBits", [], @(x) isempty(x) || isnumeric(x) || islogical(x));
    addParameter(p, "NoiseVar", [], @(x) isempty(x) || isnumeric(x));
    addParameter(p, "NoiseVarDomain", "auto", @(x) any(strcmpi(char(string(x)), {'time','grid','frequency','auto'})));
    addParameter(p, "ConfiguredNoiseVariance", [], @(x) isempty(x) || isnumeric(x));
    addParameter(p, "ConfiguredNoiseVarianceSource", "configured_awgn_derivation", @(x) ischar(x) || isstring(x));
    addParameter(p, "StrictNoiseVarianceRequired", [], @(x) isempty(x) || islogical(x) || (isscalar(x) && isnumeric(x)));
    addParameter(p, "Equalize", true, @(x) islogical(x) || (isscalar(x) && (x==0 || x==1)));
    addParameter(p, "ChannelEstimatorFcn", @sixgr.phy.rx.channelEstimate, @(x) isa(x, "function_handle"));
    addParameter(p, "DetectionThreshold", [], @(x) isempty(x) || (isscalar(x) && isnumeric(x) && x>=0 && x<=1));
    addParameter(p, "DTXThreshold", sixgr.util.structGet(cfg, "phy.pucch.DTXThreshold", 0.2), @(x) isempty(x) || (isscalar(x) && isnumeric(x) && x>=0 && x<=1));

    parse(p, rxWaveform, cfg, varargin{:});
    opts = p.Results;

    % ---- Carrier ---------------------------------------------------------
    if isempty(opts.Carrier)
        carrier = sixgr.phy.grid.makeCarrier(cfg);
    else
        carrier = opts.Carrier;
    end

    % ---- Format and config ----------------------------------------------
    if isempty(opts.Format)
        fmt = sixgr.util.structGet(cfg, "phy.pucch.format", 2);
    else
        fmt = opts.Format;
    end

    if isempty(opts.PUCCH)
        pucch = localMakePUCCHConfig(fmt);
        pucch = localApplyPUCCHFromCfg(pucch, cfg, carrier);
    else
        pucch = opts.PUCCH;
    end

    % ---- Indices ---------------------------------------------------------
    [pucchInd, pucchInfo] = nrPUCCHIndices(carrier, pucch);

    dmrsInd = [];
    dmrsSym = [];
    try
        dmrsSym = nrPUCCHDMRS(carrier, pucch);
        dmrsInd = nrPUCCHDMRSIndices(carrier, pucch);
    catch
        dmrsSym = [];
        dmrsInd = [];
    end

    % ---- OFDM demod ------------------------------------------------------
    [rxGrid, ofdmInfo] = sixgr.phy.waveform.ofdmDemodulate(carrier, rxWaveform);

    % ---- Channel estimation / noise var ---------------------------------
    Hest = [];
    nVarEst = [];

    estInfo = struct();
    estimationAttempted = ~isempty(dmrsInd) && opts.Equalize;
    estimationFailed = false;
    if estimationAttempted
        try
            [Hest, nVarEst, estInfo] = opts.ChannelEstimatorFcn(carrier, rxGrid, dmrsInd, dmrsSym);
            if ~isempty(Hest) && size(Hest, 2) > 1
                Hest = localInterpolateChannelInTime(Hest);
            end
        catch ME
            Hest = [];
            nVarEst = [];
            estimationFailed = true;
            estInfo = struct( ...
                "Status", "failed", ...
                "FailureReason", "channel_estimation_failed", ...
                "ErrorIdentifier", string(ME.identifier), ...
                "ErrorMessage", string(ME.message));
        end
    end

    noiseCandidate = opts.NoiseVar;
    hasExplicitNoiseVariance = ~isempty(noiseCandidate);
    noiseSource = "runtime_metadata";
    noiseTransformInfo = struct( ...
        "InputDomain", "grid", ...
        "OutputDomain", "resource_grid_pre_equalization", ...
        "TransformSource", "runtime_channel_estimate_grid_domain");
    configuredNoiseTransformInfo = struct( ...
        "InputDomain", "time", ...
        "OutputDomain", "resource_grid_pre_equalization", ...
        "TransformSource", "not_requested");
    if isempty(noiseCandidate)
        noiseCandidate = nVarEst;
        noiseSource = "runtime_channel_estimate";
    else
        [noiseCandidate, noiseTransformInfo] = sixgr.phy.waveform.convertNoiseVarianceToGridDomain( ...
            noiseCandidate, ofdmInfo, ...
            "InputDomain", opts.NoiseVarDomain, ...
            "Source", noiseSource);
    end
    configuredNoiseVariance = opts.ConfiguredNoiseVariance;
    if ~isempty(configuredNoiseVariance)
        [configuredNoiseVariance, configuredNoiseTransformInfo] = sixgr.phy.waveform.convertNoiseVarianceToGridDomain( ...
            configuredNoiseVariance, ofdmInfo, ...
            "InputDomain", "time", ...
            "Source", opts.ConfiguredNoiseVarianceSource);
    end
    [nVar, noiseStatus] = sixgr.phy.ul.resolveULNoiseVariance(noiseCandidate, cfg, ...
        "ChannelType", "PUCCH", ...
        "OriginalSource", noiseSource, ...
        "StrictRequired", opts.StrictNoiseVarianceRequired, ...
        "ConfiguredNoiseVariance", configuredNoiseVariance, ...
        "ConfiguredNoiseVarianceSource", opts.ConfiguredNoiseVarianceSource);
    nVar = double(nVar);
    if ~logical(noiseStatus.IsValid)
        failureReason = string(noiseStatus.Reason);
        if estimationAttempted && estimationFailed && ~hasExplicitNoiseVariance
            failureReason = "channel_estimation_failed";
        end
        [rx, info] = localBuildUnavailablePUCCHRx( ...
            carrier, pucch, pucchInfo, Hest, rxGrid, pucchInd, dmrsInd, dmrsSym, estInfo, ...
            nVar, noiseStatus, logical(opts.Equalize), failureReason);
        return;
    end
    if estimationAttempted && isempty(Hest)
        if ~estimationFailed
            estimationFailed = true;
            if ~isstruct(estInfo) || numel(estInfo) ~= 1
                estInfo = struct();
            end
            estInfo.Status = "failed";
            estInfo.FailureReason = "channel_estimation_failed";
        end
        [rx, info] = localBuildUnavailablePUCCHRx( ...
            carrier, pucch, pucchInfo, Hest, rxGrid, pucchInd, dmrsInd, dmrsSym, estInfo, ...
            nVar, noiseStatus, false, "channel_estimation_failed");
        return;
    end

    % ---- Extract + equalize ---------------------------------------------
    rxSym = nrExtractResources(pucchInd, rxGrid);

    eqSym = rxSym;
    eqInfo = struct();
    if opts.Equalize && ~isempty(Hest)
        try
            [eqSym, ~, eqInfo] = sixgr.phy.rx.equalizeMMSE(rxGrid, Hest, nVar, "Indices", pucchInd);
        catch ME
            eqInfo = struct( ...
                "Status", "failed", ...
                "FailureReason", "equalization_failed", ...
                "ErrorIdentifier", string(ME.identifier), ...
                "ErrorMessage", string(ME.message));
            [rx, info] = localBuildUnavailablePUCCHRx( ...
                carrier, pucch, pucchInfo, Hest, rxGrid, pucchInd, dmrsInd, dmrsSym, estInfo, ...
                nVar, noiseStatus, false, "equalization_failed");
            info.Equalization = eqInfo;
            return;
        end
    end

    % ---- Decode ----------------------------------------------------------
    nv = {};
    if ~isempty(opts.DetectionThreshold)
        nv = {"DetectionThreshold", opts.DetectionThreshold};
    end

    % Determine ouci parameter for nrPUCCHDecode
    ouci = opts.NumUCIBits;
    if isempty(ouci) && ~isempty(opts.ExpectedUCIBits) && (fmt >= 2)
        ouci = numel(opts.ExpectedUCIBits);
    end
    if isempty(ouci) && (fmt >= 2)
        % Conservative default if caller didn't specify
        ouci = 20;
    end

    try
        if isempty(nv)
            [uciSoft, rxConst, detMet] = nrPUCCHDecode(carrier, pucch, ouci, eqSym, nVar);
        else
            [uciSoft, rxConst, detMet] = nrPUCCHDecode(carrier, pucch, ouci, eqSym, nVar, nv{:});
        end
    catch ME
        error("sixgr:phy:ul:PUCCH_Rx:DecodeFailed", "nrPUCCHDecode failed: %s", ME.message);
    end

    % Decode uncoded UCI (formats 2/3/4)
    uciBits = uciSoft;
    if fmt >= 2
        try
            uciBits = nrUCIDecode(uciSoft{1}, ouci);
        catch
            uciBits = [];
        end
    end
    dtxThreshold = localScalarOrNaN(opts.DTXThreshold);
    detectionFailureReason = localPUCCHDetectionFailureReason(fmt, ouci, uciBits, detMet, dtxThreshold);
    if double(fmt) == 0 && string(detectionFailureReason) == "correlation_metric_below_dtx_threshold"
        uciBits = int8([]);
    end
    detectionUsable = strlength(detectionFailureReason) == 0;
    detectionThreshold = localScalarOrNaN(opts.DetectionThreshold);
    if ~isfinite(detectionThreshold) && double(fmt) == 0
        detectionThreshold = dtxThreshold;
    end
    detectorPeakMetric = localFiniteDetectionMetric(detMet);
    expectedUCIBits = localNormalizeUCIBits(opts.ExpectedUCIBits);
    decodedUCIBits = localNormalizeUCIBits(uciBits);
    [uciBitErrors, uciBitsCompared, uciContentMatch] = localCompareUCIBits(expectedUCIBits, decodedUCIBits);
    detectionMetricStatus = "OK";
    if ~isfinite(detectorPeakMetric)
        detectionMetricStatus = "NOT_AVAILABLE";
    elseif ~logical(detectionUsable)
        detectionMetricStatus = "REVIEW_REQUIRED";
    end

    rx = struct();
    rx.Ok              = logical(detectionUsable);
    rx.UCISoft         = uciSoft;
    rx.UCIBits         = uciBits;
    rx.ExpectedUCIBits = expectedUCIBits;
    rx.ExpectedBitCount = double(numel(expectedUCIBits));
    rx.DecodedBitCount = double(numel(decodedUCIBits));
    rx.BitsCompared = double(uciBitsCompared);
    rx.BitErrors = double(uciBitErrors);
    rx.UCIContentMatch = logical(uciContentMatch);
    rx.FalseAck = logical(~isempty(expectedUCIBits) && ~logical(expectedUCIBits(1)) && ~isempty(decodedUCIBits) && logical(decodedUCIBits(1)));
    rx.FalseNack = logical(~isempty(expectedUCIBits) && logical(expectedUCIBits(1)) && ~isempty(decodedUCIBits) && ~logical(decodedUCIBits(1)));
    rx.Symbols         = rxConst;
    rx.DetMetric       = detMet;
    rx.DetectionThreshold = detectionThreshold;
    rx.DetectionMetricStatus = char(detectionMetricStatus);
    rx.DetectorPeakMetric = detectorPeakMetric;
    rx.DetectorNoiseFloor = nVar;
    rx.DTXFlag = ~logical(detectionUsable);
    rx.DTXReason = char(detectionFailureReason);
    rx.NoiseVar        = nVar;
    rx.NoiseVarDomain  = "resource_grid_pre_equalization";
    rx.NoiseVarTransformSource = char(string(sixgr.util.structGet(noiseTransformInfo, "TransformSource", "")));
    rx.SampleToGridNoiseVarianceGain = double(sixgr.util.structGet(noiseTransformInfo, "SampleToGridNoiseVarianceGain", NaN));
    rx.NoiseVarStatus  = char(string(noiseStatus.Status));
    rx.NoiseVarSource  = char(string(noiseStatus.Source));
    rx.NoiseVarReason  = char(string(noiseStatus.Reason));
    rx.NoiseVarStrictFailure = logical(noiseStatus.StrictFailure);
    rx.ReceiverUsable  = logical(detectionUsable);
    rx.DetectionAttempted = true;
    rx.DetectionUsable = logical(detectionUsable);
    rx.FailureReason   = char(detectionFailureReason);
    rx.ChannelEstimate = Hest;
    rx.Carrier         = carrier;
    rx.PUCCH           = pucch;
    rx.PUCCHInfo       = pucchInfo;
    rx.Equalized       = logical(opts.Equalize);

    info = struct();
    info.RxGrid       = rxGrid;
    info.PUCCHIndices = pucchInd;
    info.DMRSIndices  = dmrsInd;
    info.DMRSSymbols  = dmrsSym;
    info.Estimation   = estInfo;
    info.Equalization = eqInfo;
    info.NoiseVariance = noiseStatus;
    info.OFDM = ofdmInfo;
    info.OFDMNoiseTransform = sixgr.util.structGet(ofdmInfo, "NoiseTransform", struct());
    info.NoiseVarianceTransform = noiseTransformInfo;
    info.ConfiguredNoiseVarianceTransform = configuredNoiseTransformInfo;
    info.DetectionValidation = struct( ...
        "DetectionUsable", logical(detectionUsable), ...
        "FailureReason", string(detectionFailureReason), ...
        "DetectionThreshold", detectionThreshold, ...
        "DetectionMetricStatus", detectionMetricStatus, ...
        "DetectorPeakMetric", detectorPeakMetric, ...
        "DetectorNoiseFloor", nVar, ...
        "BitsCompared", double(uciBitsCompared), ...
        "BitErrors", double(uciBitErrors), ...
        "UCIContentMatch", logical(uciContentMatch), ...
        "DTXFlag", ~logical(detectionUsable));
end

% -------------------------------------------------------------------------
function pucch = localMakePUCCHConfig(fmt)
    switch double(fmt)
        case 0
            pucch = nrPUCCH0Config;
        case 1
            pucch = nrPUCCH1Config;
        case 2
            pucch = nrPUCCH2Config;
        case 3
            pucch = nrPUCCH3Config;
        case 4
            pucch = nrPUCCH4Config;
        otherwise
            error("sixgr:phy:ul:PUCCH_Rx:UnsupportedFormat", "Unsupported PUCCH format: %g", fmt);
    end
end

% -------------------------------------------------------------------------
function pucch = localApplyPUCCHFromCfg(pucch, cfg, carrier)
    if isprop(pucch, "NSizeBWP")
        pucch.NSizeBWP = sixgr.util.structGet(cfg, "phy.pucch.NSizeBWP", []);
    end
    if isprop(pucch, "NStartBWP")
        pucch.NStartBWP = sixgr.util.structGet(cfg, "phy.pucch.NStartBWP", []);
    end

    prbSet = sixgr.util.structGet(cfg, "phy.pucch.PRBSet", []);
    if ~isempty(prbSet) && isprop(pucch, "PRBSet")
        pucch.PRBSet = prbSet;
    end

    symAlloc = sixgr.util.structGet(cfg, "phy.pucch.SymbolAllocation", []);
    if isprop(pucch, "SymbolAllocation")
        if ~isempty(symAlloc)
            pucch.SymbolAllocation = symAlloc;
        else
            % Match TX default: ensure enough REs for nrUCIEncode min E>=31
            if isa(pucch, 'nrPUCCH2Config') || isa(pucch, 'nrPUCCH3Config') || isa(pucch, 'nrPUCCH4Config')
                pucch.SymbolAllocation = [0 2];
            end
        end
    end

    if isprop(pucch, "NID")
        nid = sixgr.util.structGet(cfg, "phy.pucch.NID", []);
        if isempty(nid)
            nid = carrier.NCellID;
        end
        pucch.NID = nid;
    end

    if isprop(pucch, "RNTI")
        pucch.RNTI = double(sixgr.util.structGet(cfg, "phy.rnti", 1));
    end

    if isprop(pucch, "NID0")
        nid0 = sixgr.util.structGet(cfg, "phy.pucch.NID0", []);
        if ~isempty(nid0)
            pucch.NID0 = nid0;
        end
    end

    if isprop(pucch, "FrequencyHopping")
        hopping = sixgr.util.structGet(cfg, "phy.pucch.FrequencyHopping", []);
        if isempty(hopping)
            hopping = sixgr.util.structGet(cfg, "phy.pucch.IntraSlotFrequencyHopping", []);
        end
        if ~isempty(hopping)
            if islogical(hopping) || isnumeric(hopping)
                pucch.FrequencyHopping = ternaryString(logical(hopping), "intraSlot", "neither");
            else
                pucch.FrequencyHopping = char(string(hopping));
            end
        end
    end

    if isprop(pucch, "SecondHopStartPRB")
        secondHop = sixgr.util.structGet(cfg, "phy.pucch.SecondHopStartPRB", ...
            sixgr.util.structGet(cfg, "phy.pucch.SecondHopPRB", []));
        if ~isempty(secondHop) && isfinite(double(secondHop))
            pucch.SecondHopStartPRB = max(0, round(double(secondHop)));
        end
    end

    if isprop(pucch, "InitialCyclicShift")
        cyclicShift = sixgr.util.structGet(cfg, "phy.pucch.InitialCyclicShift", []);
        if ~isempty(cyclicShift) && isfinite(double(cyclicShift))
            pucch.InitialCyclicShift = mod(round(double(cyclicShift)), 12);
        end
    end

    if isprop(pucch, "OCCI")
        occIndex = sixgr.util.structGet(cfg, "phy.pucch.OCCI", ...
            sixgr.util.structGet(cfg, "phy.pucch.OCCIndex", []));
        if ~isempty(occIndex) && isfinite(double(occIndex))
            pucch.OCCI = max(0, round(double(occIndex)));
        end
    end

    if isprop(pucch, "SpreadingFactor")
        occLength = sixgr.util.structGet(cfg, "phy.pucch.SpreadingFactor", ...
            sixgr.util.structGet(cfg, "phy.pucch.OCCLength", []));
        if ~isempty(occLength) && isfinite(double(occLength)) && double(occLength) > 0
            pucch.SpreadingFactor = max(1, round(double(occLength)));
        end
    end

    if isprop(pucch, "HoppingID")
        hoppingID = sixgr.util.structGet(cfg, "phy.pucch.HoppingID", []);
        if ~isempty(hoppingID) && isfinite(double(hoppingID))
            pucch.HoppingID = max(0, round(double(hoppingID)));
        end
    end
end

% -------------------------------------------------------------------------
function failureReason = localPUCCHDetectionFailureReason(fmt, ouci, uciBits, detMet, dtxThreshold)
failureReason = "";
if ~localHasFiniteDetectionMetric(detMet)
    failureReason = "pucch_detection_metric_unavailable";
    return;
end
if nargin >= 5 && double(fmt) == 0 && isfinite(double(dtxThreshold))
    detectorPeak = localFiniteDetectionMetric(detMet);
    if ~(isfinite(detectorPeak) && detectorPeak >= double(dtxThreshold))
        failureReason = "correlation_metric_below_dtx_threshold";
        return;
    end
end
expectedCount = NaN;
if ~isempty(ouci)
    expectedCount = max(0, round(double(ouci)));
end
if ~localHasUsableUCIBits(uciBits, expectedCount)
    failureReason = "pucch_uci_bits_unavailable";
end
end

function tf = localHasFiniteDetectionMetric(detMet)
tf = false;
if isempty(detMet) || ~isnumeric(detMet)
    return;
end
vals = double(detMet(:));
tf = any(isfinite(vals));
end

function metric = localFiniteDetectionMetric(detMet)
metric = NaN;
if isempty(detMet) || ~isnumeric(detMet)
    return;
end
vals = double(detMet(:));
vals = vals(isfinite(vals));
if ~isempty(vals)
    metric = vals(1);
end
end

function value = localScalarOrNaN(raw)
value = NaN;
if isempty(raw)
    return;
end
try
    vals = double(raw(:));
    vals = vals(isfinite(vals));
    if ~isempty(vals)
        value = vals(1);
    end
catch
    value = NaN;
end
end

function out = ternaryString(cond, a, b)
    if logical(cond)
        out = a;
    else
        out = b;
    end
end

function tf = localHasUsableUCIBits(uciBits, expectedCount)
tf = false;
if iscell(uciBits)
    if isempty(uciBits)
        return;
    end
    uciBits = uciBits{1};
end
if ~(isnumeric(uciBits) || islogical(uciBits))
    return;
end
vals = double(uciBits(:));
if isempty(vals) && isfinite(expectedCount) && expectedCount == 0
    tf = true;
    return;
end
if isempty(vals) || any(~isfinite(vals))
    return;
end
if isfinite(expectedCount) && numel(vals) < expectedCount
    return;
end
tf = true;
end

function Hout = localInterpolateChannelInTime(H)
Hout = H;
sz = size(H);
if numel(sz) < 2 || sz(2) <= 1
    return;
end
K = sz(1);
L = sz(2);
nRx = 1;
nTx = 1;
if numel(sz) >= 3
    nRx = sz(3);
end
if numel(sz) >= 4
    nTx = sz(4);
end
for rxIdx = 1:nRx
    for txIdx = 1:nTx
        if numel(sz) >= 4
            hSlice = squeeze(H(:, :, rxIdx, txIdx));
        elseif numel(sz) == 3
            hSlice = squeeze(H(:, :, rxIdx));
        else
            hSlice = H;
        end
        if isempty(hSlice)
            continue;
        end
        hasPilot = any(abs(hSlice) > 0 & isfinite(real(hSlice)) & isfinite(imag(hSlice)), 1);
        pilotSyms = find(hasPilot);
        if numel(pilotSyms) < 2
            continue;
        end
        allSyms = 1:L;
        interpSlice = complex(zeros(K, L, "like", hSlice));
        for k = 1:K
            interpSlice(k, :) = interp1(pilotSyms, hSlice(k, pilotSyms), allSyms, "linear", "extrap");
        end
        if numel(sz) >= 4
            Hout(:, :, rxIdx, txIdx) = interpSlice;
        elseif numel(sz) == 3
            Hout(:, :, rxIdx) = interpSlice;
        else
            Hout = interpSlice;
        end
    end
end
end

% -------------------------------------------------------------------------
function [rx, info] = localBuildUnavailablePUCCHRx( ...
        carrier, pucch, pucchInfo, Hest, rxGrid, pucchInd, dmrsInd, dmrsSym, estInfo, nVar, noiseStatus, equalized, failureReason)
if nargin < 13 || strlength(string(failureReason)) == 0
    failureReason = string(noiseStatus.Reason);
end
rx = struct();
rx.Ok = false;
rx.UCISoft = {};
rx.UCIBits = int8([]);
rx.Symbols = complex([]);
rx.DetMetric = NaN;
rx.DetectionThreshold = NaN;
rx.DetectionMetricStatus = "NOT_AVAILABLE";
rx.DetectorPeakMetric = NaN;
rx.DetectorNoiseFloor = double(nVar);
rx.DTXFlag = true;
rx.DTXReason = char(string(failureReason));
rx.NoiseVar = double(nVar);
rx.NoiseVarStatus = char(string(noiseStatus.Status));
rx.NoiseVarSource = char(string(noiseStatus.Source));
rx.NoiseVarReason = char(string(noiseStatus.Reason));
rx.NoiseVarStrictFailure = logical(noiseStatus.StrictFailure);
rx.ReceiverUsable = false;
rx.DetectionAttempted = false;
rx.DetectionUsable = false;
rx.FailureReason = char(string(failureReason));
rx.ChannelEstimate = Hest;
rx.Carrier = carrier;
rx.PUCCH = pucch;
rx.PUCCHInfo = pucchInfo;
rx.Equalized = logical(equalized);

info = struct();
info.RxGrid = rxGrid;
info.PUCCHIndices = pucchInd;
info.DMRSIndices = dmrsInd;
info.DMRSSymbols = dmrsSym;
info.Estimation = estInfo;
info.Equalization = struct();
info.NoiseVariance = noiseStatus;
info.DetectionValidation = struct( ...
    "DetectionUsable", false, ...
    "FailureReason", string(failureReason), ...
    "DetectionThreshold", NaN, ...
    "DetectionMetricStatus", "NOT_AVAILABLE", ...
    "DetectorPeakMetric", NaN, ...
    "DetectorNoiseFloor", double(nVar), ...
    "DTXFlag", true);
end

function bits = localNormalizeUCIBits(rawBits)
bits = int8([]);
if isempty(rawBits)
    return;
end
if iscell(rawBits)
    if isempty(rawBits)
        return;
    end
    rawBits = rawBits{1};
end
if ~(isnumeric(rawBits) || islogical(rawBits))
    return;
end
vals = double(rawBits(:));
vals = vals(isfinite(vals));
bits = int8(vals ~= 0);
end

function [bitErrors, bitsCompared, contentMatch] = localCompareUCIBits(expectedBits, decodedBits)
if isempty(expectedBits)
    bitErrors = NaN;
    bitsCompared = 0;
    contentMatch = true;
    return;
end
bitsCompared = min(numel(expectedBits), numel(decodedBits));
if bitsCompared > 0
    bitErrors = sum(expectedBits(1:bitsCompared) ~= decodedBits(1:bitsCompared));
else
    bitErrors = 0;
end
bitErrors = bitErrors + abs(numel(expectedBits) - numel(decodedBits));
contentMatch = (bitErrors == 0) && (numel(decodedBits) == numel(expectedBits));
end
