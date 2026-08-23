function ok = testSIB1ToFourStepRAIntegration()
%TESTSIB1TOFOURSTEPRANINTEGRATION Decoded SIB1 must bind PRACH/RA.

setup6GRSimToolkit("Verbose", false);
if exist("nrWaveformGenerator", "file") ~= 2
    ok = true;
    return;
end
[supported, ~] = sixgr.phy.broadcast.siRNTIWaveformSupported();
if ~supported
    ok = true;
    return;
end

cfg = localCfg();
tx = sixgr.phy.broadcast.generateSSB_MIB_SIB1_Waveform(cfg, "SNRdB", 35, "Seed", 1701);
rx = sixgr.phy.broadcast.recoverSIB1FromWaveform(tx.Waveform, cfg);
assert(logical(rx.StrictOk), "SIB1 decode must pass before RA integration test.");

poisoned = cfg;
poisoned.random_access.configuration_index = 87;
poisoned.random_access.root_sequence_index = 111;
poisoned.random_access.zero_correlation_zone = 1;
poisoned.random_access.restricted_set = "RestrictedSetTypeA";
poisoned.random_access.subcarrier_spacing_khz = 30;
poisoned.random_access.prach_format = "A1";
poisoned.random_access.ra_response_window_slots = 1;
poisoned.random_access.preamble_received_target_power_dbm = -120;
poisoned.random_access.power_ramping_step_db = 6;
poisoned.random_access.preamble_trans_max = 1;
poisoned.random_access.binding_source = "scenario_config_pending_sib1";

runFolder = fullfile(tempdir, "sixgr_test_sib1_to_ra");
if exist(runFolder, "dir")
    rmdir(runFolder, "s");
end
res = sixgr.phy.ra.runFourStepRA(poisoned, ...
    "RunFolder", runFolder, ...
    "RunId", "test_sib1_to_ra", ...
    "ScenarioName", "test_sib1_to_ra", ...
    "SIB1Recovery", rx, ...
    "WriteArtifacts", true);

assert(logical(res.StrictOk) && logical(res.RACompleted), ...
    "Four-step RA must complete after installing decoded SIB1 RACH config.");
assert(logical(res.RRCSetupRequestDecoded) && ...
    logical(res.RRCSetupDecoded) && ...
    logical(res.RRCSetupCompleteCRC) && logical(res.RRCConnected), ...
    "Initial access must not complete before waveform-backed RRCSetupComplete.");
assert(string(res.RABindingSource) == "decoded_sib1_rach_config_common", ...
    "RA binding source must switch to decoded SIB1.");
assert(logical(res.SIB1RACHBindingApplied), ...
    "RA result must disclose that decoded SIB1 RACH binding was applied.");
bind = res.ArtifactTables.sib1_rach_config_binding;
assert(istable(bind) && height(bind) >= 8, ...
    "SIB1-to-RA binding table must be present.");
assert(localBindingValue(bind, "configuration_index") == cfg.random_access.configuration_index, ...
    "PRACH configuration index must come from decoded SIB1, not poisoned scenario config.");
assert(localBindingValue(bind, "root_sequence_index") == cfg.random_access.root_sequence_index, ...
    "Root sequence index must come from decoded SIB1.");
assert(localBindingValue(bind, "zero_correlation_zone") == cfg.random_access.zero_correlation_zone, ...
    "Zero-correlation-zone config must come from decoded SIB1.");
assert(string(localBindingText(bind, "restricted_set")) == string(cfg.random_access.restricted_set), ...
    "Restricted-set config must come from decoded SIB1, not poisoned scenario config.");
assert(localBindingValue(bind, "subcarrier_spacing_khz") == cfg.random_access.subcarrier_spacing_khz, ...
    "PRACH Msg1 SCS must come from decoded SIB1, not poisoned scenario config.");
csvPath = fullfile(runFolder, "control", "csv", "sib1_rach_config_binding.csv");
assert(exist(csvPath, "file") == 2, "RA artifacts must export SIB1 RACH binding CSV.");
assert(exist(fullfile(runFolder, "control", "csv", "rach_config_from_decoded_sib1.csv"), "file") == 2, ...
    "RA artifacts must export decoded SIB1 RACH ownership CSV.");
assert(exist(fullfile(runFolder, "reports", "csv", "phase4_decoded_config_ownership_audit.csv"), "file") == 2, ...
    "RA artifacts must export Phase 4 decoded-config ownership audit CSV.");
rrcSetupComplete = res.ArtifactTables.rrc_setup_complete;
assert(istable(rrcSetupComplete) && height(rrcSetupComplete) == 1 && ...
    logical(rrcSetupComplete.CRC(1)) && logical(rrcSetupComplete.Decoded(1)) && ...
    logical(rrcSetupComplete.SRB1Installed(1)) && ...
    logical(rrcSetupComplete.RRCConnected(1)) && ...
    string(rrcSetupComplete.Status(1)) == "PASS" && ...
    strlength(string(rrcSetupComplete.PayloadSHA256(1))) == 64, ...
    "RA truth artifacts must include the decoded waveform-backed SRB1 RRCSetupComplete row.");
assert(exist(fullfile(runFolder, "control", "csv", "rrc_setup_complete.csv"), "file") == 2, ...
    "RA artifacts must export canonical rrc_setup_complete.csv evidence.");

threw = false;
try
    sixgr.phy.ra.runFourStepRA(cfg, "RequireDecodedSIB1", true, "WriteArtifacts", false);
catch ME
    threw = strcmp(string(ME.identifier), "sixgr:mac:ra:UE_RACH_CONFIG_ORACLE_READ") || ...
        contains(string(ME.message), "UE_RACH_CONFIG_ORACLE_READ");
end
assert(threw, "Phase 4 RA must fail closed if decoded SIB1 ownership is required but absent.");

integrated = sixgr.phy.broadcast.runInitialAccessWithRAAnchor(fullfile(tempdir, "sixgr_test_initial_access_ra"), cfg, ...
    "RunId", "test_initial_access_ra", "ScenarioName", "test_initial_access_ra");
assert(logical(integrated.Ok) && logical(integrated.SIB1Ok) && logical(integrated.RAOk), ...
    "Integrated SSB/PBCH/SIB1/RA anchor must pass end-to-end.");

miniRunFolder = fullfile(tempdir, "sixgr_test_sib1_mini_anchor_ra");
if exist(miniRunFolder, "dir")
    rmdir(miniRunFolder, "s");
end
cfg.random_access.require_runtime_stage_waveforms = true;
cfg.random_access.allow_runtime_stage_waveform_composition = true;
cfg.random_access.use_runtime_channel = true;
mini = sixgr.phy.broadcast.runSIB1StrictMiniAnchor( ...
    miniRunFolder, cfg, "RunNegativeSuite", false);
assert(logical(mini.Ok) && logical(mini.RandomAccessRequested) && logical(mini.RAOk), ...
    "SIB1 strict mini-anchor must continue into four-step RA when random_access.enabled=true.");
assert(logical(mini.RandomAccess.RuntimeChannelStateUsed) && ...
    logical(mini.RandomAccess.RuntimeStageWaveformsUsed) && ...
    ~logical(mini.RandomAccess.RuntimeSelfLoopWaveformsUsed), ...
    ["Runtime-required SIB1-to-RA continuation must propagate every stage " + ...
     "through measured runtime channel state, never a self-loop."]);
assert(exist(fullfile(miniRunFolder, "control", "csv", "ra_attempts.csv"), "file") == 2, ...
    "Mini-anchor RA continuation must export RA attempts.");
tracePath = fullfile(miniRunFolder, "control", "csv", "initial_access_lifecycle_trace.csv");
assert(exist(tracePath, "file") == 2, ...
    "Mini-anchor RA continuation must export an initial-access lifecycle trace.");
trace = readtable(tracePath, "TextType", "string");
assert(any(string(trace.StageName) == "RA_MSG4_CONTENTION_RESOLUTION" & logical(trace.Completed)), ...
    "Lifecycle trace must prove Msg4 contention resolution completed.");
assert(any(string(trace.StageName) == "RRC_SETUP_COMPLETE_SRB1" & logical(trace.Completed)), ...
    "Lifecycle trace must prove SRB1 RRCSetupComplete decoded at the gNB.");

ok = true;
end

function cfg = localCfg()
cfg = raStrictAnchorConfig();
cfg.phy.sib1.enable = true;
cfg.phy.sib1.ssbObservationSubframes = 5;
cfg.phy.sib1.coreset0Index = 0;
cfg.phy.sib1.searchSpaceZero = 0;
cfg.phy.mib.pdcchConfigSIB1 = 0;
cfg.phy.mib.dmrsTypeAPosition = 2;
cfg.phy.prach.configurationIndex = double(cfg.random_access.configuration_index);
cfg.phy.prach.rootSeqIndex = double(cfg.random_access.root_sequence_index);
cfg.phy.prach.zeroCorrelationZone = double(cfg.random_access.zero_correlation_zone);
cfg.phy.prach.nPreambles = 64;
cfg.phy.prach.preambleFormat = string(cfg.random_access.prach_format);
end

function value = localBindingValue(T, name)
idx = find(string(T.Parameter) == string(name), 1);
assert(~isempty(idx), "Missing SIB1 binding parameter " + string(name));
value = str2double(string(T.ValueAfter(idx)));
end

function value = localBindingText(T, name)
idx = find(string(T.Parameter) == string(name), 1);
assert(~isempty(idx), "Missing SIB1 binding parameter " + string(name));
value = string(T.ValueAfter(idx));
end
