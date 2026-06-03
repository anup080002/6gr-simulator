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
grant.MCS = double(sixgr.util.structGet(cfg, ternary(isUL, "phy.pusch.mcsIndex", "phy.pdsch.mcsIndex"), NaN));
grant.Modulation = char(string(sixgr.util.structGet(cfg, ternary(isUL, "phy.pusch.modulation", "phy.pdsch.modulation"), "")));
grant.TargetCodeRate = double(sixgr.util.structGet(cfg, ternary(isUL, "phy.pusch.codeRate", "phy.pdsch.codeRate"), NaN));
grant.Layers = double(sixgr.util.structGet(cfg, ternary(isUL, "phy.pusch.numLayers", "phy.pdsch.numLayers"), ...
    sixgr.util.structGet(cfg, ternary(isUL, "phy.pusch.nLayers", "phy.pdsch.nLayers"), 1)));
grant.Rank = double(grant.Layers);
grant.PortCount = double(sixgr.util.structGet(cfg, ternary(isUL, "phy.pusch.numPorts", "phy.pdsch.numPorts"), ...
    sixgr.util.structGet(cfg, ternary(isUL, "phy.pusch.nPorts", "phy.pdsch.nPorts"), ...
    sixgr.util.structGet(cfg, "phy.nTxAnt", NaN))));
[grant.PRBStart, grant.AllocatedPRBCount] = localResolveConfiguredPRBAllocation(cfg, isUL);
grant.RV = double(opt.RV);
grant.HARQProcess = double(opt.HARQProcess);
grant.IsRetransmission = logical(opt.IsRetransmission);
grant.Source = "explicit_waveform_grant";
grant.Valid = true;
end

function value = ternary(cond, a, b)
if cond
    value = a;
else
    value = b;
end
end

function [prbStart, prbCount] = localResolveConfiguredPRBAllocation(cfg, isUL)
prbStart = NaN;
prbCount = NaN;
prbSet = sixgr.util.structGet(cfg, ternary(isUL, "phy.pusch.prbSet", "phy.pdsch.prbSet"), []);
if isempty(prbSet)
    prbSet = sixgr.util.structGet(cfg, ternary(isUL, "phy.pusch.PRBSet", "phy.pdsch.PRBSet"), []);
end
if isempty(prbSet)
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
end
