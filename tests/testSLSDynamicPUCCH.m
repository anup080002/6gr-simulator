function ok=testSLSDynamicPUCCH()
s=sixgr.lls6g.config.loadScenarioConfig('simulator/configs/scenarios/lls_causal_access_to_data_wiring_tdd_short_continuous_iq.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
cfg=sixgr.util.mergeStruct(cfg,sixgr.lls6g.config.readConfigFile('simulator/configs/system/calibrated_link_abstraction.yaml'));
cfg.phy.pucch.uciOnPUSCHEnabled=false;
cfg.phy.csi.reportCSI=false; cfg.system.linkAbstraction.dynamicPUCCH.enabled=true;
ledger=sixgr.system.SLSDynamicPUCCH(cfg);
% Empty HARQ still reserves independently configured SR occasions.
seen=0;
for slot=0:19
    o=ledger.snapshot(slot,slot,1,struct([]));
    if isempty(o), continue; end
    assert(all([o.HARQBits]==0) && all([o.SRBits]==1));
    assert(all(string({o.EvidenceKind})=="scheduled_receive_obligation"));
    partition=sixgr.util.resolveTDDSlotPartition(cfg,slot);
    budget=struct('PRBSet',0:cfg.phy.carrier.NSizeGrid-1,'SymbolAllocation',partition.ULSymbolAllocation);
    r=sixgr.system.resolveSLSResourceReservations(cfg,slot+1,"UL",budget, ...
        struct('CellID',1,'AsOfAbsoluteSlot0',slot,'PUCCHObligationsComplete',true,'Obligations',o));
    assert(any(r.ReservedPRBSymbolMask,'all') && ~any(r.Evidence.PhysicalTransmissionProven));
    ledger.completeSlot(slot,1,struct([]),{},struct([]));
    assert(height(ledger.CompletionTrace)==seen+numel(o) && ~any(ledger.CompletionTrace.WaveformBacked));
    rejected=false;
    try, ledger.completeSlot(slot,1,struct([]),{},struct([]));
    catch ME, assert(strcmp(ME.identifier,'sixgr:system:SLSUCIDuplicateCompletion')); rejected=true; end
    assert(rejected,'A repeated completion must not deliver feedback twice.');
    seen=seen+numel(o);
end
assert(seen>0);
fprintf('SLS_DYNAMIC_PUCCH_SR_RESERVATION_PASS occasions=%d\n',seen); ok=true;
end
