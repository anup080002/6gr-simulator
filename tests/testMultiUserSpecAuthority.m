function ok=testMultiUserSpecAuthority()
% Config/adapter contracts only: no waveform, scheduler or beam qualification.
setup6GRSimToolkit('Verbose',false);
root=fileparts(fileparts(mfilename('fullpath')));
path=fullfile(root,'simulator','configs','scenarios', ...
    'lls_tdd_received_csi_application_coexistence_fixture.yaml');
scenario=sixgr.lls6g.config.loadScenarioConfig(path);
cfg=sixgr.lls6g.buildInternalConfig(scenario,tempname);
users=scenario.get('users');
assert(isequaln(cfg.lls6g.users,users), ...
    'The actual resolved YAML user block must reach the internal config unchanged.');
before=cfg; beforeRNG=rng;
spec=sixgr.truth.resolveMultiUserSpec(cfg);
expected=struct('Enabled',logical(users.enabled),'NumUsers',double(users.n_users), ...
    'RNTIStart',double(users.rnti_start),'SeedStride',double(users.seed_stride), ...
    'ExecutionModel',string(users.execution_model), ...
    'BeamSelectionStrategy',lower(string(users.beam_selection_strategy)), ...
    'SaveUserTables',logical(users.save_user_tables));
assert(isequaln(spec,expected) && isequaln(cfg,before) && isequal(rng,beforeRNG), ...
    'Resolve all seven production fields without changing config or executing a random realization.');
assert(spec.Enabled && spec.NumUsers==1 && spec.RNTIStart==1 && ...
    spec.ExecutionModel=="slot_coupled_truth" && ...
    spec.BeamSelectionStrategy=="runtime_best_beam_per_link", ...
    'The bounded fixture must use its actual inherited user/beam policy, not a test fallback.');
names=string(fieldnames(expected));
assert(numel(names)==7 && all(ismember( ...
    ["SeedStride","BeamSelectionStrategy","SaveUserTables"],names)));

% Declared resolver-only inputs exercise existing one-user/multi-user
% semantics. They are not alternate resolved scenarios or runtime evidence.
declared=struct('lls6g',struct('users',users));
declared.lls6g.users.enabled=false;
declared.lls6g.users.n_users=1;
declared.lls6g.users.rnti_start=37;
declared.lls6g.users.seed_stride=19;
declared.lls6g.users.execution_model='independent_link_sweep';
declared.lls6g.users.save_user_tables=false;
single=sixgr.truth.resolveMultiUserSpec(declared);
assert(~single.Enabled && single.NumUsers==1 && single.RNTIStart==37 && ...
    single.SeedStride==19 && single.ExecutionModel=="independent_link_sweep" && ...
    ~single.SaveUserTables && single.BeamSelectionStrategy==spec.BeamSelectionStrategy && ...
    isequal(string(fieldnames(single)),names));
declared.lls6g.users.enabled=true;
enabledSingle=sixgr.truth.resolveMultiUserSpec(declared);
assert(enabledSingle.Enabled && enabledSingle.NumUsers==1);
declared.lls6g.users.enabled=false;
declared.lls6g.users.n_users=3;
declared.lls6g.users.execution_model='slot_coupled_truth';
multi=sixgr.truth.resolveMultiUserSpec(declared);
assert(multi.Enabled && multi.NumUsers==3 && multi.RNTIStart==37 && ...
    multi.SeedStride==19 && multi.ExecutionModel=="slot_coupled_truth" && ...
    ~multi.SaveUserTables && multi.BeamSelectionStrategy==spec.BeamSelectionStrategy && ...
    isequal(string(fieldnames(multi)),names));

% Preserve the old compatibility/sentinel contract. Missing policy cannot
% be repaired from userContext, a beam index or the fixture's known policy.
legacy=sixgr.truth.resolveMultiUserSpec(struct());
legacyExpected=struct('Enabled',false,'NumUsers',1,'RNTIStart',1, ...
    'SeedStride',101,'ExecutionModel',"independent_link_sweep", ...
    'BeamSelectionStrategy',"missing_from_config",'SaveUserTables',true);
assert(isequaln(legacy,legacyExpected));
empty=sixgr.truth.resolveMultiUserSpec(struct('lls6g',struct('users',struct())));
assert(isequaln(empty,legacy));
missing=cfg;
missing.lls6g.users=rmfield(missing.lls6g.users,'beam_selection_strategy');
missing.lls6g.userContext=struct('BeamSelectionStrategy',spec.BeamSelectionStrategy, ...
    'BeamIndexSet','0');
sentinel=sixgr.truth.resolveMultiUserSpec(missing);
expectedMissing=spec; expectedMissing.BeamSelectionStrategy="missing_from_config";
assert(isequaln(sentinel,expectedMissing));
for blank=["","   "]
    missing.lls6g.users.beam_selection_strategy=blank;
    assert(isequaln(sixgr.truth.resolveMultiUserSpec(missing),expectedMissing));
end
fprintf('MULTI_USER_SPEC_AUTHORITY_PASS resolved_YAML=1 complete_schema=1 missing_policy_not_invented=1 physical_execution=0\n');
ok=true;
end
