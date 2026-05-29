function [tx, info] = PRACH_Tx(cfg, varargin)
%PRACH_Tx Generate a PRACH preamble waveform (grid -> PRACH OFDM).
%
%   [TX,INFO] = sixgr.phy.ul.PRACH_Tx(CFG) creates an nrCarrierConfig and an
%   nrPRACHConfig from CFG.phy and generates a single PRACH instance.
%
%   This is a thin, toolbox-first implementation: it relies on 5G Toolbox
%   functions (nrPRACH/nrPRACHIndices/nrPRACHGrid/nrPRACHOFDMModulate) and
%   returns a consistent struct used by the SixGR simulator pipelines.
%
%   Name-Value options:
%     "Carrier"       : nrCarrierConfig override (default: make from cfg)
%     "PRACH"         : nrPRACHConfig override (default: make from cfg)
%     "PreambleIndex" : 0..63 (default: cfg.phy.prach.preambleIndex or 0)
%     "NPRACHSlot"    : PRACH slot index (default: carrier.NSlot)
%     "Windowing"     : windowing samples for nrPRACHOFDMModulate (default: [])
%     "OutputDataType": "double" or "single" (default: "double")
%
%   Outputs (TX):
%     .Waveform    : time-domain PRACH waveform (T-by-P)
%     .Grid        : PRACH resource grid (K-by-L-by-P)
%     .Symbols     : PRACH symbols (column)
%     .Indices     : PRACH RE indices (linear)
%     .Carrier     : nrCarrierConfig used
%     .PRACH       : nrPRACHConfig used
%     .SampleRate  : OFDM sample rate (Hz)
%
%   INFO contains tool-specific metadata (indices info, OFDM info, etc).

    % ---- Parse inputs ----------------------------------------------------
    p = inputParser;
    p.FunctionName = "sixgr.phy.ul.PRACH_Tx";
    addRequired(p, "cfg", @(x) isstruct(x) || isobject(x));
    addParameter(p, "Carrier", [], @(x) isempty(x) || isa(x, "nrCarrierConfig"));
    addParameter(p, "PRACH",   [], @(x) isempty(x) || isa(x, "nrPRACHConfig"));
    addParameter(p, "PreambleIndex", [], @(x) isempty(x) || (isscalar(x) && isnumeric(x)));
    addParameter(p, "NPRACHSlot", [], @(x) isempty(x) || (isscalar(x) && isnumeric(x)));
    addParameter(p, "Windowing", [], @(x) isempty(x) || (isscalar(x) && isnumeric(x) && x >= 0));
    addParameter(p, "OutputDataType", "double", @(x) ischar(x) || isstring(x));
    parse(p, cfg, varargin{:});
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

    % PreambleIndex (per cell)
    if isempty(opts.PreambleIndex)
        preIdx = sixgr.util.structGet(cfg, "phy.prach.preambleIndex", 0);
    else
        preIdx = opts.PreambleIndex;
    end
    try
        prach.PreambleIndex = preIdx;
    catch
        % Some configurations do not require explicit PreambleIndex at TX time.
    end

    % NPRACHSlot (controls current PRACH slot in OFDM modulator)
    if isempty(opts.NPRACHSlot)
        nslot = localResolveDefaultNPRACHSlot(cfg, carrier, prach);
    else
        nslot = opts.NPRACHSlot;
    end
    try
        carrier.NSlot = nslot;
    catch
        % Leave carrier slot unchanged if the property is unavailable
    end
    try
        prach.NPRACHSlot = nslot;
    catch
        % Leave default if property not available
    end

    % ---- Generate PRACH symbols and waveform -----------------------------
    % Symbols (and optional symbol info)
    symInfo = struct();
    try
        [prachSym, symInfo] = nrPRACH(carrier, prach, "OutputDataType", char(opts.OutputDataType));
    catch ME
        % Fallback: older signature without OutputDataType
        try
            [prachSym, symInfo] = nrPRACH(carrier, prach);
        catch
            error("sixgr:phy:ul:PRACH_Tx:Failed", "nrPRACH failed: %s", ME.message);
        end
    end

    if isempty(prachSym)
        tx = struct();
        tx.Waveform   = [];
        tx.Grid       = [];
        tx.Symbols    = prachSym;
        tx.Indices    = [];
        tx.Carrier    = carrier;
        tx.PRACH      = prach;
        tx.SampleRate = NaN;

        info = struct();
        info.SymbolInfo = symInfo;
        info.IndicesInfo = struct();
        info.OFDMInfo = struct("SampleRate", NaN);
        info.ActiveOccasionPresent = false;
        info.ResolvedNPRACHSlot = double(nslot);
        return;
    end

    % Indices and grid
    [prachInd, indInfo] = nrPRACHIndices(carrier, prach); % 1-based linear indices
    if isempty(prachInd)
        tx = struct();
        tx.Waveform   = [];
        tx.Grid       = [];
        tx.Symbols    = prachSym;
        tx.Indices    = prachInd;
        tx.Carrier    = carrier;
        tx.PRACH      = prach;
        tx.SampleRate = NaN;

        info = struct();
        info.SymbolInfo = symInfo;
        info.IndicesInfo = indInfo;
        info.OFDMInfo = struct("SampleRate", NaN);
        info.ActiveOccasionPresent = false;
        info.ResolvedNPRACHSlot = double(nslot);
        return;
    end
    prachGrid = nrPRACHGrid(carrier, prach);
    prachGrid(prachInd) = prachSym;

    % PRACH OFDM modulation (note: PRACH has dedicated OFDM numerology)
    if isempty(opts.Windowing)
        [waveform, ofdmInfo] = nrPRACHOFDMModulate(carrier, prach, prachGrid);
    else
        [waveform, ofdmInfo] = nrPRACHOFDMModulate(carrier, prach, prachGrid, "Windowing", opts.Windowing);
    end

    % ---- Pack outputs ----------------------------------------------------
    tx = struct();
    tx.Waveform   = waveform;
    tx.Grid       = prachGrid;
    tx.Symbols    = prachSym;
    tx.Indices    = prachInd;
    tx.Carrier    = carrier;
    tx.PRACH      = prach;
    tx.SampleRate = ofdmInfo.SampleRate;

    info = struct();
    info.SymbolInfo  = symInfo;
    info.IndicesInfo = indInfo;
    info.OFDMInfo    = ofdmInfo;
    info.ActiveOccasionPresent = true;
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

% -------------------------------------------------------------------------
function prach = localApplyPRACHFromCfg(prach, cfg, carrier)
% Apply cfg.phy.prach fields into an nrPRACHConfig object (best-effort).
%
% We keep this "forgiving": unknown/missing fields just fall back to default
% object values. This lets you evolve cfg without breaking callers.

    % Duplex mode mapping (cfg.phy.duplex.mode -> prach.DuplexMode)
    duplex = sixgr.util.structGet(cfg, "phy.duplex.mode", "TDD");
    try
        if strcmpi(duplex, "FDD")
            prach.DuplexMode = "FDD";
        else
            prach.DuplexMode = "TDD";
        end
    catch
    end

    % Frequency range heuristic (FR2 if fc >= 24.25 GHz)
    fc = sixgr.util.structGet(cfg, "channel.fc_Hz", 3.5e9);
    try
        if fc >= 24.25e9
            prach.FrequencyRange = "FR2";
        else
            prach.FrequencyRange = "FR1";
        end
    catch
    end

    % Configuration index (drives PRACH format and occasions)
    cfgIdx = sixgr.util.structGet(cfg, "phy.prach.configurationIndex", []);
    if ~isempty(cfgIdx)
        try
            prach.ConfigurationIndex = cfgIdx;
        catch
        end
    end

    % PRACH subcarrier spacing in kHz (can be 1.25/5/15/30/60/120 depending on FR)
    scs = sixgr.util.structGet(cfg, "phy.prach.subcarrierSpacing_kHz", []);
    if ~isempty(scs)
        try
            prach.SubcarrierSpacing = scs;
        catch
        end
    end

    % Root sequence index (SequenceIndex in nrPRACHConfig)
    seqIdx = sixgr.util.structGet(cfg, "phy.prach.rootSeqIndex", []);
    if ~isempty(seqIdx)
        try
            prach.SequenceIndex = seqIdx;
        catch
        end
    end

    % Zero-correlation zone configuration index
    zcz = sixgr.util.structGet(cfg, "phy.prach.zeroCorrelationZone", []);
    if ~isempty(zcz)
        try
            prach.ZeroCorrelationZone = zcz;
        catch
        end
    end

    % Optionally align carrier numerology used by PRACH OFDM functions
    % (They only use NSizeGrid/SubcarrierSpacing/CyclicPrefix)
    try
        prachSlots = sixgr.util.structGet(cfg, "phy.prach.nPrachSlot", []);
        if ~isempty(prachSlots)
            prach.NPRACHSlot = prachSlots;
        else
            prach.NPRACHSlot = carrier.NSlot;
        end
    catch
    end
end
