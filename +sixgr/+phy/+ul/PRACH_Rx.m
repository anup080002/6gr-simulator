function [rx, info] = PRACH_Rx(rxWaveform, cfg, varargin)
%PRACH_Rx Detect a PRACH preamble in a time-domain waveform.
%
%   [RX,INFO] = sixgr.phy.ul.PRACH_Rx(RXWAVEFORM, CFG) detects a PRACH
%   transmission using nrPRACHDetect. This is the typical "Msg1" receiver
%   primitive for random access procedures.
%
%   Name-Value options:
%     "Carrier"            : nrCarrierConfig override (default: make from cfg)
%     "PRACH"              : nrPRACHConfig override (default: make from cfg)
%     "DetectionThreshold" : [] or scalar in [0,1] (default: [])
%     "PreambleIndex"      : [] or array of candidate indices (0..63)
%
%   Outputs (RX):
%     .Ok            : true if a peak is detected above threshold
%     .PreambleIndex : detected preamble index (0..63) or []
%     .TimingOffset  : timing offset (samples) or []
%     .DetInfo       : struct from nrPRACHDetect (peaks, threshold)
%     .Carrier/.PRACH: configs used
%
%   INFO mirrors DetInfo and adds bookkeeping.

    % ---- Parse inputs ----------------------------------------------------
    p = inputParser;
    p.FunctionName = "sixgr.phy.ul.PRACH_Rx";
    addRequired(p, "rxWaveform", @(x) isnumeric(x) && ~isempty(x));
    addRequired(p, "cfg", @(x) isstruct(x) || isobject(x));
    addParameter(p, "Carrier", [], @(x) isempty(x) || isa(x, "nrCarrierConfig"));
    addParameter(p, "PRACH",   [], @(x) isempty(x) || isa(x, "nrPRACHConfig"));
    addParameter(p, "DetectionThreshold", [], @(x) isempty(x) || (isscalar(x) && isnumeric(x) && x>=0 && x<=1));
    addParameter(p, "PreambleIndex", [], @(x) isempty(x) || (isnumeric(x) && numel(x) <= 64));
    parse(p, rxWaveform, cfg, varargin{:});
    opts = p.Results;

    % ---- Build configs ---------------------------------------------------
    if isempty(opts.Carrier)
        carrier = sixgr.phy.grid.makeCarrier(cfg);
    else
        carrier = opts.Carrier;
    end

    if isempty(opts.PRACH)
        prach = nrPRACHConfig;
        prach = localApplyPRACHFromCfg(prach, cfg, carrier);
    else
        prach = opts.PRACH;
    end
    try
        carrier.NSlot = prach.NPRACHSlot;
    catch
    end

    % ---- Detection -------------------------------------------------------
    nv = {};
    if ~isempty(opts.DetectionThreshold)
        nv = [nv {"DetectionThreshold", opts.DetectionThreshold}]; %#ok<AGROW>
    end
    if ~isempty(opts.PreambleIndex)
        nv = [nv {"PreambleIndex", opts.PreambleIndex}]; %#ok<AGROW>
    end

    try
        [idx, offset, detInfo] = nrPRACHDetect(carrier, prach, rxWaveform, nv{:});
    catch ME
        error("sixgr:phy:ul:PRACH_Rx:Failed", "nrPRACHDetect failed: %s", ME.message);
    end

    rx = struct();
    rx.Ok           = ~isempty(idx);
    rx.PreambleIndex = idx;
    rx.TimingOffset = offset;
    rx.DetInfo      = detInfo;
    rx.Carrier      = carrier;
    rx.PRACH        = prach;

    info = struct();
    info.DetectionInfo = detInfo;
    info.PreambleIndex = idx;
    info.TimingOffset  = offset;
end

% -------------------------------------------------------------------------
function prach = localApplyPRACHFromCfg(prach, cfg, carrier)
% Keep consistent with PRACH_Tx local helper (duplicated intentionally).

    duplex = sixgr.util.structGet(cfg, "phy.duplex.mode", "TDD");
    try
        if strcmpi(duplex, "FDD")
            prach.DuplexMode = "FDD";
        else
            prach.DuplexMode = "TDD";
        end
    catch
    end

    fc = sixgr.util.structGet(cfg, "channel.fc_Hz", 3.5e9);
    try
        if fc >= 24.25e9
            prach.FrequencyRange = "FR2";
        else
            prach.FrequencyRange = "FR1";
        end
    catch
    end

    cfgIdx = sixgr.util.structGet(cfg, "phy.prach.configurationIndex", []);
    if ~isempty(cfgIdx)
        try
            prach.ConfigurationIndex = cfgIdx;
        catch
        end
    end

    scs = sixgr.util.structGet(cfg, "phy.prach.subcarrierSpacing_kHz", []);
    if ~isempty(scs)
        try
            prach.SubcarrierSpacing = scs;
        catch
        end
    end

    seqIdx = sixgr.util.structGet(cfg, "phy.prach.rootSeqIndex", []);
    if ~isempty(seqIdx)
        try
            prach.SequenceIndex = seqIdx;
        catch
        end
    end

    zcz = sixgr.util.structGet(cfg, "phy.prach.zeroCorrelationZone", []);
    if ~isempty(zcz)
        try
            prach.ZeroCorrelationZone = zcz;
        catch
        end
    end

    try
        prach.NPRACHSlot = carrier.NSlot;
    catch
    end
end
