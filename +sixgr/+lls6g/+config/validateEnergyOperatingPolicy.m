function validateEnergyOperatingPolicy(cfg)
% Resolved consumers cannot bypass authoring-time energy-policy validation.
modern=string(sixgr.util.structGet(cfg,'energy_and_complexity.sleep_state_model',""));
legacy=string(sixgr.util.structGet(cfg,'energy_efficiency.sleep_state_model',""));
race=string(sixgr.util.structGet(cfg,'energy_and_complexity.race_to_sleep_metrics',""));
enabled=sixgr.util.structGet(cfg,'energy_efficiency.race_to_sleep_enabled',[]);
id='sixgr:lls6g:config:EnergyOperatingPolicyConflict';
if strlength(modern)>0 && strlength(legacy)>0
    assert(isequal(modern,legacy),id, ...
        'energy_and_complexity.sleep_state_model and energy_efficiency.sleep_state_model must agree.');
end
if strlength(race)>0 && ~isempty(enabled)
    assert(any(race==["enabled","disabled"]) && islogical(enabled) && isscalar(enabled) && ...
        enabled==(race=="enabled"),id, ...
        'energy_and_complexity.race_to_sleep_metrics and energy_efficiency.race_to_sleep_enabled must agree.');
end
if any([modern legacy]=="none")
    assert(race~="enabled" && (isempty(enabled)||~enabled),id, ...
        'A no-sleep baseline cannot request race-to-sleep gains.');
end
policy=string(sixgr.util.structGet(cfg,'energy_efficiency.operating_state_policy',"represented_intervals"));
if policy=="always_awake"
    assert(modern=="none" && legacy=="none" && race=="disabled" && ...
        islogical(enabled) && isscalar(enabled) && ~enabled,id, ...
        'always_awake requires explicit no-sleep policy and disabled sleep-gain accounting.');
end
end
