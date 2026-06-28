function grant = resolveWaveformGrant(cfg, direction, frameIdx, varargin)
%RESOLVEWAVEFORMGRANT Materialize the authoritative LLS control/grant stage.

ip = inputParser;
ip.addParameter("Slot", frameIdx, @(x) isnumeric(x) && isscalar(x));
ip.addParameter("SFN", mod(max(double(frameIdx) - 1, 0), 1024), @(x) isnumeric(x) && isscalar(x));
ip.addParameter("RV", NaN, @(x) isnumeric(x) && isscalar(x));
ip.addParameter("HARQProcess", NaN, @(x) isnumeric(x) && isscalar(x));
ip.addParameter("IsRetransmission", false, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
ip.parse(varargin{:});
opt = ip.Results;

direction = upper(string(direction));
isUL = direction == "UL";

grant = struct();
grant.Direction = char(direction);
grant.Frame = double(frameIdx);
grant.Slot = double(opt.Slot);
grant.SFN = double(opt.SFN);
grant.UEID = double(sixgr.util.structGet(cfg, "lls6g.userContext.UEIndex", 1));
grant.RNTI = double(sixgr.util.structGet(cfg, ternary(isUL, "phy.pusch.RNTI", "phy.pdsch.RNTI"), NaN));
grant.BaseStationID = double(sixgr.util.structGet(cfg, "scenario.bs.cell_id", ...
    sixgr.util.structGet(cfg, "scenario.cell_id", sixgr.util.structGet(cfg, "scenario.base_station_id", 1))));
grant.MCS = localFiniteDefault(sixgr.util.structGet(cfg, ternary(isUL, "phy.pusch.mcsIndex", "phy.pdsch.mcsIndex"), NaN), 0);
grant.MCSIndex = double(grant.MCS);
grant.Modulation = char(string(sixgr.util.structGet(cfg, ternary(isUL, "phy.pusch.modulation", "phy.pdsch.modulation"), "")));
grant.TargetCodeRate = double(sixgr.util.structGet(cfg, ternary(isUL, "phy.pusch.codeRate", "phy.pdsch.codeRate"), NaN));
grant.Layers = double(sixgr.util.structGet(cfg, ternary(isUL, "phy.pusch.numLayers", "phy.pdsch.numLayers"), ...
    sixgr.util.structGet(cfg, ternary(isUL, "phy.pusch.nLayers", "phy.pdsch.nLayers"), 1)));
grant.NumLayers = double(grant.Layers);
grant.Rank = double(grant.Layers);
grant.PortCount = double(sixgr.util.structGet(cfg, ternary(isUL, "phy.pusch.numPorts", "phy.pdsch.numPorts"), ...
    sixgr.util.structGet(cfg, ternary(isUL, "phy.pusch.nPorts", "phy.pdsch.nPorts"), ...
    double(grant.Layers))));
[grant.PRBStart, grant.AllocatedPRBCount, grant.PRBSet] = localResolveConfiguredPRBAllocation(cfg, isUL);
grant.SymbolAllocation = localResolveConfiguredSymbolAllocation(cfg, isUL);
grant.RV = localFiniteDefault(opt.RV, 0);
grant.HARQProcess = localFiniteDefault(opt.HARQProcess, 0);
grant.IsRetransmission = logical(opt.IsRetransmission);
grant.HARQ = struct("HarqID", double(grant.HARQProcess), ...
    "NDI", ~logical(opt.IsRetransmission), ...
    "RV", double(grant.RV), ...
    "IsRetransmission", logical(opt.IsRetransmission));
grant.DAI = 1;
grant.K1 = double(sixgr.util.structGet(cfg, "mac.harq.k1", 4));
grant.K2 = double(sixgr.util.structGet(cfg, "mac.harq.k2", 1));
grant.SearchSpaceID = double(sixgr.util.structGet(cfg, "phy.dl.pdcch.SearchSpaceID", 0));
grant.CORESETID = double(sixgr.util.structGet(cfg, "phy.dl.pdcch.CORESETID", 0));
grant.BWPId = double(sixgr.util.structGet(cfg, "phy.bwp.id", 0));
grant.Source = "explicit_waveform_grant";
grant.Valid = true;

scheduler = sixgr.l2.mac.SchedulerPF(cfg, "Direction", char(direction));
grant = scheduler.freezePHYGrantForGrant(grant);
grant.DCI = scheduler.buildDCIBitfield(grant);
end

function value = ternary(cond, a, b)
if cond
    value = a;
else
    value = b;
end
end

function value = localFiniteDefault(raw, fallback)
value = double(raw);
if isempty(value)
    value = fallback;
    return;
end
value = value(1);
if ~(isscalar(value) && isfinite(value))
    value = fallback;
end
end

function [prbStart, prbCount, prbSet] = localResolveConfiguredPRBAllocation(cfg, isUL)
prbStart = NaN;
prbCount = NaN;
prbSet = [];
prbSet = sixgr.util.structGet(cfg, ternary(isUL, "phy.pusch.prbSet", "phy.pdsch.prbSet"), []);
if isempty(prbSet)
    prbSet = sixgr.util.structGet(cfg, ternary(isUL, "phy.pusch.PRBSet", "phy.pdsch.PRBSet"), []);
end
if isempty(prbSet)
    nGrid = double(sixgr.util.structGet(cfg, "phy.carrier.NSizeGrid", NaN));
    if isscalar(nGrid) && isfinite(nGrid) && nGrid >= 1
        prbSet = 0:(round(nGrid) - 1);
        prbStart = 0;
        prbCount = double(numel(prbSet));
    end
    return;
end
prbSet = double(prbSet(:));
prbSet = prbSet(isfinite(prbSet) & prbSet >= 0);
if isempty(prbSet)
    return;
end
prbSet = unique(round(prbSet), "stable");
prbStart = double(min(prbSet));
prbCount = double(numel(prbSet));
prbSet = double(prbSet(:).');
end

function symAlloc = localResolveConfiguredSymbolAllocation(cfg, isUL)
symAlloc = sixgr.util.structGet(cfg, ternary(isUL, "phy.pusch.symbolAllocation", "phy.pdsch.symbolAllocation"), []);
if isempty(symAlloc)
    symAlloc = sixgr.util.structGet(cfg, ternary(isUL, "phy.pusch.SymbolAllocation", "phy.pdsch.SymbolAllocation"), []);
end
if isempty(symAlloc)
    symAlloc = [0 14];
end
symAlloc = double(symAlloc(:).');
if numel(symAlloc) < 2 || any(~isfinite(symAlloc(1:2)))
    symAlloc = [0 14];
else
    symAlloc = round(symAlloc(1:2));
end
end
