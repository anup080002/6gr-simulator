function ok = testReferenceSignalCausalProducersConsumers()
%TESTREFERENCESIGNALCAUSALPRODUCERSCONSUMERS CSI-RS/SRS/TRS causal contracts.

setup6GRSimToolkit("Verbose", false);
if exist("nrSRS", "file") ~= 2 || exist("nrOFDMModulate", "file") ~= 2
    ok = true;
    return;
end

localCSIRSResourceGridMapping();
localSRSSharedSlotMultiUE();
localCausalMeasurementLedger();
localSSBMeasurementBinding();

ok = true;
end

function localSSBMeasurementBinding()
row = table(-89, 37, 41, 42, ...
    'VariableNames', {'SS_RSRP_dBm','SS_SINR_dB','MeasuredSINR_dB','SINR_dB'});
state = struct("CurrentSlot", 1);
state = sixgr.truth.CoupledTruthRuntime.publishReferenceSignalMeasurementRuntime( ...
    state, "SSB", "UE", 1, row, "Valid", true, "Direction", "DL");
T = state.ReferenceSignalMeasurementTable;
assert(T.SINR_dB(end) == 37 && T.RSRP_dBm(end) == -89, ...
    "An SSB measurement must bind SS-SINR, not PBCH DM-RS or generic SINR.");
assert(string(T.SINRSourceField(end)) == "SS_SINR_dB", ...
    "The ledger must retain the exact source field for its reported SINR.");
row.SS_SINR_dB = NaN;
state = sixgr.truth.CoupledTruthRuntime.publishReferenceSignalMeasurementRuntime( ...
    state, "SSB", "UE", 1, row, "Valid", true, "Direction", "DL");
assert(isnan(state.ReferenceSignalMeasurementTable.SINR_dB(end)), ...
    "Missing SS-SINR must remain unavailable, without substitution from another signal.");
assert(string(state.ReferenceSignalMeasurementTable.SINRValueStatus(end)) == "unavailable", ...
    "Missing SS-SINR must be explicitly marked unavailable.");
end

function localCSIRSResourceGridMapping()
cfg = sixgr.config.defaultConfig();
cfg.phy.carrier.NCellID = 17;
cfg.phy.carrier.NSizeGrid = 24;
cfg.phy.numerology.scs_kHz = 30;
cfg.phy.csirs.enable = true;
cfg.phy.csirs.rbOffset = 2;
cfg.phy.csirs.numRB = 12;
cfg.phy.csirs.symbolLocations = 4;

[carrier, ~] = sixgr.phy.grid.makeCarrier(cfg);
for nPorts = [1 2 4]
    cfg.phy.csirs.nPorts = nPorts;
    [ind, sym, info] = sixgr.phy.refsig.csirs(carrier, cfg);
    T = info.ResourceMappingTable;
    assert(~isempty(ind) && numel(ind) == numel(sym), ...
        "CSI-RS must generate paired indices and symbols.");
    assert(istable(T) && height(T) == numel(sym), ...
        "CSI-RS info must expose one resource-mapping row per generated RE.");
    assert(all(double(T.PRB) >= cfg.phy.csirs.rbOffset & ...
        double(T.PRB) < cfg.phy.csirs.rbOffset + cfg.phy.csirs.numRB), ...
        "CSI-RS mapping must stay inside the configured BWP/RB range.");
    nP = max(1, round(double(info.NumCSIRSPorts)));
    grid = complex(zeros(double(carrier.NSizeGrid) * 12, double(carrier.SymbolsPerSlot), nP));
    grid(ind) = sym;
    mapped = grid(double(T.LinearIndex));
    ref = complex(double(T.SymbolI), double(T.SymbolQ));
    assert(max(abs(mapped(:) - ref(:))) < 1e-12, ...
        "CSI-RS resource-mapping table must match the exact grid contents.");
end
end

function localSRSSharedSlotMultiUE()
cfg = sixgr.config.defaultConfig();
cfg.phy.carrier.NCellID = 11;
cfg.phy.carrier.NSizeGrid = 24;
cfg.phy.numerology.scs_kHz = 30;
cfg.channel.snr_dB = 45;
cfg.phy.srs.nPorts = 1;
cfg.phy.srs.KTC = 2;
cfg.phy.srs.KBarTC = 0;
cfg.phy.srs.CyclicShift = 0;
cfg.phy.srs.SymbolStart = 13;
cfg.phy.srs.NumSRSSymbols = 1;
cfg.phy.srs.slotNumbers = 0;
strictCfg = sixgr.phy.srs.buildSRSConfigFromScenario(cfg, ...
    "RunId", "causal_srs", "ScenarioName", "causal_srs");

orth = sixgr.phy.srs.generateMultiUESRSGrid(strictCfg, [1 2], ...
    "Mode", "orthogonal", "SNRdB", 45, "Seed", 9210);
orthT = orth.TrialTable;
assert(all(logical(orthT.SharedSlotWaveformSuperposition)), ...
    "Multi-UE SRS must be produced by a shared slot waveform superposition.");
assert(all(double(orthT.OverlapRECount) == 0) && all(logical(orthT.OrthogonalityPass)), ...
    "Orthogonal multi-UE SRS resources must be detected and estimated without RE overlap.");

coll = sixgr.phy.srs.generateMultiUESRSGrid(strictCfg, [1 2], ...
    "Mode", "collision", "SNRdB", 45, "Seed", 9220);
collT = coll.TrialTable;
assert(any(double(collT.OverlapRECount) > 0), ...
    "Collision multi-UE SRS case must have actual RE overlap in the shared grid.");
assert(any(logical(collT.CollisionInjected) & logical(collT.CollisionDetected)), ...
    "Collision multi-UE SRS case must be detected from the composite waveform/estimator output.");
end

function localCausalMeasurementLedger()
state = struct();
state.CurrentSlot = 6;
state = sixgr.truth.CoupledTruthRuntime.publishReferenceSignalMeasurementRuntime( ...
    state, "SRS", "UE", 1, table(5, 10, 2, 4, 18, ...
    'VariableNames', {'Slot','WidebandCQI','RIEstimate','TPMIEstimate','WidebandSRSSINR_dB'}), ...
    "ProducerSlot", 5, "AvailableSlot", 5, "Valid", true, ...
    "Direction", "UL", "SourceSignal", "SRS");
state = sixgr.truth.CoupledTruthRuntime.publishReferenceSignalMeasurementRuntime( ...
    state, "CSI-RS", "UE", 1, table(4, 11, 2, ...
    'VariableNames', {'Slot','WidebandCQI','RI'}), ...
    "ProducerSlot", 4, "AvailableSlot", 8, "Valid", true, ...
    "Direction", "DL", "SourceSignal", "CSI-RS");
state = sixgr.truth.CoupledTruthRuntime.publishReferenceSignalMeasurementRuntime( ...
    state, "TRS", "CELL", 1, table(3, 0, 0, ...
    'VariableNames', {'Slot','EstimatedTimingOffset_samples','EstimatedCFO_Hz'}), ...
    "ProducerSlot", 3, "AvailableSlot", 3, "Valid", true, ...
    "Direction", "DL", "SourceSignal", "TRS");

srsNow = sixgr.truth.CoupledTruthRuntime.consumeReferenceSignalMeasurementRuntime(state, "SRS", "UE", 1, 6, 2);
assert(logical(srsNow.Usable) && double(srsNow.AgeSlots) == 1, ...
    "SRS measurement must be usable only after production and with explicit age.");

csirsFuture = sixgr.truth.CoupledTruthRuntime.consumeReferenceSignalMeasurementRuntime(state, "CSI-RS", "UE", 1, 6, 10);
assert(~logical(csirsFuture.Usable) && strcmp(string(csirsFuture.Status), "future_measurement_not_available"), ...
    "CSI-RS-derived CSI must not be consumable before its feedback available slot.");
csirsReady = sixgr.truth.CoupledTruthRuntime.consumeReferenceSignalMeasurementRuntime(state, "CSI-RS", "UE", 1, 8, 10);
assert(logical(csirsReady.Usable) && double(csirsReady.AvailableSlot) == 8, ...
    "CSI-RS-derived CSI must become consumable at its configured available slot.");

srsStale = sixgr.truth.CoupledTruthRuntime.consumeReferenceSignalMeasurementRuntime(state, "SRS", "UE", 1, 9, 2);
assert(~logical(srsStale.Usable) && strcmp(string(srsStale.Status), "stale"), ...
    "Reference-signal consumers must reject measurements older than the configured age.");

trs = sixgr.truth.CoupledTruthRuntime.consumeReferenceSignalMeasurementRuntime(state, "TRS", "CELL", 1, 4, 2);
assert(logical(trs.Usable) && double(trs.AgeSlots) == 1, ...
    "TRS tracking measurements must share the same causal producer/consumer contract.");
end
