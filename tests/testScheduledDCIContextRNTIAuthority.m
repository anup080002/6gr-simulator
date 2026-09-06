function ok = testScheduledDCIContextRNTIAuthority()
% RRC/DCI schema unit test only; no scenario waveform execution.
setup6GRSimToolkit('Verbose',false);
s = sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios', ...
    'webgui_sinr_sweep_64x4_mu_mimo_repair_slice.yaml'));
cfg = sixgr.lls6g.buildInternalConfig(s,tempname);
before = cfg.phy.pdcch.operatorControl;
base = sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(cfg,'1_1');
grant = struct('Direction','DL','SymbolAllocation',cfg.phy.pdsch.symbolAllocation);
identities = [1 2 32767];
digests = strings(size(identities));
for k = 1:numel(identities)
    grant.RNTI = identities(k);
    [context,~] = sixgr.phy.pdcch.DCIContextFactory.fromScheduledGrant(cfg,grant,'1_1');
    assert(context.Data.RNTIValue == grant.RNTI);
    expected = base.Data; expected.RNTIValue = grant.RNTI;
    assert(isequaln(context.Data,expected),'Only the per-UE RNTI binding may change.');
    digests(k) = context.Digest;
end
assert(numel(unique(digests)) == numel(identities));
assert(isequaln(cfg.phy.pdcch.operatorControl,before),'Per-UE binding mutated the shared RRC context.');
for value = {[],NaN,1.5,[1 2],-1,65536}
    grant.RNTI = value{1};
    try
        sixgr.phy.pdcch.DCIContextFactory.fromScheduledGrant(cfg,grant,'1_1');
    catch cause
        assert(strcmp(cause.identifier,'sixgr:phy:pdcch:missing_dci_context'));
        continue;
    end
    error('TEST:MissingRejection','Invalid scheduled RNTI was accepted.');
end
ok = true;
disp('PASS testScheduledDCIContextRNTIAuthority: per-UE binding, preserved RRC layout, no template mutation.');
end
