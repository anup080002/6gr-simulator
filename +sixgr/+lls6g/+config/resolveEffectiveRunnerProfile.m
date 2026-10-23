function [profile, authority] = resolveEffectiveRunnerProfile(scenario, runtimeCfg, configuredProfile)
%RESOLVEEFFECTIVERUNNERPROFILE Pure authority shared by preflight and dispatch.
% The existing legacy system-level profile selects the waveform runner only
% for slot-coupled truth with an enabled physical control/reference gate.
% Do not broaden this promotion for an audit, a PHY backend or a profile name.
if isa(scenario, 'sixgr.lls6g.config.ScenarioConfig')
    scenario = scenario.toStruct();
end
if nargin < 3
    configuredProfile = "";
end
profile = lower(strtrim(string(configuredProfile)));
if strlength(profile) == 0
    profile = lower(strtrim(string(sixgr.util.structGet( ...
        scenario, 'scenario.runner_profile', ""))));
end
configuredProfile = profile;
scenarioUsers = sixgr.util.structGet(scenario, 'users', struct());
scenarioExecutionModel = sixgr.util.structGet(scenario, 'users.execution_model', "");
hasRuntime = nargin >= 2 && ~isempty(runtimeCfg);
if hasRuntime
    % Runtime gates are authoritative at dispatch. An absent runtime gate
    % remains false; an authored gate must not override that absence.
    executionModel = sixgr.util.structGet(runtimeCfg, ...
        'lls6g.users.execution_model', scenarioExecutionModel);
    users = sixgr.util.structGet(runtimeCfg, 'lls6g.users', scenarioUsers);
    gates = sixgr.util.structGet(runtimeCfg, 'run.controlGating', struct());
    gateNames = ["pbchRequired", "prachRequired", "pdcchRequired", ...
        "srsRequired", "trsRequired"];
else
    % Before internal mapping, use the validated resolved scenario fields
    % that buildInternalConfig maps directly to those same runtime gates.
    executionModel = scenarioExecutionModel;
    users = scenarioUsers;
    gates = sixgr.util.structGet(scenario, 'control_gating', struct());
    gateNames = ["pbch_required", "prach_required", "pdcch_required", ...
        "srs_required", "trs_required"];
end
executionModel = lower(strtrim(string(executionModel)));
controlRequired = false;
for name = gateNames
    controlRequired = controlRequired || logical(sixgr.util.structGet(gates, name, false));
end
promoted = profile == "system_level_lls" && ...
    executionModel == "slot_coupled_truth" && controlRequired;
if promoted
    profile = "waveform_bundle";
end

% This does not alter dispatch. It describes whether the selected waveform
% route will create a shared owner, matching runWaveformLinkBundle's user
% enable/count rule. Audits requiring that owner must check it explicitly.
sharedUsersEnabled = false;
ownerExecutionModel = "independent_link_sweep";
if isstruct(users) && isscalar(users) && ~isempty(fieldnames(users))
    numUsers = max(1, round(double(sixgr.util.structGet(users, 'n_users', 1))));
    sharedUsersEnabled = logical(sixgr.util.structGet(users, 'enabled', false)) || numUsers > 1;
    ownerExecutionModel = string(sixgr.util.structGet(users, ...
        'execution_model', "independent_link_sweep"));
end
authority = struct('ConfiguredProfile', configuredProfile, ...
    'EffectiveProfile', profile, 'ExecutionModel', executionModel, ...
    'ControlRequired', controlRequired, 'Promoted', promoted, ...
    'SharedUsersEnabled', sharedUsersEnabled, ...
    'SharedWaveformOwner', profile == "waveform_bundle" && sharedUsersEnabled && ...
        ownerExecutionModel == "slot_coupled_truth");
end
