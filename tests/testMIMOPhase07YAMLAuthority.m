function ok = testMIMOPhase07YAMLAuthority()
%TESTMIMOPHASE07YAMLAUTHORITY Both operator modes expose one strict MIMO surface.

setup6GRSimToolkit("Verbose",false,"RunToolboxChecks",false);
root = fullfile(pwd,"simulator","configs","scenarios");
names = ["master_sinr_sweep.yaml","master_geometry_based.yaml"];
resolved = cell(numel(names),1);
for index = 1:numel(names)
    scenario = sixgr.lls6g.config.loadScenarioConfig( ...
        fullfile(root,names(index)));
    s = scenario.toStruct();
    assert(isfield(s.mimo,"phase07_strict"), ...
        "%s does not expose mimo.phase07_strict.",names(index));
    phase = s.mimo.phase07_strict;
    required = ["enabled","profile_id","specification_profile","direction", ...
        "codebook_type","ports","panels","n1","n2","o1","o2", ...
        "max_rank","rank_domain","receiver","precoder_prg_size_rbs", ...
        "require_active_tci_state","measurement_max_age_slots", ...
        "covariance","csi_report","ul_srs_authority"];
    assert(all(isfield(phase,required)), ...
        "%s omits a Phase-07 operator field.",names(index));
    cfg = sixgr.lls6g.buildInternalConfig(s,tempdir);
    assert(~logical(cfg.phy.mimo.strict), ...
        "Master profiles must not silently enable unfinished strict campaigns.");
    assert(string(cfg.phy.mimo.profileID)==string(phase.profile_id));
    assert(double(cfg.phy.mimo.ports)==double(phase.ports));
    assert(isfield(cfg.phy.csi,"reportConfiguration"));
    resolved{index} = s;
end

strictScenario = resolved{1};
strictScenario.mimo.n_tx_ant = 2;
strictScenario.mimo.n_rx_ant = 2;
strictScenario.mimo.n_layers = 2;
strictScenario.mimo.max_dl_layers = 2;
strictScenario.reference_signals.pdsch_dmrs_ports = 2;
strictScenario.mimo.phase07_strict.enabled = true;
strictScenario.mimo.phase07_strict.ports = 2;
strictScenario.mimo.phase07_strict.panels = 1;
strictScenario.mimo.phase07_strict.n1 = 1;
strictScenario.mimo.phase07_strict.n2 = 1;
strictScenario.mimo.phase07_strict.o1 = 1;
strictScenario.mimo.phase07_strict.o2 = 1;
strictScenario.mimo.phase07_strict.max_rank = 2;
strictScenario.mimo.phase07_strict.rank_domain = [1 2];
strictScenario.mimo.phase07_strict.csi_report.num_csi_resources = 2;
strictCfg = sixgr.lls6g.buildInternalConfig(strictScenario,tempdir);
assert(logical(strictCfg.phy.mimo.strict));
assert(double(strictCfg.phy.pdsch.numPorts)==2);
assert(~logical(strictCfg.phy.pdsch.normalizePrecodingMatrix));
assert(isequal(double(strictCfg.phy.csi.rankDomain),[1 2]));

bad = strictScenario;
bad.mimo.phase07_strict.ports = 3;
localAssertError(@()sixgr.lls6g.buildInternalConfig(bad,tempdir), ...
    "sixgr:mimo:UnsupportedAntennaTuple");
ok = true;
end

function localAssertError(f,identifier)
try
    f();
catch ME
    assert(strcmp(ME.identifier,identifier), ...
        "Expected %s, received %s.",identifier,ME.identifier);
    return;
end
error("testMIMOPhase07YAMLAuthority:ExpectedFailure", ...
    "Expected %s.",identifier);
end
