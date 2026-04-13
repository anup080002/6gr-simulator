function ok = test6GScenarioConfigValidation()
%TEST6GSCENARIOCONFIGVALIDATION Validate 6G scenario loader and schema checks.

setup6GRSimToolkit("Verbose", false);

scfg = sixgr.lls6g.config.loadScenarioConfig("simulator/configs/scenarios/dl_4ghz_baseline.yaml");
assert(string(scfg.ScenarioID) == "dl_4ghz_baseline", "Scenario ID mismatch.");
assert(strlength(string(scfg.ConfigHash)) > 0, "Config hash must be populated.");
assert(numel(scfg.SourceFiles) >= 5, "Scenario inheritance chain should include multiple source files.");
assert(string(scfg.get("channels.profile")) == "TDL-C", "Expected TDL-C profile.");
assert(string(scfg.get("scenario.runner_profile")) == "waveform_bundle", "Runner profile mismatch.");

scfg100 = sixgr.lls6g.config.loadScenarioConfig("simulator/configs/scenarios/lls_100mhz_tdlc_bidirectional_truth.yaml");
cfg100 = sixgr.lls6g.buildInternalConfig(scfg100, fullfile(tempdir, "lls6g_cfg_check"));
assert(abs(double(cfg100.phy.channelBandwidth_MHz) - 100) < 1e-9, ...
    "Internal 6G config must propagate the scenario bandwidth into phy.channelBandwidth_MHz.");
assert(abs(double(cfg100.phy.carrier.SubcarrierSpacing_kHz) - 30) < 1e-9, ...
    "Internal 6G config must propagate the scenario SCS into phy.carrier.SubcarrierSpacing_kHz.");

scfgPi2 = sixgr.lls6g.config.loadScenarioConfig("simulator/configs/scenarios/ul_4ghz_dfts_pi2bpsk.yaml");
cfgPi2 = sixgr.lls6g.buildInternalConfig(scfgPi2, fullfile(tempdir, "lls6g_pi2bpsk_cfg_check"));
assert(string(cfgPi2.phy.pusch.modulation) == "pi/2-BPSK", ...
    "DFT-s-OFDM UL pi/2-BPSK scenarios must resolve cfg.phy.pusch.modulation to pi/2-BPSK.");
summaryPi2 = sixgr.truth.summarizeEffectiveOperatingPoint(scfgPi2, table(), table());
assert(string(summaryPi2.Configured.UL.Modulation) == "pi/2-BPSK", ...
    "Configured operating-point summaries must preserve pi/2-BPSK semantics.");

tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>

badFile = fullfile(tmp, "bad_dfts.yaml");
fid = fopen(badFile, "w");
fprintf(fid, "%s", ['{' ...
    '"inherits":["' strrep(fullfile(pwd, "simulator", "configs", "defaults", "global.yaml"), '\', '\\') '"],' ...
    '"meta":{"scenario_id":"bad_dfts","description":"bad","version":"1","owner":"t","maturity_tag":"smoke"},' ...
    '"waveform":{"ul_waveform":"DFT-S-OFDM","transform_precoding_enabled":false}}']);
fclose(fid);

threw = false;
try
    sixgr.lls6g.config.loadScenarioConfig(badFile);
catch ME
    threw = contains(string(ME.identifier), "BadDFTSOFDM");
end
assert(threw, "Invalid DFT-s-OFDM config should fail validation.");

badUsersFile = fullfile(tmp, "bad_users.yaml");
fid = fopen(badUsersFile, "w");
fprintf(fid, "%s", ['{' ...
    '"inherits":["' strrep(fullfile(pwd, "simulator", "configs", "defaults", "global.yaml"), '\', '\\') '"],' ...
    '"meta":{"scenario_id":"bad_users","description":"bad users","version":"1","owner":"t","maturity_tag":"smoke"},' ...
    '"users":{"enabled":false,"n_users":2,"rnti_start":1,"seed_stride":1,' ...
    '"execution_model":"independent_link_sweep","beam_selection_strategy":"fixed_first_beam","save_user_tables":true}}']);
fclose(fid);

threw = false;
try
    sixgr.lls6g.config.loadScenarioConfig(badUsersFile);
catch ME
    threw = contains(string(ME.identifier), "UsersDisabledMismatch");
end
assert(threw, "users.n_users > 1 with users.enabled=false should fail validation.");

ok = true;
end
