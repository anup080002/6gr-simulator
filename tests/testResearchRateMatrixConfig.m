function ok=testResearchRateMatrixConfig()
% Selection configuration must not trade extra power or less noise for rate.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
path=fullfile(pwd,'simulator','configs','scenarios','research_400mhz_rate_matrix.yaml');
matrix=sixgr.lls6g.config.readConfigFile(path);
sixgr.lls6g.config.validateScenarioConfig(matrix,'Kind','matrix');
paths=string(matrix.scenarios(:)); configs=cell(size(paths));
for k=1:numel(paths)
    configs{k}=sixgr.lls6g.config.loadScenarioConfig(fullfile(fileparts(path),paths(k)));
end
sixgr.phy.research.assertComparableRateConfigs(configs);
assert(numel(configs)==4 && matrix.execution.maximum_observed_bler==0);
assert(configs{1}.get('simulation.n_slots')==80);
bad=configs; data=bad{2}.toStruct(); data.simulation.snr_db=data.simulation.snr_db+1;
bad{2}=sixgr.lls6g.config.ScenarioConfig(data);
expectRejection(bad,'sixgr:research:IncomparableRateCandidates');
bad=configs; data=bad{2}.toStruct(); data.research_dl.num_layers=4;
bad{2}=sixgr.lls6g.config.ScenarioConfig(data);
expectRejection(bad,'sixgr:research:IncomparableRateCandidates');
bad=configs; data=bad{2}.toStruct(); data.meta.scenario_id=configs{1}.ScenarioID;
bad{2}=sixgr.lls6g.config.ScenarioConfig(data);
expectRejection(bad,'sixgr:research:DuplicateCandidateID');
bad=configs; data=bad{2}.toStruct(); data.research_link.require_all_tb_success=true;
bad{2}=sixgr.lls6g.config.ScenarioConfig(data);
expectRejection(bad,'sixgr:research:ExplorationPolicyRequired');
ok=true;
fprintf('RESEARCH_RATE_MATRIX_CONFIG_PASS fixed_link_budget=1 waveform_comparison_executed=0\n');
end

function expectRejection(configs,id)
try
    sixgr.phy.research.assertComparableRateConfigs(configs);
    error('test:ExpectedRejection','Invalid comparison was accepted.');
catch ME
    assert(strcmp(ME.identifier,id));
end
end
