function artifacts = exportLLSEnergyDiagnostics(cfg, airInterfaceRunFolder, rawTrials)
%EXPORTLLSENERGYDIAGNOSTICS Emit measured/model-backed RF and energy tables for LLS.

artifacts = struct("CSV", "", "TimelineCSV", "", "SummaryTable", table(), "TimelineTable", table());

rootRunFolder = fileparts(char(string(airInterfaceRunFolder)));
layout = sixgr.report.resultLayout(rootRunFolder);
sixgr.util.ensureFolder(layout.RFCSVDir);

timelineT = localBuildEnergyTimeline(cfg, rawTrials);
if isempty(timelineT)
    return;
end
summaryT = localBuildEnergySummary(cfg, timelineT);
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

function timelineT = localBuildEnergyTimeline(cfg, rawTrials)
ueCfg = localBuildEnergyModelCfg(cfg);
ueModel = sixgr.rf.EnergyModelUE(ueCfg);
bsModel = sixgr.rf.EnergyModelBS(ueCfg);
slotDur_s = localSlotDuration(cfg);
bsRfChains = localResolveRFChains(cfg, "gNB");
ueRfChains = localResolveRFChains(cfg, "UE");
bsTxPowerW = localdBmToW(localResolveTxPowerdBm(cfg, "gNB"));
ueTxPowerW = localdBmToW(localResolveTxPowerdBm(cfg, "UE"));
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

function summaryT = localBuildEnergySummary(cfg, timelineT)
summaryT = localEmptyProbeMetricTable();
if ~(istable(timelineT) && ~isempty(timelineT))
    return;
end

slotDur_s = localSlotDuration(cfg);
numFrames = max(1, double(sixgr.util.structGet(cfg, "run.numFrames", 1)));
scenarioDur = localScenarioMeasurementDuration(cfg, timelineT, numFrames, slotDur_s);
[successBitsRaw, firstDeliveryCount] = localUniqueDeliveredBits(timelineT);
successBits = max(successBitsRaw, 1);
ueMask = string(timelineT.Entity) == "UE";
gnbMask = string(timelineT.Entity) == "gNB";
ueEnergy = sum(double(timelineT.Energy_J(ueMask)), "omitnan");
gnbEnergy = sum(double(timelineT.Energy_J(gnbMask)), "omitnan");
bbEnergy = sum(double(timelineT.BBProcessingEnergy_J(gnbMask)), "omitnan");
rfActiveTime = sum(double(timelineT.Duration_s(gnbMask)), "omitnan");
throughputMbps = (successBits / max(scenarioDur, eps)) / 1e6;
avgPowerW = (ueEnergy + gnbEnergy) / max(scenarioDur, eps);
sleepModel = lower(string(sixgr.util.structGet(cfg, "lls6g.energy_efficiency.sleep_state_model", "none")));
sleepRatio = max(0, 1 - rfActiveTime / max(scenarioDur, eps));
raceToSleepGain = 0;
raceToSleepNote = "Sleep-state model disabled; race-to-sleep gain is zero for this scenario.";
if sleepModel ~= "none"
    raceToSleepGain = sleepRatio;
    raceToSleepNote = "Measured sleep-ratio proxy under the configured sleep-state model.";
end
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
bandwidthAdaptEffect = 0;
bandwidthAdaptNote = "Bandwidth-adaptation energy saving disabled; delta is zero by construction.";
if bandwidthAdaptEnabled
    bandwidthAdaptEffect = sleepRatio * avgPowerW;
    bandwidthAdaptNote = "Measured energy-saving proxy using observed sleep ratio under bandwidth adaptation mode '" + bandwidthAdaptMode + "'.";
end

summaryT = [summaryT; ... %#ok<AGROW>
    localProbeMetricRow("ue_energy_per_successful_bit", "UE", "mean", ueEnergy / successBits, "", "J/bit", "UE runtime energy divided by successful bits."); ...
    localProbeMetricRow("first_delivered_bits", "system", "total", successBitsRaw, "", "bit", "Unique first-success delivered bits used as energy denominator."); ...
    localProbeMetricRow("first_delivery_count", "system", "total", firstDeliveryCount, "", "count", "Unique first-success TB delivery events used by energy accounting."); ...
    localProbeMetricRow("measurement_window_duration", "system", "total", scenarioDur, "", "s", "Simulated measurement window used by energy and throughput-per-watt metrics."); ...
    localProbeMetricRow("ue_energy_per_slot_frame_burst", "UE", "per_frame_mean", ueEnergy / numFrames, "", "J/frame", "Average UE energy per frame."); ...
    localProbeMetricRow("gnb_energy_per_successful_bit", "gNB", "mean", gnbEnergy / successBits, "", "J/bit", "gNB runtime energy divided by successful bits."); ...
    localProbeMetricRow("gnb_active_sleep_duty_cycle", "gNB", "active_ratio", rfActiveTime / max(scenarioDur, eps), "", "fraction", "Active ratio from gNB runtime timeline."); ...
    localProbeMetricRow("gnb_active_sleep_duty_cycle", "gNB", "sleep_ratio", max(0, 1 - rfActiveTime / max(scenarioDur, eps)), "", "fraction", "Residual ratio not spent in active runtime states."); ...
    localProbeMetricRow("rf_chain_active_time", "gNB", "total", rfActiveTime, "", "s", "Accumulated gNB RF-chain active time."); ...
    localProbeMetricRow("bb_processing_energy", "gNB", "total", bbEnergy, "", "J", "Modeled TRX-chain processing energy in the RF energy model."); ...
    localProbeMetricRow("pdcch_monitoring_energy_metric", "UE", "total", localDomainEnergy(timelineT, "UE", "PDCCH_monitoring"), "", "J", "UE receive energy while monitoring PDCCH."); ...
    localProbeMetricRow("pdcch_monitoring_energy", "UE", "total", localDomainEnergy(timelineT, "UE", "PDCCH_monitoring"), "", "J", "UE receive energy while monitoring PDCCH."); ...
    localProbeMetricRow("ssb_pbch_common_signal_energy", "gNB", "total", localDomainEnergy(timelineT, "gNB", "SSB_PBCH"), "", "J", "gNB common-signal transmit energy."); ...
    localProbeMetricRow("prach_common_channel_clustering_energy_effect", "system", "delta_j", clusteringEffect, "", "J", clusteringNote); ...
    localProbeMetricRow("bandwidth_adaptation_energy_effect", "system", "delta_j", bandwidthAdaptEffect, "", "J", bandwidthAdaptNote); ...
    localProbeMetricRow("race_to_sleep_gains", "system", "fractional_gain", raceToSleepGain, "", "fraction", raceToSleepNote); ...
    localProbeMetricRow("throughput_per_watt", "system", "mean", throughputMbps / max(avgPowerW, eps), "", "Mbps/W", "Throughput per average combined UE+gNB power."); ...
    localProbeMetricRow("energy_delay_product", "system", "mean", (ueEnergy + gnbEnergy) * scenarioDur, "", "J*s", "Energy-delay product over the scenario runtime."); ...
    localProbeMetricRow("energy_spectral_efficiency_tradeoff", "system", "mean", localEnergySpectralEfficiency(cfg, throughputMbps, avgPowerW), "", "(bit/s/Hz)/W", "Spectral efficiency per watt proxy.")];
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
if strlength(strtrim(tb)) > 0 && lower(strtrim(tb)) ~= "nan"
    key = tb;
    return;
end
key = upper(string(T.Direction(i))) + "_ue" + string(T.UEID(i)) + "_rnti" + string(T.RNTI(i)) + ...
    "_harq" + string(T.HARQProcessId(i)) + "_ndi" + string(T.NDI(i)) + "_f" + string(T.Frame(i)) + "_s" + string(T.Slot(i));
end

function cfgEnergy = localBuildEnergyModelCfg(cfg)
cfgEnergy = cfg;
eff = double(sixgr.util.structGet(cfg, "lls6g.energy_efficiency.pa_efficiency", 0.35));
cfgEnergy = sixgr.util.structSet(cfgEnergy, "energy.bs.efficiencyPA", eff);
cfgEnergy = sixgr.util.structSet(cfgEnergy, "energy.ue.txWPerWattRF", 1 / max(eff, eps));
cfgEnergy = sixgr.util.structSet(cfgEnergy, "energy.bs.perTRxPW", ...
    double(sixgr.util.structGet(cfg, "energy.bs.perTRxPW", ...
    sixgr.util.structGet(cfg, "lls6g.energy_efficiency.per_rf_chain_power_w", 5))));
end

function n = localResolveRFChains(cfg, entity)
entity = upper(string(entity));
if entity == "UE"
    n = localFirstFiniteScalar( ...
        sixgr.util.structGet(cfg, "powerAndRF.ueRFChainCount", []), ...
        sixgr.util.structGet(cfg, "rf.ue.numRFChains", []), ...
        sixgr.util.structGet(cfg, "scenario.ue.numRFChains", []), ...
        sixgr.util.structGet(cfg, "scenario.ue.nTxAnt", []), ...
        sixgr.util.structGet(cfg, "scenario.ue.nRxAnt", []), ...
        1);
else
    n = localFirstFiniteScalar( ...
        sixgr.util.structGet(cfg, "powerAndRF.bsRFChainCount", []), ...
        sixgr.util.structGet(cfg, "rf.bs.numRFChains", []), ...
        sixgr.util.structGet(cfg, "scenario.bs.numRFChains", []), ...
        sixgr.util.structGet(cfg, "lls6g.energy_efficiency.rf_chain_count", []), ...
        sixgr.util.structGet(cfg, "phy.nTxAnt", []), ...
        1);
end
if ~(isfinite(double(n)) && double(n) >= 1)
    n = 1;
else
    n = max(1, round(double(n)));
end
end

function dbm = localResolveTxPowerdBm(cfg, entity)
entity = upper(string(entity));
if entity == "UE"
    dbm = localFirstFiniteScalar( ...
        sixgr.util.structGet(cfg, "powerAndRF.ueTxPower_dBm", []), ...
        sixgr.util.structGet(cfg, "lls6g.resolvedConfig.power_and_rf_frontend.ue_tx_power_dbm", []), ...
        sixgr.util.structGet(cfg, "phy.pusch.powerControl.pcmax_dBm", []), ...
        sixgr.util.structGet(cfg, "lls6g.energy_efficiency.ue_tx_power_dbm", []), ...
        23);
else
    dbm = localFirstFiniteScalar( ...
        sixgr.util.structGet(cfg, "powerAndRF.bsTxPower_dBm", []), ...
        sixgr.util.structGet(cfg, "lls6g.resolvedConfig.power_and_rf_frontend.bs_tx_power_dbm", []), ...
        sixgr.util.structGet(cfg, "scenario.bs.txPower_dBm", []), ...
        sixgr.util.structGet(cfg, "lls6g.energy_efficiency.bs_tx_power_dbm", []), ...
        sixgr.util.structGet(cfg, "lls6g.energy_efficiency.tx_power_dbm", []), ...
        46);
end
end

function value = localFirstFiniteScalar(varargin)
value = NaN;
for i = 1:nargin
    raw = varargin{i};
    if isempty(raw)
        continue;
    end
    if islogical(raw)
        raw = double(raw);
    end
    if ~isnumeric(raw)
        numeric = str2double(string(raw));
    else
        numeric = double(raw);
    end
    numeric = numeric(:);
    numeric = numeric(isfinite(numeric));
    if ~isempty(numeric)
        value = numeric(1);
        return;
    end
end
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
for name = ["TransportBlockId","TBId","MACPDUId","MACSDUId","GrantContextId"]
    if istable(T) && ismember(name, string(T.Properties.VariableNames))
        raw = strtrim(string(T.(char(name))(rowIdx)));
        if strlength(raw) > 0 && lower(raw) ~= "nan"
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
tbId = upper(string(direction)) + "_ue" + string(ueId) + "_rnti" + string(rnti) + ...
    "_harq" + string(harqProcessId) + "_ndi" + string(ndi) + "_f" + string(frameVal) + "_s" + string(slotVal);
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
T = table('Size', [0 7], ...
    'VariableTypes', {'string','string','string','double','string','string','string'}, ...
    'VariableNames', {'MetricKey','Entity','Statistic','Value','TextValue','Unit','Notes'});
end

function T = localProbeMetricRow(metricKey, entity, statistic, value, textValue, unit, notes)
if strlength(strtrim(string(textValue))) == 0 && isfinite(double(value))
    textValue = sprintf('%.12g', double(value));
end
T = table(string(metricKey), string(entity), string(statistic), double(value), string(textValue), string(unit), string(notes), ...
    'VariableNames', {'MetricKey','Entity','Statistic','Value','TextValue','Unit','Notes'});
end
