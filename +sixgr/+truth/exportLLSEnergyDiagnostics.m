function artifacts = exportLLSEnergyDiagnostics(cfg, airInterfaceRunFolder, rawTrials)
%EXPORTLLSENERGYDIAGNOSTICS Emit measured/model-backed RF and energy tables for LLS.

artifacts = struct("CSV", "", "TimelineCSV", "", "ModelTermsCSV", "", ...
    "SummaryTable", table(), "TimelineTable", table(), "ModelTermsTable", table(), ...
    "Available", false, "FailureReason", "");

rootRunFolder = fileparts(char(string(airInterfaceRunFolder)));
layout = sixgr.report.resultLayout(rootRunFolder);
sixgr.util.ensureFolder(layout.RFCSVDir);

model = sixgr.truth.resolveLLSEnergyModelConfig(cfg);
modelTermsPath = fullfile(layout.RFCSVDir, "energy_model_terms.csv");
sixgr.util.csvWriteTable(modelTermsPath, model.TermTable);
artifacts.ModelTermsCSV = modelTermsPath;
artifacts.ModelTermsTable = model.TermTable;
artifacts.Available = logical(model.Available);
artifacts.FailureReason = string(model.FailureReason);

if model.Available
    timelineT = localBuildEnergyTimeline(cfg, rawTrials, model.ModelConfig, model.ModelVersion);
    summaryT = localBuildEnergySummary(cfg, timelineT, model.ModelVersion);
else
    timelineT = table();
    summaryT = localUnavailableEnergySummary(model.ModelVersion, model.FailureReason);
end
summaryT = sixgr.truth.finalizeProbeMetricTable(summaryT);

timelinePath = fullfile(layout.RFCSVDir, "energy_timeline_trace.csv");
summaryPath = fullfile(layout.RFCSVDir, "probe_rf_energy.csv");
sixgr.util.csvWriteTable(timelinePath, timelineT);
sixgr.util.csvWriteTable(summaryPath, summaryT);

artifacts.CSV = summaryPath;
artifacts.TimelineCSV = timelinePath;
artifacts.SummaryTable = summaryT;
artifacts.TimelineTable = timelineT;
end

function timelineT = localBuildEnergyTimeline(cfg, rawTrials, modelCfg, modelVersion)
ueModel = sixgr.rf.EnergyModelUE(modelCfg);
bsModel = sixgr.rf.EnergyModelBS(modelCfg);
slotDur_s = localSlotDuration(cfg);
bsRfChains = double(sixgr.util.structGet(modelCfg, "powerAndRF.bsRFChainCount", NaN));
ueRfChains = double(sixgr.util.structGet(modelCfg, "powerAndRF.ueRFChainCount", NaN));
bsTxPowerW = localdBmToW(double(sixgr.util.structGet(modelCfg, "powerAndRF.bsTxPower_dBm", NaN)));
ueTxPowerW = localdBmToW(double(sixgr.util.structGet(modelCfg, "powerAndRF.ueTxPower_dBm", NaN)));
totalRBs = max(1, double(sixgr.util.structGet(cfg, "phy.carrier.NSizeGrid", 1)));

rows = repmat(localEmptyEnergyRow(), 0, 1);
rows = [rows; localBuildRowsForTable(localResolveTrialTable(sixgr.util.structGet(rawTrials, "DL", table())), "DL_data", "DL", slotDur_s, totalRBs, bsRfChains, ueRfChains, bsModel, ueModel, bsTxPowerW, ueTxPowerW, "air_interface/csv/dl_pdsch_trials.csv")]; %#ok<AGROW>
rows = [rows; localBuildRowsForTable(localResolveTrialTable(sixgr.util.structGet(rawTrials, "UL", table())), "UL_data", "UL", slotDur_s, totalRBs, bsRfChains, ueRfChains, bsModel, ueModel, bsTxPowerW, ueTxPowerW, "air_interface/csv/ul_pusch_trials.csv")]; %#ok<AGROW>
rows = [rows; localBuildRowsForTable(localResolveTrialTable(sixgr.util.structGet(rawTrials, "PDCCH", table())), "PDCCH_monitoring", "DL", slotDur_s, totalRBs, bsRfChains, ueRfChains, bsModel, ueModel, bsTxPowerW, ueTxPowerW, "air_interface/csv/pdcch_trials.csv")]; %#ok<AGROW>
rows = [rows; localBuildRowsForTable(localResolveTrialTable(sixgr.util.structGet(rawTrials, "PBCH", table())), "SSB_PBCH", "DL", slotDur_s, totalRBs, bsRfChains, ueRfChains, bsModel, ueModel, bsTxPowerW, ueTxPowerW, "air_interface/csv/pbch_trials.csv")]; %#ok<AGROW>
rows = [rows; localBuildRowsForTable(localResolveTrialTable(sixgr.util.structGet(rawTrials, "PRACH", table())), "PRACH", "UL", slotDur_s, totalRBs, bsRfChains, ueRfChains, bsModel, ueModel, bsTxPowerW, ueTxPowerW, "air_interface/csv/prach_trials.csv")]; %#ok<AGROW>
rows = [rows; localBuildRowsForTable(localResolveTrialTable(sixgr.util.structGet(rawTrials, "PUCCH", table())), "PUCCH", "UL", slotDur_s, totalRBs, bsRfChains, ueRfChains, bsModel, ueModel, bsTxPowerW, ueTxPowerW, "air_interface/csv/pucch_trials.csv")]; %#ok<AGROW>
rows = [rows; localBuildRowsForTable(localResolveTrialTable(sixgr.util.structGet(rawTrials, "SRS", table())), "SRS", "UL", slotDur_s, totalRBs, bsRfChains, ueRfChains, bsModel, ueModel, bsTxPowerW, ueTxPowerW, "air_interface/csv/srs_trials.csv")]; %#ok<AGROW>

if isempty(rows)
    timelineT = table();
else
    timelineT = struct2table(rows);
    timelineT.EnergyModelVersion = repmat(string(modelVersion), height(timelineT), 1);
    timelineT.EvidenceType = repmat("runtime_state_conditioned_engineering_model", height(timelineT), 1);
    timelineT.Availability = repmat("AVAILABLE", height(timelineT), 1);
    timelineT.PowerEquation = repmat("configured_state_power_w*observed_interval_s", height(timelineT), 1);
end
end

function rows = localBuildRowsForTable(T, domain, direction, slotDur_s, totalRBs, bsRfChains, ueRfChains, bsModel, ueModel, bsTxPowerW, ueTxPowerW, sourceArtifact)
rows = repmat(localEmptyEnergyRow(), 0, 1);
if ~(istable(T) && ~isempty(T))
    return;
end

for i = 1:height(T)
    load = 1;
    prbCount = localNumericField(T, i, ["PRBs","AllocatedPRBCount","PRBCount"], NaN);
    if isfinite(prbCount)
        load = min(max(double(prbCount) / totalRBs, 0), 1);
    end
    status = string(localTableValue(T, i, "Status", "NA"));
    successBits = 0;
    tbBits = localNumericField(T, i, ["TBSize_bits","TBSBits","BitsCompared"], NaN);
    if status == "PASS" && isfinite(tbBits)
        successBits = double(tbBits);
    end
    frameVal = double(localTableValue(T, i, "Frame", i));
    slotVal = double(localTableValue(T, i, "Slot", i));
    symbolVal = localNumericField(T, i, ["SymbolStart"], NaN);
    ueId = localNumericField(T, i, ["UEID","UEIndex"], NaN);
    cellId = localNumericField(T, i, ["CellID","BaseStationID"], NaN);
    baseStationId = localNumericField(T, i, ["BaseStationID","CellID"], NaN);
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
        rxPower_dBm = localNumericField(T, i, ["ServingRSRP_dBm","CSI_RSRP_dB","RSRP_dBm"], NaN);
    else
        txPower_dBm = localOptionalScalar(T, i, "TxPower_dBm", NaN);
        if ~isfinite(txPower_dBm)
            txPower_dBm = localOptionalScalar(T, i, "ConfiguredTxPower_dBm", NaN);
        end
        if ~isfinite(txPower_dBm)
            txPower_dBm = localWToDbm(ueTxPowerW);
        end
        rxPower_dBm = localNumericField(T, i, ["ReceivedPower_dBm","RxPower_dBm","ServingRSRP_dBm"], NaN);
    end
    switch upper(string(direction))
        case "DL"
            bs = bsModel.power('active', bsRfChains, load, bsTxPowerW);
            ue = ueModel.power('rx', 0);
            rows(end+1, 1) = localMakeEnergyRow("gNB", domain, direction, frameVal, slotVal, symbolVal, slotDur_s, bs.totalW, successBits, bsRfChains, bs.trxW * slotDur_s, sourceArtifact, status, ... %#ok<AGROW>
                ueId, cellId, baseStationId, rnti, tbId, harqProcessId, ndi, rv, prbCount, load, layers, bsRfChains, 1, txPower_dBm, NaN, "active_tx");
            rows(end+1, 1) = localMakeEnergyRow("UE", domain, direction, frameVal, slotVal, symbolVal, slotDur_s, ue.totalW, successBits, ueRfChains, 0, sourceArtifact, status, ... %#ok<AGROW>
                ueId, cellId, baseStationId, rnti, tbId, harqProcessId, ndi, rv, prbCount, load, layers, 0, localControlMonitoringLoad(domain), NaN, rxPower_dBm, localUEEnergyState(domain, direction, "UE"));
        otherwise
            ue = ueModel.power('tx', ueTxPowerW);
            bs = bsModel.power('active', bsRfChains, load, 0);
            rows(end+1, 1) = localMakeEnergyRow("UE", domain, direction, frameVal, slotVal, symbolVal, slotDur_s, ue.totalW, successBits, ueRfChains, 0, sourceArtifact, status, ... %#ok<AGROW>
                ueId, cellId, baseStationId, rnti, tbId, harqProcessId, ndi, rv, prbCount, load, layers, ueRfChains, localControlMonitoringLoad(domain), txPower_dBm, NaN, localUEEnergyState(domain, direction, "UE"));
            rows(end+1, 1) = localMakeEnergyRow("gNB", domain, direction, frameVal, slotVal, symbolVal, slotDur_s, bs.totalW, successBits, bsRfChains, bs.trxW * slotDur_s, sourceArtifact, status, ... %#ok<AGROW>
                ueId, cellId, baseStationId, rnti, tbId, harqProcessId, ndi, rv, prbCount, load, layers, 0, 0, NaN, rxPower_dBm, "active_rx");
    end
end
end

function row = localMakeEnergyRow(entity, domain, direction, frameVal, slotVal, symbolVal, duration_s, powerW, successBits, rfChains, bbEnergyJ, sourceArtifact, status, ueId, cellId, baseStationId, rnti, tbId, harqProcessId, ndi, rv, prbCount, activeBWFrac, activeRank, activeTxruCount, controlMonitoringLoad, txPower_dBm, rxPower_dBm, state)
row = struct( ...
    "Entity", string(entity), ...
    "EntityType", localEntityTypeToken(entity), ...
    "EntityID", localEntityID(entity, ueId, cellId, baseStationId), ...
    "Domain", string(domain), ...
    "Direction", string(direction), ...
    "Frame", double(frameVal), ...
    "Slot", double(slotVal), ...
    "Symbol", double(symbolVal), ...
    "TimestampSim_ms", double(((max(frameVal, 1) - 1) * 1e1) + ((max(slotVal, 1) - 1) * duration_s * 1e3)), ...
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
    "RFChainCount", double(rfChains), ...
    "BBProcessingEnergy_J", double(bbEnergyJ), ...
    "SourceArtifact", string(sourceArtifact), ...
    "Status", string(status));
end

function row = localEmptyEnergyRow()
row = struct( ...
    "Entity", "", "EntityType", "", "EntityID", NaN, "Domain", "", "Direction", "", ...
    "Frame", NaN, "Slot", NaN, "Symbol", NaN, "TimestampSim_ms", NaN, ...
    "UEID", NaN, "CellID", NaN, "BaseStationID", NaN, "RNTI", NaN, ...
    "TransportBlockId", "", "HARQProcessId", NaN, "NDI", NaN, "RV", NaN, ...
    "PRBCount", NaN, "ActiveBWFraction", NaN, "ActiveRank", NaN, "ActiveTxRUCount", NaN, ...
    "ControlMonitoringLoad", NaN, "TxPower_dBm", NaN, "RxPowerEst_dBm", NaN, "State", "", ...
    "Duration_s", NaN, "Power_W", NaN, "Energy_J", NaN, "SuccessfulBits", NaN, ...
    "RFChainCount", NaN, "BBProcessingEnergy_J", NaN, "SourceArtifact", "", "Status", "");
end

function summaryT = localBuildEnergySummary(cfg, timelineT, modelVersion)
summaryT = localEmptyProbeMetricTable();
if ~(istable(timelineT) && ~isempty(timelineT))
    summaryT = localUnavailableEnergySummary(modelVersion, "runtime_energy_timeline_empty");
    return;
end

slotDur_s = localSlotDuration(cfg);
numFrames = max(1, double(sixgr.util.structGet(cfg, "run.numFrames", 1)));
scenarioDur = localScenarioMeasurementDuration(cfg, timelineT, numFrames, slotDur_s);
[successBitsRaw, firstDeliveryCount] = localUniqueDeliveredBits(timelineT);
ueMask = string(timelineT.Entity) == "UE";
gnbMask = string(timelineT.Entity) == "gNB";
ueEnergy = sum(double(timelineT.Energy_J(ueMask)), "omitnan");
gnbEnergy = sum(double(timelineT.Energy_J(gnbMask)), "omitnan");
bbEnergy = sum(double(timelineT.BBProcessingEnergy_J(gnbMask)), "omitnan");
if localHasFixedLinkObservationIdentity(timelineT)
    % Fixed-link campaign observations are independent executions that may
    % intentionally reuse the same frame/slot coordinates.  Their durations
    % are sequential campaign exposure, not overlapping connected-runtime
    % intervals.
    rfActiveTime = sum(double(timelineT.Duration_s(gnbMask)), "omitnan");
    activeEntityCount = 1;
else
    % Connected-runtime rows are emitted per UE and per PHY domain.  Several
    % rows can therefore describe the same gNB being active in one interval.
    % A duty cycle is wall-clock occupancy, so use the union of intervals per
    % gNB rather than summing simultaneous MU-MIMO/control observations.
    [rfActiveTime, activeEntityCount] = localActiveIntervalUnionByEntity( ...
        timelineT(gnbMask, :));
end
activeRatio = min(max(rfActiveTime / max(scenarioDur * activeEntityCount, eps), 0), 1);
throughputMbps = (successBitsRaw / max(scenarioDur, eps)) / 1e6;
avgPowerW = (ueEnergy + gnbEnergy) / max(scenarioDur, eps);
sleepRatio = 1 - activeRatio;
clusteringEnabled = logical(sixgr.util.structGet(cfg, "lls6g.energy_efficiency.common_signal_clustering_enabled", ...
    sixgr.util.structGet(cfg, "signals_and_channels_common.common_signal_clustering.enable_flag", false))) || ...
    logical(sixgr.util.structGet(cfg, "lls6g.random_access.beam_clustering_enabled", false)) || ...
    logical(sixgr.util.structGet(cfg, "lls6g.random_access.ro_clustering_enabled", false));
clusteringEffect = 0;
clusteringNote = "Common-signal clustering disabled; energy delta is zero by construction.";
if clusteringEnabled
    clusteringEffect = localDomainEnergy(timelineT, "gNB", "SSB_PBCH") + localDomainEnergy(timelineT, "gNB", "PRACH");
    clusteringNote = "Measured common-signal and PRACH energy while clustering is enabled.";
end
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

if successBitsRaw > 0
    ueEnergyPerBit = ueEnergy / successBitsRaw;
    gnbEnergyPerBit = gnbEnergy / successBitsRaw;
    throughputPerWatt = throughputMbps / max(avgPowerW, eps);
    energyAvailability = "AVAILABLE";
    energyNotes = "Runtime-conditioned configured energy model divided by unique first-success transport-block bits.";
else
    ueEnergyPerBit = NaN;
    gnbEnergyPerBit = NaN;
    throughputPerWatt = NaN;
    energyAvailability = "NOT_EVALUATED";
    energyNotes = "No successful transport-block delivery exists; energy per bit is undefined.";
end

summaryT = [summaryT; ... %#ok<AGROW>
    localProbeMetricRow("ue_energy_per_successful_bit", "UE", "mean", ueEnergyPerBit, "", "J/bit", energyNotes, energyAvailability, "runtime_state_conditioned_engineering_model", modelVersion); ...
    localProbeMetricRow("first_delivered_bits", "system", "total", successBitsRaw, "", "bit", "Unique first-success delivered bits used as energy denominator."); ...
    localProbeMetricRow("first_delivery_count", "system", "total", firstDeliveryCount, "", "count", "Unique first-success TB delivery events used by energy accounting."); ...
    localProbeMetricRow("measurement_window_duration", "system", "total", scenarioDur, "", "s", "Simulated measurement window used by energy and throughput-per-watt metrics."); ...
    localProbeMetricRow("ue_energy_per_slot_frame_burst", "UE", "per_frame_mean", ueEnergy / numFrames, "", "J/frame", "Average UE energy per frame."); ...
    localProbeMetricRow("gnb_energy_per_successful_bit", "gNB", "mean", gnbEnergyPerBit, "", "J/bit", energyNotes, energyAvailability, "runtime_state_conditioned_engineering_model", modelVersion); ...
    localProbeMetricRow("gnb_active_sleep_duty_cycle", "gNB", "active_ratio", activeRatio, "", "fraction", "Mean gNB active-time ratio from the union of persisted runtime intervals per gNB."); ...
    localProbeMetricRow("gnb_active_sleep_duty_cycle", "gNB", "sleep_ratio", sleepRatio, "", "fraction", "Residual mean gNB time not occupied by persisted active runtime intervals."); ...
    localProbeMetricRow("rf_chain_active_time", "gNB", "total", rfActiveTime, "", "s", "Union of gNB active runtime intervals, summed across distinct gNB entities."); ...
    localProbeMetricRow("bb_processing_energy", "gNB", "total", bbEnergy, "", "J", "Modeled TRX-chain processing energy in the RF energy model."); ...
    localProbeMetricRow("pdcch_monitoring_energy_metric", "UE", "total", localDomainEnergy(timelineT, "UE", "PDCCH_monitoring"), "", "J", "UE receive energy while monitoring PDCCH."); ...
    localProbeMetricRow("pdcch_monitoring_energy", "UE", "total", localDomainEnergy(timelineT, "UE", "PDCCH_monitoring"), "", "J", "UE receive energy while monitoring PDCCH."); ...
    localProbeMetricRow("ssb_pbch_common_signal_energy", "gNB", "total", localDomainEnergy(timelineT, "gNB", "SSB_PBCH"), "", "J", "gNB common-signal transmit energy."); ...
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

function value = localDomainEnergy(T, entity, domain)
mask = string(T.Entity) == string(entity) & string(T.Domain) == string(domain);
value = sum(double(T.Energy_J(mask)), "omitnan");
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
seen = strings(0, 1);
for i = find(txMask(:).')
    key = localEnergyDeliveryKey(T, i);
    if any(seen == key)
        continue;
    end
    duration = double(T.Duration_s(i));
    if ~(isfinite(duration) && duration > 0)
        continue;
    end
    seen(end+1, 1) = key; %#ok<AGROW>
    durationSec = durationSec + duration;
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
success = double(timelineT.SuccessfulBits) > 0 & txMask;
if ~any(success)
    return;
end
seen = strings(0, 1);
idx = find(success(:).');
for k = 1:numel(idx)
    i = idx(k);
    key = localEnergyDeliveryKey(timelineT, i);
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
if isfinite(fixedPoint) && isfinite(fixedTrial)
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
for name = ["TransportBlockId","TBId","MACPDUId","MACSDUId","GrantContextId"]
    if istable(T) && ismember(name, string(T.Properties.VariableNames))
        raw = strtrim(string(T.(char(name))(rowIdx)));
        if ~ismissing(raw) && strlength(raw) > 0 && lower(raw) ~= "nan"
            tbId = raw;
            return;
        end
    end
end
ueId = localNumericField(T, rowIdx, ["UEID","UEIndex"], NaN);
rnti = localNumericField(T, rowIdx, ["RNTI","UEID","UEIndex"], NaN);
harqProcessId = localNumericField(T, rowIdx, ["HARQProcessId","HARQProcess"], NaN);
ndi = localNumericField(T, rowIdx, ["NDI","HARQNDI"], NaN);
frameVal = double(localTableValue(T, rowIdx, "Frame", rowIdx));
slotVal = double(localTableValue(T, rowIdx, "Slot", rowIdx));
tbId = upper(string(direction)) + "_ue" + localIdentityNumericToken(ueId) + ...
    "_rnti" + localIdentityNumericToken(rnti) + ...
    "_harq" + localIdentityNumericToken(harqProcessId) + ...
    "_ndi" + localIdentityNumericToken(ndi) + ...
    "_f" + localIdentityNumericToken(frameVal) + ...
    "_s" + localIdentityNumericToken(slotVal);
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
