function ok = testMasterScenarioPrompt1YAMLRuntimeWiring()
%TESTMASTERSCENARIOPROMPT1YAMLRUNTIMEWIRING Guard the WebGUI master YAML Prompt-1 fixes.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);

scenarioDir = fullfile(pwd, "simulator", "configs", "scenarios");
masterPath = fullfile(scenarioDir, "master_scenaio_all_file.yaml");
assert(exist(masterPath, "file") == 2, "Missing master_scenaio_all_file.yaml.");

localAssertScenario(masterPath, "master");

webRuntimeFiles = dir(fullfile(scenarioDir, "__web_runtime_*.yaml"));
for idx = 1:numel(webRuntimeFiles)
    localAssertScenario(fullfile(webRuntimeFiles(idx).folder, webRuntimeFiles(idx).name), ...
        "web runtime " + string(webRuntimeFiles(idx).name));
end

ok = true;
end

function localAssertScenario(configPath, label)
scfg = sixgr.lls6g.config.loadScenarioConfig(configPath);
resolved = scfg.toStruct();

expectedDopplerHz = (100 / 3.6) * 4.0e9 / 299792458;

assert(strcmpi(char(string(sixgr.util.structGet(resolved, "channels.profile", ""))), "CDL-C"), ...
    "%s must resolve channels.profile to CDL-C.", label);
assert(strcmpi(char(string(sixgr.util.structGet(resolved, "channel_model.scenario_label", ""))), "CDL-C"), ...
    "%s must mirror CDL-C into channel_model.scenario_label.", label);
assert(strcmpi(char(string(sixgr.util.structGet(resolved, "random_access.channel_model", ""))), "CDL-C"), ...
    "%s must run PRACH/RA on CDL-C.", label);
localAssertStrictFourStepRAConfig(resolved, label + " resolved");
assert(abs(double(sixgr.util.structGet(resolved, "channels.delay_spread_ns", NaN)) - 93) < 1e-12, ...
    "%s must use 93 ns UMa delay spread.", label);
assert(abs(double(sixgr.util.structGet(resolved, "channels.doppler_hz", NaN)) - expectedDopplerHz) < 1e-6, ...
    "%s must derive Doppler from 100 km/h at 4 GHz.", label);
assert(abs(double(sixgr.util.structGet(resolved, "channels.max_doppler_hz", NaN)) - expectedDopplerHz) < 1e-6, ...
    "%s must mirror resolved Doppler into channels.max_doppler_hz.", label);
assert(~logical(sixgr.util.structGet(resolved, "channels.los_enabled", true)), ...
    "%s must not keep the LOS-biased CDL-D setting.", label);
assert(abs(double(sixgr.util.structGet(resolved, "mobility.ue_speed_kmh", NaN)) - 100) < 1e-12, ...
    "%s must resolve UE mobility to 100 km/h.", label);
assert(strcmpi(char(string(sixgr.util.structGet(resolved, "mobility.trajectory_model", ""))), "linear"), ...
    "%s must expose linear trajectory mobility.", label);
assert(strcmpi(char(string(sixgr.util.structGet(resolved, "link_adaptation.rank_adaptation_policy", ""))), "dynamic"), ...
    "%s must use dynamic rank adaptation.", label);
assert(strcmpi(char(string(sixgr.util.structGet(resolved, "link_adaptation.al_adaptation_policy", ""))), "dynamic"), ...
    "%s must use dynamic PDCCH aggregation-level adaptation.", label);
assert(strcmpi(char(string(sixgr.util.structGet(resolved, "link_adaptation.bootstrap_cqi_mode", ""))), "estimated"), ...
    "%s must bootstrap CQI from measurements.", label);
assert(abs(double(sixgr.util.structGet(resolved, "link_adaptation.olla_step_down", NaN)) - 0.1) < 1e-12, ...
    "%s must use OLLA down step 0.1.", label);
assert(abs(double(sixgr.util.structGet(resolved, "link_adaptation.olla_step_up", NaN)) - 0.01) < 1e-12, ...
    "%s must use OLLA up step 0.01.", label);
assert(strcmpi(char(string(sixgr.util.structGet(resolved, "harq.validation_mode", ""))), "closed_loop"), ...
    "%s must use closed-loop HARQ validation.", label);
assert(logical(sixgr.util.structGet(resolved, "interference.inter_cell_interference_flag", false)), ...
    "%s must enable inter-cell interference.", label);
assert(~logical(sixgr.util.structGet(resolved, "interference.intra_cell_interference_flag", true)), ...
    "%s must leave intra-cell interference disabled by default.", label);
assert(~logical(sixgr.util.structGet(resolved, "sweeps_and_matrix.snr_sweep.enabled", true)), ...
    "%s must disable injected SNR sweep mode.", label);
assert(isempty(double(sixgr.util.structGet(resolved, "simulation.snr_sweep_offsets_db", 1))), ...
    "%s must resolve an empty SNR sweep offset vector.", label);

tmp = tempname;
mkdir(tmp);
cleanup = onCleanup(@() localCleanupTempFolder(tmp)); %#ok<NASGU>
cfg = sixgr.lls6g.buildInternalConfig(scfg, fullfile(tmp, "run"));

assert(strcmpi(char(string(sixgr.util.structGet(cfg, "channel.model", ""))), "CDL"), ...
    "%s must build a CDL channel.", label);
assert(strcmpi(char(string(sixgr.util.structGet(cfg, "channel.cdlProfile", ""))), "CDL-C"), ...
    "%s must apply CDL-C internally.", label);
assert(abs(double(sixgr.util.structGet(cfg, "channel.delaySpread_s", NaN)) - 93e-9) < 1e-15, ...
    "%s must apply 93 ns internally.", label);
assert(abs(double(sixgr.util.structGet(cfg, "channel.doppler_Hz", NaN)) - expectedDopplerHz) < 1e-6, ...
    "%s must apply derived 100 km/h Doppler internally.", label);
assert(abs(double(sixgr.util.structGet(cfg, "channel.maxDoppler_Hz", NaN)) - expectedDopplerHz) < 1e-6, ...
    "%s must expose channel.maxDoppler_Hz for runtime diagnostics.", label);
assert(abs(double(sixgr.util.structGet(cfg, "channel.fading.maxDoppler_Hz", NaN)) - expectedDopplerHz) < 1e-6, ...
    "%s must expose channel.fading.maxDoppler_Hz for channel factory use.", label);
assert(~logical(sixgr.util.structGet(cfg, "channel.losEnabled", true)), ...
    "%s must keep LOS disabled internally.", label);
multiUser = struct("NumUsers", double(sixgr.util.structGet(cfg, "scenario.nUE", 1)));
runtimeState = sixgr.truth.CoupledTruthRuntime.initialize(cfg, fullfile(tmp, "runtime_init"), multiUser, struct(), 1);
assert(~logical(sixgr.util.structGet(runtimeState.CfgLargeScale, "channel.losEnabled", true)), ...
    "%s must keep LOS disabled in coupled large-scale runtime.", label);
assert(~logical(runtimeState.PLModel.LOSEnabled), ...
    "%s must instantiate TR38901Plus with LOS disabled.", label);
assert(logical(sixgr.util.structGet(runtimeState.CfgLargeScale, "channel.pathlossEnabled", false)), ...
    "%s must keep pathloss enabled in coupled large-scale runtime.", label);
assert(logical(sixgr.util.structGet(runtimeState.CfgLargeScale, "channel.shadowFadingEnabled", false)), ...
    "%s must keep shadow fading enabled in coupled large-scale runtime.", label);
assert(all(abs(double(sixgr.util.structGet(cfg, "scenario.mobility.speed_kmh", NaN)) - 100) < 1e-12), ...
    "%s must apply 100 km/h mobility internally.", label);
assert(strcmpi(char(string(sixgr.util.structGet(cfg, "scenario.mobility.model", ""))), "straightLine"), ...
    "%s must map linear YAML mobility to straightLine runtime mobility.", label);
assert(strcmpi(char(string(sixgr.util.structGet(cfg, "phy.linkAdaptation.rankPolicy", ""))), "dynamic"), ...
    "%s must wire dynamic rank policy internally.", label);
assert(strcmpi(char(string(sixgr.util.structGet(cfg, "phy.linkAdaptation.alPolicy", ""))), "dynamic"), ...
    "%s must wire dynamic AL policy internally.", label);
assert(strcmpi(char(string(sixgr.util.structGet(cfg, "phy.linkAdaptation.bootstrapCQIMode", ""))), "estimated"), ...
    "%s must wire measured bootstrap CQI internally.", label);
assert(abs(double(sixgr.util.structGet(cfg, "phy.linkAdaptation.ollaStepDown", NaN)) - 0.1) < 1e-12, ...
    "%s must wire OLLA down step internally.", label);
assert(abs(double(sixgr.util.structGet(cfg, "phy.linkAdaptation.ollaStepUp", NaN)) - 0.01) < 1e-12, ...
    "%s must wire OLLA up step internally.", label);
assert(strcmpi(char(string(sixgr.util.structGet(cfg, "phy.harq.validationMode", ""))), "closed_loop"), ...
    "%s must wire closed-loop HARQ internally.", label);
assert(logical(sixgr.util.structGet(cfg, "channel.interference.interCellEnabled", false)), ...
    "%s must expose inter-cell interference on the internal channel config.", label);
assert(~logical(sixgr.util.structGet(cfg, "channel.interference.intraCellEnabled", true)), ...
    "%s must expose disabled intra-cell interference on the internal channel config.", label);
assert(strcmpi(char(string(sixgr.util.structGet(cfg, "run.interferenceExecutionMode", ""))), ...
    "full_per_link_channel_waveform_sum"), ...
    "%s must use waveform-backed inter-cell interference.", label);
assert(~logical(sixgr.util.structGet(cfg, "run.snrSweepEnabled", true)), ...
    "%s must disable injected SNR sweep execution internally.", label);
assert(isempty(double(sixgr.util.structGet(cfg, "run.snrSweepOffsets_dB", 1))), ...
    "%s must expose an empty SNR sweep vector internally.", label);
assert(strcmpi(char(string(sixgr.util.structGet(cfg, "run.noiseOperatingMode", ""))), ...
    "receiver_noise_figure_thermal_noise"), ...
    "%s must use receiver thermal-noise operation rather than configured-SNR injection.", label);
localAssertStrictFourStepRAConfig(cfg, label + " internal");
end

function localAssertStrictFourStepRAConfig(cfg, label)
required = [ ...
    "random_access.binding_source"
    "random_access.restricted_set"
    "random_access.frequency_start"
    "random_access.ra_response_window_slots"
    "random_access.ra_contention_resolution_timer_slots"
    "random_access.preamble_trans_max"
    "random_access.power_ramping_step_db"
    "random_access.preamble_received_target_power_dbm"
    "random_access.temp_crnti"
    "random_access.final_crnti"
    "random_access.msg2_slot"
    "random_access.msg3_slot"
    "random_access.msg4_slot"
    "random_access.dci_payload_bits"
    "random_access.msg2_pdsch.prb_start"
    "random_access.msg2_pdsch.num_prb"
    "random_access.msg2_pdsch.symbol_start"
    "random_access.msg2_pdsch.num_symbols"
    "random_access.msg2_pdsch.modulation"
    "random_access.msg2_pdsch.target_code_rate"
    "random_access.msg3_pusch.prb_start"
    "random_access.msg3_pusch.num_prb"
    "random_access.msg3_pusch.symbol_start"
    "random_access.msg3_pusch.num_symbols"
    "random_access.msg3_pusch.mcs"
    "random_access.msg3_pusch.modulation"
    "random_access.msg3_pusch.target_code_rate"
    "random_access.msg4_pdsch.prb_start"
    "random_access.msg4_pdsch.num_prb"
    "random_access.msg4_pdsch.symbol_start"
    "random_access.msg4_pdsch.num_symbols"
    "random_access.msg4_pdsch.modulation"
    "random_access.msg4_pdsch.target_code_rate"];
for idx = 1:numel(required)
    value = sixgr.util.structGet(cfg, required(idx), []);
    assert(~isempty(value), "%s must preserve strict four-step RA field %s.", ...
        label, required(idx));
end
assert(strcmpi(char(string(sixgr.util.structGet(cfg, "random_access.binding_source", ""))), ...
    "scenario_config_pending_sib1"), ...
    "%s must disclose scenario_config_pending_sib1 RA binding until decoded SIB1 owns the config.", label);
assert(strcmpi(char(string(sixgr.util.structGet(cfg, "random_access.restricted_set", ""))), ...
    "UnrestrictedSet"), ...
    "%s must use strict-supported UnrestrictedSet PRACH.", label);
end

function localCleanupTempFolder(tmp)
if isfolder(tmp)
    rmdir(tmp, "s");
end
end
