function ok = testLLSEnergyEvidenceIntegrity()
%TESTLLSENERGYEVIDENCEINTEGRITY Energy evidence is explicit and fail closed.

setup6GRSimToolkit("Verbose", false);

cfg = localExplicitConfig();
resolved = sixgr.truth.resolveLLSEnergyModelConfig(cfg);
assert(resolved.Available && height(resolved.TermTable) == 12);
assert(all(string(resolved.TermTable.Availability) == "AVAILABLE"));

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
pass = sixgr.truth.exportLLSEnergyDiagnostics(cfg, airFolder, passTrials);
for key = ["ue_energy_per_successful_bit","gnb_energy_per_successful_bit"]
    row = pass.SummaryTable(string(pass.SummaryTable.MetricKey) == key, :);
    assert(height(row) == 1 && isfinite(row.Value) && row.Value > 0);
    assert(string(row.Availability) == "AVAILABLE");
    assert(string(row.EvidenceType) == "runtime_state_conditioned_engineering_model");
end
assert(~any(contains(lower(string(pass.SummaryTable.EvidenceType)), ...
    ["proxy","fallback","synthetic","placeholder"])));

% Fixed-link campaign points reuse frame/slot coordinates. Their campaign
% hierarchy must keep successful TBs distinct and their active-time
% denominator must not yield an impossible duty cycle above one.
fixedT = [localTrial("PASS", 800); localTrial("PASS", 800); localTrial("FAIL", 0)];
fixedT.FixedLinkPointIndex = (1:3).';
fixedT.FixedLinkDropIndex = ones(3, 1);
fixedT.FixedLinkTrialIndex = ones(3, 1);
fixedT.FixedLinkSeedIndex = ones(3, 1);
fixedT.FixedLinkSeedValue = 104729 * ones(3, 1);
fixed = sixgr.truth.exportLLSEnergyDiagnostics(cfg, airFolder, ...
    struct("DL", fixedT, "UL", table()));
localAssertMetricValue(fixed.SummaryTable, "first_delivery_count", 2, 0);
localAssertMetricValue(fixed.SummaryTable, "first_delivered_bits", 1600, 0);
activeRows = fixed.SummaryTable(string(fixed.SummaryTable.MetricKey) == ...
    "gnb_active_sleep_duty_cycle" & string(fixed.SummaryTable.Statistic) == "active_ratio", :);
assert(height(activeRows) == 1 && activeRows.Value >= 0 && activeRows.Value <= 1, ...
    "Fixed-link gNB duty cycle must be in [0,1].");

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
cfg.energy.bs.staticW = 100;
cfg.energy.bs.perTRxPW = 4;
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
end

function localAssertMetricUnavailable(T, key)
row = T(string(T.MetricKey) == string(key), :);
assert(height(row) == 1 && ~isfinite(row.Value));
assert(string(row.Availability) == "NOT_EVALUATED");
end

function localAssertMetricValue(T, key, expected, tolerance)
row = T(string(T.MetricKey) == string(key), :);
assert(height(row) == 1 && abs(double(row.Value) - double(expected)) <= tolerance, ...
    "Unexpected %s value.", key);
end

function localCleanup(root)
if isfolder(root)
    try
        rmdir(root, "s");
    catch
    end
end
end
