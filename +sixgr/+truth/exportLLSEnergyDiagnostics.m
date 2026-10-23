function artifacts = exportLLSEnergyDiagnostics(cfg, airInterfaceRunFolder, rawTrials, resourceEvidence)
%EXPORTLLSENERGYDIAGNOSTICS Emit measured/model-backed RF and energy tables for LLS.

artifacts = struct("CSV", "", "TimelineCSV", "", "ModelTermsCSV", "", ...
    "SummaryTable", table(), "TimelineTable", table(), "ModelTermsTable", table(), ...
    "Available", false, "FailureReason", "");

rootRunFolder = fileparts(char(string(airInterfaceRunFolder)));
layout = sixgr.report.resultLayout(rootRunFolder);
sixgr.util.ensureFolder(layout.RFCSVDir);
artifacts.RFExecution=sixgr.truth.publishRFEndpointExecutionLedger(cfg,airInterfaceRunFolder,rawTrials);
if nargin<4
    [resourceEvidence,rawTrials,loadAudit]=sixgr.truth.loadLLSEnergyResourceEvidence(cfg,airInterfaceRunFolder,rawTrials);
    artifacts.ResourceLoadAudit=loadAudit;
end
if ~isempty(resourceEvidence)
    carrierMissing=false;
    if isempty(resourceEvidence.Intervals)
        binding=table('Size',[0 1],'VariableTypes',{'double'},'VariableNames',{'BoundIntervalCount'});
        unbound=resourceEvidence.Intervals;
        for name=["DL","UL","PDCCH","PUCCH","SRS","CSIRS","TRS"]
            carrierMissing=carrierMissing || ~isempty(sixgr.util.structGet(rawTrials,name,table()));
        end
        if sixgr.util.structGet(cfg,'phy.ssb.scs_kHz',cfg.phy.carrier.SubcarrierSpacing)==cfg.phy.carrier.SubcarrierSpacing
            carrierMissing=carrierMissing || ~isempty(sixgr.util.structGet(rawTrials,'PBCH',table()));
        end
    else
    [rawTrials,binding,unbound]=sixgr.truth.bindObservedResourcesToTrials(rawTrials,cfg, ...
        resourceEvidence.Intervals,resourceEvidence.ConfigHash,resourceEvidence.SourceSHA256);
    end
    [common,commonBinding,unbound]=sixgr.truth.buildCommonSignalEnergyObservations( ...
        rawTrials,cfg,unbound,resourceEvidence.ConfigHash,resourceEvidence.SourceSHA256);
    rawTrials.CommonEnergyObservations=common;
    artifacts.CommonSignalObservations=common;
    artifacts.CommonResourceBindingTable=commonBinding;
    artifacts.CommonSignalObservationsCSV=fullfile(layout.RFCSVDir,'energy_common_signal_observations.csv');
    artifacts.CommonResourceBindingCSV=fullfile(layout.RFCSVDir,'energy_common_resource_binding.csv');
    sixgr.util.csvWriteTable(artifacts.CommonSignalObservationsCSV,common);
    sixgr.util.csvWriteTable(artifacts.CommonResourceBindingCSV,commonBinding);
    artifacts.ResourceBindingCSV=fullfile(layout.RFCSVDir,'energy_resource_binding.csv');
    artifacts.UnboundResourcesCSV=fullfile(layout.RFCSVDir,'energy_unbound_executed_resources.csv');
    sixgr.util.csvWriteTable(artifacts.ResourceBindingCSV,binding);
    sixgr.util.csvWriteTable(artifacts.UnboundResourcesCSV,unbound);
    artifacts.ResourceBindingTable=binding;
    artifacts.UnboundResourceTable=unbound;
    artifacts.ResourceCoverageScope="supplied_executed_occupancy_ledgers_not_complete_run";
    artifacts.ResourceCoverageComplete=~carrierMissing && isempty(unbound) && all(binding.BoundIntervalCount>0);
    if isfield(resourceEvidence,'NativePRACH')
        nativeBinding=table(); nativeUsed=strings(0,1);
        if isfield(rawTrials,'PRACH') && ~isempty(rawTrials.PRACH)
            [rawTrials.PRACH,nativeBinding]=sixgr.truth.bindPRACHNativeResourcesToTrials( ...
                rawTrials.PRACH,cfg,resourceEvidence.NativePRACH,resourceEvidence.ConfigHash,resourceEvidence.NativeSourceSHA256);
            nativeUsed=string(nativeBinding.AllocationID(nativeBinding.NativeRows>0));
        end
        nativeUnbound=resourceEvidence.NativePRACH(~ismember(string(resourceEvidence.NativePRACH.allocation_id),nativeUsed),:);
        artifacts.NativeResourceBindingTable=nativeBinding;
        artifacts.NativeResourceBindingCSV=fullfile(layout.RFCSVDir,'energy_native_resource_binding.csv');
        sixgr.util.csvWriteTable(artifacts.NativeResourceBindingCSV,nativeBinding);
        artifacts.UnboundNativeResourceTable=nativeUnbound;
        artifacts.UnboundNativeResourceCSV=fullfile(layout.RFCSVDir,'energy_unbound_native_resources.csv');
        sixgr.util.csvWriteTable(artifacts.UnboundNativeResourceCSV,nativeUnbound);
        nativeComplete=isempty(nativeUnbound);
        if ~isempty(nativeBinding), nativeComplete=nativeComplete && all(nativeBinding.NativeRows>0); end
        artifacts.ResourceCoverageComplete=artifacts.ResourceCoverageComplete && nativeComplete;
    elseif isfield(rawTrials,'PRACH') && ~isempty(rawTrials.PRACH)
        artifacts.ResourceCoverageComplete=false;
    end
    if isfield(resourceEvidence,'NativeSSB')
        ssbBinding=table(); ssbUsed=strings(0,1);
        if isfield(rawTrials,'PBCH') && ~isempty(rawTrials.PBCH)
            [rawTrials.PBCH,ssbBinding]=sixgr.truth.bindSSBNativeResourcesToTrials( ...
                rawTrials.PBCH,cfg,resourceEvidence.NativeSSB,resourceEvidence.ConfigHash,resourceEvidence.NativeSSBSourceSHA256);
            ssbUsed=string(ssbBinding.AllocationID(ssbBinding.NativeRows>0));
        end
        ssbUnbound=resourceEvidence.NativeSSB(~ismember(string(resourceEvidence.NativeSSB.allocation_id),ssbUsed),:);
        artifacts.NativeSSBResourceBindingTable=ssbBinding;
        artifacts.NativeSSBResourceBindingCSV=fullfile(layout.RFCSVDir,'energy_native_ssb_resource_binding.csv');
        sixgr.util.csvWriteTable(artifacts.NativeSSBResourceBindingCSV,ssbBinding);
        artifacts.UnboundNativeSSBResourceTable=ssbUnbound;
        artifacts.UnboundNativeSSBResourceCSV=fullfile(layout.RFCSVDir,'energy_unbound_native_ssb_resources.csv');
        sixgr.util.csvWriteTable(artifacts.UnboundNativeSSBResourceCSV,ssbUnbound);
        complete=isempty(ssbUnbound);
        if ~isempty(ssbBinding), complete=complete && all(ssbBinding.NativeRows>0); end
        artifacts.ResourceCoverageComplete=artifacts.ResourceCoverageComplete && complete;
    elseif ~isempty(sixgr.util.structGet(rawTrials,'PBCH',table())) && ...
            sixgr.util.structGet(cfg,'phy.ssb.scs_kHz',cfg.phy.carrier.SubcarrierSpacing)~=cfg.phy.carrier.SubcarrierSpacing
        artifacts.ResourceCoverageComplete=false;
    end
end

% Shared observations carry the real RF sample clock independently of the
% modeled energy rows below. Export their union without equating an observed
% operator interval with a hardware TX/RX/idle/sleep transition.
[rfObservations,rfIntervals,rfCoverage]=sixgr.truth.collectRFEndpointObservationIntervals(rawTrials);
artifacts.RFObservationCSV=fullfile(layout.RFCSVDir,"rf_endpoint_observation_intervals.csv");
artifacts.RFIntervalUnionCSV=fullfile(layout.RFCSVDir,"rf_endpoint_interval_union.csv");
artifacts.RFIntervalCoverageCSV=fullfile(layout.RFCSVDir,"rf_endpoint_interval_coverage.csv");
sixgr.util.csvWriteTable(artifacts.RFObservationCSV,rfObservations);
sixgr.util.csvWriteTable(artifacts.RFIntervalUnionCSV,rfIntervals);
sixgr.util.csvWriteTable(artifacts.RFIntervalCoverageCSV,rfCoverage);
artifacts.RFObservationTable=rfObservations;
artifacts.RFIntervalUnionTable=rfIntervals;
artifacts.RFIntervalCoverageTable=rfCoverage;

model = sixgr.truth.resolveLLSEnergyModelConfig(cfg, ...
    RFInventoryPolicy="bind_declared_inventory");
% A live/repair prefix is not the planned full run. Bind its committed
% radio boundary only in the reporting copy, never mutate physical config.
summaryCfg=cfg;
completed=sixgr.util.structGet(rawTrials,'CoupledRuntime.CompletedCanonicalSlots',NaN);
artifacts.MeasurementWindowSource="existing_declared_or_observed_duration";
if isfinite(completed)
    validateattributes(completed,{'numeric'},{'scalar','integer','nonnegative'});
    if completed>0
        summaryCfg.run.measurementWindow_s=double(completed)*localSlotDuration(cfg);
        artifacts.MeasurementWindowSource="committed_runtime_completed_canonical_slots";
    end
end
modelTermsPath = fullfile(layout.RFCSVDir, "energy_model_terms.csv");
sixgr.util.csvWriteTable(modelTermsPath, model.TermTable);
artifacts.ModelTermsCSV = modelTermsPath;
artifacts.ModelTermsTable = model.TermTable;
artifacts.Available = logical(model.Available);
artifacts.ModelAvailable = logical(model.Available);
artifacts.FailureReason = string(model.FailureReason);

if model.Available
    timelineT = localBuildEnergyTimeline(cfg, rawTrials, model.ModelConfig, model.ModelVersion);
    endpointT = sixgr.truth.integrateLLSEndpointEnergy(timelineT,model.ModelConfig);
    summaryT = localBuildEnergySummary(summaryCfg, timelineT, endpointT, model.ModelVersion);
    artifacts.EndpointTotalsAvailable=~isempty(endpointT) && ...
        all(endpointT.Availability=="AVAILABLE");
    if ~isempty(endpointT) && ~artifacts.EndpointTotalsAvailable
        artifacts.Available=false;
        artifacts.FailureReason=strjoin(unique(endpointT.Status( ...
            endpointT.Availability~="AVAILABLE"),'stable'),";");
    end
else
    timelineT = table();
    endpointT = table();
    summaryT = localUnavailableEnergySummary(model.ModelVersion, model.FailureReason);
    artifacts.EndpointTotalsAvailable=false;
end
if isfield(artifacts,'ResourceCoverageComplete') && ~artifacts.ResourceCoverageComplete
    % Keep partial calculations in an explicitly scoped diagnostic artifact,
    % not as primary endpoint totals when executed signals are unaccounted.
    partial=summaryT;
    partial.EvidenceScope=repmat("represented_receiver_intervals_only_incomplete_signal_coverage",height(partial),1);
    artifacts.RepresentedIntervalSummaryTable=partial;
    artifacts.RepresentedIntervalSummaryCSV=fullfile(layout.RFCSVDir,'energy_represented_interval_diagnostics.csv');
    sixgr.util.csvWriteTable(artifacts.RepresentedIntervalSummaryCSV,partial);
    totals=ismember(string(summaryT.MetricKey),["ue_energy_per_successful_bit", ...
        "gnb_energy_per_successful_bit","ue_energy_per_slot_frame_burst", ...
        "gnb_active_sleep_duty_cycle","rf_chain_active_time","bb_processing_energy", ...
        "throughput_per_watt","energy_delay_product","energy_spectral_efficiency_tradeoff"]);
    summaryT.Value(totals)=NaN;
    summaryT.TextValue(totals)="";
    summaryT.Availability(totals)="NOT_EVALUATED";
    summaryT.Notes(totals)="Executed signal resources remain unbound; inspect energy_unbound_executed_resources and the separately scoped represented-interval diagnostics.";
    artifacts.Available=false;
    reasons=[artifacts.FailureReason,"unbound_executed_signal_resources"];
    artifacts.FailureReason=strjoin(reasons(strlength(reasons)>0),";");
end
summaryT = sixgr.truth.finalizeProbeMetricTable(summaryT);
summaryT.EnergyAccountingScope=repmat("represented_signal_intervals_not_complete_run_or_hardware_energy",height(summaryT),1);
summaryT.MeasurementWindowSource=repmat(artifacts.MeasurementWindowSource,height(summaryT),1);

timelinePath = fullfile(layout.RFCSVDir, "energy_timeline_trace.csv");
summaryPath = fullfile(layout.RFCSVDir, "probe_rf_energy.csv");
artifacts.EndpointTimelineCSV=fullfile(layout.RFCSVDir,"energy_endpoint_timeline.csv");
artifacts.EndpointTimelineTable=endpointT;
sixgr.util.csvWriteTable(artifacts.EndpointTimelineCSV,endpointT);
sixgr.util.csvWriteTable(timelinePath, timelineT);
sixgr.util.csvWriteTable(summaryPath, summaryT);

artifacts.CSV = summaryPath;
artifacts.TimelineCSV = timelinePath;
artifacts.SummaryTable = summaryT;
artifacts.TimelineTable = timelineT;
% EndpointTotalsAvailable concerns only represented receiver intervals. A
% caller with the complete TX ledger must also inspect coverage; unbound SI,
% RA or common signals cannot disappear from a complete-run energy claim.
artifacts.EndpointTotalsScope="represented_receiver_intervals_not_complete_run_or_hardware_power";
artifacts.CompleteRunEnergyAvailable=false;
end

function timelineT = localBuildEnergyTimeline(cfg, rawTrials, modelCfg, modelVersion)
rawTrials=localBindSinglePopulationScope(rawTrials);
ueModel = sixgr.rf.EnergyModelUE(modelCfg);
bsModel = sixgr.rf.EnergyModelBS(modelCfg);
slotDur_s = localSlotDuration(cfg);
bsRfChains = double(sixgr.util.structGet(modelCfg, "powerAndRF.bsRFChainCount", NaN));
ueRfChains = double(sixgr.util.structGet(modelCfg, "powerAndRF.ueRFChainCount", NaN));
bsRfChains=localDirectionalRFInventory(modelCfg,"bs",bsRfChains);
ueRfChains=localDirectionalRFInventory(modelCfg,"ue",ueRfChains);
bsTxPowerW = localdBmToW(double(sixgr.util.structGet(modelCfg, "powerAndRF.bsTxPower_dBm", NaN)));
ueTxPowerW = localdBmToW(double(sixgr.util.structGet(modelCfg, "powerAndRF.ueTxPower_dBm", NaN)));
totalRBs = max(1, double(sixgr.util.structGet(cfg, "phy.carrier.NSizeGrid", 1)));

rows = repmat(localEmptyEnergyRow(), 0, 1);
rows = [rows; localBuildRowsForTable(localResolveTrialTable(sixgr.util.structGet(rawTrials, "DL", table())), "DL_data", "DL", slotDur_s, totalRBs, bsRfChains, ueRfChains, bsModel, ueModel, bsTxPowerW, ueTxPowerW, "air_interface/csv/dl_pdsch_trials.csv",cfg)]; %#ok<AGROW>
rows = [rows; localBuildRowsForTable(localResolveTrialTable(sixgr.util.structGet(rawTrials, "UL", table())), "UL_data", "UL", slotDur_s, totalRBs, bsRfChains, ueRfChains, bsModel, ueModel, bsTxPowerW, ueTxPowerW, "air_interface/csv/ul_pusch_trials.csv",cfg)]; %#ok<AGROW>
rows = [rows; localBuildRowsForTable(localResolveTrialTable(sixgr.util.structGet(rawTrials, "PDCCH", table())), "PDCCH_monitoring", "DL", slotDur_s, totalRBs, bsRfChains, ueRfChains, bsModel, ueModel, bsTxPowerW, ueTxPowerW, "air_interface/csv/pdcch_trials.csv",cfg)]; %#ok<AGROW>
rows = [rows; localBuildRowsForTable(localResolveTrialTable(sixgr.util.structGet(rawTrials, "PBCH", table())), "SSB_PBCH", "DL", slotDur_s, totalRBs, bsRfChains, ueRfChains, bsModel, ueModel, bsTxPowerW, ueTxPowerW, "air_interface/csv/pbch_trials.csv",cfg)]; %#ok<AGROW>
rows = [rows; localBuildRowsForTable(localResolveTrialTable(sixgr.util.structGet(rawTrials, "PRACH", table())), "PRACH", "UL", slotDur_s, totalRBs, bsRfChains, ueRfChains, bsModel, ueModel, bsTxPowerW, ueTxPowerW, "air_interface/csv/prach_trials.csv",cfg)]; %#ok<AGROW>
rows = [rows; localBuildRowsForTable(localResolveTrialTable(sixgr.util.structGet(rawTrials, "PUCCH", table())), "PUCCH", "UL", slotDur_s, totalRBs, bsRfChains, ueRfChains, bsModel, ueModel, bsTxPowerW, ueTxPowerW, "air_interface/csv/pucch_trials.csv",cfg)]; %#ok<AGROW>
rows = [rows; localBuildRowsForTable(localResolveTrialTable(sixgr.util.structGet(rawTrials, "SRS", table())), "SRS", "UL", slotDur_s, totalRBs, bsRfChains, ueRfChains, bsModel, ueModel, bsTxPowerW, ueTxPowerW, "air_interface/csv/srs_trials.csv",cfg)]; %#ok<AGROW>
rows = [rows; localBuildRowsForTable(localResolveTrialTable(sixgr.util.structGet(rawTrials, "CSIRS", table())), "CSI_RS", "DL", slotDur_s, totalRBs, bsRfChains, ueRfChains, bsModel, ueModel, bsTxPowerW, ueTxPowerW, "air_interface/csv/csi_rs_trials.csv",cfg)]; %#ok<AGROW>
rows = [rows; localBuildRowsForTable(localResolveTrialTable(sixgr.util.structGet(rawTrials, "TRS", table())), "TRS", "DL", slotDur_s, totalRBs, bsRfChains, ueRfChains, bsModel, ueModel, bsTxPowerW, ueTxPowerW, "air_interface/csv/trs_trials.csv",cfg)]; %#ok<AGROW>
common=sixgr.util.structGet(rawTrials,'CommonEnergyObservations',table());
if ~isempty(common)
    for domain=reshape(unique(string(common.Domain),'stable'),1,[])
        C=common(common.Domain==domain,:);
        direction=unique(string(C.Direction)); source=unique(string(C.SourceArtifact));
        assert(isscalar(direction)&&isscalar(source),'sixgr:truth:CommonEnergyDomain','Common domain must retain one direction and source.');
        rows=[rows;localBuildRowsForTable(C,domain,direction,slotDur_s,totalRBs, ...
            bsRfChains,ueRfChains,bsModel,ueModel,bsTxPowerW,ueTxPowerW,source,cfg)]; %#ok<AGROW>
    end
end

if isempty(rows)
    timelineT = table();
else
    timelineT = struct2table(rows);
    timelineT.EnergyModelVersion = repmat(string(modelVersion), height(timelineT), 1);
    timelineT.EvidenceType = repmat("runtime_state_conditioned_engineering_model", height(timelineT), 1);
    timelineT.Availability = repmat("AVAILABLE", height(timelineT), 1);
    invalid=~isfinite(timelineT.Power_W) | ~isfinite(timelineT.Energy_J);
    timelineT.Availability(invalid)="NOT_EVALUATED";
    timelineT.PowerEquation = repmat("configured_state_power_w*declared_model_interval_s", height(timelineT), 1);
    timelineT.PowerModelStatus=repmat("configured_channel_attribution_not_endpoint_total",height(timelineT),1);
    timelineT.PowerModelStatus(invalid)="missing_observed_resource_load";
    timelineT.AccountingRole=repmat("nonadditive_channel_attribution_use_endpoint_timeline_for_totals",height(timelineT),1);
end
end

function rows = localBuildRowsForTable(T, domain, direction, slotDur_s, totalRBs, bsRfChains, ueRfChains, bsModel, ueModel, bsTxPowerW, ueTxPowerW, sourceArtifact,cfg)
rows = repmat(localEmptyEnergyRow(), 0, 1);
if ~(istable(T) && ~isempty(T))
    return;
end
% Credit the original TB once before splitting its reporting intervals.
% Otherwise a per-symbol duplicate could be mistaken for a HARQ attempt.
isData=any(string(domain)==["DL_data","UL_data"]);
if isData
    if ~ismember('Direction',T.Properties.VariableNames)
        T.Direction=repmat(string(direction),height(T),1);
    end
    assert(all(upper(string(T.Direction))==direction), ...
        'sixgr:truth:EnergyDirectionMismatch','Raw-table direction must match its owning DL/UL population.');
    if ~ismember('UniqueDeliveredTBBits',T.Properties.VariableNames)
        T=sixgr.kpi.creditTransportGoodput(T);
    end
    % Validate once on receiver rows, before making nonadditive symbol
    % attribution rows. These are not new first-delivery events.
    T.EnergyReceiverGoodputBits=sixgr.kpi.transportGoodputBits(T);
end
if ismember('ExecutedResourceIntervalsJSON',T.Properties.VariableNames)
    T=sixgr.truth.expandExecutedResourceIntervals(T,cfg);
end
T=sixgr.truth.expandExecutedSampleIntervals(T,cfg);
if direction=="DL"
    bsRfChains=bsRfChains.Tx; ueRfChains=ueRfChains.Rx;
else
    bsRfChains=bsRfChains.Rx; ueRfChains=ueRfChains.Tx;
end
if isData
    delivered=double(T.EnergyReceiverGoodputBits);
end

for i = 1:height(T)
    load = 1;
    prbCount = localNumericField(T, i, ["PRBs","AllocatedPRBCount","PRBCount"], NaN);
    loadSource="observed_allocation_PRB_count";
    exactPRBs=string(localTableValue(T,i,"EnergyAllocatedPRBSetJSON",""));
    intervalJSON=string(localTableValue(T,i,"ExecutedResourceIntervalsJSON",""));
    nativeJSON=string(localTableValue(T,i,"ExecutedSampleIntervalsJSON",""));
    hasExactPRBs=~ismissing(exactPRBs) && strlength(strtrim(exactPRBs))>0 && ...
        ((~ismissing(intervalJSON) && strlength(strtrim(intervalJSON))>0) || ...
        (~ismissing(nativeJSON) && strlength(strtrim(nativeJSON))>0));
    if hasExactPRBs
        prbs=jsondecode(exactPRBs);
        validateattributes(prbs,{'numeric'},{'vector','nonempty','integer','nonnegative','<',totalRBs});
        prbCount=numel(unique(prbs));
        loadSource="executed_per_symbol_PRB_union";
    elseif domain=="PDCCH_monitoring"
        % The generic PRBStart/AllocatedPRBCount columns describe decoded
        % DATA grants, not the transmitted control candidate.
        prbCount=NaN;
        if ismember("PDCCHAllocatedPRBSetJSON",string(T.Properties.VariableNames))
            value=string(T.PDCCHAllocatedPRBSetJSON(i));
            if ~ismissing(value) && strlength(strtrim(value))>0
                prbs=jsondecode(value);
                validateattributes(prbs,{'numeric'},{'vector','integer','nonnegative','<',totalRBs});
                prbCount=numel(unique(prbs));
                loadSource="transmitted_PDCCH_data_and_DMRS_PRB_union";
            end
        end
    elseif domain=="PUCCH"
        prbCount=localNumericField(T,i,"PUCCHPRBCount",prbCount);
    elseif domain=="SRS"
        prbCount=localNumericField(T,i,"SRSOccupiedPRBCount",prbCount);
    end
    if isfinite(prbCount)
        assert(isreal(prbCount) && isscalar(prbCount) && prbCount==fix(prbCount) && ...
            prbCount>=0 && prbCount<=totalRBs, ...
            'sixgr:truth:EnergyPRBCountOutOfGrid', ...
            'Observed resource count must be an integer in [0,NSizeGrid]; do not clamp it into a power-model load.');
        load = double(prbCount) / totalRBs;
    else
        load=NaN;
        loadSource="missing_observed_resource_load_no_full_band_substitute";
    end
    status = string(localTableValue(T, i, "Status", "NA"));
    successBits = 0;
    if isData, successBits=delivered(i); end
    frameVal = double(localTableValue(T, i, "Frame", i));
    slotVal = double(localTableValue(T, i, "Slot", NaN));
    % The link-trial producer contract uses one-based ABSOLUTE Slot. Frame
    % is a separate label, not another elapsed-time offset. Explicit legacy
    % zero-based input must declare its base rather than relying on min(Slot).
    slotBase = localNumericField(T,i,"SlotIndexBase",1);
    assert(ismember(slotBase,[0 1]) && isfinite(slotVal) && ...
        slotVal==fix(slotVal) && slotVal>=slotBase, ...
        'sixgr:truth:EnergyTrialClockMismatch', ...
        'Energy observation requires a valid absolute trial slot and index base.');
    executedSlot0=localNumericField(T,i,"RuntimeAbsoluteSlotIndex0",NaN);
    assert(~isfinite(executedSlot0) || executedSlot0==slotVal-slotBase, ...
        'sixgr:truth:EnergyTrialClockMismatch', ...
        'Exported Slot must agree with its executed absolute-slot clock.');
    symbolVal = localNumericField(T, i, ["SymbolStart"], NaN);
    ueId = localNumericField(T, i, ["UEIndex","UEID"], NaN);
    cellId = localNumericField(T, i, ["CellID","ServingCell","BaseStationID"], NaN);
    baseStationId = localNumericField(T, i, ["BaseStationID","CellID","ServingCell"], NaN);
    configuredSites=sixgr.util.structGet(cfg,"scenario.layout.nSites",NaN);
    configuredSectors=sixgr.util.structGet(cfg,"scenario.layout.nSectorsPerSite",NaN);
    if configuredSites==1 && configuredSectors==1
        if ~isfinite(cellId), cellId=1; end
        if ~isfinite(baseStationId), baseStationId=1; end
    end
    rnti = localNumericField(T, i, ["RNTI","UEID","UEIndex"], NaN);
    tbId = localTransportBlockId(T, i, direction);
    harqProcessId = localNumericField(T, i, ["HARQProcessId","HARQProcess"], NaN);
    ndi = localNumericField(T, i, ["NDI","HARQNDI"], NaN);
    rv = localNumericField(T, i, ["RV","HARQRV"], NaN);
    layers = localNumericField(T, i, ["Layers","RankIndicator","Rank"], NaN);
    txPower_dBm = NaN;
    rxPower_dBm = NaN;
    if upper(string(direction)) == "DL"
        txPower_dBm = localOptionalScalar(T, i, "TxPower_dBm", NaN);
        if ~isfinite(txPower_dBm)
            txPower_dBm = localOptionalScalar(T, i, "ConfiguredTxPower_dBm", NaN);
        end
        if ~isfinite(txPower_dBm)
            txPower_dBm = localOptionalScalar(T, i, "BS_TX_Power_dBm", NaN);
        end
        if ~isfinite(txPower_dBm)
            txPower_dBm = localWToDbm(bsTxPowerW);
        end
        % Normalized CSI_RSRP_dB has no watt reference, and per-RS-RE RSRP
        % is not total received power. Do not alias either into this plane.
        rxPower_dBm = localNumericField(T, i, ["ReceivedPower_dBm"], NaN);
    else
        txPower_dBm = localOptionalScalar(T, i, "TxPower_dBm", NaN);
        if ~isfinite(txPower_dBm)
            txPower_dBm = localOptionalScalar(T, i, "ConfiguredTxPower_dBm", NaN);
        end
        if ~isfinite(txPower_dBm)
            txPower_dBm = localWToDbm(ueTxPowerW);
        end
        rxPower_dBm = localNumericField(T, i, ["ReceivedPower_dBm"], NaN);
    end
    switch upper(string(direction))
        case "DL"
            bs = localBSPower(bsModel,bsRfChains,load,bsTxPowerW);
            ue = ueModel.power('rx', 0);
            rows(end+1, 1) = localMakeEnergyRow("gNB", domain, direction, frameVal, slotVal, symbolVal, slotDur_s, bs.totalW, successBits, bsRfChains, bs.trxW * slotDur_s, sourceArtifact, status, ... %#ok<AGROW>
                ueId, cellId, baseStationId, rnti, tbId, harqProcessId, ndi, rv, prbCount, load, layers, bsRfChains, 1, txPower_dBm, NaN, "active_tx", slotBase);
            rows(end+1, 1) = localMakeEnergyRow("UE", domain, direction, frameVal, slotVal, symbolVal, slotDur_s, ue.totalW, successBits, ueRfChains, 0, sourceArtifact, status, ... %#ok<AGROW>
                ueId, cellId, baseStationId, rnti, tbId, harqProcessId, ndi, rv, prbCount, load, layers, 0, localControlMonitoringLoad(domain), NaN, rxPower_dBm, localUEEnergyState(domain, direction, "UE"), slotBase);
        otherwise
            ue = ueModel.power('tx', ueTxPowerW);
            bs = localBSPower(bsModel,bsRfChains,load,0);
            rows(end+1, 1) = localMakeEnergyRow("UE", domain, direction, frameVal, slotVal, symbolVal, slotDur_s, ue.totalW, successBits, ueRfChains, 0, sourceArtifact, status, ... %#ok<AGROW>
                ueId, cellId, baseStationId, rnti, tbId, harqProcessId, ndi, rv, prbCount, load, layers, ueRfChains, localControlMonitoringLoad(domain), txPower_dBm, NaN, localUEEnergyState(domain, direction, "UE"), slotBase);
            rows(end+1, 1) = localMakeEnergyRow("gNB", domain, direction, frameVal, slotVal, symbolVal, slotDur_s, bs.totalW, successBits, bsRfChains, bs.trxW * slotDur_s, sourceArtifact, status, ... %#ok<AGROW>
                ueId, cellId, baseStationId, rnti, tbId, harqProcessId, ndi, rv, prbCount, load, layers, 0, 0, NaN, rxPower_dBm, "active_rx", slotBase);
    end
    % Keep receiver-owned credit on both endpoints for traceability, but
    % only the transmitter-side row enters the denominator once below.
    if isData
        for rowIndex=numel(rows)-1:numel(rows)
            rows(rowIndex).TransportGoodputKey=string(T.TransportGoodputKey(i));
            rows(rowIndex).TransportGoodputStatus=string(T.TransportGoodputStatus(i));
        end
    end
    for rowIndex=numel(rows)-1:numel(rows)
        rows(rowIndex).ExecutedAllocationID=string(localTableValue(T,i,"AllocationID", ...
            localTableValue(T,i,"ExecutedAllocationID","")));
        rows(rowIndex).SourceObservationRow=localNumericField(T,i,"SourceRow",NaN);
        rows(rowIndex).RecordedReceiverOutcomeField=string(localTableValue(T,i,"RecordedReceiverOutcomeField",""));
        rows(rowIndex).RecordedReceiverOutcome=localNumericField(T,i,"RecordedReceiverOutcome",NaN);
        rows(rowIndex).ObservationStartSample=localNumericField(T,i,"ObservationStartSample",NaN);
        rows(rowIndex).ObservationEndSampleExclusive=localNumericField(T,i,"ObservationEndSampleExclusive",NaN);
        rows(rowIndex).ObservationSampleRateHz=localNumericField(T,i,"ObservationSampleRateHz",NaN);
        rows(rowIndex).ObservationPopulationKey=localPopulationKey(T,i,tbId);
        rows(rowIndex).PopulationBindingSource=string(localTableValue(T,i, ...
            "EnergyPopulationBindingSource","retained_row_identity"));
        rows(rowIndex).LoadSource=loadSource;
        rows(rowIndex).ResourcePRBSetJSON=string(localTableValue(T,i,"EnergyAllocatedPRBSetJSON",""));
        if domain=="PDCCH_monitoring" && ~hasExactPRBs
            rows(rowIndex).ResourcePRBSetJSON=string(localTableValue(T,i,"PDCCHAllocatedPRBSetJSON",""));
        end
        rows(rowIndex).ResourceGridPRBCount=totalRBs;
        if rows(rowIndex).Entity=="gNB"
            rows(rowIndex).EndpointModelTxPower_W=0;
            if direction=="DL", rows(rowIndex).EndpointModelTxPower_W=bsTxPowerW; end
        else
            rows(rowIndex).EndpointModelTxPower_W=0;
            if direction=="UL", rows(rowIndex).EndpointModelTxPower_W=ueTxPowerW; end
        end
        rows(rowIndex)=localBindResourceInterval(rows(rowIndex),T,i,cfg,domain,slotVal-slotBase);
    end
end
end

function power=localBSPower(model,chains,load,watts)
if isfinite(load)
    power=model.power('active',chains,load,watts);
elseif model.PerTRxPW==0 || model.IdleRFChainPowerFraction==1
    % The declared coefficient of load is exactly zero. Evaluate the
    % constant equation, but keep occupancy unknown in the exported row.
    % This is not permission to invent PRBs, active RF samples or a full-
    % run interval. Nonconstant models still require observed load below.
    power=model.power('active',chains,0,watts);
    power.load=NaN;
else
    power=struct('totalW',NaN,'trxW',NaN);
end
end

function row=localBindResourceInterval(row,T,i,cfg,domain,slot0)
nativeStart=localNumericField(T,i,"EnergyIntervalStartSample",NaN);
if isfinite(nativeStart)
    nativeEnd=localNumericField(T,i,"EnergyIntervalEndSampleExclusive",NaN);
    fs=localNumericField(T,i,"EnergyIntervalSampleRateHz",NaN);
    assert(isfinite(nativeEnd)&&nativeEnd>nativeStart&&isfinite(fs)&&fs>0, ...
        'sixgr:truth:EnergyNativeClock','Native sample interval must be explicit and positive.');
    duration=(nativeEnd-nativeStart)/fs;
    row.BBProcessingEnergy_J=row.BBProcessingEnergy_J*duration/row.Duration_s;
    row.TimestampSim_ms=1000*nativeStart/fs; row.Duration_s=duration;
    row.Symbol=NaN; % Native SSB/PRACH symbols are not carrier symbols.
    row.NativeSymbolIndex0=localNumericField(T,i,"EnergyNativeSymbolIndex0",NaN);
    row.ExecutedStartSample=nativeStart;
    row.ExecutedEndSampleExclusive=nativeEnd;
    row.ExecutedSampleRateHz=fs;
    row.Energy_J=row.Power_W*duration;
    row.TimestampReference="executed_native_TX_sample_clock_not_propagated_RX_arrival";
    source=string(localTableValue(T,i,'ExecutedSampleIntervalSource',""));
    if source=="executed_native_SSB_CP_useful_samples_not_RF_activity"
        row.EnergyIntervalBasis="native_SSB_CP_and_useful_interval_engineering_power_model_not_RF_tails";
    else
        assert(source=="executed_native_PRACH_CP_useful_samples_not_RF_activity", ...
            'sixgr:truth:EnergyNativeAuthority','Unknown native energy interval source.');
        row.EnergyIntervalBasis="native_PRACH_CP_and_useful_interval_engineering_power_model_not_RF_tails";
    end
    return;
end
first=localNumericField(T,i,"SymbolStart",NaN);
count=localNumericField(T,i,"NumSymbols",NaN);
exact=string(localTableValue(T,i,"EnergyAllocatedPRBSetJSON",""));
hasExact=~ismissing(exact) && strlength(strtrim(exact))>0 && ...
    ismember('ExecutedResourceIntervalsJSON',T.Properties.VariableNames) && ...
    strlength(string(T.ExecutedResourceIntervalsJSON(i)))>0;
if domain=="PDCCH_monitoring" && ~hasExact
    first=localNumericField(T,i,"PDCCHCORESETStartSymbol",NaN);
    count=localNumericField(T,i,"PDCCHCORESETDuration",NaN);
elseif domain=="PUCCH" && ~hasExact
    first=localNumericField(T,i,"PUCCHSymbolStart",NaN);
    count=localNumericField(T,i,"PUCCHNumSymbols",NaN);
end
if ~(isfinite(first)&&isfinite(count)), return; end
spec=sixgr.phy.frame.AbsoluteTime.resolveNumerology(cfg.phy.carrier);
validateattributes(first,{'numeric'},{'scalar','integer','nonnegative','<',spec.SymbolsPerSlot});
validateattributes(count,{'numeric'},{'scalar','integer','positive','<=',spec.SymbolsPerSlot-first});
start=sixgr.phy.frame.AbsoluteTime.fromAbsoluteSlotSymbol(slot0,first,spec);
stop=start.plusSymbols(count,spec);
ratio=(stop.seconds()-start.seconds())/row.Duration_s;
row.Symbol=first;
row.TimestampSim_ms=start.milliseconds();
row.Duration_s=stop.seconds()-start.seconds();
row.Energy_J=row.Power_W*row.Duration_s;
row.BBProcessingEnergy_J=row.BBProcessingEnergy_J*ratio;
row.TimestampReference="executed_resource_absolute_slot_symbol_clock_not_RF_propagation_time";
row.EnergyIntervalBasis="CP_accurate_observed_resource_interval_engineering_power_model";
end

function counts=localDirectionalRFInventory(cfg,endpoint,pool)
counts=struct('Tx',pool,'Rx',pool);
for direction=["Tx","Rx"]
    value=sixgr.util.structGet(cfg,"antenna."+endpoint+".num"+direction+"RFChains", ...
        sixgr.util.structGet(cfg,"scenario."+endpoint+".num"+direction+"RFChains",pool));
    validateattributes(value,{'numeric'},{'scalar','finite','integer','positive','<=',pool});
    counts.(direction)=double(value);
end
end

function row = localMakeEnergyRow(entity, domain, direction, frameVal, slotVal, symbolVal, duration_s, powerW, successBits, rfChains, bbEnergyJ, sourceArtifact, status, ueId, cellId, baseStationId, rnti, tbId, harqProcessId, ndi, rv, prbCount, activeBWFrac, activeRank, activeTxruCount, controlMonitoringLoad, txPower_dBm, rxPower_dBm, state, slotIndexBase)
row = struct( ...
    "Entity", string(entity), ...
    "EntityType", localEntityTypeToken(entity), ...
    "EntityID", localEntityID(entity, ueId, cellId, baseStationId), ...
    "Domain", string(domain), ...
    "Direction", string(direction), ...
    "Frame", double(frameVal), ...
    "Slot", double(slotVal), ...
    "Symbol", double(symbolVal), ...
    "TimestampSim_ms", double((slotVal-slotIndexBase)*duration_s*1e3), ...
    "SlotIndexBase", double(slotIndexBase), ...
    "TimestampReference", "absolute_trial_slot_nominal_grid_not_RF_event_time", ...
    "EnergyIntervalBasis", "whole_slot_engineering_model_not_measured_RF_active_interval", ...
    "UEID", double(ueId), ...
    "CellID", double(cellId), ...
    "BaseStationID", double(baseStationId), ...
    "RNTI", double(rnti), ...
    "TransportBlockId", string(tbId), ...
    "HARQProcessId", double(harqProcessId), ...
    "NDI", double(ndi), ...
    "RV", double(rv), ...
    "PRBCount", double(prbCount), ...
    "ActiveBWFraction", double(activeBWFrac), ...
    "ActiveRank", double(activeRank), ...
    "ActiveTxRUCount", double(activeTxruCount), ...
    "ControlMonitoringLoad", double(controlMonitoringLoad), ...
    "TxPower_dBm", double(txPower_dBm), ...
    "RxPowerEst_dBm", double(rxPower_dBm), ...
    "State", string(state), ...
    "Duration_s", double(duration_s), ...
    "Power_W", double(powerW), ...
    "Energy_J", double(powerW * duration_s), ...
    "SuccessfulBits", double(successBits), ...
    "TransportGoodputKey", "", "TransportGoodputStatus", "not_data_payload", ...
    "ObservationPopulationKey", "", ...
    "PopulationBindingSource", "", ...
    "ExecutedAllocationID", "", "SourceObservationRow", NaN, ...
    "RecordedReceiverOutcomeField", "", "RecordedReceiverOutcome", NaN, ...
    "ObservationStartSample", NaN, "ObservationEndSampleExclusive", NaN, "ObservationSampleRateHz", NaN, ...
    "NativeSymbolIndex0", NaN, "ExecutedStartSample", NaN, "ExecutedEndSampleExclusive", NaN, "ExecutedSampleRateHz", NaN, ...
    "LoadSource", "", ...
    "ResourcePRBSetJSON", "", "ResourceGridPRBCount", NaN, "EndpointModelTxPower_W", NaN, ...
    "RFChainCount", double(rfChains), ...
    "BBProcessingEnergy_J", double(bbEnergyJ), ...
    "SourceArtifact", string(sourceArtifact), ...
    "Status", string(status));
end

function row = localEmptyEnergyRow()
row = struct( ...
    "Entity", "", "EntityType", "", "EntityID", NaN, "Domain", "", "Direction", "", ...
    "Frame", NaN, "Slot", NaN, "Symbol", NaN, "TimestampSim_ms", NaN, ...
    "SlotIndexBase", NaN, "TimestampReference", "", "EnergyIntervalBasis", "", ...
    "UEID", NaN, "CellID", NaN, "BaseStationID", NaN, "RNTI", NaN, ...
    "TransportBlockId", "", "HARQProcessId", NaN, "NDI", NaN, "RV", NaN, ...
    "PRBCount", NaN, "ActiveBWFraction", NaN, "ActiveRank", NaN, "ActiveTxRUCount", NaN, ...
    "ControlMonitoringLoad", NaN, "TxPower_dBm", NaN, "RxPowerEst_dBm", NaN, "State", "", ...
    "Duration_s", NaN, "Power_W", NaN, "Energy_J", NaN, "SuccessfulBits", NaN, ...
    "TransportGoodputKey", "", "TransportGoodputStatus", "not_data_payload", ...
    "ObservationPopulationKey", "", ...
    "PopulationBindingSource", "", ...
    "ExecutedAllocationID", "", "SourceObservationRow", NaN, ...
    "RecordedReceiverOutcomeField", "", "RecordedReceiverOutcome", NaN, ...
    "ObservationStartSample", NaN, "ObservationEndSampleExclusive", NaN, "ObservationSampleRateHz", NaN, ...
    "NativeSymbolIndex0", NaN, "ExecutedStartSample", NaN, "ExecutedEndSampleExclusive", NaN, "ExecutedSampleRateHz", NaN, ...
    "LoadSource", "", ...
    "ResourcePRBSetJSON", "", "ResourceGridPRBCount", NaN, "EndpointModelTxPower_W", NaN, ...
    "RFChainCount", NaN, "BBProcessingEnergy_J", NaN, "SourceArtifact", "", "Status", "");
end

function summaryT = localBuildEnergySummary(cfg, timelineT, endpointT, modelVersion)
summaryT = localEmptyProbeMetricTable();
if ~(istable(timelineT) && ~isempty(timelineT))
    summaryT = localUnavailableEnergySummary(modelVersion, "runtime_energy_timeline_empty");
    return;
end

slotDur_s = localSlotDuration(cfg);
numFrames = max(1, double(sixgr.util.structGet(cfg, "run.numFrames", 1)));
scenarioDur = localScenarioMeasurementDuration(cfg, timelineT, numFrames, slotDur_s);
[successBitsRaw, firstDeliveryCount] = localUniqueDeliveredBits(timelineT);
ueMask = string(endpointT.Entity) == "UE";
gnbMask = string(endpointT.Entity) == "gNB";
% A missing/ambiguous interval is unknown energy, not zero. Never omit NaN
% here: doing so would make incomplete modeled coverage appear complete.
ueEnergy = sum(double(endpointT.Energy_J(ueMask)));
gnbEnergy = sum(double(endpointT.Energy_J(gnbMask)));
bbEnergy = sum(double(endpointT.BBProcessingEnergy_J(gnbMask)));
rfActiveTime = sum(double(endpointT.Duration_s(gnbMask)));
activeEntityCount=max(1,numel(unique(endpointT.EntityID(gnbMask))));
activeRatio = min(max(rfActiveTime / max(scenarioDur * activeEntityCount, eps), 0), 1);
throughputMbps = (successBitsRaw / max(scenarioDur, eps)) / 1e6;
avgPowerW = (ueEnergy + gnbEnergy) / max(scenarioDur, eps);
sleepRatio = NaN;
clusteringEffect = NaN;
clusteringNote = "NOT_EVALUATED: clustering energy delta requires a matched executed baseline; one trace is not a gain.";
bandwidthAdaptMode = lower(string(sixgr.util.structGet(cfg, "lls6g.energy_efficiency.bandwidth_adaptation_mode", "none")));
bandwidthAdaptEnabled = logical(sixgr.util.structGet(cfg, "lls6g.energy_efficiency.bandwidth_adaptation_enabled", ...
    sixgr.util.structGet(cfg, "bandwidth_operation.supports_bwp_like_operation", false))) || ...
    ~(bandwidthAdaptMode == "" || any(bandwidthAdaptMode == ["none","disabled","off","false"]));
% Counterfactual sleep and bandwidth-adaptation gains require paired
% executed scenarios.  A single runtime trace cannot measure them.
bandwidthAdaptEffect = NaN;
bandwidthAdaptNote = "NOT_EVALUATED: requires a paired executed bandwidth-adaptation scenario; no proxy is emitted.";
raceToSleepGain = NaN;
raceToSleepNote = "NOT_EVALUATED: requires explicit executed sleep-state transitions and a paired baseline; no proxy is emitted.";

if successBitsRaw > 0 && isfinite(ueEnergy) && isfinite(gnbEnergy)
    ueEnergyPerBit = ueEnergy / successBitsRaw;
    gnbEnergyPerBit = gnbEnergy / successBitsRaw;
    throughputPerWatt = throughputMbps / max(avgPowerW, eps);
    energyAvailability = "AVAILABLE";
    energyNotes = "Nonoverlapping endpoint engineering-model intervals divided by unique first-success transport-block bits; not measured circuit power.";
else
    ueEnergyPerBit = NaN;
    gnbEnergyPerBit = NaN;
    throughputPerWatt = NaN;
    energyAvailability = "NOT_EVALUATED";
    if ~isfinite(ueEnergy) || ~isfinite(gnbEnergy)
        energyNotes = "Ambiguous overlapping endpoint power states; inspect energy_endpoint_timeline. No summed or maximum-power substitute is used.";
    elseif isfinite(successBitsRaw)
        energyNotes = "No successful transport-block delivery exists; energy per bit is undefined.";
    else
        energyNotes = "Incomplete receiver CRC/TB identity evidence; delivered-bit denominator is unknown, not zero.";
    end
end

summaryT = [summaryT; ... %#ok<AGROW>
    localProbeMetricRow("ue_energy_per_successful_bit", "UE", "mean", ueEnergyPerBit, "", "J/bit", energyNotes, energyAvailability, "runtime_state_conditioned_engineering_model", modelVersion); ...
    localProbeMetricRow("first_delivered_bits", "system", "total", successBitsRaw, "", "bit", "Unique first-success delivered bits used as energy denominator."); ...
    localProbeMetricRow("first_delivery_count", "system", "total", firstDeliveryCount, "", "count", "Unique first-success TB delivery events used by energy accounting."); ...
    localProbeMetricRow("measurement_window_duration", "system", "total", scenarioDur, "", "s", "Simulated measurement window used by energy and throughput-per-watt metrics."); ...
    localProbeMetricRow("ue_energy_per_slot_frame_burst", "UE", "per_frame_mean", ueEnergy / (scenarioDur/0.010), "", "J/frame", "Represented UE energy normalized to a 10 ms radio frame; partial frames are duration weighted, not counted as slots."); ...
    localProbeMetricRow("gnb_energy_per_successful_bit", "gNB", "mean", gnbEnergyPerBit, "", "J/bit", energyNotes, energyAvailability, "runtime_state_conditioned_engineering_model", modelVersion); ...
    localProbeMetricRow("gnb_active_sleep_duty_cycle", "gNB", "active_ratio", activeRatio, "", "fraction", "Mean gNB active-time ratio from the union of persisted runtime intervals per gNB."); ...
    localProbeMetricRow("gnb_active_sleep_duty_cycle", "gNB", "sleep_ratio", sleepRatio, "", "fraction", "Unobserved intervals are not executed sleep states.", "NOT_EVALUATED", "sleep_state_evidence_required", modelVersion); ...
    localProbeMetricRow("rf_chain_active_time", "gNB", "total", rfActiveTime, "", "s", "Union of gNB active runtime intervals, summed across distinct gNB entities."); ...
    localProbeMetricRow("bb_processing_energy", "gNB", "total", bbEnergy, "", "J", "Modeled TRX-chain processing energy in the RF energy model."); ...
    localProbeMetricRow("pdcch_monitoring_energy_metric", "UE", "total", localDomainEnergy(timelineT, "UE", "PDCCH_monitoring",cfg), "", "J", "Nonadditive monitoring-window modeled energy; overlaps data receive energy."); ...
    localProbeMetricRow("pdcch_monitoring_energy", "UE", "total", localDomainEnergy(timelineT, "UE", "PDCCH_monitoring",cfg), "", "J", "Nonadditive monitoring-window modeled energy; not incremental control cost."); ...
    localProbeMetricRow("ssb_pbch_common_signal_energy", "gNB", "total", localDomainEnergy(timelineT, "gNB", "SSB_PBCH",cfg), "", "J", "Nonadditive common-signal-window modeled energy; not isolated signal RF energy."); ...
    localProbeMetricRow("prach_common_channel_clustering_energy_effect", "system", "delta_j", clusteringEffect, "", "J", clusteringNote); ...
    localProbeMetricRow("bandwidth_adaptation_energy_effect", "system", "delta_j", bandwidthAdaptEffect, "", "J", bandwidthAdaptNote, "NOT_EVALUATED", "paired_counterfactual_required", modelVersion); ...
    localProbeMetricRow("race_to_sleep_gains", "system", "fractional_gain", raceToSleepGain, "", "fraction", raceToSleepNote, "NOT_EVALUATED", "paired_counterfactual_required", modelVersion); ...
    localProbeMetricRow("throughput_per_watt", "system", "mean", throughputPerWatt, "", "Mbps/W", energyNotes, energyAvailability, "runtime_state_conditioned_engineering_model", modelVersion); ...
    localProbeMetricRow("energy_delay_product", "system", "mean", (ueEnergy + gnbEnergy) * scenarioDur, "", "J*s", "Energy-delay product over the scenario runtime."); ...
    localProbeMetricRow("energy_spectral_efficiency_tradeoff", "system", "mean", localEnergySpectralEfficiency(cfg, throughputMbps, avgPowerW), "", "(bit/s/Hz)/W", "Derived from runtime delivered bits, configured bandwidth, and the explicit energy model; not a measured circuit-power quantity.", energyAvailability, "runtime_state_conditioned_engineering_model", modelVersion)];

% Record enabled policy without converting it into unexecuted savings.
summaryT(end+1,:) = localProbeMetricRow("bandwidth_adaptation_policy_enabled", "system", "configured", ...
    double(bandwidthAdaptEnabled), string(bandwidthAdaptMode), "bool", ...
    "Configuration fact only; does not claim an energy saving.", "AVAILABLE", "configuration_fact", modelVersion);
end

function [unionDuration, entityCount] = localActiveIntervalUnionByEntity(T)
unionDuration = 0;
entityCount = 1;
if ~(istable(T) && ~isempty(T))
    return;
end
if ismember("EntityID", string(T.Properties.VariableNames))
    entity = double(T.EntityID);
elseif ismember("BaseStationID", string(T.Properties.VariableNames))
    entity = double(T.BaseStationID);
else
    entity = ones(height(T), 1);
end
entity(~isfinite(entity)) = 1;
ids = unique(entity, "stable");
entityCount = max(numel(ids), 1);
for i = 1:numel(ids)
    mask = entity == ids(i);
    duration = double(T.Duration_s(mask));
    if ismember("TimestampSim_ms", string(T.Properties.VariableNames))
        startTime = double(T.TimestampSim_ms(mask)) / 1e3;
    else
        startTime = nan(size(duration));
    end
    valid = isfinite(startTime) & isfinite(duration) & duration > 0;
    if ~any(valid)
        continue;
    end
    intervals = sortrows([startTime(valid), startTime(valid) + duration(valid)], 1);
    currentStart = intervals(1, 1);
    currentEnd = intervals(1, 2);
    for row = 2:size(intervals, 1)
        if intervals(row, 1) <= currentEnd + 10 * eps(max(abs(currentEnd), 1))
            currentEnd = max(currentEnd, intervals(row, 2));
        else
            unionDuration = unionDuration + max(currentEnd - currentStart, 0);
            currentStart = intervals(row, 1);
            currentEnd = intervals(row, 2);
        end
    end
    unionDuration = unionDuration + max(currentEnd - currentStart, 0);
end
end

function value = localDomainEnergy(T, entity, domain, cfg)
mask = string(T.Entity) == string(entity) & string(T.Domain) == string(domain);
resolved=sixgr.truth.resolveLLSEnergyModelConfig(cfg,RFInventoryPolicy="bind_declared_inventory");
intervals=sixgr.truth.integrateLLSEndpointEnergy(T(mask,:),resolved.ModelConfig);
value = sum(double(intervals.Energy_J));
end

function key=localPopulationKey(T,i,tb)
% Nominal radio slots can repeat across independent executions/sweep points.
% Never union them as simultaneous observations in one physical clock.
key="";
for name=["RunID","ExecutionID","SweepPointIndex","SweepRealizationIndex"]
    raw=string(localTableValue(T,i,"EnergyScope_"+name,localTableValue(T,i,name,"")));
    if ~isscalar(raw) || ismissing(raw), raw=""; end
    key=key+"|"+name+"="+raw;
end
if startsWith(tb,"FIXED|")
    key=key+"|"+tb+"|attempt="+string(localNumericField(T,i, ...
        ["FixedLinkAttemptIndex","AttemptIndex","HARQTransmissionNumber","RV"],0));
end
end

function raw=localBindSinglePopulationScope(raw)
% Join optional identity columns only when the supplied raw population has
% exactly one explicit value. This repairs sparse channel schemas without
% guessing a sweep identity when several independent points are present.
domains=["DL","UL","PDCCH","PBCH","PRACH","PUCCH","SRS","CSIRS","TRS","CommonEnergyObservations"];
for field=["RunID","ExecutionID","SweepPointIndex","SweepRealizationIndex"]
    values=strings(0,1);
    for domain=domains
        T=sixgr.util.structGet(raw,domain,table());
        if ~istable(T)||isempty(T)||~ismember(field,string(T.Properties.VariableNames)), continue; end
        current=string(T.(field));
        present=~ismissing(current)&strlength(strtrim(current))>0&lower(current)~="nan";
        values=[values;current(present)]; %#ok<AGROW>
    end
    values=unique(values);
    if numel(values)~=1, continue; end
    for domain=domains
        T=sixgr.util.structGet(raw,domain,table());
        if ~istable(T)||isempty(T), continue; end
        if ~ismember(field,string(T.Properties.VariableNames))
            current=repmat(values,height(T),1);
            filled=true(height(T),1);
        else
            current=string(T.(field));
            filled=ismissing(current)|strlength(strtrim(current))==0|lower(current)=="nan";
            current(filled)=values;
        end
        % A model-only join must never rewrite the scientific identity
        % columns which own already-issued causal transport-goodput credit.
        T.("EnergyScope_"+field)=current;
        if any(filled)
            if ~ismember("EnergyPopulationBindingSource",string(T.Properties.VariableNames))
                T.EnergyPopulationBindingSource=repmat("retained_row_identity",height(T),1);
            end
            T.EnergyPopulationBindingSource(filled)=T.EnergyPopulationBindingSource(filled)+ ...
                "|"+field+":unique_explicit_value_in_supplied_raw_population";
        end
        raw.(domain)=T;
    end
end
end

function value = localEnergySpectralEfficiency(cfg, throughputMbps, avgPowerW)
bwHz = double(sixgr.util.structGet(cfg, "channel.bandwidth_Hz", NaN));
if ~(isfinite(bwHz) && bwHz > 0)
    value = NaN;
    return;
end
spectralEfficiency = (throughputMbps * 1e6) / bwHz;
value = spectralEfficiency / max(avgPowerW, eps);
end

function durationSec = localScenarioMeasurementDuration(cfg, timelineT, numFrames, slotDur_s)
% Fixed-link points are independent waveform observations. They intentionally
% reuse frame/slot coordinates, so configured slot count and max timestamp
% undercount the actual energy observation duration. Count every distinct
% transmitter-side fixed-link TB once before considering connected-runtime
% time axes.
if localHasFixedLinkObservationIdentity(timelineT)
    durationSec = localUniqueTransmitterObservationDuration(timelineT);
    if isfinite(durationSec) && durationSec > 0
        return;
    end
end
durationSec = double(sixgr.util.structGet(cfg, "run.measurementWindow_s", ...
    sixgr.util.structGet(cfg, "simulation.measurementWindow_s", NaN)));
if isfinite(durationSec) && durationSec > 0
    return;
end
totalSlots = double(sixgr.util.structGet(cfg, "run.totalSlots", ...
    sixgr.util.structGet(cfg, "run.numTTI", NaN)));
if isfinite(totalSlots) && totalSlots > 0
    durationSec = totalSlots * slotDur_s;
    return;
end
if istable(timelineT) && ~isempty(timelineT) && all(ismember(["TimestampSim_ms","Duration_s"], string(timelineT.Properties.VariableNames)))
    endTimes = double(timelineT.TimestampSim_ms) ./ 1e3 + double(timelineT.Duration_s);
    endTimes = endTimes(isfinite(endTimes) & endTimes >= 0);
    if ~isempty(endTimes)
        durationSec = max(endTimes);
        if isfinite(durationSec) && durationSec > 0
            return;
        end
    end
end
durationSec = max(numFrames * slotDur_s, sum(double(timelineT.Duration_s(string(timelineT.Entity) == "gNB")), "omitnan"));
end

function tf = localHasFixedLinkObservationIdentity(T)
tf = istable(T) && ~isempty(T) && ismember("TransportBlockId", string(T.Properties.VariableNames)) && ...
    any(startsWith(upper(strtrim(string(T.TransportBlockId))), "FIXED|"));
end

function durationSec = localUniqueTransmitterObservationDuration(T)
durationSec = 0;
if ~(istable(T) && ~isempty(T))
    return;
end
txMask = (upper(string(T.Direction)) == "DL" & string(T.Entity) == "gNB") | ...
    (upper(string(T.Direction)) == "UL" & string(T.Entity) == "UE");
% Per-symbol rows are attribution, not independent waveform trials. Union
% all of an exposure's intervals instead of taking only its first symbol.
% ObservationPopulationKey also retains the independent HARQ-attempt scope.
indices=find(txMask); keys=strings(numel(indices),1);
for k=1:numel(indices)
    i=indices(k);
    keys(k)=string(T.ObservationPopulationKey(i))+"|"+localEnergyDeliveryKey(T,i)+ ...
        "|"+localIdentityNumericToken(T.EntityID(i))+"|"+string(T.Direction(i));
end
assert(~any(ismissing(keys)),'sixgr:truth:MissingFixedEnergyIdentity', ...
    'Independent exposure identity must not collapse to a missing string.');
for key=reshape(unique(keys,'stable'),1,[])
    ids=indices(keys==key);
    intervals=sortrows([double(T.TimestampSim_ms(ids))/1000, ...
        double(T.TimestampSim_ms(ids))/1000+double(T.Duration_s(ids))]);
    assert(all(isfinite(intervals),'all') && all(intervals(:,2)>intervals(:,1)), ...
        'sixgr:truth:InvalidFixedEnergyInterval','Independent exposure needs valid actual intervals.');
    start=intervals(1,1); stop=intervals(1,2);
    for k=2:size(intervals,1)
        if intervals(k,1)<=stop
            stop=max(stop,intervals(k,2));
        else
            durationSec=durationSec+stop-start;
            start=intervals(k,1); stop=intervals(k,2);
        end
    end
    durationSec=durationSec+stop-start;
end
end

function [bits, count] = localUniqueDeliveredBits(timelineT)
bits = 0;
count = 0;
if ~(istable(timelineT) && ~isempty(timelineT))
    return;
end
txMask = (upper(string(timelineT.Direction)) == "DL" & string(timelineT.Entity) == "gNB") | ...
    (upper(string(timelineT.Direction)) == "UL" & string(timelineT.Entity) == "UE");
dataMask=ismember(string(timelineT.Domain),["DL_data","UL_data"]);
if any(isnan(double(timelineT.SuccessfulBits(txMask & dataMask))))
    bits=NaN; count=NaN; return;
end
success = double(timelineT.SuccessfulBits) > 0 & txMask & dataMask;
if ~any(success)
    return;
end
seen = strings(0, 1);
idx = find(success(:).');
for k = 1:numel(idx)
    i = idx(k);
    key = string(timelineT.TransportGoodputKey(i));
    assert(~ismissing(key)&&strlength(key)>0, ...
        'sixgr:truth:MissingEnergyDeliveryIdentity','Positive delivery needs receiver-owned TB credit.');
    if any(seen == key)
        continue;
    end
    seen(end+1, 1) = key; %#ok<AGROW>
    bits = bits + double(timelineT.SuccessfulBits(i));
    count = count + 1;
end
end

function key = localEnergyDeliveryKey(T, i)
tb = string(T.TransportBlockId(i));
if ~ismissing(tb) && strlength(strtrim(tb)) > 0 && lower(strtrim(tb)) ~= "nan"
    key = tb;
    return;
end
key = upper(string(T.Direction(i))) + "_ue" + localIdentityNumericToken(T.UEID(i)) + ...
    "_rnti" + localIdentityNumericToken(T.RNTI(i)) + ...
    "_harq" + localIdentityNumericToken(T.HARQProcessId(i)) + ...
    "_ndi" + localIdentityNumericToken(T.NDI(i)) + ...
    "_f" + localIdentityNumericToken(T.Frame(i)) + ...
    "_s" + localIdentityNumericToken(T.Slot(i));
end

function T = localResolveTrialTable(v)
if istable(v)
    T = v;
else
    T = table();
end
end

function value = localTableValue(T, rowIdx, varName, defaultValue)
value = defaultValue;
if ~(istable(T) && rowIdx >= 1 && rowIdx <= height(T) && ismember(varName, string(T.Properties.VariableNames)))
    return;
end
value = T.(varName)(rowIdx);
end

function value = localOptionalScalar(T, rowIdx, varName, defaultValue)
value = defaultValue;
if ~(istable(T) && rowIdx >= 1 && rowIdx <= height(T) && ismember(varName, string(T.Properties.VariableNames)))
    return;
end
raw = T.(varName)(rowIdx);
if iscell(raw)
    raw = raw{1};
end
numeric = str2double(string(raw));
if isfinite(numeric)
    value = double(numeric);
elseif isnumeric(raw) || islogical(raw)
    value = double(raw);
end
end

function value = localNumericField(T, rowIdx, names, defaultValue)
value = defaultValue;
for name = reshape(string(names), 1, [])
    candidate = localOptionalScalar(T, rowIdx, char(name), NaN);
    if isfinite(candidate)
        value = candidate;
        return;
    end
end
end

function tbId = localTransportBlockId(T, rowIdx, direction)
% Fixed-link campaign points are independent waveform executions but reuse
% frame/slot/HARQ coordinates. Build their identity from the persisted
% campaign hierarchy before consulting connected-runtime TB/grant IDs.
fixedPoint = localNumericField(T, rowIdx, ["FixedLinkPointIndex"], NaN);
fixedTrial = localNumericField(T, rowIdx, ["FixedLinkTrialIndex"], NaN);
if localNumericField(T,rowIdx,"FixedLinkCampaign",0)==1 && ...
        isfinite(fixedPoint) && isfinite(fixedTrial)
    fixedDrop = localNumericField(T, rowIdx, ["FixedLinkDropIndex"], 1);
    fixedSeedIndex = localNumericField(T, rowIdx, ["FixedLinkSeedIndex"], 1);
    fixedSeedValue = localNumericField(T, rowIdx, ["FixedLinkSeedValue","PointSeed"], NaN);
    ueId = localNumericField(T, rowIdx, ["UEID","UEIndex"], NaN);
    rnti = localNumericField(T, rowIdx, ["RNTI","UEID","UEIndex"], NaN);
    tbId = "FIXED|" + upper(string(direction)) + ...
        "|point=" + localIdentityNumericToken(fixedPoint) + ...
        "|drop=" + localIdentityNumericToken(fixedDrop) + ...
        "|trial=" + localIdentityNumericToken(fixedTrial) + ...
        "|seed_index=" + localIdentityNumericToken(fixedSeedIndex) + ...
        "|seed=" + localIdentityNumericToken(fixedSeedValue) + ...
        "|ue=" + localIdentityNumericToken(ueId) + ...
        "|rnti=" + localIdentityNumericToken(rnti);
    return;
end
tbId="";
for name = ["LogicalTBID","TransportBlockId","TBId"]
    if istable(T) && ismember(name, string(T.Properties.VariableNames))
        value=T.(char(name))(rowIdx,:);
        if iscell(value), value=value{1}; end
        if ~(isstring(value)||ischar(value)), continue; end
        raw = strtrim(string(value));
        if ~ismissing(raw) && strlength(raw) > 0 && lower(raw) ~= "nan"
            tbId = raw;
            return;
        end
    end
end

end

function token = localIdentityNumericToken(value)
value = double(value);
if ~(isscalar(value) && isfinite(value))
    token = "na";
elseif abs(value - round(value)) <= eps(max(1, abs(value))) * 4
    token = string(sprintf('%.0f', value));
else
    token = string(sprintf('%.17g', value));
end
end

function token = localEntityTypeToken(entity)
entity = upper(string(entity));
if entity == "UE"
    token = "ue";
else
    token = "cell";
end
end

function entityID = localEntityID(entity, ueId, cellId, baseStationId)
entity = upper(string(entity));
if entity == "UE"
    entityID = double(ueId);
elseif isfinite(cellId)
    entityID = double(cellId);
else
    entityID = double(baseStationId);
end
end

function load = localControlMonitoringLoad(domain)
domain = upper(string(domain));
if contains(domain, "PDCCH") || contains(domain, "PUCCH")
    load = 1;
else
    load = 0;
end
end

function state = localUEEnergyState(domain, direction, entity)
domain = upper(string(domain));
direction = upper(string(direction));
entity = upper(string(entity));
if entity ~= "UE"
    if direction == "DL"
        state = "active_tx";
    else
        state = "active_rx";
    end
    return;
end
if contains(domain, "PDCCH")
    state = "monitor_only";
elseif direction == "DL"
    state = "active_rx";
else
    state = "active_tx";
end
end

function dbm = localWToDbm(powerW)
if ~(isfinite(powerW) && powerW > 0)
    dbm = NaN;
    return;
end
dbm = 10 * log10(double(powerW) / 1e-3);
end

function watts = localdBmToW(dbm)
watts = 1e-3 * 10.^(double(dbm) / 10);
end

function slotDur_s = localSlotDuration(cfg)
slotDur_s = sixgr.time.slotDurationSec(cfg);
end

function T = localEmptyProbeMetricTable()
T = table('Size', [0 10], ...
    'VariableTypes', {'string','string','string','double','string','string','string','string','string','string'}, ...
    'VariableNames', {'MetricKey','Entity','Statistic','Value','TextValue','Unit','Notes', ...
    'Availability','EvidenceType','ModelVersion'});
end

function T = localProbeMetricRow(metricKey, entity, statistic, value, textValue, unit, notes, availability, evidenceType, modelVersion)
if nargin < 8 || strlength(strtrim(string(availability))) == 0
    if isfinite(double(value))
        availability = "AVAILABLE";
    else
        availability = "NOT_EVALUATED";
    end
end
if nargin < 9 || strlength(strtrim(string(evidenceType))) == 0
    evidenceType = "runtime_state_conditioned_engineering_model";
end
if nargin < 10 || strlength(strtrim(string(modelVersion))) == 0
    modelVersion = "lls_energy_accounting_v2";
end
if strlength(strtrim(string(textValue))) == 0 && isfinite(double(value))
    textValue = sprintf('%.12g', double(value));
end
T = table(string(metricKey), string(entity), string(statistic), double(value), string(textValue), string(unit), string(notes), ...
    string(availability), string(evidenceType), string(modelVersion), ...
    'VariableNames', {'MetricKey','Entity','Statistic','Value','TextValue','Unit','Notes', ...
    'Availability','EvidenceType','ModelVersion'});
end

function T = localUnavailableEnergySummary(modelVersion, reason)
T = [ ...
    localProbeMetricRow("ue_energy_per_successful_bit", "UE", "mean", NaN, "", "J/bit", ...
        string(reason), "NOT_EVALUATED", "unavailable", modelVersion); ...
    localProbeMetricRow("gnb_energy_per_successful_bit", "gNB", "mean", NaN, "", "J/bit", ...
        string(reason), "NOT_EVALUATED", "unavailable", modelVersion)];
end
