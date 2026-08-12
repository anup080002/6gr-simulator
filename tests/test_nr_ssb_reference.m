function test_nr_ssb_reference()
%TEST_NR_SSB_REFERENCE Verify C0 uses the exact NR 20-RB resource map.
[cfg,~]=sixgr.phy.ia.c0.config.loadScenario( ...
    "simulator/configs/initial_access/c0/C0.yaml","smoke");
b=sixgr.phy.ia.c0.waveform.buildNRAnchorA(cfg,"PayloadSeed",9101);
assert(isequal(size(b.SSBGrid),[240 4]));
assert(b.ResourceAudit.PSSRE==127);
assert(b.ResourceAudit.SSSRE==127);
assert(b.ResourceAudit.PBCHRE==432);
assert(b.ResourceAudit.DMRSRE==144);
assert(b.ResourceAudit.ActiveRE==830);
assert(numel(b.BCHCodeword)==864);
fprintf('test_nr_ssb_reference: PASS\n');
end
