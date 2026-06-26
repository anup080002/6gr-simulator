function ok = testPowerContextPhysicalUnits()
%TESTPOWERCONTEXTPHYSICALUNITS Validate entity-specific sample power units.

setup6GRSimToolkit("Verbose", false);

cfg = struct();
cfg.powerAndRF.bsTxPower_dBm = 46;
cfg.powerAndRF.ueTxPower_dBm = 23;
cfg.powerAndRF.bsRFChainCount = 64;
cfg.scenario.ue.nTxAnt = 2;
cfg.phy.nTxAnt = 64;
cfg.phy.carrier.NSizeGrid = 52;
cfg.phy.carrier.SubcarrierSpacing = 30;
cfg.channel.pathlossEnabled = true;
cfg.channel.pathloss_dB = 100;
cfg.channel.bandwidth_Hz = 20e6;
cfg.run.noiseOperatingMode = "receiver_noise_figure_thermal_noise";
cfg.energy.bs.staticW = 0;
cfg.energy.bs.perTRxPW = 5;
cfg.energy.bs.efficiencyPA = 1;
cfg.lls6g.energy_efficiency.rf_chain_count = 64;
cfg.lls6g.energy_efficiency.pa_efficiency = 1;

xDL = complex(ones(2048, 4), zeros(2048, 4));
[yDL, ctxDL] = sixgr.rf.applyPowerContext(xDL, cfg, "DL", struct());
assert(abs(ctxDL.OutputTotalPower_dBm - 46) < 1e-10, ...
    "DL waveform total sample power must close to 46 dBm.");
assert(abs(sum(ctxDL.OutputPerPortPower_mW) - ctxDL.TotalTxPower_mW) < 1e-6, ...
    "DL per-port powers must sum to total transmit power.");

xUL = complex(ones(2048, 2), zeros(2048, 2));
[~, ctxUL] = sixgr.rf.applyPowerContext(xUL, cfg, "UL", struct());
assert(abs(ctxUL.OutputTotalPower_dBm - 23) < 1e-10, ...
    "UL waveform total sample power must close to 23 dBm.");
assert(ctxUL.RFChainCount == 2, ...
    "UE RF-chain count must not inherit the 64-chain gNB configuration.");

cfgDL = sixgr.util.structSet(cfg, "lls6g.runtimePowerContext", ctxDL);
cfgDL = sixgr.util.structSet(cfgDL, "lls6g.userContext", struct( ...
    "RuntimeCurrentDirection", "DL"));
[rxDL, replayDL] = sixgr.link.applyWaveformImpairments(yDL, cfgDL, 30.72e6);
rxPower_dBm = localMeanTotalPowerDbm(rxDL);
assert(abs(rxPower_dBm - (-54)) < 1e-9, ...
    "Known 46 dBm, 100 dB pathloss link budget must close to -54 dBm.");
assert(abs(double(replayDL.ServingRxPower_dBm) - (-54)) < 1e-9, ...
    "Replay ServingRxPower_dBm must match the PowerContext link budget.");
assert(strcmp(string(replayDL.ServingRxPowerSource), "power_context_link_budget"), ...
    "Replay must label the dimensional link-budget source.");

bsModel = sixgr.rf.EnergyModelBS(cfg);
p4 = bsModel.power('active', 4, 1, 0);
p8 = bsModel.power('active', 8, 1, 0);
assert(abs((p8.trxW / p4.trxW) - 2) < 1e-12, ...
    "Doubling active gNB RF chains must double, not square, TRx chain power.");

root = tempname;
airFolder = fullfile(root, "air_interface");
mkdir(airFolder);
cleanupObj = onCleanup(@() localCleanup(root)); %#ok<NASGU>
rawTrials = struct();
rawTrials.DL = table("PASS", 1, 1, 10, 1000, 1, ...
    'VariableNames', {'Status','Frame','Slot','PRBs','TBSize_bits','UEID'});
rawTrials.UL = table("PASS", 1, 2, 10, 1000, 1, ...
    'VariableNames', {'Status','Frame','Slot','PRBs','TBSize_bits','UEID'});
artifacts = sixgr.truth.exportLLSEnergyDiagnostics(cfg, airFolder, rawTrials);
T = artifacts.TimelineTable;
assert(~isempty(T), "Energy timeline must be generated for measured raw trial rows.");
dlGnb = T(string(T.Entity) == "gNB" & string(T.Direction) == "DL" & string(T.Domain) == "DL_data", :);
ulUe = T(string(T.Entity) == "UE" & string(T.Direction) == "UL" & string(T.Domain) == "UL_data", :);
assert(dlGnb.RFChainCount(1) == 64, "DL gNB timeline rows must use gNB RF-chain count.");
assert(ulUe.RFChainCount(1) == 2, "UL UE timeline rows must use UE RF-chain count.");
assert(abs(dlGnb.TxPower_dBm(1) - 46) < 1e-12, "DL gNB rows must use gNB transmit power.");
assert(abs(ulUe.TxPower_dBm(1) - 23) < 1e-12, "UL UE rows must use UE transmit power.");

ok = true;
end

function dbm = localMeanTotalPowerDbm(x)
power_mW = mean(sum(abs(double(x)).^2, 2), "omitnan");
dbm = 10 * log10(max(power_mW, realmin));
end

function localCleanup(root)
if isfolder(root)
    try
        rmdir(root, "s");
    catch
    end
end
end
