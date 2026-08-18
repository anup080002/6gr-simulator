function ok = testRAConfigBinding()
sixgr.config.publishConfigApplicationEvidence("reset", struct( ...
    "RunId", "test_ra_config", "ScenarioID", "test_ra_config"));
c = onCleanup(@() sixgr.config.publishConfigApplicationEvidence("clear")); %#ok<NASGU>
cfg = raStrictAnchorConfig();
ra = sixgr.mac.ra.RAConfig(cfg, "RunId", "test_ra_config");
assert(ra.BindingSource == "scenario_config_pending_sib1", "RA binding source must be explicit.");
assert(strlength(ra.RACHConfigHash) > 16, "RA config hash must be exported.");
evidence = sixgr.config.publishConfigApplicationEvidence("snapshot");
localAssertApplied(evidence, "random_access.ra_response_window_slots", ...
    string(ra.RAResponseWindowSlots));
localAssertApplied(evidence, "random_access.power_ramping_step_db", ...
    string(ra.PowerRampingStep_dB));
localAssertApplied(evidence, "random_access.preamble_received_target_power_dbm", ...
    string(ra.PreambleReceivedTargetPower_dBm));
localAssertApplied(evidence, "random_access.msg1_fdm", string(ra.Msg1FDM));
localAssertApplied(evidence, "random_access.frequency_start", string(ra.FrequencyStart));
localAssertApplied(evidence, "random_access.ra_rnti_policy", ...
    "ts_38_321_ra_rnti_formula");
localAssertApplied(evidence, "random_access.prach_occasion_policy", ...
    "ts_38_211_configuration_index_resolution");
bad = cfg;
bad.random_access = rmfield(bad.random_access, "preamble_index");
threw = false;
try
    sixgr.mac.ra.RAConfig(bad);
catch ME
    threw = strcmp(string(ME.identifier), "sixgr:mac:ra:MissingMandatoryRACHFields");
end
assert(threw, "Missing mandatory RACH fields must fail closed.");
ok = true;
end

function localAssertApplied(T, parameterId, expected)
row = T(string(T.ParameterId) == string(parameterId), :);
assert(height(row) == 1, "Expected one runtime binding row for %s.", parameterId);
assert(string(row.AppliedValue(1)) == string(expected), ...
    "Runtime binding for %s does not match the consumed value.", parameterId);
end
