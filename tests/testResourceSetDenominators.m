function ok=testResourceSetDenominators()
setup6GRSimToolkit('Verbose',false);
% Audited gross/data/no-data fixture. DMRS pilots occupy half the reserved
% DMRS symbols; zero-power CDM positions are not occupied pilot RE.
a=struct('PRBCount',126,'SymbolAllocation',[0 12]);
a.Indices=struct('DataBase',(1:13356).', ...
    'DMRSBase',(13357:15624).','PTRSBase',(15625:15876).', ...
    'ReservedBase',zeros(0,1));
s=sixgr.phy.resource.summarizeResourceSets(a);
assert(s.GrossAllocationRE==18144 && s.MappedDataBaseRE==13356);
assert(s.NonDataBaseRE==4536+252 && abs(s.NonDataOverGrossFraction-19/72)<1e-14);
assert(s.PilotOccupiedBaseRE==2520 && s.UnoccupiedByThisChannelRE==2268);
assert(abs(s.PilotOverDataPlusPilotFraction-2520/15876)<1e-14);
% Duplicated port mappings and overlapping reservation sets must not add RE.
b=a; b.Indices.DMRSBase=repmat(a.Indices.DMRSBase,4,1);
b.Indices.ReservedBase=[a.Indices.DMRSBase;(15877:18144).'];
t=sixgr.phy.resource.summarizeResourceSets(b);
assert(t.PilotOccupiedBaseRE==s.PilotOccupiedBaseRE && ...
    t.NonDataBaseRE==s.NonDataBaseRE && t.ExplicitReservedBaseRE==4536);
% TP maps include punctured PT-RS rows; they are not counted as coded data.
b=a; b.Indices.DataBase=[a.Indices.DataBase;a.Indices.PTRSBase];
t=sixgr.phy.resource.summarizeResourceSets(b);
assert(t.MappedDataBaseRE==13356 && t.NonDataBaseRE==s.NonDataBaseRE);
carrier=nrCarrierConfig('NSizeGrid',25);
for channel=["PDSCH","PUSCH"]
    if channel=="PDSCH", cfg=nrPDSCHConfig; else, cfg=nrPUSCHConfig; end
    cfg.PRBSet=0:24; cfg.SymbolAllocation=[0 14]; cfg.NumLayers=2;
    if channel=="PDSCH"
        [~,info]=sixgr.phy.grid.allocREsPDSCH(carrier,cfg);
    else
        [~,info]=sixgr.phy.grid.allocREsPUSCH(carrier,cfg);
    end
    acct=info.ResourceAccounting; s=acct.ResourceSetSummary;
    assert(s.GrossAllocationRE==25*12*14 && ...
        s.MappedDataBaseRE==nnz(acct.Masks.Data) && ...
        s.PilotOccupiedBaseRE==nnz(acct.Masks.DMRS|acct.Masks.PTRS));
    metrics=sixgr.link.deriveModulationTrackingMetrics( ...
        struct('ResourceAccounting',acct),struct(),struct(),channel);
    exported=sixgr.link.modulationDiagnosticsExport(metrics);
    assert(exported.GrossAllocationRE==s.GrossAllocationRE && ...
        exported.NonDataOverGrossFraction==s.NonDataOverGrossFraction);
end
unknown=sixgr.phy.resource.summarizeResourceSets(struct());
assert(isnan(unknown.GrossAllocationRE));
ok=true;
end
