function [T, checkT] = buildPlannedREAllocation(cfg, varargin)
%BUILDPLANNEDREALLOCATION Resolve every enabled channel to exact Toolbox REs.
%
% T is configuration/planning evidence.  It is intentionally separate from
% observed runtime occupancy.  CHECKT is fail-closed: an enabled feature is
% resolved only after its authoritative configuration produces exact
% zero-based [subcarrier symbol port] coordinates on a legal DL/UL occasion.

ip = inputParser;
ip.addRequired("cfg", @(x)isstruct(x) || isobject(x));
ip.addParameter("TargetChannels", strings(0, 1), ...
    @(x)ischar(x) || isstring(x) || iscellstr(x));
ip.addParameter("ReusePeriodicCoordinateTemplates", true, ...
    @(x)islogical(x) && isscalar(x));
ip.parse(cfg, varargin{:});
targetChannels = upper(strtrim(string(ip.Results.TargetChannels)));
targetChannels = targetChannels(:);
targetChannels = targetChannels(strlength(targetChannels) > 0);
if isempty(targetChannels)
    % Make the default full-stack selection explicit.  Keeping an empty
    % string array inside repeated anonymous membership checks is both less
    % readable and release-sensitive; the public meaning remains "all".
    targetChannels = ["SSB_PBCH";"TYPE0_PDCCH";"SIB1_PDSCH";"PDCCH"; ...
        "PDSCH";"CSI_RS";"TRS";"PRACH";"PUCCH";"PUSCH";"SRS"];
end
isSelected = @(name) any(targetChannels == upper(string(name)));
reusePeriodicTemplates = logical(ip.Results.ReusePeriodicCoordinateTemplates);
plannedAllocationEncoding = lower(strtrim(string(sixgr.util.structGet( ...
    cfg, "outputs.plannedAllocationEncoding", "expanded_per_slot"))));
assert(isscalar(plannedAllocationEncoding) && any(plannedAllocationEncoding == ...
    ["expanded_per_slot", "exact_periodic_templates"]), ...
    "sixgr:truth:InvalidPlannedAllocationEncoding", ...
    ["outputs.plannedAllocationEncoding must be expanded_per_slot or " ...
     "exact_periodic_templates."]);
compactPeriodicOutput = plannedAllocationEncoding == "exact_periodic_templates";

carrier = sixgr.phy.grid.makeCarrier(cfg);
frame = sixgr.phy.FrameStructureEngine(cfg);
totalSlots = max(1, round(double(sixgr.util.structGet( ...
    cfg, "run.totalSlots", 1))));
if isSelected("PRACH")
    prachSlots = double(sixgr.util.structGet(cfg, ...
        "prach_lls.NumSlots", NaN));
    if isscalar(prachSlots) && isfinite(prachSlots) && prachSlots >= 1
        totalSlots = max(totalSlots, round(prachSlots));
    end
end
rows = repmat(localEmptyRow(), 0, 1);
checks = repmat(localEmptyCheck(), 0, 1);

[rows, checks] = localAttempt(rows, checks, "FRAME", "BIDIR", true, ...
    "carrier_and_duplex_yaml", "sixgr.phy.FrameStructureEngine", ...
    @() localFrame(frame, carrier));

ssbEnabled = isSelected("SSB_PBCH") && ...
    logical(sixgr.util.structGet(cfg, "phy.ssb.enable", false));
[rows, checks] = localAttempt(rows, checks, "SSB_PBCH", "DL", ...
    ssbEnabled, "MIB_and_SSB_burst_configuration", ...
    "FrameStructureEngine+nrPSS/SSS/PBCHIndices", ...
    @() localSSB(cfg, carrier, totalSlots));

type0Enabled = isSelected("TYPE0_PDCCH") && ssbEnabled && logical(sixgr.util.structGet( ...
    cfg, "phy.mib.enable", true));
[rows, checks, type0] = localAttemptValue(rows, checks, ...
    "TYPE0_PDCCH", "DL", type0Enabled, "decoded_MIB_pdcch_ConfigSIB1", ...
    "deriveType0PDCCHFromMIB+nrPDCCHResources", ...
    @() localType0(cfg, carrier, totalSlots));

sib1Enabled = isSelected("SIB1_PDSCH") && logical(sixgr.util.structGet(cfg, ...
    "initial_access.sib1.enable", sixgr.util.structGet(cfg, ...
    "phy.sib1.enable", type0Enabled)));
[rows, checks] = localAttempt(rows, checks, "SIB1_PDSCH", "DL", ...
    sib1Enabled, "decoded_Type0_DCI_1_0_SI_RNTI", ...
    "buildSIB1DCI10+nrPDSCHIndices", ...
    @() localSIB1(cfg, carrier, type0));

pdcchEnabled = isSelected("PDCCH") && ...
    logical(sixgr.util.structGet(cfg, "phy.pdcch.enable", false));
[rows, checks] = localAttempt(rows, checks, "PDCCH", "DL", ...
    pdcchEnabled, "RRC_SearchSpace_CORESET_and_DCI", ...
    "buildPDCCHConfigFromScenario+nrPDCCHResources", ...
    @() localPDCCH(cfg, totalSlots, frame, compactPeriodicOutput));

pdschEnabled = isSelected("PDSCH") && ...
    logical(sixgr.util.structGet(cfg, "phy.pdsch.enable", true));
[rows, checks] = localAttempt(rows, checks, "PDSCH", "DL", ...
    pdschEnabled, "configured_RRC_BWP_resource_pool_not_scheduler_grant", ...
    "allocREsPDSCH+nrPDSCHIndices", ...
    @() localPDSCH(cfg, carrier, totalSlots, frame, reusePeriodicTemplates, ...
    compactPeriodicOutput));

csirsEnabled = isSelected("CSI_RS") && ...
    logical(sixgr.util.structGet(cfg, "phy.csirs.enable", false));
[rows, checks] = localAttempt(rows, checks, "CSI_RS", "DL", ...
    csirsEnabled, "RRC_CSI_RS_resource_configuration", ...
    "sixgr.phy.refsig.csirs+nrCSIRSIndices", ...
    @() localCSIRS(cfg, carrier, totalSlots, frame, compactPeriodicOutput));

trsEnabled = isSelected("TRS") && ...
    logical(sixgr.util.structGet(cfg, "phy.trs.enable", false));
[rows, checks] = localAttempt(rows, checks, "TRS", "DL", ...
    trsEnabled, "RRC_NZP_CSI_RS_TRS_resource_configuration", ...
    "buildTRSConfigFromScenario+nrCSIRSIndices", ...
    @() localTRS(cfg, totalSlots, frame, compactPeriodicOutput));

prachEnabled = isSelected("PRACH") && ...
    logical(sixgr.util.structGet(cfg, "phy.prach.enable", false));
[rows, checks] = localAttempt(rows, checks, "PRACH", "UL", ...
    prachEnabled, "decoded_SIB1_RACH_ConfigCommon", ...
    "PRACHConfig+nrPRACHIndices", ...
    @() localPRACH(cfg, carrier, totalSlots, frame));

pucchEnabled = isSelected("PUCCH") && ...
    logical(sixgr.util.structGet(cfg, "phy.pucch.enable", false));
[rows, checks] = localAttempt(rows, checks, "PUCCH", "UL", ...
    pucchEnabled, "RRC_PUCCH_resource_and_DCI_K1_PRI", ...
    "PUCCHResource.toolboxConfig+nrPUCCHIndices", ...
    @() localPUCCH(cfg, carrier, totalSlots, frame));

puschEnabled = isSelected("PUSCH") && ...
    logical(sixgr.util.structGet(cfg, "phy.pusch.enable", true));
[rows, checks] = localAttempt(rows, checks, "PUSCH", "UL", ...
    puschEnabled, "configured_RRC_UL_BWP_resource_pool_not_scheduler_grant", ...
    "allocREsPUSCH+nrPUSCHIndices", ...
    @() localPUSCH(cfg, carrier, totalSlots, frame, reusePeriodicTemplates, ...
    compactPeriodicOutput));

srsEnabled = isSelected("SRS") && ...
    logical(sixgr.util.structGet(cfg, "phy.srs.enable", false));
[rows, checks] = localAttempt(rows, checks, "SRS", "UL", ...
    srsEnabled, "RRC_SRS_resource_configuration", ...
    "buildSRSConfigFromScenario+nrSRSIndices", ...
    @() localSRS(cfg, carrier, totalSlots, frame, compactPeriodicOutput));

if isempty(rows)
    T = struct2table(repmat(localEmptyRow(), 0, 1), "AsArray", true);
else
    T = struct2table(rows, "AsArray", true);
    carrierRows=T.grid_domain=="carrier_cp_ofdm";
    T.grid_subcarrier_spacing_hz(carrierRows)=1000*double(carrier.SubcarrierSpacing);
    T.grid_subcarrier_count(carrierRows)=12*double(carrier.NSizeGrid);
    T.grid_symbol_count(carrierRows)=double(carrier.SymbolsPerSlot);
    slotsPerFrame = 10 * round(double(carrier.SlotsPerSubframe));
    T.sfn = floor(T.absolute_slot ./ slotsPerFrame);
    T.slot_within_frame = mod(T.absolute_slot, slotsPerFrame);
    T = sortrows(T, ["absolute_slot","direction","symbol_index", ...
        "subcarrier_start","port_index","channel","component"]);
end
checkT = struct2table(checks, "AsArray", true);
end

function out = localFrame(frame, carrier)
if double(carrier.NSizeGrid) ~= double(frame.NRB) || ...
        double(carrier.SubcarrierSpacing) ~= double(frame.SCSkHz)
    error("sixgr:truth:CarrierFrameMismatch", ...
        "Carrier and frame engine resolved different grid dimensions.");
end
out = localPayload(repmat(localEmptyRow(), 0, 1), 1, ...
    "carrier/frame dimensions resolved");
end

function out = localSSB(cfg, carrier, totalSlots)
nCellID = double(carrier.NCellID);
nCRB = double(sixgr.util.structGet(cfg, "phy.ssb.nCRBSSB", ...
    sixgr.util.structGet(cfg,"phy.ssb.NCRBSSB",NaN)));
kSSB = double(sixgr.util.structGet(cfg, "phy.ssb.kSSB", ...
    sixgr.util.structGet(cfg,"phy.ssb.KSSB",NaN)));
if any(~isfinite([nCRB kSSB]))
    error("sixgr:truth:MissingSSBFrequencyPlacement", ...
        "Enabled SSB requires resolved nCRBSSB and kSSB.");
end
baseSC = 12*nCRB + kSSB;
spec = { ...
    "PSS", @() nrPSSIndices(); ...
    "SSS", @() nrSSSIndices(); ...
    "PBCH", @() nrPBCHIndices(nCellID); ...
    "PBCH_DMRS", @() nrPBCHDMRSIndices(nCellID)};
rows = repmat(localEmptyRow(), 0, 1);
candidateCount = 0;
for slot1 = 1:totalSlots
    [active, occasion] = sixgr.truth.isActiveSSBOccasion(cfg, slot1);
    if ~active, continue; end
    starts = double(occasion.CandidateSSBSymbolsWithinSlot0Based);
    ids = double(occasion.ActiveSSBIndices0Based);
    for c = 1:numel(ids)
        candidateCount = candidateCount + 1;
        for s = 1:size(spec,1)
            coords = localSSBCoordinates(spec{s,2}());
            coords(:,1) = coords(:,1) + baseSC;
            coords(:,2) = coords(:,2) + starts(c);
            localAssertCoordinates(coords, carrier);
            rows = [rows; localRows(coords, slot1-1, "SSB_PBCH", ...
                string(spec{s,1}), 1, NaN, ...
                "MIB_and_SSB_burst_configuration", ...
                "nr" + string(spec{s,1}) + "Indices", ...
                "ssb_candidate_" + string(ids(c)))]; %#ok<AGROW>
        end
    end
end
if candidateCount == 0
    error("sixgr:truth:NoActiveSSBOccasion", ...
        "Enabled SSB resolved no active SS/PBCH occasion in the run window.");
end
out = localPayload(rows, sum([rows.re_count]), ...
    sprintf("%d active SS/PBCH candidate(s)",candidateCount));
end

function coords = localSSBCoordinates(linearIndices)
% Toolbox SS/PBCH indices address the standardized 240-by-4 SS/PBCH grid.
% Convert explicitly instead of relying on release-dependent NVP support.
[subcarrier, symbol] = ind2sub([240 4], double(linearIndices(:)));
coords = [subcarrier-1 symbol-1 zeros(numel(subcarrier),1)];
end

function out = localType0(cfg, carrier, totalSlots)
mib = struct( ...
    "PDCCHConfigSIB1", double(sixgr.util.structGet(cfg, ...
        "phy.mib.pdcchConfigSIB1", NaN)), ...
    "DMRSTypeAPosition", double(sixgr.util.structGet(cfg, ...
        "phy.mib.dmrsTypeAPosition", NaN)), ...
    "SSBSubcarrierOffset", double(sixgr.util.structGet(cfg, ...
        "phy.ssb.kSSB", 0)), ...
    "SSBIndex", double(sixgr.util.structGet(cfg, ...
        "phy.ssb.runtimeSSBIndex", 0)), ...
    "Source", "configured_MIB_bits_preflight");
if any(~isfinite([mib.PDCCHConfigSIB1 mib.DMRSTypeAPosition]))
    error("sixgr:truth:MissingMIBControlAuthority", ...
        "MIB must resolve pdcchConfigSIB1 and dmrsTypeAPosition.");
end
[resolution,cfgSI] = sixgr.phy.broadcast.deriveType0PDCCHFromMIB( ...
    carrier,cfg,mib,"RNTI",65535);
occasions = resolution.MonitoringOccasions;
slots = unique(double(occasions.AbsoluteSlot));
slots = slots(slots >= 0 & slots < totalSlots);
if isempty(slots)
    error("sixgr:truth:NoType0Occasion", ...
        "Decoded MIB resolved no Type-0 monitoring occasion in the run window.");
end
rows = repmat(localEmptyRow(),0,1);
for slot0 = reshape(slots,1,[])
    c = localCarrierAtSlot(carrier,slot0);
    materialized = sixgr.phy.frame.ChannelAllocationMaterializer. ...
        materializePDCCH(c,resolution.PDCCH,"AbsoluteSlot",slot0);
    rows = [rows; localResultRows(materialized,slot0,"TYPE0_PDCCH", ...
        1,NaN,"decoded_MIB_pdcch_ConfigSIB1", ...
        "deriveType0PDCCHFromMIB+nrPDCCHResources")]; %#ok<AGROW>
end
value = struct("Resolution",resolution,"Config",cfgSI, ...
    "Slots",slots,"Carrier",carrier);
out = localPayload(rows,size(unique(vertcat(rows.allocation_id)),1), ...
    sprintf("%d Type-0 monitoring slot(s)",numel(slots)),value);
end

function out = localSIB1(cfg, carrier, type0)
if isempty(type0) || ~isstruct(type0) || ~isfield(type0,"Resolution")
    error("sixgr:truth:MissingType0ForSIB1", ...
        "SIB1 allocation requires successfully resolved Type-0 PDCCH.");
end
[~,cfgSI,c,~,slot0] = sixgr.phy.broadcast.resolveSIB1ControlOccasion(carrier,cfg);
pdsch = sixgr.phy.broadcast.configuredSIB1Allocation(c,cfgSI);
materialized = sixgr.phy.frame.ChannelAllocationMaterializer. ...
    materializePDSCH(c,pdsch,"AbsoluteSlot",slot0);
rows = localResultRows(materialized,slot0,"SIB1_PDSCH",1,double(pdsch.NumLayers), ...
    "configured_Type0_DCI_1_0_SI_RNTI_not_received", ...
    "buildSIB1DCI10+nrPDSCHIndices");
for rowIndex = 1:numel(rows), rows(rowIndex).ue_id = NaN; end
out = localPayload(rows,size(materialized.ActualCoordinates0Based,1), ...
    "SI-RNTI DCI and SIB1 PDSCH resolve on the same slot");
end

function out = localPDCCH(cfg,totalSlots,frame,compactPeriodicOutput)
rows = repmat(localEmptyRow(),0,1); count = 0;
cache = containers.Map('KeyType','char','ValueType','any');
keyOrder = cell(0,1);
[carrier,~]=sixgr.phy.grid.makeCarrier(cfg);
connected=isfield(sixgr.util.structGet(cfg,"phy.pdcch.operatorControl",struct()), ...
    'connected_monitoring');
if connected
    % Planning is resource geometry, not a dummy DCI transmission. Use the
    % same installed identity and monitoring object as connected reception.
    context=sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(cfg,'1_1');
    [pdcch,~]=sixgr.phy.pdcch.ConnectedPDCCHConfiguration.build( ...
        cfg,carrier,context.Data.RNTIValue,false);
    period=pdcch.SearchSpace.SlotPeriodAndOffset(1);
    offset=pdcch.SearchSpace.SlotPeriodAndOffset(2);
    duration=pdcch.SearchSpace.Duration;
    resolver="ConnectedPDCCHConfiguration+nrPDCCHResources";
else
    calendar=double(sixgr.util.structGet(cfg, ...
        "phy.pdcch.searchSpace.slotPeriodAndOffset",[1 0]));
    period=calendar(1); offset=0;
    if numel(calendar)>1, offset=calendar(2); end
    duration=1;
    [k,~]=sixgr.phy.pdcch.dciPayloadSizeBits(double(carrier.NSizeGrid), ...
        string(sixgr.util.structGet(cfg,"phy.pdcch.dciFormat","1_0")));
    resolver="buildPDCCHConfigFromScenario+nrPDCCHResources";
end
for slot0 = 0:(totalSlots-1)
    if mod(slot0-offset,period) >= duration || ~frame.IsDLSlot(slot0), continue; end
    c = localCarrierAtSlot(carrier,slot0);
    if ~connected
        [tx,~]=sixgr.phy.dl.PDCCH_Tx(cfg,"Carrier",c, ...
            "DCIBits",int8(zeros(k,1)),"K",k,"OFDMModulate",false);
        pdcch=tx.PDCCH;
    end
    materialized = sixgr.phy.frame.ChannelAllocationMaterializer. ...
        materializePDCCH(c,pdcch,"AbsoluteSlot",slot0);
    slotRows = localResultRows(materialized,slot0,"PDCCH",1,1, ...
        "RRC_SearchSpace_CORESET_and_DCI", ...
        resolver);
    if compactPeriodicOutput
        [cache,keyOrder] = localAccumulatePeriodicRows( ...
            cache,keyOrder,slotRows,slot0);
    else
        rows = [rows; slotRows]; %#ok<AGROW>
    end
    count = count + size(materialized.ActualCoordinates0Based,1);
end
if count == 0, error("sixgr:truth:NoPDCCHOccasion","No legal PDCCH occasion resolved."); end
if compactPeriodicOutput
    rows = localEmitPeriodicRows(cache,keyOrder,"PDCCH");
end
out = localPayload(rows,count,"dedicated PDCCH monitoring occasions resolved");
end

function out = localPDSCH(cfg,carrier,totalSlots,frame,reusePeriodicTemplates,compactPeriodicOutput)
rowParts = cell(totalSlots,1); partCount = 0;
count = 0; blockedSlots = 0;
cache = containers.Map('KeyType','char','ValueType','any');
keyOrder = cell(0,1);
cacheEnabled = reusePeriodicTemplates || compactPeriodicOutput;
symbolAllocation = double(sixgr.util.structGet(cfg, ...
    "phy.pdsch.symbolAllocation", []));
if numel(symbolAllocation) ~= 2
    error("sixgr:truth:MissingPDSCHSymbolAllocation", ...
        "Exact PDSCH planning requires phy.pdsch.symbolAllocation.");
end
for slot0 = 0:(totalSlots-1)
    if ~frame.IsDLAllocation(slot0,symbolAllocation), continue; end
    actual=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,slot0+1);
    c=sixgr.phy.grid.makeCarrier(actual);
    pdsch=sixgr.phy.grid.pdschConfigFromConfig(c,actual);
    reservation=sixgr.phy.frame.ssbPRBSymbolReservation(actual,c,slot0);
    key = localPDSCHCoordinateTemplateKey(actual,c,slot0,reservation);
    if cacheEnabled && isKey(cache,key)
        cached = cache(key);
        if cached.Blocked
            blockedSlots = blockedSlots + 1;
            continue;
        end
        count = count + sum([cached.Rows.re_count]);
        if compactPeriodicOutput
            cached.Slots(end+1) = slot0;
            cache(key) = cached;
        else
            slotRows = localRetargetPeriodicRows(cached.Rows,slot0,"PDSCH");
            partCount = partCount + 1;
            rowParts{partCount} = slotRows;
        end
        continue;
    end
    available=sixgr.phy.grid.pdschPRBsWithoutReservedDMRS(c,pdsch,reservation.ReservedCarrierRE0);
    if isempty(available)
        blockedSlots=blockedSlots+1;
        if cacheEnabled
            cache(key)=struct("Rows",repmat(localEmptyRow(),0,1), ...
                "Blocked",true,"Slots",zeros(1,0));
            keyOrder{end+1,1}=key; %#ok<AGROW>
        end
        continue;
    end
    % The pool can contain multiple islands. It is not a DCI/grant: actual
    % scheduling still enforces contiguous chunks, queue and capability limits.
    [~,~,pdsch]=sixgr.phy.grid.allocREsPDSCH(c,actual,'PRBSet',available);
    m = sixgr.phy.frame.ChannelAllocationMaterializer. ...
        materializePDSCH(c,pdsch,"AbsoluteSlot",slot0);
    slotRows = localResultRows(m,slot0,"PDSCH",1, ...
        double(pdsch.NumLayers),"configured_RRC_BWP_resource_pool_not_scheduler_grant", ...
        "allocREsPDSCH+nrPDSCHIndices");
    count = count + sum([slotRows.re_count]);
    if cacheEnabled
        cache(key)=struct("Rows",slotRows,"Blocked",false,"Slots",slot0);
        keyOrder{end+1,1}=key; %#ok<AGROW>
    end
    if ~compactPeriodicOutput
        partCount = partCount + 1;
        rowParts{partCount} = slotRows;
    end
end
if count == 0, error("sixgr:truth:NoPDSCHOccasion","No legal PDSCH occasion resolved."); end
if compactPeriodicOutput
    for keyIndex = 1:numel(keyOrder)
        key = keyOrder{keyIndex};
        cached = cache(key);
        if cached.Blocked, continue; end
        partCount = partCount + 1;
        rowParts{partCount} = localPeriodicTemplateRows( ...
            cached.Rows,cached.Slots,"PDSCH",key);
    end
end
rows = vertcat(rowParts{1:partCount});
detail = string(sprintf( ...
    'Per-occasion PDSCH resource pools resolved; %d DL occasions have no SSB-safe PRBs. Not executed grants.',blockedSlots));
if compactPeriodicOutput
    detail = detail + " Exact coordinates are stored once per periodic template with explicit occurrence slots.";
end
out = localPayload(rows,count,detail);
end

function out = localPUSCH(cfg,carrier,totalSlots,frame,reusePeriodicTemplates,compactPeriodicOutput)
rowParts = cell(totalSlots,1); partCount = 0; count = 0;
cache = containers.Map('KeyType','char','ValueType','any');
keyOrder = cell(0,1);
cacheEnabled = reusePeriodicTemplates || compactPeriodicOutput;
symbolAllocation = double(sixgr.util.structGet(cfg, ...
    "phy.pusch.symbolAllocation", []));
if numel(symbolAllocation) ~= 2
    error("sixgr:truth:MissingPUSCHSymbolAllocation", ...
        "Exact PUSCH planning requires phy.pusch.symbolAllocation.");
end
for slot0 = 0:(totalSlots-1)
    if ~frame.IsULAllocation(slot0,symbolAllocation), continue; end
    % nrPUSCHIndices resource coordinates are invariant to NSlot/NFrame;
    % only scrambling/reference symbol values change with the clock. This
    % table records coordinates, not generated symbol values.
    key = 'static_pusch_coordinate_geometry';
    if cacheEnabled && isKey(cache,key)
        cached = cache(key);
        count = count + sum([cached.Rows.re_count]);
        if compactPeriodicOutput
            cached.Slots(end+1) = slot0;
            cache(key) = cached;
        else
            slotRows = localRetargetPeriodicRows(cached.Rows,slot0,"PUSCH");
            partCount = partCount + 1;
            rowParts{partCount} = slotRows;
        end
        continue;
    end
    actual=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,slot0+1);
    c=sixgr.phy.grid.makeCarrier(actual);
    [~,~,pusch]=sixgr.phy.grid.allocPUSCHTransport(c,actual);
    m = sixgr.phy.frame.ChannelAllocationMaterializer. ...
        materializePUSCH(c,pusch,"AbsoluteSlot",slot0);
    slotRows = localResultRows(m,slot0,"PUSCH",1, ...
        double(pusch.NumLayers),"configured_RRC_UL_BWP_resource_pool_not_scheduler_grant", ...
        "allocREsPUSCH+nrPUSCHIndices");
    count = count + sum([slotRows.re_count]);
    if cacheEnabled
        cache(key)=struct("Rows",slotRows,"Slots",slot0);
        keyOrder{end+1,1}=key; %#ok<AGROW>
    end
    if ~compactPeriodicOutput
        partCount = partCount + 1;
        rowParts{partCount} = slotRows;
    end
end
if count == 0, error("sixgr:truth:NoPUSCHOccasion","No legal PUSCH occasion resolved."); end
if compactPeriodicOutput
    for keyIndex = 1:numel(keyOrder)
        key = keyOrder{keyIndex};
        cached = cache(key);
        partCount = partCount + 1;
        rowParts{partCount} = localPeriodicTemplateRows( ...
            cached.Rows,cached.Slots,"PUSCH",key);
    end
end
rows = vertcat(rowParts{1:partCount});
detail = "PUSCH data, DM-RS and PT-RS resolved";
if compactPeriodicOutput
    detail = detail + "; exact coordinates are stored once with explicit occurrence slots";
end
out = localPayload(rows,count,detail);
end

function key = localPDSCHCoordinateTemplateKey(cfg,carrier,slot0,reservation)
% Exact coordinate ownership changes only when one of the installed
% reference reservations changes. NSlot/NFrame alter sequences, not RE
% positions, and therefore are deliberately absent from this coordinate
% table key.
[csirsScheduled,~] = sixgr.phy.refsig.csirsOccasion(cfg,slot0);
trsScheduled = sixgr.truth.isActiveTRSOccasion(cfg,slot0+1);
csiimScheduled = false;
if logical(sixgr.util.structGet(cfg,'phy.csiim.enabled',false))
    csiim = sixgr.phy.refsig.csiIMResource(carrier,cfg);
    csiimScheduled = logical(csiim.Scheduled);
end
reserved = double(sixgr.util.structGet(reservation, ...
    'ReservedCarrierRE0',zeros(0,1)));
if isempty(reserved)
    ssbDigest = "none";
else
    encoded = sprintf('%.0f,',reserved(:));
    ssbDigest = sixgr.util.sha256Hex(uint8(unicode2native(encoded,'UTF-8')));
end
key = char("ssb="+ssbDigest+"|csirs="+string(double(csirsScheduled))+ ...
    "|trs="+string(double(trsScheduled))+ ...
    "|csiim="+string(double(csiimScheduled)));
end

function rows = localRetargetPeriodicRows(template,slot0,channel)
rows = template;
allocationID = lower(string(channel))+"_slot_"+string(slot0);
for rowIndex = 1:numel(rows)
    rows(rowIndex).absolute_slot = slot0;
    rows(rowIndex).sfn = NaN;
    rows(rowIndex).slot_within_frame = NaN;
    rows(rowIndex).allocation_id = allocationID;
    rows(rowIndex).occurrence_slots = string(slot0);
    rows(rowIndex).occurrence_count = 1;
end
end

function [cache,keyOrder] = localAccumulatePeriodicRows(cache,keyOrder,slotRows,slot0,varargin)
identity = "";
if nargin >= 5, identity = string(varargin{1}); end
key = char(identity+"|"+string(localCoordinateRowsKey(slotRows)));
if isKey(cache,key)
    entry = cache(key);
    entry.Slots(end+1) = slot0;
    cache(key) = entry;
else
    cache(key) = struct("Rows",slotRows,"Slots",slot0);
    keyOrder{end+1,1} = key; %#ok<AGROW>
end
end

function rows = localEmitPeriodicRows(cache,keyOrder,channel)
parts = cell(numel(keyOrder),1);
for keyIndex = 1:numel(keyOrder)
    key = keyOrder{keyIndex};
    entry = cache(key);
    parts{keyIndex} = localPeriodicTemplateRows( ...
        entry.Rows,entry.Slots,channel,key);
end
if isempty(parts)
    rows = repmat(localEmptyRow(),0,1);
else
    rows = vertcat(parts{:});
end
end

function key = localCoordinateRowsKey(rows)
% Hash only exact coordinate/ownership content. Absolute time and allocation
% IDs are represented separately by the explicit occurrence list.
tokens = strings(numel(rows),1);
for rowIndex = 1:numel(rows)
    row = rows(rowIndex);
    values = [ ...
        string(row.direction),string(row.channel),string(row.component), ...
        string(row.subcarrier_start),string(row.subcarrier_count), ...
        string(row.symbol_index),string(row.port_index),string(row.re_count), ...
        string(row.cell_id),string(row.ue_id),string(row.layer_count), ...
        string(row.authority),string(row.resolver),string(row.grid_domain), ...
        string(row.grid_subcarrier_spacing_hz), ...
        string(row.grid_subcarrier_count),string(row.grid_symbol_count)];
    values(ismissing(values)) = "<missing>";
    tokens(rowIndex) = strjoin(values,"|");
end
tokens(ismissing(tokens)) = "<missing_row>";
encoded = unicode2native(char(join(tokens,newline)),'UTF-8');
key = char(sixgr.util.sha256Hex(uint8(encoded)));
end

function rows = localPeriodicTemplateRows(template,slots,channel,key)
% Keep exact contiguous-RE coordinates while removing only redundant copies.
% occurrence_slots is the complete zero-based slot identity set; consumers
% can reconstruct the expanded table without guessing periodicity.
slots = unique(double(slots(:).'),"stable");
assert(~isempty(slots) && all(isfinite(slots)) && ...
    all(slots >= 0) && all(slots == fix(slots)), ...
    "sixgr:truth:InvalidPeriodicAllocationOccurrences", ...
    "Periodic allocation templates require explicit finite zero-based slots.");
rows = template;
slotText = join(string(slots),"|");
encodedKey = unicode2native(char(string(key)),'UTF-8');
digest = string(sixgr.util.sha256Hex(uint8(encodedKey)));
allocationID = lower(string(channel))+"_periodic_template_"+extractBetween(digest,1,16);
for rowIndex = 1:numel(rows)
    rows(rowIndex).absolute_slot = slots(1);
    rows(rowIndex).sfn = NaN;
    rows(rowIndex).slot_within_frame = NaN;
    rows(rowIndex).allocation_id = allocationID;
    rows(rowIndex).occurrence_slots = slotText;
    rows(rowIndex).occurrence_count = numel(slots);
    rows(rowIndex).coordinate_precision = "exact_periodic_contiguous_re_run";
    rows(rowIndex).evidence_scope = ...
        "planned_config_periodic_template_not_runtime_observation";
end
end

function out = localCSIRS(cfg,carrier,totalSlots,frame,compactPeriodicOutput)
rows = repmat(localEmptyRow(),0,1); count=0;
cache = containers.Map('KeyType','char','ValueType','any');
keyOrder = cell(0,1);
for slot0=0:(totalSlots-1)
    if ~frame.IsDLSlot(slot0), continue; end
    cfgSlot=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,slot0+1);
    [scheduled,~]=sixgr.phy.refsig.csirsOccasion(cfgSlot,slot0);
    if ~scheduled, continue; end
    c=localCarrierAtSlot(carrier,slot0);
    [~,~,info,primary]=sixgr.phy.refsig.csirs(c,cfgSlot);
    assert(info.Scheduled,"sixgr:truth:CSIRSCalendarResolutionMismatch", ...
        "The CSI-RS calendar and physical CSI-RS resolver disagree for slot %d.",slot0);
    configs={primary};
    if isfield(info,"Resources") && ~isempty(info.Resources)
        configs=cell(numel(info.Resources),1);
        for i=1:numel(info.Resources), configs{i}=info.Resources(i).Configuration; end
    end
    for i=1:numel(configs)
        m=sixgr.phy.frame.ChannelAllocationMaterializer.materializeReferenceSignal( ...
            c,"CSI_RS",configs{i},"AbsoluteSlot",slot0);
        slotRows=localResultRows(m,slot0,"CSI_RS",1,NaN, ...
            "RRC_CSI_RS_resource_configuration", ...
            "sixgr.phy.refsig.csirs+nrCSIRSIndices");
        for j=1:numel(slotRows), slotRows(j).csi_resource_index=i-1; end
        if compactPeriodicOutput
            [cache,keyOrder]=localAccumulatePeriodicRows( ...
                cache,keyOrder,slotRows,slot0, ...
                "csi_rs_resource_"+string(i));
        else
            rows=[rows;slotRows]; %#ok<AGROW>
        end
        count=count+size(m.ActualCoordinates0Based,1);
    end
end
if count==0,error("sixgr:truth:NoCSIRSOccasion","No CSI-RS RE resolved in run window.");end
if compactPeriodicOutput
    rows=localEmitPeriodicRows(cache,keyOrder,"CSI_RS");
end
out=localPayload(rows,count,"CSI-RS resources resolved");
end

function out = localTRS(cfg,totalSlots,frame,compactPeriodicOutput)
strict=sixgr.phy.trs.buildTRSConfigFromScenario(cfg);
rows=repmat(localEmptyRow(),0,1);count=0;
cache = containers.Map('KeyType','char','ValueType','any');
keyOrder = cell(0,1);
for slot0=0:totalSlots-1
    if ~sixgr.truth.isActiveTRSOccasion(cfg,slot0+1),continue;end
    c=localCarrierAtSlot(strict.ToolboxCarrier,slot0);
    for resourceIndex=1:numel(strict.ToolboxResources)
    m=sixgr.phy.frame.ChannelAllocationMaterializer.materializeReferenceSignal( ...
        c,"CSI_RS",strict.ToolboxResources{resourceIndex},"AbsoluteSlot",slot0);
    slotRows=localResultRows(m,slot0,"TRS",1,NaN, ...
        "RRC_NZP_CSI_RS_TRS_resource_configuration", ...
        "buildTRSConfigFromScenario+nrCSIRSIndices");
    if compactPeriodicOutput
        [cache,keyOrder]=localAccumulatePeriodicRows( ...
            cache,keyOrder,slotRows,slot0, ...
            "trs_resource_"+string(resourceIndex));
    else
        rows=[rows;slotRows]; %#ok<AGROW>
    end
    count=count+size(m.ActualCoordinates0Based,1);
    end
end
if count==0,error("sixgr:truth:NoTRSOccasion","No TRS RE resolved in run window.");end
if compactPeriodicOutput
    rows=localEmitPeriodicRows(cache,keyOrder,"TRS");
end
out=localPayload(rows,count,"TRS resources resolved");
end

function out = localPRACH(cfg,carrier,totalSlots,frame)
strict=sixgr.rach.PRACHConfig(cfg);
slots=[];
if isfield(strict,"FirstActiveOccasion") && isstruct(strict.FirstActiveOccasion)
    % PRACHConfig publishes the canonical zero-based carrier-slot identity
    % as SlotIndex0.  Older evidence used AbsoluteSlot; retain read
    % compatibility without making the legacy alias authoritative.
    slots=double(sixgr.util.structGet(strict.FirstActiveOccasion,"SlotIndex0", ...
        sixgr.util.structGet(strict.FirstActiveOccasion,"AbsoluteSlot",[])));
end
if isempty(slots)
    for slot1=1:totalSlots
        if sixgr.truth.isActivePRACHOccasion(cfg,slot1),slots(end+1)=slot1-1;end %#ok<AGROW>
    end
end
slots=unique(slots);slots=slots(slots>=0 & slots<totalSlots);
rows=repmat(localEmptyRow(),0,1);count=0;
for slot0=reshape(slots,1,[])
    if ~frame.IsULSlot(slot0),continue;end
    c=localCarrierAtSlot(carrier,slot0);
    m=sixgr.phy.frame.ChannelAllocationMaterializer.materializePRACH( ...
        c,strict.ToolboxPRACH,"AbsoluteSlot",slot0);
    rows=[rows;localResultRows(m,slot0,"PRACH",1,NaN, ...
        "decoded_SIB1_RACH_ConfigCommon","PRACHConfig+nrPRACHIndices")]; %#ok<AGROW>
    count=count+size(m.ActualCoordinates0Based,1);
end
if count==0,error("sixgr:truth:NoPRACHOccasion","No legal PRACH occasion resolved.");end
out=localPayload(rows,count,"PRACH occasions resolved from RACH-ConfigCommon");
end

function out = localPUCCH(cfg,carrier,totalSlots,frame)
section=sixgr.util.structGet(cfg,"validation.pucch_resources",struct());
resources=sixgr.util.structGet(section,"resources",struct([]));
if ~isstruct(resources)||isempty(resources)
    error("sixgr:truth:MissingPUCCHResources","Enabled PUCCH has no RRC resources.");
end
slots=find(arrayfun(@(x)frame.IsULSlot(x),0:(totalSlots-1)))-1;
if isempty(slots),error("sixgr:truth:NoPUCCHOccasion","No UL slot available for PUCCH.");end
rows=repmat(localEmptyRow(),0,1);count=0;
for i=1:numel(resources)
    d=localPUCCHData(resources(i));
    object=sixgr.phy.pucch.PUCCHResource(d).toolboxConfig();
    slot0=slots(1+mod(i-1,numel(slots)));
    c=localCarrierAtSlot(carrier,slot0);
    m=sixgr.phy.frame.ChannelAllocationMaterializer.materializePUCCH( ...
        c,object,"AbsoluteSlot",slot0);
    rows=[rows;localResultRows(m,slot0,"PUCCH",1,NaN, ...
        "RRC_PUCCH_resource_and_DCI_K1_PRI", ...
        "PUCCHResource.toolboxConfig+nrPUCCHIndices")]; %#ok<AGROW>
    count=count+size(m.ActualCoordinates0Based,1);
end
out=localPayload(rows,count,"all configured PUCCH resources resolved");
end

function out = localSRS(cfg,carrier,totalSlots,frame,compactPeriodicOutput)
srsStrict=sixgr.phy.srs.buildSRSConfigFromScenario(cfg);
srs=srsStrict.ToolboxSRS;
period=double(srs.SRSPeriod(1));offset=double(srs.SRSPeriod(2));
rows=repmat(localEmptyRow(),0,1);count=0;
cache = containers.Map('KeyType','char','ValueType','any');
keyOrder = cell(0,1);
for slot0=0:(totalSlots-1)
    if mod(slot0-offset,period)~=0 || ~frame.IsULSlot(slot0),continue;end
    c=localCarrierAtSlot(carrier,slot0);
    m=sixgr.phy.frame.ChannelAllocationMaterializer.materializeReferenceSignal( ...
        c,"SRS",srs,"AbsoluteSlot",slot0);
    slotRows=localResultRows(m,slot0,"SRS",1,NaN, ...
        "RRC_SRS_resource_configuration", ...
        "buildSRSConfigFromScenario+nrSRSIndices");
    if compactPeriodicOutput
        [cache,keyOrder]=localAccumulatePeriodicRows( ...
            cache,keyOrder,slotRows,slot0);
    else
        rows=[rows;slotRows]; %#ok<AGROW>
    end
    count=count+size(m.ActualCoordinates0Based,1);
end
if count==0,error("sixgr:truth:NoSRSOccasion","No SRS RE resolved in run window.");end
if compactPeriodicOutput
    rows=localEmitPeriodicRows(cache,keyOrder,"SRS");
end
out=localPayload(rows,count,"SRS resources resolved");
end

function d=localPUCCHData(r)
d=struct("ID",localField(r,["id","resource_id"]), ...
    "Format",localField(r,"format"), ...
    "StartPRB",localField(r,"starting_prb"), ...
    "NumPRBs",localField(r,["nrof_prbs","num_prb"]), ...
    "StartSymbol",localField(r,["starting_symbol","symbol_start"]), ...
    "NumSymbols",localField(r,["nrof_symbols","num_symbols"]), ...
    "IntraSlotHopping",logical(localField(r,"intra_slot_hopping")), ...
    "SecondHopStartPRB",localField(r,"second_hop_start_prb",NaN), ...
    "InitialCyclicShift",localField(r,"initial_cyclic_shift"), ...
    "OCCLength",localField(r,"occ_length"), ...
    "OCCIndex",localField(r,"occ_index"), ...
    "AdditionalDMRS",logical(localField(r,"additional_dmrs")), ...
    "Pi2BPSK",logical(localField(r,"pi2_bpsk")), ...
    "RNTI",4660,"NID",localField(r,"nid"), ...
    "HoppingID",localField(r,"hopping_id"));
end

function value=localField(s,names,varargin)
if nargin>=3,value=varargin{1};else,value=[];end
for n=string(names)
    if isfield(s,char(n)) && ~isempty(s.(char(n))),value=s.(char(n));return;end
end
if isempty(value),error("sixgr:truth:MissingAllocationField", ...
        "Missing allocation field %s.",strjoin(string(names),"/"));end
end

function c=localCarrierAtSlot(carrier,slot0)
c=carrier;
slotsPerFrame=10*round(double(c.SlotsPerSubframe));
c.NSlot=mod(slot0,slotsPerFrame);
c.NFrame=floor(slot0/slotsPerFrame);
end

function rows=localResultRows(result,slot0,channel,cellID,layerCount,authority,resolver)
parts={};labels=strings(0,1);
for name=["Data","DMRS","PTRS","Resources"]
    if isfield(result,char(name)) && isstruct(result.(char(name))) && ...
            isfield(result.(char(name)),"Coordinates0Based") && ...
            ~isempty(result.(char(name)).Coordinates0Based)
        parts{end+1}=result.(char(name)).Coordinates0Based; %#ok<AGROW>
        labels(end+1)=string(result.(char(name)).Label); %#ok<AGROW>
    end
end
if isempty(parts)
    parts={result.ActualCoordinates0Based};labels=string(channel);
end
rows=repmat(localEmptyRow(),0,1);
for i=1:numel(parts)
    rows=[rows;localRows(double(parts{i}),slot0,string(channel), ...
        labels(i),cellID,layerCount,string(authority),string(resolver), ...
        lower(string(channel))+"_slot_"+string(slot0))]; %#ok<AGROW>
end
if isfield(result,'GridDomain')
    for i=1:numel(rows)
        rows(i).grid_domain=string(result.GridDomain);
        rows(i).grid_subcarrier_spacing_hz=result.NativeGridSubcarrierSpacingHz;
        rows(i).grid_subcarrier_count=result.NativeGridSubcarrierCount;
        rows(i).grid_symbol_count=result.NativeGridSymbolCount;
    end
end
end

function rows=localRows(coords,slot0,channel,component,cellID,layerCount,authority,resolver,id)
if isempty(coords),rows=repmat(localEmptyRow(),0,1);return;end
coords=unique(double(coords),"rows","sorted");
rows=repmat(localEmptyRow(),0,1);
keys=unique(coords(:,2:3),"rows","stable");
for k=1:size(keys,1)
    sc=sort(coords(coords(:,2)==keys(k,1)&coords(:,3)==keys(k,2),1));
    cuts=[1;find(diff(sc)~=1)+1;numel(sc)+1];
    for j=1:(numel(cuts)-1)
        run=sc(cuts(j):(cuts(j+1)-1));r=localEmptyRow();
        r.absolute_slot=slot0;r.sfn=NaN;r.slot_within_frame=NaN;
        r.direction=localDirection(channel);r.channel=channel;r.component=component;
        r.subcarrier_start=run(1);r.subcarrier_count=numel(run);
        r.symbol_index=keys(k,1);r.port_index=keys(k,2);r.re_count=numel(run);
        r.cell_id=cellID;r.ue_id=1;r.layer_count=layerCount;
        r.authority=authority;r.resolver=resolver;r.allocation_id=id;
        r.occurrence_slots=string(slot0);r.occurrence_count=1;
        rows(end+1,1)=r; %#ok<AGROW>
    end
end
end

function direction=localDirection(channel)
if any(channel==["PRACH","PUCCH","PUSCH","SRS"]),direction="UL";else,direction="DL";end
end

function localAssertCoordinates(coords,carrier)
if isempty(coords)||size(coords,2)~=3||any(~isfinite(coords),"all")|| ...
        any(coords<0,"all")||any(coords~=fix(coords),"all")|| ...
        any(coords(:,1)>=12*double(carrier.NSizeGrid))||any(coords(:,2)>=14)
    error("sixgr:truth:InvalidExactRECoordinates", ...
        "Exact allocation contains out-of-grid coordinates.");
end
end

function [rows,checks]=localAttempt(rows,checks,feature,direction,enabled,authority,resolver,fn)
[rows,checks]=localAttemptValue(rows,checks,feature,direction,enabled,authority,resolver,fn);
end

function [rows,checks,value]=localAttemptValue(rows,checks,feature,direction,enabled,authority,resolver,fn)
value=[];c=localEmptyCheck();c.feature=feature;c.direction=direction;c.enabled=enabled;
c.authority=authority;c.resolver=resolver;
if ~enabled,c.resolved=true;c.status="DISABLED";c.detail="disabled by resolved YAML";checks(end+1,1)=c;return;end
try
    payload=fn();
    if isfield(payload,"Value"),value=payload.Value;end
    if ~isfield(payload,"Rows")||isempty(payload.Rows)&&payload.RECount<=0
        error("sixgr:truth:EmptyEnabledAllocation", ...
            "Enabled feature %s produced no exact allocation evidence.",feature);
    end
    rows=[rows;payload.Rows]; %#ok<AGROW>
    c.resolved=true;c.exact_re_count=payload.RECount;c.status="PASS";c.detail=payload.Detail;
catch cause
    c.resolved=false;c.status="FAIL";c.error_id=string(cause.identifier);
    c.detail=string(cause.message);
    if ~isempty(cause.stack)
        c.detail = c.detail + " [" + string(cause.stack(1).name) + ...
            ":" + string(cause.stack(1).line) + "]";
    end
end
checks(end+1,1)=c;
end

function out=localPayload(rows,count,detail,varargin)
out=struct("Rows",rows,"RECount",double(count),"Detail",string(detail));
if nargin>=4,out.Value=varargin{1};end
end

function row=localEmptyRow()
row=struct("absolute_slot",NaN,"sfn",NaN,"slot_within_frame",NaN, ...
    "direction","","channel","","component","", ...
    "subcarrier_start",NaN,"subcarrier_count",NaN,"symbol_index",NaN, ...
    "port_index",NaN,"re_count",NaN,"cell_id",NaN,"ue_id",NaN,"csi_resource_index",NaN, ...
    "layer_count",NaN,"authority","","resolver","", ...
    "allocation_id","","occurrence_slots","","occurrence_count",NaN, ...
    "coordinate_precision","exact_contiguous_re_run", ...
    "evidence_scope","planned_config_not_runtime_observation", ...
    "grid_domain","carrier_cp_ofdm", "grid_subcarrier_spacing_hz",NaN, ...
    "grid_subcarrier_count",NaN,"grid_symbol_count",NaN);
end

function c=localEmptyCheck()
c=struct("feature","","direction","","enabled",false,"resolved",false, ...
    "exact_re_count",0,"authority","","resolver","","status","", ...
    "error_id","","detail","");
end
