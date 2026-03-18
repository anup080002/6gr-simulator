function [tx, info] = PUCCH_Tx(cfg, uciBits, varargin)
%PUCCH_Tx Create a basic PUCCH transmission (UCI -> PUCCH -> OFDM waveform).
%
%   [TX,INFO] = sixgr.phy.ul.PUCCH_Tx(CFG, UCIBITS) creates a PUCCH waveform
%   using 5G Toolbox primitives.
%
%   Supported formats:
%     - Format 0/1: UCIBITS are mapped directly (no nrUCIEncode used)
%     - Format 2/3/4: UCIBITS are encoded using nrUCIEncode to length G
%       (where G comes from nrPUCCHIndices(...).G)
%
%   Name-Value options:
%     "Carrier"   : nrCarrierConfig override (default: from cfg)
%     "Format"    : 0|1|2|3|4 override (default: cfg.phy.pucch.format)
%     "PUCCH"     : override PUCCH config object (nrPUCCHxConfig)
%     "IsCoded"   : true if uciBits are already coded to length G
%     "RNTI"      : override RNTI (default: cfg.phy.rnti or 1)
%     "IndexBase" : "1based"|"0based" (applies when IndexStyle='subscript')
%
%   Outputs (TX struct):
%     .Waveform      : time-domain OFDM waveform
%     .Grid          : K-by-L-by-P resource grid
%     .Carrier       : nrCarrierConfig
%     .PUCCH         : PUCCH configuration object
%     .PUCCHIndices  : RE indices used for PUCCH
%     .DMRSIndices   : RE indices used for PUCCH DM-RS (when applicable)
%     .UCIBits       : original uncoded UCI bits
%     .CodedUCI      : coded UCI bits (formats 2/3/4)
%
%   Notes:
%     - nrUCIEncode requires Euci >= 31 for polar coding / rate matching.
%       If the configured PUCCH resources yield G < 31, you must allocate
%       more PUCCH REs (e.g. 2 symbols instead of 1, or more PRBs).
%
%   See also: nrPUCCH, nrPUCCHIndices, nrUCIEncode, nrOFDMModulate

    % ---- Parse name-value options ---------------------------------------
    p = inputParser;
    p.FunctionName = "sixgr.phy.ul.PUCCH_Tx";
    addRequired(p, "cfg", @(x) isstruct(x) || isobject(x));
    addRequired(p, "uciBits", @(x) isnumeric(x) || islogical(x));

    addParameter(p, "Carrier", [], @(x) isempty(x) || isa(x, "nrCarrierConfig"));
    addParameter(p, "Format",  [], @(x) isempty(x) || (isscalar(x) && isnumeric(x)));
    addParameter(p, "PUCCH",   [], @(x) isempty(x) || isobject(x));
    addParameter(p, "IsCoded", false, @(x) islogical(x) || (isscalar(x) && (x==0 || x==1)));
    addParameter(p, "RNTI",    [], @(x) isempty(x) || (isscalar(x) && isnumeric(x)));
    addParameter(p, "IndexBase", "1based", @(x) ischar(x) || isstring(x));

    parse(p, cfg, uciBits, varargin{:});
    in = p.Results;

    % Normalize bits
    uciBits = uciBits(:);

    % ---- Carrier ---------------------------------------------------------
    if isempty(in.Carrier)
        carrier = sixgr.phy.grid.makeCarrier(cfg);
    else
        carrier = in.Carrier;
    end

    % ---- Determine format ------------------------------------------------
    if isempty(in.Format)
        fmt = sixgr.util.structGet(cfg, "phy.pucch.format", 2);
    else
        fmt = in.Format;
    end

    % ---- Build/override PUCCH object ------------------------------------
    if isempty(in.PUCCH)
        pucch = localMakePUCCHConfig(fmt);
        pucch = localApplyPUCCHFromCfg(pucch, cfg, carrier);
    else
        pucch = in.PUCCH;
    end

    % RNTI override
    if isprop(pucch, "RNTI")
        if ~isempty(in.RNTI)
            pucch.RNTI = double(in.RNTI);
        else
            pucch.RNTI = double(sixgr.util.structGet(cfg, "phy.rnti", 1));
        end
    end

    % ---- Indices and sizes ----------------------------------------------
    try
        [pucchInd, pucchInfo] = nrPUCCHIndices(carrier, pucch);
    catch ME
        error("sixgr:phy:ul:PUCCH_Tx:IndicesFailed", "nrPUCCHIndices failed: %s", ME.message);
    end

    % For formats 2/3/4, pucchInfo.G is the required coded length.
    G = [];
    if isfield(pucchInfo, 'G')
        G = double(pucchInfo.G);
    end

    % ---- UCI encoding (formats 2/3/4) -----------------------------------
    codedUCI = [];
    if fmt <= 1
        % Formats 0/1: no UCI polar encoding in toolbox flow
        uciForPUCCH = uciBits;
    else
        if isempty(G)
            error("sixgr:phy:ul:PUCCH_Tx:MissingG", "PUCCHInfo.G not available; cannot size UCI encoding.");
        end

        if ~in.IsCoded
            try
                codedUCI = nrUCIEncode(uciBits, G);
            catch ME
                error("sixgr:phy:ul:PUCCH_Tx:UCIEncodeFailed", ...
                    ["nrUCIEncode failed (A=%d uncoded bits, G=%d coded bits).\n" ...
                     "This typically means the configured PUCCH resources are too small for the requested UCI payload.\n" ...
                     "Fix: allocate more PUCCH resources, e.g. cfg.phy.pucch.SymbolAllocation=[0 2] (2 symbols) " ...
                     "or increase cfg.phy.pucch.PRBSet (e.g. 0:1).\n" ...
                     "Original error: %s"], numel(uciBits), G, ME.message);
            end

        else
            codedUCI = uciBits;
            if numel(codedUCI) ~= G
                error("sixgr:phy:ul:PUCCH_Tx:CodedLengthMismatch", ...
                    "IsCoded=true but length(uciBits)=%d ~= G=%d from nrPUCCHIndices. Provide G coded bits.", ...
                    numel(codedUCI), G);
            end
        end
        uciForPUCCH = codedUCI;
    end

    % ---- Generate PUCCH symbols and DM-RS --------------------------------
    try
        pucchSym = nrPUCCH(carrier, pucch, uciForPUCCH);
    catch ME
        error("sixgr:phy:ul:PUCCH_Tx:PUCCHFailed", "nrPUCCH failed: %s", ME.message);
    end

    dmrsInd = [];
    dmrsSym = [];
    try
        dmrsSym = nrPUCCHDMRS(carrier, pucch);
        dmrsInd = nrPUCCHDMRSIndices(carrier, pucch);
    catch
        dmrsInd = [];
        dmrsSym = [];
    end

    % ---- Resource grid mapping -------------------------------------------
    K = carrier.NSizeGrid * 12;
    L = carrier.SymbolsPerSlot;
    % Number of ports for mapping inferred from indices
    P = max([size(pucchInd,2), size(dmrsInd,2), 1]);

    txGrid = complex(zeros([K L P]));
    txGrid(pucchInd) = pucchSym;
    if ~isempty(dmrsInd)
        txGrid(dmrsInd) = dmrsSym;
    end

    % ---- OFDM modulation -------------------------------------------------
    [waveform, ofdmInfo] = sixgr.phy.waveform.ofdmModulate(carrier, txGrid);

    % ---- Outputs ---------------------------------------------------------
    tx = struct();
    tx.Waveform     = waveform;
    tx.Grid         = txGrid;
    tx.Carrier      = carrier;
    tx.PUCCH        = pucch;
    tx.PUCCHIndices = pucchInd;
    tx.DMRSIndices  = dmrsInd;
    tx.UCIBits      = uciBits;
    tx.CodedUCI     = codedUCI;

    info = struct();
    info.OFDMInfo    = ofdmInfo;
    info.PUCCHInfo   = pucchInfo;
    info.Format      = fmt;
    info.IndexBase   = char(in.IndexBase);
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
            error("sixgr:phy:ul:PUCCH_Tx:UnsupportedFormat", "Unsupported PUCCH format: %g", fmt);
    end
end

% -------------------------------------------------------------------------
function pucch = localApplyPUCCHFromCfg(pucch, cfg, carrier)
    % BWP (optional)
    if isprop(pucch, "NSizeBWP")
        pucch.NSizeBWP = sixgr.util.structGet(cfg, "phy.pucch.NSizeBWP", []);
    end
    if isprop(pucch, "NStartBWP")
        pucch.NStartBWP = sixgr.util.structGet(cfg, "phy.pucch.NStartBWP", []);
    end

    % PRB allocation
    prbSet = sixgr.util.structGet(cfg, "phy.pucch.PRBSet", []);
    if ~isempty(prbSet) && isprop(pucch, "PRBSet")
        pucch.PRBSet = prbSet;
    end

    % Symbol allocation
    symAlloc = sixgr.util.structGet(cfg, "phy.pucch.SymbolAllocation", []);
    if isprop(pucch, "SymbolAllocation")
        if ~isempty(symAlloc)
            pucch.SymbolAllocation = symAlloc;
        else
            % Important: for formats 2/3/4, ensure enough REs so that
            % nrPUCCHIndices returns G>=31 (required by nrUCIEncode).
            if isa(pucch, 'nrPUCCH2Config') || isa(pucch, 'nrPUCCH3Config') || isa(pucch, 'nrPUCCH4Config')
                pucch.SymbolAllocation = [0 2]; % 2 symbols by default
            end
        end
    end

    % Scrambling identity
    if isprop(pucch, "NID")
        nid = sixgr.util.structGet(cfg, "phy.pucch.NID", []);
        if isempty(nid)
            nid = carrier.NCellID;
        end
        pucch.NID = nid;
    end

    % Optional NID0 for format 0/1
    if isprop(pucch, "NID0")
        nid0 = sixgr.util.structGet(cfg, "phy.pucch.NID0", []);
        if ~isempty(nid0)
            pucch.NID0 = nid0;
        end
    end
end
