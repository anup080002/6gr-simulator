function ok = testPersistedPrimaryReductionAuthorityFDDTDD()
%TESTPERSISTEDPRIMARYREDUCTIONAUTHORITYFDDTDD Final reducers use canonical rows.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
root = fileparts(fileparts(mfilename("fullpath")));
scenarioDir = fullfile(root, "simulator", "configs", "scenarios");
scenarioPaths = [ ...
    fullfile(scenarioDir, "lls_causal_access_to_data_wiring.yaml"), ...
    fullfile(scenarioDir, "lls_causal_access_to_data_wiring_tdd.yaml")];

for scenarioPath = scenarioPaths
    scenario = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
    cfg = sixgr.lls6g.buildInternalConfig(scenario, string(tempname));
    runRoot = string(tempname);
    cleanup = onCleanup(@()localRemoveTree(runRoot)); %#ok<NASGU>
    csvDir = fullfile(runRoot, "air_interface", "csv");
    mkdir(csvDir);

    dl = localPrimaryRow("DL", 11, 5, "QPSK");
    ul = localPrimaryRow("UL", 15, 12, "16QAM");
    sixgr.util.csvWriteTable(fullfile(csvDir, "dl_pdsch_trials.csv"), dl);
    sixgr.util.csvWriteTable(fullfile(csvDir, "ul_pusch_trials.csv"), ul);

    % This models a live callback snapshot retained before the primary row
    % gained its finalized PHY schema.  It has the same cardinality but is
    % not acceptable evidence for a terminal reduction.
    stale = table(1, 'VariableNames', {'SnapshotOrdinal'});
    raw = struct("DL", stale, "UL", stale);
    loaded = sixgr.kpi.loadDirectionRawTables( ...
        struct("RawTrials", raw, "Config", cfg), ...
        "RunFolder", runRoot, "PreferPersistedPrimary", true);

    assert(height(loaded.DL) == 1 && height(loaded.UL) == 1);
    assert(double(loaded.DL.MCS(1)) == 5 && double(loaded.UL.MCS(1)) == 12);
    assert(all(contains(string(loaded.PrimarySourceReconciliation.Status), ...
        "canonical_persisted_selected")));

    exported = sixgr.mimo.exportMIMOEvidenceArtifacts(runRoot, cfg, raw, ...
        "RunId", "persisted_primary_" + lower(string(cfg.phy.duplex.mode)), ...
        "ScenarioName", "duplex_neutral_primary_reduction", ...
        "StrictMode", false);
    rankT = exported.Evidence.RankLayerTrials;
    dlRank = rankT(string(rankT.Direction) == "DL", :);
    ulRank = rankT(string(rankT.Direction) == "UL", :);
    assert(double(dlRank.Slot(1)) == 11 && double(dlRank.ScheduledMCS(1)) == 5);
    assert(double(ulRank.Slot(1)) == 15 && double(ulRank.ScheduledMCS(1)) == 12);
    assert(string(dlRank.ScheduledModulation(1)) == "QPSK");
    assert(string(ulRank.ScheduledModulation(1)) == "16QAM");
end

ok = true;
fprintf("[PASS] testPersistedPrimaryReductionAuthorityFDDTDD canonical FDD/TDD reduction authority retained.\n");
end

function T = localPrimaryRow(direction, slot, mcs, modulation)
T = table(string(direction), 2, double(slot), 1, 1, double(mcs), ...
    double(mcs), string(modulation), string(modulation), 1, 1, 1, 1, 1, ...
    1, 1, 2, 2, "18.5", true, true, true, true, true, ...
    "scheduler_grant", "runtime_cqi_table", ...
    'VariableNames', {'Direction','Frame','Slot','UEID','ServingCell', ...
    'MCS','ScheduledMCS','Modulation','ScheduledModulation','Layers', ...
    'ConfiguredLayers','RankIndicator','Rank','EffectiveRank', ...
    'NumTxPorts','TxWaveformColumns','PhysicalTxAntennas', ...
    'RxWaveformBranches','PostEqSINRPerLayer_dB','CRCPass', ...
    'DecodeUsable','ReceiverUsable','LinkAdaptationScheduled', ...
    'LinkAdaptationApplied','ActualMCSSelectionMode','MCSSelectionSource'});
end

function localRemoveTree(path)
if isfolder(path)
    rmdir(path, "s");
end
end
