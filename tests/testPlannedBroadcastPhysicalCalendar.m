function ok=testPlannedBroadcastPhysicalCalendar()
% Configuration/native-RE calendar regression, not a waveform or BLER trial.
setup6GRSimToolkit('Verbose',false);
cfg=localConfig('simulator/configs/scenarios/lls_tdd_n40_20mhz_64txru_4rx_cdlc100_impaired.yaml');
cfg.run.totalSlots=100;
if isfield(cfg.run,'executionHorizon'),cfg.run=rmfield(cfg.run,'executionHorizon');end
original=cfg;
channels=["SSB_PBCH","TYPE0_PDCCH","SIB1_PDSCH"];
[rows,checks]=sixgr.truth.buildPlannedREAllocation(cfg,'TargetChannels',channels);
sixgr.truth.assertAllocationPreflight(checks);
assert(isequaln(cfg,original),'Planning must not mutate the installed configuration.');
carrier=sixgr.phy.grid.makeCarrier(cfg);
frame=sixgr.phy.FrameStructureEngine(cfg,'FrameCoreOnly',true);
assert(carrier.SubcarrierSpacing==30 && carrier.NSizeGrid==51);
ssb=rows(rows.channel=="SSB_PBCH",:);
assert(min(ssb.subcarrier_start)==181 && ...
    max(ssb.subcarrier_start+ssb.subcarrier_count-1)==420, ...
    'sixgr:test:PlannedSSBFrequencyUnits','n40 SSB must occupy carrier bins 181..420, not 362..601.');
assert(isequal(unique(ssb.absolute_slot).',[0 1 40 41 80 81]));
localSSBSupport(cfg,carrier,ssb);

si=rows(rows.channel=="SIB1_PDSCH",:);
assert(isequal(unique(si.absolute_slot).',[10:13 50:53 90:93]), ...
    'sixgr:test:PlannedSIB1FirstPeriodOnly','Every configured SI repetition must be planned.');
localSIB1Support(cfg,carrier,si,100);
control=rows(rows.channel=="TYPE0_PDCCH",:);
assert(~any(ismember(control.absolute_slot,[14 54 94])) && any(control.absolute_slot>=90), ...
    'sixgr:test:PlannedType0Duplex','Full-UL monitoring alternatives must not become planned DL resources.');
for index=1:height(control)
    assert(frame.IsDLAllocation(control.absolute_slot(index),[control.symbol_index(index) 1]));
end
assert(all(control.authority=="configured_MIB_bits_preflight_not_received") && ...
    ~any(contains(checks.authority(ismember(checks.feature,["TYPE0_PDCCH","SIB1_PDSCH"])),"decoded")), ...
    'Configured MIB authority is not a received MIB.');
assert(all(rows.evidence_scope=="planned_config_not_runtime_observation"));

% Explicit execution horizon may clip a repetition but never wrap its offset.
short=cfg;short.run.executionHorizon=struct('FinishAfterSlot',52);
[shortRows,shortChecks]=sixgr.truth.buildPlannedREAllocation(short,'TargetChannels',"SIB1_PDSCH");
sixgr.truth.assertAllocationPreflight(shortChecks);
assert(isequal(unique(shortRows.absolute_slot).',[10:13 50 51]));
before=cfg;before.run.totalSlots=10;
[beforeRows,beforeChecks]=sixgr.truth.buildPlannedREAllocation(before,'TargetChannels',"SIB1_PDSCH");
% There is no configured SI inside this window. No replacement slot/row may
% be invented, whether the preflight reports unavailable or an empty plan.
assert(isempty(beforeRows) && ~any(beforeChecks.status=="FAIL" & ...
    beforeChecks.feature~="SIB1_PDSCH"));

% At 15 kHz the reference units coincide; retain correct existing geometry.
fifteen=localConfig('simulator/configs/scenarios/lls_tdd_5mhz_two_ue_rank2_al8_shared_awgn_20db.yaml');
fifteen.run.totalSlots=2;
[fifteenRows,fifteenChecks]=sixgr.truth.buildPlannedREAllocation(fifteen,'TargetChannels',"SSB_PBCH");
sixgr.truth.assertAllocationPreflight(fifteenChecks);
fifteenCarrier=sixgr.phy.grid.makeCarrier(fifteen);
assert(fifteenCarrier.SubcarrierSpacing==15);
localSSBSupport(fifteen,fifteenCarrier,fifteenRows);
assert(min(fifteenRows.subcarrier_start)==12*double(fifteen.phy.ssb.nCRBSSB)+double(fifteen.phy.ssb.kSSB));

% A native 30-kHz SSB on a 15-kHz carrier must keep the native-domain path;
% it cannot be silently compressed to 240 carrier subcarriers.
mixed=localConfig('simulator/configs/validation/lls_n40_ssb30_common15_regression.yaml');
mixed.run.totalSlots=2;
[mixedRows,mixedChecks]=sixgr.truth.buildPlannedREAllocation(mixed,'TargetChannels',"SSB_PBCH");
sixgr.truth.assertAllocationPreflight(mixedChecks);
assert(~isempty(mixedRows) && all(mixedRows.grid_domain=="ssb_native_cp_ofdm") && ...
    all(mixedRows.grid_subcarrier_spacing_hz==30000) && all(mixedRows.grid_subcarrier_count==240));

bad=cfg;bad.phy.ssb.NCRBSSB=10000;bad.phy.ssb.nCRBSSB=10000;
rejected=false;
try
    [badRows,badChecks]=sixgr.truth.buildPlannedREAllocation(bad,'TargetChannels',"SSB_PBCH");
    rejected=isempty(badRows) && any(badChecks.error_id=="sixgr:phy:frame:SSBOutsideCarrierGrid");
catch cause
    assert(strcmp(cause.identifier,'sixgr:phy:frame:SSBOutsideCarrierGrid'));
    rejected=true;
end
assert(rejected,'Out-of-carrier SSB coordinates must not be clipped or fabricated.');
fprintf('PLANNED_BROADCAST_PHYSICAL_CALENDAR_PASS 30kHz_15kHz_native_mixed_TDD_periodic_SI_horizon\n');
ok=true;
end

function cfg=localConfig(path)
scenario=sixgr.lls6g.config.loadScenarioConfig(path);
cfg=sixgr.lls6g.buildInternalConfig(scenario,tempname);
end

function localSSBSupport(cfg,carrier,rows)
timing=sixgr.phy.frame.SSBTimingResolver.resolveFromConfig(cfg);
base=(double(timing.GridRelationship.SSBLowOffsetFromPointAHz)- ...
    double(timing.GridRelationship.CarrierLowOffsetFromPointAHz))/(1000*carrier.SubcarrierSpacing);
native={"PSS",nrPSSIndices();"SSS",nrSSSIndices(); ...
    "PBCH",nrPBCHIndices(carrier.NCellID);"PBCH_DMRS",nrPBCHDMRSIndices(carrier.NCellID)};
for slot=reshape(unique(rows.absolute_slot),1,[])
    [active,occasion]=sixgr.truth.isActiveSSBOccasion(cfg,slot+1);
    assert(active);
    c=carrier;c.NFrame=floor(slot/c.SlotsPerFrame);c.NSlot=mod(slot,c.SlotsPerFrame);
    reserved=sixgr.phy.frame.ssbPRBSymbolReservation(cfg,c,slot);
    for candidate=1:numel(occasion.ActiveSSBIndices0Based)
        id="ssb_candidate_"+string(occasion.ActiveSSBIndices0Based(candidate));
        for component=1:size(native,1)
            [k,l]=ind2sub([240 4],double(native{component,2}(:)));
            expected=sortrows([k-1+base,l-1+double(occasion.CandidateSSBSymbolsWithinSlot0Based(candidate)),zeros(numel(k),1)]);
            selected=rows(rows.absolute_slot==slot & rows.allocation_id==id & rows.component==native{component,1},:);
            actual=localExpand(selected);
            assert(isequal(actual,expected),'Exact original native SSB RE coordinates must be preserved.');
            assert(all(ismember(actual(:,1)+12*carrier.NSizeGrid*actual(:,2),reserved.ReservedCarrierRE0)));
        end
    end
end
end

function localSIB1Support(cfg,carrier,rows,horizon)
indices=sixgr.phy.broadcast.resolveSIB1TransmitSSBIndices(cfg);
for index=indices
    child=cfg;child.phy.sib1.transmissionScope="selected_ssb_occasion";child.phy.ssb.runtimeSSBIndex=index;
    plan=sixgr.phy.frame.CommonDLResourcePlan(child);
    for slot=plan.SIB1Slot0:plan.BroadcastPeriodSlots:horizon-1
        c=carrier;c.NFrame=floor(slot/c.SlotsPerFrame);c.NSlot=mod(slot,c.SlotsPerFrame);
        exact=sixgr.phy.frame.ChannelAllocationMaterializer.materializePDSCH(c,plan.SIB1PDSCH,'AbsoluteSlot',slot);
        selected=rows(rows.absolute_slot==slot & endsWith(rows.allocation_id,"_ssb_"+index),:);
        assert(isequal(localExpand(selected),sortrows(double(exact.ActualCoordinates0Based))), ...
            'Each planned SI repetition must retain native materialized RE coordinates.');
    end
end
end

function coords=localExpand(rows)
coords=zeros(sum(rows.re_count),3);next=1;
for index=1:height(rows)
    n=rows.subcarrier_count(index);target=next:next+n-1;
    coords(target,:)=[rows.subcarrier_start(index)+(0:n-1).', ...
        repmat(rows.symbol_index(index),n,1),repmat(rows.port_index(index),n,1)];
    next=next+n;
end
coords=sortrows(coords);
end
