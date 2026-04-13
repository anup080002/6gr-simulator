function ok = test6GScenarioPromptCompliance()
%TEST6GSCENARIOPROMPTCOMPLIANCE Guard prompt-required 6G config-driven assets.

setup6GRSimToolkit("Verbose", false);

repoRoot = pwd;
configRoot = fullfile(repoRoot, "simulator", "configs");

bandFiles = [ ...
    "band_700mhz.yaml"
    "band_2ghz.yaml"
    "band_4ghz.yaml"
    "band_7ghz.yaml"
    "band_15ghz.yaml"
    "band_30ghz.yaml"];
for i = 1:numel(bandFiles)
    bandPath = fullfile(configRoot, "bands", bandFiles(i));
    assert(exist(bandPath, "file") == 2, "Missing shipped band pack %s.", bandFiles(i));
    raw = sixgr.lls6g.config.readConfigFile(bandPath);
    assert(isfield(raw.frequency, "energy_model_defaults"), "Band pack %s must define energy_model_defaults.", bandFiles(i));
    assert(isfield(raw.frequency, "rf_impairment_defaults"), "Band pack %s must define rf_impairment_defaults.", bandFiles(i));
end

scenarioFiles = [ ...
    "dl_700mhz_coverage.yaml"
    "dl_4ghz_baseline.yaml"
    "dl_7ghz_mimo4x4.yaml"
    "dl_30ghz_beam_tracking.yaml"
    "ul_4ghz_cpofdm.yaml"
    "ul_4ghz_dfts_pi2bpsk.yaml"
    "ul_7ghz_srs_csi.yaml"
    "ul_30ghz_impairment_stress.yaml"
    "pdcch_blind_decode_sweep.yaml"
    "prach_detection.yaml"
    "harq_process_sweep.yaml"
    "bandwidth_operation_profiles.yaml"
    "ce_non_ai_baseline.yaml"
    "ce_ai_nn.yaml"
    "csi_non_ai_baseline.yaml"
    "csi_ai_autoencoder.yaml"
    "beam_prediction_ai.yaml"
    "energy_aware_ai_mode_select.yaml"
    "high_doppler_stress.yaml"
    "low_snr_stress.yaml"
    "phase_noise_stress.yaml"
    "cfo_stress.yaml"
    "high_order_modulation_stress.yaml"
    "rank_adaptation_sweep.yaml"];
for i = 1:numel(scenarioFiles)
    scenarioPath = fullfile(configRoot, "scenarios", scenarioFiles(i));
    assert(exist(scenarioPath, "file") == 2, "Missing shipped scenario %s.", scenarioFiles(i));
end

matrixCfg = sixgr.lls6g.config.readConfigFile(fullfile(configRoot, "scenarios", "matrix_regression.yaml"));
sixgr.lls6g.config.validateScenarioConfig(matrixCfg, "Kind", "matrix", "AllowPartial", false, ...
    "Context", "matrix_regression.yaml");
assert(numel(matrixCfg.scenarios) == numel(scenarioFiles), "Matrix regression must include all 24 shipped scenarios.");

registry = sixgr.lls6g.config.scenarioRegistry();
registryIDs = string(registry.ScenarioID);
assert(height(registry) >= numel(scenarioFiles), "Scenario registry should expose the shipped scenario set.");
for i = 1:numel(scenarioFiles)
    scenarioId = erase(scenarioFiles(i), ".yaml");
    assert(any(registryIDs == scenarioId), "Scenario registry missing %s.", scenarioId);
end

tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>

scenarioPath = fullfile(tmp, "prompt_contract.yaml");
fid = fopen(scenarioPath, "w");
fprintf(fid, "%s", ['{' ...
    '"inherits":["' strrep(fullfile(configRoot, "scenarios", "dl_4ghz_baseline.yaml"), '\', '\\') '"],' ...
    '"meta":{"scenario_id":"prompt_contract_case","description":"prompt contract","version":"1","owner":"test","maturity_tag":"smoke"},' ...
    '"reference_signals":{"cqi_reporting_enabled":false,"pmi_reporting_enabled":true,"ri_reporting_enabled":true},' ...
    '"mimo":{"multi_panel_ready":true,"panel_count":2},' ...
    '"modulation":{"dl_mcs_index":17,"ul_mcs_index":13},' ...
    '"control":{"pucch_format":3},' ...
    '"random_access":{"configuration_index":86},' ...
    '"energy_efficiency":{"ai_compute_energy_per_flop_score":2e-6}}']);
fclose(fid);

scfg = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
cfg = sixgr.lls6g.buildInternalConfig(scfg, fullfile(tmp, "run"));
assert(cfg.phy.pdsch.mcsIndex == 17, "DL MCS must come from scenario config.");
assert(cfg.phy.pusch.mcsIndex == 13, "UL MCS must come from scenario config.");
assert(cfg.phy.pucch.format == 3, "PUCCH format must come from scenario config.");
assert(cfg.phy.prach.configurationIndex == 86, "PRACH configuration must come from scenario config.");
assert(~sixgr.util.structGet(cfg, "phy.csi.reportCQI"), "CQI reporting hook must come from scenario config.");
assert(logical(sixgr.util.structGet(cfg, "phy.beamManagement.multiPanelReady")), "Multi-panel readiness hook must come from scenario config.");
assert(double(sixgr.util.structGet(cfg, "phy.beamManagement.panelCount")) == 2, "Panel count must come from scenario config.");
assert(abs(double(sixgr.util.structGet(cfg, "lls6g.energy_efficiency.ai_compute_energy_per_flop_score")) - 2e-6) < 1e-12, ...
    "Energy-per-FLOP score must come from scenario config.");
assert(strcmpi(string(sixgr.util.structGet(cfg, "scenario.id", "")), "prompt_contract_case"), ...
    "Scenario identifier must remain available as provenance metadata.");
assert(strcmpi(string(sixgr.util.structGet(cfg, "scenario.profileName", "")), "InH"), ...
    "Scenario profile name must come from the deployment topology, not the scenario ID.");
assert(strcmpi(string(sixgr.util.structGet(cfg, "scenario.name", "")), "InH"), ...
    "scenario.name must mirror the resolved profile/layout selector after normalization.");
assert(strcmpi(string(sixgr.util.structGet(cfg, "channel.propagationScenario", "")), "InH"), ...
    "Propagation scenario must come from the deployment topology, not the scenario ID.");
assert(strcmpi(string(sixgr.util.structGet(cfg, "run.scenario", "")), "InH"), ...
    "Legacy run.scenario alias must mirror the resolved propagation scenario.");
assert(abs(double(sixgr.util.structGet(cfg, "phy.fc_Hz", NaN)) - double(sixgr.util.structGet(cfg, "channel.fc_Hz", NaN))) < 1e-9, ...
    "Canonical phy.fc_Hz alias must mirror channel.fc_Hz.");
assert(strcmpi(string(sixgr.util.structGet(cfg, "channel.pathlossModel", "")), "nrPathLoss"), ...
    "Canonical channel.pathlossModel alias must mirror channel.pathloss.model.");
assert(double(sixgr.util.structGet(cfg, "channel.shadowSigma_dB", NaN)) == 6, ...
    "Canonical channel.shadowSigma_dB alias must mirror channel.shadowFadingStd_dB.");
assert(strcmpi(cfg.channel.pathloss.model, "nrPathLoss"), "Pathloss model must come from scenario config.");
assert(cfg.channel.shadowFadingStd_dB == 6, "Shadow-fading sigma must come from scenario config.");
assert(cfg.phy.pdsch.dmrs.configType == 1, "PDSCH DMRS config type must come from scenario config.");
assert(cfg.phy.pdsch.dmrs.typeApos == 2, "PDSCH DMRS type-A position must come from scenario config.");
assert(cfg.phy.pdsch.dmrs.numCDMGroupsWithoutData == 2, "PDSCH DMRS CDM groups must come from scenario config.");

pl = sixgr.channel.TR38901Plus(cfg);
assert(strcmpi(string(pl.Scenario), "InH"), ...
    "TR38901Plus must resolve the propagation scenario rather than the scenario identifier.");
assert(abs(double(pl.Fc_Hz) - double(sixgr.util.structGet(cfg, "channel.fc_Hz", NaN))) < 1e-9, ...
    "TR38901Plus must resolve carrier frequency from the normalized cfg.");
assert(strcmpi(string(pl.PathlossModel), "nrPathLoss"), ...
    "TR38901Plus must resolve the canonical pathloss model.");
assert(double(pl.ShadowSigma_dB) == 6, ...
    "TR38901Plus must resolve the canonical shadow-fading sigma.");

legacyCfg = struct();
legacyCfg = sixgr.util.structSet(legacyCfg, "scenario.profileName", "RMa");
legacyCfg = sixgr.util.structSet(legacyCfg, "channel.propagationScenario", "RMa");
legacyCfg = sixgr.util.structSet(legacyCfg, "channel.fc_Hz", 2.1e9);
legacyCfg = sixgr.util.structSet(legacyCfg, "channel.pathloss.model", "ABG");
legacyCfg = sixgr.util.structSet(legacyCfg, "channel.shadowFadingStd_dB", 7);
plLegacy = sixgr.channel.TR38901Plus(legacyCfg);
assert(strcmpi(string(plLegacy.Scenario), "RMa"), ...
    "TR38901Plus must prefer channel.propagationScenario / scenario.profileName when run.scenario is absent.");
assert(abs(double(plLegacy.Fc_Hz) - 2.1e9) < 1e-9, ...
    "TR38901Plus must fall back to channel.fc_Hz when phy.fc_Hz is absent.");
assert(strcmpi(string(plLegacy.PathlossModel), "ABG"), ...
    "TR38901Plus must fall back to channel.pathloss.model when channel.pathlossModel is absent.");
assert(double(plLegacy.ShadowSigma_dB) == 7, ...
    "TR38901Plus must fall back to channel.shadowFadingStd_dB when channel.shadowSigma_dB is absent.");

ok = true;
end
