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
        "PDSCH";"CSI_RS";"CSI_IM";"TRS";"PRACH";"PUCCH";"PUSCH";"SRS"];
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
if isfield(cfg.run,'executionHorizon')
    % A standalone PRACH campaign's legacy duration cannot extend a bounded
    % connected-run grid beyond its explicit scheduling endpoint.
    totalSlots=min(totalSlots,double(cfg.run.executionHorizon.FinishAfterSlot));
end
rows = repmat(localEmptyRow(), 0, 1);
checks = repmat(localEmptyCheck(), 0, 1);

[rows, checks] = localAttempt(rows, checks, "FRAME", "BIDIR", true, ...
    "carrier_and_duplex_yaml", "sixgr.phy.FrameStructureEngine", ...
    @() localFrame(frame, carrier));

ssbConfigured = logical(sixgr.util.structGet(cfg, "phy.ssb.enable", false));
ssbEnabled = isSelected("SSB_PBCH") && ssbConfigured;
[rows, checks] = localAttempt(rows, checks, "SSB_PBCH", "DL", ...
    ssbEnabled, "MIB_and_SSB_burst_configuration", ...
    "FrameStructureEngine+nrPSS/SSS/PBCHIndices", ...
    @() localSSB(cfg, carrier, totalSlots));

% Use the same normalized SIB1 execution flag as the waveform runtime.
% An SSB alone does not schedule SI-RNTI control. TargetChannels selects
% published allocations, not the configuration of their dependencies.
sib1Configured = logical(sixgr.util.structGet(cfg, "phy.sib1.enable", false));
type0Enabled = isSelected("TYPE0_PDCCH") && sib1Configured;
[rows, checks, type0] = localAttemptValue(rows, checks, ...
    "TYPE0_PDCCH", "DL", type0Enabled, "configured_MIB_bits_preflight_not_received", ...
    "deriveType0PDCCHFromMIB+nrPDCCHResources", ...
    @() localType0(cfg, carrier, totalSlots, frame));

sib1Enabled = isSelected("SIB1_PDSCH") && sib1Configured;
[rows, checks] = localAttempt(rows, checks, "SIB1_PDSCH", "DL", ...
    sib1Enabled, "configured_Type0_DCI_1_0_SI_RNTI_not_received", ...
    "buildSIB1DCI10+nrPDSCHIndices", ...
    @() localSIB1(cfg, carrier, type0, totalSlots, frame));

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

csiimEnabled = isSelected("CSI_IM") && ...
    logical(sixgr.util.structGet(cfg,"phy.csiim.enabled",false));
[rows,checks] = localAttempt(rows,checks,"CSI_IM","DL",csiimEnabled, ...
    "RRC_CSI_IM_resource_configuration", "sixgr.phy.refsig.csiIMResource", ...
    @() localCSIIM(cfg,carrier,totalSlots,frame,compactPeriodicOutput));

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
    [T.sfn,T.slot_within_frame] = sixgr.truth.reAllocationRadioClock( ...
        T.absolute_slot,slotsPerFrame);
    nativeSSB=T.grid_domain=="ssb_native_cp_ofdm";
    nativeSlotsPerFrame=10*T.grid_subcarrier_spacing_hz(nativeSSB)/15000;
    [nativeSFN,nativeSlot] = sixgr.truth.reAllocationRadioClock( ...
        T.absolute_slot(nativeSSB),nativeSlotsPerFrame);
    T.sfn(nativeSSB)=nativeSFN;
    T.slot_within_frame(nativeSSB)=nativeSlot;
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
timing=sixgr.phy.frame.SSBTimingResolver.resolveFromConfig(cfg);
if timing.SSBSubcarrierSpacingKHz~=carrier.SubcarrierSpacing
    out=localNativeSSB(cfg,carrier,totalSlots,timing);
    return;
end
nCellID = double(carrier.NCellID);
nCRB = double(sixgr.util.structGet(cfg, "phy.ssb.nCRBSSB", ...
    sixgr.util.structGet(cfg,"phy.ssb.NCRBSSB",NaN)));
kSSB = double(sixgr.util.structGet(cfg, "phy.ssb.kSSB", ...
    sixgr.util.structGet(cfg,"phy.ssb.KSSB",NaN)));
if any(~isfinite([nCRB kSSB]))
    error("sixgr:truth:MissingSSBFrequencyPlacement", ...
        "Enabled SSB requires resolved nCRBSSB and kSSB.");
end
% nCRB/kSSB are Point-A reference units, not necessarily carrier bins.
% Use the same physical grid relationship as the production SSB reservation.
grid=timing.GridRelationship;
assert(timing.CarrierSubcarrierSpacingKHz==carrier.SubcarrierSpacing && ...
    grid.NStartGrid==carrier.NStartGrid && grid.NSizeGrid==carrier.NSizeGrid, ...
    'sixgr:truth:PlannedSSBCarrierMismatch','SSB and planned carrier must share one physical grid.');
baseSC=(double(grid.SSBLowOffsetFromPointAHz)- ...
    double(grid.CarrierLowOffsetFromPointAHz))/(double(carrier.SubcarrierSpacing)*1000);
validateattributes(baseSC,{'numeric'},{'scalar','real','finite','integer','nonnegative'});
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

function out=localNativeSSB(cfg,carrier,totalSlots,timing)
% Planned native REs, not an expanded common-grid occupancy estimate.
scs=double(timing.SSBSubcarrierSpacingKHz);
active=double(cfg.phy.ssb.activeCandidateIndices0Based);
spec=struct('SCSKHz',scs,'CyclicPrefix',"normal");
ofdm=nrOFDMInfo(carrier); fs=double(ofdm.SampleRate);
duration=double(totalSlots)/(1000*double(carrier.SlotsPerSubframe));
period=double(timing.PeriodicityMs)*scs/15*14;
assert(period>0 && period==fix(period),'sixgr:truth:InvalidNativeSSBPeriod','Native SSB period must resolve exactly.');
low=double(timing.GridRelationship.SSBLowOffsetFromPointAHz- ...
    timing.GridRelationship.CarrierLowOffsetFromPointAHz);
bandwidth=12*double(carrier.NSizeGrid)*double(carrier.SubcarrierSpacing)*1000;
indices={nrPSSIndices(),nrSSSIndices(),nrPBCHIndices(carrier.NCellID),nrPBCHDMRSIndices(carrier.NCellID)};
labels=["PSS","SSS","PBCH","PBCH_DMRS"];
rows=repmat(localEmptyRow(),0,1); candidates=0;
for cycle=0:ceil(duration*1000/timing.PeriodicityMs)-1
    for beam=reshape(active,1,[])
        first=cycle*period+double(timing.CandidateStartSymbols(beam+1));
        ending=sixgr.phy.frame.AbsoluteTime.fromAbsoluteSlotSymbol(floor((first+4)/14),mod(first+4,14),spec);
        if ending.seconds()>duration+1e-12, continue; end
        candidates=candidates+1;
        for component=1:numel(labels)
            coords=localSSBCoordinates(indices{component});
            symbols=coords(:,2)+first;
            for slot=reshape(unique(floor(symbols/14)),1,[])
                selected=floor(symbols/14)==slot;
                local=coords(selected,:); local(:,2)=mod(symbols(selected),14);
                part=localRows(local,slot,"SSB_PBCH",labels(component),carrier.NCellID,NaN, ...
                    "MIB_and_SSB_burst_configuration","native_nr_SS_PBCH_indices_and_CP_clock", ...
                    "ssb_candidate_"+beam+"_cycle_"+cycle);
                for k=1:numel(part)
                    r=part(k); time=sixgr.phy.frame.AbsoluteTime.fromAbsoluteSlotSymbol(slot,r.symbol_index,spec);
                    stop=time.plusSymbols(1,spec);
                    r.grid_domain="ssb_native_cp_ofdm";
                    r.grid_subcarrier_spacing_hz=scs*1000;
                    r.grid_subcarrier_count=240; r.grid_symbol_count=14;
                    r.coordinate_precision="exact_native_ssb_grid_run";
                    r.cp_start_sample=round(time.seconds()*fs);
                    r.useful_end_sample_exclusive=round(stop.seconds()*fs);
                    r.useful_start_sample=r.useful_end_sample_exclusive-fs/(scs*1000);
                    r.observation_sample_rate_hz=fs;
                    r.frequency_first_hz=low-bandwidth/2+r.subcarrier_start*scs*1000;
                    r.frequency_last_hz=r.frequency_first_hz+(r.subcarrier_count-1)*scs*1000;
                    r.ssb_index0=beam;
                    rows(end+1,1)=r; %#ok<AGROW>
                end
            end
        end
    end
end
assert(candidates>0,'sixgr:truth:NoActiveSSBOccasion','No complete native SSB occurs within the configured horizon.');
out=localPayload(rows,sum([rows.re_count]),sprintf('%d native SS/PBCH candidates; no common-grid RE substitution',candidates));
end

function coords = localSSBCoordinates(linearIndices)
% Toolbox SS/PBCH indices address the standardized 240-by-4 SS/PBCH grid.
% Convert explicitly instead of relying on release-dependent NVP support.
[subcarrier, symbol] = ind2sub([240 4], double(linearIndices(:)));
coords = [subcarrier-1 symbol-1 zeros(numel(subcarrier),1)];
end

function out = localType0(cfg, carrier, totalSlots, frame)
indices=sixgr.phy.broadcast.resolveSIB1TransmitSSBIndices(cfg);
if numel(indices)>1
    rows=repmat(localEmptyRow(),0,1); count=0; value=struct();
    for index=indices
        child=cfg; child.phy.sib1.transmissionScope="selected_ssb_occasion";
        child.phy.ssb.runtimeSSBIndex=index;
        part=localType0(child,carrier,totalSlots,frame);
        for row=1:numel(part.Rows)
            part.Rows(row).allocation_id=part.Rows(row).allocation_id+"_ssb_"+index;
        end
        rows=[rows;part.Rows]; count=count+part.RECount; %#ok<AGROW>
        if isempty(fieldnames(value)), value=part.Value; end
    end
    out=localPayload(rows,count,"configured Type-0 monitoring across the transmitted SI beam set",value);
    return;
end
if ~logical(sixgr.util.structGet(cfg, "phy.ssb.enable", false)) || ...
        ~logical(sixgr.util.structGet(cfg, "phy.mib.enable", true))
    error("sixgr:truth:MissingMIBControlAuthority", ...
        "Enabled SIB1 requires configured SSB and MIB for Type-0 control.");
end
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
% The resolver provides the canonical monitoring period. Expand its exact
% occasions, not an assumed SSB period or an executed-transmission claim.
slots=zeros(0,1);
for ordinal=1:height(occasions)
    first=double(occasions.AbsoluteSlot(ordinal));
    period=double(occasions.PeriodSlots(ordinal));
    validateattributes(period,{'numeric'},{'scalar','finite','integer','positive'});
    slots=[slots;(first:period:totalSlots-1).']; %#ok<AGROW>
end
slots=unique(slots);
slots = slots(slots >= 0 & slots < totalSlots);
controlSymbols=[double(resolution.PDCCH.SearchSpace.StartSymbolWithinSlot), ...
    double(resolution.PDCCH.CORESET.Duration)];
slots=slots(arrayfun(@(slot)frame.IsDLAllocation(slot,controlSymbols),slots));
if isempty(slots)
    error("sixgr:truth:NoType0Occasion", ...
        "Configured MIB resolved no DL-capable Type-0 monitoring occasion in the run window.");
end
rows = repmat(localEmptyRow(),0,1);
for slot0 = reshape(slots,1,[])
    c = localCarrierAtSlot(carrier,slot0);
    materialized = sixgr.phy.frame.ChannelAllocationMaterializer. ...
        materializePDCCH(c,resolution.PDCCH,"AbsoluteSlot",slot0);
    rows = [rows; localResultRows(materialized,slot0,"TYPE0_PDCCH", ...
        1,NaN,"configured_MIB_bits_preflight_not_received", ...
        "deriveType0PDCCHFromMIB+nrPDCCHResources")]; %#ok<AGROW>
end
value = struct("Resolution",resolution,"Config",cfgSI, ...
    "Slots",slots,"Carrier",carrier);
% Each allocation ID denotes a monitoring occasion, not a resource element.
% Count its actual data and DM-RS coordinates, as for other planned channels.
out = localPayload(rows,sum([rows.re_count]), ...
    sprintf("%d Type-0 monitoring slot(s)",numel(slots)),value);
end

function out = localSIB1(cfg, carrier, type0, totalSlots, frame)
indices=sixgr.phy.broadcast.resolveSIB1TransmitSSBIndices(cfg);
if numel(indices)>1
    rows=repmat(localEmptyRow(),0,1); count=0;
    for index=indices
        child=cfg; child.phy.sib1.transmissionScope="selected_ssb_occasion";
        child.phy.ssb.runtimeSSBIndex=index;
        part=localSIB1(child,carrier,type0,totalSlots,frame);
        for row=1:numel(part.Rows)
            part.Rows(row).allocation_id=part.Rows(row).allocation_id+"_ssb_"+index;
        end
        rows=[rows;part.Rows]; count=count+part.RECount; %#ok<AGROW>
    end
    out=localPayload(rows,count,"exact configured SI-RNTI PDSCH on every transmitted SSB-associated occasion");
    return;
end
if isempty(type0) || ~isstruct(type0) || ~isfield(type0,"Resolution")
    % Resolve the dependency even when TYPE0_PDCCH is not selected for
    % publication. Errors remain fatal to this enabled SIB1 allocation;
    % unrequested Type-0 rows are not inserted in the output table.
    localType0(cfg, carrier, totalSlots, frame);
end
% Reuse installed SI resource ownership. BroadcastPeriodSlots is the legacy
% alias for the SI calendar, not the independently configured SSB period.
% Never modulo-fold an SI transmission before its first configured occasion.
common=sixgr.phy.frame.CommonDLResourcePlan(cfg);
pdsch=common.SIB1PDSCH;
slots=common.SIB1Slot0:common.BroadcastPeriodSlots:totalSlots-1;
controlSymbols=[double(common.SIB1PDCCH.SearchSpace.StartSymbolWithinSlot), ...
    double(common.SIB1PDCCH.CORESET.Duration)];
rows=repmat(localEmptyRow(),0,1);
for slot0=slots
    assert(frame.IsDLAllocation(slot0,controlSymbols) && ...
        frame.IsDLAllocation(slot0,pdsch.SymbolAllocation), ...
        'sixgr:truth:PlannedSIB1OutsideDL', ...
        'Configured repeated SI control/data symbols are not DL-capable at slot0 %d.',slot0);
    c=localCarrierAtSlot(carrier,slot0);
    materialized = sixgr.phy.frame.ChannelAllocationMaterializer. ...
        materializePDSCH(c,pdsch,"AbsoluteSlot",slot0);
    rows=[rows;localResultRows(materialized,slot0,"SIB1_PDSCH",1,double(pdsch.NumLayers), ...
        "configured_Type0_DCI_1_0_SI_RNTI_not_received", ...
        "CommonDLResourcePlan+buildSIB1DCI10+nrPDSCHIndices")]; %#ok<AGROW>
end
for rowIndex = 1:numel(rows), rows(rowIndex).ue_id = NaN; end
out = localPayload(rows,sum([rows.re_count]), ...
    "Configured periodic SI-RNTI DCI and SIB1 PDSCH share each planned slot; not observed execution");
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
    allocation = symbolAllocation;
    selectedTDRA = NaN;
    if ~frame.IsDLAllocation(slot0,allocation)
        % A planned pool uses the same authored, same-slot TDRA selection
        % as the scheduler budget. Never clip a full-slot allocation into
        % the DL part of a special slot or manufacture a scheduled grant.
        if frame.DuplexMode ~= "TDD", continue; end
        partition = frame.SlotPartition(slot0);
        selection = sixgr.truth.selectConfiguredTDRARow( ...
            cfg,"DL",double(partition.DLSymbolAllocation),0);
        if isempty(selection), continue; end
        allocation = selection.SymbolAllocation;
        selectedTDRA = selection.Index;
        assert(frame.IsDLAllocation(slot0,allocation), ...
            "sixgr:truth:PlannedPDSCHTDRAPartitionMismatch", ...
            "The configured TDRA must fit the original resolved DL symbols.");
    end
    actual=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,slot0+1);
    actual.phy.pdsch.symbolAllocation = allocation;
    c=sixgr.phy.grid.makeCarrier(actual);
    pdsch=sixgr.phy.grid.pdschConfigFromConfig(c,actual);
    reservation=sixgr.phy.frame.ssbPRBSymbolReservation(actual,c,slot0);
    key = localPDSCHCoordinateTemplateKey(actual,c,slot0,reservation,pdsch,selectedTDRA);
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

function key = localPDSCHCoordinateTemplateKey(cfg,carrier,slot0,reservation,pdsch,selectedTDRA)
% Reuse requires the same effective TDRA and every occasion-owned resource
% reservation. Native slot numbers also alter reference sequences, but this
% table stores coordinates, not those sequence values.
[csirsScheduled,~] = sixgr.phy.refsig.csirsOccasion(cfg,slot0);
trsScheduled = sixgr.truth.isActiveTRSOccasion(cfg,slot0+1);
csiimScheduled = false;
if logical(sixgr.util.structGet(cfg,'phy.csiim.enabled',false))
    csiim = sixgr.phy.refsig.csiIMResource(carrier,cfg);
    csiimScheduled = logical(csiim.Scheduled);
end
connectedCORESET = false;
patterns = string(sixgr.util.structGet(cfg, ...
    'phy.pdsch.rateMatchingPattern',strings(0,1)));
if any(patterns == "connected_coreset")
    monitor = cfg.phy.pdcch.operatorControl.connected_monitoring;
    sixgr.phy.pdcch.ConnectedPDCCHConfiguration.validatePolicy(monitor);
    validateattributes(monitor.period_slots,{'numeric'},{'scalar','integer','positive'});
    validateattributes(monitor.offset_slots,{'numeric'}, ...
        {'scalar','integer','nonnegative','<',monitor.period_slots});
    validateattributes(monitor.duration_slots,{'numeric'}, ...
        {'scalar','integer','>=',1,'<=',monitor.period_slots});
    connectedCORESET = mod(slot0-double(monitor.offset_slots), ...
        double(monitor.period_slots)) < double(monitor.duration_slots);
end
reserved = double(sixgr.util.structGet(reservation, ...
    'ReservedCarrierRE0',zeros(0,1)));
if isempty(reserved)
    ssbDigest = "none";
else
    encoded = sprintf('%.0f,',reserved(:));
    ssbDigest = sixgr.util.sha256Hex(uint8(unicode2native(encoded,'UTF-8')));
end
% A legal baseline need not have a selected catalog-row identifier. MATLAB
% string(NaN) is <missing>, not a usable cache token. Keep that case explicit
% rather than inventing TDRA index zero (which may be a real authored row).
tdraKey = "baseline_configured_allocation";
if isfinite(selectedTDRA)
    tdraKey = "authored_index_"+string(selectedTDRA);
end
key = char("ssb="+ssbDigest+"|csirs="+string(double(csirsScheduled))+ ...
    "|trs="+string(double(trsScheduled))+ ...
    "|csiim="+string(double(csiimScheduled))+ ...
    "|coreset="+string(double(connectedCORESET))+ ...
    "|symbols="+string(mat2str(double(pdsch.SymbolAllocation)))+ ...
    "|mapping="+string(pdsch.MappingType)+"|tdra="+tdraKey);
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
        string(row.transform_precoded), ...
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

function out = localCSIIM(cfg,carrier,totalSlots,frame,compactPeriodicOutput)
% Muted measurement resources have no transmit antenna port or payload.
rows=repmat(localEmptyRow(),0,1); count=0;
cache=containers.Map('KeyType','char','ValueType','any'); keyOrder=cell(0,1);
for slot0=0:totalSlots-1
    cfgSlot=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,slot0+1);
    c=localCarrierAtSlot(carrier,slot0);
    plan=sixgr.phy.refsig.csiIMResource(c,cfgSlot);
    if ~plan.Scheduled, continue; end
    assert(all(arrayfun(@(s)frame.IsDLAllocation(slot0,[s 1]), ...
        unique(plan.Symbols0Based))),'sixgr:truth:CSIIMNotDLAvailable', ...
        'Configured CSI-IM REs must occupy DL symbols, not guard or UL symbols.');
    coords=[plan.Subcarriers0Based plan.Symbols0Based zeros(plan.NumRE,1)];
    slotRows=localRows(coords,slot0,"CSI_IM","MUTED",double(c.NCellID),NaN, ...
        "RRC_CSI_IM_resource_configuration","sixgr.phy.refsig.csiIMResource", ...
        "csi_im_slot_"+string(slot0));
    for j=1:numel(slotRows)
        slotRows(j).port_index=NaN;
        slotRows(j).ue_id=NaN;
        slotRows(j).csi_resource_index=plan.ResourceID;
    end
    if compactPeriodicOutput
        [cache,keyOrder]=localAccumulatePeriodicRows(cache,keyOrder,slotRows,slot0,"csi_im");
    else
        rows=[rows;slotRows]; %#ok<AGROW>
    end
    count=count+plan.NumRE;
end
assert(count>0,'sixgr:truth:NoCSIIMOccasion','No CSI-IM resource falls within the run window.');
if compactPeriodicOutput, rows=localEmitPeriodicRows(cache,keyOrder,"CSI_IM"); end
out=localPayload(rows,count,"Serving-cell-muted CSI-IM resources; no transmitted port or payload");
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
% The first active occasion is a waveform-construction convenience, not
% the entire configured calendar. Enumerate the canonical joint PRACH/TDD
% period, preserving each native time/frequency occasion and its clock.
timing=frame.PRACHTiming;
required=["AbsoluteSlot","PRACHSlot","ActivePRACHSlot","TimeIndex", ...
    "FrequencyIndex","StartSymbol","DurationSymbols"];
assert(isfield(timing,'Occasions') && istable(timing.Occasions) && ...
    ~isempty(timing.Occasions) && all(ismember(required, ...
    string(timing.Occasions.Properties.VariableNames))), ...
    'sixgr:truth:MissingPlannedPRACHCalendar', ...
    'Planned PRACH requires the resolved native occasion table, not its first occurrence.');
period=double(timing.PeriodCarrierSlots);
nativePeriod=double(timing.PeriodPRACHSlots);
validateattributes(period,{'numeric'},{'scalar','integer','positive','finite'});
validateattributes(nativePeriod,{'numeric'},{'scalar','integer','positive','finite'});
rows=repmat(localEmptyRow(),0,1);count=0;
for repetition=0:ceil(totalSlots/period)-1
    for ordinal=1:height(timing.Occasions)
        occasion=timing.Occasions(ordinal,:);
        slot0=double(occasion.AbsoluteSlot)+repetition*period;
        if slot0>=totalSlots,continue;end
        assert(frame.IsULAllocation(slot0, ...
            [double(occasion.StartSymbol),double(occasion.DurationSymbols)]), ...
            'sixgr:truth:PlannedPRACHNotULAvailable', ...
            'A canonical PRACH occasion must remain UL available on the carrier clock.');
        c=localCarrierAtSlot(carrier,slot0);
        prach=strict.ToolboxPRACH;
        prach.NPRACHSlot=double(occasion.PRACHSlot)+repetition*nativePeriod;
        prach.ActivePRACHSlot=double(occasion.ActivePRACHSlot);
        prach.TimeIndex=double(occasion.TimeIndex);
        prach.FrequencyIndex=double(occasion.FrequencyIndex);
        m=sixgr.phy.frame.ChannelAllocationMaterializer.materializePRACH( ...
            c,prach,"AbsoluteSlot",slot0);
        part=localResultRows(m,slot0,"PRACH",1,NaN, ...
            "decoded_SIB1_RACH_ConfigCommon","PRACHConfig+nrPRACHIndices");
        identity="prach_slot_"+string(slot0)+"_native_"+string(prach.NPRACHSlot)+ ...
            "_active_"+string(prach.ActivePRACHSlot)+"_time_"+string(prach.TimeIndex)+ ...
            "_frequency_"+string(prach.FrequencyIndex);
        for row=1:numel(part),part(row).allocation_id=identity;end
        rows=[rows;part]; %#ok<AGROW>
        count=count+size(m.ActualCoordinates0Based,1);
    end
end
if count==0,error("sixgr:truth:NoPRACHOccasion","No legal PRACH occasion resolved.");end
out=localPayload(rows,count,"All PRACH time/frequency occasions in the configured run window; planning, not executed transmissions.");
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
    if name=="PTRS" && isfield(result,'TransformPrecoding') && result.TransformPrecoding
        % DFT PT-RS occupies the transformed PUSCH region already counted
        % by Data, not additional isolated frequency-domain pilot cells.
        continue;
    end
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
if isfield(result,'TransformPrecoding')
    for i=1:numel(rows), rows(i).transform_precoded=result.TransformPrecoding; end
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
    "grid_domain","carrier_cp_ofdm", "transform_precoded",false, ...
    "grid_subcarrier_spacing_hz",NaN, ...
    "grid_subcarrier_count",NaN,"grid_symbol_count",NaN, ...
    "cp_start_sample",NaN,"useful_start_sample",NaN,"useful_end_sample_exclusive",NaN, ...
    "observation_sample_rate_hz",NaN,"frequency_first_hz",NaN,"frequency_last_hz",NaN, ...
    "ssb_index0",NaN);
end

function c=localEmptyCheck()
c=struct("feature","","direction","","enabled",false,"resolved",false, ...
    "exact_re_count",0,"authority","","resolver","","status","", ...
    "error_id","","detail","");
end
