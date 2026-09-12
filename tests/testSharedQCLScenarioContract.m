function ok=testSharedQCLScenarioContract()
% Exercise the actual enabled YAML, TCI context and generated TRS resource map.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios', ...
    'lls_causal_access_to_data_wiring_tdd_short_continuous_iq.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
assert(cfg.phy.pdsch.qclTCI.enabled && cfg.phy.pdsch.activeTCIStateID==17 && ...
    cfg.phy.pdsch.qclTCI.codepoint==0);
p=sixgr.link.prepareTRSTransmission(cfg,12);
assert(isequal(unique(p.Tx.ResourceMappingTable.NZPCSIRSResourceID).',[100 101 102 103]) && ...
    size(p.Tx.Waveform,1)>0 && ~p.PowerContext.PAApplied);
grant=struct('RNTI',1,'SymbolAllocation',double(cfg.phy.pdsch.symbolAllocation));
[context,~]=sixgr.phy.pdcch.DCIContextFactory.fromScheduledGrant(cfg,grant,'1_1');
assert(context.Data.TCIPresent && context.Data.TCIWidth==3 && ...
    context.Data.ConfigurationEpoch==cfg.phy.pdsch.qclTCI.configuration_epoch);
ok=true;
fprintf('PASS testSharedQCLScenarioContract\n');
end
