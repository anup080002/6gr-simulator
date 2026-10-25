function [pdschInd, info, pdsch] = allocREsPDSCH(carrier, cfgOrPdsch, varargin)
%ALLOCRESPDSCH PDSCH RE allocation indices from config.
%
%   [ind,info,pdsch] = sixgr.phy.grid.allocREsPDSCH(carrier,cfg) creates an
%   nrPDSCHConfig from cfg.phy.pdsch and calls nrPDSCHIndices.
%
%   [ind,info,pdsch] = sixgr.phy.grid.allocREsPDSCH(carrier,pdschCfg) uses
%   the provided nrPDSCHConfig.
%
%   Name-Value overrides (all optional):
%     "IndexBase"        - "1based" (default) or "0based"
%     "PRBSet"           - explicit vector of zero-based PRB indices
%     "SymbolAllocation" - [startSym nSym]
%     "FixedReferenceMode" - true rejects implicit mapping mutations

opts = sixgr.phy.grid.parsePDSCHAllocationOptions(varargin{:});
ssbReservation = struct();
csiimReservation = struct();
controlReservation = struct();

if isa(cfgOrPdsch, "nrPDSCHConfig")
    pdsch = cfgOrPdsch;
else
    pdsch = sixgr.phy.grid.pdschConfigFromConfig(carrier, cfgOrPdsch, varargin{:});
    [pdsch,controlReservation] = sixgr.phy.grid.reserveConnectedCORESETPDSCHResources(carrier,pdsch,cfgOrPdsch);
    pdsch = localReserveCSIRSResources(carrier, pdsch, cfgOrPdsch);
    pdsch = localReserveTRSResources(carrier, pdsch, cfgOrPdsch);
    [pdsch, ssbReservation] = sixgr.phy.grid.reserveSSBPDSCHResources(carrier, pdsch, cfgOrPdsch);
    [pdsch,csiimReservation] = localReserveCSIIMResources(carrier,pdsch,cfgOrPdsch);
end

try
    [pdschInd, indInfo] = nrPDSCHIndices(carrier, pdsch, "IndexStyle", "index", "IndexBase", opts.IndexBase);
catch
    [pdschInd, indInfo] = nrPDSCHIndices(carrier, pdsch, "IndexBase", opts.IndexBase);
end

info = struct();
info.Channel = "PDSCH";
info.SSBReservation = ssbReservation;
info.CSIIMReservation = csiimReservation;
info.ConnectedCORESETReservation = controlReservation;
info.IndexBase = opts.IndexBase;
info.NRE = size(pdschInd, 1);
info.PRBSet = pdsch.PRBSet;
info.SymbolAllocation = pdsch.SymbolAllocation;
info.Modulation = localModulationText(pdsch.Modulation);
info.NumLayers = pdsch.NumLayers;
info.NumCodewords = double(pdsch.NumCodewords);
info.IndicesInfo = indInfo;
info.ResourceAccounting = sixgr.phy.resource.computeResourceAccounting("PDSCH", carrier, pdsch, ...
    "ChannelIndices", pdschInd, ...
    "AllocationInfo", info, ...
    "IndexBase", opts.IndexBase);
if double(info.ResourceAccounting.DMRSRE) <= 0
    error("sixgr:pdsch:NoDMRSResources", ...
        "The configured PDSCH mapping and symbol allocation produce no " + ...
        "DM-RS resource elements. Cross-check TS 38.211 mapping type, " + ...
        "allocation duration, and DM-RS position parameters.");
end
info.LayerDataRE = info.ResourceAccounting.LayerDataRE;
info.PortMappedRE = info.ResourceAccounting.PortMappedRE;
info.ModulationSymbolCount = info.ResourceAccounting.ModulationSymbolCount;
info.CodedBitCountG = info.ResourceAccounting.CodedBitCountG;
info.CodedBitCountGPerCodeword = info.ResourceAccounting.CodedBitCountGPerCodeword;
info.GPerCodeword = info.ResourceAccounting.GPerCodeword;
info.G = info.ResourceAccounting.CodedBitCountG;
info.NREPerPRB = info.ResourceAccounting.NREPerPRBForTBS;
info.DMRSRE = info.ResourceAccounting.DMRSRE;
info.PTRSRE = info.ResourceAccounting.PTRSRE;
info.ReservedRE = info.ResourceAccounting.ReservedRE;

end

function [pdsch,plan] = localReserveCSIIMResources(carrier,pdsch,cfg)
plan=sixgr.phy.refsig.csiIMResource(carrier,cfg);
if ~plan.Scheduled, return; end
pdsch=sixgr.phy.grid.reservePDSCHReferenceRE(carrier,pdsch, ...
    plan.PhysicalIndices1Based-1,'SignalName','CSI-IM', ...
    'DMRSCollisionIdentifier','sixgr:phy:csiim:DMRSCollision', ...
    'RejectExistingReservations',true, ...
    'ExistingCollisionIdentifier','sixgr:phy:csiim:ReferenceCollision', ...
    'RejectPTRS',true,'PTRSCollisionIdentifier','sixgr:phy:csiim:PTRSCollision');
end

function text = localModulationText(raw)
if iscell(raw)
    tokens = string(raw);
else
    tokens = string(raw);
end
tokens = tokens(:).';
tokens = tokens(strlength(strtrim(tokens)) > 0);
if isempty(tokens)
    text = "";
else
    text = strjoin(tokens, "|");
end
end


function pdsch = localReserveCSIRSResources(carrier, pdsch, cfg)
if ~(isstruct(cfg) && logical(sixgr.util.structGet(cfg, "phy.csirs.enable", false)))
    return;
end
try
    [csirsInd, csirsSym, csirsInfo] = sixgr.phy.refsig.csirs( ...
        carrier, cfg, "IndexBase", "0based");
catch ME
    error("sixgr:phy:grid:allocREsPDSCH:CSIRSReservationFailed", ...
        "CSI-RS is enabled but runtime CSI-RS resources could not be generated for PDSCH reservation: %s", ME.message);
end
if isempty(csirsSym) || ~isstruct(csirsInfo) || ~logical(sixgr.util.structGet(csirsInfo, "Enabled", false))
    return;
end

% CSI-RS is sparse inside each configured RB.  Reserving an entire PRB for
% every CSI-RS symbol removes unrelated PDSCH data and can remove every
% active DM-RS RE from a narrow scheduler grant.  nrPDSCHConfig.ReservedRE
% is BWP-relative, whereas these generated indices are carrier-relative.
% The shared owner retains carrier-space collisions before converting once.
pdsch = sixgr.phy.grid.reservePDSCHReferenceRE(carrier,pdsch,csirsInd, ...
    'SignalName','CSI-RS','DMRSCollisionIdentifier', ...
    'sixgr:phy:grid:allocREsPDSCH:CSIRSDMRSCollision');
end

function pdsch = localReserveTRSResources(carrier, pdsch, cfg)
% TRS is an NZP-CSI-RS resource and owns exact REs on its configured
% occasions. The PDSCH encoder must rate-match around those REs before G
% and TBS are frozen; removing collisions only from an exported grid would
% leave the transmitted codeword and receiver allocation inconsistent.
if ~(isstruct(cfg) && logical(sixgr.util.structGet(cfg, ...
        "phy.trs.enable", false)))
    return;
end

try
    strictTRS = sixgr.phy.trs.buildTRSConfigFromScenario(cfg, ...
        "RunId", "pdsch_exact_trs_reservation", ...
        "ScenarioName", "pdsch_exact_trs_reservation");
catch ME
    error("sixgr:phy:grid:allocREsPDSCH:TRSReservationFailed", ...
        "TRS is enabled but its exact NZP-CSI-RS resource could not be resolved for PDSCH reservation: %s", ...
        ME.message);
end

slotsPerFrame = round(double(carrier.SlotsPerFrame));
slot0 = mod(round(double(carrier.NSlot)), slotsPerFrame);
absoluteSlot0=double(sixgr.util.structGet(cfg,"lls6g.runtime.AbsoluteSlotIndex0", ...
    double(carrier.NFrame)*slotsPerFrame+double(carrier.NSlot)));
validateattributes(absoluteSlot0,{'numeric'},{'scalar','finite','integer','nonnegative'});
assert(mod(absoluteSlot0,slotsPerFrame)==slot0, ...
    'sixgr:phy:grid:allocREsPDSCH:TRSClockMismatch', ...
    'TRS reservation must use the same absolute resource occasion as the data carrier.');
if ~sixgr.truth.isActiveTRSOccasion(cfg,absoluteSlot0+1)
    return;
end

try
    trsCarrier = carrier;
    trsCarrier.NSlot = slot0;
    trsIndices=[];
    for resourceIndex=1:numel(strictTRS.ToolboxResources)
        indices=nrCSIRSIndices(trsCarrier,strictTRS.ToolboxResources{resourceIndex}, ...
            "IndexStyle","index","IndexBase","0based");
        trsIndices=[trsIndices;indices(:)]; %#ok<AGROW>
    end
catch ME
    error("sixgr:phy:grid:allocREsPDSCH:TRSReservationFailed", ...
        "The active TRS occasion in carrier slot %d could not be materialized for exact PDSCH reservation: %s", ...
        slot0, ME.message);
end

if isempty(trsIndices)
    error("sixgr:phy:grid:allocREsPDSCH:EmptyActiveTRSReservation", ...
        "TRS is active in carrier slot %d but produced no exact REs.", slot0);
end

pdsch = sixgr.phy.grid.reservePDSCHReferenceRE(carrier,pdsch,trsIndices, ...
    'SignalName','TRS','DMRSCollisionIdentifier', ...
    'sixgr:phy:grid:allocREsPDSCH:TRSDMRSCollision');
end
