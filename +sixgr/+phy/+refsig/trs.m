function [trsInd, trsSym, info] = trs(carrier, cfgOrTrs, varargin)
%TRS Generate a lightweight tracking reference signal resource.
%
%   [IND,SYM,INFO] = sixgr.phy.refsig.trs(CARRIER, CFG) generates a
%   deterministic TRS resource from cfg.phy.trs.* settings. This helper is
%   simulator-focused and is intended for tracking/reference experiments.

opts.IndexBase = "1based";
for i = 1:2:numel(varargin)
    if i + 1 > numel(varargin)
        break;
    end
    key = lower(string(varargin{i}));
    switch key
        case "indexbase"
            opts.IndexBase = string(varargin{i+1});
    end
end

cfg = localResolveTRSCfg(cfgOrTrs);
enabled = logical(sixgr.util.structGet(cfg, "enable", false));
if ~enabled
    trsInd = zeros(0, 1);
    trsSym = complex(zeros(0, 1));
    info = struct("Channel", "TRS", "Enabled", false);
    return;
end

K = double(carrier.NSizeGrid) * 12;
L = double(carrier.SymbolsPerSlot);
numPorts = max(1, round(double(sixgr.util.structGet(cfg, "nPorts", 1))));
symbolLoc = localResolveSymbolLocations(cfg, L);
comb = max(1, round(double(sixgr.util.structGet(cfg, "subcarrierComb", 4))));
subcarrierOffset = max(0, round(double(sixgr.util.structGet(cfg, "subcarrierOffset", 0))));
rbOffset = max(0, round(double(sixgr.util.structGet(cfg, "rbOffset", 0))));
numRB = max(1, min(round(double(sixgr.util.structGet(cfg, "numRB", double(carrier.NSizeGrid)))), double(carrier.NSizeGrid) - rbOffset));
scramblingID = max(0, round(double(sixgr.util.structGet(cfg, "scramblingID", 0))));

scStart = rbOffset * 12 + 1 + subcarrierOffset;
scStop = min(K, (rbOffset + numRB) * 12);
subcarriers = scStart:comb:scStop;

if isempty(subcarriers) || isempty(symbolLoc)
    trsInd = zeros(0, 1);
    trsSym = complex(zeros(0, 1));
    info = struct("Channel", "TRS", "Enabled", false, "Reason", "empty_mapping");
    return;
end

[scGrid, symGrid, portGrid] = ndgrid(subcarriers, symbolLoc, 1:numPorts);
linInd = sub2ind([K, L, numPorts], scGrid(:), symGrid(:), portGrid(:));
slotsPerFrame = double(carrier.SlotsPerFrame);
if ~(isscalar(slotsPerFrame) && isfinite(slotsPerFrame) && ...
        slotsPerFrame >= 1 && slotsPerFrame == fix(slotsPerFrame))
    error("sixgr:phy:refsig:trs:MissingSlotsPerFrame", ...
        "TRS generation requires carrier-resolved SlotsPerFrame.");
end
slotInFrame = mod(round(double(carrier.NSlot)), slotsPerFrame);
seq = complex(zeros(numel(linInd), 1));
for ii = 1:numel(symbolLoc)
    sym = double(symbolLoc(ii));
    mask = symGrid(:) == sym;
    seq(mask) = localQPSKSequence(nnz(mask), scramblingID, slotInFrame, sym - 1);
end

trsInd = linInd;
if strcmpi(opts.IndexBase, "0based")
    trsInd = trsInd - 1;
end
trsSym = seq;

info = struct();
info.Channel = "TRS";
info.Enabled = true;
info.NumPorts = double(numPorts);
info.SymbolLocations = double(symbolLoc(:).');
info.SubcarrierComb = double(comb);
info.RBOffset = double(rbOffset);
info.NumRB = double(numRB);
info.ScramblingID = double(scramblingID);
info.NRE = double(numel(trsInd));
end

function cfg = localResolveTRSCfg(cfgOrTrs)
if isstruct(cfgOrTrs) && isfield(cfgOrTrs, "enable")
    cfg = cfgOrTrs;
    return;
end

cfg = struct();
cfg.enable = logical(sixgr.util.structGet(cfgOrTrs, "phy.trs.enable", false));
cfg.nPorts = double(sixgr.util.structGet(cfgOrTrs, "phy.trs.nPorts", 1));
cfg.scramblingID = double(sixgr.util.structGet(cfgOrTrs, "phy.trs.scramblingID", 0));
cfg.symbolLocations = sixgr.util.structGet(cfgOrTrs, "phy.trs.symbolLocations", []);
cfg.subcarrierComb = double(sixgr.util.structGet(cfgOrTrs, "phy.trs.subcarrierComb", 4));
cfg.subcarrierOffset = double(sixgr.util.structGet(cfgOrTrs, "phy.trs.subcarrierOffset", 0));
cfg.rbOffset = double(sixgr.util.structGet(cfgOrTrs, "phy.trs.rbOffset", 0));
cfg.numRB = double(sixgr.util.structGet(cfgOrTrs, "phy.trs.numRB", sixgr.util.structGet(cfgOrTrs, "phy.carrier.NSizeGrid", 1)));

llsTrs = sixgr.util.structGet(cfgOrTrs, "lls6g.reference_signals.trs", struct());
if isempty(cfg.symbolLocations)
    cfg.symbolLocations = sixgr.util.structGet(llsTrs, "symbol_locations", []);
end
if ~isfield(cfg, "scramblingID") || ~isfinite(cfg.scramblingID)
    cfg.scramblingID = double(sixgr.util.structGet(llsTrs, "scrambling_id", 0));
end
if ~isfield(cfg, "nPorts") || ~isfinite(cfg.nPorts)
    cfg.nPorts = double(sixgr.util.structGet(llsTrs, "num_ports", 1));
end
end

function symbolLoc = localResolveSymbolLocations(cfg, L)
symbolLoc = sixgr.util.structGet(cfg, "symbolLocations", []);
if isempty(symbolLoc)
    if L >= 12
        symbolLoc = [2 11];
    elseif L >= 7
        symbolLoc = [2 L-1];
    else
        symbolLoc = max(1, round(L / 2));
    end
end
symbolLoc = unique(max(1, min(L, round(double(symbolLoc(:).')))));
end

function sym = localQPSKSequence(N, scramblingID, slotInFrame, symbolInSlot)
% TS 38.211 7.4.1.6 CSI-RS/TRS QPSK sequence with TS 38.211 5.2.1 Gold bits.
if nargin < 3 || isempty(slotInFrame)
    slotInFrame = 0;
end
if nargin < 4 || isempty(symbolInSlot)
    symbolInSlot = 0;
end
n_s = round(double(slotInFrame));
l = round(double(symbolInSlot));
N_ID = round(double(scramblingID));
cInit = mod(2^10 * (14 * n_s + l + 1) * (2 * N_ID + 1) + 2 * N_ID + 1, 2^31);
c = localGoldSequence(2 * N, cInit);
re = 1 - 2 * double(c(1:2:end));
im = 1 - 2 * double(c(2:2:end));
sym = (re(:) + 1j * im(:)) / sqrt(2);
sym = sym(1:N);
end

function c = localGoldSequence(Nout, cInit)
Nc = 1600;
M = Nout + Nc;
x1 = zeros(1, M + 31);
x2 = zeros(1, M + 31);
x1(1) = 1;
for n = 1:31
    x2(n) = mod(floor(double(cInit) / 2^(n - 1)), 2);
end
for n = 1:M
    x1(n + 31) = mod(x1(n + 3) + x1(n), 2);
    x2(n + 31) = mod(x2(n + 3) + x2(n + 2) + x2(n + 1) + x2(n), 2);
end
c = mod(x1(Nc + 1:Nc + Nout) + x2(Nc + 1:Nc + Nout), 2);
end
