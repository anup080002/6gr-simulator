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
        prach = sixgr.phy.ul.applyPRACHCfgToObject(prach, cfg, carrier);
    else
        prach = opts.PRACH;
    end

    % PreambleIndex (per cell)
    if isempty(opts.PreambleIndex)
        preIdx = sixgr.util.structGet(cfg, "phy.prach.preambleIndex", 0);
    else
        preIdx = opts.PreambleIndex;
    end
    prach.PreambleIndex = preIdx;

    % NPRACHSlot controls the current PRACH slot in the OFDM modulator,
    % but it is never accepted as a direct Toolbox-only override. Both
    % default and explicit selections are mapped through the canonical
    % Release-18 occasion resolver first.
    if isempty(opts.NPRACHSlot)
        canonicalOccasion = sixgr.rach.mapPRACHToOccasion( ...
            cfg, "OccasionIndex", 1, "Carrier", carrier, "PRACH", prach);
    else
        canonicalOccasion = sixgr.rach.mapPRACHToOccasion( ...
            cfg, "NPRACHSlot", double(opts.NPRACHSlot), ...
            "Carrier", carrier, "PRACH", prach);
    end
    nslot = double(canonicalOccasion.PRACHSlotIndex0);
    carrier.NFrame = double(canonicalOccasion.Carrier.NFrame);
    carrier.NSlot = double(canonicalOccasion.Carrier.NSlot);
    prach.NPRACHSlot = nslot;
    prach.ActivePRACHSlot = double(canonicalOccasion.ActivePRACHSlot);
    prach.TimeIndex = double(canonicalOccasion.TimeIndex);
    prach.FrequencyIndex = double(canonicalOccasion.FrequencyIndex);

    % ---- Generate PRACH symbols and waveform -----------------------------
    % Symbols (and optional symbol info)
    [prachSym, symInfo] = nrPRACH( ...
        carrier, prach, "OutputDataType", char(opts.OutputDataType));

    if isempty(prachSym)
        error("sixgr:phy:ul:PRACH_Tx:InactiveOccasion", ...
            "PRACH slot %d is not active for configuration index %d.", ...
            nslot, double(prach.ConfigurationIndex));
    end

    % Indices and grid
    [prachInd, indInfo] = nrPRACHIndices(carrier, prach); % 1-based linear indices
    if isempty(prachInd)
        error("sixgr:phy:ul:PRACH_Tx:InactiveOccasion", ...
            "PRACH slot %d has no indices for configuration index %d.", ...
            nslot, double(prach.ConfigurationIndex));
    end
    prachGrid = nrPRACHGrid(carrier, prach);
    prachGrid(prachInd) = prachSym;

    % PRACH OFDM modulation (note: PRACH has dedicated OFDM numerology)
    if isempty(opts.Windowing)
        [waveform, ofdmInfo] = nrPRACHOFDMModulate( ...
            carrier, prach, prachGrid, "Windowing", 0);
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
    info.PRACHOccasion = canonicalOccasion;
end
