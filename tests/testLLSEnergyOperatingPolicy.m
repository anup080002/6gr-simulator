function ok = testLLSEnergyOperatingPolicy()
% Configuration-only regression: no waveform, device-power or sleep claims.
% The always-awake baseline must have one policy across both YAML surfaces.
% This test is deliberately independent of the active checkpoint's config.
setup6GRSimToolkit('Verbose',false);
root=fileparts(fileparts(mfilename('fullpath')));
parent=fullfile(root,'simulator','configs','scenarios', ...
    'h4_100_cdlc100_connected_impaired_40db_adaptation.yaml');
% Test the executable scenario itself. A wrapper that adds the right
% fragment can pass even when the actual H4 inheritance is still wrong.
production=sixgr.lls6g.config.loadScenarioConfig(parent);
localAssertAwake(production.toStruct());
assert(string(production.toStruct().energy_efficiency.operating_state_policy)=="always_awake", ...
    'test:H4EnergyOperatingPolicy','The production H4 family must select the approved awake baseline.');
folder=tempname; mkdir(folder);
cleanup=onCleanup(@()localCleanup(folder)); %#ok<NASGU>

% Exercise the reusable authored policy fragment, not just temporary test
% values. This is a future-run configuration; never rewrite a saved prefix.
baseline=fullfile(root,'simulator','configs','energy','always_awake_baseline.yaml');
raw=struct('inherits',{{parent,baseline}});
raw.energy_efficiency.bs_rf_chain_idle_power_fraction=0.37;
path=fullfile(folder,'configured_awake_baseline.yaml');
sixgr.util.jsonWrite(path,raw);
scfg=sixgr.lls6g.config.loadScenarioConfig(path);
localAssertAwake(scfg.toStruct());
cfg=sixgr.lls6g.buildInternalConfig(scfg,fullfile(folder,'baseline_not_executed'));
assert(string(cfg.lls6g.energy_efficiency.sleep_state_model)=="none" && ...
    ~cfg.lls6g.energy_efficiency.race_to_sleep_enabled, ...
    'test:EnergyPolicyBaselineBinding', ...
    'The reusable awake fragment must reach the runtime unchanged.');
model=sixgr.truth.resolveLLSEnergyModelConfig(cfg,RFInventoryPolicy="require_match");
assert(model.Available, ...
    'test:EnergyPolicyPhysicalInventory', ...
    ['A future baseline needs complete explicit energy terms matching the ' ...
     'installed RF-chain inventory; a reporting-only count override is not ' ...
     'a corrected production configuration. Missing or invalid: %s'], ...
    char(strjoin(model.MissingTerms,",")));
assert(model.OperatingStatePolicy=="always_awake" && ...
    model.RFInventorySource=="declared_endpoint_inventory" && ...
    model.ModelConfig.powerAndRF.bsRFChainCount==cfg.antenna.bs.numRFChains && ...
    model.ModelConfig.powerAndRF.ueRFChainCount==cfg.antenna.ue.numRFChains, ...
    'test:EnergyPolicyDeclaredInventory', ...
    'YAML must bind the declared endpoint RF inventory before export without a reporting override.');
assert(model.ModelConfig.energy.bs.idleRFChainPowerFraction==0.37 && ...
    model.TermTable.Value(model.TermTable.Term=="BSRFChainIdlePowerFraction")==0.37, ...
    'test:EnergyIdleFractionBinding','A nondefault YAML model fraction must reach the consumer and its terms table.');

% Use an explicitly sleeping parent to exercise genuine conflicting
% inheritance now that the production causal baseline is internally valid.
sleepingParent=struct('inherits',{{parent}});
sleepingParent.energy_efficiency.sleep_state_model='micro_sleep';
sleepingParent.energy_efficiency.race_to_sleep_enabled=true;
sleepingParent.energy_efficiency.operating_state_policy='represented_intervals';
sleepingParentPath=fullfile(folder,'sleeping_parent.yaml');
sixgr.util.jsonWrite(sleepingParentPath,sleepingParent);

% A child-authored modern policy must override a conflicting inherited
% legacy value; a child-authored legacy policy must work in the reverse
% direction too. Merely choosing the non-default value is not authorship.
for surface=["energy_and_complexity","energy_efficiency"]
    raw=struct('inherits',{{sleepingParentPath}});
    raw.(surface).sleep_state_model='none';
    raw.energy_and_complexity.race_to_sleep_metrics='disabled';
    raw.energy_efficiency.race_to_sleep_enabled=false;
    raw.energy_efficiency.active_sleep_tracking_enabled=false;
    path=fullfile(folder,char(surface+"_awake.yaml"));
    sixgr.util.jsonWrite(path,raw);
    scfg=sixgr.lls6g.config.loadScenarioConfig(path);
    localAssertAwake(scfg.toStruct());
    cfg=sixgr.lls6g.buildInternalConfig(scfg,fullfile(folder,'not_executed'));
    assert(string(cfg.lls6g.energy_efficiency.sleep_state_model)=="none" && ...
        ~cfg.lls6g.energy_efficiency.race_to_sleep_enabled, ...
        'test:EnergyPolicyRuntimeBinding', ...
        'The runtime must consume the same explicit no-sleep policy as YAML.');
end

% Explicitly consistent policy is valid, but contradictory sibling fields
% in the same authored document must not be silently normalized away.
consistent=struct('inherits',{{parent}});
consistent.energy_efficiency.sleep_state_model='none';
consistent.energy_efficiency.race_to_sleep_enabled=false;
consistent.energy_efficiency.active_sleep_tracking_enabled=false;
consistent.energy_and_complexity.sleep_state_model='none';
consistent.energy_and_complexity.race_to_sleep_metrics='disabled';
path=fullfile(folder,'consistent_awake.yaml');
sixgr.util.jsonWrite(path,consistent);
scfg=sixgr.lls6g.config.loadScenarioConfig(path);
localAssertAwake(scfg.toStruct());

conflicting=consistent;
conflicting.energy_and_complexity.sleep_state_model='micro_sleep';
path=fullfile(folder,'conflicting_sleep.yaml');
sixgr.util.jsonWrite(path,conflicting);
localReject(@()sixgr.lls6g.config.loadScenarioConfig(path), ...
    'sixgr:lls6g:config:EnergyOperatingPolicyConflict');

% Validation must also reject already-resolved contradictions. Otherwise
% direct ScenarioConfig consumers could bypass the loader's alias checks.
resolved=scfg.toStruct();
resolved.energy_and_complexity.sleep_state_model='deep_sleep';
localReject(@()sixgr.lls6g.config.validateScenarioConfig(resolved), ...
    'sixgr:lls6g:config:EnergyOperatingPolicyConflict');

% A no-sleep experiment cannot enable a race-to-sleep gain calculation.
% It may still publish an explicit "not applicable: no sleep" indicator.
race=consistent;
race.energy_efficiency.race_to_sleep_enabled=true;
race.energy_and_complexity.race_to_sleep_metrics='enabled';
path=fullfile(folder,'awake_with_sleep_gain.yaml');
sixgr.util.jsonWrite(path,race);
localReject(@()sixgr.lls6g.config.loadScenarioConfig(path), ...
    'sixgr:lls6g:config:EnergyOperatingPolicyConflict');
ok=true;
end

function localAssertAwake(cfg)
assert(string(cfg.energy_and_complexity.sleep_state_model)=="none" && ...
    string(cfg.energy_efficiency.sleep_state_model)=="none", ...
    'test:EnergyPolicyAliasMismatch', ...
    'Modern and legacy energy fields must resolve to one awake baseline.');
assert(~cfg.energy_efficiency.race_to_sleep_enabled && ...
    string(cfg.energy_and_complexity.race_to_sleep_metrics)=="disabled", ...
    'test:EnergyPolicySleepSavings', ...
    'An always-awake baseline must not request sleep savings.');
end

function localReject(call,identifier)
caught=false;
try
    call();
catch cause
    assert(strcmp(cause.identifier,identifier), ...
        'test:EnergyPolicyWrongFailure','Expected %s, got %s: %s', ...
        identifier,cause.identifier,cause.message);
    caught=true;
end
assert(caught,'test:EnergyPolicyAcceptedConflict', ...
    'Conflicting operating policy was accepted; expected %s.',identifier);
end

function localCleanup(folder)
% Delete only this test's independently generated temporary fixture tree.
if isfolder(folder), rmdir(folder,'s'); end
end
