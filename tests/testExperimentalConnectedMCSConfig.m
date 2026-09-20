function ok=testExperimentalConnectedMCSConfig()
% YAML authority, explicit classification, fixed codepoint contents and guards.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_four_port_connected_research_ul_fixture.yaml');
raw=s.toStruct(); cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
assert(string(raw.modulation.mcs_table)=="qam64_table1" && ...
    string(cfg.phy.pdsch.mcsTable)=="qam64_table1" && ...
    string(cfg.phy.pusch.mcsTable)=="experimental_square_qam_v1");
for index=0:10
    p=sixgr.phy.pdcch.resolveConnectedMCS(cfg.phy.pusch,index);
    assert(p.Valid && ~p.StandardNR && p.ResearchClass=="optional_research_experiment");
end
p=sixgr.link.resolveMCSProfile(cfg.phy.pusch.mcsTable,4);
assert(p.Qm==10 && p.TargetCodeRate==.5 && string(p.Modulation)=="1024QAM");
p=sixgr.link.resolveMCSProfile(cfg.phy.pusch.mcsTable,10);
assert(p.Qm==10 && p.TargetCodeRate==.9);
bad=raw; bad.meta.research_class='baseline_benchmark';
localReject(@()sixgr.lls6g.config.validateScenarioConfig(bad),'sixgr:research:ExplicitUCIAdapterRequired');
bad=raw; bad=rmfield(bad,'research_pusch_uci');
localReject(@()sixgr.lls6g.config.validateScenarioConfig(bad),'sixgr:research:ExplicitUCIAdapterRequired');
bad=raw; bad.modulation_and_mapping.ul_mcs_table='qam64_table1';
localReject(@()sixgr.lls6g.config.validateScenarioConfig(bad),'sixgr:research:InvalidMCSTable');
bad=cfg; bad.lls6g.resolvedConfig.meta.research_class='baseline_benchmark';
localReject(@()sixgr.config.validateConfig(bad),'sixgr:research:ExplicitUCIAdapterRequired');
bad=cfg; bad.phy.pusch.experimentalMCSTable.Rows(5,3)=.9;
localReject(@()sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(bad,'0_1'), ...
    'sixgr:research:MCSTableContextMismatch');
c=sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(cfg,'0_1');
assert(isequal(c.Data.ExperimentalULMCSTable,cfg.phy.pusch.experimentalMCSTable));
bad=cfg; bad.phy.pusch.researchTransportPolicy.research_pusch_uci.resource_mapping='changed';
c2=sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(bad,'0_1');
assert(c2.Digest~=c.Digest,'Transport policy contents must participate in the received context.');
% Native directional differences must also remain isolated and idempotent.
alias=raw; alias.modulation_and_mapping.ul_mcs_table='qam256_table2';
alias=sixgr.lls6g.config.normalizeScenarioAliases(alias);
again=sixgr.lls6g.config.normalizeScenarioAliases(alias);
assert(string(alias.modulation.mcs_table)=="qam64_table1" && ...
    string(alias.modulation_and_mapping.ul_mcs_table)=="qam256_table2" && ...
    isequaln(alias.modulation,again.modulation) && ...
    isequaln(alias.modulation_and_mapping,again.modulation_and_mapping));
ok=true;
end

function localReject(fn,id)
try, fn(); catch ME, assert(strcmp(ME.identifier,id),'Expected %s, got %s: %s',id,ME.identifier,ME.message); return; end
error('test:MissingRejection','Expected %s.',id);
end
