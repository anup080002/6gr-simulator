function ok=testFourPortSharedAWGNScenario()
% Configuration coverage only; full coordinator measurements remain required.
paths={'lls_tdd_four_port_research_pusch_csi_fixture.yaml', ...
    'lls_tdd_5mhz_four_port_shared_awgn_12db.yaml'};
for k=1:numel(paths)
    s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios',paths{k}));
    cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
    carrier=sixgr.phy.grid.makeCarrier(cfg);
    assert(carrier.NSizeGrid==25 && carrier.SubcarrierSpacing==15);
    assert(cfg.antenna.bs.numElements==4 && cfg.antenna.ue.numElements==4);
    assert(cfg.phy.srs.nPorts==4 && cfg.phy.pusch.NumAntennaPorts==4);
    assert(cfg.phy.csirs.nPorts==4 && cfg.phy.pdsch.numPorts==4);
    assert(cfg.channel.sharedIdentityAWGNEnabled && ...
        sixgr.link.resolveAWGNReferenceEnergy(cfg)==.25);
    assert(string(s.get('meta.research_class'))=="optional_research_experiment");
    if k==1
        assert(cfg.channel.snr_dB==30 && cfg.phy.pusch.mcsIndex==4 && ...
            strcmp(cfg.phy.pusch.modulation,'1024QAM'));
    else
        assert(cfg.channel.snr_dB==12 && cfg.phy.pusch.mcsIndex==0 && ...
            strcmp(cfg.phy.pusch.modulation,'QPSK'));
        assert(s.get('initial_access.enabled') && s.get('initial_access.sib1.enabled') && ...
            s.get('random_access.enabled') && s.get('harq.enabled') && ...
            s.get('run_control.total_slots')==58);
    end
end
fprintf('FOUR_PORT_SHARED_AWGN_SCENARIO_PASS config_only=1\n');
ok=true;
end
