function ok = testLLS4GHzUMaChannelProfileWiring()
%TESTLLS4GHZUMACHANNELPROFILEWIRING Guard UMa midband mobility CDL profile selection.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);

scenarioPath = fullfile(pwd, "simulator", "configs", "scenarios", ...
    "master_scenaio_all_file.yaml");
scfg = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
resolved = scfg.toStruct();

assert(strcmpi(char(string(resolved.channels.profile)), "CDL-C"), ...
    "4 GHz UMa WebGUI master scenario must default to CDL-C, not LOS-biased CDL-D.");
assert(strcmpi(char(string(resolved.channel_model.scenario_label)), "CDL-C"), ...
    "channel_model.scenario_label must mirror channels.profile as CDL-C.");
assert(strcmpi(char(string(resolved.random_access.channel_model)), "CDL-C"), ...
    "Master random-access channel model must follow the 4 GHz UMa CDL-C channel profile.");
expectedDefaultDopplerHz = (100 / 3.6) * 4.0e9 / 299792458;
assert(abs(double(resolved.channels.doppler_hz) - expectedDefaultDopplerHz) < 1e-6 && ...
    abs(double(resolved.channel_model.doppler_hz) - expectedDefaultDopplerHz) < 1e-6, ...
    "Resolved master Doppler must be derived from 100 km/h and 4 GHz when derive_from_ue_speed is active.");

tmp = tempname;
mkdir(tmp);
cleanup = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>

cfgDefault = sixgr.lls6g.buildInternalConfig(scfg, fullfile(tmp, "default"));
assert(strcmpi(char(string(cfgDefault.channel.cdlProfile)), "CDL-C"), ...
    "Internal 4 GHz UMa master config must apply CDL-C to the channel factory.");

familyScenarios = [
    "lls_3gpp_rel20_anchor_4ghz_100mhz_waveform_honest_200ue_4000slot.yaml"
    "lls_3gpp_rel20_anchor_4ghz_100mhz_waveform_honest_2site_6sector_150ue_60slot.yaml"
    ];
for ii = 1:numel(familyScenarios)
    scfgFamily = sixgr.lls6g.config.loadScenarioConfig(fullfile(pwd, ...
        "simulator", "configs", "scenarios", familyScenarios(ii)));
    resolvedFamily = scfgFamily.toStruct();
    cfgFamily = sixgr.lls6g.buildInternalConfig(scfgFamily, fullfile(tmp, "family_" + string(ii)));
    assert(strcmpi(char(string(resolvedFamily.channels.profile)), "CDL-C") && ...
        strcmpi(char(string(resolvedFamily.channel_model.scenario_label)), "CDL-C"), ...
        "4 GHz UMa scenario %s must resolve YAML channel profile as CDL-C.", familyScenarios(ii));
    assert(strcmpi(char(string(cfgFamily.channel.cdlProfile)), "CDL-C"), ...
        "4 GHz UMa scenario %s must apply CDL-C internally.", familyScenarios(ii));
end

legacyHighMobility = resolved;
legacyHighMobility.mobility.ue_speed_kmh = 100;
legacyHighMobility.channels.mobility_kmph = 100;
legacyHighMobility.channels.profile = "CDL-D";
legacyHighMobility.channel_model.scenario_label = "CDL-D";
legacyHighMobility.channels.los_enabled = true;
legacyHighMobility.channel_model.doppler_source_mode = "derive_from_ue_speed";
legacyHighMobility.channels.doppler_source_mode = "derive_from_ue_speed";

scfgLegacy = sixgr.lls6g.config.ScenarioConfig(legacyHighMobility, ...
    "ConfigPath", "unit_test_legacy_high_mobility_cdl_d");
cfgLegacy = sixgr.lls6g.buildInternalConfig(scfgLegacy, fullfile(tmp, "legacy"));
expectedDopplerHz = (100 / 3.6) * 4.0e9 / 299792458;

assert(strcmpi(char(string(cfgLegacy.channel.configuredDelayProfile)), "CDL-D"), ...
    "Regression fixture must start from the stale CDL-D channel profile.");
assert(strcmpi(char(string(cfgLegacy.channel.cdlProfile)), "CDL-C") && ...
    strcmpi(char(string(cfgLegacy.channel.delayProfile)), "CDL-C"), ...
    "4 GHz UMa 100 km/h runtime must map stale CDL-D requests to CDL-C.");
assert(abs(double(cfgLegacy.channel.doppler_Hz) - expectedDopplerHz) < 1e-6, ...
    "100 km/h at 4 GHz must derive Doppler around 370.63 Hz, not the 3 km/h 11.12 Hz value.");
assert(strcmpi(char(string(cfgLegacy.channel.profileResolutionSource)), ...
    "tr38901_uma_midband_high_mobility_mapping"), ...
    "CDL-C high-mobility remapping must expose provenance.");

ok = true;
end
