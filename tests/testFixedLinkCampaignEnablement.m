function ok = testFixedLinkCampaignEnablement()
% A disabled calibration must not be resurrected by reference diagnostics.
setup6GRSimToolkit('Verbose',false);
cfg = struct('run',struct('referenceSweepEnabled',true));
localCheck(cfg,false,false);
cfg.validation.fixed_link_campaign = struct('enabled',false);
localCheck(cfg,true,false);
cfg.sweeps_and_matrix.fixed_link_calibration = struct('enabled',true);
localCheck(cfg,false,true); % Explicit legacy opt-in remains supported.
cfg.validation.fixed_link_campaign.configuration_authority = 'master_yaml';
localCheck(cfg,true,false); % Master authority includes disabled state.
cfg.validation.fixed_link_campaign.enabled = true;
localCheck(cfg,true,true);
cfg.sweeps_and_matrix.fixed_link_calibration.enabled = false;
localCheck(cfg,true,true); % Legacy aliases do not replace master policy.
cfg = rmfield(cfg,'validation');
localCheck(cfg,false,false);

% Reproduce the actual report fixture through public YAML/config loading.
scfg = sixgr.lls6g.config.loadScenarioConfig(fullfile(pwd,'simulator', ...
    'configs','scenarios','lls_100mhz_tdlc_bidirectional_truth.yaml'));
internal = sixgr.lls6g.buildInternalConfig(scfg,tempdir);
assert(~internal.validation.fixed_link_campaign.enabled, ...
    'The retained failure requires an explicitly disabled campaign.');
localCheck(internal,true,false);

master = sixgr.lls6g.config.loadScenarioConfig(fullfile(pwd,'simulator', ...
    'configs','scenarios','master_sinr_sweep.yaml'));
internal = sixgr.lls6g.buildInternalConfig(master,tempdir);
localCheck(internal,true,true);
ok = true;
end

function localCheck(cfg,expectedValidation,expectedEnabled)
[useValidation,enabled] = sixgr.lls6g.runners.resolveFixedLinkCampaignAuthority(cfg);
assert(isequal(useValidation,expectedValidation) && isequal(enabled,expectedEnabled), ...
    'test:FixedLinkCampaignAuthority', ...
    'Fixed-link campaign authority/enablement did not preserve resolved configuration.');
end
