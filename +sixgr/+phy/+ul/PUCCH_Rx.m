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
    addParameter(p, "ConfiguredNoiseVariance", [], @(x) isempty(x) || isnumeric(x));
    addParameter(p, "ConfiguredNoiseVarianceSource", "configured_awgn_derivation", @(x) ischar(x) || isstring(x));
    addParameter(p, "StrictNoiseVarianceRequired", [], @(x) isempty(x) || islogical(x) || (isscalar(x) && isnumeric(x)));
    addParameter(p, "Equalize", true, @(x) islogical(x) || (isscalar(x) && (x==0 || x==1)));
    addParameter(p, "ChannelEstimatorFcn", @sixgr.phy.rx.channelEstimate, @(x) isa(x, "function_handle"));
    addParameter(p, "DetectionThreshold", [], @(x) isempty(x) || (isscalar(x) && isnumeric(x) && x>=0 && x<=1));

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
    rxGrid = nrOFDMDemodulate(carrier, rxWaveform);
    ofdmInfo = struct();
    try
        ofdmInfo = nrOFDMInfo(carrier);
    catch
        ofdmInfo = struct();
    end

    % ---- Channel estimation / noise var ---------------------------------
    Hest = [];
    nVarEst = [];

    estInfo = struct();
    estimationAttempted = ~isempty(dmrsInd) && opts.Equalize;
    estimationFailed = false;
    if estimationAttempted
        try
            [Hest, nVarEst, estInfo] = opts.ChannelEstimatorFcn(carrier, rxGrid, dmrsInd, dmrsSym);
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
    if isempty(noiseCandidate)
        noiseCandidate = nVarEst;
        noiseSource = "runtime_channel_estimate";
    else
        noiseCandidate = localConvertNoiseVarToGridDomain(noiseCandidate, ofdmInfo);
    end
    configuredNoiseVariance = opts.ConfiguredNoiseVariance;
    if ~isempty(configuredNoiseVariance)
        configuredNoiseVariance = localConvertNoiseVarToGridDomain(configuredNoiseVariance, ofdmInfo);
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

    rx = struct();
    rx.Ok              = true;
    rx.UCISoft         = uciSoft;
    rx.UCIBits         = uciBits;
    rx.Symbols         = rxConst;
    rx.DetMetric       = detMet;
    rx.NoiseVar        = nVar;
    rx.NoiseVarStatus  = char(string(noiseStatus.Status));
    rx.NoiseVarSource  = char(string(noiseStatus.Source));
    rx.NoiseVarReason  = char(string(noiseStatus.Reason));
    rx.NoiseVarStrictFailure = logical(noiseStatus.StrictFailure);
    rx.ReceiverUsable  = true;
    rx.DetectionAttempted = true;
    rx.DetectionUsable = true;
    rx.FailureReason   = "";
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
end

function nVarGrid = localConvertNoiseVarToGridDomain(nVarTime, ofdmInfo)
nVarGrid = double(nVarTime);
if nargin < 2 || ~isstruct(ofdmInfo)
    return;
end
nfft = double(sixgr.util.structGet(ofdmInfo, "Nfft", NaN));
if isfinite(nfft) && nfft > 0
    nVarGrid = nVarGrid * nfft;
end
end
