function ok=testScenarioInitialMCS28()
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_received_ul_harq_shared_fixture.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
p=sixgr.link.resolveMCSProfile('qam64_table1',28);
assert(p.Valid && cfg.phy.pusch.mcsIndex==28 && ...
    string(cfg.phy.pusch.modulation)=="64QAM" && ...
    abs(cfg.phy.pusch.codeRate-p.TargetCodeRate)<1e-12 && cfg.channel.snr_dB==12);
bad=s.toStruct(); bad.modulation.mcs_table='qam256_table2';
try
    sixgr.lls6g.config.validateScenarioConfig(bad);
catch ME
    assert(strcmp(ME.identifier,'sixgr:lls6g:config:InitialMCSRateRequired'), ...
        'Expected table-specific initial-rate rejection, got %s: %s',ME.identifier,ME.message);
    fprintf('SCENARIO_INITIAL_MCS28_PASS: qam64 row 28 accepted, qam256 reserved row 28 rejected.\n');
    ok=true; return;
end
error('test:MissingRejection','Reserved qam256 row 28 cannot initialize an UL TB.');
end
