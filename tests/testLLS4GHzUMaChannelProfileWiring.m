function ok = testLLS4GHzUMaChannelProfileWiring()
%TESTLLS4GHZUMACHANNELPROFILEWIRING Guard UMa midband mobility CDL profile selection.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);

scenarioPath = fullfile(pwd, "simulator", "configs", "scenarios", ...
    "master_geometry_based.yaml");
scfg = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
resolved = scfg.toStruct();

assert(strcmpi(char(string(resolved.channels.profile)), "CDL-C"), ...
    "4 GHz UMa WebGUI master scenario must default to CDL-C, not LOS-biased CDL-D.");
assert(strcmpi(char(string(resolved.channel_model.scenario_label)), "CDL-C"), ...
    "channel_model.scenario_label must mirror channels.profile as CDL-C.");
assert(strcmpi(char(string(resolved.random_access.channel_model)), "CDL-C"), ...
    "Master random-access channel model must follow the 4 GHz UMa CDL-C channel profile.");
configuredSpeedKmh = double(sixgr.util.structGet( ...
    resolved, "mobility.ue_speed_kmh", NaN));
configuredCarrierHz = double(sixgr.util.structGet( ...
    resolved, "frequency.center_frequency_hz", NaN));
assert(isfinite(configuredSpeedKmh) && isfinite(configuredCarrierHz), ...
    "Master must explicitly configure UE speed and carrier frequency.");
expectedDefaultDopplerHz = ...
    (configuredSpeedKmh / 3.6) * configuredCarrierHz / 299792458;
assert(abs(double(resolved.channels.doppler_hz) - expectedDefaultDopplerHz) < 1e-6 && ...
    abs(double(resolved.channel_model.doppler_hz) - expectedDefaultDopplerHz) < 1e-6, ...
    "Resolved master Doppler must be derived from configured speed and carrier frequency.");

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
legacyHighMobility.channels.los_enabled = false;
legacyHighMobility.channel_model.doppler_source_mode = "derive_from_ue_speed";
legacyHighMobility.channels.doppler_source_mode = "derive_from_ue_speed";

scfgLegacy = sixgr.lls6g.config.ScenarioConfig(legacyHighMobility, ...
    "ConfigPath", "unit_test_legacy_high_mobility_cdl_d");
localAssertError(@() sixgr.lls6g.buildInternalConfig( ...
    scfgLegacy, fullfile(tmp, "legacy")), "ChannelProfileLOSConflict");

explicitLOS = legacyHighMobility;
explicitLOS.channels.los_enabled = true;
scfgLOS = sixgr.lls6g.config.ScenarioConfig(explicitLOS, ...
    "ConfigPath", "unit_test_explicit_los_cdl_d");
cfgLOS = sixgr.lls6g.buildInternalConfig(scfgLOS, fullfile(tmp, "explicit_los"));
expectedDopplerHz = (100 / 3.6) * configuredCarrierHz / 299792458;
assert(strcmpi(char(string(cfgLOS.channel.configuredDelayProfile)), "CDL-D") && ...
    strcmpi(char(string(cfgLOS.channel.cdlProfile)), "CDL-D"), ...
    "A compatible explicit CDL-D/LOS request must be preserved exactly.");
assert(abs(double(cfgLOS.channel.doppler_Hz) - expectedDopplerHz) < 1e-6, ...
    "Explicit 100 km/h mobility must drive Doppler without changing the channel profile.");
assert(strcmpi(char(string(cfgLOS.channel.profileResolutionSource)), ...
    "configured_channels_profile"), ...
    "Compatible configured channel profiles must retain YAML provenance.");

ok = true;
end

function localAssertError(action, expectedIdentifierFragment)
caught = [];
try
    action();
catch ME
    caught = ME;
end
assert(~isempty(caught), "Expected channel-profile validation failure.");
assert(contains(string(caught.identifier), string(expectedIdentifierFragment)), ...
    "Expected '%s', got '%s': %s", expectedIdentifierFragment, ...
    string(caught.identifier), string(caught.message));
end
