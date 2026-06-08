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
        prach = sixgr.phy.ul.applyPRACHCfgToObject(prach, cfg, carrier);
        nslot = localResolveDefaultNPRACHSlot(cfg, carrier, prach);
        try
            prach.NPRACHSlot = nslot;
        catch
        end
    else
        prach = opts.PRACH;
        nslot = prach.NPRACHSlot;
    end
    try
        carrier.NSlot = nslot;
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
    info.ResolvedNPRACHSlot = double(nslot);
end

% -------------------------------------------------------------------------
function nslot = localResolveDefaultNPRACHSlot(cfg, carrier, prach)
cfgSlot = sixgr.util.structGet(cfg, "phy.prach.nPrachSlot", []);
if isempty(cfgSlot)
    cfgSlot = sixgr.util.structGet(cfg, "phy.prach.NPRACHSlot", []);
end
if ~isempty(cfgSlot)
    vals = double(cfgSlot(:));
    vals = vals(isfinite(vals));
    if ~isempty(vals)
        nslot = vals(1);
        return;
    end
end

startSlot = double(carrier.NSlot);
if ~(isfinite(startSlot) && startSlot >= 0)
    startSlot = 0;
end
scanSlots = 160;
nslot = startSlot;
for offset = 0:scanSlots
    candidate = round(startSlot) + offset;
    c = carrier;
    p = prach;
    try
        c.NSlot = candidate;
    catch
    end
    try
        p.NPRACHSlot = candidate;
    catch
    end
    try
        sym = nrPRACH(c, p);
        ind = nrPRACHIndices(c, p);
        if ~isempty(sym) && ~isempty(ind)
            nslot = candidate;
            return;
        end
    catch
    end
end
end
