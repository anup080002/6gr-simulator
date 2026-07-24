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
[ueIndex, ueIdentitySource] = localResolveUEIdentity(cfg);
grant.UEIndex = double(ueIndex);
grant.UEID = double(ueIndex);
grant.UEIdentitySource = char(ueIdentitySource);
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
grant.K0 = NaN;
grant.K1 = NaN;
grant.K2 = NaN;
grant.SearchSpaceID = double(sixgr.util.structGet(cfg, "phy.dl.pdcch.SearchSpaceID", 0));
grant.CORESETID = double(sixgr.util.structGet(cfg, "phy.dl.pdcch.CORESETID", 0));
grant.BWPId = NaN;
grant.Source = "explicit_waveform_grant";
grant.Valid = true;

scheduler = sixgr.l2.mac.SchedulerPF(cfg, "Direction", char(direction));
grant = scheduler.freezePHYGrantForGrant(grant);
grant.DCI = scheduler.buildDCIBitfield(grant);
end

function [ueIndex, source] = localResolveUEIdentity(cfg)
runtimeUE = localFiniteOrNaN(sixgr.util.structGet(cfg, ...
    "lls6g.userContext.RuntimeUEIndex", NaN));
configuredUE = localFiniteOrNaN(sixgr.util.structGet(cfg, ...
    "lls6g.userContext.UEIndex", NaN));
if isfinite(runtimeUE)
    ueIndex = runtimeUE;
    source = "runtime_user_context";
    return;
end
if isfinite(configuredUE)
    ueIndex = configuredUE;
    source = "configured_user_context";
    return;
end

multiUserEnabled = logical(sixgr.util.structGet(cfg, "lls6g.users.enabled", false));
numUsers = localFiniteDefault(sixgr.util.structGet(cfg, "lls6g.users.n_users", 1), 1);
if multiUserEnabled && numUsers > 1
    error("sixgr:link:resolveWaveformGrant:MissingMultiUserIdentity", ...
        "A multi-user waveform grant requires lls6g.userContext.RuntimeUEIndex or UEIndex.");
end
ueIndex = 1;
source = "standalone_single_user_default";
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

function value = localFiniteOrNaN(raw)
value = double(raw);
if isempty(value)
    value = NaN;
    return;
end
value = value(1);
if ~(isscalar(value) && isfinite(value))
    value = NaN;
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
    error("sixgr:link:resolveWaveformGrant:MissingPRBSet", ...
        "%s waveform grant requires an explicit configured PRBSet.", ...
        ternary(isUL, "UL", "DL"));
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
    error("sixgr:link:resolveWaveformGrant:MissingSymbolAllocation", ...
        "%s waveform grant requires an explicit configured SymbolAllocation.", ...
        ternary(isUL, "UL", "DL"));
end
symAlloc = double(symAlloc(:).');
if numel(symAlloc) ~= 2 || any(~isfinite(symAlloc))
    error("sixgr:link:resolveWaveformGrant:InvalidSymbolAllocation", ...
        "Configured waveform SymbolAllocation must contain exactly two finite values.");
end
symAlloc = round(symAlloc);
if symAlloc(1) < 0 || symAlloc(2) < 1
    error("sixgr:link:resolveWaveformGrant:InvalidSymbolAllocation", ...
        "Configured waveform SymbolAllocation must be [start>=0 count>=1].");
end
end
