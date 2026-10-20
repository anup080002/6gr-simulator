function ok=testCheckpointOverlayConfigAuthority()
% Operational resume layers must not reinterpret inherited scientific aliases.
% Config-only check: no checkpoint load, physical run, or invented PHY rows.
setup6GRSimToolkit('Verbose',false);
root=fullfile(pwd,'logs','lls_repairs', ...
    ['checkpoint_overlay_config_' char(java.util.UUID.randomUUID)]);
mkdir(root);
scenarios=["h4_100_cdlc100_connected_impaired_40db_adaptation", ...
    "lls_tdd_4ghz_20mhz_64txru_4rx_cdlc100_impaired", ...
    "lls_tdd_5mhz_rank2_shared_awgn_20db", ...
    "lls_7ghz_400mhz_1024qam_tdd_30db"];
for i=1:numel(scenarios)
    parent=fullfile(pwd,'simulator','configs','scenarios',scenarios(i)+".yaml");
    original=sixgr.lls6g.config.loadScenarioConfig(parent);
    controls=struct('runtime_checkpoint_enable',true, ...
        'runtime_checkpoint_resume_from',fullfile(root,'not_loaded_state.mat'), ...
        'runtime_checkpoint_repair_reason','configuration-only regression', ...
        'runtime_checkpoint_keep',3,'checkpoint_every_slots',5);
    raw=struct('inherits',{{char(parent)}},'run_control',controls);
    overlay=fullfile(root,scenarios(i)+"_resume.json");
    sixgr.util.jsonWrite(overlay,raw);
    resumed=sixgr.lls6g.config.loadScenarioConfig(overlay);
    assert(isequaln(localScience(original),localScience(resumed)), ...
        'sixgr:test:CheckpointOverlayChangedScience', ...
        'An operational-only child changed the scientific configuration: %s',scenarios(i));
    assert(string(resumed.get('run_control.runtime_checkpoint_resume_from'))== ...
        string(controls.runtime_checkpoint_resume_from));
    assert(any(string(resumed.SourceFiles)==string(overlay)), ...
        'Keep the operational input file in provenance, even though science is unchanged.');
    % A second operational layer (including an empty wrapper) is also neutral.
    outer=fullfile(root,scenarios(i)+"_outer.json");
    sixgr.util.jsonWrite(outer,struct('inherits',{{char(overlay)}}));
    again=sixgr.lls6g.config.loadScenarioConfig(outer);
    assert(isequaln(localScience(original),localScience(again)));
    % A real experiment change is NOT an operational layer or resume-compatible.
    nextSeed=double(original.get('simulation.random_seed'))+1;
    raw.simulation=struct('random_seed',nextSeed);
    changedFile=fullfile(root,scenarios(i)+"_changed_seed.json");
    sixgr.util.jsonWrite(changedFile,raw);
    changed=sixgr.lls6g.config.loadScenarioConfig(changedFile);
    assert(changed.get('simulation.random_seed')==nextSeed && ...
        changed.get('run_control.seed')==nextSeed && ...
        ~isequaln(localScience(original),localScience(changed)), ...
        'A real seed override must remain visible to the unchanged checkpoint guard.');
end
fprintf('CHECKPOINT_OVERLAY_CONFIG_AUTHORITY_PASS: four bandwidth configurations; no PHY executed.\n');
ok=true;
end

function value=localScience(scenario)
value=sixgr.runtime.SlotCheckpoint.scientificScenario(scenario.toStruct());
end
