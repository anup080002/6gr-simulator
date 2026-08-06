function ok = testCausalKPIEventAccounting()
%TESTCAUSALKPIEVENTACCOUNTING KPI, latency, energy derive from causal events.

setup6GRSimToolkit("Verbose", false);

raw = struct();
raw.UL = localDirectionRows("UL");
raw.DL = localDirectionRows("DL");
raw.PacketSDU = localPacketSDURows();
raw.ApplicationPackets = localApplicationPacketRows();

out = sixgr.kpi.reconstructLLSKPISummaryFromRaw(raw, ...
    "StrictMode", true, ...
    "MeasurementWindowSec", 0.004, ...
    "EffectiveBandwidthHz", 1e6);

ulSched = localRecon(out, "UL_PHY_ScheduledThroughput_Mbps");
ulGoodput = localRecon(out, "UL_TB_Delivery_Goodput_Mbps");
ulSe = localRecon(out, "UL_SpectralEfficiency_bpsHz");
ulLatency = localRecon(out, "UL_Latency_ms");
ulMacGoodput = localRecon(out, "UL_MAC_Goodput_Mbps");
ulAppGoodput = localRecon(out, "UL_Application_Goodput_Mbps");

assert(abs(double(ulSched.ReconstructionValue) - 1.0) < 1e-12, ...
    "Scheduled PHY rate must use active scheduled exposure: 3000 bits / 3 ms = 1 Mbps.");
assert(abs(double(ulGoodput.ReconstructionValue) - 0.5) < 1e-12, ...
    "Scenario goodput must use measurement window: 2000 delivered bits / 4 ms = 0.5 Mbps.");
assert(abs(double(ulSe.ReconstructionValue) - 0.5) < 1e-12, ...
    "Spectral efficiency must be delivered bits / measurement window / bandwidth.");
assert(abs(double(ulLatency.ReconstructionValue) - 1.5) < 1e-12, ...
    "Mean delivery latency must come from causal packet delivery timestamps when packet ledgers are present.");
assert(abs(double(ulMacGoodput.ReconstructionValue) - 0.5) < 1e-12, ...
    "MAC goodput must be delivered MAC SDU payload bits divided by the measurement window.");
assert(abs(double(ulAppGoodput.ReconstructionValue) - 0.5) < 1e-12, ...
    "Application goodput must be delivered reassembled packet bits divided by the measurement window.");
assert(abs(double(ulSched.AggregationDurationSec) - 0.003) < 1e-12 && ...
    abs(double(ulGoodput.AggregationDurationSec) - 0.004) < 1e-12, ...
    "Scheduled-rate and scenario-goodput denominators must remain distinct.");

ledger = out.TBDeliveryLedgerUL;
assert(string(ledger.TransportBlockId(1)) == string(ledger.TransportBlockId(2)), ...
    "RV0 failure and RV2 retransmission must share one TB identity.");
assert(sum(logical(ledger.FirstSuccessDelivery)) == 2, ...
    "Only first successful deliveries count as delivered TB events.");
assert(sum(double(ledger.CountedGoodputBits), "omitnan") == 2000, ...
    "Retransmitted TB must be counted once at first success.");

localAssertEnergyAccounting(raw);
localAssertHARQEntityLedger();

ok = true;
end

function T = localDirectionRows(direction)
direction = string(direction);
T = table( ...
    repmat(direction, 3, 1), [0; 0; 0], [false; true; true], [10; 0; 0], [1000; 1000; 1000], ...
    [1000; 1000; 1000], [0; 1000; 1000], [1; 1; 1], [1; 2; 3], ...
    [0; 0; 0], [1; 1; 1], [0; 2; 0], [true; false; true], [false; true; false], ...
    [1; 1; 1], [1; 2; 3], [0.001; 0.001; 0.001], ...
    'VariableNames', {'Direction','Goodput_Mbps','CRCPass','BitErrors','BitsCompared', ...
    'TBSize_bits','GoodBits','Frame','Slot','HARQProcessId','NDI','RV', ...
    'NewDataFlag','RetransmissionFlag','AirInterfaceObservation_ms','TrialId','SlotDuration_s'});
end

function T = localPacketSDURows()
T = table( ...
    ["UL"; "UL"; "DL"], [1; 1; 1], ["ul_pkt_1"; "ul_pkt_2"; "dl_pkt_1"], ...
    ["ul_sdu_1"; "ul_sdu_2"; "dl_sdu_1"], ["ul_tb_1"; "ul_tb_2"; "dl_tb_1"], ...
    [1000; 1000; 1000], [true; true; true], [true; true; true], ...
    [1; 1; 1], [2; 3; 2], [0.001; 0.002; 0.001], [0.002; 0.003; 0.002], ...
    'VariableNames', {'Direction','UEIndex','PacketId','MACSDUId','TransportBlockId', ...
    'PayloadBits','DeliverySuccess','FirstSuccessDelivery','ScheduleSlot','FirstSuccessSlot', ...
    'ScheduleTime_s','DeliveryTime_s'});
end

function T = localApplicationPacketRows()
T = table( ...
    ["UL"; "UL"; "DL"], [1; 1; 1], ["ul_pkt_1"; "ul_pkt_2"; "dl_pkt_1"], ...
    ["ul_pkt_1"; "ul_pkt_2"; "dl_pkt_1"], [1000; 1000; 1000], [1000; 1000; 1000], ...
    [true; true; true], [true; true; true], [0.0005; 0.0015; 0.0005], [0.002; 0.003; 0.002], [1.5; 1.5; 1.5], ...
    'VariableNames', {'Direction','UEIndex','PacketId','ApplicationPacketId','OfferedBits', ...
    'DeliveredBits','DeliverySuccess','SameWaveformProtocolComplete','EnqueueTime_s','DeliveryTime_s','Latency_ms'});
end

function row = localRecon(out, name)
T = out.ReconstructionSummary;
row = T(strcmp(string(T.KPIName), string(name)), :);
assert(height(row) == 1, "Expected one reconstruction row for %s.", name);
end

function localAssertEnergyAccounting(raw)
cfg = struct();
cfg.powerAndRF.bsTxPower_dBm = 46;
cfg.powerAndRF.ueTxPower_dBm = 23;
cfg.powerAndRF.bsRFChainCount = 1;
cfg.powerAndRF.ueRFChainCount = 1;
cfg.phy.carrier.NSizeGrid = 24;
cfg.phy.carrier.SubcarrierSpacing = 15;
cfg.channel.bandwidth_Hz = 1e6;
cfg.run.numFrames = 1;
cfg.energy.ue.idleW = 1;
cfg.energy.ue.rxW = 0;
cfg.energy.ue.sleepW = 0.1;
cfg.energy.ue.txWPerWattRF = 1;
cfg.energy.bs.staticW = 0;
cfg.energy.bs.perTRxPW = 0;
cfg.energy.bs.sleepW = 1;
cfg.energy.bs.efficiencyPA = 1;
cfg.lls6g.energy_efficiency.bs_static_power_w = 0;
cfg.lls6g.energy_efficiency.bs_per_rf_chain_power_w = 0;
cfg.lls6g.energy_efficiency.bs_sleep_power_w = 1;
cfg.lls6g.energy_efficiency.bs_pa_efficiency = 1;
cfg.lls6g.energy_efficiency.ue_idle_power_w = 1;
cfg.lls6g.energy_efficiency.ue_rx_power_w = 0;
cfg.lls6g.energy_efficiency.ue_sleep_power_w = 0.1;
cfg.lls6g.energy_efficiency.ue_tx_dc_per_watt_rf = 1;
cfg.lls6g.energy_efficiency.bs_tx_power_dbm = 46;
cfg.lls6g.energy_efficiency.ue_tx_power_dbm = 23;
cfg.lls6g.energy_efficiency.bs_rf_chain_count = 1;
cfg.lls6g.energy_efficiency.ue_rf_chain_count = 1;

rawTrials = struct();
rawTrials.UL = raw.UL(2, :);
rawTrials.UL.Status = "PASS";
rawTrials.UL.TransportBlockId = "ul_tb_1";
rawTrials.DL = table();

root = tempname;
airFolder = fullfile(root, "air_interface");
mkdir(airFolder);
cleanupObj = onCleanup(@() localCleanup(root)); %#ok<NASGU>
artifacts = sixgr.truth.exportLLSEnergyDiagnostics(cfg, airFolder, rawTrials);
timeline = artifacts.TimelineTable;
assert(all(abs(double(timeline.Energy_J) - double(timeline.Power_W) .* double(timeline.Duration_s)) < 1e-15), ...
    "Every energy timeline row must satisfy E = P * dt.");
summary = artifacts.SummaryTable;
bitsRow = summary(strcmp(string(summary.MetricKey), "first_delivered_bits"), :);
assert(height(bitsRow) == 1 && abs(double(bitsRow.Value) - 1000) < 1e-12, ...
    "Energy denominator must use unique first-delivered bits, not both endpoint rows.");
end

function localAssertHARQEntityLedger()
harq = sixgr.l2.mac.HARQEntity(struct(), "Direction", "DL", "MaxRetx", 3);
txp = harq.allocate(77, 1, 100, "NewData", true);
grant = struct("TBSBits", 800);
harq.onTx(77, txp.HARQ.HarqID, uint8(zeros(800, 1)), grant, 1);
harq.onFeedback(77, txp.HARQ.HarqID, false, "SourceSlot", 1, "FeedbackSlot", 1);
retx = harq.allocate(77, 2, 100, "NewData", false);
harq.onTx(77, retx.HARQ.HarqID, uint8(zeros(800, 1)), grant, 2);
harq.onFeedback(77, retx.HARQ.HarqID, true, "SourceSlot", 2, "FeedbackSlot", 2);
ledger = harq.getDeliveryLedger();
assert(height(ledger) == 2, "HARQ ledger must record both transmission attempts.");
assert(numel(unique(string(ledger.TransportBlockId))) == 1, ...
    "HARQ retransmission attempts must retain the original TB identity.");
assert(sum(logical(ledger.FirstSuccessDelivery)) == 1 && sum(double(ledger.CountedGoodputBits)) == 800, ...
    "HARQ ledger must count exactly one first-success delivery.");
end

function localCleanup(root)
if isfolder(root)
    try
        rmdir(root, "s");
    catch
    end
end
end
