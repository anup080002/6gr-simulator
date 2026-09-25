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

if isa(cfgOrPdsch, "nrPDSCHConfig")
    pdsch = cfgOrPdsch;
else
    pdsch = sixgr.phy.grid.pdschConfigFromConfig(carrier, cfgOrPdsch, varargin{:});
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
reservedZero=localReferenceREInsidePDSCHAllocation(plan.PhysicalIndices1Based-1,carrier,pdsch);
if isempty(reservedZero), return; end
assert(isempty(intersect(reservedZero,double(pdsch.ReservedRE(:)))), ...
    'sixgr:phy:csiim:ReferenceCollision','CSI-IM overlaps an existing serving reference reservation.');
localRejectReferenceDMRSCollision(reservedZero,carrier,pdsch,'CSI-IM', ...
    'sixgr:phy:csiim:DMRSCollision');
ptrs=nrPDSCHPTRSIndices(carrier,pdsch,'IndexBase','0based');
plane=12*double(carrier.NSizeGrid)*double(carrier.SymbolsPerSlot);
assert(isempty(intersect(reservedZero,mod(double(ptrs(:)),plane))), ...
    'sixgr:phy:csiim:PTRSCollision','CSI-IM cannot puncture PDSCH PT-RS.');
pdsch.ReservedRE=unique([double(pdsch.ReservedRE(:));reservedZero(:)],'sorted');
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
% is zero-based, so project the physical multi-port CSI-RS indices onto one
% resource-grid plane and retain only REs inside this PDSCH allocation.
plane = double(carrier.NSizeGrid) * 12 * double(carrier.SymbolsPerSlot);
csirsBaseZero = unique(mod(double(csirsInd(:)), plane), "sorted");
prbs = double(pdsch.PRBSet(:).');
symbolAllocation = double(pdsch.SymbolAllocation(:).');
subcarriers = reshape(12 .* prbs + (0:11).', 1, []);
scheduledSymbols = symbolAllocation(1) + (0:(symbolAllocation(2) - 1));
[k, l] = ndgrid(subcarriers, scheduledSymbols);
allocationZero = double(k(:) + 12 .* double(carrier.NSizeGrid) .* l(:));
reservedZero = intersect(csirsBaseZero, allocationZero, "sorted");
if isempty(reservedZero)
    return;
end

% PDSCH data can be rate-matched around exact CSI-RS REs, but PDSCH DM-RS
% cannot be punctured by CSI-RS.  Reject a colliding YAML schedule before
% the Toolbox silently deactivates the receiver's channel-estimation
% reference symbols.
dmrsSub = nrPDSCHDMRSIndices(carrier, pdsch, ...
    "IndexStyle", "subscript", "IndexBase", "0based");
dmrsBaseZero = unique(double(dmrsSub(:,1) + ...
    12 .* double(carrier.NSizeGrid) .* dmrsSub(:,2)), "sorted");
dmrsCollision = intersect(reservedZero, dmrsBaseZero, "sorted");
if ~isempty(dmrsCollision)
    error("sixgr:phy:grid:allocREsPDSCH:CSIRSDMRSCollision", ...
        ['Configured CSI-RS overlaps %d active PDSCH DM-RS RE(s) in slot %d. ' ...
         'Move the YAML-owned CSI-RS resource(s) off the DM-RS symbols; ' ...
         'DM-RS puncturing is not permitted.'], ...
        numel(dmrsCollision), double(carrier.NSlot));
end

try
    existing = double(pdsch.ReservedRE(:));
    pdsch.ReservedRE = unique([existing; reservedZero(:)], "sorted");
catch ME
    error("sixgr:phy:grid:allocREsPDSCH:CSIRSReservationApplyFailed", ...
        "CSI-RS runtime resources were generated but could not be reserved in the PDSCH allocation: %s", ME.message);
end
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

plane = double(carrier.NSizeGrid) * 12 * double(carrier.SymbolsPerSlot);
trsBaseZero = unique(mod(double(trsIndices(:)), plane), "sorted");
reservedZero = localReferenceREInsidePDSCHAllocation( ...
    trsBaseZero, carrier, pdsch);
if isempty(reservedZero)
    return;
end

localRejectReferenceDMRSCollision( ...
    reservedZero, carrier, pdsch, "TRS", ...
    "sixgr:phy:grid:allocREsPDSCH:TRSDMRSCollision");
try
    pdsch.ReservedRE = unique([double(pdsch.ReservedRE(:)); ...
        reservedZero(:)], "sorted");
catch ME
    error("sixgr:phy:grid:allocREsPDSCH:TRSReservationApplyFailed", ...
        "Exact TRS REs were resolved but could not be installed in PDSCH ReservedRE: %s", ...
        ME.message);
end
end

function reservedZero = localReferenceREInsidePDSCHAllocation( ...
        referenceBaseZero, carrier, pdsch)
prbs = double(pdsch.PRBSet(:).');
symbolAllocation = double(pdsch.SymbolAllocation(:).');
subcarriers = reshape(12 .* prbs + (0:11).', 1, []);
scheduledSymbols = symbolAllocation(1) + ...
    (0:(symbolAllocation(2) - 1));
[k, l] = ndgrid(subcarriers, scheduledSymbols);
allocationZero = double(k(:) + ...
    12 .* double(carrier.NSizeGrid) .* l(:));
reservedZero = intersect(double(referenceBaseZero(:)), ...
    allocationZero, "sorted");
end

function localRejectReferenceDMRSCollision( ...
        reservedZero, carrier, pdsch, signalName, identifier)
dmrsSub = nrPDSCHDMRSIndices(carrier, pdsch, ...
    "IndexStyle", "subscript", "IndexBase", "0based");
dmrsBaseZero = unique(double(dmrsSub(:,1) + ...
    12 .* double(carrier.NSizeGrid) .* dmrsSub(:,2)), "sorted");
dmrsCollision = intersect(double(reservedZero(:)), ...
    dmrsBaseZero, "sorted");
if ~isempty(dmrsCollision)
    error(identifier, ...
        ['Configured %s overlaps %d active PDSCH DM-RS RE(s) in slot %d. ' ...
         'Move the YAML-owned reference resource off the DM-RS symbols; ' ...
         'DM-RS puncturing is not permitted.'], ...
        signalName, numel(dmrsCollision), double(carrier.NSlot));
end
end
