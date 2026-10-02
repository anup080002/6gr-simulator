function testRAN1AI1032MCSRepresentation()
%TESTRAN1AI1032MCSREPRESENTATION Deterministic MCS semantics and state guard.

[cfg, provenance] = sixgr.studies.ran1ai1032.loadStudyConfig();
assert(string(cfg.study.generation_label) == "6GR" && ...
    strlength(string(provenance.ConfigSHA256)) == 64);

a = sixgr.studies.ran1ai1032.MCSCatalog.optionA();
assert(height(a) == 32 && isequal(a.indication_index, (0:31).'));
assert(a.entry_id(28) == "B27" && a.Qm(28) == 8 && ...
    a.target_code_rate_x1024(28) == 948 && ...
    abs(a.nominal_spectral_efficiency(28) - 7.40625) < 1e-12);
assert(isequal(a.entry_id(29:32), ["H0";"H1";"H2";"H3"]));
assert(isequal(a.Qm(29:32), repmat(10,4,1)) && ...
    isequal(a.target_code_rate_x1024(29:32), [805.5;853;900.5;948]));

c = sixgr.studies.ran1ai1032.MCSCatalog.optionC();
assert(height(c) > 32 && all(c.indication_width_bits == ceil(log2(height(c)))));
d = sixgr.studies.ran1ai1032.MCSCatalog.optionD();
assert(d.TotalIndicationBits == d.QmFieldBits + d.RateFieldBits && ...
    height(d.ValidPairs) == height(c));

e = sixgr.studies.ran1ai1032.MCSCatalog.equalSpectralEfficiencyPairs();
assert(height(e) == 6 && all(groupsummary(e,"pair_id","range", ...
    "nominal_spectral_efficiency").range_nominal_spectral_efficiency < 1e-12));

state = sixgr.studies.ran1ai1032.ProfileSwitchState("baseline", 4, 40);
[profile, source] = state.profileForGrant(true);
assert(profile == "baseline" && startsWith(source,"active_configuration_epoch_"));
state = state.request("fwa_high_order", 10, "cfg-1");
localAssertError(@() state.profileForGrant(true), ...
    "sixgr:ran1ai1032:ProfileStateNotSchedulable");
[profile, source] = state.profileForGrant(false, "baseline");
assert(profile == "baseline" && source == "immutable_stored_HARQ_TB_context");
state = state.confirm(12, "cfg-1", true);
state = state.advance(15);
assert(state.ActiveProfile == "baseline" && state.State == "transition_pending");
state = state.advance(16);
assert(state.ActiveProfile == "fwa_high_order" && state.State == "active" && ...
    state.ConfigurationEpoch == 1);

failed = sixgr.studies.ran1ai1032.ProfileSwitchState("baseline", 1, 4);
failed = failed.request("fwa_high_order", 1, "cfg-fail");
failed = failed.confirm(2, "cfg-fail", false);
assert(failed.ActiveProfile == "baseline" && failed.FailureCount == 1);

fprintf('RAN1_AI_1032_MCS_REPRESENTATION_PASS entries_A=%d entries_C=%d option_D_bits=%d\n', ...
    height(a), height(c), d.TotalIndicationBits);
end

function localAssertError(fcn, expected)
caught = false;
try
    fcn();
catch ME
    caught = strcmp(ME.identifier, expected);
end
assert(caught, "Expected error %s.", expected);
end
