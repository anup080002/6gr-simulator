function ok = testInitialAccessMasterYAMLAuthority()
%TESTINITIALACCESSMASTERYAMLAUTHORITY Guard both operator IA config paths.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
root = fullfile(pwd, "simulator", "configs", "scenarios");
tmp = string(tempname);
mkdir(tmp);
cleanup = onCleanup(@() localCleanup(tmp)); %#ok<NASGU>

fixed = localLoadBuild(root, "master_sinr_sweep.yaml", tmp);
geometry = localLoadBuild(root, "master_geometry_based.yaml", tmp);

localAssertSurface(fixed.Raw, fixed.Cfg, false, false);
localAssertSurface(geometry.Raw, geometry.Cfg, true, true);

mutated = geometry.Raw;
mutated.canonical_control.initial_access.ssb.positions_in_burst = "11000000";
mutated.canonical_control.initial_access.ssb.beam_count = 2;
mutated.canonical_control.initial_access.mib.pdcch_config_sib1 = 1;
mutated.canonical_control.initial_access.sib1.pdsch.num_prb = 18;
mutated.canonical_control.initial_access.rrc.transaction_id = 2;
mutated.canonical_control.random_access.power_ramping_step_db = 4;
mutated.canonical_control.random_access.enable_frequency_estimation_metric = false;
path = fullfile(tmp, "mutated_initial_access_master.json");
sixgr.util.jsonWrite(path, mutated);
scfg = sixgr.lls6g.config.loadScenarioConfig(path);
cfg = sixgr.lls6g.buildInternalConfig(scfg, fullfile(tmp, "mutated"));
assert(string(cfg.phy.ssb.positionsInBurst) == "11000000");
assert(double(cfg.phy.ssb.beamCount) == 2);
assert(double(cfg.phy.mib.pdcchConfigSIB1) == 1);
assert(double(cfg.initial_access.sib1.pdsch.num_prb) == 18);
assert(double(cfg.initial_access.rrc.transaction_id) == 2);
assert(double(cfg.random_access.power_ramping_step_db) == 4);
assert(~logical(cfg.random_access.enable_frequency_estimation_metric), ...
    "Canonical random-access CFO-estimator authority must override an inherited legacy value.");

plan = sixgr.phy.ia.InitialAccessCapabilityRegistry.fromConfig(cfg);
assert(logical(plan.Executable) && ~logical(plan.Profile.ProxyAllowed) && ...
    string(plan.CompletionCriterion) == "RRCSetupComplete_accepted_by_gNB");
localAssertStrictAnchorCenteredSSB(tmp);
ok = true;
end

function out = localLoadBuild(root, name, tmp)
path = fullfile(root, name);
raw = sixgr.lls6g.config.readConfigFile(path);
scfg = sixgr.lls6g.config.loadScenarioConfig(path);
cfg = sixgr.lls6g.buildInternalConfig(scfg, ...
    fullfile(tmp, erase(name, ".yaml")));
out = struct("Raw", raw, "Cfg", cfg);
end

function localAssertSurface(raw, cfg, expectedEnabled, expectedRRC)
required = [ ...
    "canonical_control.initial_access.profile"
    "canonical_control.initial_access.ssb.case"
    "canonical_control.initial_access.ssb.positions_in_burst"
    "canonical_control.initial_access.mib.pdcch_config_sib1"
    "canonical_control.initial_access.type0.monitoring_occasion_ordinal"
    "canonical_control.initial_access.sib1.pdsch.num_prb"
    "canonical_control.initial_access.rrc.require_setup_complete"
    "canonical_control.random_access.ra_response_window_slots"
    "canonical_control.random_access.ra_contention_resolution_timer_slots"
    "canonical_control.random_access.enable_frequency_estimation_metric"
    "canonical_control.random_access.msg3_pusch.transform_precoding"
    "canonical_control.random_access.setup_complete_pusch.transform_precoding"];
for ii = 1:numel(required)
    assert(~isempty(sixgr.util.structGet(raw, required(ii), [])), ...
        "Master YAML is missing explicit initial-access field %s.", ...
        required(ii));
end

ia = raw.canonical_control.initial_access;
assert(logical(cfg.initial_access.enabled) == logical(expectedEnabled));
assert(logical(cfg.initial_access.rrc.require_setup_complete) == ...
    logical(expectedRRC));
assert(string(cfg.initial_access.profile) == string(ia.profile));
assert(string(cfg.phy.ssb.blockPattern) == string(ia.ssb.case));
assert(double(cfg.phy.ssb.scs_kHz) == double(ia.ssb.scs_khz));
assert(double(cfg.phy.ssb.Lmax) == double(ia.ssb.lmax));
assert(double(cfg.phy.ssb.beamCount) == double(ia.ssb.beam_count));
assert(string(cfg.phy.ssb.positionsInBurst) == ...
    string(ia.ssb.positions_in_burst));
assert(double(cfg.phy.mib.pdcchConfigSIB1) == ...
    double(ia.mib.pdcch_config_sib1));
assert(double(cfg.phy.mib.dmrsTypeAPosition) == ...
    double(ia.mib.dmrs_type_a_position));
assert(logical(cfg.phy.sib1.enable) == logical(ia.sib1.enabled));
assert(logical(cfg.random_access.enable_frequency_estimation_metric) == ...
    logical(raw.canonical_control.random_access.enable_frequency_estimation_metric), ...
    "PRACH receiver CFO-estimator enablement must remain YAML-authoritative.");
assert(isequal(cfg.random_access.setup_complete_pusch, ...
    raw.canonical_control.random_access.setup_complete_pusch), ...
    "RRCSetupComplete PUSCH must reach the production RA configuration unchanged.");
end

function localAssertStrictAnchorCenteredSSB(tmp)
% Regression for the canonical snake-case frequency aliases. Their loss
% previously made SSB_Tx place the block at an inaccessible path/default.
repoRoot = fileparts(fileparts(mfilename("fullpath")));
path = fullfile(repoRoot, "configs", "lls", ...
    "lls_ra_four_step_strict_mini_anchor.yaml");
raw = sixgr.lls6g.config.loadScenarioConfig(path);
cfg = sixgr.lls6g.buildInternalConfig(raw, ...
    fullfile(tmp, "strict_anchor_centered_ssb"));
assert(string(cfg.frequency.range_name) == "FR1");
assert(strlength(string(cfg.frequency.band_name)) > 0);
assert(isfinite(double(cfg.frequency.center_frequency_hz)));
assert(isfinite(double(cfg.frequency.bandwidth_hz)));

[waveform, ~, tx] = sixgr.phy.dl.SSB_Tx(cfg, "NumSubframes", 2);
assert(double(tx.SSBGridValidation.NCRBSSB) == 31);
assert(double(tx.SSBGridValidation.KSSB) == 0);
[grid, sync] = sixgr.phy.dl.SSB_Rx( ...
    waveform, cfg, "SampleRate_Hz", tx.SampleRate_Hz);
[pbch, ~] = sixgr.phy.dl.PBCH_Recovery(grid, sync, cfg);
assert(logical(pbch.Ok), ...
    "Centered strict-anchor SSB must pass blind PSS/SSS/PBCH recovery.");
assert(string(sync.NCellIDSource) == "blind_pss_sss_correlation");
end

function localCleanup(path)
if isfolder(path)
    rmdir(path, "s");
end
end
