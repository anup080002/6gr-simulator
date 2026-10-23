function ok=testEnergyOperatingPolicyAliases()
% Fast policy/inheritance invariants; no waveform or measured power claims.
base=struct();
base.energy_and_complexity.sleep_state_model='micro_sleep';
base.energy_and_complexity.race_to_sleep_metrics='enabled';
base.energy_efficiency.sleep_state_model='micro_sleep';
base.energy_efficiency.race_to_sleep_enabled=true;
for section=["energy_efficiency","energy_and_complexity"]
    child=struct(); child.(section).sleep_state_model='none';
    child.energy_efficiency.race_to_sleep_enabled=false;
    authority=sixgr.lls6g.config.mergeEnergyOperatingAuthority(struct(),base);
    authority=sixgr.lls6g.config.mergeEnergyOperatingAuthority(authority,child);
    % A grandchild's unrelated fields must not erase intermediate authority.
    unrelated=struct('simulation',struct('n_slots',100));
    authority=sixgr.lls6g.config.mergeEnergyOperatingAuthority(authority,unrelated);
    merged=sixgr.util.mergeStruct(base,child);
    actual=sixgr.lls6g.config.normalizeEnergyOperatingPolicy(merged,authority);
    assert(actual.energy_efficiency.sleep_state_model=="none" && ...
        actual.energy_and_complexity.sleep_state_model=="none" && ...
        ~actual.energy_efficiency.race_to_sleep_enabled && ...
        actual.energy_and_complexity.race_to_sleep_metrics=="disabled");
    % Later parent composition has the same last-author rule as inheritance.
    later=struct('energy_efficiency',struct('sleep_state_model','deep_sleep', ...
        'race_to_sleep_enabled',true));
    authority=sixgr.lls6g.config.mergeEnergyOperatingAuthority(authority,later);
    actual=sixgr.lls6g.config.normalizeEnergyOperatingPolicy(actual,authority);
    assert(actual.energy_efficiency.sleep_state_model=="deep_sleep" && ...
        actual.energy_and_complexity.sleep_state_model=="deep_sleep" && ...
        actual.energy_and_complexity.race_to_sleep_metrics=="enabled");
end
conflict=base; conflict.energy_and_complexity.sleep_state_model='none';
localReject(@()sixgr.lls6g.config.normalizeEnergyOperatingPolicy(conflict,conflict));
localReject(@()sixgr.lls6g.config.validateEnergyOperatingPolicy(conflict));
conflict=base; conflict.energy_efficiency.race_to_sleep_enabled=false;
localReject(@()sixgr.lls6g.config.normalizeEnergyOperatingPolicy(conflict,conflict));
awake=base; awake.energy_and_complexity.sleep_state_model='none';
awake.energy_efficiency.sleep_state_model='none';
localReject(@()sixgr.lls6g.config.validateEnergyOperatingPolicy(awake));
awake.energy_efficiency.race_to_sleep_enabled=false;
awake.energy_and_complexity.race_to_sleep_metrics='disabled';
awake.energy_efficiency.operating_state_policy='always_awake';
sixgr.lls6g.config.validateEnergyOperatingPolicy(awake);
ok=true;
end
function localReject(action)
try
    action();
catch cause
    assert(strcmp(cause.identifier,'sixgr:lls6g:config:EnergyOperatingPolicyConflict'), ...
        'Unexpected rejection %s: %s',cause.identifier,cause.message);
    return;
end
error('test:MissingEnergyPolicyRejection','An energy-policy contradiction was accepted.');
end
