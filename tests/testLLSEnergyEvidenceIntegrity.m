function ok = testLLSEnergyEvidenceIntegrity()
%TESTLLSENERGYEVIDENCEINTEGRITY Energy evidence is explicit and fail closed.

setup6GRSimToolkit("Verbose", false);

cfg = localExplicitConfig();
resolved = sixgr.truth.resolveLLSEnergyModelConfig(cfg);
assert(resolved.Available && height(resolved.TermTable) == 13);
assert(all(string(resolved.TermTable.Availability) == "AVAILABLE"));
missingFraction=cfg;
missingFraction.lls6g.energy_efficiency=rmfield(missingFraction.lls6g.energy_efficiency, ...
    'bs_rf_chain_idle_power_fraction');
missingResolved=sixgr.truth.resolveLLSEnergyModelConfig(missingFraction);
assert(~missingResolved.Available && ...
    any(missingResolved.MissingTerms=="BSRFChainIdlePowerFraction"), ...
    'A class default must not become an explicitly configured LLS model operand.');
% H4-207: RF units are not antenna elements, logical ports or data layers.
% This fixture deliberately has 64 gNB elements but four declared RF units.
% A valid hybrid inventory must remain accepted, while explicit contradictory
% endpoint-chain declarations must not become an available energy model.
for endpoint = ["bs","ue"]
    inconsistent = cfg;
    inconsistent.antenna.(endpoint).numTxRFChains = 8;
    inconsistent.antenna.(endpoint).numRxRFChains = 8;
    inconsistent.antenna.(endpoint).numRFChains = 8;
    rejected = sixgr.truth.resolveLLSEnergyModelConfig(inconsistent);
    assert(~rejected.Available, 'test:EnergyRFInventoryMismatchAccepted', ...
        'Energy accounting accepted RF-chain counts inconsistent with %s inventory.', endpoint);
    corrected=sixgr.truth.resolveLLSEnergyModelConfig(inconsistent, ...
        RFInventoryPolicy="bind_declared_inventory");
    term="BSRFChainCount";
    if endpoint=="ue", term="UERFChainCount"; end
    row=corrected.TermTable(corrected.TermTable.Term==term,:);
    assert(corrected.Available && row.Value==8 && ...
        row.ConfiguredValue~=row.Value && contains(row.Notes,"Explicit_report_model_binding"));
    assert(inconsistent.lls6g.energy_efficiency.(endpoint+"_rf_chain_count")~=8, ...
        'A report-model correction must not mutate the frozen input configuration.');
    configured=inconsistent;
    configured.lls6g.energy_efficiency.rf_inventory_source='declared_endpoint_inventory';
    bound=sixgr.truth.resolveLLSEnergyModelConfig(configured);
    binding=bound.TermTable(bound.TermTable.Term==term,:);
    assert(bound.Available && binding.Value==8 && ...
        binding.RFInventoryPolicy=="yaml_declared_endpoint_inventory", ...
        'The configured inventory source must work without a reporting override.');
    noPool=configured;
    noPool.antenna.(endpoint)=rmfield(noPool.antenna.(endpoint),'numRFChains');
    absent=sixgr.truth.resolveLLSEnergyModelConfig(noPool);
    assert(~absent.Available && any(absent.MissingTerms==term), ...
        'Do not infer a common physical RF pool from directional counts.');
    conflict=configured;
    conflict.scenario.(endpoint).numRFChains=9;
    contradictory=sixgr.truth.resolveLLSEnergyModelConfig(conflict);
    assert(~contradictory.Available && any(contradictory.MissingTerms==term), ...
        'Contradictory independent RF inventories cannot be corrected by choosing one.');
end

root = tempname;
airFolder = fullfile(root, "air_interface");
mkdir(airFolder);
cleanupObj = onCleanup(@() localCleanup(root)); %#ok<NASGU>

zeroTrials = struct("DL", localTrial("FAIL", 0), "UL", table());
zero = sixgr.truth.exportLLSEnergyDiagnostics(cfg, airFolder, zeroTrials);
assert(zero.Available);
localAssertMetricUnavailable(zero.SummaryTable, "ue_energy_per_successful_bit");
localAssertMetricUnavailable(zero.SummaryTable, "gnb_energy_per_successful_bit");
localAssertMetricUnavailable(zero.SummaryTable, "race_to_sleep_gains");
localAssertMetricUnavailable(zero.SummaryTable, "bandwidth_adaptation_energy_effect");

passTrials = struct("DL", localTrial("PASS", 800), "UL", table());
passTrials.DL.CSI_RSRP_dB=-10.26;
passTrials.DL.ServingRSRP_dBm=-90; % Per-RS-RE, not total receiver power.
for invalidCount=[-1 0.5 25]
    bad=passTrials; bad.DL.PRBs=invalidCount;
    localRejectResource(@()sixgr.truth.exportLLSEnergyDiagnostics(cfg,airFolder,bad), ...
        'sixgr:truth:EnergyPRBCountOutOfGrid');
end
pass = sixgr.truth.exportLLSEnergyDiagnostics(cfg, airFolder, passTrials);
assert(all(isnan(pass.TimelineTable.RxPowerEst_dBm)), ...
    'Neither normalized CSI power nor per-RE RSRP may become total RX dBm.');
partialCfg=cfg; partialCfg.run.totalSlots=100; partialCfg.run.numFrames=100;
prefix=passTrials; prefix.CoupledRuntime=struct('CompletedCanonicalSlots',49);
partialTime=sixgr.truth.exportLLSEnergyDiagnostics(partialCfg,airFolder,prefix);
localAssertMetricValue(partialTime.SummaryTable,"measurement_window_duration",.049,1e-12);
ueJ=sum(partialTime.EndpointTimelineTable.Energy_J(partialTime.EndpointTimelineTable.Entity=="UE"));
localAssertMetricValue(partialTime.SummaryTable,"ue_energy_per_slot_frame_burst",ueJ/4.9,1e-12);
assert(~isfield(partialCfg.run,'measurementWindow_s') && ...
    partialTime.MeasurementWindowSource=="committed_runtime_completed_canonical_slots");
for key = ["ue_energy_per_successful_bit","gnb_energy_per_successful_bit"]
    row = pass.SummaryTable(string(pass.SummaryTable.MetricKey) == key, :);
    assert(height(row) == 1 && isfinite(row.Value) && row.Value > 0);
    assert(string(row.Availability) == "AVAILABLE");
    assert(string(row.EvidenceType) == "runtime_state_conditioned_engineering_model");
end
% Qualification PASS/FAIL is not the decoder CRC. Energy efficiency uses
% the same first-success payload credit as the connected runtime.
crcFailed=localTrial("PASS",800); crcFailed.CRCPass=0;
a=sixgr.truth.exportLLSEnergyDiagnostics(cfg,airFolder,struct('DL',crcFailed));
localAssertMetricValue(a.SummaryTable,"first_delivered_bits",0,0);
crcPassed=localTrial("FAIL",800); crcPassed.CRCPass=1;
a=sixgr.truth.exportLLSEnergyDiagnostics(cfg,airFolder,struct('DL',crcPassed));
localAssertMetricValue(a.SummaryTable,"first_delivered_bits",800,0);
sameLabel=[localTrial("PASS",800);localTrial("PASS",800)];
sameLabel.UEID=[1;2];
a=sixgr.truth.exportLLSEnergyDiagnostics(cfg,airFolder,struct('DL',sameLabel));
localAssertMetricValue(a.SummaryTable,"first_delivered_bits",1600,0);
sameLabel.UEID(:)=1; sameLabel.SweepPointIndex=[1;2];
a=sixgr.truth.exportLLSEnergyDiagnostics(cfg,airFolder,struct('DL',sameLabel));
localAssertMetricValue(a.SummaryTable,"first_delivered_bits",1600,0);
% Slice of a repeated success must retain the prior runtime zero credit.
credited=[localTrial("PASS",800);localTrial("PASS",800)];
credited.Direction(:)="DL"; credited.Slot=[1;2];
credited=sixgr.kpi.creditTransportGoodput(credited);
a=sixgr.truth.exportLLSEnergyDiagnostics(cfg,airFolder,struct('DL',credited(2,:)));
localAssertMetricValue(a.SummaryTable,"first_delivered_bits",0,0);
unknown=removevars(localTrial("PASS",800),'CRCPass');
a=sixgr.truth.exportLLSEnergyDiagnostics(cfg,airFolder,struct('DL',unknown));
localAssertMetricUnavailable(a.SummaryTable,"first_delivered_bits");
unknown=removevars(localTrial("PASS",800),'TransportBlockId');
unknown.GrantContextId="attempt_not_a_logical_TB";
a=sixgr.truth.exportLLSEnergyDiagnostics(cfg,airFolder,struct('DL',unknown));
localAssertMetricUnavailable(a.SummaryTable,"first_delivered_bits");
assert(all(strlength(a.TimelineTable.TransportBlockId)==0), ...
    'Do not manufacture a TB identity from a slot or grant context.');
assert(~any(contains(lower(string(pass.SummaryTable.EvidenceType)), ...
    ["proxy","fallback","synthetic","placeholder"])));

% Fixed-link campaign points reuse frame/slot coordinates. Their campaign
% hierarchy must keep successful TBs distinct and their active-time
% denominator must not yield an impossible duty cycle above one.
fixedT = [localTrial("PASS", 800); localTrial("PASS", 800); localTrial("FAIL", 0)];
fixedT.UEID(:) = NaN;
fixedT.FixedLinkPointIndex = (1:3).';
fixedT.FixedLinkDropIndex = ones(3, 1);
fixedT.FixedLinkTrialIndex = ones(3, 1);
fixedT.FixedLinkSeedIndex = ones(3, 1);
fixedT.FixedLinkSeedValue = 104729 * ones(3, 1);
fixedT.FixedLinkCampaign = true(3,1);
fixedT.FixedLinkCampaignKind = repmat("fixed_link_monte_carlo",3,1);
fixed = sixgr.truth.exportLLSEnergyDiagnostics(cfg, airFolder, ...
    struct("DL", fixedT, "UL", table()));
fixedIds = string(fixed.TimelineTable.TransportBlockId);
assert(~any(ismissing(fixedIds)) && all(strlength(fixedIds) > 0), ...
    "Fixed-link energy rows must retain a nonmissing transport-block identity when UE/RNTI are unavailable.");
assert(numel(unique(fixedIds(string(fixed.TimelineTable.Entity) == "gNB"))) == 3, ...
    "Each independently executed fixed-link point/trial must have a distinct transmitter identity.");
localAssertMetricValue(fixed.SummaryTable, "first_delivery_count", 2, 0);
localAssertMetricValue(fixed.SummaryTable, "first_delivered_bits", 1600, 0);
localAssertMetricValue(fixed.SummaryTable, "measurement_window_duration", 0.003, 1e-12);
symbolFixed=fixedT;
grid=complex(zeros(12*24,14)); grid(1:12,[3 10])=1;
mapped=sixgr.truth.executedResourceIntervals(grid,0);
for field=string(fieldnames(mapped)).'
    symbolFixed.(field)=repmat(mapped.(field),height(symbolFixed),1);
end
symbolEnergy=sixgr.truth.exportLLSEnergyDiagnostics(cfg,airFolder,struct('DL',symbolFixed));
observed=symbolEnergy.TimelineTable(symbolEnergy.TimelineTable.Entity=="gNB",:);
assert(height(observed)==6);
localAssertMetricValue(symbolEnergy.SummaryTable,"measurement_window_duration",sum(observed.Duration_s),1e-12);
localAssertMetricValue(symbolEnergy.SummaryTable,"first_delivered_bits",1600,0);
% Independent fixed-link executions are three exposures, even though their
% nominal slot coordinates coincide. Two successful deliveries do not erase
% the energy of the third, failed transmission.
for key = ["gnb_energy_per_successful_bit","ue_energy_per_successful_bit"]
    reference = pass.SummaryTable(pass.SummaryTable.MetricKey == key, :);
    localAssertMetricValue(fixed.SummaryTable, key, 1.5*reference.Value, 1e-12);
end
activeRows = fixed.SummaryTable(string(fixed.SummaryTable.MetricKey) == ...
    "gnb_active_sleep_duty_cycle" & string(fixed.SummaryTable.Statistic) == "active_ratio", :);
assert(height(activeRows) == 1 && activeRows.Value >= 0 && activeRows.Value <= 1, ...
    "Fixed-link gNB duty cycle must be in [0,1].");

% Two UEs and a control/data observation in the same connected-runtime slot
% are simultaneous gNB activity, not four sequential active intervals.
multiDL = [localTrial("PASS", 800); localTrial("PASS", 800)];
multiDL.UEID = [1; 2];
multiDL.TransportBlockId = ["dl_tb_ue1"; "dl_tb_ue2"];
multiPDCCH = multiDL;
multiPDCCH.TransportBlockId = ["dci_ue1"; "dci_ue2"];
multiPDCCH.PDCCHAllocatedPRBSetJSON=repmat(string(jsonencode(0:7)),2,1);
connected = sixgr.truth.exportLLSEnergyDiagnostics(cfg, airFolder, ...
    struct("DL", multiDL, "UL", table(), "PDCCH", multiPDCCH));
% H4-208: the same endpoint state may be described by several receiver
% observations. These fixtures use the same whole-slot interval, PRB load,
% configured PA power and UE identities; PDCCH introduces no additional
% modeled circuit-power term. Adding its attribution must not charge the
% gNB site/chain power or the already-active UE receiver a second time.
% These are explicit accounting fixtures, not physical energy measurements.
dataOnly = sixgr.truth.exportLLSEnergyDiagnostics(cfg, airFolder, ...
    struct("DL", multiDL, "UL", table()));
for key = ["gnb_energy_per_successful_bit","ue_energy_per_successful_bit"]
    reference = dataOnly.SummaryTable(dataOnly.SummaryTable.MetricKey == key, :);
    localAssertMetricValue(connected.SummaryTable, key, reference.Value, 1e-12);
end
localAssertMetricValue(connected.SummaryTable, ...
    "gnb_active_sleep_duty_cycle", 1, 1e-12, "active_ratio");
activeTime = connected.SummaryTable(string(connected.SummaryTable.MetricKey) == ...
    "rf_chain_active_time", :);
assert(height(activeTime) == 1 && abs(double(activeTime.Value) - 0.001) < 1e-12, ...
    "Simultaneous per-UE/control gNB rows must reduce to one interval of active time.");
localAssertMetricValue(connected.SummaryTable,"first_delivered_bits",1600,0);
assert(all(connected.TimelineTable.SuccessfulBits( ...
    connected.TimelineTable.Domain=="PDCCH_monitoring")==0), ...
    'Control bits are not delivered transport-block payload.');
% Equal gNB power from two equal-size channel allocations does not prove
% equal PRB occupancy. Without the actual sets a union cannot be evaluated.
unlocated=removevars(multiDL,'EnergyAllocatedPRBSetJSON');
noUnion=sixgr.truth.exportLLSEnergyDiagnostics(cfg,airFolder,struct('DL',unlocated));
assert(~noUnion.EndpointTotalsAvailable && ...
    any(noUnion.EndpointTimelineTable.Status=="equal_power_does_not_establish_joint_endpoint_state"));
% One active gNB serving two UEs and two independently active gNBs are not
% the same endpoint inventory. Deduplicating intervals must retain both
% sites while keeping each UE's receiver energy unchanged.
distinctCells = multiDL;
distinctCells.CellID = [1;2];
distinctCells.BaseStationID = [1;2];
twoSites = sixgr.truth.exportLLSEnergyDiagnostics(cfg, airFolder, ...
    struct("DL", distinctCells, "UL", table()));
reference = dataOnly.SummaryTable( ...
    dataOnly.SummaryTable.MetricKey=="gnb_energy_per_successful_bit",:);
localAssertMetricValue(twoSites.SummaryTable, ...
    "gnb_energy_per_successful_bit",2*reference.Value,1e-12);
reference = dataOnly.SummaryTable( ...
    dataOnly.SummaryTable.MetricKey=="ue_energy_per_successful_bit",:);
localAssertMetricValue(twoSites.SummaryTable, ...
    "ue_energy_per_successful_bit",reference.Value,1e-12);
controlOnly=sixgr.truth.exportLLSEnergyDiagnostics(cfg,airFolder, ...
    struct('PDCCH',multiPDCCH));
localAssertMetricValue(controlOnly.SummaryTable,"first_delivered_bits",0,0);
localAssertMetricUnavailable(controlOnly.SummaryTable,"gnb_energy_per_successful_bit");

% Missing observations are not executed sleep-state transitions. A single
% trace also cannot establish a clustering gain against an unexecuted
% baseline, whether the policy is enabled or disabled.
sparseCfg = cfg;
sparseCfg.run.totalSlots = 4;
sparse = sixgr.truth.exportLLSEnergyDiagnostics(sparseCfg, airFolder, ...
    struct("DL", multiDL, "UL", table()));
sleepRow = sparse.SummaryTable( ...
    sparse.SummaryTable.MetricKey=="gnb_active_sleep_duty_cycle" & ...
    sparse.SummaryTable.Statistic=="sleep_ratio",:);
assert(height(sleepRow)==1 && isnan(sleepRow.Value) && ...
    sleepRow.Availability=="NOT_EVALUATED", ...
    'Unobserved slots must not be reported as measured sleep occupancy.');
for enabled = [false true]
    clusteredCfg = cfg;
    clusteredCfg.lls6g.energy_efficiency.common_signal_clustering_enabled = enabled;
    clustered = sixgr.truth.exportLLSEnergyDiagnostics(clusteredCfg, airFolder, ...
        struct("DL", multiDL, "PBCH", multiPDCCH));
    localAssertMetricUnavailable(clustered.SummaryTable, ...
        "prach_common_channel_clustering_energy_effect");
end

% Do not implement the overlap repair by globally discarding control rows:
% the same active endpoint state in a different slot adds a second interval.
laterPDCCH = multiPDCCH;
laterPDCCH.Slot(:) = 2;
sequential = sixgr.truth.exportLLSEnergyDiagnostics(cfg, airFolder, ...
    struct("DL", multiDL, "UL", table(), "PDCCH", laterPDCCH));
for key = ["gnb_energy_per_successful_bit","ue_energy_per_successful_bit"]
    reference = dataOnly.SummaryTable(dataOnly.SummaryTable.MetricKey == key, :);
    localAssertMetricValue(sequential.SummaryTable, key, 2*reference.Value, 1e-12);
end
localAssertMetricValue(sequential.SummaryTable,"first_delivered_bits",1600,0);

% Sparse channel identity columns must not split one explicitly identified
% sweep point into two physical clocks. This is a local model join, not a
% rewrite of the original receiver tables.
scopedDL=multiDL; scopedDL.ExecutionID=repmat("executed_fixture",height(scopedDL),1);
scopedDL.SweepPointIndex=ones(height(scopedDL),1);
scopedControl=multiPDCCH;
scopedControl.ExecutionID=repmat("executed_fixture",height(scopedControl),1);
scoped=sixgr.truth.exportLLSEnergyDiagnostics(cfg,airFolder, ...
    struct('DL',scopedDL,'PDCCH',scopedControl));
localAssertMetricValue(scoped.SummaryTable,"gnb_energy_per_successful_bit", ...
    connected.SummaryTable.Value(connected.SummaryTable.MetricKey=="gnb_energy_per_successful_bit"),1e-12);
assert(all(scoped.TimelineTable.PopulationBindingSource( ...
    scoped.TimelineTable.Domain=="PDCCH_monitoring")~="retained_row_identity"));

% A TDD special slot has disjoint control/data/UL resources, not simultaneous
% whole-slot TX and RX power. Use exact normal-CP symbol boundaries.
mixedCfg=cfg; mixedCfg.phy.carrier.SubcarrierSpacing=30;
data=localTrial("PASS",800); data.Slot=4;
data.SymbolStart=2; data.NumSymbols=8;
control=localTrial("PASS",800); control.Slot=4;
control.PDCCHCORESETStartSymbol=0; control.PDCCHCORESETDuration=2;
control.PDCCHAllocatedPRBSetJSON=string(jsonencode(0:3));
uplink=localTrial("PASS",0); uplink.Slot=4; uplink.Direction="UL";
uplink.PUCCHSymbolStart=12; uplink.PUCCHNumSymbols=2; uplink.PUCCHPRBCount=1;
uplink.EnergyAllocatedPRBSetJSON="0";
mixed=sixgr.truth.exportLLSEnergyDiagnostics(mixedCfg,airFolder, ...
    struct('DL',data,'PDCCH',control,'PUCCH',uplink));
assert(mixed.EndpointTotalsAvailable && all(mixed.EndpointTimelineTable.Availability=="AVAILABLE"));
assert(all(mixed.TimelineTable.PRBCount(mixed.TimelineTable.Domain=="PDCCH_monitoring")==4), ...
    'PDCCH load must not use the associated data grant PRB count.');
spec=sixgr.phy.frame.AbsoluteTime.resolveNumerology(mixedCfg.phy.carrier);
start=sixgr.phy.frame.AbsoluteTime.fromAbsoluteSlotSymbol(3,2,spec);
stop=start.plusSymbols(8,spec);
dataRows=mixed.TimelineTable.Domain=="DL_data";
assert(all(abs(mixed.TimelineTable.TimestampSim_ms(dataRows)-start.milliseconds())<1e-12) && ...
    all(abs(mixed.TimelineTable.Duration_s(dataRows)-(stop.seconds()-start.seconds()))<1e-15));
% Old control rows contain the associated DATA allocation, not the actual
% PDCCH resource set. Never accept that unrelated count or label NaN power
% as an available endpoint model value.
legacyControl=removevars(control,'PDCCHAllocatedPRBSetJSON');
legacy=sixgr.truth.exportLLSEnergyDiagnostics(mixedCfg,airFolder, ...
    struct('PDCCH',legacyControl));
gnb=legacy.TimelineTable.Entity=="gNB";
assert(all(isnan(legacy.TimelineTable.Power_W(gnb))) && ...
    all(legacy.TimelineTable.Availability(gnb)=="NOT_EVALUATED") && ...
    contains(legacy.FailureReason,"missing_endpoint_power_model_inputs"));
% Missing occupancy remains unknown, but it is not a required operand of a
% strictly load-independent configured power equation. No PRBs are created.
for constantKind=["zero_chain_term","constant_chain_term"]
    constant=mixedCfg;
    if constantKind=="zero_chain_term"
        constant.lls6g.energy_efficiency.bs_per_rf_chain_power_w=0;
        expectedChain=0;
    else
        constant.lls6g.energy_efficiency.bs_rf_chain_idle_power_fraction=1;
        expectedChain=4*4;
    end
    independent=sixgr.truth.exportLLSEnergyDiagnostics(constant,airFolder, ...
        struct('PDCCH',legacyControl));
    B=independent.TimelineTable(independent.TimelineTable.Entity=="gNB",:);
    assert(all(isnan(B.PRBCount)) && all(isnan(B.ActiveBWFraction)) && ...
        all(abs(B.Power_W-(100+expectedChain+10^((46-30)/10)/0.4))<1e-12));
    assert(~independent.CompleteRunEnergyAvailable);
end

% Link trials use absolute Slot, not a within-frame slot. Adding Frame*10ms
% CSI-RS/TRS mapped occupancy is sparse in time and may overlap in PRBs.
% This is a declared accounting fixture, not a measured RF-power result.
g1=complex(zeros(24*12,14,2)); g1(1:60,5,1)=1;
g2=complex(zeros(24*12,14,2)); g2(37:96,5,2)=1;
csi=localTrial("PASS",0); csi.Slot=4;
trs=csi;
e1=sixgr.truth.executedResourceIntervals(g1,3);
e2=sixgr.truth.executedResourceIntervals(g2,3);
for field=string(fieldnames(e1)).'
    csi.(field)=e1.(field); trs.(field)=e2.(field);
end
rs=sixgr.truth.exportLLSEnergyDiagnostics(cfg,airFolder,struct('CSIRS',csi,'TRS',trs));
assert(rs.EndpointTotalsAvailable && height(rs.TimelineTable)==4 && ...
    all(ismember(["CSI_RS","TRS"],rs.TimelineTable.Domain)));
joint=rs.EndpointTimelineTable(rs.EndpointTimelineTable.Entity=="gNB",:);
assert(height(joint)==1 && joint.ActivePRBCount==8 && ...
    joint.Status=="joint_occupied_PRB_union_endpoint_engineering_model");
model=sixgr.rf.EnergyModelBS(cfg);
p=model.power('active',4,8/24,10^((46-30)/10));
assert(abs(joint.Power_W-p.totalW)<1e-12 && ...
    joint.Energy_J<sum(rs.TimelineTable.Energy_J(rs.TimelineTable.Entity=="gNB")));
% The allowed low PA efficiency previously passed configuration, was
% silently clamped by the model and then rejected by the joint integrator.
% Exercise the real exporter and independent equation, not the model twice.
low=cfg;
low.lls6g.energy_efficiency.bs_pa_efficiency=0.0005;
low.lls6g.energy_efficiency.bs_rf_chain_idle_power_fraction=0.37;
lowEnergy=sixgr.truth.exportLLSEnergyDiagnostics(low,airFolder,struct('CSIRS',csi,'TRS',trs));
lowJoint=lowEnergy.EndpointTimelineTable(lowEnergy.EndpointTimelineTable.Entity=="gNB",:);
expected=100+4*4*(0.37+(1-0.37)*8/24)+10^((46-30)/10)/0.0005;
assert(lowEnergy.EndpointTotalsAvailable && height(lowJoint)==1 && ...
    abs(lowJoint.Power_W-expected)<1e-10);
assert(all(lowEnergy.ModelTermsTable.ModelVersion=="lls_energy_accounting_v4"));
corrupt=rs.TimelineTable; corrupt.Power_W(corrupt.Entity=="gNB")=123;
localRejectResource(@()sixgr.truth.integrateLLSEndpointEnergy(corrupt,cfg), ...
    'sixgr:truth:EnergyModelOperandMismatch');
assert(all(rs.TimelineTable.Symbol==4) && all(rs.TimelineTable.Duration_s<.0001));
% Later TRS resources stay at their true absolute slot, not the trial's
% first slot or receiver-completion slot.
later=sixgr.truth.executedResourceIntervals(g2,4);
entries=[jsondecode(e2.ExecutedResourceIntervalsJSON);jsondecode(later.ExecutedResourceIntervalsJSON)];
trs.ExecutedResourceIntervalsJSON=string(jsonencode(entries));
expanded=sixgr.truth.expandExecutedResourceIntervals(trs,cfg);
assert(isequal(expanded.Slot,[4;5]) && all(expanded.SymbolStart==4));
rs=sixgr.truth.exportLLSEnergyDiagnostics(cfg,airFolder,struct('TRS',trs));
assert(height(rs.EndpointTimelineTable)==4 && rs.EndpointTotalsAvailable);
% Exact per-symbol control evidence must not widen to the legacy bounding
% box. Hopping changes the PRB union between the two symbols.
control=csi; control.PDCCHCORESETStartSymbol=0; control.PDCCHCORESETDuration=2;
control.PDCCHAllocatedPRBSetJSON=string(jsonencode(0:12));
entries=jsondecode(e1.ExecutedResourceIntervalsJSON);
entries(1).SymbolIndex0=0;
entries(2)=entries(1); entries(2).SymbolIndex0=1; entries(2).PRBSet0Based=5:9;
control.ExecutedResourceIntervalsJSON=string(jsonencode(entries));
exactControl=sixgr.truth.exportLLSEnergyDiagnostics(cfg,airFolder,struct('PDCCH',control));
assert(exactControl.EndpointTotalsAvailable && height(exactControl.TimelineTable)==4 && ...
    all(exactControl.TimelineTable.PRBCount==5) && ...
    all(exactControl.TimelineTable.Duration_s<.0001));
assert(isequal(exactControl.TimelineTable.Symbol,[0;0;1;1]));
assert(~exactControl.CompleteRunEnergyAvailable);
% Native PRACH CP/useful samples are not carrier symbols. The two separated
% intervals deliberately leave a guard gap, which must not acquire power.
native=localTrial("PASS",0); native.Direction="UL"; native.Slot=4;
defaults=sixgr.truth.prachNativeSampleIntervals();
for field=string(fieldnames(defaults)).', native.(field)=defaults.(field); end
samples=struct('StartSample',3000,'EndSampleExclusive',3200,'SampleRateHz',1e6, ...
    'NativeSymbolIndex0',0,'CarrierPRBIntersectionSet0Based',0:2);
samples(2)=samples(1); samples(2).StartSample=3300; samples(2).EndSampleExclusive=3500;
samples(2).NativeSymbolIndex0=1;
native.ExecutedSampleIntervalsJSON=string(jsonencode(samples));
native.ExecutedSampleIntervalSource="executed_native_PRACH_CP_useful_samples_not_RF_activity";
native.ResourceGridPRBCount=cfg.phy.carrier.NSizeGrid;
nativeEnergy=sixgr.truth.exportLLSEnergyDiagnostics(cfg,airFolder,struct('PRACH',native));
assert(nativeEnergy.EndpointTotalsAvailable && height(nativeEnergy.TimelineTable)==4 && ...
    all(isnan(nativeEnergy.TimelineTable.Symbol)) && all(nativeEnergy.TimelineTable.PRBCount==3));
assert(max(abs(nativeEnergy.TimelineTable.TimestampSim_ms-[3;3;3.3;3.3]))<1e-12 && ...
    all(abs(nativeEnergy.TimelineTable.Duration_s-.0002)<1e-15));
assert(isequal(nativeEnergy.TimelineTable.ExecutedStartSample,[3000;3000;3300;3300]) && ...
    all(nativeEnergy.TimelineTable.ExecutedSampleRateHz==1e6) && ...
    all(isfinite(nativeEnergy.TimelineTable.NativeSymbolIndex0)));
badNative=native; samples(2).StartSample=3100;
badNative.ExecutedSampleIntervalsJSON=string(jsonencode(samples));
localRejectResource(@()sixgr.truth.expandExecutedSampleIntervals(badNative,cfg), ...
    'sixgr:truth:SampleIntervalClock');
data=localTrial("PASS",800); data.Slot=4;
for field=string(fieldnames(e1)).', data.(field)=e1.(field); end
entries=[jsondecode(e1.ExecutedResourceIntervalsJSON);jsondecode(e1.ExecutedResourceIntervalsJSON)];
entries(2).SymbolIndex0=5;
data.ExecutedResourceIntervalsJSON=string(jsonencode(entries));
dataEnergy=sixgr.truth.exportLLSEnergyDiagnostics(cfg,airFolder,struct('DL',data));
assert(dataEnergy.EndpointTotalsAvailable && height(dataEnergy.TimelineTable)==4);
localAssertMetricValue(dataEnergy.SummaryTable,"first_delivered_bits",800,0);
localAssertMetricValue(dataEnergy.SummaryTable,"first_delivery_count",1,0);
% A represented interval can be valid while the full executed resource
% ledger contains an unaccounted common signal. Preserve the partial value
% only in diagnostics; it must not become a primary energy/bit result.
hash=string(repmat('a',1,64)); source=string(repmat('b',1,64));
covered=localTrial("PASS",800); covered.ConfigHash=hash;
covered.BaseStationID=1; covered.GrantContextId="data_identity_fixture";
ledger=table(["DL";"DL"],["PDSCH";"PDCCH"],[1;1],[1;NaN], ...
    ["data_identity_fixture";"unbound_common_control_fixture"],[0;2],[2;0], ...
    [24;24],[14;14],["[0,1,2,3,4,5,6,7]";"[0,1]"], ...
    repmat(string(jsonencode(struct('ConfigHash',hash))),2,1),repmat(source,2,1), ...
    repmat("retained_executed_TX_RE_occupancy_not_RF_activity",2,1), ...
    'VariableNames',{'Direction','Channel','CellID','UEID','AllocationID', ...
    'AbsoluteSlotIndex0','SymbolIndex0','ResourceGridPRBCount','ResourceSymbolsPerSlot', ...
    'PRBSet0BasedJSON','PopulationScopeJSON','SourceSHA256','Source'});
evidence=struct('Intervals',ledger,'ConfigHash',hash,'SourceSHA256',source);
partial=sixgr.truth.exportLLSEnergyDiagnostics(cfg,airFolder,struct('DL',covered),evidence);
assert(partial.EndpointTotalsAvailable && ~partial.Available && ~partial.ResourceCoverageComplete && ...
    height(partial.UnboundResourceTable)==1 && isfile(partial.RepresentedIntervalSummaryCSV));
localAssertMetricUnavailable(partial.SummaryTable,"gnb_energy_per_successful_bit");
localAssertMetricUnavailable(partial.SummaryTable,"throughput_per_watt");
localAssertMetricValue(partial.SummaryTable,"first_delivered_bits",800,0);
assert(isfinite(partial.RepresentedIntervalSummaryTable.Value( ...
    partial.RepresentedIntervalSummaryTable.MetricKey=="gnb_energy_per_successful_bit")));
% An executed native transmission without a receiver trial cannot vanish
% from coverage merely because the OFDM ledger has no unbound entries.
orphan=evidence; orphan.Intervals=ledger(1,:);
orphan.NativePRACH=table("unbound_native_fixture",'VariableNames',{'allocation_id'});
orphan.NativeSourceSHA256=source;
missingNative=sixgr.truth.exportLLSEnergyDiagnostics(cfg,airFolder,struct('DL',covered),orphan);
assert(~missingNative.ResourceCoverageComplete && height(missingNative.UnboundNativeResourceTable)==1);
localAssertMetricUnavailable(missingNative.SummaryTable,"gnb_energy_per_successful_bit");
% Reject contradictory carrier dimensions and duplicate time intervals.
bad=trs; bad.ResourceGridPRBCount=25;
localRejectResource(@()sixgr.truth.expandExecutedResourceIntervals(bad,cfg), ...
    'sixgr:truth:ResourceIntervalAuthorityMismatch');
entries=jsondecode(trs.ExecutedResourceIntervalsJSON);
bad=trs; bad.ExecutedResourceIntervalsJSON=string(jsonencode([entries;entries(1)]));
localRejectResource(@()sixgr.truth.expandExecutedResourceIntervals(bad,cfg), ...
    'sixgr:truth:DuplicateExecutedSymbolInterval');

% Link trials use absolute Slot, not a within-frame slot. Adding Frame*10ms
% a second time moves the observation and corrupts the energy/time axis.
clocked=localTrial("PASS",800); clocked.Frame=3; clocked.Slot=47;
clocked.RuntimeAbsoluteSlotIndex0=46;
timed=sixgr.truth.exportLLSEnergyDiagnostics(cfg,airFolder,struct('DL',clocked));
assert(all(abs(timed.TimelineTable.TimestampSim_ms-46)<1e-12), ...
    'An absolute slot must not acquire a second frame offset.');
clocked.Slot=46; clocked.SlotIndexBase=0;
zeroBased=sixgr.truth.exportLLSEnergyDiagnostics(cfg,airFolder,struct('DL',clocked));
assert(isequal(timed.TimelineTable.TimestampSim_ms,zeroBased.TimelineTable.TimestampSim_ms));
clocked.RuntimeAbsoluteSlotIndex0=45;
try
    sixgr.truth.exportLLSEnergyDiagnostics(cfg,airFolder,struct('DL',clocked));
    error('test:ExpectedEnergyClockRejection','Contradictory runtime clock was accepted.');
catch ex
    assert(strcmp(ex.identifier,'sixgr:truth:EnergyTrialClockMismatch'),'%s',ex.message);
end
clocked.Slot=47; clocked.SlotIndexBase=1; clocked.RuntimeAbsoluteSlotIndex0=46;
h4Clock=cfg; h4Clock.phy.carrier.SubcarrierSpacing=30;
mu1=sixgr.truth.exportLLSEnergyDiagnostics(h4Clock,airFolder,struct('DL',clocked));
assert(all(abs(mu1.TimelineTable.TimestampSim_ms-23)<1e-12) && ...
    all(abs(mu1.TimelineTable.Duration_s-.0005)<1e-15), ...
    'H4 slot47 starts at23ms on the native30kHz nominal clock, not43ms.');

missingCfg = cfg;
missingCfg.lls6g.energy_efficiency = rmfield( ...
    missingCfg.lls6g.energy_efficiency, "ue_tx_dc_per_watt_rf");
missing = sixgr.truth.exportLLSEnergyDiagnostics(missingCfg, airFolder, passTrials);
assert(~missing.Available && isempty(missing.TimelineTable));
localAssertMetricUnavailable(missing.SummaryTable, "ue_energy_per_successful_bit");
assert(contains(string(missing.FailureReason), "missing_or_invalid_explicit_energy_terms"));

ok = true;
end

function cfg = localExplicitConfig()
cfg = struct();
cfg.powerAndRF.bsTxPower_dBm = 46;
cfg.powerAndRF.ueTxPower_dBm = 23;
cfg.powerAndRF.bsRFChainCount = 4;
cfg.powerAndRF.ueRFChainCount = 2;
cfg.antenna.bs = struct('numElements',64,'numTxRFChains',4, ...
    'numRxRFChains',4,'numRFChains',4);
cfg.antenna.ue = struct('numElements',8,'numTxRFChains',2, ...
    'numRxRFChains',2,'numRFChains',2);
cfg.energy.bs.staticW = 100;
cfg.energy.bs.perTRxPW = 4;
cfg.energy.bs.idleRFChainPowerFraction = 0.2;
cfg.energy.bs.sleepW = 10;
cfg.energy.bs.efficiencyPA = 0.4;
cfg.energy.ue.idleW = 1;
cfg.energy.ue.rxW = 1.5;
cfg.energy.ue.sleepW = 0.1;
cfg.energy.ue.txWPerWattRF = 2.5;
cfg.phy.carrier.NSizeGrid = 24;
cfg.phy.carrier.SubcarrierSpacing = 15;
cfg.channel.bandwidth_Hz = 1e6;
cfg.run.numFrames = 1;
cfg.lls6g.energy_efficiency.sleep_state_model = "micro_sleep";
cfg.lls6g.energy_efficiency.bandwidth_adaptation_enabled = true;
cfg.lls6g.energy_efficiency.bandwidth_adaptation_mode = "bwp_like";
cfg.lls6g.energy_efficiency.bs_static_power_w = 100;
cfg.lls6g.energy_efficiency.bs_per_rf_chain_power_w = 4;
cfg.lls6g.energy_efficiency.bs_rf_chain_idle_power_fraction = 0.2;
cfg.lls6g.energy_efficiency.bs_sleep_power_w = 10;
cfg.lls6g.energy_efficiency.bs_pa_efficiency = 0.4;
cfg.lls6g.energy_efficiency.ue_idle_power_w = 1;
cfg.lls6g.energy_efficiency.ue_rx_power_w = 1.5;
cfg.lls6g.energy_efficiency.ue_sleep_power_w = 0.1;
cfg.lls6g.energy_efficiency.ue_tx_dc_per_watt_rf = 2.5;
cfg.lls6g.energy_efficiency.bs_tx_power_dbm = 46;
cfg.lls6g.energy_efficiency.ue_tx_power_dbm = 23;
cfg.lls6g.energy_efficiency.bs_rf_chain_count = 4;
cfg.lls6g.energy_efficiency.ue_rf_chain_count = 2;
end

function T = localTrial(status, bits)
T = table(string(status), 1, 1, 8, double(bits), 1, "dl_tb_1", ...
    'VariableNames', {'Status','Frame','Slot','PRBs','TBSize_bits','UEID','TransportBlockId'});
T.Direction="DL";
T.CRCPass=double(string(status)=="PASS");
% Explicit accounting-fixture occupancy; never represents a PHY outcome.
T.EnergyAllocatedPRBSetJSON=string(jsonencode(0:7));
end

function localAssertMetricUnavailable(T, key)
row = T(string(T.MetricKey) == string(key), :);
assert(height(row) == 1 && ~isfinite(row.Value));
assert(string(row.Availability) == "NOT_EVALUATED");
end

function localAssertMetricValue(T, key, expected, tolerance, statistic)
if nargin < 5
    row = T(string(T.MetricKey) == string(key), :);
    label = string(key);
else
    row = T(string(T.MetricKey) == string(key) & ...
        string(T.Statistic) == string(statistic), :);
    label = string(key) + "/" + string(statistic);
end
assert(height(row) == 1 && abs(double(row.Value) - double(expected)) <= tolerance, ...
    "Unexpected %s value.", label);
end

function localCleanup(root)
if isfolder(root)
    try
        rmdir(root, "s");
    catch
    end
end
end

function localRejectResource(fn,identifier)
try
    fn();
    error('test:MissingResourceRejection','Invalid resource evidence accepted.');
catch err
    assert(strcmp(err.identifier,identifier),'test:UnexpectedResourceFailure', ...
        'Expected %s; got %s: %s',identifier,err.identifier,err.message);
end
end
