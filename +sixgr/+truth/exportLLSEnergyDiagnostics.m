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
rfChains = max(1, round(double(sixgr.util.structGet(cfg, "lls6g.energy_efficiency.rf_chain_count", sixgr.util.structGet(cfg, "phy.nTxAnt", 1)))));
bsTxPowerW = localdBmToW(double(sixgr.util.structGet(cfg, "scenario.bs.txPower_dBm", sixgr.util.structGet(cfg, "lls6g.energy_efficiency.tx_power_dbm", 23))));
ueTxPowerW = localdBmToW(double(sixgr.util.structGet(cfg, "lls6g.energy_efficiency.tx_power_dbm", 23)));
totalRBs = max(1, double(sixgr.util.structGet(cfg, "phy.carrier.NSizeGrid", 1)));

rows = repmat(localEmptyEnergyRow(), 0, 1);
rows = [rows; localBuildRowsForTable(localResolveTrialTable(sixgr.util.structGet(rawTrials, "DL", table())), "DL_data", "DL", slotDur_s, totalRBs, rfChains, bsModel, ueModel, bsTxPowerW, ueTxPowerW, "air_interface/csv/dl_pdsch_trials.csv")]; %#ok<AGROW>
rows = [rows; localBuildRowsForTable(localResolveTrialTable(sixgr.util.structGet(rawTrials, "UL", table())), "UL_data", "UL", slotDur_s, totalRBs, rfChains, bsModel, ueModel, bsTxPowerW, ueTxPowerW, "air_interface/csv/ul_pusch_trials.csv")]; %#ok<AGROW>
rows = [rows; localBuildRowsForTable(localResolveTrialTable(sixgr.util.structGet(rawTrials, "PDCCH", table())), "PDCCH_monitoring", "DL", slotDur_s, totalRBs, rfChains, bsModel, ueModel, bsTxPowerW, ueTxPowerW, "air_interface/csv/pdcch_trials.csv")]; %#ok<AGROW>
rows = [rows; localBuildRowsForTable(localResolveTrialTable(sixgr.util.structGet(rawTrials, "PBCH", table())), "SSB_PBCH", "DL", slotDur_s, totalRBs, rfChains, bsModel, ueModel, bsTxPowerW, ueTxPowerW, "air_interface/csv/pbch_trials.csv")]; %#ok<AGROW>
rows = [rows; localBuildRowsForTable(localResolveTrialTable(sixgr.util.structGet(rawTrials, "PRACH", table())), "PRACH", "UL", slotDur_s, totalRBs, rfChains, bsModel, ueModel, bsTxPowerW, ueTxPowerW, "air_interface/csv/prach_trials.csv")]; %#ok<AGROW>
rows = [rows; localBuildRowsForTable(localResolveTrialTable(sixgr.util.structGet(rawTrials, "PUCCH", table())), "PUCCH", "UL", slotDur_s, totalRBs, rfChains, bsModel, ueModel, bsTxPowerW, ueTxPowerW, "air_interface/csv/pucch_trials.csv")]; %#ok<AGROW>
rows = [rows; localBuildRowsForTable(localResolveTrialTable(sixgr.util.structGet(rawTrials, "SRS", table())), "SRS", "UL", slotDur_s, totalRBs, rfChains, bsModel, ueModel, bsTxPowerW, ueTxPowerW, "air_interface/csv/srs_trials.csv")]; %#ok<AGROW>

if isempty(rows)
    timelineT = table();
else
    timelineT = struct2table(rows);
end
end

function rows = localBuildRowsForTable(T, domain, direction, slotDur_s, totalRBs, rfChains, bsModel, ueModel, bsTxPowerW, ueTxPowerW, sourceArtifact)
rows = repmat(localEmptyEnergyRow(), 0, 1);
if ~(istable(T) && ~isempty(T))
    return;
end

for i = 1:height(T)
    load = 1;
    if ismember("PRBs", string(T.Properties.VariableNames)) && isfinite(double(T.PRBs(i)))
        load = min(max(double(T.PRBs(i)) / totalRBs, 0), 1);
    end
    status = string(localTableValue(T, i, "Status", "NA"));
    successBits = 0;
    if status == "PASS" && ismember("TBSize_bits", string(T.Properties.VariableNames)) && isfinite(double(T.TBSize_bits(i)))
        successBits = double(T.TBSize_bits(i));
    end
    frameVal = double(localTableValue(T, i, "Frame", i));
    slotVal = double(localTableValue(T, i, "Slot", i));
    switch upper(string(direction))
        case "DL"
            bs = bsModel.power('active', rfChains, load, bsTxPowerW);
            ue = ueModel.power('rx', 0);
            rows(end+1, 1) = localMakeEnergyRow("gNB", domain, direction, frameVal, slotVal, slotDur_s, bs.totalW, successBits, rfChains, bs.trxW * slotDur_s, sourceArtifact, status); %#ok<AGROW>
            rows(end+1, 1) = localMakeEnergyRow("UE", domain, direction, frameVal, slotVal, slotDur_s, ue.totalW, successBits, rfChains, 0, sourceArtifact, status); %#ok<AGROW>
        otherwise
            ue = ueModel.power('tx', ueTxPowerW);
            bs = bsModel.power('active', rfChains, load, 0);
            rows(end+1, 1) = localMakeEnergyRow("UE", domain, direction, frameVal, slotVal, slotDur_s, ue.totalW, successBits, rfChains, 0, sourceArtifact, status); %#ok<AGROW>
            rows(end+1, 1) = localMakeEnergyRow("gNB", domain, direction, frameVal, slotVal, slotDur_s, bs.totalW, successBits, rfChains, bs.trxW * slotDur_s, sourceArtifact, status); %#ok<AGROW>
    end
end
end

function row = localMakeEnergyRow(entity, domain, direction, frameVal, slotVal, duration_s, powerW, successBits, rfChains, bbEnergyJ, sourceArtifact, status)
row = struct( ...
    "Entity", string(entity), ...
    "Domain", string(domain), ...
    "Direction", string(direction), ...
    "Frame", double(frameVal), ...
    "Slot", double(slotVal), ...
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
    "Entity", "", "Domain", "", "Direction", "", "Frame", NaN, "Slot", NaN, ...
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
scenarioDur = max(numFrames * slotDur_s, sum(double(timelineT.Duration_s(string(timelineT.Entity) == "gNB")), "omitnan"));
successBits = max(sum(double(timelineT.SuccessfulBits), "omitnan"), 1);
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

function cfgEnergy = localBuildEnergyModelCfg(cfg)
cfgEnergy = cfg;
eff = double(sixgr.util.structGet(cfg, "lls6g.energy_efficiency.pa_efficiency", 0.35));
cfgEnergy = sixgr.util.structSet(cfgEnergy, "energy.bs.efficiencyPA", eff);
cfgEnergy = sixgr.util.structSet(cfgEnergy, "energy.ue.txWPerWattRF", 1 / max(eff, eps));
cfgEnergy = sixgr.util.structSet(cfgEnergy, "energy.bs.perTRxPW", 5 * double(sixgr.util.structGet(cfg, "lls6g.energy_efficiency.rf_chain_count", 2)));
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

function watts = localdBmToW(dbm)
watts = 1e-3 * 10.^(double(dbm) / 10);
end

function slotDur_s = localSlotDuration(cfg)
scs = double(sixgr.util.structGet(cfg, "phy.carrier.SubcarrierSpacing", 30));
mu = log2(scs / 15);
if ~isfinite(mu) || mu < 0
    mu = 0;
end
slotDur_s = 1e-3 / (2^mu);
end

function T = localEmptyProbeMetricTable()
T = table('Size', [0 7], ...
    'VariableTypes', {'string','string','string','double','string','string','string'}, ...
    'VariableNames', {'MetricKey','Entity','Statistic','Value','TextValue','Unit','Notes'});
end

function T = localProbeMetricRow(metricKey, entity, statistic, value, textValue, unit, notes)
T = table(string(metricKey), string(entity), string(statistic), double(value), string(textValue), string(unit), string(notes), ...
    'VariableNames', {'MetricKey','Entity','Statistic','Value','TextValue','Unit','Notes'});
end
