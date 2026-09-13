function ok=test12dBSameChainSweepConfig()
% Resolve the authored sweep through the same front door as the 12 dB run.
setup6GRSimToolkit('Verbose',false);
root='simulator/configs/scenarios/';
base=sixgr.lls6g.config.loadScenarioConfig( ...
    [root 'lls_causal_access_to_data_wiring_tdd_short_continuous_iq.yaml']);
sweep=sixgr.lls6g.config.loadScenarioConfig( ...
    [root 'lls_causal_access_to_data_wiring_tdd_short_snr_sweep.yaml']);
expected=[-30 -20 -10 0 10 12 20 30 40];
assert(base.get('simulation.snr_db')==12 && sweep.get('simulation.snr_db')==0);
offsets=sweep.get('simulation.snr_sweep_offsets_db');
values=sweep.get('sweeps_and_matrix.snr_sweep.values_db');
assert(isequal(double(offsets(:).'),expected));
assert(isequal(double(values(:).'),expected));
aliases=["canonical_control.run.fixed_link_snr_grid_db", ...
    "sweeps_and_matrix.fixed_link_calibration.snr_db", ...
    "validation.fixed_link_campaign.snr_db"];
for alias=aliases
    values=sweep.get(alias);
    assert(isequal(double(values(:).'),expected),'test:SweepAliasDrift', ...
        'Resolved SNR alias %s differs from the authored points.',alias);
end
% Compare every leaf, including duration/seed/impairments. Allow only run
% identity and the explicitly authored sweep controls (including aliases).
differences=localDifferences(base.Data,sweep.Data,"");
allowed=["canonical_control.launch.sweep_enabled", ...
    "output.profile","scenario.name","scenario.description", ...
    "run.snr_db","run.snr_sweep_offsets_db", ...
    "simulation.snr_db","simulation.snr_sweep_offsets_db", ...
    "sweeps_and_matrix.snr_sweep.enabled", ...
    "sweeps_and_matrix.snr_sweep.values_db", ...
    "sweeps_and_matrix.snr_sweep.state_policy", ...
    "sweeps_and_matrix.snr_sweep.initial_access_state_policy",aliases];
unexpected=differences(~ismember(differences,allowed) & ...
    ~startsWith(differences,"meta.") & ~startsWith(differences,"identity.") & ...
    ~startsWith(differences,"config_inheritance."));
assert(isempty(unexpected),'test:SweepPHYDrift', ...
    'Sweep changed non-sweep configuration: %s.',strjoin(unexpected,", "));
assert(~base.get('canonical_control.launch.sweep_enabled') && ...
    sweep.get('canonical_control.launch.sweep_enabled'));
cfg=sixgr.lls6g.buildInternalConfig(sweep,tempname);
assert(isequal(cfg.run.snrSweepOffsets_dB,expected) && cfg.run.snrSweepEnabled);
assert(string(cfg.run.snrSweepStatePolicy)=="independent_link_state_per_point" && ...
    string(cfg.run.snrSweepInitialAccessStatePolicy)=="independent_per_point");
assert(any(endsWith(strrep(sweep.SourceFiles,'\','/'), ...
    '/lls_causal_access_to_data_wiring_tdd_short_continuous_iq.yaml')));
fprintf('SAME_CHAIN_SWEEP_CONFIG_PASS points=%d permitted_changed_leaves=%d hash=%s\n', ...
    numel(expected),numel(differences),sweep.ConfigHash);
ok=true;
end

function paths=localDifferences(a,b,prefix)
paths=strings(0,1);
if isstruct(a) && isscalar(a) && isstruct(b) && isscalar(b)
    names=union(fieldnames(a),fieldnames(b));
    for k=1:numel(names)
        name=names{k}; path=string(name);
        if strlength(prefix)>0, path=prefix+"."+path; end
        if ~isfield(a,name) && isstruct(b.(name)) && isscalar(b.(name))
            paths=[paths;localDifferences(struct(),b.(name),path)]; %#ok<AGROW>
        elseif ~isfield(b,name) && isstruct(a.(name)) && isscalar(a.(name))
            paths=[paths;localDifferences(a.(name),struct(),path)]; %#ok<AGROW>
        elseif ~isfield(a,name) || ~isfield(b,name)
            paths(end+1,1)=path;
        else
            paths=[paths;localDifferences(a.(name),b.(name),path)]; %#ok<AGROW>
        end
    end
elseif ~isequaln(a,b)
    paths=prefix;
end
end
